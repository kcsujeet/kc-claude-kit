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

// Bundled scripts print one JSON line last; ops returns stdout and stderr together.
function lastLineJson(label, output) {
  try { return JSON.parse(output.trim().split('\n').pop()) }
  catch { throw new Stop('failed', `${label} printed no JSON: ${output}`) }
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
  const call = async (prompt, opts) => {
    // Checked before counting, so `agents` is the number of calls actually made.
    if (progress.agents >= LIMITS.max_agents_per_unit) throw new Stop('blocked:budget', `reached ${LIMITS.max_agents_per_unit} agent calls`)
    progress.agents += 1
    return agent(prompt, opts)
  }
  const ops = async (label, command, cwd) => {
    const out = await call(`Run from ${cwd}:\n${command}\nScripts directory: ${SCRIPTS}`, { agentType: 'autopilot:ops', model: WORKERS, effort: 'low', schema: OPS, label: `${tag} ${label}`, phase: 'Build' })
    if (!out) throw new Stop('failed', `ops ${label} returned nothing`)
    return out
  }

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
  const engineer = async (mode, extra) => {
    const out = await call(`Mode: ${mode}\n${context}\n${extra || ''}`, { agentType: 'autopilot:engineer', model: WORKERS, schema: ENGINEER, label: `${tag} engineer ${mode}`, phase: mode === 'propose' ? 'Design' : 'Build' })
    if (!out) throw new Stop('failed', `engineer ${mode} returned nothing`)
    if (out.status === 'plan-conflict') throw new Stop('blocked:plan-conflict', out.notes || out.summary)
    if (out.status === 'risky') throw new Stop('blocked:risky', out.notes || out.summary)
    return out
  }

  // Design gate: engineer proposes, staff picks; one rework allowed.
  let decision = null
  let direction = ''
  for (let attempt = 1; attempt <= 2 && !decision; attempt += 1) {
    const proposal = await engineer('propose', direction && `Staff direction for this proposal: ${direction}`)
    const verdict = await call(`Design gate.\n${context}\nApproaches: ${JSON.stringify(proposal.approaches)}\nEngineer recommends: ${proposal.recommendation}`,
      { agentType: 'autopilot:staff-reviewer', model: STAFF, schema: DESIGN, label: `${tag} design gate ${attempt}`, phase: 'Design' })
    if (verdict && verdict.verdict === 'pick') {
      decision = { approach: proposal.approaches[verdict.approach_index] || proposal.approaches[0], rationale: verdict.rationale, direction: verdict.direction }
      note('design gate', `approach ${verdict.approach_index}`, verdict.rationale)
    } else {
      direction = verdict ? verdict.direction : 'no verdict returned'
      note('design gate', 'rework', direction)
    }
  }
  if (!decision) throw new Stop('blocked:no-approach', direction)

  await engineer('build', `Approach: ${JSON.stringify(decision.approach)}\nStaff direction: ${decision.direction}`)

  let pending = null
  let reviewLog = { fixed: [], dismissed: [] }
  const qaLog = Object.fromEntries(unit.contract.personas.map(p => [p.name, { persona: p.name, confirmed: [], evidence: [] }]))
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

    const review = await reviewStage(unit, worktree, baseBranch, context, call)
    reviewLog.fixed.push(...review.fix.map(f => f.finding))
    reviewLog.dismissed.push(...review.dismiss)
    if (review.fix.length) { nextRound('review', review.fix.map(f => `${f.finding} (${f.reason})`)); continue }

    const verdict = await qaStage(unit, worktree, state, context, call, ops)
    criteria = verdict.criteria
    // Bugs confirmed in any round are what QA caught; the last round is clean by definition.
    for (const bug of verdict.confirmed) {
      const persona = bug.persona || 'unattributed'
      const entry = qaLog[persona] || (qaLog[persona] = { persona, confirmed: [], evidence: [] })
      entry.confirmed.push(bug.title)
      entry.evidence.push(bug.evidence)
    }
    const failing = criteria.filter(c => !c.passes).map(c => `${c.id} fails: ${c.evidence}`)
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
    if (ship.ci === 'fail') { nextRound('ci', [ship.failures || 'CI failed']); continue }
    note('ship', ship.ci, `${prUrl || 'dry run'}; stack ${ship.stack || 'none'}`)
    return { id: unit.id, status: 'done', pr_url: prUrl, stack: ship.stack || 'none', reason: '', result, ...progress }
  }
}

