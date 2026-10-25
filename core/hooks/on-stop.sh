#!/usr/bin/env bash
# Fires when a Claude Code session ends.
# 1. Appends a dated entry to the memory session log.
# 2. Writes ~/.claude/loop-state.json so the next session knows where the loop left off.

# Guard: the plugin Stop hook and a settings.json Stop hook may both point at
# this script on machines using both install paths — skip the second fire.
STAMP="$HOME/.claude/.on-stop-ran"
NOW=$(date +%s)
LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
case "$LAST" in (*[!0-9]*|'') LAST=0;; esac
if [ $((NOW - LAST)) -lt 5 ]; then
    exit 0
fi
echo "$NOW" > "$STAMP"

# Derive the memory slug from the working directory (matches Claude Code's
# ~/.claude/projects/<slug>/ convention) instead of hardcoding a user path.
PROJECT_SLUG=$(pwd | sed 's|[^a-zA-Z0-9]|-|g')
SESSION_LOG="$HOME/.claude/projects/$PROJECT_SLUG/memory/session_log.md"
LOOP_STATE="$HOME/.claude/loop-state.json"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")
TIMESTAMP_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
LAST_COMMIT=$(git log -1 --pretty="%h %s" 2>/dev/null || echo "no commits")

# Read context remaining. The Stop-hook payload does NOT include context_window
# (that field is status-line-only), so we read the value the status line writes
# to ~/.claude/ctx_pct on every render. Fall back to 100 if unavailable.
cat >/dev/null 2>&1  # drain stdin
CTX_REMAINING=$(tr -dc '0-9' < "$HOME/.claude/ctx_pct" 2>/dev/null)
[ -z "$CTX_REMAINING" ] && CTX_REMAINING=100

# --- 1. Session log ---
if [ ! -f "$SESSION_LOG" ]; then
    mkdir -p "$(dirname "$SESSION_LOG")"
    printf '# Session Log\n\nOne entry per Claude Code session. Used by /self-improve to understand recent work context.\n\n---\n\n' > "$SESSION_LOG"
fi

printf '**%s** branch=`%s` last-commit=`%s`\n\n' \
    "$TIMESTAMP" "$GIT_BRANCH" "$LAST_COMMIT" >> "$SESSION_LOG"

# --- 2. Loop state (for next session resumption) ---
python3 -c "
import json, os, time
state_file = os.path.expanduser('$LOOP_STATE')
try:
    prev = json.load(open(state_file)) if os.path.exists(state_file) else {}
except Exception:
    prev = {}
ctx = $CTX_REMAINING
prev.update({
    'stopped_at': '$TIMESTAMP_ISO',
    'ctx_remaining_pct': ctx,
    'git_branch': '$GIT_BRANCH',
    'last_commit': '$LAST_COMMIT',
    'loop_prompt': '/loop /self-improve',
    'needs_restart': ctx < 20,
})
json.dump(prev, open(state_file, 'w'), indent=2)
" 2>/dev/null || true

# --- 3. Auto-clear on low context (robust + audited) ---
# When context drops below 20%, clear the session AND immediately re-arm the local
# loop by sending the loop command (`/loop /self-improve`) into the same tab after
# the clear settles. `/clear` wipes any pending in-session schedule, so without this
# re-arm the loop would go dormant after every auto-clear until an external cron
# resumed it. Re-sending the loop command restarts it fresh in clean context.
# Delivery prefers Terminal's `do script "/clear" in <tab matched by tty>` (and the
# iTerm2 `write text` equivalent): these write "/clear"+Return straight to the target
# tab's tty, so they need NO Accessibility permission, do NOT steal window focus, and
# do NOT depend on which window is frontmost. The previous System Events keystroke went
# to whatever window happened to be frontmost and silently hit the wrong one when
# several Terminal windows were open — the likely reason a 16%-ctx session failed to
# clear. A frontmost keystroke is kept only as a last-resort fallback. Every run appends
# to ~/.claude/auto-clear.log so the behavior is auditable after the fact.
NEEDS_CLEAR="$HOME/.claude/needs_clear"
CLEAR_LOG="$HOME/.claude/auto-clear.log"
log_ac() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$CLEAR_LOG" 2>/dev/null; }

if [ "$CTX_REMAINING" -lt 20 ] 2>/dev/null; then
    touch "$NEEDS_CLEAR"
    log_ac "ctx=${CTX_REMAINING}% < 20 -> needs_clear set"
fi

