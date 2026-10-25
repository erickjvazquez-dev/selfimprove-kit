#!/usr/bin/env bash
# Bundle the framework's skills into a single markdown file that any agentic CLI
# can load as a rules/context file (Cursor .cursorrules, Codex AGENTS.md,
# Gemini GEMINI.md, or pasted into a system prompt).
#
# Usage: bash scripts/export_skills.sh [output_file]
#   default output: ./CCF_SKILLS.md
#
# Claude Code reads commands/*.md natively as slash commands; this is the
# plain-markdown path for everything else.
set -euo pipefail
CCF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(pwd)/CCF_SKILLS.md}"

{
  echo "# Claude Code Framework — Skills (bundled for any CLI)"
  echo
  echo "These are the framework's skills as plain instructions. Invoke one by name"
  echo "(e.g. \"run self-improve\", \"run gap\"). Some reference Claude Code helpers"
  echo "(\$ARGUMENTS, ScheduleWakeup, AskUserQuestion) — treat those as 'use your"
  echo "CLI's equivalent for arguments / scheduling / asking the user'."
  echo
  echo "---"
  echo
  for f in "$CCF_DIR/commands/"*.md; do
    [ -f "$f" ] || continue
    echo "## skill: $(basename "$f" .md)"
    echo
    cat "$f"
    echo
    echo "---"
    echo
  done
} > "$OUT"

COUNT=$(ls "$CCF_DIR/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
echo "exported $COUNT skills → $OUT ($(wc -l < "$OUT" | tr -d ' ') lines)"
