#!/usr/bin/env bash
# F03: non-interactive setup.sh runs for all four project categories in a
# sandbox HOME, asserting the gating values written to .ccf/project.env.
set -u
CCF_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAIL=0

check() { # project_dir key expected
  local got
  got=$(grep "^$2=" "$1/.ccf/project.env" | cut -d= -f2- | tr -d '"')
  if [ "$got" = "$3" ]; then echo "  ok: $(basename "$1") $2=[$3]"; else echo "  FAIL: $(basename "$1") $2 expected [$3] got [$got]"; FAIL=1; fi
}

run_case() { # name answer-format-string
  local name="$1" answers="$2"
  local proj="$TMP/$name" home="$TMP/home-$name"
  mkdir -p "$proj" "$home"
  (cd "$proj" && git init -q . && printf "$answers" | HOME="$home" bash "$CCF_DIR/setup.sh" --scaffold-only >/dev/null 2>&1)
  if [ ! -f "$proj/.ccf/project.env" ]; then echo "  FAIL: $name produced no project.env"; FAIL=1; return; fi
  if [ -d "$home/.claude/hooks" ] || [ -d "$home/.claude/commands" ]; then
    echo "  FAIL: $name scaffold-only wrote hooks/commands into HOME"; FAIL=1
  fi
}

# app: name, cat 1, type 1, test none, live URL, health path, repo blank, deploy 5, key blank, north star
run_case app 'tapp\n1\n1\nnone\nhttps://x.test\n/health\n\n5\n\nns\n'
check "$TMP/app" CCF_PROJECT_CATEGORY app
check "$TMP/app" CCF_LIVE_URL "https://x.test"
check "$TMP/app" CCF_TEST_CMD ""
check "$TMP/app" CCF_DEPLOY_TARGET local

# library: name, cat 2, type 1, test none, repo blank, key blank, north star
run_case library 'tlib\n2\n1\nnone\n\n\nns\n'
check "$TMP/library" CCF_PROJECT_CATEGORY library
check "$TMP/library" CCF_LIVE_URL ""
check "$TMP/library" CCF_TEST_CMD ""
check "$TMP/library" CCF_DEPLOY_TARGET local

# cli: name, cat 3, type 7, test cmd, repo blank, key blank, north star
run_case cli 'tcli\n3\n7\nmake test\n\n\nns\n'
check "$TMP/cli" CCF_PROJECT_CATEGORY cli
check "$TMP/cli" CCF_TEST_CMD "make test"
check "$TMP/cli" CCF_LIVE_URL ""

# idea: name, cat 4, repo blank, key blank, north star
run_case idea 'tidea\n4\n\n\nns\n'
check "$TMP/idea" CCF_PROJECT_CATEGORY idea
check "$TMP/idea" CCF_PROJECT_TYPE idea
check "$TMP/idea" CCF_TEST_CMD ""
check "$TMP/idea" CCF_LIVE_URL ""

exit $FAIL
