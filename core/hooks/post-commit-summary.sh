#!/usr/bin/env bash
# Plain-English commit summary hook. Delegates to summarize_commit.py.
# Called by .git/hooks/post-commit
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
/opt/homebrew/bin/python3 "$SCRIPT_DIR/summarize_commit.py" || true
