#!/usr/bin/env python3
"""Keep docs/claims.md honest about the landscape claims bonsai makes publicly.

`reference/` docs carry verification stamps because a stale citation makes bonsai confidently wrong. The
same is true one level up, for claims about what *other* tools do — "nobody else records artifact loads."
Those rot faster than citations and nothing noticed the last time one did (docs/backlog.md C-05).

This is the deterministic half (reference/determinism.md): parse the register, resolve each claim to the
exact phrase it's attributed to, and do date math. Judging whether a competitor falsifies a claim is model
work and stays model work — no script can do it, and one that pretended to would be worse than none.

Checks:
  malformed         a claim missing a required field, or an unparseable date/cadence
  missing-file      an Asserted: path that doesn't exist
  orphaned-site     the quoted phrase is gone from the file it's attributed to  ← the drift that matters
  stale-assertion   a retracted claim still asserted publicly
  overdue           past its re-check cadence — a warning, unless --strict

Structural problems fail. Age only warns, so the suite never goes red on a date with no code change; the
quarterly sweep runs --strict and fails on overdue.

Usage: claims_check.py [--repo DIR] [--json] [--strict] [--today YYYY-MM-DD]
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import sys

SECTION_RE = re.compile(r"^##\s+(CLAIM-\d{1,3})\s*[—–-]\s*(.+?)\s*$")
FIELD_RE = re.compile(r"^\s*[-*]\s+\*\*(.+?):\*\*\s*(.*)$")
# `path/to/file.md` — "the exact phrase asserted there". Straight or curly quotes, en/em dash.
SITE_RE = re.compile(r"`([^`]+)`\s*[—–-]\s*[\"“]([^\"”]+)[\"”]")

CADENCES = {"monthly": 30, "quarterly": 90, "semiannual": 182, "annual": 365}
CADENCE_DAYS_RE = re.compile(r"^(\d{1,4})\s*d(?:ays)?$")
REQUIRED = ("Claim", "Asserted", "Verified", "Re-check", "Falsified by")
STATUSES = ("active", "softened", "retracted")


def squash(text: str) -> str:
    """Collapse whitespace so a phrase still matches when markdown wraps it across lines."""
    return re.sub(r"\s+", " ", text)


def parse_register(path: str) -> tuple[list[dict], list[str]]:
    claims: list[dict] = []
    problems: list[str] = []
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return [], []

    current: dict | None = None
    for n, raw in enumerate(lines, 1):
        section = SECTION_RE.match(raw.rstrip())
        if section:
            current = {"id": section.group(1), "title": section.group(2), "line": n, "fields": {}}
            claims.append(current)
            continue
        if current is None:
            continue
        field = FIELD_RE.match(raw.rstrip())
        if field:
            key, value = field.group(1).strip(), field.group(2).strip()
            if key in current["fields"]:
                problems.append(f"{current['id']} repeats field '{key}' at line {n}")
            current["fields"][key] = value

    seen: dict[str, int] = {}
    for claim in claims:
        if claim["id"] in seen:
            problems.append(f"{claim['id']} redefined at line {claim['line']} "
                            f"(first at {seen[claim['id']]})")
        else:
            seen[claim["id"]] = claim["line"]
    return claims, problems


def cadence_days(value: str) -> int | None:
    key = value.strip().lower()
    if key in CADENCES:
        return CADENCES[key]
    m = CADENCE_DAYS_RE.match(key)
    return int(m.group(1)) if m else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd()))
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--strict", action="store_true",
                    help="fail on overdue claims, not just structural problems")
    ap.add_argument("--today", help="override today's date (YYYY-MM-DD), for tests")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    register = os.path.join(repo, "docs", "claims.md")
    claims, malformed = parse_register(register)
    if not claims:
        print(json.dumps({"ok": True, "note": f"no claims found in {register}"}))
        return 0

    try:
        today = (datetime.date.fromisoformat(args.today) if args.today
                 else datetime.date.today())
    except ValueError:
        print(json.dumps({"ok": False, "error": f"bad --today value: {args.today!r}"}))
        return 1

    problems: dict[str, list[str]] = {"malformed": malformed, "missing-file": [],
                                      "orphaned-site": [], "stale-assertion": []}
    overdue: list[str] = []
    contents: dict[str, str] = {}
    summary: list[dict] = []

    for claim in claims:
        ident, fields, line = claim["id"], claim["fields"], claim["line"]
        status = fields.get("Status", "active").strip().lower()
        if status not in STATUSES:
            problems["malformed"].append(
                f"{ident} has unknown Status '{status}' at claims.md:{line} "
                f"(expected one of {', '.join(STATUSES)})")
            status = "active"

        for key in REQUIRED:
            if key == "Asserted" and status == "retracted":
                continue  # a retracted claim has nowhere left to be asserted
            if not fields.get(key):
                problems["malformed"].append(
                    f"{ident} is missing '{key}' at claims.md:{line}")

        verified = None
        if fields.get("Verified"):
            try:
                verified = datetime.date.fromisoformat(fields["Verified"].split()[0])
            except (ValueError, IndexError):
                problems["malformed"].append(
                    f"{ident} has an unparseable Verified date "
                    f"'{fields['Verified']}' at claims.md:{line}")

        days = cadence_days(fields.get("Re-check", ""))
        if fields.get("Re-check") and days is None:
            problems["malformed"].append(
                f"{ident} has an unrecognized Re-check cadence '{fields['Re-check']}' at "
                f"claims.md:{line} (expected one of {', '.join(CADENCES)}, or e.g. '45d')")

        age = None
        if verified is not None:
            age = (today - verified).days
            if age < 0:
                problems["malformed"].append(
                    f"{ident} is verified in the future ({verified}) at claims.md:{line}")
            elif days is not None and age > days:
                overdue.append(f"{ident} last verified {verified}, {age}d > {days}d "
                               f"({fields.get('Re-check')})")

        # Resolve every assertion site to its exact public phrasing. A claim reworded in the README
        # without touching the register is a structural inconsistency, not a scheduling problem.
        sites = SITE_RE.findall(fields.get("Asserted", ""))
        if fields.get("Asserted") and not sites and status != "retracted":
            problems["malformed"].append(
                f"{ident} has an Asserted field no site parsed out of, at claims.md:{line} "
                f'(expected: `path` — "quoted phrase")')

        for rel, phrase in sites:
            target = os.path.join(repo, rel)
            if rel not in contents:
                try:
                    with open(target, encoding="utf-8") as fh:
                        contents[rel] = squash(fh.read())
                except OSError:
                    contents[rel] = ""
                    problems["missing-file"].append(
                        f"{ident} cites {rel}, which cannot be read (claims.md:{line})")
            if not contents[rel]:
                continue
            present = squash(phrase) in contents[rel]
            if status == "retracted" and present:
                problems["stale-assertion"].append(
                    f'{ident} is retracted but {rel} still asserts "{phrase}"')
            elif status != "retracted" and not present:
                problems["orphaned-site"].append(
                    f'{ident} cites {rel} for "{phrase}", which is not there any more — '
                    f"the claim moved or was reworded (claims.md:{line})")

        summary.append({"id": ident, "status": status, "sites": len(sites),
                        "verified": str(verified) if verified else None, "age_days": age})

    failures = {k: v for k, v in problems.items() if v}
    if args.strict and overdue:
        failures["overdue"] = overdue

    result = {
        "ok": not failures,
        "claims": len(claims),
        "active": sum(1 for c in summary if c["status"] == "active"),
        "retracted": sum(1 for c in summary if c["status"] == "retracted"),
        "sites_resolved": sum(c["sites"] for c in summary),
        "overdue": overdue,
        "problems": failures,
        "detail": summary,
    }

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if failures:
            print("claims register is out of sync:")
            for kind, msgs in failures.items():
                for msg in msgs:
                    print(f"  [{kind}] {msg}")
        else:
            print(f"claims register sound: {result['claims']} "
                  f"claim{'' if result['claims'] == 1 else 's'}, "
                  f"{result['sites_resolved']} assertion sites resolved, "
                  f"{result['retracted']} retracted")
        # Warnings, not failures — unless --strict already promoted them above.
        if overdue and not args.strict:
            for msg in overdue:
                print(f"  [warn overdue] {msg}")

    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        sys.exit(1)
