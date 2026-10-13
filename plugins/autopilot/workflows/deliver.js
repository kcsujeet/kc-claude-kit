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
// Review rounds in which minor findings still cost an engineer fix round. After them, each fix
// adds new code for the gates to nit, so a large unit would never run dry; minor findings are
// listed in the PR instead.
const MINOR_FIX_ROUNDS = 2
const WORKERS = CFG.models.workers
const STAFF = CFG.models.staff
const SCRIPTS = `${A.plugin_root}/scripts`
const CONFIG_PATH = `${A.run_dir}/config.json`
// review-code's phase-1 gates (plugins/code-review/skills/review-code/SKILL.md, Step 2):
// all ten every round; a gate that does not apply returns PASS (N/A) itself.
const GATE_TOPICS = ['naming', 'clarity', 'structure', 'simplicity', 'datetime', 'react', 'i18n', 'testing', 'correctness', 'project-conventions']
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
const PREP = {
  type: 'object', required: ['exit_code', 'head_sha', 'diff_file', 'changed_files', 'files', 'scope'],
  properties: { exit_code: { type: 'number' }, output: str, head_sha: str, diff_file: str, changed_files: str, files: strs, scope: str },
}
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
    confirmed: { type: 'array', items: { type: 'object', required: ['title', 'steps', 'evidence', 'origin'], properties: { title: str, steps: strs, evidence: str, persona: str, origin: { type: 'string', enum: ['caused', 'pre-existing'] } } } },
    dropped: { type: 'array', items: { type: 'object', required: ['title', 'reason'], properties: { title: str, reason: str } } },
  },
}
const SHIP = { type: 'object', required: ['ci', 'body'], properties: { pr_url: { type: ['string', 'null'] }, body: str, stack: str, ci: { type: 'string', enum: ['pass', 'fail', 'none', 'skipped'] }, failures: str, notes: str } }

// ---------- one unit ----------
class Stop extends Error { constructor(status, reason) { super(reason); this.status = status } }

const NOT_CHECKED = 'not checked by verifier'

