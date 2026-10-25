#!/bin/bash
# Claude Code status line — adapts to the project's .ccf/project.env.
# Row 1 = identity (user@host cwd [branch] model ctx time) — always shown.
# Row 2 = RUNNING — CI only if CCF_GITHUB_REPO; health only if CCF_LIVE_URL; + live agents/loops.
# Row 3 = LOADED — installed skills / plugins / rules + last commit.
#
# Hand-maintained in the framework (frozen from auto-sync). Every project-specific
# segment is gated on configuration, so unconfigured segments simply disappear
# rather than showing "?". A library or idea project shows a clean two-row line.
input=$(cat)

cwd=$(echo "$input"       | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)
model=$(echo "$input"     | jq -r '.model.display_name // empty' 2>/dev/null)
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty' 2>/dev/null)
session_name=$(echo "$input" | jq -r '.session_name // empty' 2>/dev/null)

# Bridge context % to the Stop hook (on-stop.sh reads this for <20% auto-clear).
if [ -n "$remaining" ]; then
  printf '%.0f' "$remaining" > "$HOME/.claude/ctx_pct" 2>/dev/null
fi

# Load project config so segments can adapt to what's actually used.
[ -n "$cwd" ] && [ -f "$cwd/.ccf/project.env" ] && . "$cwd/.ccf/project.env" 2>/dev/null

USER_HOST="$(whoami)@$(hostname -s)"
TIMESTAMP="$(date +%H:%M:%S)"

# --- Git branch + last commit (generic) ---
git_branch=""; last_commit=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null \
    || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  last_commit=$(git -C "$cwd" log -1 --format="%ar" 2>/dev/null)
fi

# ── LIVE: what is RUNNING RIGHT NOW (generic) ─────────────────────────────────
# Count genuine Claude Code CLI processes by EXACT exe name, then drop 1 for this
# session. `-f "claude"` (old) also matched the Claude DESKTOP app (Claude Helper),
# every ~/.claude/… path, and the statusline's own render shells — massively
# over-counting. `-x claude` matches only comm=="claude" (the CLI), so this reflects
# OTHER running Claude Code processes; in-process sub-agents are not OS-visible.
AGENTS_RUNNING=$(pgrep -x "claude" 2>/dev/null | wc -l | tr -d ' ')
AGENTS_RUNNING=$(( AGENTS_RUNNING > 0 ? AGENTS_RUNNING - 1 : 0 ))
LOOPS_RUNNING=$(pgrep -f "ScheduleWakeup" 2>/dev/null | wc -l | tr -d ' ')
# Per-project local loop (additive, isolated). A repo with its own loop heartbeat
# at ~/.claude/loops/<CCF_PROJECT_NAME>.json owns the local-loop segment with a
# project-specific label (e.g. "/self-improve myproject"), so concurrent per-repo
# loops are distinguishable per session. Repos WITHOUT such a file fall through to
# the global loop-state.json path below — completely unchanged.
PROJ_LOOP_LABEL=""
if [ -n "${CCF_PROJECT_NAME:-}" ] && [ -f "$HOME/.claude/loops/$CCF_PROJECT_NAME.json" ]; then
  _plf="$HOME/.claude/loops/$CCF_PROJECT_NAME.json"
  _plage=$(( $(date +%s) - $(stat -f %m "$_plf" 2>/dev/null || stat -c %Y "$_plf" 2>/dev/null || echo 0) ))
  if [ "$_plage" -lt 10800 ]; then # fresh within the 3h self-pace ceiling
    PROJ_LOOP_LABEL=$(python3 -c "import json,os;d=json.load(open(os.path.expanduser('~/.claude/loops/$CCF_PROJECT_NAME.json')));print(d.get('label') or '/self-improve $CCF_PROJECT_NAME')" 2>/dev/null)
    [ -z "$PROJ_LOOP_LABEL" ] && PROJ_LOOP_LABEL="/self-improve $CCF_PROJECT_NAME"
  fi
fi

# ── INVENTORY: read from cache if fresh (< 10 s), else compute live ───────────
CACHE="$HOME/.claude/statusline-cache.json"
if [ -f "$CACHE" ] && [ $(( $(date +%s) - $(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0) )) -lt 10 ]; then
  SKILLS_TOTAL=$(python3 -c "import json; print(json.load(open('$CACHE'))['skills'])" 2>/dev/null || echo 0)
  PLUGINS_TOTAL=$(python3 -c "import json; print(json.load(open('$CACHE'))['plugins'])" 2>/dev/null || echo 0)
  RULES_TOTAL=$(python3 -c "import json; print(json.load(open('$CACHE'))['rules'])" 2>/dev/null || echo 0)
