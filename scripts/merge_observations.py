#!/usr/bin/env python3
"""Merge a retrospective's JSON output into observations.jsonl and report threshold crossings.

Counters and confidence are computed here, deterministically, rather than by the model. A model that
invents a new id for a recurring pattern would silently reset its own counter, so id matching, session
de-duplication, expiry, and reversals are all mechanical.

Reads agent JSON on stdin. Writes space-separated crossed ids on stdout. Exits 0 on any input problem
with no output: bonsai never breaks a session.

See reference/thresholds.md — this file is that document, executed.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
from datetime import datetime, timedelta, timezone

OCCURRENCE_TTL_DAYS = 45
CONFIDENCE_FLOOR = 0.6
EXCERPT_MAX = 200
EMISSION_COOLDOWN_HOURS = 24

# thresholds.md § Thresholds by signal class (team tier)
BASE_THRESHOLDS = {
    "constraint": 1,
    "directive": 1,
    "fact": 2,
    "reference": 2,
    "preference": 3,
    "procedure": 3,
    "repeated-prompt": 3,
    "context-heavy": 3,
}
TIER_MODIFIER = {"solo": -1, "team": 0, "enterprise": 1}

SECRET_PATTERNS = [
    re.compile(r"(?i)\b(?:api[_-]?key|secret|passwd|password|token|bearer)\b\s*[:=]\s*\S+"),
    re.compile(r"\b(?:gh[pousr]|github_pat)_[A-Za-z0-9_]{16,}"),
    re.compile(r"\bsk-[A-Za-z0-9]{16,}"),
    re.compile(r"\b(?:postgres|postgresql|mysql|mongodb(?:\+srv)?|redis)://[^\s]+"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\."),
]


def now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime) -> str:
    return dt.replace(microsecond=0).isoformat()


def parse_iso(value: str) -> datetime | None:
    try:
        dt = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def scrub(text: object) -> str:
    """Truncate and redact. The agent is told to do this; we enforce it regardless."""
    s = " ".join(str(text or "").split())[:EXCERPT_MAX]
    for pattern in SECRET_PATTERNS:
        s = pattern.sub("[redacted]", s)
    return s


def load_jsonl(path: str) -> dict[str, dict]:
    out: dict[str, dict] = {}
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue  # tolerate a partial write rather than losing the file
            if isinstance(rec, dict) and rec.get("id"):
                out[rec["id"]] = rec
    return out


def write_jsonl(path: str, records: dict[str, dict]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            for rec in sorted(records.values(), key=lambda r: r["id"]):
                fh.write(json.dumps(rec, separators=(",", ":")) + "\n")
        os.replace(tmp, path)  # atomic; a crash mid-write can't corrupt the ledger
    except Exception:
        os.path.exists(tmp) and os.unlink(tmp)
        raise


def expire(rec: dict) -> None:
    cutoff = now() - timedelta(days=OCCURRENCE_TTL_DAYS)
    kept = []
    for occ in rec.get("occurrences", []):
        ts = parse_iso(occ.get("ts", ""))
        if ts is None or ts >= cutoff:
            kept.append(occ)
    rec["occurrences"] = kept
    rec["distinct_sessions"] = len({o.get("session") for o in kept if o.get("session")})


def confidence(rec: dict, threshold: int) -> float:
    # Meeting the threshold is what confers baseline confidence: the threshold *is* the bar. Starting
    # below the floor here would mean nothing that exactly met its threshold could ever be proposed.
    surplus = rec.get("distinct_sessions", 0) - threshold
    score = CONFIDENCE_FLOOR if surplus >= 0 else CONFIDENCE_FLOOR - 0.2
    if surplus > 0:
        score += 0.1 * surplus
    if rec.get("explicit"):
        score += 0.2
    stamps = sorted(t for t in (parse_iso(o.get("ts", "")) for o in rec.get("occurrences", [])) if t)
    if len(stamps) >= 2 and (stamps[-1] - stamps[0]) > timedelta(days=7):
        score += 0.1
    if rec.get("repo_corroborated"):
        score += 0.1
    if rec.get("untrusted_source"):
        score -= 0.2
    if rec.get("conflicts_with"):
        score -= 0.3
    if rec.get("class") == "preference" and not rec.get("path_correlation"):
        score -= 0.1
    return max(0.0, min(1.0, round(score, 2)))


def threshold_for(rec: dict, tier: str, archived: set[str]) -> int:
    base = BASE_THRESHOLDS.get(rec.get("class", "preference"), 3)
    base += TIER_MODIFIER.get(tier, 0)
    if rec["id"] in archived:
        base += 2  # declined by silence once already
    return max(1, base)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="path to .claude/bonsai")
    ap.add_argument("--session", default="")
    args = ap.parse_args()

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    if not isinstance(payload, dict):
        return 0

    base = args.dir
    ledger_path = os.path.join(base, "observations.jsonl")
    session = payload.get("session") or args.session or "unknown"

    tier = "team"
    try:
        with open(os.path.join(base, "config.json"), encoding="utf-8") as fh:
            tier = json.load(fh).get("tier", "team")
    except (OSError, json.JSONDecodeError):
        pass

    archived = {
        os.path.splitext(f)[0]
        for f in os.listdir(os.path.join(base, "archive"))
        if f.endswith(".md")
    } if os.path.isdir(os.path.join(base, "archive")) else set()

    pending = {
        os.path.splitext(f)[0]
        for f in os.listdir(os.path.join(base, "proposals"))
        if f.endswith(".md")
    } if os.path.isdir(os.path.join(base, "proposals")) else set()

    ledger = load_jsonl(ledger_path)
    stamp = iso(now())

    # Reversals first: a contradicted pattern must re-earn its threshold from scratch, and must not be
    # re-promoted by an observation arriving in the same batch.
    for rev in payload.get("reversals") or []:
        rid = (rev or {}).get("id")
        if rid and rid in ledger:
            ledger[rid].update(
                occurrences=[],
                distinct_sessions=0,
                reversed_at=stamp,
                reversal_excerpt=scrub(rev.get("excerpt")),
            )

    reversed_now = {(r or {}).get("id") for r in (payload.get("reversals") or [])}

    for obs in payload.get("observations") or []:
        if not isinstance(obs, dict):
            continue
        oid = obs.get("id")
        if not oid or oid in reversed_now:
            continue

        rec = ledger.get(oid) or {
            "id": oid,
            "class": obs.get("class", "preference"),
            "statement": scrub(obs.get("statement")),
            "occurrences": [],
            "first_seen": stamp,
        }
        rec["class"] = obs.get("class", rec.get("class", "preference"))
        rec["statement"] = rec.get("statement") or scrub(obs.get("statement"))
        rec["last_seen"] = stamp
        if obs.get("untrusted_source"):
            rec["untrusted_source"] = True
        if obs.get("files_read"):
            rec["files_read"] = obs["files_read"]
        if obs.get("path_correlation"):
            rec["path_correlation"] = obs["path_correlation"]

        # One occurrence per session, however many times it came up inside it.
        if not any(o.get("session") == session for o in rec["occurrences"]):
            rec["occurrences"].append(
                {"session": session, "ts": stamp, "excerpt": scrub(obs.get("excerpt"))}
            )

        expire(rec)
        ledger[oid] = rec

    crossed = []
    for oid, rec in ledger.items():
        expire(rec)
        need = threshold_for(rec, tier, archived)
        rec["threshold_required"] = need
        rec["confidence"] = confidence(rec, need)

        if oid in pending or rec.get("promoted_at"):
            continue
        if rec.get("untrusted_source") and not rec.get("repo_corroborated"):
            continue  # thresholds.md § Never promote — injection surface

        # Don't re-emit a crossing the drafting pass is already handling. Expires so that a pass which
        # crashed before writing its proposal gets retried rather than lost forever.
        emitted = parse_iso(rec.get("crossing_emitted_at", ""))
        if emitted and (now() - emitted) < timedelta(hours=EMISSION_COOLDOWN_HOURS):
            continue

        if rec["distinct_sessions"] >= need and rec["confidence"] >= CONFIDENCE_FLOOR:
            rec["crossing_emitted_at"] = stamp
            crossed.append(oid)

    write_jsonl(ledger_path, ledger)

    if crossed:
        sys.stdout.write(" ".join(sorted(crossed)))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:  # never surface a traceback into a hook
        sys.exit(0)
