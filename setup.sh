#!/usr/bin/env bash
# Claude Code Framework — Setup Wizard
# Drop into any project and run: bash setup.sh
# With the Claude Code plugin installed, run: bash setup.sh --scaffold-only
# (skips hooks/skills/settings — the plugin already provides them)
set -euo pipefail

CCF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
PROJECT_DIR="$(pwd)"

SCAFFOLD_ONLY=false
for arg in "$@"; do
  case "$arg" in
    --scaffold-only) SCAFFOLD_ONLY=true ;;
    -h|--help)
      echo "Usage: bash setup.sh [--scaffold-only]"
      echo "  --scaffold-only  Only write .ccf/project.env, CLAUDE.md, GOAL.md and memory dir."
      echo "                   Use after installing the selfimprove-kit plugin."
      exit 0 ;;
  esac
done

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

say()  { echo -e "${BLUE}${BOLD}$*${NC}"; }
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $*"; }
ask()  { echo -en "${BOLD}$* ${NC}"; }

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║     Claude Code Framework — Setup        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Pre-flight ─────────────────────────────────────────────────────────────────
if ! command -v claude &>/dev/null; then
  warn "Claude Code CLI not found — continuing anyway (skills are plain markdown and work with any agentic CLI)."
fi
if ! command -v git &>/dev/null; then
  warn "git not found. Please install git first."
  exit 1
fi

# ── Load existing .ccf/project.env if present ─────────────────────────────────
CCF_ENV_FILE="$PROJECT_DIR/.ccf/project.env"
if [ -f "$CCF_ENV_FILE" ]; then
  say "Found existing .ccf/project.env — loading defaults"
  # shellcheck disable=SC1090
  source "$CCF_ENV_FILE" 2>/dev/null || true
fi

# ── Wizard questions ───────────────────────────────────────────────────────────
say "Step 1 — Project identity"
echo ""

ask "Project name [${CCF_PROJECT_NAME:-$(basename "$PROJECT_DIR")}]:"; read -r INPUT
CCF_PROJECT_NAME="${INPUT:-${CCF_PROJECT_NAME:-$(basename "$PROJECT_DIR")}}"

echo "What kind of project is this?"
echo "  1) app      — deployable app/service (has or will have a live URL)"
echo "  2) library  — package/SDK consumed by other code"
echo "  3) cli      — command-line tool"
echo "  4) idea     — idea, doc, research, or content project (no code gates)"
ask "Choice [${CCF_PROJECT_CATEGORY:-1}]:"; read -r INPUT
case "${INPUT:-${CCF_PROJECT_CATEGORY:-1}}" in
  1|app)      CCF_PROJECT_CATEGORY="app" ;;
  2|library)  CCF_PROJECT_CATEGORY="library" ;;
  3|cli)      CCF_PROJECT_CATEGORY="cli" ;;
  4|idea)     CCF_PROJECT_CATEGORY="idea" ;;
  *)          CCF_PROJECT_CATEGORY="app" ;;
esac

if [ "$CCF_PROJECT_CATEGORY" != "idea" ]; then
  echo "Project type:"
  echo "  1) python-fastapi   2) python-django   3) node-express"
  echo "  4) node-nextjs      5) go              6) react-spa"
  echo "  7) cli              8) other"
  ask "Choice [${CCF_PROJECT_TYPE:-1}]:"; read -r INPUT
  case "${INPUT:-1}" in
    1|python-fastapi)  CCF_PROJECT_TYPE="python-fastapi" ;;
    2|python-django)   CCF_PROJECT_TYPE="python-django" ;;
    3|node-express)    CCF_PROJECT_TYPE="node-express" ;;
    4|node-nextjs)     CCF_PROJECT_TYPE="node-nextjs" ;;
    5|go)              CCF_PROJECT_TYPE="go" ;;
    6|react-spa)       CCF_PROJECT_TYPE="react-spa" ;;
    7|cli)             CCF_PROJECT_TYPE="cli" ;;
    *)                 CCF_PROJECT_TYPE="${INPUT:-other}" ;;
  esac
else
  CCF_PROJECT_TYPE="idea"
fi

