export const meta = {
  name: 'deliver',
  description: 'Run each unit of an autopilot plan through engineer, review, persona QA and verification until clean, then open a ready PR',
  whenToUse: 'Started by /autopilot:run with the run directory; not run by hand',
  phases: [
    { title: 'Design', detail: 'engineer proposes, staff reviewer picks' },
    { title: 'Build', detail: 'engineer builds and fixes in the unit worktree' },
    { title: 'Review', detail: 'code-review gates plus lens reviewers, skeptics, triage' },
    { title: 'QA', detail: 'personas drive the running app; verifier confirms' },
    { title: 'Ship', detail: 'staff final gate, push, ready PR, CI' },
  ],
}

const A = args
const CFG = A.config
const LIMITS = CFG.limits
const WORKERS = CFG.models.workers
const STAFF = CFG.models.staff
const SCRIPTS = `${A.plugin_root}/scripts`
const CONFIG_PATH = `${A.run_dir}/config.json`
const LENSES = ['security', 'data', 'compatibility', 'concurrency', 'accessibility', 'observability', 'plan-fit',
  'type-safety', 'error-handling', 'performance', 'dependencies']

// ---------- schemas ----------
const str = { type: 'string' }
const strs = { type: 'array', items: str }
const OPS = { type: 'object', required: ['exit_code', 'output'], properties: { exit_code: { type: 'number' }, output: str } }
const ENGINEER = {
  type: 'object', required: ['status', 'summary'],
  properties: {
    status: { type: 'string', enum: ['proposal', 'done', 'plan-conflict', 'risky'] },
    approaches: { type: 'array', items: { type: 'object', required: ['summary', 'tradeoffs'], properties: { summary: str, files: strs, tradeoffs: str } } },
    recommendation: str, summary: str, commits: strs, notes: str,
  },
}
const DESIGN = {
  type: 'object', required: ['verdict', 'rationale', 'direction'],
  properties: { verdict: { type: 'string', enum: ['pick', 'rework'] }, approach_index: { type: 'number' }, rationale: str, direction: str },
}
const FINAL = {
  type: 'object', required: ['verdict', 'rationale'],
  properties: { verdict: { type: 'string', enum: ['approve', 'rework'] }, rationale: str, direction: str },
}
const FINDING = { type: 'object', required: ['location', 'scenario', 'severity'], properties: { location: str, scenario: str, consequence: str, severity: str, lens: str } }
const FINDINGS = { type: 'object', required: ['findings'], properties: { findings: { type: 'array', items: FINDING }, skipped: str } }
const GATES = { type: 'object', required: ['passed', 'fails'], properties: { passed: { type: 'boolean' }, fails: { type: 'array', items: FINDING } } }
const REFUTE = { type: 'object', required: ['refuted', 'reason'], properties: { refuted: { type: 'boolean' }, reason: str } }
const TRIAGE = {
  type: 'object', required: ['fix', 'dismiss'],
  properties: { fix: { type: 'array', items: { type: 'object', required: ['finding', 'reason'], properties: { finding: str, reason: str } } },
    dismiss: { type: 'array', items: { type: 'object', required: ['finding', 'reason'], properties: { finding: str, reason: str } } } },
}
const QA = {
  type: 'object', required: ['bugs', 'covered'],
  properties: { bugs: { type: 'array', items: { type: 'object', required: ['title', 'steps', 'expected', 'actual', 'evidence', 'script', 'severity'],
    properties: { title: str, steps: strs, expected: str, actual: str, evidence: str, script: str, severity: str } } }, covered: strs, not_covered: strs },
}
const VERDICT = {
  type: 'object', required: ['criteria', 'confirmed', 'dropped'],
  properties: {
    criteria: { type: 'array', items: { type: 'object', required: ['id', 'passes', 'evidence'], properties: { id: str, passes: { type: 'boolean' }, evidence: str } } },
    confirmed: { type: 'array', items: { type: 'object', required: ['title', 'steps', 'evidence'], properties: { title: str, steps: strs, evidence: str, persona: str } } },
    dropped: { type: 'array', items: { type: 'object', required: ['title', 'reason'], properties: { title: str, reason: str } } },
  },
}
const SHIP = { type: 'object', required: ['ci'], properties: { pr_url: { type: ['string', 'null'] }, stack: str, ci: { type: 'string', enum: ['pass', 'fail', 'none', 'skipped'] }, failures: str, notes: str } }

