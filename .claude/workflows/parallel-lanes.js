export const meta = {
  name: 'parallel-lanes',
  description: 'Generic 4-phase parallel improvement: Planner decomposes work into disjoint lanes → parallel Implementers (worktree-isolated, self-gated) → collective Gap-checker reviews all diffs → targeted Fixers address P0/P1 findings. Returns per-lane diffs for sequential gated integration.',
  whenToUse: 'When a self-improve tick should advance multiple disjoint areas at once. Configure LANES and GATE_CMD for the project, then invoke from a /self-improve tick or on demand.',
  phases: [
    { title: 'Plan', detail: 'Planner decomposes the tick into one concrete item per disjoint lane' },
    { title: 'Implement', detail: 'one agent per lane, worktree-isolated, self-gated' },
    { title: 'Gap-check', detail: 'Reviewer critiques all lane diffs collectively for regressions and rule violations' },
    { title: 'Fix', detail: 'Targeted agents re-implement flagged lanes guided by gap findings' },
  ],
}

// ── PROJECT CONFIGURATION ─────────────────────────────────────────────────────
// Lanes MUST be disjoint — no two lanes may list the same file.
// Explicit file ownership prevents merge conflicts between parallel worktrees.
// Replace the examples below with the project's actual domains and files.
const LANES = (args && args.lanes) || [
  {
    key: 'frontend',
    title: 'Frontend / UI polish',
    files: ['src/components/', 'static/', 'templates/'],
    focus: 'Improve UI usability, accessibility, or visual consistency. One focused, user-visible improvement.',
  },
  {
    key: 'backend',
    title: 'Backend / API correctness',
    files: ['src/api/', 'app.py', 'server.py'],
    focus: 'Fix a real API correctness or reliability bug. New/changed endpoints need a regression test.',
  },
  {
    key: 'tests',
    title: 'Test coverage and quality',
    files: ['tests/'],
    focus: 'Close one real coverage gap: untested endpoint, missing edge case, or adversarial probe.',
  },
]

// Fast gate run inside each worktree after implementation.
const GATE_CMD = (args && args.gate) || 'bash tests/run.sh 2>/dev/null || echo "(no test command)"'

// Project conventions injected into every agent prompt.
const PROJECT_RULES = (args && args.rules) || `
- Minimum change that solves the problem. No drive-by refactors.
- Every changed line must trace to the lane's stated focus.
- Add a regression test that fails without the change and passes with it.
- A lane with nothing worth changing returns status 'noop' — never invent work.
`
// ── END CONFIGURATION ─────────────────────────────────────────────────────────

const PLAN_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['lanes'],
  properties: {
    lanes: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['key', 'item'],
        properties: {
          key: { type: 'string' },
          item: { type: 'string', description: 'ONE concrete, shippable improvement for this lane' },
          rationale: { type: 'string' },
        },
      },
    },
  },
}

const LANE_RESULT = {
  type: 'object',
  additionalProperties: false,
  required: ['key', 'status', 'summary', 'diff'],
  properties: {
    key: { type: 'string' },
    status: { type: 'string', enum: ['done', 'noop', 'blocked'] },
    summary: { type: 'string', description: 'what changed in one or two sentences' },
    gate: { type: 'string', description: 'gate commands run + PASS/FAIL result' },
    files: { type: 'array', items: { type: 'string' } },
    diff: { type: 'string', description: 'full unified diff (git diff) — empty string if noop' },
  },
}

const GAP_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['findings'],
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['lane', 'severity', 'issue'],
        properties: {
          lane: { type: 'string' },
          severity: { type: 'string', enum: ['P0', 'P1', 'P2'] },
          issue: { type: 'string' },
          fix: { type: 'string', description: 'concrete corrective action for the fixer' },
        },
      },
    },
  },
}

function implementPrompt(lane, planItem) {
  return `You are the **${lane.key}** lane of a parallel self-improvement tick, running in an ISOLATED git worktree.

LANE: ${lane.title}
SCOPE — edit ONLY these paths (touching any other file fails your lane): ${lane.files.join(', ')}
FOCUS: ${lane.focus}
PLANNED ITEM: ${planItem ? planItem.item : lane.focus}

PROJECT RULES:${PROJECT_RULES}

STEPS:
1. Read the target files and understand the current state.
2. Implement ONE concrete, high-value improvement confined to your lane's files.
3. SELF-GATE: run \`${GATE_CMD}\` — if it fails, fix the failure before continuing.
4. Do NOT commit and do NOT push. Leave edits as unstaged changes.
5. Return the schema: status ('done'|'noop'|'blocked'), summary, gate output,
   files changed, and diff = full output of \`git diff\` (applies cleanly onto HEAD).
   If noop, diff is "".

Your diff is the deliverable — the caller integrates it into main sequentially with a re-gate.`
}