// ---------- review: code-review gates + lenses, skeptics, triage ----------
async function reviewStage(unit, worktree, baseBranch, context, call) {
  const tag = unit.id
  const gates = () => call(
    `Invoke the code-review:review-code skill on the current HEAD of the repo at ${worktree} against base ${baseBranch}, and run it to completion including its verification gate. Return passed (true only if the overall verdict is PASSED) and fails: one entry per FAIL box with location (file:line), scenario (the box id and evidence), severity "major".`,
    { model: WORKERS, schema: GATES, label: `${tag} code-review gates`, phase: 'Review' })
  const lenses = [...LENSES.map(lens => ({ lens, agentType: 'autopilot:lens-reviewer' })),
    ...CFG.review.extra_agents.map(type => ({ lens: type, agentType: type }))]
  const lensUntilDry = async ({ lens, agentType }) => {
    const found = []
    for (let round = 1; round <= 3; round += 1) {
      const out = await call(`Lens: ${lens}\n${context}\nBase: ${baseBranch}\nAlready reported (do not repeat): ${JSON.stringify(found.map(f => f.location + ' ' + f.scenario))}`,
        { agentType, model: WORKERS, schema: FINDINGS, label: `${tag} lens ${lens} r${round}`, phase: 'Review' })
      if (out && out.skipped) log(`${tag} lens ${lens} skipped: ${out.skipped}`)
      const fresh = out ? out.findings.filter(f => f.location && f.scenario) : []
      if (!fresh.length) break
      found.push(...fresh.map(f => ({ ...f, lens })))
    }
    return found
  }
  const [gateResult, ...lensResults] = await parallel([gates, ...lenses.map(l => () => lensUntilDry(l))])
  const gateFail = scenario => [{ location: '-', scenario, severity: 'major' }]
  const gateFails = !gateResult ? gateFail('code-review gates returned nothing')
    : !gateResult.passed && !gateResult.fails.length ? gateFail('code-review verdict FAILED with no FAIL boxes returned')
    : gateResult.fails
  const lensFindings = lensResults.filter(Boolean).flat()

  const survives = async finding => {
    const votes = await parallel([1, 2].map(n => () => call(
      `Try to refute this review finding. Read the code at ${worktree}. Return refuted=false only if you confirm the scenario really breaks; otherwise refuted=true with the reason.\nFinding: ${JSON.stringify(finding)}`,
      { model: WORKERS, schema: REFUTE, label: `${tag} skeptic ${n} ${finding.location}`, phase: 'Review' })))
    return votes.filter(v => v && v.refuted).length < 2 ? finding : null
  }
  const kept = (await parallel(lensFindings.map(f => () => survives(f)))).filter(Boolean)
  if (!gateFails.length && !kept.length) return { fix: [], dismiss: [] }

  const triage = await call(`Triage these findings for ${worktree}.\nGate FAILs: ${JSON.stringify(gateFails)}\nLens findings: ${JSON.stringify(kept)}`,
    { agentType: 'autopilot:triage', model: WORKERS, schema: TRIAGE, label: `${tag} triage`, phase: 'Review' })
  return triage || { fix: [...gateFails, ...kept].map(f => ({ finding: `${f.location} ${f.scenario}`, reason: 'triage returned nothing' })), dismiss: [] }
}

