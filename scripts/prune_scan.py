#!/usr/bin/env python3
"""Find harness artifacts that no longer earn their keep. Detection only — judgment stays with the model.

Categories: stale, orphan, unscoped, conflict, oversized, redundant.

Usage:
    prune_scan.py --project DIR [--plugin-root DIR]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

CLAUDE_MD_LINE_LIMIT = 200
STALE_AFTER_DAYS = 60
FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

# Path-ish tokens in rule prose that suggest the rule should have been scoped.
PATH_HINT = re.compile(
    r"(?:\b\w[\w.-]*\.(?:ts|tsx|js|jsx|py|go|rs|rb|java|kt|swift|sql|css|scss)\b"
    r"|\btest(?:s)?/|\bsrc/|\bapi/|\bmigrations?/|\bcomponents?/|\*\*/)",
    re.IGNORECASE,
)

# Style concerns a formatter/linter owns; a rule restating them is redundant.
TOOL_OWNED = {
    "indent": ("prettier", "eslint", "black", "ruff", "rustfmt", "gofmt", "editorconfig"),
    "quotes": ("prettier", "eslint", "black", "ruff"),
    "semicolon": ("prettier", "eslint"),
    "line length": ("prettier", "black", "ruff", "flake8", "editorconfig"),
    "trailing comma": ("prettier", "eslint", "black"),
    "import order": ("eslint", "ruff", "isort"),
    "formatting": ("prettier", "black", "rustfmt", "gofmt"),
}

TOOL_CONFIGS = {
    "prettier": (".prettierrc", ".prettierrc.json", ".prettierrc.yaml", "prettier.config.js"),
    "eslint": (".eslintrc", ".eslintrc.json", ".eslintrc.cjs", "eslint.config.js", "eslint.config.mjs"),
    "black": ("pyproject.toml",),
    "ruff": ("ruff.toml", ".ruff.toml", "pyproject.toml"),
    "isort": (".isort.cfg", "pyproject.toml"),
    "flake8": (".flake8", "setup.cfg"),
    "rustfmt": ("rustfmt.toml", ".rustfmt.toml"),
    "gofmt": ("go.mod",),
    "editorconfig": (".editorconfig",),
}


def read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError:
        return ""


def parse_iso(value: object) -> datetime | None:
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def exercised_dates(project: str) -> dict[str, datetime]:
    """Most recent load date per artifact, from the append-only log touch_artifact.sh writes.

    The inventory's `last_exercised` field is only ever a fallback: nothing writes it during normal
    operation, because a hook appending to a flat log is far cheaper than rewriting JSON on every
    instruction load.
    """
    out: dict[str, datetime] = {}
    log = os.path.join(project, ".claude", "bonsai", ".state", "exercised")
    for line in read(log).splitlines():
        parts = line.strip().split(" ", 1)
        if len(parts) != 2:
            continue
        when, rel = parse_iso(parts[0]), parts[1].strip()
        if when and (rel not in out or when > out[rel]):
            out[rel] = when
    return out


def detect_tools(project: str) -> set[str]:
    found = set()
    for tool, candidates in TOOL_CONFIGS.items():
        for candidate in candidates:
            if os.path.exists(os.path.join(project, candidate)):
                found.add(tool)
                break
    return found


def rule_files(project: str) -> list[str]:
    pattern = os.path.join(project, "**", ".claude", "rules", "*.md")
    return sorted(glob.glob(pattern, recursive=True))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--plugin-root", default=os.environ.get("CLAUDE_PLUGIN_ROOT", "."))
    args = ap.parse_args()

    project = os.path.abspath(args.project)
    findings: list[dict] = []
    now = datetime.now(timezone.utc)

    def add(category: str, target: str, detail: str, **extra) -> None:
        findings.append({"category": category, "target": target, "detail": detail, **extra})

    # --- inventory reconciliation -------------------------------------------------
    inv_path = os.path.join(project, ".claude", "bonsai", "inventory.json")
    try:
        inventory = json.loads(read(inv_path) or "{}")
    except json.JSONDecodeError:
        inventory = {}
    artifacts = inventory.get("artifacts", []) if isinstance(inventory, dict) else []
    tracked = {a.get("target") for a in artifacts if isinstance(a, dict)}
    loaded = exercised_dates(project)

    for art in artifacts:
        if not isinstance(art, dict):
            continue
        target = art.get("target", "")
        abs_target = os.path.join(project, target)

        if not os.path.exists(abs_target):
            add("orphan", target, "inventory entry has no file on disk", id=art.get("id"))
            continue

        # Staleness: not loaded in a long time, or never. Enforced constraints are exempt — a guardrail
        # that never fires is working correctly, not dead.
        if art.get("mechanism") in ("hook", "permission"):
            continue
        created = parse_iso(art.get("created"))
        exercised = loaded.get(target) or parse_iso(art.get("last_exercised"))
        age_ref = exercised or created
        stale_for = (now - age_ref).days if age_ref else None

        if stale_for is not None and stale_for > STALE_AFTER_DAYS:
            detail = (
                f"last loaded {exercised.date()} ({stale_for}d ago)" if exercised
                else f"never loaded since {created.date()} ({stale_for}d ago)"
            )
            add("stale", target, detail, id=art.get("id"), mechanism=art.get("mechanism"),
                days_stale=stale_for, ever_loaded=bool(exercised))

    # --- rules: scoping and conflicts --------------------------------------------
    by_topic: dict[str, list[str]] = {}
    for path in rule_files(project):
        rel = os.path.relpath(path, project)
        body = read(path)
        fm = FRONTMATTER.match(body)
        block = fm.group(1) if fm else ""
        prose = body[fm.end():] if fm else body

        if "paths:" not in block:
            hits = sorted(set(m.group(0) for m in PATH_HINT.finditer(prose)))[:5]
            if hits:
                add("unscoped", rel,
                    "no `paths:` frontmatter, but content references specific paths/filetypes",
                    hints=hits)

        if rel not in tracked:
            add("orphan", rel, "artifact has no provenance in the inventory (may be human-authored)")

        topic = os.path.splitext(os.path.basename(path))[0].lower()
        by_topic.setdefault(topic, []).append(
            {"path": rel, "scoped": "paths:" in block, "dir": os.path.dirname(rel)}
        )

    for topic, entries in by_topic.items():
        if len(entries) < 2:
            continue
        # Same-topic rules in different directories where at least one is path-scoped are normal
        # monorepo layering, not a contradiction. Only flag genuinely overlapping guidance.
        dirs = {e["dir"] for e in entries}
        if len(dirs) > 1 and any(e["scoped"] for e in entries):
            continue
        add("conflict", ", ".join(e["path"] for e in entries),
            f"{len(entries)} rule files share the topic '{topic}' with overlapping scope "
            "and may contradict each other")

    # --- resident instruction size -----------------------------------------------
    for candidate in ("CLAUDE.md", os.path.join(".claude", "CLAUDE.md")):
        text = read(os.path.join(project, candidate))
        if not text:
            continue
        lines = len(text.splitlines())
        if lines > CLAUDE_MD_LINE_LIMIT:
            add("oversized", candidate,
                f"{lines} lines, over the {CLAUDE_MD_LINE_LIMIT}-line target; "
                "delegate trims to /doctor, then split by path", lines=lines)

    # --- guidance a tool already enforces ----------------------------------------
    tools = detect_tools(project)
    if tools:
        sources = [os.path.join(project, c) for c in ("CLAUDE.md", ".claude/CLAUDE.md")]
        sources += rule_files(project)
        for path in sources:
            body = read(path).lower()
            if not body:
                continue
            rel = os.path.relpath(path, project)
            for concern, owners in TOOL_OWNED.items():
                overlap = tools.intersection(owners)
                if concern in body and overlap:
                    add("redundant", rel,
                        f"mentions '{concern}', already enforced by {', '.join(sorted(overlap))}",
                        concern=concern)

    summary: dict[str, int] = {}
    for f in findings:
        summary[f["category"]] = summary.get(f["category"], 0) + 1

    print(json.dumps({
        "findings": findings,
        "summary": summary,
        "artifacts_tracked": len(artifacts),
        "load_tracking": {
            "artifacts_with_load_data": len(loaded),
            "active": bool(loaded),
            "hint": None if loaded else
                    "No load data yet. Staleness is measured from creation date until the "
                    "InstructionsLoaded hook has run; treat stale findings as weak evidence.",
        },
        "tools_detected": sorted(tools),
        "note": "Detection only. Judgment belongs to the model; see skills/prune/SKILL.md step 3.",
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(json.dumps({"findings": [], "summary": {}, "error": str(exc)}))
        sys.exit(0)
