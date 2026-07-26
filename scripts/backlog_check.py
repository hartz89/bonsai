#!/usr/bin/env python3
"""Keep docs/backlog.md honest against git history.

The backlog is only useful if it reflects reality, and reality drifts the moment an agent finishes an item
and forgets to strike it. This is the deterministic half of that problem (reference/determinism.md): parse
the backlog, parse commit messages for item references, and report disagreement.

Checks:
  duplicate-id      the same ID defined twice
  undone            an ID referenced by a commit but still open in the backlog   ← the drift that matters
  unreferenced      an ID marked done with no commit mentioning it
  phantom           an ID referenced by a commit that the backlog never defines
  phase-mismatch    backlog phase headings out of step with roadmap.md

Exit 1 if any check fails, so it can gate a test run.

Usage: backlog_check.py [--repo DIR] [--json]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

ID_RE = re.compile(r"\b([A-Z]{1,2}-\d{1,3}[a-z]?)\b")
ROW_RE = re.compile(r"^\|\s*(~~)?\s*([A-Z]{1,2}-\d{1,3}[a-z]?)\s*(~~)?\s*\|(.*)$")
PHASE_RE = re.compile(r"^##\s+(Phase\s+\d+|Runtime robustness|Continuous)\b.*$", re.MULTILINE)
TRAILER_RE = re.compile(r"^(?:Backlog|Resolves|Closes|Fixes):", re.IGNORECASE)
DONE_MARKERS = ("**Done.**", "**Fixed.**", "~~")


def git(repo: str, *args: str) -> str:
    try:
        return subprocess.run(("git", "-C", repo, *args), capture_output=True, text=True,
                              timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def parse_backlog(path: str) -> tuple[dict[str, dict], list[str]]:
    items: dict[str, dict] = {}
    dupes: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return {}, []

    for n, line in enumerate(lines, 1):
        m = ROW_RE.match(line.rstrip())
        if not m:
            continue
        struck, ident, _, rest = m.group(1), m.group(2), m.group(3), m.group(4)
        done = bool(struck) or any(mark in rest for mark in DONE_MARKERS)
        if ident in items:
            dupes.append(f"{ident} redefined at line {n} (first at {items[ident]['line']})")
            continue
        items[ident] = {"line": n, "done": done}
    return items, dupes


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    items, dupes = parse_backlog(os.path.join(repo, "docs", "backlog.md"))
    if not items:
        print(json.dumps({"ok": True, "note": "no backlog items found"}))
        return 0

    # Two distinct signals. A bare mention is ambiguous — a commit that *creates* an item mentions it
    # too — so only an explicit trailer counts as "resolved". Mentions are still tracked, because they're
    # forgiving evidence for the reverse check.
    log = git(repo, "log", "--format=%H%x00%B%x00%x00", "--no-merges")
    resolved: dict[str, str] = {}
    mentioned: dict[str, str] = {}
    for entry in log.split("\x00\x00"):
        if "\x00" not in entry:
            continue
        sha, body = entry.split("\x00", 1)
        short = sha.strip()[:9]
        for ident in set(ID_RE.findall(body)):
            mentioned.setdefault(ident, short)
        for line in body.splitlines():
            if TRAILER_RE.match(line.strip()):
                for ident in set(ID_RE.findall(line)):
                    resolved.setdefault(ident, short)
    referenced = {**mentioned, **resolved}

    problems: dict[str, list[str]] = {"duplicate-id": dupes, "undone": [], "unreferenced": [],
                                      "phantom": [], "phase-mismatch": []}

    for ident, sha in sorted(referenced.items()):
        if ident not in items:
            problems["phantom"].append(f"{ident} referenced by {sha} but not defined in the backlog")

    for ident, sha in sorted(resolved.items()):
        if ident in items and not items[ident]["done"]:
            problems["undone"].append(
                f"{ident} has a resolving commit ({sha}) but is still open at "
                f"backlog.md:{items[ident]['line']}")

    for ident, meta in sorted(items.items()):
        if meta["done"] and ident not in referenced:
            problems["unreferenced"].append(
                f"{ident} marked done at backlog.md:{meta['line']} with no commit referencing it")

    # Phase headings should agree between the two planning docs.
    def phases(rel: str) -> list[str]:
        try:
            with open(os.path.join(repo, "docs", rel), encoding="utf-8") as fh:
                return [m.group(1) for m in PHASE_RE.finditer(fh.read())]
        except OSError:
            return []

    b_phases = [p for p in phases("backlog.md") if p.startswith("Phase")]
    r_phases = [p for p in phases("roadmap.md") if p.startswith("Phase")]
    if b_phases and r_phases and b_phases != r_phases:
        problems["phase-mismatch"].append(
            f"backlog phases {b_phases} do not match roadmap phases {r_phases}")

    failures = {k: v for k, v in problems.items() if v}
    result = {
        "ok": not failures,
        "items": len(items),
        "done": sum(1 for m in items.values() if m["done"]),
        "resolved_by_commits": len(resolved),
        "mentioned_in_commits": len(mentioned),
        "problems": failures,
    }

    if args.json:
        print(json.dumps(result, indent=2))
    elif failures:
        print("backlog is out of sync with git history:")
        for kind, msgs in failures.items():
            for msg in msgs:
                print(f"  [{kind}] {msg}")
    else:
        print(f"backlog in sync: {result['done']}/{result['items']} done, "
              f"{result['resolved_by_commits']} closed by trailer, "
              f"{result['mentioned_in_commits']} mentioned")

    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
