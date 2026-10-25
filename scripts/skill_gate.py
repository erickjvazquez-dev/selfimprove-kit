#!/usr/bin/env python3
"""CCF skill-governance gate — machine-readable skill metadata + contract evals.

Adapts the governance MODEL from github.com/NVIDIA/skills (declared per-skill metadata
+ a gate that enforces it) — NOT the GPU/domain skills. Two checks, both baseline-widened
and shrink-only (same pattern as tests/check_skillspector.py), so they land report-only
for the existing fleet and never break a self-improve tick on arrival:

  1. FRONTMATTER (P0) — every commands/*.md declares a YAML `description`
     (docs/SKILL_SCHEMA.md). Baseline: tests/skill_governance_baseline.json.
  2. EVALS (P1) — every skill has commands/evals/<skill>.json with >=1 contract case
     asserting essential invariant strings of the skill's own text (`must_contain` /
     `must_not_contain`). These are STATIC text checks — never an LLM run ($0, offline)
     — a regression guard against skill-rot. Baseline: tests/skill_eval_baseline.json.

A baseline is shrink-only: a baselined skill that has SINCE become compliant fails with
"remove from baseline", so governance can only ratchet forward. A PRESENT eval must
always be valid (a must_contain string that no longer appears in the skill fails even if
the skill is baselined) — so an eval can never silently rot.

Stdlib only (no PyYAML — matches tests/run.sh, which is the CI gate). Usage:
  python3 scripts/skill_gate.py [commands_dir]
  python3 scripts/skill_gate.py --selftest   # prove both checks are non-vacuous (run.sh)
"""
from __future__ import annotations

import contextlib
import glob
import io
import json
import os
import re
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ── shared helpers ────────────────────────────────────────────────────────────

def parse_frontmatter(text: str) -> dict:
    """Top-level scalar keys of a leading ``--- ... ---`` YAML block, else {}."""
    if not text.startswith("---"):
        return {}
    m = re.match(r"---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    if not m:
        return {}
    fm: dict = {}
    for line in m.group(1).splitlines():
        km = re.match(r"([A-Za-z0-9_-]+):\s*(.*)$", line)
        if km:
            fm[km.group(1)] = km.group(2).strip().strip('"').strip("'")
    return fm


def _skill_names(commands_dir: str) -> list[str]:
    return sorted(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(commands_dir, "*.md")))


def _load_baseline(path: str) -> set[str]:
    if not os.path.exists(path):
        return set()
    return {e["key"] for e in json.load(open(path)).get("accepted", [])}


# ── check 1: frontmatter description ──────────────────────────────────────────

def check_frontmatter(commands_dir: str, baseline_path: str) -> int:
    accepted = _load_baseline(baseline_path)
    missing, stale, compliant = [], [], []
    for name in _skill_names(commands_dir):
        with open(os.path.join(commands_dir, name + ".md"), encoding="utf-8") as fh:
            has_desc = bool(parse_frontmatter(fh.read()).get("description", "").strip())
        key = name + ".md"
        if has_desc:
            compliant.append(name)
            if key in accepted:
                stale.append(name)
        elif key not in accepted:
            missing.append(name)

    fail = 0
    if missing:
        fail = 1
        print(f"  FAIL: {len(missing)} skill(s) missing frontmatter `description` (not baselined):")
        for n in missing:
            print(f"    {n}")
        print("  Fix: add a YAML `description:` (docs/SKILL_SCHEMA.md), or grandfather in "
              "tests/skill_governance_baseline.json.")
    if stale:
        fail = 1
        print(f"  FAIL: {len(stale)} baselined skill(s) now have a description — remove from "
              "tests/skill_governance_baseline.json (shrink-only):")
        for n in stale:
            print(f"    {n}")
    if not fail:
        print(f"  ok: frontmatter — {len(compliant)} with description, {len(accepted)} grandfathered")
    return fail


# ── check 2: per-skill contract evals ─────────────────────────────────────────

def _validate_eval(data: dict, skill_text: str) -> list[str]:
    """Return a list of problems with one eval file (empty = valid)."""
    problems = []
    cases = data.get("cases")
    if not isinstance(cases, list) or not cases:
        return ["no `cases` array with >=1 case"]
    for i, c in enumerate(cases):
        if not isinstance(c, dict):
            problems.append(f"case {i} is not an object")
            continue
        mc = c.get("must_contain", [])
        mnc = c.get("must_not_contain", [])
        if not mc and not mnc:
            problems.append(f"case {i} ({c.get('name', '?')}) asserts nothing")
        for s in mc:
            if s not in skill_text:
                problems.append(f"case {i}: must_contain {s!r} NOT in skill (rotted)")
        for s in mnc:
            if s in skill_text:
                problems.append(f"case {i}: must_not_contain {s!r} PRESENT in skill")
    return problems


