#!/usr/bin/env python3
"""Apply an approved proposal: write the artifact, record provenance, file the eval case.

Deterministic by design (reference/determinism.md). Once a human has approved a proposal, nothing left
here needs judgment — and doing it in code means the target-path allowlist is actually enforced rather
than merely requested of a model.

Usage:
    apply.py --proposal .claude/bonsai/proposals/<id>.md [--project DIR] [--dry-run]
             [--allow-shrink]

The write boundary is about content as well as path (AGENTS.md invariant 8). A proposal's fenced block
is the *entire resulting file*, never a fragment — but a model that gets that wrong would otherwise
silently destroy the target, which is exactly how sharpshooter lost an 80-line CLAUDE.md (D-14). So
every overwrite is backed up first, and an implausible shrink is refused rather than applied.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
from datetime import datetime, timezone

FRONTMATTER = re.compile(r"^---\s*\n(.*?)\n---\s*\n(.*)$", re.DOTALL)
FENCE = re.compile(r"```[a-zA-Z0-9_-]*\s*\n(.*?)```", re.DOTALL)

# D-14. A fragment pasted where a whole file belongs shows up as a drastic shrink, so that's what we
# test for. Deliberately not a superset check: a legitimate edit that *rewrites* a line ("use npm" ->
# "use pnpm") is not a superset of the original, and rejecting those would make the tool unusable.
SHRINK_MIN_LINES = 10   # below this, a big proportional shrink is ordinary, not suspicious
SHRINK_RATIO = 0.5      # refuse when the result keeps less than half the existing non-blank lines

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


def substantive_lines(text: str) -> int:
    """Non-blank lines. The unit CLAUDE.md and rule files are actually reasoned about in."""
    return sum(1 for line in text.splitlines() if line.strip())


def shrink_verdict(existing: str, proposed: str) -> tuple[bool, int, int]:
    """(refuse?, existing lines, proposed lines) — see SHRINK_* above."""
    before, after = substantive_lines(existing), substantive_lines(proposed)
    refuse = before >= SHRINK_MIN_LINES and after < before * SHRINK_RATIO
    return refuse, before, after


def back_up(dest: str, target: str, bonsai_dir: str) -> str:
    """Copy the current file aside before it is overwritten. Returns a project-relative path.

    Backups live under .state/ (already gitignored) rather than as a sibling `.bak`, which would show
    up as an untracked file in the user's tree and eventually get committed by someone.
    """
    backups = os.path.join(bonsai_dir, ".state", "backups")
    os.makedirs(backups, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    name = f"{stamp}-{target.replace('/', '_')}"
    shutil.copy2(dest, os.path.join(backups, name))
    return os.path.join(".claude", "bonsai", ".state", "backups", name)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--proposal", required=True)
    ap.add_argument("--project", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--allow-shrink", action="store_true",
                    help="apply even when the result is drastically smaller than the current file")
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

    # D-14. settings.json is exempt: merge_settings is additive, so a shrink there isn't data loss.
    refuse, before_lines, after_lines = (False, 0, 0)
    if existing and not is_settings:
        refuse, before_lines, after_lines = shrink_verdict(existing, final)

    bonsai_dir = os.path.join(project, ".claude", "bonsai")

    # Dry-run reports the verdict rather than failing on it — surfacing the problem at review time is
    # the whole reason /bonsai:review runs this first.
    if args.dry_run:
        print(json.dumps({"ok": True, "dry_run": True, "target": target, "action": mode,
                          "bytes": len(final), "existing_lines": before_lines,
                          "proposed_lines": after_lines,
                          "shrink_refused": refuse and not args.allow_shrink}, indent=2))
        return 0

    if refuse and not args.allow_shrink:
        fail(
            f"refusing to shrink '{target}' from {before_lines} to {after_lines} non-blank lines. "
            "A proposal's fenced block must be the ENTIRE resulting file, not just the changed "
            "part. If this really is intended, re-run with --allow-shrink."
        )

    backup = back_up(dest, target, bonsai_dir) if existing else None

    os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(final)

    stamp = datetime.now(timezone.utc).replace(microsecond=0).isoformat()

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
        "backup": backup,
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
        "backup": backup,
    }, indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:
        fail(str(exc))
