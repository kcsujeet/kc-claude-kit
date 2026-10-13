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
  if (label.includes('code-review gates')) return { passed: true, fails: [] }
  if (label.includes('skeptic')) return { refuted: false, reason: 'reproduces' }
  throw new Error(`no scripted answer for ${label}`)
}

function unit(id, index, dependsOn = []) {
  return {
    id, index, title: `Unit ${id}`, scope: 'scope', depends_on: dependsOn,
    contract: { criteria: [{ id: 'AC1', statement: 'It works.', check: { kind: 'test', how: 'bun test' } }], personas: [{ name: 'newbie', goals: 'g', behaviour: 'b' }] },
  }
}

async function simulate({ units = [unit('U1', 0)], limits = {}, answer = () => undefined } = {}) {
  const calls = []
  const args = {
    run_id: 'r1', repo: '/repo', run_dir: '/repo/.autopilot/runs/r1', plugin_root: '/plugin', dry_run: false, base_branch: 'main',
    plan: { title: 'Plan', goal: 'goal', out_of_scope: 'none' }, architecture: 'arch',
    config: {
      launch: { login: null }, review: { extra_agents: [] },
      limits: { max_fix_rounds: 2, max_parallel_units: 2, max_agents_per_unit: 120, ...limits },
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

  'a FAILED code-review verdict without FAIL boxes still goes to triage': async () => {
    let gateCalls = 0
    const { byId, calls } = await simulate({
      answer: (p, { label }) => (label.includes('code-review gates') && gateCalls++ === 0 ? { passed: false, fails: [] } : undefined),
    })
    assert.ok(calls.some(c => c.label === 'U1 triage'))
    assert.equal(byId.U1.status, 'done')
  },

  'ops, shipper, persona and verifier prompts name the scripts directory': async () => {
    const { calls } = await simulate()
    for (const type of ['ops', 'shipper', 'qa-persona', 'verifier']) {
      for (const c of calls.filter(x => x.agentType === `autopilot:${type}`)) assert.match(c.prompt, /^Scripts directory: \/plugin\/scripts$/m, c.label)
    }
    for (const type of ['qa-persona', 'verifier']) assert.match(calls.find(c => c.agentType === `autopilot:${type}`).prompt, /^Evidence directory: \//m)
  },
}

let failures = 0
for (const [name, run] of Object.entries(tests)) {
  try { await run(); console.log(`ok   ${name}`) }
  catch (error) { failures += 1; console.log(`FAIL ${name}\n     ${error.message.split('\n').join('\n     ')}`) }
}
process.exit(failures ? 1 : 0)
