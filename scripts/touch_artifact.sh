#!/bin/sh
# bonsai — record that an instruction artifact was actually loaded.
#
# Fires on InstructionsLoaded, which is informational only: it has no output control and its exit code is
# ignored, so this can never interrupt or block. That property is why staleness tracking is allowed to be a
# hook at all (reference/etiquette.md rule 1).
#
# Appends `<date> <relpath>` to .claude/bonsai/.state/exercised, at most once per artifact per day.
# prune_scan.py reads that log to compute last_exercised. An append-only log is deliberate: this fires
# repeatedly per session, so it must be fast, must not parse JSON, and must tolerate concurrent writers.
#
# Hot path. Pure POSIX sh, forever. No python3.

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/.claude/bonsai"
[ -f "$DIR/config.json" ] || exit 0
[ -e "$DIR/paused" ] && exit 0

payload=$(cat 2>/dev/null || true)

# Single field, no JSON parser. Bail rather than guess if it isn't there.
path=$(printf '%s' "$payload" \
    | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$path" ] || exit 0

# Store repo-relative so the log survives clones and worktrees.
case "$path" in
    "$ROOT"/*) rel=${path#"$ROOT"/} ;;
    /*)        exit 0 ;;   # outside the project: user-level rules aren't ours to track
    *)         rel=$path ;;
esac

STATE="$DIR/.state"
LOG="$STATE/exercised"
mkdir -p "$STATE" 2>/dev/null || exit 0

today=$(date +%Y-%m-%d)
entry="$today $rel"

# Already recorded today? Nothing to do. Checking the tail bounds the cost as the log grows.
if [ -f "$LOG" ] && tail -n 400 "$LOG" 2>/dev/null | grep -qxF "$entry"; then
    exit 0
fi

printf '%s\n' "$entry" >>"$LOG" 2>/dev/null || true

# Keep the log bounded. Only the most recent date per artifact matters, so trimming loses nothing.
lines=$(wc -l < "$LOG" 2>/dev/null | tr -d ' ')
case "$lines" in ''|*[!0-9]*) lines=0 ;; esac
if [ "$lines" -gt 2000 ]; then
    tail -n 500 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG" 2>/dev/null || rm -f "$LOG.tmp"
fi

exit 0
