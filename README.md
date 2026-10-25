# Claude Code Framework

A ready-to-load self-improvement kit for **any** idea, tool, app, or project — install it
into Claude Code (or any agentic CLI), answer a few questions, and get an autonomous
loop that plans, builds, verifies, and ships toward your North Star.

Version: see `.claude-plugin/plugin.json` · Changes: `CHANGELOG.md`

---

## Install

### Path A — Claude Code plugin (recommended for Claude Code)

```
/plugin marketplace add erickjvazquez-dev/selfimprove-kit   # or a local path
/plugin install selfimprove-kit@selfimprove-kit
```

On Claude Code 2.1.275+ this is one step:
`/plugin install selfimprove-kit --marketplace erickjvazquez-dev/selfimprove-kit`.
Commands are namespaced `/selfimprove-kit:<command>` (e.g. `/selfimprove-kit:self-improve`).
The plugin was previously named `claude-code-framework`; Claude Code reserves `claude-*`
plugin names, so that name no longer installs — reinstall under the new name.

Then scaffold your project (writes `.ccf/project.env`, `CLAUDE.md`, `GOAL.md`, and
installs + wires the statusline — the plugin already provides commands, agents, and
hooks, but Claude Code has no statusLine plugin component, so the scaffold step ships it):

```bash
cd ~/your-project
bash ~/path/to/claude-code-framework/setup.sh --scaffold-only
```

### Path B — any CLI (Claude Code optional)

```bash
cd ~/your-project
bash ~/Claude\ Code\ Framework/setup.sh
```

The full wizard installs hooks to `~/.claude/hooks/`, skills to `~/.claude/commands/`,
patches `~/.claude/settings.json`, and scaffolds the project. Skills are plain markdown
and hooks are plain bash — they work with any agentic CLI that reads them.

**Loading skills into a non-Claude-Code CLI.** The skills are plain instruction
markdown. Bundle them into one file your CLI loads as rules/context:

```bash
bash ~/Claude\ Code\ Framework/scripts/export_skills.sh ./CCF_SKILLS.md
```

Then point your CLI at it — e.g. Cursor `.cursorrules`, Codex `AGENTS.md`,
Gemini CLI `GEMINI.md`, or paste into a system prompt. Invoke a skill by name
("run self-improve", "run gap"). Claude-Code helpers a few skills mention
(`$ARGUMENTS`, `ScheduleWakeup`, `AskUserQuestion`) map to your CLI's own
argument/scheduling/prompt mechanisms.

### Path C — Docker (nothing installed on the host)

The whole framework — commands, agents, hooks, scripts, tests, setup wizard, **and the
Claude Code CLI** — ships in one container image. Useful for trying it out, running QA
against a project, or CI:

```bash
cd ~/Claude\ Code\ Framework/docker
docker compose run --rm framework    # interactive shell with claude + the framework
docker compose run --rm tests        # full self-test inside the container
```

