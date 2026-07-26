#!/bin/sh
# bonsai — environment pre-flight and degradation-tier detection.
#
# Probes the four things bonsai can depend on (`sh`, `git`, `python3`/`python`, `gh`), computes the
# degradation tier from docs/roadmap.md, and names a one-line fix for anything missing. bonsai never
# installs software: it detects the gap, offers the command, and degrades in the meantime.
#
# Runs at install and is cached. Probing the environment on every SessionStart would violate the cost
# contract, so nothing on the hot path should call this without --refresh intent.
#
# Pure POSIX sh by necessity — the whole point is to run on a machine with no python3.
#
# Usage: preflight.sh [--project DIR] [--refresh]
#   --refresh   ignore any cached result and probe again
#
# Emits one JSON object on stdout. Any failure exits 0 with no stdout; BONSAI_DEBUG=1 logs to stderr.

set -u

SCHEMA=1
CACHE_REL=".claude/bonsai/.state/preflight.json"

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
REFRESH=false

while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT="${2:-$PROJECT}"; shift 2 || break ;;
        --refresh|--force) REFRESH=true; shift ;;
        *) shift ;;
    esac
done

debug() { [ -n "${BONSAI_DEBUG:-}" ] && printf 'preflight: %s\n' "$1" >&2; return 0; }
die()   { printf 'preflight: %s\n' "$1" >&2; exit 0; }

cd "$PROJECT" 2>/dev/null || die "cannot cd to project: $PROJECT"
PROJECT=$PWD
CACHE="$PROJECT/$CACHE_REL"

# --- cached result -----------------------------------------------------------
# The cache is authoritative until someone asks for a re-probe or the schema moves. A machine's
# toolchain changes far less often than a session starts.
if [ "$REFRESH" = false ] && [ -f "$CACHE" ]; then
    if grep -q "\"schema\": $SCHEMA," "$CACHE" 2>/dev/null && grep -q '"tier":' "$CACHE" 2>/dev/null; then
        debug "serving cached result from $CACHE_REL"
        sed 's/"cached": false/"cached": true/' "$CACHE" 2>/dev/null && exit 0
        die "cache unreadable: $CACHE_REL"
    fi
    debug "cache present but unusable; re-probing"
fi

# --- probe -------------------------------------------------------------------
j_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'; }

# First token that looks like a version number, from whatever the tool prints.
ver_of() { awk '{for(i=1;i<=NF;i++) if ($i ~ /^[0-9]+\.[0-9]/) {print $i; exit}}'; }

SH_PATH=$(command -v sh 2>/dev/null || printf '')
GIT_PATH=$(command -v git 2>/dev/null || printf '')
GH_PATH=$(command -v gh 2>/dev/null || printf '')

# python3 first; a bare `python` only counts when it is actually Python 3.
PY_CMD=""; PY_PATH=""
if p=$(command -v python3 2>/dev/null) && [ -n "$p" ]; then
    PY_CMD=python3; PY_PATH=$p
elif p=$(command -v python 2>/dev/null) && [ -n "$p" ]; then
    if "$p" -c 'import sys; raise SystemExit(0 if sys.version_info[0] >= 3 else 1)' 2>/dev/null; then
        PY_CMD=python; PY_PATH=$p
    else
        debug "found python at $p but it is not Python 3"
    fi
fi

SH_VER=""
GIT_VER=""; [ -n "$GIT_PATH" ] && GIT_VER=$(git --version 2>/dev/null | ver_of)
GH_VER="";  [ -n "$GH_PATH" ]  && GH_VER=$(gh --version 2>/dev/null | head -n1 | ver_of)
PY_VER="";  [ -n "$PY_PATH" ]  && PY_VER=$("$PY_PATH" -V 2>&1 | ver_of)

debug "sh=${SH_PATH:-none} git=${GIT_PATH:-none} python=${PY_PATH:-none} gh=${GH_PATH:-none}"

# --- how would this user install something? ----------------------------------
# Named, never run. bonsai does not install software on someone's machine (roadmap §2).
PKG=none
if [ "$(uname -s 2>/dev/null || printf '')" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
    PKG=brew
elif command -v apt-get >/dev/null 2>&1; then PKG=apt
elif command -v dnf     >/dev/null 2>&1; then PKG=dnf
elif command -v pacman  >/dev/null 2>&1; then PKG=pacman
elif command -v apk     >/dev/null 2>&1; then PKG=apk
elif [ "$(uname -s 2>/dev/null || printf '')" = "Darwin" ]; then PKG=darwin
fi

fix_for() {
    case "$PKG" in
        brew)   printf 'brew install %s' "$1" ;;
        apt)    printf 'sudo apt-get install -y %s' "$1" ;;
        dnf)    printf 'sudo dnf install -y %s' "$1" ;;
        pacman) printf 'sudo pacman -S %s' "$1" ;;
        apk)    printf 'sudo apk add %s' "$1" ;;
        darwin) printf 'install Homebrew (https://brew.sh), then: brew install %s' "$1" ;;
        *)      printf 'install %s with your system package manager' "$1" ;;
    esac
}

