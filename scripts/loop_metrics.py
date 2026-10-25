#!/usr/bin/env python3
"""Telemetry-free loop metrics: summarize shipped work per ISO week from git history.

Usage: python3 scripts/loop_metrics.py [weeks=4]
Run from any framework-managed project; reads only `git log` (no network, no telemetry).
"""
import re
import subprocess
import sys
from collections import defaultdict

SHIPPED_TYPES = ("feat", "fix", "test", "perf")


def main():
    weeks = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    out = subprocess.run(
        ["git", "log", f"--since={weeks} weeks ago",
         "--date=format:%G-W%V", "--pretty=%h|%ad|%s"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        print("not a git repository (or git unavailable)")
        return 1

    by_week = defaultdict(lambda: defaultdict(int))
    for line in out.stdout.strip().splitlines():
        _, week, subj = line.split("|", 2)
        m = re.match(r"(\w+)(\(.*?\))?!?:", subj)
        by_week[week][m.group(1) if m else "other"] += 1

    if not by_week:
        print(f"no commits in the last {weeks} week(s)")
        return 0

    print(f"LOOP METRICS — last {weeks} week(s)")
    grand = defaultdict(int)
    for week in sorted(by_week):
        counts = by_week[week]
        shipped = sum(counts.get(t, 0) for t in SHIPPED_TYPES)
        total = sum(counts.values())
        detail = " ".join(f"{t}:{n}" for t, n in sorted(counts.items(), key=lambda kv: -kv[1]))
        print(f"  {week}  shipped:{shipped:<3} total:{total:<3} {detail}")
        for t, n in counts.items():
            grand[t] += n
    shipped = sum(grand.get(t, 0) for t in SHIPPED_TYPES)
    print(f"  TOTAL    shipped:{shipped:<3} total:{sum(grand.values()):<3} "
          + " ".join(f"{t}:{n}" for t, n in sorted(grand.items(), key=lambda kv: -kv[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