// Bundled scripts print one JSON line last; ops returns stdout and stderr
// together and may add a line of its own after it (seen: "exit=0"), so the
// last line that parses as a JSON object wins.
function lastLineJson(label, output) {
  for (const line of output.trim().split('\n').reverse()) {
    try {
      const value = JSON.parse(line)
      if (value && typeof value === 'object' && !Array.isArray(value)) return value
    } catch { /* not the JSON line */ }
  }
  throw new Stop('failed', `${label} printed no JSON: ${output}`)
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
  let reviewLog = { fixed: [], dismissed: [], deferred_minor: [] }
  // Every earlier fix and dismissal, so later rounds do not reverse them without a new scenario.
  const history = []
  const qaLog = Object.fromEntries(personas.map(p => [p.name, { persona: p.name, confirmed: [], evidence: [] }]))
  // Confirmed bugs the verifier traced to the base branch, outside this unit's criteria.
  const qaPreexisting = []
  // Receipt-only verification FAILs left after one gate recheck, from the last review.
  let reviewReceipts = []
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

    const review = await reviewStage({ ...ctx, history, reviewRound: progress.rounds + 1 })
    reviewReceipts = review.receipts
    reviewLog.deferred_minor = (review.deferred || []).map(f => `${f.location} ${f.scenario}`)
    reviewLog.fixed.push(...review.fix.map(f => f.finding))
    reviewLog.dismissed.push(...review.dismiss)
    history.push(...review.fix.map(f => ({ round: progress.rounds + 1, decision: 'fixed', finding: f.finding, reason: f.reason })),
      ...review.dismiss.map(f => ({ round: progress.rounds + 1, decision: 'dismissed', finding: f.finding, reason: f.reason })))
    if (review.fix.length) { nextRound('review', review.fix.map(f => `${f.finding} (${f.reason})`)); continue }

    const verdict = await qaStage(ctx)
    criteria = contractResults(unit, verdict.criteria)
    // Only bugs this unit caused enter the fix loop; an unclassified bug counts as caused.
    const caused = verdict.confirmed.filter(b => b.origin !== 'pre-existing')
    for (const bug of verdict.confirmed.filter(b => b.origin === 'pre-existing')) {
      if (!qaPreexisting.some(p => p.title === bug.title)) qaPreexisting.push({ title: bug.title, steps: bug.steps, evidence: bug.evidence })
    }
    // Bugs confirmed in any round are what QA caught; the last round is clean by definition.
    for (const bug of caused) {
      const persona = bug.persona || 'unattributed'
      const entry = qaLog[persona] || (qaLog[persona] = { persona, confirmed: [], evidence: [] })
      entry.confirmed.push(bug.title)
      entry.evidence.push(bug.evidence)
    }
    const failing = criteria.filter(c => !c.passes).map(c => (c.evidence === NOT_CHECKED ? `${c.id} ${NOT_CHECKED}` : `${c.id} fails: ${c.evidence}`))
    const bugs = caused.map(b => `${b.title}: ${b.steps.join(' → ')} (evidence ${b.evidence})`)
    // A QA-driven fix is a decision later review rounds may not revert without a new scenario.
    history.push(...caused.map(b => ({ round: progress.rounds + 1, decision: 'fixed', finding: `QA: ${b.title}`, reason: `confirmed by the verifier (${b.persona || 'unattributed'}): ${b.steps.join(' → ')}` })))
    if (failing.length || bugs.length) { nextRound('qa', [...failing, ...bugs]); continue }

    const final = await call(`Final gate.\n${context}\nGet the diff with: git -C ${worktree} diff ${baseBranch}...HEAD\nContract results: ${JSON.stringify(criteria)}\nDecision log: ${JSON.stringify(decisions)}`,
      { agentType: 'autopilot:staff-reviewer', model: STAFF, schema: FINAL, label: `${tag} final gate`, phase: 'Ship' })
    if (!final || final.verdict !== 'approve') { nextRound('staff', [final ? final.direction : 'final gate returned nothing']); continue }
    finalRationale = final.rationale
    note('final gate', 'approve', final.rationale)

    const result = unitResult(unit, progress.rounds, criteria, decision.rationale, finalRationale, reviewLog, { qa: Object.values(qaLog), preexisting: qaPreexisting, receipts: reviewReceipts }, decisions)
    const ship = await call(`Worktree: ${worktree}\nBranch: ${branch}\nBase: ${baseBranch}\nTitle: ${A.plan.title}: ${unit.title}\nScratch: ${state}\nScripts directory: ${SCRIPTS}\ndry_run: ${A.dry_run}\nparent_pr: ${parentPr || 'none'}\nUnit result counts: ${resultCounts(result)}\nUnit result JSON:\n${JSON.stringify(result)}`,
      { agentType: 'autopilot:shipper', model: WORKERS, schema: SHIP, label: `${tag} ship`, phase: 'Ship' })
    if (!ship) throw new Stop('failed', 'shipper returned nothing')
    // Even a dry run must leave unit-result.json and the rendered PR body behind.
    if (!ship.body) throw new Stop('failed', `shipper rendered no PR body: ${ship.notes || 'no notes'}`)
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
// Returns {fix, dismiss, receipts, deferred}: triage's verdict on every gate FAIL and
// surviving lens finding, the review's incomplete receipts, and minor findings deferred to the PR.
async function reviewStage({ unit, tag, worktree, baseBranch, state, context, call, note, retryOnce, history, reviewRound }) {
  const earlier = history.length
    ? `Earlier review decisions (do not re-raise or reverse one unless you give a new concrete scenario it did not consider): ${JSON.stringify(history)}`
    : ''
  const gates = () => codeReviewGates({ unit, tag, worktree, baseBranch, state, call, note, retryOnce, earlier, reviewRound })
  const lenses = [...LENSES.map(lens => ({ lens, agentType: 'autopilot:lens-reviewer' })),
    ...CFG.review.extra_agents.map(type => ({ lens: type, agentType: type }))]
  const lensUntilDry = async ({ lens, agentType }) => {
    const found = []
    for (let round = 1; round <= 3; round += 1) {
      const out = await retryOnce(`lens ${lens} r${round}`, label => call(
        `Lens: ${lens}\n${context}\nBase: ${baseBranch}\nAlready reported (do not repeat): ${JSON.stringify(found.map(f => f.location + ' ' + f.scenario))}${earlier && `\n${earlier}`}`,
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
  const lensFindings = lensResults.flat()

  // Skeptics guard against plausible-but-wrong serious findings; minor ones go straight to triage.
  const serious = f => f.severity === 'blocker' || f.severity === 'major'
  const survives = async finding => {
    const votes = await settle([1, 2].map(n => () => call(
      `Try to refute this review finding. Read the code at ${worktree}. Return refuted=false only if you confirm the scenario really breaks; otherwise refuted=true with the reason.\nFinding: ${JSON.stringify(finding)}`,
      { agentType: 'autopilot:skeptic', model: WORKERS, schema: REFUTE, label: `${tag} skeptic ${n} ${finding.location}`, phase: 'Review' })))
    if (votes.some(v => !v)) note(`skeptic ${finding.location}`, 'null', 'a skeptic returned nothing; counted as not refuted')
    return votes.filter(v => v && v.refuted).length < 2 ? finding : null
  }
  const judged = await settle(lensFindings.filter(serious).map(f => () => survives(f)))
  const kept = [...judged.filter(Boolean), ...lensFindings.filter(f => !serious(f))]
  const receipts = gateResult.receiptsIncomplete
  const deferMinor = reviewRound > MINOR_FIX_ROUNDS
  const minor = f => f.severity === 'minor'
  const deferred = deferMinor ? [...gateResult.fails, ...kept].filter(minor) : []
  const fails = deferMinor ? gateResult.fails.filter(f => !minor(f)) : gateResult.fails
  const toTriage = deferMinor ? kept.filter(f => !minor(f)) : kept
  if (!fails.length && !toTriage.length) return { fix: [], dismiss: [], receipts, deferred }

  const triage = await call(`Triage these findings for ${worktree}.\n${planSpecs(unit)}\nGate FAILs: ${JSON.stringify(fails)}\nLens findings: ${JSON.stringify(toTriage)}${fails.some(f => f.lens === 'verification') ? '\nItems with lens "verification" cite code in this diff: never dismiss one as a format or citation issue.' : ''}${earlier && `\n${earlier}\nDismiss an item that only reverses an earlier decision, with reason "reverses round N decision without new scenario" (N from that decision).`}`,
    { agentType: 'autopilot:triage', model: WORKERS, schema: TRIAGE, label: `${tag} triage`, phase: 'Review' })
  return { ...(triage || { fix: [...fails, ...toTriage].map(f => ({ finding: `${f.location} ${f.scenario}`, reason: 'triage returned nothing' })), dismiss: [] }), receipts, deferred }
}

// What the plan fixes for this unit: names, signatures and files there are
// out of scope for gate-driven fixes (triage dismisses with "specified by plan").
function planSpecs(unit) {
  const brief = u => ({ id: u.id, title: u.title, scope: u.scope, criteria: u.contract.criteria.map(c => c.statement) })
  const dependents = A.units.filter(u => ancestors(u.id).has(unit.id)).map(brief)
  return [`Plan specifies (names, signatures and files here are not changed by a gate-driven fix; dismiss such a fix with reason "specified by plan"):`,
    `Cross-unit architecture: ${A.architecture}`, `This unit: ${JSON.stringify(brief(unit))}`,
    `Units that depend on this one: ${JSON.stringify(dependents)}`].join('\n')
}

// ---------- code-review gates, dispatched the way review-code does ----------
// Workflow agents cannot spawn agents, so the workflow runs review-code's
// orchestration itself (plugins/code-review/skills/review-code/SKILL.md):
// Step 1 gather + SCOPE block, Step 2 phase-1 gates in parallel, then the
// verification gate on their verbatim blocks, Step 4 aggregation.
const CR = () => A.code_review_root
const SEVERITY = { '🔴': 'blocker', '🟠': 'major', '🟡': 'minor' }

// Parses a gate's verdict block (GATE/STATUS/BOXES/FINDINGS lines; a SCOPE:
// header reads as BOXES); null when it does not have review-code's shape.
function parseGateBlock(text) {
  if (typeof text !== 'string') return null
  const sections = { BOXES: [], FINDINGS: [] }
  let status = null
  let current = null
  let sawBoxes = false
  for (const raw of text.split('\n')) {
    const line = raw.trim()
    const header = line.match(/^(GATE|STATUS|BOXES|FINDINGS|SCOPE):\s*(.*)$/)
    if (header) {
      current = header[1] === 'SCOPE' ? 'BOXES' : header[1]
      if (current === 'STATUS') status = (header[2].match(/^(PASS \(N\/A\)|PASS|FAIL)\b/) || [])[1] || null
      if (current === 'BOXES') sawBoxes = true
      if (!(current in sections)) current = null
      continue
    }
    if (current && line.startsWith('- ')) sections[current].push(line.slice(2))
  }
  if (!status || !sawBoxes) return null
  const failBoxes = sections.BOXES.filter(b => b.startsWith('[FAIL]')).map(b => b.slice(6).trim())
  const findings = sections.FINDINGS.filter(f => !/^(none|n\/a)\.?$/i.test(f))
  return { status, failBoxes, findings }
}

const locationOf = text => (text.match(/[\w./-]+\.[\w]+:\d+(?:[-,]\d+)*(?:@[0-9a-f]+)?/) || [null])[0]

// One fail entry per finding line; with no findings, one per FAIL box; with
// neither, one saying the gate FAILED without box details (never nothing).
function gateFails(gate, parsed) {
  const fromFindings = parsed.findings.map(f => {
    const sev = Object.keys(SEVERITY).find(e => f.startsWith(e))
    return { location: locationOf(f) || gate, scenario: `${gate}: ${f}`, severity: sev ? SEVERITY[sev] : 'major', lens: gate }
  })
  if (fromFindings.length) return fromFindings
  if (parsed.failBoxes.length) return parsed.failBoxes.map(b => ({ location: locationOf(b) || gate, scenario: `${gate} ${b}`, severity: 'major', lens: gate }))
  return [{ location: gate, scenario: `${gate}: FAILED without box details`, severity: 'major', lens: gate }]
}

async function codeReviewGates({ unit, tag, worktree, baseBranch, state, call, note, retryOnce, earlier, reviewRound }) {
  if (!CR()) throw new Stop('failed', 'code_review_root missing from the workflow args')
  const outDir = `${state}/review/r${reviewRound}`
  const prep = await retryOnce('review prep', label => call(
    `You are review-code's orchestrator for Step 1 only (read ${CR()}/skills/review-code/SKILL.md, "Step 1: gather context" and "Scope checks").\n` +
    `1. Run exactly: cd ${worktree} && bash ${CR()}/scripts/gather-review.sh --branch ${baseBranch} --out-dir ${outDir}\n` +
    `2. Read the diff it saved in full (in offset/limit chunks if it is 35KB or more), and write the SCOPE: block for this local branch, one box per line in the BOXES: shape, each with evidence or its N/A reason: §G1 (N/A: local diff), §G2 against the stated purpose "${unit.title}: ${unit.scope}", §G3 (N/A: no linked issue), §G4.\n` +
    `Return exit_code (gather-review.sh's), output (its stdout and stderr), head_sha, diff_file and changed_files (HEAD_SHA, DIFF_FILE, CHANGED_FILES from its meta.env), files (the paths listed in CHANGED_FILES), and scope (the whole SCOPE: block starting with "SCOPE:").`,
    { agentType: 'autopilot:review-prep', model: WORKERS, effort: 'low', schema: PREP, label: `${tag} ${label}`, phase: 'Review' }))
  if (!prep) throw new Stop('failed', 'code-review prep did not run')
  if (prep.exit_code !== 0) throw new Stop('failed', `code-review gather failed: ${prep.output || ''}`)
  const inputs = [`Head SHA: ${prep.head_sha}`, `Diff file: ${prep.diff_file}`, `Changed files: ${prep.changed_files}`, `Repo root: ${worktree}`].join('\n')

  // A null or malformed block is retried once (review-code sends a shapeless verdict back); twice fails closed.
  // A FAIL naming no FAIL box and no finding is malformed too, but a second one
  // is kept: gateFails/auditItems turn it into a "FAILED without box details" item.
  const unexplainedFail = p => p.status === 'FAIL' && !p.failBoxes.length && !p.findings.length
  const runGate = async (gate, prompt, pass = '') => {
    let parsed = null
    let text = null
    for (const label of [`gate ${gate}${pass}`, `gate ${gate}${pass} retry`]) {
      text = await call(prompt, { agentType: `code-review:${gate}-gate`, model: WORKERS, label: `${tag} ${label}`, phase: 'Review' })
      parsed = parseGateBlock(text)
      if (parsed && !unexplainedFail(parsed)) break
      const why = parsed ? 'STATUS: FAIL with no FAIL box or finding' : (text ? 'verdict block has no STATUS:/BOXES:' : 'returned nothing')
      note(`gate ${gate}`, parsed ? 'malformed' : 'null', `${why}; retrying once`)
    }
    if (!parsed) throw new Stop('failed', `code-review ${gate} gate did not return a verdict block`)
    return { gate, text: text.trim(), ...parsed }
  }
  let phase1 = await settle(GATE_TOPICS.map(gate => () => runGate(gate, inputs)))
  const verify = pass => runGate('verification', [
    inputs, `Phase-1 gate verdict blocks, verbatim:\n\n${phase1.map(g => g.text).join('\n\n')}`, prep.scope,
    earlier && `Re-review. ${earlier}`,
  ].filter(Boolean).join('\n\n'), pass)
  const failed = g => g.status === 'FAIL' || g.findings.length > 0

  // Verification items that cite code in the diff go to triage like any gate
  // FAIL; receipt-only items re-run the gates they name once, then whatever is
  // left is recorded as incomplete receipts and does not block the unit.
  let verification = await verify('')
  let audit = auditItems(verification, prep.files || [], worktree)
  if (audit.receipts.length) {
    const named = GATE_TOPICS.filter(g => audit.receipts.some(r => r.gates.includes(g)))
    const findings = audit.receipts.map(r => `- ${r.text}`).join('\n')
    const rerun = await settle(named.map(gate => () => runGate(gate, `${inputs}\n\nThe verification gate failed your last verdict's receipts:\n${findings}\nReturn a complete verdict block that fixes them.`, ' recheck')))
    phase1 = phase1.map(g => rerun.find(r => r.gate === g.gate) || g)
    verification = await verify(' recheck')
    // Code items from the first pass stay: the recheck only re-audits receipts.
    const second = auditItems(verification, prep.files || [], worktree)
    const code = [...audit.code, ...second.code.filter(c => !audit.code.some(a => a.scenario === c.scenario))]
    audit = { code, receipts: second.receipts }
  }

  const scope = parseGateBlock(`STATUS: PASS\n${prep.scope}`) || { failBoxes: ['scope block unreadable'], findings: [] }
  const fails = [...phase1.flatMap(g => (failed(g) ? gateFails(g.gate, g) : [])), ...audit.code,
    ...scope.failBoxes.map(b => ({ location: 'scope', scenario: `scope ${b}`, severity: 'major', lens: 'scope' }))]
  const passed = !phase1.some(failed) && !audit.code.length && !scope.failBoxes.length
  return { passed, fails, receiptsIncomplete: audit.receipts.map(r => r.text) }
}

// Sorts a verification verdict's items. Its FINDINGS lead with "<gate, or
// file:line>" (plugins/code-review/agents/verification-gate.md, Output): a
// lead naming a gate or the SCOPE block is receipt-only; a lead citing a file
// in the diff is code. A finding with neither, and every FAIL box when there
// are no findings, is receipt-only and names the gates its text mentions.
function auditItems(verification, files, worktree) {
  if (!(verification.status === 'FAIL' || verification.findings.length)) return { code: [], receipts: [] }
  const mentioned = text => GATE_TOPICS.filter(g => new RegExp(`(^|[^\\w-])${g}([^\\w-]|$)`, 'i').test(text))
  const code = []
  const receipts = []
  // An item naming no gate has nothing to re-run, so triage judges it as code,
  // unless it leads with SCOPE or verification: those are about the review's
  // own write-up, which no engineer change can fix, so they stay receipts.
  const sort = (text, location, severity, receiptLike, aboutReview = false) => {
    const gates = mentioned(text)
    if (receiptLike && (gates.length || aboutReview)) receipts.push({ text, gates })
    else code.push({ location: location || 'verification', scenario: text, severity, lens: 'verification' })
  }
  for (const f of verification.findings) {
    const sev = Object.keys(SEVERITY).find(e => f.startsWith(e))
    const lead = ((sev ? f.slice(sev.length) : f).trim().match(/^(.+?):\s/) || [null, ''])[1]
    const aboutReview = /^(scope|verification)\b/i.test(lead)
    const leadsWithGate = aboutReview || GATE_TOPICS.some(g => new RegExp(`^${g}([^\\w-]|$)`, 'i').test(lead))
    const location = diffLocation(lead, files, worktree)
    sort(`verification: ${f}`, location || diffLocation(f, files, worktree), sev ? SEVERITY[sev] : 'major', leadsWithGate || !location, aboutReview)
  }
  if (!verification.findings.length) {
    const boxes = verification.failBoxes.length ? verification.failBoxes : ['FAILED without box details']
    for (const b of boxes) sort(`verification ${b}`, diffLocation(b, files, worktree), 'major', true)
  }
  return { code, receipts }
}

// The first "<path>:<line>", "<path>:L<line>", "<path>#L<line>" (a GitHub
// anchor) or "<path> line <line>" in text
// whose path is a changed file, as "<changed path>:<line>". The path may carry
// ./, a/, b/ or the worktree prefix, and matches a changed file by path suffix,
// or by basename when only one changed file has it.
function diffLocation(text, files, worktree) {
  const prefix = worktree ? `${worktree.replace(/\/$/, '')}/` : null
  for (const m of text.matchAll(/([\w./@+-]*\w\.\w+)(?::L?(\d+)|#L(\d+)|\s+line\s+(\d+))/gi)) {
    let path = m[1]
    if (prefix && path.startsWith(prefix)) path = path.slice(prefix.length)
    path = path.replace(/^(\.\/|[ab]\/)+/, '')
    const base = path.split('/').pop()
    const bySuffix = files.filter(f => f === path || f.endsWith(`/${path}`) || path.endsWith(`/${f}`))
    const byBase = files.filter(f => f.split('/').pop() === base)
    const file = bySuffix.length === 1 ? bySuffix[0] : (!bySuffix.length && byBase.length === 1 ? byBase[0] : null)
    if (file) return `${file}:${m[2] || m[3] || m[4]}`
  }
  return null
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

// The shipper retypes the result into unit-result.json; these counts let it
// check that nothing was shortened (it compares them with jq, see shipper.md).
function resultCounts(result) {
  return JSON.stringify({ criteria: result.criteria.length, decisions: result.decisions.length,
    fixed: result.review.fixed.length, dismissed: result.review.dismissed.length, qa_preexisting: result.qa_preexisting.length,
    review_receipts_incomplete: result.review_receipts_incomplete.length })
}

function unitResult(unit, rounds, criteria, design, final, review, { qa, preexisting, receipts }, decisions) {
  return {
    plan_title: A.plan.title, unit: { id: unit.id, title: unit.title }, rounds,
    criteria: criteria.map(({ id, statement, passes, evidence }) => ({ id, statement, passes, evidence })),
    staff: { design, final }, review, review_receipts_incomplete: receipts, qa, qa_preexisting: preexisting, decisions,
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