# --- tier (docs/roadmap.md §2, the degradation ladder) -----------------------
if [ -z "$SH_PATH" ]; then
    TIER=unsupported
elif [ -z "$GIT_PATH" ]; then
    TIER=manual
elif [ -z "$PY_PATH" ]; then
    TIER=reduced
else
    TIER=full
fi

case "$TIER" in
    full)        TIER_NOTE="everything works" ;;
    reduced)     TIER_NOTE="surfacing and guards work; threshold merging and apply fall back to the model in-skill" ;;
    manual)      TIER_NOTE="observation is off; /bonsai:promote and /bonsai:review still work, with the agent doing the bookkeeping" ;;
    unsupported) TIER_NOTE="bonsai cannot install here" ;;
esac

# --- missing dependencies, each with its one-line fix ------------------------
MISSING=""
add_missing() { # name required impact fix
    entry=$(printf '{"command":"%s","required":%s,"impact":"%s","fix":"%s"}' \
        "$(j_str "$1")" "$2" "$(j_str "$3")" "$(j_str "$4")")
    if [ -z "$MISSING" ]; then MISSING="$entry"; else MISSING="$MISSING,$entry"; fi
}

[ -z "$SH_PATH" ] && add_missing sh true \
    "every hook and script is POSIX sh; nothing runs without it" \
    "use a POSIX shell — on Windows, WSL or Git Bash"
[ -z "$GIT_PATH" ] && add_missing git true \
    "no observation, no tier detection, no history to learn from" \
    "$(fix_for git)"
[ -z "$PY_PATH" ] && add_missing python3 true \
    "threshold merging, apply, footprint and prune scanning fall back to the model" \
    "$(fix_for python3)"
if [ -z "$GH_PATH" ]; then
    case "$PKG" in
        brew|darwin) ghfix=$(fix_for gh) ;;
        *)           ghfix="see https://cli.github.com/manual/installation" ;;
    esac
    add_missing gh false \
        "branch protection cannot be checked, so tier detection may under-report enterprise" \
        "$ghfix"
fi

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '')

BODY=$(cat <<JSON
{
  "schema": $SCHEMA,
  "probed_at": "$NOW",
  "cached": false,
  "commands": {
    "sh":     { "present": $([ -n "$SH_PATH" ]  && printf true || printf false), "path": "$(j_str "$SH_PATH")",  "version": "$(j_str "$SH_VER")" },
    "git":    { "present": $([ -n "$GIT_PATH" ] && printf true || printf false), "path": "$(j_str "$GIT_PATH")", "version": "$(j_str "$GIT_VER")" },
    "python": { "present": $([ -n "$PY_PATH" ]  && printf true || printf false), "path": "$(j_str "$PY_PATH")",  "version": "$(j_str "$PY_VER")", "command": "$(j_str "$PY_CMD")" },
    "gh":     { "present": $([ -n "$GH_PATH" ]  && printf true || printf false), "path": "$(j_str "$GH_PATH")",  "version": "$(j_str "$GH_VER")" }
  },
  "tier": "$TIER",
  "tier_note": "$(j_str "$TIER_NOTE")",
  "installable": $([ "$TIER" = unsupported ] && printf false || printf true),
  "package_manager": "$PKG",
  "missing": [$MISSING]
}
JSON
)

# --- cache, then emit --------------------------------------------------------
# A cache that cannot be written is a performance problem, not a correctness one: still report.
dir=$(dirname "$CACHE")
if mkdir -p "$dir" 2>/dev/null && printf '%s\n' "$BODY" > "$CACHE.tmp" 2>/dev/null; then
    mv "$CACHE.tmp" "$CACHE" 2>/dev/null || { rm -f "$CACHE.tmp" 2>/dev/null; debug "could not move cache into place"; }
else
    rm -f "$CACHE.tmp" 2>/dev/null
    printf 'preflight: could not cache result at %s\n' "$CACHE_REL" >&2
fi

printf '%s\n' "$BODY"
exit 0
