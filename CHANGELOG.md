# Changelog

All notable changes to selfimprove-kit are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/). Release label:
`metadata.version` in `.claude-plugin/marketplace.json` — the plugin itself is unpinned so
users receive every commit on the default branch; releases are deliberate
`chore(release): vX.Y.Z` commits that bump the label and this file.

## [1.2.0] — 2026-10-25 — first public release

The kit was extracted in June 2026 from an autonomous improvement loop running daily on a
production project, then generalized into this project-agnostic plugin. This is its first
public release; earlier history lived in a private repository.

### Included
- **21 skills** (`commands/`) — `/self-improve` (autonomous health → QA → improve → ship loop
  with adaptive idle-backoff and 529 resilience), `/qa`, `/gap` (50+ rules learned from real
  incidents), `/speckit.*` (spec → plan → implement → checklist), `/snapshot`, `/restore`,
  `/rollback`, `/critical-checks`, `/security-checklist`, `/lab`, `/status`, `/stop-loops`,
  `/meta-improve`, `/progress`, `/goal`, `/find-skill`, `/optimize`, `/preprocess`.
- **Config-gated engine** — `setup.sh` writes `.ccf/project.env` for one of four categories
  (app / library / cli / idea); every step gates on config, and SKIP is never FAIL.
- **Hooks + statusline** — Stop hook for session memory and loop state; adaptive statusline.
- **Parallel lanes workflow** (`.claude/workflows/parallel-lanes.js`) — worktree-isolated
  lanes, collective gap-check, sequential gated integration.
- **Consumer sync** (`scripts/sync_consumers.py`, `consumers.json`) — keeps repos that carry
  copies of the kit's skills current: replaces unmodified copies, never overwrites customized
  ones, reports the kit commits they miss.
- **Self-test harness** (`bash tests/run.sh`) — syntax, manifests, reserved plugin names,
  unpinned version, skill governance (frontmatter description + contract eval per skill),
  personal-path guard, Stop-hook leak test, wizard E2E, consumer-sync selftest.

### Security
- The Stop hook's framework sync is a maintainer opt-in (`CCF_FRAMEWORK_SYNC=1`), stages
  explicit paths only, and never syncs hooks the kit does not ship.
- No personal data, private project data or credentials are included; `.ccf/project.env`
  (which may hold keys) is gitignored.
