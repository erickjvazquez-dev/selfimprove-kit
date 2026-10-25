#!/bin/bash
# CI-ZERO-COST-COMBO layer 1 (2026-06-12): fast invariant gate before every push.
# Mirrors the deploy build gate + project test/invariant guards (~1-2 min).
# Config-driven: reads .ccf/project.env so each project supplies its own gate
# commands. With no config (or an idea/library project) it degrades to a no-op.
# Bypass (emergencies only): git push --no-verify
set -e
cd "$(git rev-parse --show-toplevel)"

# Load project config so the gate adapts to what's actually used.
[ -f ".ccf/project.env" ] && . ".ccf/project.env" 2>/dev/null || true

# Optional build smoke — only when the project declares one.
if [ -n "${CCF_BUILD_SMOKE_CMD:-}" ]; then
  echo "[pre-push] build_smoke..."
  eval "$CCF_BUILD_SMOKE_CMD" >/tmp/ccf_prepush_smoke.log 2>&1 || {
    echo "[pre-push] BLOCKED — build_smoke failed (the deploy would fail too):"
    tail -10 /tmp/ccf_prepush_smoke.log
    exit 1
  }
fi

# Invariant guards — the project's test command (or a focused guard subset).
GUARD_CMD="${CCF_PREPUSH_CMD:-${CCF_TEST_CMD:-}}"
if [ -n "$GUARD_CMD" ]; then
  echo "[pre-push] invariant guards..."
  eval "$GUARD_CMD" >/tmp/ccf_prepush_guards.log 2>&1 || {
    echo "[pre-push] BLOCKED — invariant guards failed:"
    tail -5 /tmp/ccf_prepush_guards.log
    exit 1
  }
fi

echo "[pre-push] gate OK"