if [ "$CCF_PROJECT_CATEGORY" != "idea" ]; then
  echo ""
  say "Step 2 — Runtime & testing"
  echo ""

  # Auto-detect test command
  DEFAULT_TEST_CMD="none"
  if [ -f "$PROJECT_DIR/pytest.ini" ] || [ -f "$PROJECT_DIR/pyproject.toml" ]; then
    DEFAULT_TEST_CMD="python3 -m pytest tests/ -q --tb=short"
  elif [ -f "$PROJECT_DIR/package.json" ]; then
    DEFAULT_TEST_CMD="npm test"
  elif [ -f "$PROJECT_DIR/go.mod" ]; then
    DEFAULT_TEST_CMD="go test ./..."
  fi

  ask "Test command ('none' if no tests yet) [${CCF_TEST_CMD:-$DEFAULT_TEST_CMD}]:"; read -r INPUT
  CCF_TEST_CMD="${INPUT:-${CCF_TEST_CMD:-$DEFAULT_TEST_CMD}}"
  [ "$CCF_TEST_CMD" = "none" ] && CCF_TEST_CMD=""
else
  CCF_TEST_CMD=""
fi

if [ "$CCF_PROJECT_CATEGORY" = "app" ]; then
  ask "Health check URL (blank to skip) [${CCF_LIVE_URL:-}]:"; read -r INPUT
  CCF_LIVE_URL="${INPUT:-${CCF_LIVE_URL:-}}"
  if [ -n "$CCF_LIVE_URL" ]; then
    ask "Health endpoint path [${CCF_HEALTH_PATH:-/health}]:"; read -r INPUT
    CCF_HEALTH_PATH="${INPUT:-${CCF_HEALTH_PATH:-/health}}"
  else
    CCF_HEALTH_PATH="/health"
  fi
else
  CCF_LIVE_URL=""
  CCF_HEALTH_PATH="/health"
fi

echo ""
say "Step 3 — CI / deployment"
echo ""

ask "GitHub repo (user/repo, blank to skip) [${CCF_GITHUB_REPO:-}]:"; read -r INPUT
CCF_GITHUB_REPO="${INPUT:-${CCF_GITHUB_REPO:-}}"

if [ "$CCF_PROJECT_CATEGORY" = "app" ]; then
  echo "Deploy target:"
  echo "  1) railway   2) vercel   3) fly.io   4) aws   5) local-only   6) other"
  ask "Choice [${CCF_DEPLOY_TARGET:-5}]:"; read -r INPUT
  case "${INPUT:-5}" in
    1|railway)     CCF_DEPLOY_TARGET="railway"; CCF_DEPLOY_CMD="railway up --detach" ;;
    2|vercel)      CCF_DEPLOY_TARGET="vercel";  CCF_DEPLOY_CMD="vercel --prod" ;;
    3|fly.io|fly)  CCF_DEPLOY_TARGET="fly";     CCF_DEPLOY_CMD="fly deploy" ;;
    4|aws)         CCF_DEPLOY_TARGET="aws";     CCF_DEPLOY_CMD="echo 'configure CCF_DEPLOY_CMD'" ;;
    5|local-only)  CCF_DEPLOY_TARGET="local";   CCF_DEPLOY_CMD="" ;;
    *)             CCF_DEPLOY_TARGET="${INPUT:-other}"; CCF_DEPLOY_CMD="echo 'configure CCF_DEPLOY_CMD'" ;;
  esac
else
  CCF_DEPLOY_TARGET="local"
  CCF_DEPLOY_CMD=""
fi

echo ""
say "Step 4 — API keys"
echo ""

ask "Anthropic API key (sk-ant-... or blank to skip) [${ANTHROPIC_API_KEY:+set}]:"; read -rs INPUT
echo ""
if [ -n "$INPUT" ]; then ANTHROPIC_API_KEY="$INPUT"; fi

ask "North star (one sentence — what this project does) [${CCF_NORTH_STAR:-}]:"; read -r INPUT
CCF_NORTH_STAR="${INPUT:-${CCF_NORTH_STAR:-Build something great}}"

echo ""
say "Installing..."
echo ""