See [Docker](#docker) below for details.

> Pick **one** path per machine. Both A and B at once would register the Stop hook twice
> (a double-fire guard makes this harmless, but one path is cleaner).

---

## Project categories

The wizard asks what kind of project this is; everything downstream adapts:

| Category | Questions asked | Loop behavior |
|---|---|---|
| `app` | all (tests, live URL, deploy) | full: health curl, live E2E, test gate, deploy |
| `library` | tests only | local smoke + test gate; no health/deploy |
| `cli` | tests only | local smoke + test gate; no health/deploy |
| `idea` | name, north star, optional repo | doc-structure checks + review gate; no code gates |

Gating variables (in `.ccf/project.env`):

| Variable | Gates |
|---|---|
| `CCF_PROJECT_CATEGORY` | overall loop shape; `idea` ⇒ no code gates |
| `CCF_LIVE_URL` | health check, live E2E, post-deploy verify (empty ⇒ skipped) |
| `CCF_TEST_CMD` | test gate; empty ⇒ review gate (`/critical-checks` + diff self-review) |
| `CCF_GITHUB_REPO` | CI / security-workflow / unpushed-commit checks (empty ⇒ skipped) |
| `CCF_DEPLOY_TARGET` / `CCF_DEPLOY_CMD` | deploy on ship; `local`/empty ⇒ commit only |
| `ANTHROPIC_API_KEY` | computer-use QA; empty ⇒ SKIP, not FAIL |

A missing prerequisite always means **SKIP, never FAIL**.

---

## What's included

| Component | Purpose |
|---|---|
| `.claude-plugin/` | Plugin manifest + single-plugin marketplace (release label in marketplace `metadata.version`) |
| `commands/` | 18 skills: self-improve, qa, gap, goal, speckit.*, snapshot, restore, rollback, critical-checks, status… |
| `agents/` | `stack-guardian` — cost/stack gatekeeper, derives the approved stack from project config |
| `hooks/hooks.json` | Plugin Stop-hook wiring → `core/hooks/on-stop.sh` |
| `core/hooks/` | `on-stop`, `post-commit-summary`, `no-secrets-check` |
| `core/statusline-command.sh` | Adaptive status bar — segments appear only for configured `.ccf` keys (CI if `CCF_GITHUB_REPO`, health if `CCF_LIVE_URL`) |
| `scaffold/` | Templates: `CLAUDE.md`, `GOAL.md`, `.ccf/project.env` |
| `scripts/` | Optional helper scripts a project can add (e.g. health checks, headless-browser/visual QA runners) |
| `docker/` | Full framework image: Claude Code CLI + headless Chrome + Playwright + Python, with compose services for shell/tests/health/QA |
| `setup.sh` | Wizard (full or `--scaffold-only`) |
| `sync-to-framework.sh` | Pulls generic skill/hook improvements back into this repo |

---

## Skills reference

| Skill | What it does |
|---|---|
| `/self-improve` | Autonomous loop: health → security → verify → improve → repeat, gated by project category |
| `/qa` | Product QA: parallel sub-agents test the real product (or docs, for idea projects) |
| `/gap` | Gap detection: finds missing infrastructure before you notice |
| `/goal` | Executes the next unchecked GOAL.md item |
| `/meta-improve` | Improves the loop itself from observed friction |
| `/critical-checks` | Pre-commit safety audit (secrets, syntax, auth) |
| `/speckit.specify` → `/speckit.plan` → `/speckit.implement` → `/speckit.checklist` | Spec-driven development workflow |
| `/snapshot "label"` / `/restore` / `/rollback` | Named recovery points, non-destructive restore, safe revert |
| `/status` | Live environment inspector |
| `/stop-loops` | Stop all self-paced loops + monitors in the active session (kill switch for `/loop /self-improve`) |
| `/find-skill` | Routes a request to the right skill |

---

## The self-improvement loop

1. **Scaffold** — `GOAL.md` holds the North Star and a Now/Next/Later backlog.
2. **Loop** — `/self-improve` (interactive `/loop`, or a standing cloud cron) runs
   gap-first: `/gap` → health → security → verify gate → improve one item → ship → report.
3. **Verify gate** — tests if you have them, structured review if you don't. Either way
   nothing ships unverified (Rule 14).
4. **Recover** — `/snapshot` before risky work; `/restore` or `/rollback` if it goes wrong.
5. **Evolve** — `/meta-improve` feeds loop friction back into the backlog;
   `sync-to-framework.sh` propagates generic skill improvements back to this repo.

---

## Walkthrough: self-improving an idea (no code at all)

The loop is not just for software. Example — a book project:

```bash
mkdir ~/my-book && cd ~/my-book && git init
bash ~/Claude\ Code\ Framework/setup.sh        # pick category 4) idea
# name: my-book · north star: "A practical field guide to X that a beginner
# can apply in a weekend"
```

The wizard skips every code question (no test command, no live URL, no deploy) and
writes `CCF_PROJECT_CATEGORY="idea"`. Then open your CLI in `~/my-book`:

1. **Seed the backlog** — put chapters/sections in `GOAL.md` under Now/Next/Later:
   `- [ ] C01 Outline — promise, audience, table of contents`
2. **Run `/loop /self-improve`** — each iteration the loop:
   - checks doc structure instead of a health endpoint (GOAL.md parses, every file
     it references exists, nothing truncated),
   - uses the **review gate** instead of a test gate: before any commit it runs
     `/critical-checks` and re-reads the diff against the GOAL.md item's acceptance
     criteria,
   - picks the next unchecked item, drafts/revises it, commits with a Conventional
     Commit, and reports in ≤10 lines.
3. **`/qa` in content mode** — sub-agents check internal links, structural
   consistency, terminology/voice drift across chapters, and whether items marked
   done are actually reflected in the text.
4. **Recover like code** — `/snapshot "before restructure"` before a big rewrite;
   `/restore` if the new direction is worse.

The same shape works for a business plan, a research survey, or a product spec —
the deliverable is a verified document instead of a deployed service.

---

## Keeping repos that use the kit current

Cloud sessions (claude.ai/code) don't install plugins a repo declares in
`.claude/settings.json`, so each repo that uses the kit carries a copy of its skills in
`.claude/commands/`. `consumers.json` lists those repos, and a weekly Routine runs
`scripts/sync_consumers.py` on each one and opens a PR with auto-merge when it drifts:

- A copy that matches any version the kit ever shipped is replaced with the current one.
- A customized copy is never overwritten; the PR lists the kit commits it hasn't received.
  A customized `self-improve.md` becomes `self-improve-<repo>.md`, which the generic
  engine's routing gate dispatches to.
- Missing kit skills are added, and the `selfimprove-kit` plugin is enabled with
  `autoUpdate` for local CLI sessions (per-repo options in `consumers.json`).

Run it by hand with `python3 scripts/sync_consumers.py --consumer ../my-repo --add-missing
--rename-custom-loop --enable-plugin`. To add a repo, append it to `consumers.json`.

## Versioning & maintenance model

- The plugin has no pinned `version`, so every commit merged to `master` reaches users
  (Claude Code versions an unpinned git plugin by commit SHA; enable `autoUpdate` on the
  marketplace to pull it). The release label lives in `.claude-plugin/marketplace.json`
  `metadata.version`; releases are deliberate `chore(release): vX.Y.Z` commits that bump
  it and CHANGELOG.md together. Sync commits stamp `[vX.Y.Z]` but never bump.
- **Auto-synced files** — framework hooks already in `core/hooks/` flow in from the
  maintainer's machine via `sync-to-framework.sh`, parameterized (`${CCF_*}`) on the way.
  The Stop hook runs it only when `CCF_FRAMEWORK_SYNC=1` is set (maintainer opt-in), since
  it commits and pushes to this repo; other files in `~/.claude/hooks` are never synced.
- **Frozen (hand-generalized) files** — `commands/self-improve.md`, `commands/qa.md`,
  `core/hooks/on-stop.sh`: project copies are too project-shaped to auto-sync, so the
  sync prints a `skipped-but-drifted` NOTICE and improvements are ported deliberately
  via `/meta-improve`.

---

## Core rules (enforced by hooks + skills)

1. **Run `/critical-checks` before every commit** — never skip
2. **Continuous product testing** — `/qa` tests the real product, not just HTTP codes
3. **Spec before building** — any change touching >3 files needs `/speckit.specify` first
4. **Surgical commits** — one purpose per commit, Conventional Commits format
5. **Full autonomy in loops** — `/self-improve` never pauses to ask; it acts and reports
6. **Push before CI check** — unpushed commits mean CI is testing stale code
7. **Diagnose CI failures** — get the log, find the root cause, fix it
8. **No speculative abstractions** — build minimum code that solves the problem
9. **One stack** — no redundant paid services; `stack-guardian` vets every addition
10. **SKIP is not FAIL** — missing config skips a check instead of failing it

---

## Skill security scanning (Rule 15)

Agent skills run with implicit trust, so the framework scans its own `commands/` and
`agents/` for malicious patterns (prompt injection, credential exfiltration, remote
script execution, MCP tool poisoning) using [NVIDIA SkillSpector](https://github.com/NVIDIA/SkillSpector)
— a free, Apache-2.0, fully-local scanner. It's an optional dependency: when installed,
`tests/run.sh` runs a static (`--no-llm`) scan and fails only on **new** HIGH/CRITICAL
findings not in `tests/skillspector_baseline.json` (by-design autonomy patterns and
false positives are triaged there with notes). Install it with:

```bash
python3 -m venv .venv-skillspector
.venv-skillspector/bin/pip install 'git+https://github.com/NVIDIA/SkillSpector.git'
```

Use it the same way before installing any **third-party** skill: `skillspector scan
https://github.com/user/some-skill`.

---

## Docker

The image in `docker/` packages the **entire framework** — commands, agents, hooks,
core, scaffold, scripts, tests, `setup.sh`, and the Claude Code CLI (native binary) —
on the Playwright base, so everything runs without installing anything on the host
(beyond a container runtime, e.g. Docker Desktop or colima).

All services run from the `docker/` directory (Compose v2.24+):

```bash
cd ~/Claude\ Code\ Framework/docker

docker compose run --rm framework    # interactive shell: claude CLI + full framework
docker compose run --rm tests        # framework self-test (bash tests/run.sh),
                                     # incl. `claude plugin validate` in-container
docker compose run --rm health       # health check against CCF_LIVE_URL
docker compose run --rm qa           # headless browser QA
```

**Secrets and config are runtime-only.** `.dockerignore` excludes `.ccf/` from the
build context, so `project.env` (which holds `ANTHROPIC_API_KEY`) can never be baked
into an image layer. Compose injects it at runtime via `env_file` when present —
`required: false`, so the image also runs in clean environments. To use the Claude
CLI interactively, pass the key: `ANTHROPIC_API_KEY=... docker compose run --rm framework`.

CI mirrors this end-to-end: the `docker` job in `.github/workflows/ci.yml` builds the
image, runs the self-test inside it, smoke-tests the default command (`health_check.py`),
asserts the Claude CLI is present, and asserts no `.ccf`/`.git` leaked into the image.

> Note: the `tests` service deliberately runs **without** the project env injected —
> the self-test simulates a config-less project, and injected `CCF_*` vars would
> contaminate its assertions.

---

## Requirements

- macOS or Linux · git · Python 3.10+
- Claude Code CLI — optional (recommended); any agentic CLI that reads markdown skills works
- `gh` CLI (CI checks) — optional
- `playwright` (browser QA) — optional: `pip install playwright && playwright install chromium`
- `cliclick` (Computer Use QA, macOS) — optional: `brew install cliclick`
- Docker + Compose v2.24+ (containerized path) — optional: replaces all of the above
  except git; `brew install colima docker docker-compose && colima start` works on macOS