// ---------- one unit ----------
class Stop extends Error { constructor(status, reason) { super(reason); this.status = status } }

const NOT_CHECKED = 'not checked by verifier'

// Bundled scripts print one JSON line last; ops returns stdout and stderr together.
function lastLineJson(label, output) {
  try { return JSON.parse(output.trim().split('\n').pop()) }
  catch { throw new Stop('failed', `${label} printed no JSON: ${output}`) }
}

// parallel() turns a throwing thunk into null, which would let a stage that
// died (budget spent, an agent that never ran) read as clean. settle() keeps
// each thunk's error and rethrows it, preferring blocked:budget.
async function settle(thunks) {
  const out = await parallel(thunks.map(thunk => async () => {
    try { return { value: await thunk() } } catch (error) { return { error } }
  }))
  const errors = out.map(o => (o ? o.error : new Stop('failed', 'a parallel task vanished'))).filter(Boolean)
  if (errors.length) throw errors.find(e => e.status === 'blocked:budget') || errors[0]
  return out.map(o => o.value)
}

// Progress survives a Stop, so the report can show blocked units' rounds and decisions.
async function deliverUnit(unit, baseBranch, parentPr) {
  const progress = { agents: 0, rounds: 0, decisions: [], branch: null, worktree: null }
  try { return await runUnit(unit, baseBranch, progress, parentPr) }
  catch (error) { error.progress = progress; throw error }
}