else
  SKILLS_TOTAL=$(ls "$HOME/.claude/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
  plugin_file="$HOME/.claude/plugins/installed_plugins.json"
  PLUGINS_TOTAL=0
  if [ -f "$plugin_file" ]; then
    PLUGINS_TOTAL=$(python3 -c \
      "import json; d=json.load(open('$plugin_file')); print(len(d.get('plugins', {})))" \
      2>/dev/null || echo 0)
  fi
  # Rules: prefer the project's CLAUDE.md, fall back to the workspace one.
  RULES_SRC="$cwd/CLAUDE.md"; [ -f "$RULES_SRC" ] || RULES_SRC="$HOME/CLAUDE.md"
  RULES_TOTAL=$(grep -c "^### Rule " "$RULES_SRC" 2>/dev/null || echo 0)
  [ "$RULES_TOTAL" -eq 0 ] && RULES_TOTAL=$(grep -c "^## " "$RULES_SRC" 2>/dev/null || echo 0)
fi

# ── CI status — only when a GitHub repo is configured ──────────────────────────
CI_SEGMENT=""
if [ -n "${CCF_GITHUB_REPO:-}" ]; then
  CI_STATE=$(gh run list --repo "$CCF_GITHUB_REPO" --limit 1 \
    --json conclusion,status \
    --jq '.[0] | if (.conclusion // "" | . != "" and . != "null") then .conclusion else .status end' \
    2>/dev/null || echo "?")
  [ -z "$CI_STATE" ] || [ "$CI_STATE" = "null" ] && CI_STATE="?"
  case "$CI_STATE" in
    success)     CI_DOT="\033[32m●\033[0m" ;;
    failure)     CI_DOT="\033[31m●\033[0m" ;;
    in_progress) CI_DOT="\033[33m◐\033[0m" ;;
    queued)      CI_DOT="\033[33m○\033[0m" ;;
    *)           CI_DOT="\033[90m●\033[0m" ;;
  esac
  CI_SEGMENT=$(printf "${CI_DOT} CI:%-10s" "$CI_STATE")
fi

# ── Health status — only when a live URL is configured (cached 60s) ────────────
HEALTH_SEGMENT=""
if [ -n "${CCF_LIVE_URL:-}" ]; then
  HC="$HOME/.claude/ccf-health.cache"
  AGE=$(( $(date +%s) - $(stat -f %m "$HC" 2>/dev/null || stat -c %Y "$HC" 2>/dev/null || echo 0) ))
  if [ "$AGE" -gt 60 ]; then
    (code=$(curl -sf -o /dev/null -w "%{http_code}" "${CCF_LIVE_URL}${CCF_HEALTH_PATH:-/health}" --max-time 5 2>/dev/null || echo 000)
     [ "$code" = "200" ] && echo "up" > "$HC" || echo "down" > "$HC") &
  fi
  HSTATE=$(cat "$HC" 2>/dev/null || echo "?")
  case "$HSTATE" in
    up)   H_DOT="\033[32m●\033[0m" ;;
    down) H_DOT="\033[31m●\033[0m" ;;
    *)    H_DOT="\033[90m●\033[0m" ;;
  esac
  HEALTH_SEGMENT=$(printf " ${H_DOT} live:%-5s" "$HSTATE")
fi

# ── Context + branch ──────────────────────────────────────────────────────────
ctx_str=""; [ -n "$remaining" ] && ctx_str="ctx:$(printf '%.0f' "$remaining")%"
git_str="";  [ -n "$git_branch" ] && git_str="[$git_branch]"

# ── OUTPUT ─────────────────────────────────────────────────────────────────────
# Row 1: identity (always)
printf "\033[32m%s\033[0m" "$USER_HOST"
printf "  \033[36m%s\033[0m" "${cwd:-~}"
[ -n "$git_str" ]      && printf "  \033[35m%s\033[0m" "$git_str"
[ -n "$model" ]        && printf "  \033[33m%s\033[0m" "$model"
[ -n "$ctx_str" ]      && printf "  \033[32m%s\033[0m" "$ctx_str"
[ -n "$session_name" ] && printf "  \033[90m(%s)\033[0m" "$session_name"
printf "  \033[90m%s\033[0m" "$TIMESTAMP"
printf "\n"

# Row 2: RUNNING — adaptive segments + live agents/loops
printf "\033[1m▶ RUNNING:\033[0m  "
[ -n "$CI_SEGMENT" ]     && printf "%b" "$CI_SEGMENT"
[ -n "$HEALTH_SEGMENT" ] && printf "%b" "$HEALTH_SEGMENT"
[ -n "$CI_SEGMENT$HEALTH_SEGMENT" ] && printf "  "
if [ "$AGENTS_RUNNING" -gt 0 ]; then
  printf "\033[32m⚡%d agents\033[0m  " "$AGENTS_RUNNING"
else
  printf "\033[90m⚡0 agents\033[0m  "
fi
if [ -n "$PROJ_LOOP_LABEL" ]; then
  # This repo runs its own local loop (per-project heartbeat) — show its label.
  printf "\033[32m↺ local:1 %s\033[0m" "$PROJ_LOOP_LABEL"
elif [ "$LOOPS_RUNNING" -gt 0 ]; then
  printf "\033[32m↺%d loops\033[0m" "$LOOPS_RUNNING"
else
  printf "\033[90m↺0 loops\033[0m"
fi
printf "\n"

# Row 3: LOADED — installed inventory + last commit
printf "\033[1m■ LOADED:\033[0m   "
printf "\033[36m⚙ %d skills\033[0m  " "$SKILLS_TOTAL"
printf "\033[35m⬡ %d plugins\033[0m  " "$PLUGINS_TOTAL"
printf "\033[33m⚑ %d rules\033[0m  " "$RULES_TOTAL"
[ -n "$last_commit" ] && printf "\033[90mlast commit: %s\033[0m  " "$last_commit"
printf "\033[90m→ /status for details\033[0m"
printf "\n"
