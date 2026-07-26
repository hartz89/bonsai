#!/bin/sh
# bonsai — repository survey and workflow-tier detection.
#
# Replaces the dozen-plus tool calls /bonsai:init would otherwise spend discovering what already
# exists. Emits one JSON object; the skill consumes one tool result and applies judgment to it.
# See reference/determinism.md.
#
# Usage: survey.sh [--project DIR]

set -u

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ "${1:-}" = "--project" ] && PROJECT="${2:-$PROJECT}"
cd "$PROJECT" 2>/dev/null || { printf '{"error":"cannot cd to project"}\n'; exit 0; }

j_str() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/ /g'; }
lines()  { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || printf '0'; }
exists() { [ -e "$1" ] && printf 'true' || printf 'false'; }

# Portable watchdog for network calls (gh). Stock macOS ships no timeout(1), so background the
# command and kill it ourselves after $1 seconds. A kill leaves a nonzero exit status, which every
# caller below already treats the same as "gh absent or errored" — a slow network degrades exactly
# like a missing `gh`, never an error.
GH_TIMEOUT=5
with_timeout() {
    secs="$1"; shift
    "$@" &
    pid=$!
    ( sleep "$secs" 2>/dev/null; kill -9 "$pid" 2>/dev/null ) &
    watcher=$!
    wait "$pid" 2>/dev/null; status=$?
    kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
    return "$status"
}

# --- instruction files -------------------------------------------------------
CLAUDE_MD_LINES=$(lines CLAUDE.md)
CLAUDE_MD_NESTED_LINES=$(lines .claude/CLAUDE.md)
AGENTS_MD=$(exists AGENTS.md)
LOCAL_MD=$(exists CLAUDE.local.md)
CURSORRULES=$(exists .cursorrules)
CURSOR_DIR=$(exists .cursor/rules)
COPILOT=$(exists .github/copilot-instructions.md)

# Does CLAUDE.md already bridge to AGENTS.md, and does it already have our stanza?
IMPORTS_AGENTS=false
HAS_POINTER=false
if [ -f CLAUDE.md ]; then
    grep -q '^[[:space:]]*@AGENTS\.md' CLAUDE.md 2>/dev/null && IMPORTS_AGENTS=true
    grep -qi '^##[[:space:]]*Harness maintenance' CLAUDE.md 2>/dev/null && HAS_POINTER=true
fi

# --- rules: how many, and how many are path-scoped ---------------------------
RULES_TOTAL=0
RULES_SCOPED=0
for f in $(find . -path ./node_modules -prune -o -path '*/.claude/rules/*.md' -print 2>/dev/null); do
    RULES_TOTAL=$((RULES_TOTAL + 1))
    awk 'NR==1 && $0!="---"{exit 1} NR>1 && /^---$/{exit 0} /^paths:/{found=1} END{exit !found}' \
        "$f" 2>/dev/null && RULES_SCOPED=$((RULES_SCOPED + 1))
done