async function runUnit(unit, baseBranch, progress, parentPr) {
  const tag = unit.id
  const decisions = progress.decisions
  const note = (step, outcome, reason) => { decisions.push({ step, outcome, reason }); log(`${tag} ${step}: ${outcome}`) }
  // Cleanup (stopping the app) is exempt from the budget so a spent budget never leaves an app running.
  const call = async (prompt, opts, { cleanup = false } = {}) => {
    if (!cleanup && progress.agents >= LIMITS.max_agents_per_unit) throw new Stop('blocked:budget', `reached ${LIMITS.max_agents_per_unit} agent calls`)
    progress.agents += 1
    return agent(prompt, opts)
  }
  const ops = async (label, command, cwd, flags) => {
    const out = await call(`Run from ${cwd}:\n${command}\nScripts directory: ${SCRIPTS}`,
      { agentType: 'autopilot:ops', model: WORKERS, effort: 'low', schema: OPS, label: `${tag} ${label}`, phase: 'Build' }, flags)
    if (!out) throw new Stop('failed', `ops ${label} returned nothing`)
    return out
  }
  // One retry for an agent that returned nothing; the caller decides what a second null means.
  const retryOnce = async (what, ask) => {
    const out = await ask(what)
    if (out) return out
    note(what, 'null', 'returned nothing; retrying once')
    return ask(`${what} retry`)
  }

  const personas = unit.contract.personas
  if (personas.length < LIMITS.qa_personas.min) throw new Stop('failed', `contract has ${personas.length} personas; qa_personas.min is ${LIMITS.qa_personas.min}`)

  const wt = await ops('worktree', `bash ${SCRIPTS}/worktree.sh create ${A.repo} ${A.run_id} ${unit.id} ${baseBranch}`, A.repo)
  if (wt.exit_code !== 0) throw new Stop('failed', `worktree: ${wt.output}`)
  const { path: worktree, branch } = lastLineJson('worktree', wt.output)
  progress.worktree = worktree
  progress.branch = branch
  const state = `${A.run_dir}/${unit.id}`
  const context = [
    `Worktree: ${worktree}`, `Branch: ${branch} (base ${baseBranch})`,
    `Plan: ${A.plan.title}. Goal: ${A.plan.goal}`, `Out of scope: ${A.plan.out_of_scope}`,
    `Cross-unit architecture (decided by the staff engineer): ${A.architecture}`,
    `Unit ${unit.id}: ${unit.title}. Scope: ${unit.scope}`,
    `Contract: ${JSON.stringify(unit.contract.criteria)}`,
    `Checks command: bash ${SCRIPTS}/run-checks.sh ${CONFIG_PATH} ${worktree}`,
    `Scripts directory: ${SCRIPTS}`,
  ].join('\n')
  const ctx = { unit, tag, worktree, baseBranch, state, context, call, ops, note, retryOnce }
  const engineer = async (mode, extra) => {
    const out = await call(`Mode: ${mode}\n${context}\n${extra || ''}`, { agentType: 'autopilot:engineer', model: WORKERS, schema: ENGINEER, label: `${tag} engineer ${mode}`, phase: mode === 'propose' ? 'Design' : 'Build' })
    if (!out) throw new Stop('failed', `engineer ${mode} returned nothing`)
    if (out.status === 'plan-conflict') throw new Stop('blocked:plan-conflict', out.notes || out.summary)
    if (out.status === 'risky') throw new Stop('blocked:risky', out.notes || out.summary)
    return out
  }

  // Design gate: engineer proposes, staff picks; one rework allowed. A proposal
  // with no approaches, or a pick of an approach that was not proposed, is a rework.
  let decision = null
  let direction = ''
  for (let attempt = 1; attempt <= 2 && !decision; attempt += 1) {
    const proposal = await engineer('propose', direction && `Staff direction for this proposal: ${direction}`)
    const approaches = proposal.approaches || []
    if (!approaches.length) {
      direction = 'Propose 2-3 genuinely different approaches; the last proposal had none.'
      note('design gate', 'rework', 'engineer returned no approaches')
      continue
    }
    const verdict = await call(`Design gate.\n${context}\nApproaches: ${JSON.stringify(approaches)}\nEngineer recommends: ${proposal.recommendation}`,
      { agentType: 'autopilot:staff-reviewer', model: STAFF, schema: DESIGN, label: `${tag} design gate ${attempt}`, phase: 'Design' })
    const picked = verdict && verdict.verdict === 'pick' ? approaches[verdict.approach_index] : undefined
    if (picked) {
      decision = { approach: picked, rationale: verdict.rationale, direction: verdict.direction }
      note('design gate', `approach ${verdict.approach_index}`, verdict.rationale)
    } else {
      direction = !verdict ? 'no verdict returned'
        : verdict.verdict === 'pick' ? `${verdict.direction} (staff picked approach ${verdict.approach_index}, which was not proposed)`
        : verdict.direction
      note('design gate', 'rework', direction)
    }
  }
  if (!decision) throw new Stop('blocked:no-approach', direction)

  await engineer('build', `Approach: ${JSON.stringify(decision.approach)}\nStaff direction: ${decision.direction}`)

  let pending = null
  let reviewLog = { fixed: [], dismissed: [] }
  const qaLog = Object.fromEntries(personas.map(p => [p.name, { persona: p.name, confirmed: [], evidence: [] }]))
  let criteria = []
  let finalRationale = ''
  let prUrl = null
  const nextRound = (kind, items) => {
    progress.rounds += 1
    note(`round ${progress.rounds}`, kind, items.slice(0, 3).join('; '))
    if (progress.rounds > LIMITS.max_fix_rounds) throw new Stop('blocked:no-converge', `still failing after ${LIMITS.max_fix_rounds} rounds: ${kind}: ${items.join('; ')}`)
    pending = { kind, items }
  }

  while (true) {
    if (pending) await engineer('fix', `Fix these (${pending.kind}):\n- ${pending.items.join('\n- ')}`)
    pending = null

    const checks = await ops('checks', `bash ${SCRIPTS}/run-checks.sh ${CONFIG_PATH} ${worktree}`, worktree)
    if (checks.exit_code !== 0) { nextRound('checks', [checks.output]); continue }

    const review = await reviewStage(ctx)
    if (review.rework) { nextRound('review', review.rework); continue }
    reviewLog.fixed.push(...review.fix.map(f => f.finding))
    reviewLog.dismissed.push(...review.dismiss)
    if (review.fix.length) { nextRound('review', review.fix.map(f => `${f.finding} (${f.reason})`)); continue }

    const verdict = await qaStage(ctx)
    criteria = contractResults(unit, verdict.criteria)
    // Bugs confirmed in any round are what QA caught; the last round is clean by definition.
    for (const bug of verdict.confirmed) {
      const persona = bug.persona || 'unattributed'
      const entry = qaLog[persona] || (qaLog[persona] = { persona, confirmed: [], evidence: [] })
      entry.confirmed.push(bug.title)
      entry.evidence.push(bug.evidence)
    }
    const failing = criteria.filter(c => !c.passes).map(c => (c.evidence === NOT_CHECKED ? `${c.id} ${NOT_CHECKED}` : `${c.id} fails: ${c.evidence}`))
    const bugs = verdict.confirmed.map(b => `${b.title}: ${b.steps.join(' → ')} (evidence ${b.evidence})`)
    if (failing.length || bugs.length) { nextRound('qa', [...failing, ...bugs]); continue }

    const final = await call(`Final gate.\n${context}\nGet the diff with: git -C ${worktree} diff ${baseBranch}...HEAD\nContract results: ${JSON.stringify(criteria)}\nDecision log: ${JSON.stringify(decisions)}`,
      { agentType: 'autopilot:staff-reviewer', model: STAFF, schema: FINAL, label: `${tag} final gate`, phase: 'Ship' })
    if (!final || final.verdict !== 'approve') { nextRound('staff', [final ? final.direction : 'final gate returned nothing']); continue }
    finalRationale = final.rationale
    note('final gate', 'approve', final.rationale)

    const result = unitResult(unit, progress.rounds, criteria, decision.rationale, finalRationale, reviewLog, Object.values(qaLog), decisions)
    const ship = await call(`Worktree: ${worktree}\nBranch: ${branch}\nBase: ${baseBranch}\nTitle: ${A.plan.title}: ${unit.title}\nScratch: ${state}\nScripts directory: ${SCRIPTS}\ndry_run: ${A.dry_run}\nparent_pr: ${parentPr || 'none'}\nUnit result JSON:\n${JSON.stringify(result)}`,
      { agentType: 'autopilot:shipper', model: WORKERS, schema: SHIP, label: `${tag} ship`, phase: 'Ship' })
    if (!ship) throw new Stop('failed', 'shipper returned nothing')
    prUrl = ship.pr_url
    progress.pr_url = prUrl // a unit blocked later by CI still reports its open PR
    // Only a dry run may finish without a PR or without CI having run.
    if (!A.dry_run && (!prUrl || ship.ci === 'skipped')) throw new Stop('failed', `shipper opened no PR or skipped CI: ${ship.notes || 'no notes'}`)
    // CI that never finished is infrastructure, not something an engineer round can fix.
    if (ship.ci === 'fail' && (ship.failures || '').startsWith('CI did not finish')) throw new Stop('failed', ship.failures)
    if (ship.ci === 'fail') { nextRound('ci', [ship.failures || 'CI failed']); continue }
    note('ship', ship.ci, `${prUrl || 'dry run'}; stack ${ship.stack || 'none'}`)
    return { id: unit.id, status: 'done', pr_url: prUrl, stack: ship.stack || 'none', reason: '', result, ...progress }
  }
}

