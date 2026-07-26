#!/bin/sh
# bonsai — SessionStart surfacing.
#
# Emits at most one line telling the user how many proposals are pending. No model call, no file
# content, no second reminder. Must finish in well under a second or exit silently.
#
# Also implements the etiquette back-off: proposals ignored for 7+ session starts are archived
# silently rather than nagged about. See reference/etiquette.md rule 4.
#
# Reads the hook payload on stdin (unused — cwd is already correct) and writes a JSON object with
# `additionalContext` on stdout. Any failure exits 0 with no output: bonsai never breaks a session.

set -u

ARCHIVE_AFTER=7
ITEMIZE_UNTIL=3

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/.claude/bonsai"
PROPOSALS="$DIR/proposals"
ARCHIVE="$DIR/archive"
SEEN="$DIR/.state/seen"

# Not installed, or paused. Silence is the default state.
[ -d "$PROPOSALS" ] || exit 0
[ -e "$DIR/paused" ] && exit 0

# Drain stdin so the hook runner never blocks on a full pipe.
cat >/dev/null 2>&1 || true

mkdir -p "$SEEN" 2>/dev/null || exit 0

visible=0
fresh=0

for p in "$PROPOSALS"/*.md; do
    [ -f "$p" ] || continue
    slug=$(basename "$p" .md)
    counter="$SEEN/$slug"

    n=0
    [ -f "$counter" ] && n=$(cat "$counter" 2>/dev/null || echo 0)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    printf '%s' "$n" >"$counter" 2>/dev/null || true

    if [ "$n" -ge "$ARCHIVE_AFTER" ]; then
        # Declined by silence. Archive without comment; a re-observed pattern can resurface later at a
        # raised threshold (see reference/thresholds.md).
        mkdir -p "$ARCHIVE" 2>/dev/null && mv "$p" "$ARCHIVE/$slug.md" 2>/dev/null || true
        rm -f "$counter" 2>/dev/null || true
        continue
    fi

    visible=$((visible + 1))
    [ "$n" -le "$ITEMIZE_UNTIL" ] && fresh=$((fresh + 1))
done

[ "$visible" -eq 0 ] && exit 0

if [ "$fresh" -gt 0 ]; then
    noun="proposal"; [ "$visible" -gt 1 ] && noun="proposals"
    msg="$visible bonsai $noun pending — /bonsai:review"
else
    # Everything pending has already been shown several times. Stay counted, stop drawing attention.
    msg="$visible bonsai proposals still pending (quieted) — /bonsai:review"
fi

# Escape for JSON: this string contains no user content, but stay safe anyway.
esc=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"additionalContext":"%s"}\n' "$esc"
exit 0