// ---------- QA: boot, personas in parallel, verifier, stop ----------
async function qaStage(unit, worktree, state, context, call, ops) {
  const tag = unit.id
  const boot = await ops('boot app', `bash ${SCRIPTS}/boot-app.sh ${CONFIG_PATH} ${worktree} ${unit.index} ${state}`, worktree)
  if (boot.exit_code !== 0) throw new Stop('failed', `app did not boot: ${boot.output}`)
  const { url } = lastLineJson('boot app', boot.output)
  const login = CFG.launch.login ? `Login: ${JSON.stringify(CFG.launch.login)} (credentials are in those env vars)` : 'No login needed.'
  try {
    const reports = await parallel(unit.contract.personas.map((persona, n) => () => call(
      `Persona: ${JSON.stringify(persona)}\nApp: ${url}\n${login}\nEvidence directory: ${state}/qa/${n}\n${context}`,
      { agentType: 'autopilot:qa-persona', model: WORKERS, schema: QA, label: `${tag} qa ${persona.name}`, phase: 'QA' })))
    const qa = reports.map((r, n) => ({ persona: unit.contract.personas[n].name, bugs: r ? r.bugs : [], not_covered: r ? (r.not_covered || []) : ['agent returned nothing'] }))
    const verdict = await call(`App: ${url}\n${login}\nEvidence directory: ${state}/verify\n${context}\nContract with checks: ${JSON.stringify(unit.contract.criteria)}\nQA reports: ${JSON.stringify(qa)}`,
      { agentType: 'autopilot:verifier', model: WORKERS, schema: VERDICT, label: `${tag} verifier`, phase: 'QA' })
    if (!verdict) throw new Stop('failed', 'verifier returned nothing')
    return { criteria: verdict.criteria, confirmed: verdict.confirmed }
  } finally {
    await ops('stop app', `bash ${SCRIPTS}/stop-app.sh ${state} ${unit.index}`, worktree)
  }
}

function unitResult(unit, rounds, criteria, design, final, review, qa, decisions) {
  const statements = Object.fromEntries(unit.contract.criteria.map(c => [c.id, c.statement]))
  return {
    plan_title: A.plan.title, unit: { id: unit.id, title: unit.title }, rounds,
    criteria: criteria.map(c => ({ id: c.id, statement: statements[c.id] || '', passes: c.passes, evidence: c.evidence })),
    staff: { design, final }, review, qa, decisions,
  }
}

// ---------- run: dependency waves ----------
const results = {}
const pendingUnits = [...A.units]
while (pendingUnits.length) {
  const ready = pendingUnits.filter(u => u.depends_on.every(d => results[d]))
  if (!ready.length) break
  for (const u of ready) pendingUnits.splice(pendingUnits.indexOf(u), 1)
  const runnable = []
  for (const u of ready) {
    const blockedDep = u.depends_on.find(d => results[d].status !== 'done')
    if (blockedDep) results[u.id] = { id: u.id, status: 'skipped', reason: `depends on ${blockedDep} (${results[blockedDep].status})`, rounds: 0, agents: 0, pr_url: null }
    else runnable.push(u)
  }
  // Stacked PRs: a unit with dependencies branches from its last dependency's branch.
  const base = u => (u.depends_on.length ? results[u.depends_on[u.depends_on.length - 1]].branch : A.base_branch)
  for (let i = 0; i < runnable.length; i += LIMITS.max_parallel_units) {
    const wave = runnable.slice(i, i + LIMITS.max_parallel_units)
    const done = await parallel(wave.map(u => async () => {
      const parent = u.depends_on.length ? results[u.depends_on[u.depends_on.length - 1]] : null
      try { return await deliverUnit(u, base(u), parent && parent.pr_url) }
      catch (error) {
        const status = error instanceof Stop ? error.status : 'failed'
        log(`${u.id} ${status}: ${error.message}`)
        return { id: u.id, status, reason: error.message, pr_url: null, ...(error.progress || { rounds: 0, agents: 0, decisions: [] }) }
      }
    }))
    done.forEach((r, n) => { results[wave[n].id] = r || { id: wave[n].id, status: 'failed', reason: 'unit returned nothing', rounds: 0, agents: 0, pr_url: null } })
  }
}
return { units: A.units.map(u => results[u.id] || { id: u.id, status: 'skipped', reason: 'dependency never ran', rounds: 0, agents: 0, pr_url: null }) }