def check_evals(commands_dir: str, evals_dir: str, baseline_path: str) -> int:
    accepted = _load_baseline(baseline_path)
    missing, invalid, stale, good = [], [], [], []
    for name in _skill_names(commands_dir):
        key = name + ".md"
        eval_path = os.path.join(evals_dir, name + ".json")
        if not os.path.exists(eval_path):
            if key not in accepted:
                missing.append(name)
            continue
        try:
            data = json.load(open(eval_path))
        except Exception as e:  # noqa: BLE001 — any parse error is a gate failure
            invalid.append((name, f"invalid JSON: {e}"))
            continue
        with open(os.path.join(commands_dir, name + ".md"), encoding="utf-8") as fh:
            problems = _validate_eval(data, fh.read())
        if problems:
            invalid.extend((name, p) for p in problems)
        else:
            good.append(name)
            if key in accepted:
                stale.append(name)

    fail = 0
    if missing:
        fail = 1
        print(f"  FAIL: {len(missing)} skill(s) have no eval file commands/evals/<skill>.json "
              "(not baselined) — 'skill has no eval = gap' (GAP-047):")
        for n in missing:
            print(f"    {n}")
    if invalid:
        fail = 1
        print(f"  FAIL: {len(invalid)} eval problem(s) — a present eval must always be valid:")
        for n, p in invalid:
            print(f"    {n}: {p}")
    if stale:
        fail = 1
        print(f"  FAIL: {len(stale)} baselined skill(s) now have a valid eval — remove from "
              "tests/skill_eval_baseline.json (shrink-only):")
        for n in stale:
            print(f"    {n}")
    if not fail:
        print(f"  ok: evals — {len(good)} with a valid contract eval, {len(accepted)} grandfathered")
    return fail


# ── entry points ──────────────────────────────────────────────────────────────

def run_all(commands_dir: str) -> int:
    fm_baseline = os.path.join(_ROOT, "tests", "skill_governance_baseline.json")
    eval_baseline = os.path.join(_ROOT, "tests", "skill_eval_baseline.json")
    evals_dir = os.path.join(commands_dir, "evals")
    rc = check_frontmatter(commands_dir, fm_baseline)
    rc |= check_evals(commands_dir, evals_dir, eval_baseline)
    return 1 if rc else 0


def selftest() -> int:
    """Prove BOTH checks flag a non-compliant skill — non-vacuity without committing a
    broken fixture (guard-must-fail discipline)."""
    import tempfile

    d = tempfile.mkdtemp(prefix="ccf_skillgate_")
    ev = os.path.join(d, "evals")
    os.makedirs(ev)
    # A compliant skill: has frontmatter + a valid eval.
    open(os.path.join(d, "good.md"), "w").write(
        "---\ndescription: real desc\n---\n# /good — TOKEN_PRESENT title\n")
    json.dump({"skill": "good", "cases": [{"name": "t", "must_contain": ["TOKEN_PRESENT"]}]},
              open(os.path.join(ev, "good.json"), "w"))
    # Non-compliant skills: one missing description, one missing its eval.
    open(os.path.join(d, "nodesc.md"), "w").write("# /nodesc — no frontmatter\n")
    open(os.path.join(d, "noeval.md"), "w").write("---\ndescription: d\n---\n# /noeval\n")
    # Empty baselines -> nothing grandfathered, so both must fail.
    fm_b = os.path.join(d, "fm.json")
    ev_b = os.path.join(d, "ev.json")
    json.dump({"accepted": []}, open(fm_b, "w"))
    json.dump({"accepted": []}, open(ev_b, "w"))

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fm_rc = check_frontmatter(d, fm_b)
        ev_rc = check_evals(d, ev, ev_b)
    out = buf.getvalue()
    ok = (fm_rc == 1 and "nodesc" in out and ev_rc == 1 and "noeval" in out)
    if ok:
        print("  ok: selftest — frontmatter gate flags a missing description AND eval gate "
              "flags a missing eval (both non-vacuous)")
        return 0
    print("  FAIL: selftest — a gate did NOT flag its non-compliant fixture (vacuous!)")
    print(out)
    return 1


def main() -> int:
    args = sys.argv[1:]
    if "--selftest" in args:
        return selftest()
    commands_dir = args[0] if args else os.path.join(_ROOT, "commands")
    return run_all(commands_dir)


if __name__ == "__main__":
    sys.exit(main())
