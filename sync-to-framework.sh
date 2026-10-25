#!/usr/bin/env bash
# sync-to-framework.sh
# Called from on-stop.sh at the end of a Claude session when CCF_FRAMEWORK_SYNC=1 (maintainer only).
# Detects when global Claude config improved and syncs generic pieces to this Framework.
#
# Rules:
#   - Only syncs files that are meaningfully DIFFERENT (avoids noisy no-op commits)
#   - Parameterizes absolute paths and project-specific strings before writing
#   - Never syncs project-specific skills
#   - Commits changes to the Framework repo if anything changed

set -euo pipefail

CCF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CHANGED=0

# ── Helpers ────────────────────────────────────────────────────────────────────
_parameterize() {
  # Strip absolute user paths and project-specific strings
  sed \
    -e "s|/Users/[^/]*/|$HOME/|g" \
    -e "s|python3\.13 -m pytest tests/ -q --tb=short|\${CCF_TEST_CMD}|g"
}

_sync_file() {
  local src="$1" dest="$2" parameterize="${3:-false}"
  [ -f "$src" ] || return 0
  mkdir -p "$(dirname "$dest")"
  if [ "$parameterize" = "true" ]; then
    _parameterize < "$src" > /tmp/ccf_sync_tmp
    src=/tmp/ccf_sync_tmp
  fi
  if ! diff -q "$src" "$dest" &>/dev/null; then
    cp "$src" "$dest"
    echo "  updated: $(basename "$dest")"
    CHANGED=$((CHANGED + 1))
  fi
}

# Skills that should NOT be auto-synced to the Framework:
#   qa/progress — project-specific
#   self-improve — hand-generalized in the Framework (conditional gating); the live
#                  copy is project-shaped and would clobber the generic version
SKIP_SKILLS="qa progress self-improve"
# Hooks that are hand-generalized in the Framework and frozen from auto-sync
SKIP_HOOKS="on-stop.sh"

# Warn (instead of silently dropping) when a frozen file has drifted from its
# live counterpart, so generic improvements can be ported by hand.
_drift_notice() {
  local src="$1" dest="$2"
  [ -f "$src" ] && [ -f "$dest" ] || return 0
  _parameterize < "$src" > /tmp/ccf_sync_drift
  if ! diff -q /tmp/ccf_sync_drift "$dest" &>/dev/null; then
    echo "  NOTICE: skipped-but-drifted: $(basename "$dest") — port improvements manually via /meta-improve"
  fi
}

# ── 1. Sync hooks ──────────────────────────────────────────────────────────────
echo "[sync] hooks"
for src in "$CLAUDE_DIR/hooks/"*; do
  [ -f "$src" ] || continue
  name="$(basename "$src")"
  skip=false
  for h in $SKIP_HOOKS; do
    [ "$name" = "$h" ] && skip=true && break
  done
  if $skip; then
    echo "  skip (hand-generalized): $name"
    _drift_notice "$src" "$CCF_DIR/core/hooks/$name"
    continue
  fi
  dest="$CCF_DIR/core/hooks/$name"
  # Only refresh hooks the framework already ships; anything else in ~/.claude/hooks
  # is the user's private tooling and may hold secrets.
  if [ ! -f "$dest" ]; then
    echo "  skip (not a framework hook): $name"
    continue
  fi
  _sync_file "$src" "$dest" true
done

# ── 2. Statusline — hand-generalized (config-adaptive); frozen from auto-sync ──
# The live copy is project-shaped; the framework copy gates every segment on
# .ccf/project.env. Auto-syncing would clobber the generic version.
echo "[sync] statusline (frozen)"
_drift_notice "$CLAUDE_DIR/statusline-command.sh" "$CCF_DIR/core/statusline-command.sh"

