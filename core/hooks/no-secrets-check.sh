#!/usr/bin/env bash
# Pre-commit guard: blocks files that likely contain secrets
FILES=$(git diff --cached --name-only)
if echo "$FILES" | grep -qiE "(\.env$|credentials\.json|\.pem$|id_rsa$|\.p12$|\.key$)"; then
    echo "ERROR: Refusing to commit file(s) that may contain secrets:"
    echo "$FILES" | grep -iE "(\.env$|credentials\.json|\.pem$|id_rsa$|\.p12$|\.key$)"
    exit 1
fi
exit 0
