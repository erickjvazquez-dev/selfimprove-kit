#!/usr/bin/env python3
"""F15 — blocker-freshness reporter (report-only).

Parses the ``## Blockers`` section of GOAL.md and reports each open blocker with a
freshness signal, so a loop tick can see at a glance what is still blocking and
whether it is an accepted ongoing constraint or a candidate for review.

It NEVER auto-clears a blocker: a blocker asserting "CI can't run" may be legitimate
(e.g. a shared GitHub Actions-minutes budget exhausted across many projects), so
clearing it on the mere existence of an old green run would be wrong. Blockers marked
EXPECTED — by the literal token ``EXPECTED`` or ``[expected]`` in the line — are
reported as accepted constraints, not anomalies.

Diagnostic / report-only: always exits 0 (SKIP, not FAIL) so it can run inside the
test gate without failing the build.

Usage:
  check_blockers.py [--goal PATH] [--selftest]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

OPEN_RE = re.compile(r"^\s*-\s*\[ \]\s*(.+)$")
EXPECTED_RE = re.compile(r"\bEXPECTED\b|\[expected\]", re.IGNORECASE)


def parse_blockers(text: str) -> list[str]:
    """Return the open ('- [ ]') blocker lines under the '## Blockers' heading."""
    lines = text.splitlines()
    out: list[str] = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            in_section = line.strip().lower() == "## blockers"
            continue
        if in_section:
            m = OPEN_RE.match(line)
            if m:
                out.append(m.group(1).strip())
    return out


def run(goal_path: Path) -> int:
    if not goal_path.is_file():
        print(f"  skip: {goal_path} not present (SKIP, not FAIL)")
        return 0
    blockers = parse_blockers(goal_path.read_text(encoding="utf-8"))
    if not blockers:
        print("  ok: no open blockers")
        return 0
    expected = [b for b in blockers if EXPECTED_RE.search(b)]
    review = [b for b in blockers if not EXPECTED_RE.search(b)]
    print(f"  {len(blockers)} open blocker(s): {len(expected)} expected, {len(review)} to review")
    for b in expected:
        print(f"    - [expected] {b[:110]}")
    for b in review:
        print(f"    - [review]   {b[:110]}")
    if review:
        print("  (review = not marked EXPECTED; confirm still blocking or resolve — never auto-cleared)")
    return 0


def selftest() -> int:
    import tempfile

    sample = (
        "# Goals\n\n"
        "## Blockers\n"
        "- [ ] B01 (EXPECTED — budget) shared Actions-minutes budget exhausted\n"
        "- [ ] B02 real unresolved blocker with no marker\n"
        "- [x] B00 already done, ignored\n\n"
        "## Now\n"
        "- [ ] F99 not a blocker, ignored\n"
    )
    with tempfile.TemporaryDirectory() as d:
        goal = Path(d) / "GOAL.md"
        goal.write_text(sample, encoding="utf-8")
        blockers = parse_blockers(goal.read_text(encoding="utf-8"))
        ok = True
        if len(blockers) != 2:
            print(f"  FAIL selftest: expected 2 open blockers, got {len(blockers)}")
            ok = False
        if not any("B01" in b for b in blockers) or not any("B02" in b for b in blockers):
            print("  FAIL selftest: missing expected blocker lines")
            ok = False
        if any("F99" in b or "B00" in b for b in blockers):
            print("  FAIL selftest: leaked a non-blocker or completed item")
            ok = False
        b01 = next((b for b in blockers if "B01" in b), "")
        b02 = next((b for b in blockers if "B02" in b), "")
        if not EXPECTED_RE.search(b01):
            print("  FAIL selftest: B01 should be classified EXPECTED")
            ok = False
        if EXPECTED_RE.search(b02):
            print("  FAIL selftest: B02 should NOT be classified EXPECTED")
            ok = False
        if run(Path(d) / "nope.md") != 0:
            print("  FAIL selftest: missing GOAL should SKIP")
            ok = False
        if ok:
            print("  ok: blocker-audit selftest passed")
            return 0
        return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Blocker-freshness reporter (F15)")
    ap.add_argument("--goal", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    repo_root = Path(__file__).resolve().parents[1]
    goal = Path(args.goal).expanduser() if args.goal else repo_root / "GOAL.md"
    return run(goal)


if __name__ == "__main__":
    sys.exit(main())