# ── 3. Skills — FROZEN (drift-notice only) ─────────────────────────────────────
# The framework's commands/ are HAND-MAINTAINED, generic, config-driven templates.
# The live ~/.claude/commands/ copies are project-specific INSTANCES — auto-copying
# them here re-hardcodes the framework to whatever project this machine runs. That
# is exactly what clobbered the 2026-06-13 generalization (a sync overwrote 9 generic
# command files with one project's live versions and pushed them). So we NEVER
# auto-copy commands now; we only drift-notice so genuinely-generic improvements can
# be hand-ported via /meta-improve. (SKIP_SKILLS above is retained for reference.)
echo "[sync] skills (frozen — drift-notice only; framework commands are hand-maintained generic)"
for src in "$CLAUDE_DIR/commands/"*.md; do
  [ -f "$src" ] || continue
  name="$(basename "$src" .md)"
  _drift_notice "$src" "$CCF_DIR/commands/$name.md"
done

# ── 4. Sync settings structure (keys only, not values) ────────────────────────
echo "[sync] settings-fragment"
python3 - "$CLAUDE_DIR/settings.json" "$CCF_DIR/core/settings-fragment.json" <<'PYEOF'
import json, sys, os
src = sys.argv[1]
dest = sys.argv[2]
with open(src) as f: s = json.load(f)
# Build a generic fragment: keep structure, strip absolute paths
fragment = {}
if "hooks" in s:
    fragment["hooks"] = {}
    for event, entries in s["hooks"].items():
        fragment["hooks"][event] = []
        for entry in entries:
            generic = {"matcher": entry.get("matcher", ""), "hooks": []}
            for h in entry.get("hooks", []):
                cmd = h.get("command", "")
                # Replace absolute path with $HOME-relative
                cmd = cmd.replace(os.path.expanduser("~"), "$HOME")
                generic["hooks"].append({"type": h.get("type", "command"), "command": cmd})
            fragment["hooks"][event].append(generic)
if "statusLine" in s:
    sl = dict(s["statusLine"])
    if "command" in sl:
        sl["command"] = sl["command"].replace(os.path.expanduser("~"), "$HOME")
    fragment["statusLine"] = sl
for k in ("effortLevel", "theme", "skipAutoPermissionPrompt", "skipDangerousModePermissionPrompt"):
    if k in s:
        fragment[k] = s[k]
os.makedirs(os.path.dirname(dest), exist_ok=True)
cur = json.load(open(dest)) if os.path.exists(dest) else {}
if cur != fragment:
    with open(dest, "w") as f:
        json.dump(fragment, f, indent=2)
    print("  updated: settings-fragment.json")
PYEOF

# ── 5. Commit if anything changed ─────────────────────────────────────────────
if [ "$CHANGED" -gt 0 ]; then
  echo "[sync] committing $CHANGED changed file(s) to Framework repo"
  cd "$CCF_DIR"
  # Stamp the current framework version (sync never bumps it; releases do)
  VERSION=$(python3 -c "import json; print(json.load(open('.claude-plugin/marketplace.json'))['metadata']['version'])" 2>/dev/null || echo "unversioned")
  git add -- core/hooks core/settings-fragment.json
  git diff --cached --quiet || \
    git commit -m "chore(sync): propagate Claude config improvements from session $(date +%Y-%m-%d) [v$VERSION]" \
      --no-gpg-sign 2>/dev/null || true
  echo "[sync] done — $CHANGED files updated (v$VERSION)"
else
  echo "[sync] no changes detected"
fi

# ── 6. Push to GitHub — the Framework must always reach its remote ─────────────
# The Framework is a standalone product
# (github.com/erickjvazquez-dev/selfimprove-kit). Improvements discovered
# while building ANY project must land on the remote, not just commit locally.
# Push whenever the branch is ahead of its known upstream. The ahead check is
# network-free (@{upstream}); the push is non-interactive so it can never hang a
# session end, and failures (offline/auth) are non-fatal and retried next session.
cd "$CCF_DIR" 2>/dev/null && {
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo master)"
  ahead="$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)"
  if [ "${ahead:-0}" -gt 0 ]; then
    echo "[sync] pushing $ahead commit(s) to origin/$branch"
    if GIT_TERMINAL_PROMPT=0 git push origin "HEAD:$branch" 2>/dev/null; then
      echo "[sync] pushed to origin"
    else
      echo "[sync] push failed (offline / auth?) — will retry next session"
    fi
  else
    echo "[sync] remote already up to date"
  fi
}
