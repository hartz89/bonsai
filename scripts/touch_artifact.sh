#!/bin/sh
# bonsai — record that a harness artifact was actually exercised.
#
# Three events feed this script, all of them side-effect-only for bonsai:
#
#   InstructionsLoaded          a CLAUDE.md or .claude/rules/*.md loaded  → payload `file_path`
#   SubagentStart               a subagent was spawned                    → payload `agent_type`
#   PostToolUse (matcher Skill) the model invoked a skill                 → payload `tool_input.skill`
#
# InstructionsLoaded and SubagentStart have no output control at all; the exit code of the first is
# ignored outright and the second can only show stderr. The PostToolUse entry is declared `async`, which
# the hooks reference defines as running in the background with `decision`, `permissionDecision`, and
# `continue` having no effect. So no path through this script can block, prompt, or add context — which
# is the only reason usage tracking is allowed to be a hook at all (reference/etiquette.md rule 1).
#
# Appends `<date> <relpath>` to .claude/bonsai/.state/exercised, at most once per artifact per day.
# prune_scan.py reads that log to compute last_exercised and loads-in-window. One flat, append-only log
# for all three events is deliberate: this fires repeatedly per session, so it must be fast, must not
# parse JSON properly, and must tolerate concurrent writers.
#
# Hot path. Pure POSIX sh, forever. No python3.

set -u

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
DIR="$ROOT/.claude/bonsai"
[ -f "$DIR/config.json" ] || exit 0
[ -e "$DIR/paused" ] && exit 0

payload=$(cat 2>/dev/null || true)

# Single field at a time, no JSON parser. Bail rather than guess if a field isn't there.
field() {
    printf '%s' "$payload" \
        | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

# Artifact names come from a model-authored payload, so they are untrusted. Anything that isn't a plain
# name is dropped rather than sanitised — that also drops plugin-scoped ids like `bonsai:prune`, which
# name artifacts bonsai doesn't own and shouldn't track.
plain_name() {
    case "$1" in
        ''|.|..|*[!A-Za-z0-9._-]*) return 1 ;;
    esac
    printf '%s' "$1"
}

rel=""

# --- CLAUDE.md and .claude/rules/*.md (InstructionsLoaded) -------------------------------------
path=$(field file_path)
if [ -n "$path" ]; then
    # Store repo-relative so the log survives clones and worktrees.
    case "$path" in
        "$ROOT"/*) rel=${path#"$ROOT"/} ;;
        /*)        exit 0 ;;   # outside the project: user-level rules aren't ours to track
        *)         rel=$path ;;
    esac
fi

# --- subagents (SubagentStart) -----------------------------------------------------------------
# `agent_type` is the agent's frontmatter `name`, which need not match its filename, so fall back to a
# scan when the obvious path misses. Also present as a common field inside any subagent, hence the
# event check: without it an InstructionsLoaded firing in a subagent would credit the wrong artifact.
if [ -z "$rel" ] && [ "$(field hook_event_name)" = "SubagentStart" ]; then
    name=$(plain_name "$(field agent_type)") || exit 0
    if [ -f "$ROOT/.claude/agents/$name.md" ]; then
        rel=".claude/agents/$name.md"
    else
        for f in "$ROOT"/.claude/agents/*.md; do
            [ -f "$f" ] || continue
            head -n 20 "$f" | grep -q "^name:[[:space:]]*$name[[:space:]]*$" || continue
            rel=".claude/agents/${f##*/}"
            break
        done
    fi
fi

# --- skills (PostToolUse on the Skill tool) ----------------------------------------------------
# Only the model-invoked path. Typing `/name` never reaches a tool call, and the event that does see it,
# UserPromptExpansion, sits on the user's prompt and can block — forbidden by etiquette rule 1. See
# docs/backlog.md P-12.
if [ -z "$rel" ] && [ "$(field tool_name)" = "Skill" ]; then
    name=$(plain_name "$(field skill)") || exit 0
    [ -f "$ROOT/.claude/skills/$name/SKILL.md" ] && rel=".claude/skills/$name/SKILL.md"
fi

[ -n "$rel" ] || exit 0

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
