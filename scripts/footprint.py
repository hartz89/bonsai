#!/usr/bin/env python3
"""Measure bonsai's actual context footprint and the ledger of what it has cost and saved.

Exists so the claims in reference/budget.md can fail a test instead of merely sounding good.

Token counts are estimates (~4 chars/token). /context is authoritative for exact numbers; the point
here is a cheap, assertable regression check.

Usage:
    footprint.py --plugin-root <dir> [--project <dir>] [--format json|line]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

RESIDENT_CEILING = 350  # reference/budget.md, budget 1
CHARS_PER_TOKEN = 4
FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

# Mechanisms that cost nothing until they are actually needed.
ZERO_RESIDENT_TARGETS = ("hooks", "agents", "settings.json")


def tokens(text: str) -> int:
    return (len(text) + CHARS_PER_TOKEN - 1) // CHARS_PER_TOKEN


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def field(frontmatter: str, key: str) -> str:
    match = re.search(rf"^{key}:\s*(.+?)\s*$", frontmatter, re.MULTILINE)
    return match.group(1).strip().strip("\"'") if match else ""


def skill_descriptions(plugin_root: str) -> tuple[int, list[dict]]:
    """Resident cost of bonsai's own skills: name + description only, never the body."""
    total, detail = 0, []
    skills_dir = os.path.join(plugin_root, "skills")
    if not os.path.isdir(skills_dir):
        return 0, []
    for name in sorted(os.listdir(skills_dir)):
        path = os.path.join(skills_dir, name, "SKILL.md")
        if not os.path.isfile(path):
            continue
        body = read(path)
        fm = FRONTMATTER.match(body)
        block = fm.group(1) if fm else ""
        desc = field(block, "description")
        # A user-only skill is invisible to the model until invoked, so it costs nothing at rest.
        user_only = field(block, "disable-model-invocation").lower() == "true"
        cost = 0 if user_only else tokens(f"{name}: {desc}")
        total += cost
        detail.append({"skill": name, "tokens": cost, "user_only": user_only})
    return total, detail


def pointer_cost(project: str) -> int:
    """Cost of bonsai's stanza in CLAUDE.md — the only prose it adds to resident context."""
    for candidate in ("CLAUDE.md", os.path.join(".claude", "CLAUDE.md")):
        text = read(os.path.join(project, candidate))
        if not text:
            continue
        match = re.search(
            r"^##\s+Harness maintenance\s*$(.*?)(?=^##\s|\Z)", text, re.MULTILINE | re.DOTALL
        )
        if match:
            return tokens(match.group(0))
    return 0


def artifact_ledger(project: str) -> dict:
    """What bonsai has created, and which of it is resident vs conditional."""
    inventory_path = os.path.join(project, ".claude", "bonsai", "inventory.json")
    try:
        inventory = json.loads(read(inventory_path) or "{}")
    except json.JSONDecodeError:
        inventory = {}

    artifacts = inventory.get("artifacts", []) if isinstance(inventory, dict) else []
    resident = conditional = 0
    counts: dict[str, int] = {}

    for art in artifacts:
        if not isinstance(art, dict):
            continue
        mechanism = art.get("mechanism", "unknown")
        counts[mechanism] = counts.get(mechanism, 0) + 1
        target = art.get("target", "")
        cost = tokens(read(os.path.join(project, target))) if target else 0

        if any(z in target for z in ZERO_RESIDENT_TARGETS) or mechanism in ("hook", "subagent", "permission"):
            conditional += cost
        elif mechanism == "rule":
            # A rule with `paths:` loads only when a matching file is touched.
            fm = FRONTMATTER.match(read(os.path.join(project, target)))
            scoped = "paths:" in (fm.group(1) if fm else "")
            if scoped:
                conditional += cost
            else:
                resident += cost
        else:
            resident += cost

    return {
        "count": len(artifacts),
        "by_mechanism": counts,
        "artifact_resident_tokens": resident,
        "artifact_conditional_tokens": conditional,
        "pruned": inventory.get("pruned_count", 0),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugin-root", default=os.environ.get("CLAUDE_PLUGIN_ROOT", "."))
    ap.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--format", choices=("json", "line"), default="json")
    args = ap.parse_args()

    skills_cost, skills_detail = skill_descriptions(args.plugin_root)
    pointer = pointer_cost(args.project)
    notice = 15  # one line, only when proposals are pending
    own_resident = skills_cost + pointer + notice

    ledger = artifact_ledger(args.project)

    result = {
        "own_resident_tokens": own_resident,
        "ceiling": RESIDENT_CEILING,
        "within_budget": own_resident <= RESIDENT_CEILING,
        "breakdown": {
            "skill_descriptions": skills_cost,
            "claude_md_pointer": pointer,
            "session_start_notice": notice,
        },
        "skills": skills_detail,
        "artifacts": ledger,
        "note": "Estimates at ~4 chars/token. /context is authoritative.",
    }

    if args.format == "line":
        status = "within" if result["within_budget"] else "OVER"
        print(
            f"bonsai footprint: ~{own_resident} resident tokens ({status} {RESIDENT_CEILING} budget) · "
            f"{ledger['count']} artifacts "
            f"({ledger['artifact_resident_tokens']} resident, "
            f"{ledger['artifact_conditional_tokens']} conditional) · "
            f"{ledger['pruned']} pruned"
        )
    else:
        print(json.dumps(result, indent=2))

    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # never break a hook or skill
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(0)
