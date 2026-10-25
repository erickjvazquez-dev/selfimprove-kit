#!/usr/bin/env python3
"""Generates a plain-English summary of the last git commit via Claude Haiku.
Called by post-commit-summary.sh. Reads API key from settings.local.json."""

import os
import re
import subprocess
import sys
from pathlib import Path


def get_api_key() -> str:
    return os.environ.get("ANTHROPIC_API_KEY", "")


def get_commit_info():
    def run(cmd):
        return subprocess.check_output(cmd, text=True).strip()

    commit_hash = run(["git", "rev-parse", "--short", "HEAD"])
    commit_msg = run(["git", "log", "-1", "--pretty=%s"])
    commit_date = run(["git", "log", "-1", "--pretty=%ci"]).split()[0]
    try:
        diff_stat = run(["git", "diff", "HEAD~1", "HEAD", "--stat"])
    except subprocess.CalledProcessError:
        diff_stat = run(["git", "show", "--stat", "--format=", "HEAD"])
    return commit_hash, commit_msg, commit_date, diff_stat


def generate_summary(api_key: str, commit_msg: str, diff_stat: str) -> str:
    import anthropic
    client = anthropic.Anthropic(api_key=api_key)
    prompt = (
        "Summarize this git commit in 1-2 plain-English sentences. "
        "Describe WHAT COMPONENT or FEATURE changed and HOW (added, updated, fixed, removed). "
        "No file names, no code, no line numbers. Focus on product capabilities. "
        "Example output: 'Added SQL query tool for CSV files. Fixed path traversal guard in the file router.' "
        "Keep it under 25 words.\n\n"
        f"Commit message: {commit_msg}\n"
        f"Files changed:\n{diff_stat}"
    )
    response = client.messages.create(
        model="claude-haiku-4-5-20251001",
        max_tokens=120,
        messages=[{"role": "user", "content": prompt}],
    )
    return response.content[0].text.strip()


def append_to_log(commit_hash: str, commit_date: str, summary: str) -> None:
    log_path = (
        Path.home()
        / ".claude"
        / "projects"
        / re.sub(r"[^A-Za-z0-9]", "-", str(Path.cwd()))
        / "memory"
        / "commit_log.md"
    )
    log_path.parent.mkdir(parents=True, exist_ok=True)
    if not log_path.exists():
        log_path.write_text(
            "# Commit Log (Plain English)\n\n"
            "Plain-English summaries of what changed — no code, just components.\n"
            "Run `/self-improve` to get improvement suggestions based on this history.\n\n"
            "---\n\n"
        )
    with log_path.open("a") as f:
        f.write(f"**{commit_date}** `{commit_hash}` — {summary}\n\n")


def main():
    api_key = get_api_key()
    commit_hash, commit_msg, commit_date, diff_stat = get_commit_info()

    # Credit-dead short-circuit: when the metered API account is out of credits
    # (see memory project_anthropic_credits), every commit otherwise prints a
    # "credit balance too low" 400. A sentinel skips the call and logs the raw
    # message instead. Delete ~/.claude/no_api_credits when credits return.
    sentinel = Path.home() / ".claude" / "no_api_credits"

    if not api_key or sentinel.exists():
        summary = commit_msg
    else:
        try:
            summary = generate_summary(api_key, commit_msg, diff_stat)
        except Exception as e:
            # First credit/auth failure trips the sentinel so future commits stay quiet.
            if any(s in str(e).lower() for s in ("credit", "balance", "401", "authentication")):
                try:
                    sentinel.write_text(f"auto-created after API failure: {str(e)[:200]}\n")
                except OSError:
                    pass
            summary = commit_msg

    append_to_log(commit_hash, commit_date, summary)
    print(f"[post-commit] {summary}")


if __name__ == "__main__":
    main()
