#!/usr/bin/env bash
# Framework self-test: every script parses, every manifest validates.
# This is CCF_TEST_CMD for the framework itself — the /self-improve test gate.
set -u
cd "$(dirname "$0")/.."
FAIL=0

echo "── shell syntax ──"
for f in setup.sh sync-to-framework.sh tests/run.sh core/statusline-command.sh core/hooks/*.sh; do
  if bash -n "$f" 2>/dev/null; then echo "  ok: $f"; else echo "  FAIL: $f"; FAIL=1; fi
done

echo "── python compile ──"
for f in core/hooks/*.py scripts/*.py; do
  [ -f "$f" ] || continue
  if python3 -m py_compile "$f" 2>/dev/null; then echo "  ok: $f"; else echo "  FAIL: $f"; FAIL=1; fi
done

echo "── json manifests ──"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json core/settings-fragment.json; do
  if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then echo "  ok: $f"; else echo "  FAIL: $f"; FAIL=1; fi
done

echo "── plugin tracks commits (no pinned version) ──"
python3 - <<'EOF' || FAIL=1
import json
p = json.load(open('.claude-plugin/plugin.json'))
m = json.load(open('.claude-plugin/marketplace.json'))
# A plugin-level version freezes every install at that version until it is bumped.
assert 'version' not in p, "plugin.json pins a version — users stop receiving commits"
assert 'version' not in m['plugins'][0], "marketplace plugin entry pins a version"
print(f"  ok: unpinned; release label v{m['metadata']['version']} (marketplace metadata)")
EOF

echo "── license consistency ──"
python3 - <<'EOF' || FAIL=1
import json, os
declared = json.load(open('.claude-plugin/plugin.json')).get('license', '')
if not declared:
    print("  ok: no license declared (nothing to verify)")
elif not os.path.exists('LICENSE'):
    raise SystemExit(f"  FAIL: plugin.json declares '{declared}' but no LICENSE file exists")
else:
    body = open('LICENSE').read()
    token = 'MIT License' if declared.upper() == 'MIT' else declared
    assert token in body, f"LICENSE file does not match declared '{declared}'"
    print(f"  ok: LICENSE present and matches declared '{declared}'")
EOF

echo "── plugin layout ──"
for d in commands agents hooks core scaffold; do
  if [ -d "$d" ]; then echo "  ok: $d/"; else echo "  FAIL: missing $d/"; FAIL=1; fi
done
HOOK_TARGET=$(python3 -c "
import json
h = json.load(open('hooks/hooks.json'))
cmd = h['hooks']['Stop'][0]['hooks'][0]['command']
print(cmd.split('CLAUDE_PLUGIN_ROOT}/')[1].rstrip('\"'))" 2>/dev/null)
if [ -n "$HOOK_TARGET" ] && [ -f "$HOOK_TARGET" ]; then
  echo "  ok: hooks.json -> $HOOK_TARGET exists"
else
  echo "  FAIL: hooks.json target missing: $HOOK_TARGET"; FAIL=1
fi

echo "── command files ──"
# Every skill needs a Markdown '#' title. Skills may now carry a leading YAML
# frontmatter block (see docs/SKILL_SCHEMA.md), so strip that before requiring the title.
python3 - <<'EOF' || FAIL=1
import glob, re, sys
bad = []
for f in sorted(glob.glob("commands/*.md")):
    t = open(f, encoding="utf-8").read()
    body = re.sub(r"^---\s*\n.*?\n---\s*\n", "", t, count=1, flags=re.S)  # strip leading frontmatter
    if not body.lstrip().startswith("#"):
        bad.append(f)
for f in bad:
    print(f"  FAIL: no title: {f}")
if bad:
    sys.exit(1)
print(f"  ok: {len(glob.glob('commands/*.md'))} command files titled")
EOF

echo "── no hardcoded personal paths in shipped skills/hooks ──"
if grep -rnE '/Users/[a-zA-Z]|-Users-[a-zA-Z]|/private/tmp/claude-[0-9]' commands agents scaffold core/hooks hooks --include='*.md' --include='*.sh' --include='*.py' --include='*.json' --include='*.template'; then
  echo "  FAIL: hardcoded personal path (derive from \$REPO_DIR / \$(pwd) instead)"; FAIL=1
else
  echo "  ok: no hardcoded personal paths"
fi

echo "── skill governance (frontmatter description + contract evals; NVIDIA/skills-inspired) ──"
python3 scripts/skill_gate.py || FAIL=1
python3 scripts/skill_gate.py --selftest || FAIL=1

echo "── installed-skill drift guard (F16; report-only, SKIP if no ~/.claude/commands) ──"
python3 scripts/check_skill_drift.py --selftest || FAIL=1
python3 scripts/check_skill_drift.py || true

echo "── consumer sync (F20; keeps repos that use the kit current) ──"
python3 scripts/sync_consumers.py --selftest || FAIL=1
python3 -c "import json; [c['repo'] for c in json.load(open('consumers.json'))['consumers']]; print('  ok: consumers.json registry parses')" || FAIL=1

echo "── blocker-freshness report (F15; report-only, never auto-clears) ──"
python3 scripts/check_blockers.py --selftest || FAIL=1
python3 scripts/check_blockers.py || true

echo "── template placeholders ──"
python3 - <<'EOF' || FAIL=1
import re, sys
known = set(re.findall(r'^(CCF_\w+|ANTHROPIC_API_KEY)=', open('scaffold/.ccf/project.env.template').read(), re.M))
bad = []
for t in ['scaffold/CLAUDE.md.template', 'scaffold/GOAL.md.template']:
    for ph in set(re.findall(r'\{\{(\w+)\}\}', open(t).read())):
        if ph not in known:
            bad.append(f"{t}: {{{{{ph}}}}}")
assert not bad, f"unresolvable placeholders: {bad}"
print(f"  ok: all template placeholders resolvable ({len(known)} env keys)")
EOF

echo "── plugin install smoke ──"
python3 - <<'EOF' || FAIL=1
import json
p = json.load(open('.claude-plugin/plugin.json'))
m = json.load(open('.claude-plugin/marketplace.json'))
entry = m['plugins'][0]
assert entry['name'] == p['name'], f"name mismatch: {entry['name']} != {p['name']}"
assert entry['source'] == './', f"single-plugin repo must use source './', got {entry['source']}"
print(f"  ok: marketplace entry matches plugin.json (name={p['name']}, source=./)")
# Claude Code refuses to install third-party plugins whose name passes as Anthropic's own;
# checked statically so CI catches it without the claude CLI.
for n in {p['name'], m['name'], entry['name']}:
    assert not (n.startswith(('claude-', 'anthropic-', 'anthropics-', 'cc-plugin-'))
                or n in ('claude', 'anthropic', 'anthropics', 'claude-code', 'claude-mods')
                or ('official' in n and ('claude' in n or 'anthropic' in n))), \
        f"reserved plugin/marketplace name: {n}"
print("  ok: plugin/marketplace names are not reserved")
EOF
for f in agents/*.md; do
  [ -f "$f" ] || continue
  if head -1 "$f" | grep -q '^---$' && grep -q '^name:' "$f"; then
    echo "  ok: agent frontmatter: $f"
  else
    echo "  FAIL: agent missing frontmatter/name: $f"; FAIL=1
  fi
done
if command -v claude &>/dev/null; then
  if claude plugin validate . 2>&1 | grep -q "Validation passed"; then
    echo "  ok: claude plugin validate"
  else
    echo "  FAIL: claude plugin validate"; FAIL=1
  fi
else
  echo "  skip: claude CLI not available (SKIP, not FAIL)"
fi

echo "── stop-loops kill switch ──"
if [ -f commands/stop-loops.md ] && grep -q "CronDelete" commands/stop-loops.md && grep -q "STOP_LOOPS" commands/stop-loops.md; then
  if grep -q "STOP_LOOPS" commands/self-improve.md; then
    echo "  ok: /stop-loops present and wired into self-improve Step 0"
  else
    echo "  FAIL: self-improve.md does not honor the STOP_LOOPS sentinel"; FAIL=1
  fi
else
  echo "  FAIL: commands/stop-loops.md missing or incomplete"; FAIL=1
fi

echo "── skill export (any-CLI path) ──"
if bash scripts/export_skills.sh /tmp/ccf_export_test.md >/dev/null 2>&1; then
  N=$(grep -c "^## skill:" /tmp/ccf_export_test.md 2>/dev/null || echo 0)
  C=$(ls commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "$N" -eq "$C" ]; then echo "  ok: export bundles all $C skills"; else echo "  FAIL: export bundled $N of $C skills"; FAIL=1; fi
  rm -f /tmp/ccf_export_test.md
else
  echo "  FAIL: export_skills.sh errored"; FAIL=1
fi

echo "── statusline adaptivity ──"
# Must carry no hardcoded personal/product paths (it adapts via .ccf/project.env).
# Denylist (no single project named — generic coupling patterns only): a hardcoded
# absolute home path, a session-id-style token, or a non-configurable health path
# that should come from CCF_HEALTH_PATH instead.
SL_DENY='/Users/[a-z]|-Users-[a-z]|claude-[0-9]{3}|/v1/health'
if grep -qE "$SL_DENY" core/statusline-command.sh; then
  echo "  FAIL: statusline contains hardcoded personal/product paths"; FAIL=1
else
  echo "  ok: no hardcoded personal/product paths"
fi
# Renders without a config (idea project: no CI/health segments, clean exit).
SL_OUT=$(printf '{"workspace":{"current_dir":"/nonexistent"},"model":{"display_name":"t"},"context_window":{"remaining_percentage":50}}' | bash core/statusline-command.sh 2>/dev/null)
if echo "$SL_OUT" | grep -q "RUNNING" && ! echo "$SL_OUT" | grep -q "CI:"; then
  echo "  ok: renders clean with no config (no spurious CI/health segments)"
else
  echo "  FAIL: statusline did not render correctly without config"; FAIL=1
fi

echo "── skill security scan (SkillSpector, static) ──"
SS=".venv-skillspector/bin/skillspector"
if [ -x "$SS" ]; then
  for target in commands agents; do
    "$SS" scan "$target/" --no-llm --format json --output "/tmp/ccf_ss_$target.json" >/dev/null 2>&1
    python3 tests/check_skillspector.py "/tmp/ccf_ss_$target.json" tests/skillspector_baseline.json || FAIL=1
  done
else
  echo "  skip: skillspector not installed (SKIP, not FAIL)"
  echo "        install: python3 -m venv .venv-skillspector && .venv-skillspector/bin/pip install 'git+https://github.com/NVIDIA/SkillSpector.git'"
fi

echo "── wizard E2E (all four categories) ──"
bash tests/wizard_e2e.sh || FAIL=1

echo "── auto-clear re-arms the loop ──"
# Regression guard: the auto-clear delivery must re-send the loop command after /clear.
# /clear wipes any pending in-session schedule, so a clear with no re-arm leaves the loop
# dormant (the bug fixed 2026-06-13). Every /clear send in the AppleScript delivery must be
# paired with a "/loop /self-improve" re-arm, across all three paths (iTerm write text,
# Terminal do script, keystroke fallback).
python3 - <<'EOF' || FAIL=1
import re, sys
src = open('core/hooks/on-stop.sh').read()
m = re.search(r"<<'ASCRIPT'\n(.*?)\nASCRIPT", src, re.S)
if not m:
    print("  FAIL: AppleScript delivery block not found"); sys.exit(1)
asc = m.group(1)
clears = len(re.findall(r'(?:write text|do script|keystroke) "/clear"', asc))
rearms = len(re.findall(r'(?:write text|do script|keystroke) "/loop /self-improve"', asc))
if clears == 0:
    print("  FAIL: no /clear delivery found"); sys.exit(1)
if rearms != clears:
    print(f"  FAIL: {clears} /clear sends but {rearms} loop re-arms (every clear must re-arm)"); sys.exit(1)
print(f"  ok: all {clears} auto-clear paths re-arm /loop /self-improve")
EOF
if command -v osacompile >/dev/null 2>&1; then
  python3 -c "import re; s=open('core/hooks/on-stop.sh').read(); open('/tmp/ccf_clear.applescript','w').write(re.search(r\"<<'ASCRIPT'\n(.*?)\nASCRIPT\", s, re.S).group(1))"
  if osacompile -o /tmp/ccf_clear.scpt /tmp/ccf_clear.applescript 2>/dev/null; then
    echo "  ok: auto-clear AppleScript compiles"
  else
    echo "  FAIL: auto-clear AppleScript does not compile"; FAIL=1
  fi
  rm -f /tmp/ccf_clear.scpt /tmp/ccf_clear.applescript
else
  echo "  skip: osacompile not available (non-macOS, SKIP not FAIL)"
fi

echo "── Stop-hook framework sync never leaks private files ──"
SB=$(mktemp -d)
git clone -q --bare . "$SB/remote.git" && git clone -q "$SB/remote.git" "$SB/home/Claude Code Framework"
cp sync-to-framework.sh "$SB/home/Claude Code Framework/"
cp core/hooks/on-stop.sh "$SB/home/Claude Code Framework/core/hooks/"
git -C "$SB/home/Claude Code Framework" -c user.name=t -c user.email=t@t commit -qam "test: working tree" 2>/dev/null
git -C "$SB/home/Claude Code Framework" push -q origin HEAD 2>/dev/null
mkdir -p "$SB/home/.claude/hooks" "$SB/proj"
echo 'export MY_TOKEN=sk-live-SECRET123' > "$SB/home/.claude/hooks/my-private-hook.sh"
echo '{}' > "$SB/home/.claude/settings.json"
touch "$SB/home/Claude Code Framework/UNRELATED_WIP.txt"
REMOTE_BEFORE=$(git -C "$SB/remote.git" rev-parse HEAD)
(cd "$SB/proj" && echo '{}' | HOME="$SB/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bash "$SB/home/Claude Code Framework/core/hooks/on-stop.sh" >/dev/null 2>&1)
if [ "$(git -C "$SB/remote.git" rev-parse HEAD)" = "$REMOTE_BEFORE" ]; then
  echo "  ok: no sync/push without CCF_FRAMEWORK_SYNC=1"
else
  echo "  FAIL: Stop hook pushed to the framework without opt-in"; FAIL=1
fi
(cd "$SB/proj" && echo '{}' | HOME="$SB/home" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t CCF_FRAMEWORK_SYNC=1 bash "$SB/home/Claude Code Framework/core/hooks/on-stop.sh" >/dev/null 2>&1)
LEAK=$(git -C "$SB/remote.git" log --all --name-only --format= "$REMOTE_BEFORE..HEAD" 2>/dev/null | grep -E 'my-private-hook|UNRELATED_WIP' || true)
if [ -z "$LEAK" ]; then
  echo "  ok: opted-in sync skips private hooks and untracked files"
else
  echo "  FAIL: sync committed private files: $LEAK"; FAIL=1
fi
rm -rf "$SB"

echo ""
if [ "$FAIL" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "FAILURES DETECTED"; fi
exit $FAIL
