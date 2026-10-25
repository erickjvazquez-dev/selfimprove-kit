# claude-code-framework — Goals & Roadmap

**North Star:** A ready-to-load self-improvement kit that lets Claude Code or any CLI plan, build, verify, and ship any idea, tool, or app autonomously — and that keeps itself current: every month it re-checks its own skills, CLAUDE.md, and hooks against the latest Claude models and deletes, updates, upgrades, or adds whatever is needed so it performs at its best

---

## Blockers
<!-- P0 items added here by /qa and /self-improve when critical bugs are found -->

---

## Now (current sprint)

- [x] F01 Self-test harness `tests/run.sh` — every shell script parses, every Python script compiles, every JSON manifest validates, plugin/marketplace versions agree, every command file has a title (becomes `CCF_TEST_CMD`)
- [x] F02 CI on GitHub — run `tests/run.sh` on every push/PR to `erickjvazquez-dev/selfimprove-kit`
- [x] F03 Wizard E2E test — scripted non-interactive `setup.sh` runs for all four categories in a sandbox HOME, asserting `.ccf/project.env` gating values
- [x] F04 Template lint (shipped inside F01 harness — template-placeholder check) — `scaffold/*.template` placeholders (`{{CCF_*}}`) all resolvable from project.env keys; fail on unknown placeholders

- [ ] F19 Monthly model-fit review — once per calendar month (and after any self-upgrade, e.g. a new Claude model or Claude Code release), the loop audits every skill in `commands/`, the CLAUDE.md rules + scaffold template, and every hook in `hooks/` + `core/hooks/` against the latest Claude models and Claude Code features, and classifies each as KEEP / DELETE (now redundant — the model or harness does it natively) / UPDATE (stale API, model ID, or CLI behavior) / UPGRADE (a newer native feature does it better), plus ADD (a new capability worth adopting). Track `last_model_review` (month + model ID) in the per-project heartbeat so it runs once per month, write the verdicts to GOAL.md as actionable items, and ship them through the normal gated loop. Spec first (Rule 3).
- [ ] F20 Consumer propagation — keep every repo that uses the kit (registry: `consumers.json`) on the latest kit automatically: enable the `selfimprove-kit` plugin per repo with `autoUpdate`, retire vendored copies of generic skills/hooks that shadow it (keep genuinely project-specific ones, or move them to `.ccf/hooks/`), and run a recurring check that opens an upgrade PR per repo when it drifts. Spec: `.claude/specs/consumer-sync.md`; tool: `scripts/sync_consumers.py`. Progress 2026-10-11: tool + registry shipped; first sync PRs opened across the maintainer's repos; weekly Routine created. Same gates as the loop (tests + /critical-checks per repo). Cloud sessions do not install repo-declared plugins — the in-repo copies are what cloud sessions use.
- [x] F14 Loop kill switch — `/stop-loops` cancels session wakeups (CronDelete) + monitors (TaskStop) + sets a STOP_LOOPS sentinel; self-improve Step 0 honors it (halt-without-reschedule on wakeup re-entry, clear-and-continue on manual restart)

## Next

