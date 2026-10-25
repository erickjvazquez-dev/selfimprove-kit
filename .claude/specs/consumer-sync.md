# Spec — Consumer sync (F20)

**Goal:** every repo that uses the kit runs the latest kit in every session, local and cloud, without anyone copying files by hand.

## Context
Cloud sessions do not install plugins a repo declares in `.claude/settings.json`
(docs: cloud-environments, "What carries over"). Repos that want the kit in cloud
therefore carry copies of its skills and hooks in `.claude/`. Those copies froze at
whatever version was pasted in, so some still run the hardcoded `/snapshot` and other
fixed bugs. Repos with no copies have no kit at all in cloud sessions.
The plugin also pinned `"version": "1.2.0"`, so even local plugin users stopped
receiving commits.

## Decisions (owner, 2026-10-11)
- Cloud path: sync copies into each repo by PR; also enable the plugin with
  `autoUpdate` for local CLI sessions.
- Customized copies are never overwritten. A customized `self-improve.md` is renamed
  `self-improve-<repo>.md` (the routing gate already dispatches to it) and the generic
  engine is added; kit fixes the customized copies miss are listed in the PR.
- Upgrades land as PRs with auto-merge when green.
- Plugin tracks commits: no plugin-level `version`.

## Acceptance criteria
1. `consumers.json` lists each consumer repo with its skills dir and options.
2. `scripts/sync_consumers.py --consumer <path>` classifies each kit-named file in the
   consumer as **pristine** (its blob matches some historical kit version of that
   file) or **customized**; pristine → replaced with the kit's current version;
   customized → untouched and reported with the kit commits it has not received.
3. With `add_missing`, kit skills absent from the consumer are added.
4. With `rename_custom_loop`, a customized `self-improve.md` becomes
   `self-improve-<name>.md` and the generic engine is added in its place.
5. With `enable_plugin`, `.claude/settings.json` gains the `selfimprove-kit`
   marketplace (GitHub source, `autoUpdate: true`) and `enabledPlugins` entry, keeps
   every other key, and drops any stale `claude-code-framework@…` entry.
6. A run that changes nothing writes nothing (no stamp-only churn). A run that changes
   something records the kit SHA in `.claude/selfimprove-kit.json`.
7. `tests/run.sh` runs a selftest covering criteria 2–6.
8. `plugin.json` and the marketplace entry carry no `version`; the harness fails if
   one is re-added.
9. A weekly Routine runs the sync for every consumer and opens or refreshes one PR
   per drifted repo with auto-merge enabled.

## Out of scope
- Converting customized copies into generic + `.ccf/hooks/` (flagged only).
- Org-level managed settings (needs an Owner on a Team/Enterprise plan).
- Wiring vendored hooks into a consumer's `settings.json` where they are not wired.
- Repos that do not use the kit.

## Risk flags
- A repo whose `.claude/` is the owner's global `~/.claude`: no adds, no
  renames, no plugin enable there — pristine updates only.
- Auto-merge needs the consumer repo to allow it; where it can't be enabled the PR
  stays open and the Routine reports it.
