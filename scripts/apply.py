#!/usr/bin/env python3
"""Apply an approved proposal: write the artifact, record provenance, file the eval case.

Deterministic by design (reference/determinism.md). Once a human has approved a proposal, nothing left
here needs judgment — and doing it in code means the target-path allowlist is actually enforced rather
than merely requested of a model.

Usage:
    apply.py --proposal .claude/bonsai/proposals/<id>.md [--project DIR] [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)$", re.DOTALL)
FENCE = re.compile(r"```[a-zA-Z0-9_-]*\s*\n(.*?)```", re.DOTALL)

# A proposal is model-authored text. Its target is therefore untrusted input, and is constrained to
# paths that are legitimately harness configuration. Anything else is a bug or an attack.
ALLOWED_TARGETS = (
    re.compile(r"^CLAUDE\.md$"),
    re.compile(r"^CLAUDE\.local\.md$"),
    re.compile(r"^\.claude/CLAUDE\.md$"),
    re.compile(r"^\.claude/rules/[A-Za-z0-9._-]+\.md$"),
    re.compile(r"^\.claude/skills/[A-Za-z0-9._-]+/SKILL\.md$"),
    re.compile(r"^\.claude/agents/[A-Za-z0-9._-]+\.md$"),
    re.compile(r"^\.claude/settings\.json$"),
    re.compile(r"^(?:[A-Za-z0-9._-]+/)*\.claude/rules/[A-Za-z0-9._-]+\.md$"),  # nested, monorepos
    re.compile(r"^(?:[A-Za-z0-9._-]+/)*CLAUDE\.md$"),
)

REQUIRED_FIELDS = ("id", "class", "mechanism", "target", "scope")


def fail(message: str) -> None:
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(1)


def parse_field(block: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:\s*(.*?)\s*$", block, re.MULTILINE)
    return match.group(1).strip().strip("\"'") if match else ""


def section(body: str, heading: str) -> str:
    match = re.search(
        rf"^##\s+{re.escape(heading)}\s*$(.*?)(?=^##\s|\Z)", body, re.MULTILINE | re.DOTALL
    )
    return match.group(1).strip() if match else ""


def target_is_allowed(target: str) -> bool:
    if not target or target.startswith("/") or ".." in target.split("/"):
        return False
    return any(p.match(target) for p in ALLOWED_TARGETS)


def merge_settings(existing_text: str, addition_text: str) -> str:
    """Merge hook config into settings.json without clobbering what's already there."""
    try:
        existing = json.loads(existing_text) if existing_text.strip() else {}
    except json.JSONDecodeError:
        fail("settings.json is not valid JSON; refusing to overwrite it")
    try:
        addition = json.loads(addition_text)
    except json.JSONDecodeError:
        fail("proposed settings block is not valid JSON")

    for event, entries in (addition.get("hooks") or {}).items():
        bucket = existing.setdefault("hooks", {}).setdefault(event, [])
        for entry in entries:
            if entry not in bucket:  # idempotent re-apply
                bucket.append(entry)

    for key, value in addition.items():
        if key != "hooks":
            existing.setdefault(key, value)

    return json.dumps(existing, indent=2) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proposal", required=True)
    ap.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    project = os.path.abspath(args.project)
    raw = ""
    try:
        with open(args.proposal, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as exc:
        fail(f"cannot read proposal: {exc}")

    parsed = FRONTMATTER.match(raw)
    if not parsed:
        fail("proposal has no frontmatter")
    block, body = parsed.group(1), parsed.group(2)

    meta = {key: parse_field(block, key) for key in REQUIRED_FIELDS}
    missing = [k for k, v in meta.items() if not v]
    if missing:
        fail(f"proposal missing required fields: {', '.join(missing)}")

    target = meta["target"]
    if not target_is_allowed(target):
        fail(f"target '{target}' is not an allowed harness path")

    artifact_section = section(body, "Proposed artifact")
    fenced = FENCE.search(artifact_section)
    if not fenced:
        fail("proposal has no fenced artifact content under '## Proposed artifact'")
    content = fenced.group(1)
    if not content.endswith("\n"):
        content += "\n"

    # thresholds.md: an artifact without an eval case cannot be audited later, so it cannot be applied.
    eval_case = section(body, "Eval case")
    if len(eval_case) < 40:
        fail("proposal has no usable eval case; rejected")

    dest = os.path.normpath(os.path.join(project, target))
    if not dest.startswith(project + os.sep) and dest != project:
        fail("target escapes the project directory")

    is_settings = target.endswith("settings.json")
    existing = ""
    if os.path.exists(dest):
        with open(dest, encoding="utf-8") as fh:
            existing = fh.read()

    final = merge_settings(existing, content) if is_settings else content
    mode = "merged" if is_settings and existing else ("overwrote" if existing else "created")

    if args.dry_run:
        print(json.dumps({"ok": True, "dry_run": True, "target": target, "action": mode,
                          "bytes": len(final)}, indent=2))
        return 0

    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(final)

    stamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    bonsai_dir = os.path.join(project, ".claude", "bonsai")

    # File the eval case alongside the artifact it justifies.
    evals_dir = os.path.join(bonsai_dir, "evals")
    os.makedirs(evals_dir, exist_ok=True)
    with open(os.path.join(evals_dir, f"{meta['id']}.md"), "w", encoding="utf-8") as fh:
        fh.write(
            f"---\nartifact: {target}\ncreated: {stamp}\nsource-proposal: {meta['id']}\n---\n\n"
            f"{eval_case}\n"
        )

    # Record provenance so /bonsai:prune can audit and demote later.
    inv_path = os.path.join(bonsai_dir, "inventory.json")
    try:
        with open(inv_path, encoding="utf-8") as fh:
            inventory = json.load(fh)
    except (OSError, json.JSONDecodeError):
        inventory = {"artifacts": [], "pruned_count": 0}
    inventory.setdefault("artifacts", [])
    inventory.setdefault("pruned_count", 0)

    record = {
        "id": meta["id"],
        "target": target,
        "mechanism": meta["mechanism"],
        "class": meta["class"],
        "scope": meta["scope"],
        "confidence": parse_field(block, "confidence"),
        "resident_token_delta": parse_field(block, "resident-token-delta"),
        "created": stamp,
        "last_exercised": None,
        "source_observations": parse_field(block, "source-observations") or meta["id"],
    }
    inventory["artifacts"] = [a for a in inventory["artifacts"] if a.get("id") != meta["id"]]
    inventory["artifacts"].append(record)

    with open(inv_path, "w", encoding="utf-8") as fh:
        json.dump(inventory, fh, indent=2)
        fh.write("\n")

    # Retire the proposal; keep it as a record rather than deleting evidence.
    applied_dir = os.path.join(bonsai_dir, "archive", "applied")
    os.makedirs(applied_dir, exist_ok=True)
    try:
        os.replace(args.proposal, os.path.join(applied_dir, os.path.basename(args.proposal)))
    except OSError:
        pass
    seen = os.path.join(bonsai_dir, ".state", "seen", f"{meta['id']}")
    if os.path.exists(seen):
        os.unlink(seen)

    print(json.dumps({
        "ok": True, "id": meta["id"], "target": target, "action": mode,
        "mechanism": meta["mechanism"], "eval_case": f".claude/bonsai/evals/{meta['id']}.md",
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:
        fail(str(exc))
