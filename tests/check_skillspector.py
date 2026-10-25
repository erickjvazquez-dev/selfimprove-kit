#!/usr/bin/env python3
"""SkillSpector regression gate: fail only on findings NOT in the triaged baseline.

Usage: python3 tests/check_skillspector.py <report.json> <baseline.json>

A finding's identity is (id, file). The static scan of an autonomy framework will
always flag by-design patterns (session persistence, autonomous decisions) and
false positives (safety docs that *mention* dangerous commands) — those live in
the baseline with a triage note. Anything new of severity HIGH/CRITICAL fails.
"""
import json
import sys

GATE_SEVERITIES = {"HIGH", "CRITICAL"}


def key(issue):
    loc = issue.get("location") or {}
    return f"{issue.get('id', '?')}@{loc.get('file', '?')}"


def main():
    report_path, baseline_path = sys.argv[1], sys.argv[2]
    report = json.load(open(report_path))
    baseline = json.load(open(baseline_path))
    accepted = {e["key"] for e in baseline["accepted"]}

    new = [i for i in report.get("issues", [])
           if i.get("severity") in GATE_SEVERITIES and key(i) not in accepted]

    if new:
        print(f"  FAIL: {len(new)} new HIGH/CRITICAL skill finding(s) not in baseline:")
        for i in new:
            loc = i.get("location") or {}
            print(f"    {i.get('severity')} {key(i)} line {loc.get('start_line')}: "
                  f"{i.get('finding', '')[:70]}")
        print("  Triage: fix the skill, or if false-positive/by-design add the key "
              "to tests/skillspector_baseline.json with a note.")
        return 1

    n_base = sum(1 for i in report.get("issues", [])
                 if i.get("severity") in GATE_SEVERITIES)
    print(f"  ok: no new HIGH/CRITICAL findings ({n_base} baselined) "
          f"in {report.get('skill', {}).get('source', '?')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