if [ -f "$NEEDS_CLEAR" ] && ! command -v osascript &>/dev/null; then
    # Non-macOS: no AppleScript delivery path — leave the flag for the runner to handle.
    log_ac "ctx=${CTX_REMAINING}% osascript unavailable -> auto-clear skipped (non-macOS)"
elif [ -f "$NEEDS_CLEAR" ]; then
    rm -f "$NEEDS_CLEAR"
    sleep 0.8  # let Claude Code return to idle input-read state

    # Walk up the process chain to find the claude binary (handles any nesting depth).
    # `ps -o comm=` can return a full path, so match on the basename too.
    _find_claude_pid() {
        local pid=$$ comm
        for _ in 1 2 3 4 5 6; do
            pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d ' ')
            { [ -z "$pid" ] || [ "$pid" -le 1 ]; } && break
            comm=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d ' ')
            case "$comm" in */claude | claude) echo "$pid"; return ;; esac
        done
    }
    CLAUDE_PID=$(_find_claude_pid)
    CLAUDE_TTY=$(ps -p "$CLAUDE_PID" -o tty= 2>/dev/null | tr -d ' ')

    if [ -z "$CLAUDE_TTY" ] || [ "$CLAUDE_TTY" = "??" ]; then
        # Headless/cron session (no controlling tty) — nothing to keystroke into.
        log_ac "ctx=${CTX_REMAINING}% no controlling tty (pid=${CLAUDE_PID:-none}) -> headless/cron, clear skipped"
    else
        TTY_PATH="/dev/$CLAUDE_TTY"
        AC_OUT="/tmp/cf_autoclear_out.$$"
        # Heredoc runs on a plain command (NOT inside $()) so bash 3.2 parses it;
        # capture osascript's result via a temp file instead.
        osascript - "$TTY_PATH" >"$AC_OUT" 2>&1 <<'ASCRIPT'
on run argv
    set targetTTY to item 1 of argv
    -- 1) iTerm2: write straight to the session whose tty matches (no focus steal)
    if application "iTerm2" is running then
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (tty of s) is targetTTY then
                                tell s to write text "/clear"
                                delay 2
                                tell s to write text "/loop /self-improve"
                                return "iterm-doscript-ok " & targetTTY
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
    end if
    -- 2) Terminal: do script straight into the tab whose tty matches (no focus steal)
    if application "Terminal" is running then
        tell application "Terminal"
            repeat with wIdx from 1 to (count windows)
                repeat with tIdx from 1 to (count tabs of window wIdx)
                    try
                        if (tty of tab tIdx of window wIdx) is targetTTY then
                            do script "/clear" in tab tIdx of window wIdx
                            delay 2
                            do script "/loop /self-improve" in tab tIdx of window wIdx
                            return "terminal-doscript-ok " & targetTTY
                        end if
                    end try
                end repeat
            end repeat
        end tell
    end if
    -- 3) Last resort: keystroke into the frontmost Terminal window (focus-stealing).
    --    Only reached if no tab's tty matched above.
    if application "Terminal" is running then
        tell application "Terminal" to activate
        delay 0.3
        tell application "System Events"
            tell process "Terminal"
                keystroke "/clear"
                key code 36
                delay 2
                keystroke "/loop /self-improve"
                key code 36
            end tell
        end tell
        return "terminal-keystroke-fallback " & targetTTY
    end if
    return "no-terminal-app " & targetTTY
end run
ASCRIPT
        AC_EXIT=$?
        AC_RESULT=$(tr -d '\n' < "$AC_OUT" 2>/dev/null)
        rm -f "$AC_OUT"
        log_ac "ctx=${CTX_REMAINING}% tty=${CLAUDE_TTY} clear -> ${AC_RESULT} (exit ${AC_EXIT})"
    fi
fi

# --- 4. Sync improvements back to Claude Code Framework (maintainer opt-in) ---
# It commits and pushes to the framework repo, so it must never fire for ordinary
# users or inside a plugin install; only the framework maintainer sets CCF_FRAMEWORK_SYNC=1.
CCF_FRAMEWORK="${CCF_FRAMEWORK_DIR:-$HOME/Claude Code Framework}"
if [ "${CCF_FRAMEWORK_SYNC:-0}" = "1" ] && [ -d "$CCF_FRAMEWORK" ] && [ -f "$CCF_FRAMEWORK/sync-to-framework.sh" ]; then
    bash "$CCF_FRAMEWORK/sync-to-framework.sh" 2>/dev/null || true
fi
