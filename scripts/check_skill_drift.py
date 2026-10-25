#!/usr/bin/env python3
"""F16 — installed-skill drift guard.

Reports globally-installed skills (``~/.claude/commands/*.md``) that have drifted
from the framework's canonical generalized versions (``commands/*.md``) by carrying
hardcoded project-specific tokens the canonical version deliberately parameterizes.

This is the trap a session can hit: ``/meta-improve`` loads a project-hardcoded
instance instead of the generalized framework skill. ``sync-to-framework.sh`` only
drift-notices at session end; this surfaces the same signal in the test gate / CI.

Diagnostic / report-only: a project's live command copies are EXPECTED to be
instances, so this never fails a build on its own. It flags only *generalized*
skills (present in the framework) whose installed copy re-hardcodes a project.

Usage:
  check_skill_drift.py [--commands-dir DIR] [--installed-dir DIR] [--selftest]
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# Project-specific tokens a generalized skill must NOT hardcode. Mirrors the
# _parameterize rules in sync-to-framework.sh (kept in sync deliberately).
PROJECT_TOKEN_PATTERNS = [
    (r"/Users/[^/\s]+/[A-Za-z0-9._-]+", "absolute user path"),
    (r"[a-z0-9-]+\.up\.railway\.app", "hardcoded Railway URL"),
]


def project_tokens(text: str) -> set[str]:
    found: set[str] = set()
    for pattern, label in PROJECT_TOKEN_PATTERNS:
        if re.search(pattern, text):
            found.add(label)
    return found


def scan(commands_dir: Path, installed_dir: Path) -> list[tuple[str, set[str]]]:
    """Return (skill_name, hardcoded_tokens) for installed copies of generalized
    skills that re-hardcode a project the canonical version does not."""
    drifted: list[tuple[str, set[str]]] = []
    for canonical in sorted(commands_dir.glob("*.md")):
        name = canonical.stem
        installed = installed_dir / f"{name}.md"
        if not installed.exists():
            continue
        canonical_tokens = project_tokens(canonical.read_text(encoding="utf-8"))
        installed_tokens = project_tokens(installed.read_text(encoding="utf-8"))
        # Only tokens the installed copy adds over the canonical version count as drift.
        added = installed_tokens - canonical_tokens
        if added:
            drifted.append((name, added))
    return drifted


def run(commands_dir: Path, installed_dir: Path) -> int:
    if not installed_dir.is_dir():
        print(f"  skip: {installed_dir} not present (SKIP, not FAIL)")
        return 0
    drifted = scan(commands_dir, installed_dir)
    if not drifted:
        print("  ok: no generalized skill has a project-hardcoded installed copy")
        return 0
    print(f"  NOTICE: {len(drifted)} generalized skill(s) shadowed by a hardcoded instance:")
    for name, tokens in drifted:
        print(f"    - {name}: installed copy adds {sorted(tokens)}")
    print("  (report-only — port the generalized version or re-run setup.sh to refresh)")
    return 0


def selftest() -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        canon = root / "commands"
        inst = root / "installed"
        canon.mkdir()
        inst.mkdir()
        # Generalized canonical skill (parameterized).
        (canon / "meta-improve.md").write_text(
            "# /meta-improve\nRead ${CCF_PROJECT_DIR}/GOAL.md\n", encoding="utf-8"
        )
        (canon / "clean.md").write_text("# /clean\nRead $HOME/GOAL.md\n", encoding="utf-8")
        # Hardcoded instance shadowing the generalized skill → must be flagged.
        (inst / "meta-improve.md").write_text(
            "# /meta-improve\nRead /Users/alice/myapp/GOAL.md\n", encoding="utf-8"
        )
        # Clean instance that adds no project tokens → must NOT be flagged.
        (inst / "clean.md").write_text("# /clean\nRead the GOAL.md\n", encoding="utf-8")

        drifted = dict(scan(canon, inst))
        ok = True
        if "meta-improve" not in drifted:
            print("  FAIL selftest: did not flag hardcoded meta-improve instance")
            ok = False
        if "clean" in drifted:
            print("  FAIL selftest: false-positive on clean instance")
            ok = False
        # Absent installed dir must SKIP (return 0), not error.
        if run(canon, root / "nope") != 0:
            print("  FAIL selftest: missing installed dir should SKIP")
            ok = False
        if ok:
            print("  ok: skill-drift selftest passed")
            return 0
        return 1


def main() -> int:
    ap = argparse.ArgumentParser(description="Installed-skill drift guard (F16)")
    ap.add_argument("--commands-dir", default=None)
    ap.add_argument("--installed-dir", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()

    if args.selftest:
        return selftest()

    repo_root = Path(__file__).resolve().parents[1]
    commands_dir = Path(args.commands_dir) if args.commands_dir else repo_root / "commands"
    installed_dir = (
        Path(args.installed_dir).expanduser()
        if args.installed_dir
        else Path.home() / ".claude" / "commands"
    )
    return run(commands_dir, installed_dir)


if __name__ == "__main__":
    sys.exit(main())