// Every contract criterion needs the verifier's own entry with passes === true;
// one the verifier left out fails as "not checked by verifier".
function contractResults(unit, checked) {
  const byId = Object.fromEntries(checked.map(c => [c.id, c]))
  return unit.contract.criteria.map(({ id, statement }) => (byId[id]
    ? { id, statement, passes: byId[id].passes === true, evidence: byId[id].evidence }
    : { id, statement, passes: false, evidence: NOT_CHECKED }))
}

// ---------- review: code-review gates + lenses, skeptics, triage ----------
// Returns {fix, dismiss} from triage, or {rework} when the gate verdict must go
// straight back to the engineer without triage.
async function reviewStage({ tag, worktree, baseBranch, context, call, note, retryOnce }) {
  const gates = async () => {
    const out = await retryOnce('code-review gates', label => call(
      `Invoke the code-review:review-code skill on the current HEAD of the repo at ${worktree} against base ${baseBranch}, and run it to completion including its verification gate. Return passed (true only if the overall verdict is PASSED) and fails: one entry per FAIL box with location (file:line), scenario (the box id and evidence), severity "major".`,
      { model: WORKERS, schema: GATES, label: `${tag} ${label}`, phase: 'Review' }))
    if (!out) throw new Stop('failed', 'code-review gates did not run')
    return out
  }
  const lenses = [...LENSES.map(lens => ({ lens, agentType: 'autopilot:lens-reviewer' })),
    ...CFG.review.extra_agents.map(type => ({ lens: type, agentType: type }))]
  const lensUntilDry = async ({ lens, agentType }) => {
    const found = []
    for (let round = 1; round <= 3; round += 1) {
      const out = await retryOnce(`lens ${lens} r${round}`, label => call(
        `Lens: ${lens}\n${context}\nBase: ${baseBranch}\nAlready reported (do not repeat): ${JSON.stringify(found.map(f => f.location + ' ' + f.scenario))}`,
        { agentType, model: WORKERS, schema: FINDINGS, label: `${tag} ${label}`, phase: 'Review' }))
      if (!out) throw new Stop('failed', `lens ${lens} did not run`)
      if (out.skipped) note(`lens ${lens}`, 'skipped', out.skipped)
      const fresh = out.findings.filter(f => f.location && f.scenario)
      if (!fresh.length) break
      found.push(...fresh.map(f => ({ ...f, lens })))
    }
    return found
  }
  const [gateResult, ...lensResults] = await settle([gates, ...lenses.map(l => () => lensUntilDry(l))])
  if (!gateResult.passed && !gateResult.fails.length) return { rework: ['code-review reported FAILED without box details'] }
  const lensFindings = lensResults.flat()

  // Skeptics guard against plausible-but-wrong serious findings; minor ones go straight to triage.
  const serious = f => f.severity === 'blocker' || f.severity === 'major'
  const survives = async finding => {
    const votes = await settle([1, 2].map(n => () => call(
      `Try to refute this review finding. Read the code at ${worktree}. Return refuted=false only if you confirm the scenario really breaks; otherwise refuted=true with the reason.\nFinding: ${JSON.stringify(finding)}`,
      { model: WORKERS, schema: REFUTE, label: `${tag} skeptic ${n} ${finding.location}`, phase: 'Review' })))
    if (votes.some(v => !v)) note(`skeptic ${finding.location}`, 'null', 'a skeptic returned nothing; counted as not refuted')
    return votes.filter(v => v && v.refuted).length < 2 ? finding : null
  }
  const judged = await settle(lensFindings.filter(serious).map(f => () => survives(f)))
  const kept = [...judged.filter(Boolean), ...lensFindings.filter(f => !serious(f))]
  if (!gateResult.fails.length && !kept.length) return { fix: [], dismiss: [] }

  const triage = await call(`Triage these findings for ${worktree}.\nGate FAILs: ${JSON.stringify(gateResult.fails)}\nLens findings: ${JSON.stringify(kept)}`,
    { agentType: 'autopilot:triage', model: WORKERS, schema: TRIAGE, label: `${tag} triage`, phase: 'Review' })
  return triage || { fix: [...gateResult.fails, ...kept].map(f => ({ finding: `${f.location} ${f.scenario}`, reason: 'triage returned nothing' })), dismiss: [] }
}

