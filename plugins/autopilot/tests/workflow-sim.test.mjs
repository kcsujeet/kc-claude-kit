// Runs workflows/deliver.js against scripted agents to exercise its control
// flow (design gate, fix rounds, QA, budget, dependency stacking) without
// spawning anything. Stubs mirror the runtime API documented at
// https://code.claude.com/docs/en/workflows: parallel() resolves a throwing
// thunk to null; agent() resolves to the schema object.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const source = readFileSync(join(here, '..', 'workflows', 'deliver.js'), 'utf8')
const body = source.replace(/^export const meta = \{[\s\S]*?^\}\n/m, '')
const AsyncFunction = (async () => {}).constructor
const deliver = new AsyncFunction('agent', 'parallel', 'pipeline', 'phase', 'log', 'args', body)

const unitOf = label => label.split(' ')[0]

const SCOPE_PASS = 'SCOPE:\n- [N/A] §G1: local diff\n- [PASS] §G2: diff matches the unit scope\n- [N/A] §G3: no linked issue\n- [PASS] §G4: diff read whole'
// A review-code verdict block; boxes and findings are lines without the "- ".
function gateBlock(gate, status, boxes = [`[${status === 'FAIL' ? 'FAIL' : 'PASS'}] §X1: a.ts:3 checked`], findings = []) {
  return [`GATE: ${gate}`, `STATUS: ${status}`, 'BOXES:', ...boxes.map(b => `- ${b}`), 'FINDINGS:', ...findings.map(f => `- ${f}`)].join('\n')
}
const GATE_TOPICS = ['naming', 'clarity', 'structure', 'simplicity', 'datetime', 'react', 'i18n', 'testing', 'correctness', 'project-conventions']

// Answers every agent with a clean, passing result; a scenario overrides by
// returning something other than undefined.
function defaultAnswer(prompt, { agentType, label }) {
  const unit = unitOf(label)
  if (agentType === 'autopilot:ops') {
    if (label.endsWith('worktree')) return { exit_code: 0, output: JSON.stringify({ path: `/wt/${unit}`, branch: `autopilot/r1/${unit}` }) }
    if (label.endsWith('boot app')) return { exit_code: 0, output: JSON.stringify({ url: 'http://localhost:4100/', port: 4100, log: '/l' }) }
    return { exit_code: 0, output: 'checks: 1/1 passed' }
  }
  if (agentType === 'autopilot:engineer') {
    return label.endsWith('propose')
      ? { status: 'proposal', approaches: [{ summary: 'reuse', files: [], tradeoffs: 'small' }], recommendation: '0', summary: 'proposed' }
      : { status: 'done', summary: 'built', commits: ['abc123'] }
  }
  if (agentType === 'autopilot:staff-reviewer') {
    return label.includes('design gate')
      ? { verdict: 'pick', approach_index: 0, rationale: 'fits', direction: 'reuse it' }
      : { verdict: 'approve', rationale: 'proportionate' }
  }
  if (agentType === 'autopilot:lens-reviewer') return { findings: [], skipped: '' }
  if (agentType === 'autopilot:triage') return { fix: [], dismiss: [] }
  if (agentType === 'autopilot:qa-persona') return { bugs: [], covered: ['AC1'], not_covered: [] }
  if (agentType === 'autopilot:verifier') return { criteria: [{ id: 'AC1', passes: true, evidence: 'test ok' }], confirmed: [], dropped: [] }
  if (agentType === 'autopilot:shipper') return { pr_url: `https://github.com/o/r/pull/${unit}`, stack: 'none', ci: 'pass', failures: '', notes: '' }
  if (agentType && agentType.startsWith('code-review:')) return gateBlock(agentType.slice(12, -5), 'PASS')
  if (label.endsWith('review prep')) return { exit_code: 0, output: 'HEAD_SHA=abc', head_sha: 'abc', diff_file: '/s/review.diff', changed_files: '/s/changed-files.txt', scope: SCOPE_PASS }
  if (label.includes('skeptic')) return { refuted: false, reason: 'reproduces' }
  throw new Error(`no scripted answer for ${label}`)
}

const criterion = id => ({ id, statement: `${id} holds.`, check: { kind: 'test', how: 'bun test' } })
const persona = name => ({ name, goals: 'g', behaviour: 'b' })

function unit(id, index, dependsOn = [], contract = {}) {
  return {
    id, index, title: `Unit ${id}`, scope: 'scope', depends_on: dependsOn,
    contract: { criteria: [criterion('AC1')], personas: [persona('newbie')], ...contract },
  }
}

