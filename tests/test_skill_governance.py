"""pytest mirror of the skill-governance gate (CI runs bash tests/run.sh, which invokes
scripts/skill_gate.py; this file gives the same guarantees to any pytest-based runner and
adds structural assertions on the eval files themselves).

Governance model adapted from github.com/NVIDIA/skills (declared metadata + a gate),
NOT its GPU/domain skills. See docs/SKILL_SCHEMA.md.
"""
from __future__ import annotations

import glob
import json
import os

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COMMANDS = os.path.join(ROOT, "commands")
EVALS = os.path.join(COMMANDS, "evals")

import importlib.util

_spec = importlib.util.spec_from_file_location(
    "skill_gate", os.path.join(ROOT, "scripts", "skill_gate.py"))
skill_gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(skill_gate)


def _skill_names():
    return sorted(os.path.basename(p)[:-3] for p in glob.glob(os.path.join(COMMANDS, "*.md")))


def _eval_files():
    return sorted(glob.glob(os.path.join(EVALS, "*.json")))


def test_gate_is_green():
    """The full stdlib gate (frontmatter + evals) passes on the real skill tree."""
    assert skill_gate.run_all(COMMANDS) == 0


def test_gate_selftest_is_nonvacuous():
    """Both sub-gates provably flag a non-compliant fixture (guard-must-fail)."""
    assert skill_gate.selftest() == 0


@pytest.mark.parametrize("path", _eval_files(), ids=lambda p: os.path.basename(p))
def test_eval_file_is_valid(path):
    """Every eval file is valid JSON, names an existing skill, and its must_contain /
    must_not_contain assertions actually hold against that skill's text (no rot)."""
    data = json.load(open(path))
    name = os.path.basename(path)[:-5]
    skill_md = os.path.join(COMMANDS, name + ".md")
    assert os.path.exists(skill_md), f"eval references non-existent skill {name}"
    text = open(skill_md, encoding="utf-8").read()
    problems = skill_gate._validate_eval(data, text)
    assert not problems, f"{name}: {problems}"


def test_seeded_skills_have_evals_and_are_not_baselined():
    """The P1-seeded skills must have evals and must NOT appear in the eval baseline
    (shrink-only ratchet — a compliant skill in the baseline is a gate failure)."""
    baseline = skill_gate._load_baseline(os.path.join(ROOT, "tests", "skill_eval_baseline.json"))
    for name in ("gap", "qa", "self-improve"):
        assert os.path.exists(os.path.join(EVALS, name + ".json")), f"{name} missing its eval"
        assert name + ".md" not in baseline, f"{name} is compliant but still baselined"