// ---------- QA: boot, personas in parallel, verifier, stop ----------
async function qaStage({ unit, tag, worktree, state, context, call, ops, note }) {
  const personas = unit.contract.personas
  try {
    const boot = await ops('boot app', `bash ${SCRIPTS}/boot-app.sh ${CONFIG_PATH} ${worktree} ${unit.index} ${state}`, worktree)
    if (boot.exit_code !== 0) throw new Stop('failed', `app did not boot: ${boot.output}`)
    const { url } = lastLineJson('boot app', boot.output)
    const login = CFG.launch.login ? `Login: ${JSON.stringify(CFG.launch.login)} (credentials are in those env vars)` : 'No login needed.'
    const reports = await settle(personas.map((persona, n) => () => call(
      `Persona: ${JSON.stringify(persona)}\nApp: ${url}\n${login}\nEvidence directory: ${state}/qa/${n}\n${context}`,
      { agentType: 'autopilot:qa-persona', model: WORKERS, schema: QA, label: `${tag} qa ${persona.name}`, phase: 'QA' })))
    reports.forEach((r, n) => { if (!r) note(`qa ${personas[n].name}`, 'null', 'persona returned nothing') })
    const reported = reports.filter(Boolean).length
    if (reported < LIMITS.qa_personas.min) throw new Stop('failed', `only ${reported} personas reported`)
    const qa = reports.map((r, n) => ({ persona: personas[n].name, bugs: r ? r.bugs : [], not_covered: r ? (r.not_covered || []) : ['agent returned nothing'] }))
    const verdict = await call(`App: ${url}\n${login}\nEvidence directory: ${state}/verify\n${context}\nContract with checks: ${JSON.stringify(unit.contract.criteria)}\nQA reports: ${JSON.stringify(qa)}`,
      { agentType: 'autopilot:verifier', model: WORKERS, schema: VERDICT, label: `${tag} verifier`, phase: 'QA' })
    if (!verdict) {
      note('verifier', 'null', 'returned nothing')
      throw new Stop('failed', 'verifier returned nothing')
    }
    return verdict
  } finally {
    try {
      const stopped = await ops('stop app', `bash ${SCRIPTS}/stop-app.sh ${state} ${unit.index}`, worktree, { cleanup: true })
      if (stopped.exit_code !== 0) note('stop app', `exit ${stopped.exit_code}`, stopped.output)
    } catch (error) { note('stop app', 'failed', error.message) }
  }
}