const labelled = (calls, label) => calls.filter(c => c.label === label)
const passing = ids => ({ criteria: ids.map(id => ({ id, passes: true, evidence: 'ok' })), confirmed: [], dropped: [] })
// Answers the first `times` calls matching `match` with `value` (a function is
// called, so it can throw), then falls back to the defaults.
function firstCalls(match, value, times = 1) {
  let seen = 0
  return (prompt, opts) => (match(opts) && seen++ < times ? (typeof value === 'function' ? value() : value) : undefined)
}
const isType = type => opts => opts.agentType === `autopilot:${type}`
const hasLabel = text => opts => opts.label.includes(text)

async function simulate({ units = [unit('U1', 0)], limits = {}, answer = () => undefined } = {}) {
  const calls = []
  const args = {
    run_id: 'r1', repo: '/repo', code_review_root: '/cr', run_dir: '/repo/.autopilot/runs/r1', plugin_root: '/plugin', dry_run: false, base_branch: 'main',
    plan: { title: 'Plan', goal: 'goal', out_of_scope: 'none' }, architecture: 'arch',
    config: {
      launch: { login: null }, review: { extra_agents: [] },
      limits: { max_fix_rounds: 2, max_parallel_units: 2, max_agents_per_unit: 120, qa_personas: { min: 1, max: 5 }, ...limits },
      models: { workers: 'sonnet', staff: 'best' },
    },
    units,
  }
  const agent = async (prompt, opts) => {
    calls.push({ prompt, ...opts })
    const scripted = answer(prompt, opts, calls)
    return scripted === undefined ? defaultAnswer(prompt, opts) : scripted
  }
  const parallel = thunks => Promise.all(thunks.map(t => Promise.resolve().then(t).catch(() => null)))
  const out = await deliver(agent, parallel, async () => [], () => {}, () => {}, args)
  return { byId: Object.fromEntries(out.units.map(u => [u.id, u])), calls }
}