# ── Write .ccf/project.env ─────────────────────────────────────────────────────
mkdir -p "$PROJECT_DIR/.ccf"
cat > "$CCF_ENV_FILE" <<EOF
# Claude Code Framework — Project Configuration
# Generated by setup.sh on $(date)
# DO NOT commit this file — add .ccf/project.env to .gitignore

CCF_PROJECT_NAME="${CCF_PROJECT_NAME}"
CCF_PROJECT_CATEGORY="${CCF_PROJECT_CATEGORY}"
CCF_PROJECT_TYPE="${CCF_PROJECT_TYPE}"
CCF_PROJECT_DIR="${PROJECT_DIR}"
CCF_LIVE_URL="${CCF_LIVE_URL}"
CCF_HEALTH_PATH="${CCF_HEALTH_PATH:-/health}"
CCF_TEST_CMD="${CCF_TEST_CMD}"
CCF_GITHUB_REPO="${CCF_GITHUB_REPO}"
CCF_DEPLOY_TARGET="${CCF_DEPLOY_TARGET}"
CCF_DEPLOY_CMD="${CCF_DEPLOY_CMD}"
CCF_NORTH_STAR="${CCF_NORTH_STAR}"
CCF_FRAMEWORK_DIR="${CCF_DIR}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
EOF
ok ".ccf/project.env written"

# Add to .gitignore
if [ -f "$PROJECT_DIR/.gitignore" ]; then
  grep -q ".ccf/project.env" "$PROJECT_DIR/.gitignore" 2>/dev/null || \
    echo ".ccf/project.env" >> "$PROJECT_DIR/.gitignore"
else
  echo ".ccf/project.env" > "$PROJECT_DIR/.gitignore"
fi
ok ".ccf/project.env added to .gitignore"

# ── Install hooks / statusline / skills / settings ────────────────────────────
# Skipped with --scaffold-only: the selfimprove-kit plugin already
# provides commands, agents, and the Stop hook. BUT a plugin cannot declare a
# statusLine, so we still install + wire that even in scaffold-only mode.
if [ "$SCAFFOLD_ONLY" = "true" ]; then
  cp "$CCF_DIR/core/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
  chmod +x "$CLAUDE_DIR/statusline-command.sh"
  SETTINGS="$CLAUDE_DIR/settings.json"
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  python3 - "$SETTINGS" <<'PYEOF'
import json, sys
p = sys.argv[1]
s = json.load(open(p))
s.setdefault("statusLine", {"type": "command",
                            "command": "bash $HOME/.claude/statusline-command.sh"})
json.dump(s, open(p, "w"), indent=2)
PYEOF
  ok "Statusline installed + wired → ~/.claude/ (plugin can't ship a statusLine)"
  ok "Scaffold-only mode — skipping hooks/skills installs (plugin provides those)"
else

# ── Install hooks ──────────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR/hooks"
for hook in "$CCF_DIR/core/hooks/"*.sh "$CCF_DIR/core/hooks/"*.py; do
  [ -f "$hook" ] || continue
  dest="$CLAUDE_DIR/hooks/$(basename "$hook")"
  cp "$hook" "$dest"
  chmod +x "$dest" 2>/dev/null || true
done
ok "Hooks installed → ~/.claude/hooks/"

# ── Install statusline ─────────────────────────────────────────────────────────
cp "$CCF_DIR/core/statusline-command.sh" "$CLAUDE_DIR/statusline-command.sh"
chmod +x "$CLAUDE_DIR/statusline-command.sh"
ok "Statusline installed → ~/.claude/statusline-command.sh"

# ── Install skills ─────────────────────────────────────────────────────────────
mkdir -p "$CLAUDE_DIR/commands"
SKILL_COUNT=0
for skill in "$CCF_DIR/commands/"*.md; do
  [ -f "$skill" ] || continue
  cp "$skill" "$CLAUDE_DIR/commands/$(basename "$skill")"
  SKILL_COUNT=$((SKILL_COUNT + 1))
done
ok "$SKILL_COUNT skills installed → ~/.claude/commands/"

# ── Patch ~/.claude/settings.json ─────────────────────────────────────────────
SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

python3 - "$SETTINGS" "$CCF_DIR/core/settings-fragment.json" <<'PYEOF'
import json, sys, copy

settings_path = sys.argv[1]
fragment_path = sys.argv[2]