function gapPrompt(built) {
  const summaries = built
    .map(r => `### lane: ${r.key}\nsummary: ${r.summary}\ngate: ${r.gate || 'n/a'}\ndiff:\n${(r.diff || '').slice(0, 8000)}`)
    .join('\n\n---\n\n')
  return `You are the GAP-CHECK reviewer for a parallel self-improvement tick.
Below are diffs from ALL lanes. Your job: find what BREAKS or violates project rules across any of them.

For EACH lane diff, check:
- Does it break a cross-lane contract (shared function, type, CSS variable, config key, or response shape another lane reads)?
- Does it violate the project's stated rules or conventions?
- Does it introduce a correctness issue a per-lane self-gate would miss (each lane only sees its own diff)?
- Does it remove a test or weaken a guard without justification?

Report ONLY real, actionable findings — an empty findings array is a valid, good outcome.
Severity: P0 = breaks prod or a critical invariant, P1 = clear rule/quality miss, P2 = minor.
Give a concrete \`fix\` for each so the fixer knows exactly what to do.

LANE DIFFS:
${summaries}`
}

function fixPrompt(lane, planItem, findings) {
  const fs = findings
    .map(f => `- [${f.severity}] ${f.issue}${f.fix ? '  → FIX: ' + f.fix : ''}`)
    .join('\n')
  return `You are the **${lane.key}** FIXER, running in an isolated worktree. The gap-checker flagged issues.
Re-implement the lane's improvement from scratch on the current HEAD, editing ONLY ${lane.files.join(', ')},
and avoid every flagged issue.

ORIGINAL ITEM: ${planItem ? planItem.item : lane.focus}
FOCUS: ${lane.focus}

GAP FINDINGS TO RESOLVE:
${fs || '(none — re-verify the lane is clean)'}

PROJECT RULES:${PROJECT_RULES}

Self-gate (\`${GATE_CMD}\`). Do NOT commit or push.
Return the schema with a self-contained \`git diff\`.
If nothing is safely fixable, return status 'blocked' with empty diff and explain in summary.`
}

// ── PIPELINE ──────────────────────────────────────────────────────────────────

phase('Plan')
const plan = await agent(
  `You are the PLANNER for a parallel self-improvement tick. Produce ONE concrete, shippable
improvement per lane below, each confined to that lane's files.

PROJECT RULES:${PROJECT_RULES}

LANES:
${LANES.map(l => `- ${l.key}: files=[${l.files.join(', ')}] — ${l.focus}`).join('\n')}

Return the schema with one entry per lane. If a lane has no safe worthwhile improvement
this tick, still include it with a note in \`item\` — the implementer will noop.`,
  { label: 'plan', phase: 'Plan', effort: 'high', schema: PLAN_SCHEMA }
)
const planByKey = {}
for (const p of (plan && plan.lanes) || []) planByKey[p.key] = p
log(`Planned ${Object.keys(planByKey).length}/${LANES.length} lanes`)

phase('Implement')
const results = await parallel(
  LANES.map(lane => () =>
    agent(implementPrompt(lane, planByKey[lane.key]), {
      label: `impl:${lane.key}`,
      phase: 'Implement',
      effort: 'high',
      isolation: 'worktree',
      schema: LANE_RESULT,
    }).then(r => (r ? { ...r, key: lane.key } : null))
  )
)
const built = results.filter(Boolean).filter(r => r.status === 'done' && (r.diff || '').trim())
log(`${built.length}/${LANES.length} lanes produced a gated diff`)

if (!built.length) {
  return { lanes: [], findings: [], note: 'all lanes noop/blocked — nothing to integrate' }
}

phase('Gap-check')
const gap = await agent(gapPrompt(built), {
  label: 'gap-check',
  phase: 'Gap-check',
  effort: 'high',
  schema: GAP_SCHEMA,
})
const findings = (gap && gap.findings) || []
const p0p1 = findings.filter(f => f.severity === 'P0' || f.severity === 'P1')
log(`Gap-check: ${findings.length} finding(s) [${p0p1.length} P0/P1]`)

phase('Fix')
const flagged = new Set(p0p1.map(f => f.lane))
const finalLanes = await parallel(
  built.map(r => () => {
    if (!flagged.has(r.key)) return Promise.resolve(r)
    const lane = LANES.find(l => l.key === r.key)
    const laneFindings = findings.filter(f => f.lane === r.key)
    return agent(fixPrompt(lane, planByKey[r.key], laneFindings), {
      label: `fix:${r.key}`,
      phase: 'Fix',
      effort: 'high',
      isolation: 'worktree',
      schema: LANE_RESULT,
    }).then(fx => ((fx && (fx.diff || '').trim()) ? { ...fx, key: r.key } : r))
  })
)

const lanes = finalLanes
  .filter(Boolean)
  .filter(r => (r.diff || '').trim() && r.status !== 'blocked')
return {
  lanes: lanes.map(r => ({
    key: r.key, status: r.status, summary: r.summary,
    gate: r.gate, files: r.files, diff: r.diff,
  })),
  findings,
}