const tests = {
  'happy path ships with zero rounds': async () => {
    const { byId } = await simulate()
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.pr_url, 'https://github.com/o/r/pull/U1')
    assert.equal(byId.U1.rounds, 0)
    assert.equal(byId.U1.result.rounds, 0)
  },

  'a confirmed QA bug costs one round and lands in result.qa': async () => {
    let verifierCalls = 0
    const { byId } = await simulate({
      answer: (p, { agentType }) => {
        if (agentType !== 'autopilot:verifier' || verifierCalls++ > 0) return undefined
        return { criteria: [{ id: 'AC1', passes: true, evidence: 'ok' }], confirmed: [{ title: 'double click inserts twice', steps: ['open', 'double click'], evidence: '/e/1.png', persona: 'newbie' }], dropped: [] }
      },
    })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.rounds, 1)
    const newbie = byId.U1.result.qa.find(q => q.persona === 'newbie')
    assert.deepEqual(newbie.confirmed, ['double click inserts twice'])
    assert.deepEqual(newbie.evidence, ['/e/1.png'])
  },

  'a pre-existing QA bug costs no round and lands in result.qa_preexisting': async () => {
    const bug = { title: 'corrupt count shows NaN', steps: ['set count=abc', 'reload'], evidence: '/e/nan.png', persona: 'newbie', origin: 'pre-existing' }
    const { byId, calls } = await simulate({
      answer: (p, { agentType }) => (agentType === 'autopilot:verifier' ? { criteria: [{ id: 'AC1', passes: true, evidence: 'ok' }], confirmed: [bug, bug], dropped: [] } : undefined),
    })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.rounds, 0)
    assert.equal(labelled(calls, 'U1 engineer fix').length, 0)
    assert.deepEqual(byId.U1.result.qa_preexisting, [{ title: bug.title, steps: bug.steps, evidence: bug.evidence }])
    assert.deepEqual(byId.U1.result.qa.find(q => q.persona === 'newbie').confirmed, [])
    assert.match(labelled(calls, 'U1 ship')[0].prompt, /^Unit result counts: .*"qa_preexisting":1\}$/m)
  },

  'a caused QA bug is fixed while a pre-existing one in the same verdict is only reported': async () => {
    let verifierCalls = 0
    const { byId, calls } = await simulate({
      answer: (p, { agentType }) => {
        if (agentType !== 'autopilot:verifier' || verifierCalls++ > 0) return undefined
        return { criteria: [{ id: 'AC1', passes: true, evidence: 'ok' }], dropped: [], confirmed: [
          { title: 'reset leaves stale view', steps: ['add', 'reset'], evidence: '/e/1.png', persona: 'newbie', origin: 'caused' },
          { title: 'NaN on corrupt count', steps: ['set abc'], evidence: '/e/2.png', persona: 'newbie', origin: 'pre-existing' }] }
      },
    })
    assert.equal(byId.U1.rounds, 1)
    const fix = labelled(calls, 'U1 engineer fix')[0].prompt
    assert.ok(fix.includes('reset leaves stale view') && !fix.includes('NaN on corrupt count'))
    assert.deepEqual(byId.U1.result.qa_preexisting.map(b => b.title), ['NaN on corrupt count'])
  },

  'checks that never pass stop the unit as blocked:no-converge': async () => {
    const { byId, calls } = await simulate({
      answer: (p, { label }) => (label.endsWith(' checks') ? { exit_code: 1, output: 'FAIL bun test' } : undefined),
    })
    assert.equal(byId.U1.status, 'blocked:no-converge')
    assert.equal(byId.U1.rounds, 3, 'max_fix_rounds 2: the third failure stops the unit')
    assert.equal(calls.filter(c => c.label === 'U1 engineer fix').length, 2)
    assert.ok(byId.U1.decisions.some(d => d.step === 'design gate'))
    assert.equal(byId.U1.decisions.filter(d => d.step.startsWith('round')).length, 3)
  },

  'plan-conflict blocks the unit and skips its dependent': async () => {
    const { byId, calls } = await simulate({
      units: [unit('U1', 0), unit('U2', 1, ['U1'])],
      answer: (p, { label }) => (label === 'U1 engineer propose' ? { status: 'plan-conflict', summary: 's', notes: 'plan says X, code says Y' } : undefined),
    })
    assert.equal(byId.U1.status, 'blocked:plan-conflict')
    assert.equal(byId.U1.reason, 'plan says X, code says Y')
    assert.equal(byId.U2.status, 'skipped')
    assert.ok(!calls.some(c => c.label.startsWith('U2')))
  },

  'two rejected proposals block the unit as blocked:no-approach': async () => {
    const { byId, calls } = await simulate({
      answer: (p, { label }) => (label.includes('design gate') ? { verdict: 'rework', rationale: 'too big', direction: 'change less' } : undefined),
    })
    assert.equal(byId.U1.status, 'blocked:no-approach')
    assert.equal(calls.filter(c => c.label === 'U1 engineer propose').length, 2)
    assert.equal(byId.U1.decisions.filter(d => d.outcome === 'rework').length, 2)
  },

  'the per-unit agent budget blocks the unit as blocked:budget': async () => {
    const { byId, calls } = await simulate({ limits: { max_agents_per_unit: 10 } })
    assert.equal(byId.U1.status, 'blocked:budget')
    assert.equal(byId.U1.agents, 10)
    assert.equal(calls.length, 10, 'no agent call past the budget')
  },

  'a dependent unit stacks on its parent branch and PR': async () => {
    const { byId, calls } = await simulate({ units: [unit('U1', 0), unit('U2', 1, ['U1'])] })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U2.status, 'done')
    const worktree = calls.find(c => c.label === 'U2 worktree')
    assert.match(worktree.prompt, /worktree\.sh create \/repo r1 U2 autopilot\/r1\/U1$/m)
    const ship = calls.find(c => c.label === 'U2 ship')
    assert.match(ship.prompt, /^parent_pr: https:\/\/github\.com\/o\/r\/pull\/U1$/m)
    assert.match(ship.prompt, /^Base: autopilot\/r1\/U1$/m)
    assert.match(calls.find(c => c.label === 'U1 ship').prompt, /^parent_pr: none$/m)
  },

  'CI that keeps failing blocks the unit but keeps its PR url': async () => {
    const { byId } = await simulate({
      answer: (p, { agentType, label }) => (agentType === 'autopilot:shipper' ? { pr_url: `https://github.com/o/r/pull/${unitOf(label)}`, stack: 'none', ci: 'fail', failures: 'lint' } : undefined),
    })
    assert.equal(byId.U1.status, 'blocked:no-converge')
    assert.equal(byId.U1.pr_url, 'https://github.com/o/r/pull/U1')
  },

  'a shipper that opens no PR outside a dry run fails the unit': async () => {
    const { byId } = await simulate({
      answer: (p, { agentType }) => (agentType === 'autopilot:shipper' ? { pr_url: null, stack: 'none', ci: 'none', notes: 'push rejected' } : undefined),
    })
    assert.equal(byId.U1.status, 'failed')
    assert.match(byId.U1.reason, /push rejected/)
  },

  'the ship prompt carries the unit result counts the shipper checks its file against': async () => {
    let triaged = false
    const { calls } = await simulate({
      answer: (p, { agentType, label }) => {
        if (label === 'U1 lens security r1') return { findings: [{ location: 'a.js:1', scenario: 'x', severity: 'minor' }] }
        if (agentType === 'autopilot:triage' && !triaged) { triaged = true; return { fix: [], dismiss: [{ finding: 'a.js:1 x', reason: 'out of scope' }] } }
        return undefined
      },
    })
    const prompt = labelled(calls, 'U1 ship')[0].prompt
    const json = JSON.parse(prompt.split('Unit result JSON:\n')[1])
    const counts = JSON.parse(prompt.match(/^Unit result counts: (.*)$/m)[1])
    assert.deepEqual(counts, { criteria: 1, decisions: json.decisions.length, fixed: 0, dismissed: 1, qa_preexisting: 0 })
    assert.ok(json.decisions.length > 0)
  },

  'ops, shipper, persona and verifier prompts name the scripts directory': async () => {
    const { calls } = await simulate()
    for (const type of ['ops', 'shipper', 'qa-persona', 'verifier']) {
      for (const c of calls.filter(x => x.agentType === `autopilot:${type}`)) assert.match(c.prompt, /^Scripts directory: \/plugin\/scripts$/m, c.label)
    }
    for (const type of ['qa-persona', 'verifier']) assert.match(calls.find(c => c.agentType === `autopilot:${type}`).prompt, /^Evidence directory: \//m)
  },

  // ---- verifier evidence against the contract ----
  'a failing criterion goes back to the engineer with its evidence': async () => {
    const { byId, calls } = await simulate({
      answer: firstCalls(isType('verifier'), { criteria: [{ id: 'AC1', passes: false, evidence: 'got 500' }], confirmed: [], dropped: [] }),
    })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.rounds, 1)
    assert.match(labelled(calls, 'U1 engineer fix')[0].prompt, /^- AC1 fails: got 500$/m)
  },

  'a criterion the verifier leaves out fails as not checked': async () => {
    const { byId, calls } = await simulate({
      units: [unit('U1', 0, [], { criteria: [criterion('AC1'), criterion('AC2')] })],
      answer: (p, opts) => (isType('verifier')(opts) ? passing(['AC1']) : undefined),
    })
    assert.equal(byId.U1.status, 'blocked:no-converge')
    assert.match(byId.U1.reason, /AC2 not checked by verifier/)
    assert.match(labelled(calls, 'U1 engineer fix')[0].prompt, /^- AC2 not checked by verifier$/m)
  },

  'only passes === true counts as passing': async () => {
    const { byId } = await simulate({
      answer: firstCalls(isType('verifier'), { criteria: [{ id: 'AC1', passes: 'yes', evidence: 'looked fine' }], confirmed: [], dropped: [] }),
    })
    assert.equal(byId.U1.rounds, 1)
  },

  'the PR result lists exactly the contract criteria': async () => {
    const { byId } = await simulate({
      units: [unit('U1', 0, [], { criteria: [criterion('AC1'), criterion('AC2')] })],
      answer: (p, opts) => (isType('verifier')(opts) ? passing(['AC9', 'AC2', 'AC1']) : undefined),
    })
    assert.equal(byId.U1.status, 'done')
    assert.deepEqual(byId.U1.result.criteria.map(c => [c.id, c.statement, c.passes]), [['AC1', 'AC1 holds.', true], ['AC2', 'AC2 holds.', true]])
  },

  'a verifier that returns nothing fails the unit and still stops the app': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(isType('verifier'), null) })
    assert.equal(byId.U1.status, 'failed')
    assert.equal(labelled(calls, 'U1 stop app').length, 1)
    assert.ok(byId.U1.decisions.some(d => d.step === 'verifier' && d.outcome === 'null'))
  },

  'a verifier that throws fails the unit and still stops the app': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(isType('verifier'), () => { throw new Error('agent crashed') }) })
    assert.equal(byId.U1.status, 'failed')
    assert.equal(labelled(calls, 'U1 stop app').length, 1)
  },

  // ---- code-review gates ----
  'review dispatches every code-review gate agent, then verification on their blocks': async () => {
    const { byId, calls } = await simulate()
    assert.equal(byId.U1.status, 'done')
    const prep = labelled(calls, 'U1 review prep')[0]
    assert.match(prep.prompt, /cd \/wt\/U1 && bash \/cr\/scripts\/gather-review\.sh --branch main --out-dir \/repo\/\.autopilot\/runs\/r1\/U1\/review\/r1$/m)
    const gateCalls = calls.filter(c => c.agentType && c.agentType.startsWith('code-review:'))
    assert.deepEqual(gateCalls.map(c => c.agentType), [...GATE_TOPICS, 'verification'].map(g => `code-review:${g}-gate`))
    for (const c of gateCalls) {
      for (const input of ['Head SHA: abc', 'Diff file: /s/review.diff', 'Changed files: /s/changed-files.txt', 'Repo root: /wt/U1']) assert.ok(c.prompt.includes(input), `${c.label} lacks ${input}`)
    }
    const verification = gateCalls.at(-1)
    assert.ok(calls.indexOf(verification) > Math.max(...gateCalls.slice(0, -1).map(c => calls.indexOf(c))), 'verification runs after phase 1')
    for (const g of GATE_TOPICS) assert.ok(verification.prompt.includes(`GATE: ${g}\nSTATUS: PASS`), `verification lacks ${g}'s block`)
    assert.ok(verification.prompt.includes(SCOPE_PASS))
  },

  'a FAIL box becomes a gate finding for triage': async () => {
    let failed = false
    const { byId, calls } = await simulate({
      answer: (p, { agentType }) => {
        if (agentType !== 'code-review:naming-gate' || failed) return undefined
        failed = true
        return gateBlock('naming', 'FAIL', ['[FAIL] §N2: counter.js:4 `x` is opaque'], ['🟡 counter.js:4: `x` is opaque. Rename `nextCount`'])
      },
    })
    assert.equal(byId.U1.status, 'done')
    const triage = labelled(calls, 'U1 triage')[0].prompt
    const fails = JSON.parse(triage.match(/^Gate FAILs: (.*)$/m)[1])
    assert.deepEqual(fails, [{ location: 'counter.js:4', scenario: 'naming: 🟡 counter.js:4: `x` is opaque. Rename `nextCount`', severity: 'minor', lens: 'naming' }])
  },

  'a verification FAIL skips triage and goes straight back as a review round': async () => {
    let failed = false
    const { byId, calls } = await simulate({
      answer: (p, { agentType }) => {
        if (agentType !== 'code-review:verification-gate' || failed) return undefined
        failed = true
        return gateBlock('verification', 'FAIL', ['[FAIL] §V2: testing gate shows no loose-assertion receipt'])
      },
    })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.rounds, 1)
    assert.equal(labelled(calls, 'U1 triage').length, 0)
    assert.match(labelled(calls, 'U1 engineer fix')[0].prompt, /^- verification §V2: testing gate shows no loose-assertion receipt$/m)
  },

  'a verification FAIL with no boxes or findings is still a round': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(opts => opts.agentType === 'code-review:verification-gate', gateBlock('verification', 'FAIL', ['[PASS] §V1: ok'])) })
    assert.equal(byId.U1.rounds, 1)
    assert.match(labelled(calls, 'U1 engineer fix')[0].prompt, /^- verification gate FAILED without box details$/m)
  },

  'a gate that returns nothing once is retried': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(opts => opts.agentType === 'code-review:clarity-gate', null) })
    assert.equal(byId.U1.status, 'done')
    assert.equal(labelled(calls, 'U1 gate clarity retry').length, 1)
    assert.ok(byId.U1.decisions.some(d => d.step === 'gate clarity' && d.outcome === 'null'))
  },

  'a gate that returns nothing twice fails the unit closed': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(opts => opts.agentType === 'code-review:clarity-gate', null, 2) })
    assert.equal(byId.U1.status, 'failed')
    assert.equal(byId.U1.reason, 'code-review clarity gate did not return a verdict block')
    assert.equal(labelled(calls, 'U1 triage').length, 0)
  },

  'a gate block without STATUS or BOXES is rejected like a null': async () => {
    const { byId } = await simulate({ answer: firstCalls(opts => opts.agentType === 'code-review:naming-gate', 'naming looks fine', 2) })
    assert.equal(byId.U1.status, 'failed')
  },

  'a PASS that lists a finding fails the review': async () => {
    let done = false
    const { calls } = await simulate({
      answer: (p, { agentType }) => {
        if (agentType !== 'code-review:testing-gate' || done) return undefined
        done = true
        return gateBlock('testing', 'PASS', ['[PASS] §T1: ok'], ['🟠 a.test.js:9: loose toBeTruthy. Use toBe(1)'])
      },
    })
    const fails = JSON.parse(labelled(calls, 'U1 triage')[0].prompt.match(/^Gate FAILs: (.*)$/m)[1])
    assert.deepEqual(fails.map(f => [f.location, f.severity]), [['a.test.js:9', 'major']])
  },

  'a FAIL in the SCOPE block fails the review': async () => {
    const { byId, calls } = await simulate({
      answer: firstCalls(hasLabel('review prep'), { exit_code: 0, output: '', head_sha: 'abc', diff_file: '/d', changed_files: '/c', scope: 'SCOPE:\n- [FAIL] §G2: adds an unrelated refactor of load()' }),
    })
    assert.equal(byId.U1.status, 'done')
    assert.ok(labelled(calls, 'U1 triage')[0].prompt.includes('§G2: adds an unrelated refactor of load()'))
  },

  'a failed gather fails the unit': async () => {
    const { byId } = await simulate({ answer: firstCalls(hasLabel('review prep'), { exit_code: 2, output: 'base not found', head_sha: '', diff_file: '', changed_files: '', scope: '' }) })
    assert.equal(byId.U1.status, 'failed')
    assert.match(byId.U1.reason, /code-review gather failed: base not found/)
  },

  'a FAILED gate without FAIL boxes or findings is a round, never triaged': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(opts => opts.agentType === 'code-review:naming-gate', gateBlock('naming', 'FAIL', ['[PASS] §N1: ok'])) })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.rounds, 1)
    assert.equal(labelled(calls, 'U1 triage').length, 0)
    assert.match(labelled(calls, 'U1 engineer fix')[0].prompt, /^- code-review reported FAILED without box details$/m)
  },

  // ---- decision history across rounds ----
  'a round-2 finding that reverses a round-1 fix is dismissed with the history in view': async () => {
    let triageCalls = 0
    let lensCalls = 0
    const { byId, calls } = await simulate({
      answer: (p, { agentType, label }) => {
        if (label === 'U1 lens plan-fit r1') {
          lensCalls += 1
          return lensCalls === 1
            ? { findings: [{ location: 'counter.js:1', scenario: "'count' literal repeated three times", severity: 'minor' }] }
            : { findings: [{ location: 'counter.js:1', scenario: 'COUNT_KEY constant is beyond the plan scope; inline it', severity: 'minor' }] }
        }
        if (agentType !== 'autopilot:triage') return undefined
        triageCalls += 1
        if (triageCalls === 1) return { fix: [{ finding: "counter.js:1 'count' literal repeated three times", reason: 'DRY: extract COUNT_KEY' }], dismiss: [] }
        const history = p.match(/^Earlier review decisions .*?: (\[.*\])$/m)
        assert.ok(history, 'round-2 triage gets the decision history')
        assert.deepEqual(JSON.parse(history[1]), [{ round: 1, decision: 'fixed', finding: "counter.js:1 'count' literal repeated three times", reason: 'DRY: extract COUNT_KEY' }])
        assert.match(p, /reverses round N decision without new scenario/)
        return { fix: [], dismiss: [{ finding: 'counter.js:1 COUNT_KEY constant is beyond the plan scope; inline it', reason: 'reverses round 1 decision without new scenario' }] }
      },
    })
    assert.equal(byId.U1.status, 'done')
    assert.equal(byId.U1.rounds, 1, 'the reversal costs no second round')
    assert.deepEqual(byId.U1.result.review.dismissed.map(d => d.reason), ['reverses round 1 decision without new scenario'])
    const [first, second] = labelled(calls, 'U1 lens plan-fit r1')
    assert.ok(!/Earlier review decisions/.test(first.prompt), 'round 1 has no history')
    assert.match(second.prompt, /Earlier review decisions .*'count' literal repeated three times/)
    const verification = calls.filter(c => c.agentType === 'code-review:verification-gate')
    assert.ok(!/Re-review/.test(verification[0].prompt))
    assert.match(verification[1].prompt, /Re-review\. Earlier review decisions/)
  },

  'a QA-driven fix enters the history later review rounds see': async () => {
    let verifierCalls = 0
    const { byId, calls } = await simulate({
      answer: (p, { agentType }) => {
        if (agentType !== 'autopilot:verifier' || verifierCalls++ > 0) return undefined
        return { criteria: [{ id: 'AC1', passes: true, evidence: 'ok' }], dropped: [], confirmed: [
          { title: 'corrupt count shows NaN', steps: ['set count=abc', 'reload'], evidence: '/e/1.png', persona: 'newbie', origin: 'caused' }] }
      },
    })
    assert.equal(byId.U1.status, 'done')
    const secondLens = labelled(calls, 'U1 lens plan-fit r1')[1].prompt
    const history = JSON.parse(secondLens.match(/^Earlier review decisions .*?: (\[.*\])$/m)[1])
    assert.deepEqual(history, [{ round: 1, decision: 'fixed', finding: 'QA: corrupt count shows NaN', reason: 'confirmed by the verifier (newbie): set count=abc → reload' }])
    assert.match(calls.filter(c => c.agentType === 'code-review:verification-gate')[1].prompt, /QA: corrupt count shows NaN/)
  },

  // ---- lenses and personas ----
  'a lens that returns nothing once is retried': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(hasLabel('lens security r1'), null) })
    assert.equal(byId.U1.status, 'done')
    assert.equal(labelled(calls, 'U1 lens security r1 retry').length, 1)
  },

  'a lens that returns nothing twice fails the unit': async () => {
    const { byId } = await simulate({ answer: firstCalls(hasLabel('lens security r1'), null, 2) })
    assert.equal(byId.U1.status, 'failed')
    assert.equal(byId.U1.reason, 'lens security did not run')
  },

  'a lens skip is recorded in the decision log': async () => {
    const { byId } = await simulate({ answer: firstCalls(hasLabel('lens accessibility'), { findings: [], skipped: 'no UI files' }) })
    assert.ok(byId.U1.decisions.some(d => d.step === 'lens accessibility' && d.outcome === 'skipped' && d.reason === 'no UI files'))
  },

  'fewer persona reports than qa_personas.min fail the unit': async () => {
    const { byId, calls } = await simulate({
      units: [unit('U1', 0, [], { personas: [persona('newbie'), persona('expert')] })],
      limits: { qa_personas: { min: 2, max: 5 } },
      answer: firstCalls(hasLabel('qa expert'), null),
    })
    assert.equal(byId.U1.status, 'failed')
    assert.equal(byId.U1.reason, 'only 1 personas reported')
    assert.ok(byId.U1.decisions.some(d => d.step === 'qa expert' && d.outcome === 'null'))
    assert.equal(labelled(calls, 'U1 stop app').length, 1)
  },

  'a contract with fewer personas than qa_personas.min fails before any agent runs': async () => {
    const { byId, calls } = await simulate({ limits: { qa_personas: { min: 3, max: 5 } } })
    assert.equal(byId.U1.status, 'failed')
    assert.equal(calls.length, 0)
  },

  'minor lens findings skip the skeptics; serious ones get two': async () => {
    const found = (severity, where) => ({ findings: [{ location: where, scenario: 's', consequence: 'c', severity, lens: 'data' }] })
    const minor = firstCalls(hasLabel('lens data r1'), found('minor', 'a.ts:1'))
    const major = firstCalls(hasLabel('lens security r1'), found('major', 'b.ts:2'))
    const { byId, calls } = await simulate({ answer: (p, o) => minor(p, o) ?? major(p, o) })
    assert.equal(byId.U1.status, 'done')
    assert.equal(calls.filter(c => c.label.includes('skeptic') && c.label.endsWith('a.ts:1')).length, 0)
    assert.equal(calls.filter(c => c.label.includes('skeptic') && c.label.endsWith('b.ts:2')).length, 2)
    const triage = labelled(calls, 'U1 triage')[0].prompt
    assert.ok(triage.includes('a.ts:1') && triage.includes('b.ts:2'))
  },

  // ---- app cleanup ----
  'a spent budget still stops the app': async () => {
    // 29 calls reach boot: worktree, propose, design, build, checks, review prep, 10 gates, verification, 11 lenses, boot.
    const { byId, calls } = await simulate({ limits: { max_agents_per_unit: 29 } })
    assert.equal(byId.U1.status, 'blocked:budget')
    assert.equal(labelled(calls, 'U1 stop app').length, 1)
  },

  'a line ops appends after the JSON (exit=0) does not hide it': async () => {
    const { byId } = await simulate({
      answer: firstCalls(hasLabel('boot app'), { exit_code: 0, output: '{"url":"http://127.0.0.1:4100/","port":4100,"log":"/l"}\nexit=0' }),
    })
    assert.equal(byId.U1.status, 'done')
  },

  'boot output without JSON fails the unit and still stops the app': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(hasLabel('boot app'), { exit_code: 0, output: 'starting…' }) })
    assert.equal(byId.U1.status, 'failed')
    assert.match(byId.U1.reason, /boot app printed no JSON/)
    assert.equal(labelled(calls, 'U1 stop app').length, 1)
  },

  'a stop-app failure is recorded': async () => {
    const { byId } = await simulate({ answer: firstCalls(hasLabel('stop app'), { exit_code: 1, output: 'kill: no such process' }) })
    assert.equal(byId.U1.status, 'done')
    assert.ok(byId.U1.decisions.some(d => d.step === 'stop app' && d.outcome === 'exit 1'))
  },

  // ---- design gate ----
  'a pick of an approach that was not proposed is a rework': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(hasLabel('design gate'), { verdict: 'pick', approach_index: 4, rationale: 'r', direction: 'd' }) })
    assert.equal(byId.U1.status, 'done')
    assert.equal(labelled(calls, 'U1 engineer propose').length, 2)
    assert.match(labelled(calls, 'U1 engineer propose')[1].prompt, /approach 4, which was not proposed/)
  },

  'a proposal with no approaches is a rework without asking staff': async () => {
    const { byId, calls } = await simulate({ answer: firstCalls(hasLabel('engineer propose'), { status: 'proposal', approaches: [], summary: 's' }) })
    assert.equal(byId.U1.status, 'done')
    assert.equal(labelled(calls, 'U1 design gate 1').length, 0)
    assert.equal(labelled(calls, 'U1 design gate 2').length, 1)
  },

  // ---- shipping ----
  'CI that did not finish fails the unit without an engineer round': async () => {
    const { byId, calls } = await simulate({
      answer: firstCalls(isType('shipper'), { pr_url: 'https://github.com/o/r/pull/1', stack: 'none', ci: 'fail', failures: 'CI did not finish: pending' }),
    })
    assert.equal(byId.U1.status, 'failed')
    assert.match(byId.U1.reason, /^CI did not finish/)
    assert.equal(labelled(calls, 'U1 engineer fix').length, 0)
  },

  // ---- dependencies and waves ----
  'a unit with several dependencies stacks on the one covering the others': async () => {
    const { byId, calls } = await simulate({ units: [unit('U1', 0), unit('U2', 1, ['U1']), unit('U3', 2, ['U1', 'U2'])] })
    assert.equal(byId.U3.status, 'done')
    assert.match(labelled(calls, 'U3 worktree')[0].prompt, / U3 autopilot\/r1\/U2$/m)
    assert.match(labelled(calls, 'U3 ship')[0].prompt, /^parent_pr: https:\/\/github\.com\/o\/r\/pull\/U2$/m)
  },

  'a unit depending on independent units is a plan conflict': async () => {
    const { byId, calls } = await simulate({ units: [unit('U1', 0), unit('U2', 1), unit('U3', 2, ['U1', 'U2']), unit('U4', 3, ['U3'])] })
    assert.equal(byId.U3.status, 'blocked:plan-conflict')
    assert.equal(byId.U3.reason, 'depends on independent units U1 and U2; make one depend on the other')
    assert.equal(byId.U4.status, 'skipped')
    assert.ok(!calls.some(c => c.label.startsWith('U3') || c.label.startsWith('U4')))
  },

  'two children of one parent both stack on it': async () => {
    const { byId, calls } = await simulate({ units: [unit('U1', 0), unit('U2', 1, ['U1']), unit('U3', 2, ['U1'])] })
    for (const id of ['U2', 'U3']) {
      assert.equal(byId[id].status, 'done')
      assert.match(labelled(calls, `${id} worktree`)[0].prompt, / autopilot\/r1\/U1$/m)
      assert.match(labelled(calls, `${id} ship`)[0].prompt, /^parent_pr: https:\/\/github\.com\/o\/r\/pull\/U1$/m)
    }
  },

  'max_parallel_units=1 runs independent units one after the other': async () => {
    const { byId, calls } = await simulate({ units: [unit('U1', 0), unit('U2', 1)], limits: { max_parallel_units: 1 } })
    assert.equal(byId.U2.status, 'done')
    const lastU1 = calls.map(c => unitOf(c.label)).lastIndexOf('U1')
    const firstU2 = calls.map(c => unitOf(c.label)).indexOf('U2')
    assert.ok(lastU1 < firstU2, `U2 started at call ${firstU2} before U1 finished at ${lastU1}`)
  },

  'max_parallel_units=2 runs independent units together': async () => {
    const { calls } = await simulate({ units: [unit('U1', 0), unit('U2', 1)] })
    const lastU1 = calls.map(c => unitOf(c.label)).lastIndexOf('U1')
    const firstU2 = calls.map(c => unitOf(c.label)).indexOf('U2')
    assert.ok(firstU2 < lastU1)
  },
}

let failures = 0
for (const [name, run] of Object.entries(tests)) {
  try { await run(); console.log(`ok   ${name}`) }
  catch (error) { failures += 1; console.log(`FAIL ${name}\n     ${error.message.split('\n').join('\n     ')}`) }
}
process.exit(failures ? 1 : 0)
