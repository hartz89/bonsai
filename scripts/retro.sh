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

# Flow-state guards — reference/etiquette.md rule 5. Every threshold here is a suppression
# threshold, so the safe direction is always "don't suppress": below the minimum sample sizes the
# signal is noise and the retrospective runs.
FAST_GAP_SECONDS=20      # a gap between consecutive human prompts shorter than this is "rapid"
MIN_GAPS_FOR_MEDIAN=8    # fewer measurable gaps than this and the median means nothing
MIN_TOOLS_FOR_LOOP=10    # fewer tool calls than this and the edit-loop ratio means nothing
EDIT_LOOP_PERCENT=60     # >this% of all tool calls landing on the top two edited files
TAIL_RECORDS=20          # how many trailing transcript records the failure guard reads

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

# --- Flow-state signals: one awk pass over the transcript, no model, no python. ---------------
#
# Emits four integers: <measurable prompt gaps> <gaps under FAST_GAP_SECONDS> <tool calls>
# <top-two-file edit count>. Sidechain (subagent) records are excluded throughout: they interleave
# with the main thread, so their timestamps would fabricate gaps no human ever sat through.
#
# Cost is one linear scan with no sorting and no per-line subprocess, so it stays flat on a
# multi-megabyte transcript. Any awk failure yields empty output, and empty output suppresses
# nothing.
signals=$(awk -v fast="$FAST_GAP_SECONDS" '
    # Days-from-civil (Howard Hinnant); avoids one date(1) fork per line.
    function epoch(ts,   y, mo, d, h, mi, s, a, era, yoe, doy, doe) {
        if (length(ts) < 19 || substr(ts, 5, 1) != "-" || substr(ts, 11, 1) != "T") return -1
        y = substr(ts, 1, 4) + 0; mo = substr(ts, 6, 2) + 0; d = substr(ts, 9, 2) + 0
        h = substr(ts, 12, 2) + 0; mi = substr(ts, 15, 2) + 0; s = substr(ts, 18, 2) + 0
        if (y < 1970 || mo < 1 || mo > 12 || d < 1 || d > 31) return -1
        a = (mo <= 2) ? 1 : 0
        y -= a
        era = int(y / 400); yoe = y - era * 400
        doy = int((153 * (mo + (a ? 9 : -3)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return (era * 146097 + doe - 719468) * 86400 + h * 3600 + mi * 60 + s
    }
    # Attribute each Edit/Write-shaped tool call to the file_path that follows it on the line.
    function edits_on(line,   fp) {
        while (match(line, /"name":"(Edit|MultiEdit|Write|NotebookEdit)"/)) {
            line = substr(line, RSTART + RLENGTH)
            if (!match(line, /"file_path":"[^"]*"/)) break
            fp = substr(line, RSTART + 13, RLENGTH - 14)
            edits[fp]++
            line = substr(line, RSTART + RLENGTH)
        }
    }
    /"isSidechain":[ ]*true/ { next }
    {
        tools += gsub(/"type":"tool_use"/, "&")
        edits_on($0)
        # A "turn" for gap purposes is a human prompt, not an assistant record. One assistant turn
        # emits a record per tool call, seconds apart, so timing assistant records would score
        # every tool-heavy session as frantic. Tool results and the harness meta records that
        # wrap slash commands are user-typed by shape only, and are excluded.
        if ($0 !~ /"type":"user"/) next
        if ($0 ~ /"type":"tool_result"/ || $0 ~ /"isMeta":[ ]*true/) next
        if (!match($0, /"timestamp":"[^"]*"/)) next
        t = epoch(substr($0, RSTART + 13, RLENGTH - 14))
        if (t < 0) next
        if (prev > 0 && t >= prev) { gaps++; if (t - prev < fast) quick++ }
        prev = t
    }
    END {
        for (f in edits) {
            if (edits[f] > m1) { m2 = m1; m1 = edits[f] }
            else if (edits[f] > m2) { m2 = edits[f] }
        }
        printf "%d %d %d %d\n", gaps + 0, quick + 0, tools + 0, m1 + m2
    }' "$TRANSCRIPT" 2>/dev/null)

log "signals (gaps quick tools hot): ${signals:-unavailable}"

case "$signals" in
    [0-9]*' '[0-9]*' '[0-9]*' '[0-9]*)
        # shellcheck disable=SC2086  # four validated integers, deliberate word split
        set -- $signals
        gaps=$1; quick=$2; tools=$3; hot=$4

        # Rapid back-and-forth. "Median prompt gap under 20s" is evaluated without sorting: the
        # median is under the threshold exactly when strictly more than half the gaps are.
        # Sessions with a thin sample fail open.
        if [ "$gaps" -ge "$MIN_GAPS_FOR_MEDIAN" ] && [ $((quick * 2)) -gt "$gaps" ]; then
            die "rapid iteration: $quick/$gaps turn gaps under ${FAST_GAP_SECONDS}s"
        fi

        # Tight debug loop: the two most-edited files account for more than 60% of *all* tool
        # calls, not just of the edits — reading and running things around an edit is normal work,
        # hammering save on the same two files is not.
        if [ "$tools" -ge "$MIN_TOOLS_FOR_LOOP" ] &&
           [ $((hot * 100)) -gt $((tools * EDIT_LOOP_PERCENT)) ]; then
            die "tight edit loop: $hot/$tools tool calls edit the same 1-2 files"
        fi
        ;;
esac

# Ended on a failure. Deliberately narrow and deliberately recent: only the last TAIL_RECORDS
# transcript records are read, and only for an errored tool result or an unambiguous test-failure
# banner. It does not try to decide whether the error was later fixed — it asks the cheaper
# question "was the last thing that happened a failure", which is the thing rule 5 cares about.
# A count of zero failures ("0 failed") deliberately does not match.
if tail -n "$TAIL_RECORDS" "$TRANSCRIPT" 2>/dev/null | grep -Eq \
    '"is_error":[ ]*true|<tool_use_error>|[1-9][0-9]* (tests? )?(failed|failures)|FAILED|Traceback \(most recent call last\)'
then
    die "session ended on a failure"
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
