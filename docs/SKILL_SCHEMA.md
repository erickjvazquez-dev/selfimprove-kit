# CCF Skill Schema — frontmatter governance

Every skill in `commands/*.md` carries a small **YAML frontmatter** block so the
framework's own tooling (`/find-skill` routing, the skill export bundle, future
skill-cards) can read machine-readable metadata instead of parsing prose. This is
adapted from [NVIDIA/skills](https://github.com/NVIDIA/skills) — we take the *governance
model* (declared metadata + a gate that enforces it), not the GPU/domain skills
themselves.

## Format

Frontmatter is a `---`-delimited block at the very top of the file, immediately followed
by the existing `#` Markdown title:

```markdown
---
description: One-line summary of what the skill does and when to use it.
---
# /gap — Gap Detection + Multi-Agent Technical Lead Orchestrator

...the skill body, unchanged...
```

Claude Code parses this frontmatter natively (it already honours `description` on slash
commands); other CLIs receive it as informational text in the export bundle.

## Fields

| Key | Status (P0) | Meaning |
|---|---|---|
| `description` | **required** | One-line, human- and machine-readable summary. This is the field `/find-skill` routes on and the gate enforces. Keep it a single line, no leading verb-of-obligation ("Use this to…") — just say what it does. |
| `name` | reserved | Canonical skill name. Optional today; Claude Code derives it from the filename. A later slice may require it. |
| `version` | reserved | SemVer of the skill. Optional today; a later slice may require it and tie it to the integrity manifest. |

Only flat `key: value` scalars are used — CCF frontmatter is intentionally not general
YAML (the gate parses it with a stdlib regex, no PyYAML).

## The gate

`scripts/skill_gate.py` (run by `tests/run.sh`, the framework self-test / `/self-improve`
Step-4c-equivalent) enforces this schema with a **baseline-widening, shrink-only**
rollout — the same pattern as `tests/check_skillspector.py`:

- A skill **not** listed in `tests/skill_governance_baseline.json` that lacks a
  `description` **fails** the gate.
- Pre-governance skills are grandfathered in the baseline, so the gate lands report-only
  for the existing fleet and never breaks a tick on arrival.
- The baseline is **shrink-only**: once a baselined skill gains a `description`, it must
  be removed from the baseline (the gate fails otherwise). Governance can only ratchet
  forward.

Bringing a skill into compliance is one edit + one baseline deletion — a natural,
low-cost standing item for the self-improve loop's improve step until the baseline is
empty.

## Roadmap (governance slices)

- **P0 (this doc):** `description` required; frontmatter schema + gate + baseline; three
  highest-traffic skills (`gap`, `qa`, `self-improve`) made compliant.
- **P1:** per-skill eval cases (`commands/evals/<skill>.json`); "skill has no eval = gap".
- **P2:** publish gate — ungoverned skills dropped from `export_skills.sh`.
- **P3:** sha256 integrity manifest + supply-chain worm-guard coverage of this repo.
- **P4 (optional):** generated skill-cards + staleness gate.
