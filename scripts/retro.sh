#!/bin/sh
# bonsai — SessionEnd / PreCompact observation.
#
# Runs the guards, then detaches. Nothing here is ever awaited by the user: the session is already
# over (SessionEnd) or about to be compacted (PreCompact). Every failure path exits 0 silently.
#
# Two model passes, both Haiku, the second only when a threshold actually crossed:
#   1. bonsai-retrospective reads the transcript and emits observations (read-only agent).
#   2. /bonsai:promote drafts proposals for whatever crossed. Skipped almost every time.
#
# Counters are merged by merge_observations.py, not by the model — see reference/thresholds.md.

set -u

MIN_TURNS=8
MIN_SECONDS_BETWEEN_RUNS=3600

log() { [ -n "${BONSAI_DEBUG:-}" ] && printf 'bonsai: %s\n' "$1" >&2; return 0; }
die() { log "$1"; exit 0; }

payload=$(cat 2>/dev/null || true)

field() {
    printf '%s' "$payload" \
        | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
        | head -1
}

TRANSCRIPT=$(field transcript_path)
SESSION=$(field session_id)

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/.claude/bonsai"
STATE="$DIR/.state"

# ---------------------------------------------------------------------------
# Guards. All cheap, all before any model spawns. See reference/etiquette.md rule 5.
# ---------------------------------------------------------------------------

[ -f "$DIR/config.json" ] || die "not installed"
[ -e "$DIR/paused" ] && die "paused"

# Plugin userConfig: exported as CLAUDE_PLUGIN_OPTION_<KEY>. Absent means default (on).
case "${CLAUDE_PLUGIN_OPTION_RETROSPECTIVE:-true}" in
    false|0|off|no) die "retrospective disabled" ;;
esac

command -v claude >/dev/null 2>&1 || die "claude not on PATH"

[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || die "no transcript"

# Nothing durable comes out of a short session.
turns=$(grep -c '"role"[[:space:]]*:[[:space:]]*"assistant"' "$TRANSCRIPT" 2>/dev/null || echo 0)
[ "$turns" -lt "$MIN_TURNS" ] && die "only $turns turns"

# Mid-operation: the user is in the middle of something. Skip, don't defer.
GITDIR="$ROOT/.git"
if [ -e "$GITDIR" ]; then
    for marker in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD BISECT_LOG REVERT_HEAD; do
        [ -e "$GITDIR/$marker" ] && die "mid-operation: $marker"
    done
fi

mkdir -p "$STATE" 2>/dev/null || die "cannot write state"

# Rate limit: at most one run per hour per repo.
now=$(date +%s)
last=0
[ -f "$STATE/last-run" ] && last=$(cat "$STATE/last-run" 2>/dev/null || echo 0)
case "$last" in ''|*[!0-9]*) last=0 ;; esac
[ $((now - last)) -lt "$MIN_SECONDS_BETWEEN_RUNS" ] && die "rate limited"

# Daily cap.
limit="${CLAUDE_PLUGIN_OPTION_DAILY_LIMIT:-6}"
case "$limit" in ''|*[!0-9]*) limit=6 ;; esac
[ "$limit" -eq 0 ] && die "daily limit is 0"
today=$(date +%Y-%m-%d)
countfile="$STATE/count-$today"
used=0
[ -f "$countfile" ] && used=$(cat "$countfile" 2>/dev/null || echo 0)
case "$used" in ''|*[!0-9]*) used=0 ;; esac
[ "$used" -ge "$limit" ] && die "daily cap reached ($used/$limit)"

# Drop stale day counters before claiming today's slot, so this never deletes the file it just wrote.
for stale in "$STATE"/count-*; do
    [ -f "$stale" ] || continue
    [ "$stale" = "$countfile" ] || rm -f "$stale" 2>/dev/null || true
done

# Claim the slot before detaching so concurrent sessions can't both run.
printf '%s' "$now" >"$STATE/last-run" 2>/dev/null || true
printf '%s' "$((used + 1))" >"$countfile" 2>/dev/null || true

MODEL="${CLAUDE_PLUGIN_OPTION_RETROSPECTIVE_MODEL:-haiku}"
HERE="${CLAUDE_PLUGIN_ROOT:-$(dirname "$0")/..}"

# ---------------------------------------------------------------------------
# Detached work. Survives session teardown; output goes nowhere the user sees.
# ---------------------------------------------------------------------------

work() {
    observations=$(
        claude -p "Read the transcript at $TRANSCRIPT for session $SESSION and report observations." \
            --agent bonsai-retrospective \
            --model "$MODEL" \
            2>/dev/null
    ) || return 0

    [ -n "$observations" ] || return 0

    crossed=$(
        printf '%s' "$observations" \
            | python3 "$HERE/scripts/merge_observations.py" --dir "$DIR" --session "$SESSION" \
            2>/dev/null
    ) || return 0

    [ -n "$crossed" ] || return 0

    # Something earned promotion. Draft proposals with the same policy the manual path uses.
    claude -p "/bonsai:promote --from-observations $crossed" \
        --model "$MODEL" \
        --permission-mode acceptEdits \
        >/dev/null 2>&1 || true
}

if [ -n "${BONSAI_SYNC:-}" ]; then
    work                     # tests run this synchronously
else
    ( work </dev/null >/dev/null 2>&1 & ) &
fi

exit 0