<!-- F19 first pass (2026-10-10) — model-fit verdicts; each ships through the normal gate -->
- [ ] F21 DELETE `/find-skill` (Claude Code routes skills by `description:` natively), `/optimize` + `/preprocess` (need an MCP server the kit doesn't ship; compression fights prompt caching; Claude reads PDFs/images natively), `/goal` (duplicates self-improve Step 4). Update references + evals + export count.
- [ ] F22 UPGRADE `/critical-checks` — delegate review to native `/code-review` + `/security-review`; keep only project-invariant checks.
- [ ] F23 UPGRADE speckit.* — merge the four into one `/spec` built on native plan mode + task list.
- [ ] F24 UPDATE `/gap` — move the 71-rule Gap Rules Registry (~25k tokens loaded every tick, mostly one project's resolver lore) into an on-demand reference file; migrate to `skills/<name>/SKILL.md` layout.
- [ ] F25 UPGRADE evals — replace string-match contract evals with `claude plugin eval` cases that run the skill and grade behavior.
- [ ] F26 UPGRADE hooks — wire `no-secrets-check.sh` + `pre-push-gate.sh` as plugin PreToolUse hooks on `git commit`/`git push` (Rule 1 enforced by harness); update `summarize_commit.py` model `claude-haiku-4-5-20251001` → `claude-haiku-5-5` and drop `/opt/homebrew/bin/python3`, or delete the commit-summary hook.
- [ ] F27 UPDATE `core/settings-fragment.json` — stop forcing theme, `effortLevel: xhigh` and permission-prompt skips on users.
- [ ] F28 Evaluate removing CLAUDE.md Rules 8/9 (current models default to them) — A/B with an eval before deleting; fix duplicate `/gap` row and `curl -sf /health` with no URL in `scaffold/CLAUDE.md.template`.
<!-- GW02 gap findings (2026-10-10) -->
- [ ] G01 (P1) statusline `stat -f %m || stat -c %Y` breaks on GNU (prints fs info) — use `stat -c %Y || stat -f %m`; add a two-render Linux test.
- [ ] G02 (P1) `on-stop.sh` pastes `$LAST_COMMIT` into Python source — an apostrophe in a commit message silently skips the loop-state write; pass via env/argv.
- [ ] G03 (P1) `setup.sh` re-run resets project type + deploy target (defaults ignore stored values), writes `project.env` unescaped (a `"` breaks sourcing), strips the memory slug's leading dash, and aborts when `~/.claude` is missing.
- [ ] G04 (P1) harness gaps — `core/practice/*.py`, `hooks/*.sh`, `scripts/*.sh`, `bin/*` not syntax-checked; `tests/test_*.py` never run (9 fail off the owner's machine); wizard E2E hides setup.sh's exit code.
- [ ] G05 (P1) personal/employer data in `data/practice/*.jsonl` ships in the plugin + Docker image; importer hardcodes project names and reads `CCF_CATEGORY`/`CCF_TYPE` instead of `CCF_PROJECT_*`.
- [ ] G06 (P2) README says 18 skills (21); `CCF_BUILD_SMOKE_CMD`/`CCF_PREPUSH_CMD`/`CCF_SMOKE_CMD`/`CCF_PRACTICE_DB` missing from setup/template/README (MANDATORY RULE).
- [x] F05 `chore(release): v1.1.0` flow rehearsal (shipped for real — tag claude-code-framework--v1.1.0) — bump plugin.json + marketplace.json + CHANGELOG in one commit, tag with `claude plugin tag`
- [x] F06 Linux compatibility pass — `stat -f` → portable `stat -f || stat -c` fallback in statusline (both copies); osascript already guarded; CI job already runs on ubuntu-latest
- [x] F07 Plugin install smoke — manifest name/source agreement, agent frontmatter, `claude plugin validate` when CLI present (SKIP in CI until claude available there)
- [x] F08 Idea-category walkthrough doc — README "Walkthrough: self-improving an idea" section

## Later

- [ ] F09 Public release readiness — [x] LICENSE file (MIT) added + harness consistency check; [ ] make repo public (user-gated); [ ] marketplace install from GitHub tested (needs public repo)
- [x] F10 Second-CLI path — `scripts/export_skills.sh` bundles all skills into one rules/context file (Cursor/.cursorrules, Codex/AGENTS.md, Gemini/GEMINI.md); README "Loading skills into a non-Claude-Code CLI" documents the load path; harness verifies the bundle. (Full live run-through in a second CLI still pending a runtime, but the enabler + docs ship.)
- [x] F11 Telemetry-free loop metrics — `scripts/loop_metrics.py` (per-ISO-week shipped/total by commit type, git-log only)
- [x] F12 Skill security gate (Rule 15) — NVIDIA SkillSpector static scan of commands/ + agents/ in the test harness with a triaged baseline; adversarially verified (injected malicious skill → gate fails; removed → passes)
- [x] F13 Adaptive + plugin-delivered statusline — config-gated segments (CI only if CCF_GITHUB_REPO, health only if CCF_LIVE_URL); de-hardcoded project/host/personal paths; --scaffold-only now installs+wires it (plugin can't ship statusLine); frozen from auto-sync; verified across app/library/idea profiles

---

## Loop Improvements
<!-- /meta-improve writes loop-friction fixes here -->

- [x] F15 Blocker-freshness report — `scripts/check_blockers.py` parses `## Blockers` and reports each open item, classifying those marked `EXPECTED`/`[expected]` (accepted ongoing constraints, e.g. budget-gated CI) separately from ones to review. **Report-only: never auto-clears** — a blocker asserting "CI can't run" can be legitimate (e.g. a shared Actions-minutes budget cap, not a stale/false blocker; corrected 2026-08-26 per owner). Wired into `tests/run.sh` (`--selftest` gate + live report) and into self-improve Step 0 (report-only diagnostics against `${CCF_PROJECT_DIR}/GOAL.md`).
- [x] F16 Installed-skill drift guard — `scripts/check_skill_drift.py` flags generalized skills (present in `commands/`) whose installed `~/.claude/commands/<name>.md` copy re-hardcodes a project (absolute user paths, project names, deploy URLs, project repo). Report-only (project instances legitimately differ) and SKIP-not-FAIL when `~/.claude/commands` is absent; harness runs `--selftest` (gates the tool) + a live report. On the maintainer's machine it detected 11 shadowed skills — exactly why a /meta-improve run loaded a project-hardcoded instance instead of the generalized one. Complements the session-end `_drift_notice` in `sync-to-framework.sh` by surfacing drift in the test gate/CI. Also wired into self-improve Step 0 (report-only diagnostics, SKIP if framework scripts absent).
- [x] F17 Retroactive eval backfill — added `commands/evals/<skill>.json` contract evals for all 18 grandfathered skills and **emptied** `tests/skill_eval_baseline.json` (shrink-only ratchet now at zero: 21/21 skills carry a valid eval). Each eval asserts pre-verified invariant strings (command name + a domain token) so skill-rot fails the gate. Applies "skill has no eval = gap" (GAP-047) retroactively. (Separate `skill_governance_baseline.json` frontmatter-description backfill remains — 18 grandfathered — a distinct next target.)

- [x] F18 Frontmatter-description backfill — added a YAML `description:` to all 18 grandfathered skills (SKILL_SCHEMA.md format) and **emptied** `tests/skill_governance_baseline.json`. Both skill-governance gates are now fully closed: 21/21 skills have a `description` AND a contract eval, 0 grandfathered on either. Any new skill must ship with both or be grandfathered explicitly (shrink-only ratchet). Sibling to F17.

## Meta-Improve Counter
Last run: 2026-08-26 | Items added: 3 (F15–F17); F15 + F16 shipped same day (scripts + harness); F15 reframed report-only for accepted constraints | Next run: after 5 more goal completions

---

## MANDATORY RULE
Any change to wizard questions, `CCF_*` variables, or gating behavior must update ALL of:
setup.sh · scaffold/.ccf/project.env.template · commands/self-improve.md gating table · commands/qa.md gating section · README tables.

---

## Gaps Found
<!-- /gap writes gap waves here — GW01, GW02, etc. -->
- GW01 (2026-06-09): framework did not dogfood itself — no scaffold, no tests, no CI. → F01/F02 + scaffold committed this iteration.
- GW02 (2026-10-10): 10 verified gaps. P0s fixed same day — Stop-hook sync could push private hooks/secrets (now `CCF_FRAMEWORK_SYNC=1` opt-in) and `/snapshot`/`/restore` hardcoded one user's home path (now `$REPO_DIR`, harness guard added). Also fixed: plugin name `claude-code-framework` rejected as reserved → renamed `selfimprove-kit`. Rest → G01–G06.