count_dirs()  { find "$1" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
count_files() { find "$1" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' '; }
SKILLS=$(count_dirs .claude/skills)
AGENTS=$(count_files .claude/agents)

HOOKS=false
[ -f .claude/settings.json ] && grep -q '"hooks"' .claude/settings.json 2>/dev/null && HOOKS=true
MCP=$(exists .mcp.json)

# --- auto memory: the loop depends on it -------------------------------------
AUTO_MEMORY=unknown
for s in "$HOME/.claude/settings.json" .claude/settings.json .claude/settings.local.json; do
    [ -f "$s" ] || continue
    if grep -q '"autoMemoryEnabled"[[:space:]]*:[[:space:]]*false' "$s" 2>/dev/null; then
        AUTO_MEMORY=false
    elif grep -q '"autoMemoryEnabled"[[:space:]]*:[[:space:]]*true' "$s" 2>/dev/null; then
        AUTO_MEMORY=true
    fi
done
[ -n "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" ] && AUTO_MEMORY=false
NEW_INIT=false
[ -n "${CLAUDE_CODE_NEW_INIT:-}" ] && NEW_INIT=true

# --- tooling that already owns style ----------------------------------------
TOOLS=""
add_tool() { [ -e "$2" ] && TOOLS="$TOOLS\"$1\","; }
add_tool prettier .prettierrc; add_tool prettier .prettierrc.json; add_tool prettier prettier.config.js
add_tool eslint .eslintrc; add_tool eslint .eslintrc.json; add_tool eslint eslint.config.js
add_tool ruff ruff.toml; add_tool editorconfig .editorconfig
add_tool rustfmt rustfmt.toml; add_tool gofmt go.mod
TOOLS=$(printf '%s' "$TOOLS" | sed 's/,$//' | tr ',' '\n' | sort -u | paste -sd, - 2>/dev/null)

CI=false
for c in .github/workflows .gitlab-ci.yml Jenkinsfile .circleci azure-pipelines.yml; do
    [ -e "$c" ] && CI=true
done

MANIFESTS=$(find . -maxdepth 2 -name package.json -o -maxdepth 2 -name pyproject.toml \
    -o -maxdepth 2 -name Cargo.toml -o -maxdepth 2 -name go.mod 2>/dev/null \
    | grep -v node_modules | wc -l | tr -d ' ')

# --- workflow tier (reference/git-strategy.md) -------------------------------
IS_GIT=false; CONTRIBUTORS=0; MERGE_RATIO=0; CODEOWNERS=false
PROTECTED=unknown; CONVENTION=none; DEFAULT_BRANCH=""; DIRTY=false; MID_OP=false

if git rev-parse --git-dir >/dev/null 2>&1; then
    IS_GIT=true
    CONTRIBUTORS=$(git shortlog -sne --all 2>/dev/null | wc -l | tr -d ' ')
    DEFAULT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || printf 'main')
    [ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=true

    G=$(git rev-parse --git-dir 2>/dev/null)
    for m in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD BISECT_LOG REVERT_HEAD; do
        [ -e "$G/$m" ] && MID_OP=true
    done

    total=$(git rev-list --count HEAD 2>/dev/null || printf 0)
    merges=$(git rev-list --count --merges HEAD 2>/dev/null || printf 0)
    [ "$total" -gt 0 ] 2>/dev/null && MERGE_RATIO=$(awk -v m="$merges" -v t="$total" 'BEGIN{printf "%.2f", m/t}')

    { [ -f CODEOWNERS ] || [ -f .github/CODEOWNERS ] || [ -f docs/CODEOWNERS ]; } && CODEOWNERS=true

    conv=$(git log --no-merges --format='%s' -n 50 2>/dev/null \
        | grep -cE '^(feat|fix|chore|docs|refactor|test|perf|build|ci)(\([^)]+\))?!?:' 2>/dev/null || printf 0)
    [ "$conv" -ge 15 ] 2>/dev/null && CONVENTION=conventional

    if command -v gh >/dev/null 2>&1 && with_timeout "$GH_TIMEOUT" gh auth status >/dev/null 2>&1; then
        slug=$(with_timeout "$GH_TIMEOUT" gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || printf '')
        if [ -n "$slug" ]; then
            if with_timeout "$GH_TIMEOUT" gh api "repos/$slug/branches/$DEFAULT_BRANCH/protection" >/dev/null 2>&1; then
                PROTECTED=true
            else
                PROTECTED=false
            fi
        fi
    fi
fi

# First match wins.
if [ "$PROTECTED" = "true" ] || [ "$CODEOWNERS" = "true" ] || [ "$CONTRIBUTORS" -ge 15 ] 2>/dev/null; then
    TIER=enterprise
elif [ "$CONTRIBUTORS" -ge 2 ] 2>/dev/null || awk -v r="$MERGE_RATIO" 'BEGIN{exit !(r>0.3)}'; then
    TIER=team
else
    TIER=solo
fi

# --- mode: does this repo already show harness fluency? ---------------------
if [ "$RULES_SCOPED" -gt 0 ] || [ "$SKILLS" -gt 0 ] || [ "$AGENTS" -gt 0 ] || [ "$HOOKS" = "true" ]; then
    MODE=express
else
    MODE=guided
fi

BONSAI_INSTALLED=$(exists .claude/bonsai/config.json)
PROPOSALS=$(find .claude/bonsai/proposals -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

cat <<JSON
{
  "instructions": {
    "claude_md_lines": $CLAUDE_MD_LINES,
    "claude_md_nested_lines": $CLAUDE_MD_NESTED_LINES,
    "agents_md": $AGENTS_MD,
    "imports_agents_md": $IMPORTS_AGENTS,
    "has_bonsai_pointer": $HAS_POINTER,
    "claude_local_md": $LOCAL_MD,
    "cursorrules": $CURSORRULES,
    "cursor_rules_dir": $CURSOR_DIR,
    "copilot_instructions": $COPILOT
  },
  "extensions": {
    "rules_total": $RULES_TOTAL,
    "rules_path_scoped": $RULES_SCOPED,
    "skills": $SKILLS,
    "agents": $AGENTS,
    "hooks_configured": $HOOKS,
    "mcp_config": $MCP
  },
  "memory": { "auto_memory": "$AUTO_MEMORY", "new_init_env": $NEW_INIT },
  "repo": {
    "is_git": $IS_GIT,
    "contributors": $CONTRIBUTORS,
    "merge_ratio": $MERGE_RATIO,
    "codeowners": $CODEOWNERS,
    "branch_protection": "$PROTECTED",
    "commit_convention": "$CONVENTION",
    "default_branch": "$(j_str "$DEFAULT_BRANCH")",
    "dirty": $DIRTY,
    "mid_operation": $MID_OP,
    "package_manifests": $MANIFESTS,
    "ci": $CI,
    "style_tools": [$TOOLS]
  },
  "verdict": {
    "tier": "$TIER",
    "mode": "$MODE",
    "bonsai_installed": $BONSAI_INSTALLED,
    "pending_proposals": $PROPOSALS,
    "needs_init_handoff": $([ "$CLAUDE_MD_LINES" -eq 0 ] && [ "$CLAUDE_MD_NESTED_LINES" -eq 0 ] && printf true || printf false),
    "needs_doctor": $([ "$CLAUDE_MD_LINES" -gt 200 ] && printf true || printf false)
  }
}
JSON
exit 0