function unitResult(unit, rounds, criteria, design, final, review, qa, decisions) {
  return {
    plan_title: A.plan.title, unit: { id: unit.id, title: unit.title }, rounds,
    criteria: criteria.map(({ id, statement, passes, evidence }) => ({ id, statement, passes, evidence })),
    staff: { design, final }, review, qa, decisions,
  }
}

// ---------- run: dependency waves ----------
const UNITS = Object.fromEntries(A.units.map(u => [u.id, u]))
const ancestors = id => {
  const seen = new Set()
  const visit = d => { if (seen.has(d)) return; seen.add(d); (UNITS[d] ? UNITS[d].depends_on : []).forEach(visit) }
  ;(UNITS[id] ? UNITS[id].depends_on : []).forEach(visit)
  return seen
}
// Stacks are linear: a unit stacks on the dependency that transitively depends
// on all its other dependencies; with none, the plan is in conflict.
function stackParent(u) {
  if (!u.depends_on.length) return { parent: null }
  const covering = u.depends_on.find(d => u.depends_on.every(o => o === d || ancestors(d).has(o)))
  if (covering) return { parent: covering }
  for (const [i, a] of u.depends_on.entries()) {
    for (const b of u.depends_on.slice(i + 1)) {
      if (!ancestors(a).has(b) && !ancestors(b).has(a)) return { conflict: `depends on independent units ${a} and ${b}; make one depend on the other` }
    }
  }
  return { conflict: `no dependency of ${u.id} covers the others` }
}

const results = {}
const pendingUnits = [...A.units]
const notStarted = (u, status, reason) => ({ id: u.id, status, reason, rounds: 0, agents: 0, pr_url: null })
while (pendingUnits.length) {
  const ready = pendingUnits.filter(u => u.depends_on.every(d => results[d]))
  if (!ready.length) break
  for (const u of ready) pendingUnits.splice(pendingUnits.indexOf(u), 1)
  const runnable = []
  for (const u of ready) {
    const stack = stackParent(u)
    const blockedDep = u.depends_on.find(d => results[d].status !== 'done')
    if (stack.conflict) results[u.id] = notStarted(u, 'blocked:plan-conflict', stack.conflict)
    else if (blockedDep) results[u.id] = notStarted(u, 'skipped', `depends on ${blockedDep} (${results[blockedDep].status})`)
    else runnable.push({ unit: u, parent: stack.parent && results[stack.parent] })
  }
  for (let i = 0; i < runnable.length; i += LIMITS.max_parallel_units) {
    const wave = runnable.slice(i, i + LIMITS.max_parallel_units)
    const done = await parallel(wave.map(({ unit: u, parent }) => async () => {
      try { return await deliverUnit(u, parent ? parent.branch : A.base_branch, parent && parent.pr_url) }
      catch (error) {
        const status = error instanceof Stop ? error.status : 'failed'
        log(`${u.id} ${status}: ${error.message}`)
        return { id: u.id, status, reason: error.message, pr_url: null, ...(error.progress || { rounds: 0, agents: 0, decisions: [] }) }
      }
    }))
    done.forEach((r, n) => { results[wave[n].unit.id] = r || notStarted(wave[n].unit, 'failed', 'unit returned nothing') })
  }
}
return { units: A.units.map(u => results[u.id] || notStarted(u, 'skipped', 'dependency never ran')) }