with open(settings_path) as f:
    settings = json.load(f)
with open(fragment_path) as f:
    fragment = json.load(f)

# Merge hooks
existing_hooks = settings.setdefault("hooks", {})
for event, entries in fragment.get("hooks", {}).items():
    existing = existing_hooks.setdefault(event, [])
    for entry in entries:
        if not any(e.get("hooks", [{}])[0].get("command", "").endswith(
                   entry["hooks"][0]["command"].split("/")[-1]) for e in existing):
            existing.append(entry)

# Set statusline only if not already set
if "statusLine" not in settings and "statusLine" in fragment:
    settings["statusLine"] = fragment["statusLine"]

# Merge top-level keys (don't override existing)
for k, v in fragment.items():
    if k not in ("hooks", "statusLine") and k not in settings:
        settings[k] = v

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)
print("settings patched")
PYEOF
ok "~/.claude/settings.json patched"

fi  # end of non-scaffold-only installs

# ── Generate CLAUDE.md ─────────────────────────────────────────────────────────
if [ ! -f "$PROJECT_DIR/CLAUDE.md" ]; then
  python3 - "$CCF_DIR/scaffold/CLAUDE.md.template" "$CCF_ENV_FILE" \
            "$PROJECT_DIR/CLAUDE.md" <<'PYEOF'
import re, sys
with open(sys.argv[1]) as f: template = f.read()
with open(sys.argv[2]) as f:
    env = {}
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip().strip('"')
for k, v in env.items():
    template = template.replace("{{" + k + "}}", v)
with open(sys.argv[3], "w") as f: f.write(template)
PYEOF
  ok "CLAUDE.md generated"
else
  warn "CLAUDE.md already exists — skipped (edit manually if needed)"
fi

# ── Generate GOAL.md ───────────────────────────────────────────────────────────
if [ ! -f "$PROJECT_DIR/GOAL.md" ]; then
  python3 - "$CCF_DIR/scaffold/GOAL.md.template" "$CCF_ENV_FILE" \
            "$PROJECT_DIR/GOAL.md" <<'PYEOF'
import re, sys
with open(sys.argv[1]) as f: template = f.read()
with open(sys.argv[2]) as f:
    env = {}
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip().strip('"')
for k, v in env.items():
    template = template.replace("{{" + k + "}}", v)
with open(sys.argv[3], "w") as f: f.write(template)
PYEOF
  ok "GOAL.md generated"
else
  warn "GOAL.md already exists — skipped"
fi

# ── Init memory ───────────────────────────────────────────────────────────────
PROJECT_SLUG=$(echo "$PROJECT_DIR" | sed 's|/|-|g' | sed 's/^-//')
MEMORY_DIR="$CLAUDE_DIR/projects/$PROJECT_SLUG/memory"
mkdir -p "$MEMORY_DIR"
if [ ! -f "$MEMORY_DIR/MEMORY.md" ]; then
  printf '# Memory Index\n\n' > "$MEMORY_DIR/MEMORY.md"
  ok "Memory directory initialized → $MEMORY_DIR"
fi

# ── Git: init loop state ───────────────────────────────────────────────────────
python3 -c "
import json, os, time
for p in ['$HOME/.claude/loop-state.json', '$HOME/.claude/loop-iterations.json']:
    if not os.path.exists(p):
        json.dump({'count': 0, 'started_at': time.time(), 'needs_restart': False}, open(p,'w'))
" 2>/dev/null
ok "Loop state files initialized"

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   Setup complete! Next steps:            ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  1. ${BOLD}cd $(pwd)${NC}"
echo -e "  2. ${BOLD}claude${NC}  ← open Claude Code"
echo -e "  3. ${BOLD}/self-improve${NC}  ← start the autonomous loop"
echo -e "  4. ${BOLD}/qa${NC}            ← run product QA"
echo -e "  5. ${BOLD}/gap${NC}           ← detect what's missing"
echo ""
echo -e "  Skills installed: /self-improve /qa /gap /goal /critical-checks"
echo -e "                    /speckit.* /snapshot /restore /rollback /status"
echo ""
if [ -n "$CCF_GITHUB_REPO" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  warn "ANTHROPIC_API_KEY not set — add it to .ccf/project.env"
fi
