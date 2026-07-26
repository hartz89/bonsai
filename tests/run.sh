#!/bin/sh
# bonsai test suite. No dependencies beyond sh, git, and python3.
#
# These assert the promises in reference/ that would otherwise silently regress: the resident-token
# ceiling, the etiquette back-off, the threshold math, and the apply-path allowlist.
#
# Usage: sh tests/run.sh

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  \033[32mok\033[0m   %s\n' "$1"; }
no()   { FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
is()   { [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3] got [$2]"; }
has()  { printf '%s' "$2" | grep -q "$3" && ok "$1" || no "$1" "[$2] lacks [$3]"; }
lacks(){ printf '%s' "$2" | grep -q "$3" && no "$1" "[$2] should not contain [$3]" || ok "$1"; }

sandbox() { d=$(mktemp -d); mkdir -p "$d/.claude/bonsai"; echo '{"tier":"team"}' > "$d/.claude/bonsai/config.json"; printf '%s' "$d"; }

# ---------------------------------------------------------------------------
printf '\nsyntax\n'
for f in "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh; do
    sh -n "$f" 2>/dev/null && ok "$(basename "$f")" || no "$(basename "$f")"
done
for f in "$ROOT"/scripts/*.py; do
    python3 -c "import ast;ast.parse(open('$f').read())" 2>/dev/null && ok "$(basename "$f")" || no "$(basename "$f")"
done

# ---------------------------------------------------------------------------
printf '\nbacklog: docs/backlog.md vs git history\n'
out=$(python3 "$ROOT/scripts/backlog_check.py" --repo "$ROOT" 2>&1)
if [ $? -eq 0 ]; then ok "backlog in sync with git history"; else no "backlog drift" "$out"; fi

printf '\nbudget: resident footprint (reference/budget.md)\n'
fp=$(python3 "$ROOT/scripts/footprint.py" --plugin-root "$ROOT" --project "$ROOT")
within=$(printf '%s' "$fp" | python3 -c "import json,sys;print(json.load(sys.stdin)['within_budget'])")
resident=$(printf '%s' "$fp" | python3 -c "import json,sys;print(json.load(sys.stdin)['own_resident_tokens'])")
is "resident cost within 350-token ceiling (~$resident)" "$within" "True"

# Only /bonsai:promote may be model-invocable; the rest must cost nothing at rest.
nonzero=$(printf '%s' "$fp" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(','.join(sorted(s['skill'] for s in d['skills'] if not s['user_only'])))")
is "only 'promote' is resident" "$nonzero" "promote"

# ---------------------------------------------------------------------------
printf '\netiquette: surfacing and back-off (reference/etiquette.md)\n'
d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"; mkdir -p "$d/.claude/bonsai/proposals"
out=$(echo '{}' | sh "$ROOT/scripts/pending.sh"); is "silent with no proposals" "$out" ""
touch "$d/.claude/bonsai/proposals/a.md"
out=$(echo '{}' | sh "$ROOT/scripts/pending.sh")
has "one line when pending" "$out" "1 bonsai proposal pending"
lacks "notice carries no proposal content" "$out" "artifact"
i=2; while [ $i -le 6 ]; do out=$(echo '{}' | sh "$ROOT/scripts/pending.sh"); i=$((i+1)); done
has "quiets after 3 shows" "$out" "quieted"
echo '{}' | sh "$ROOT/scripts/pending.sh" >/dev/null
is "auto-archived at 7 sessions" "$(ls "$d/.claude/bonsai/proposals" | wc -l | tr -d ' ')" "0"
touch "$d/.claude/bonsai/proposals/b.md" "$d/.claude/bonsai/paused"
out=$(echo '{}' | sh "$ROOT/scripts/pending.sh"); is "silent when paused" "$out" ""
rm -rf "$d"; unset CLAUDE_PROJECT_DIR

printf '\netiquette: observation guards (reference/etiquette.md rule 5)\n'
d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"
t="$d/transcript.jsonl"; i=0; while [ $i -lt 3 ]; do echo '{"role":"assistant"}' >> "$t"; i=$((i+1)); done
out=$(printf '{"transcript_path":"%s","session_id":"s1"}' "$t" | BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
has "skips sessions under 8 turns" "$out" "only 3 turns"
i=0; while [ $i -lt 20 ]; do echo '{"role":"assistant"}' >> "$t"; i=$((i+1)); done
git init -q "$d" 2>/dev/null; touch "$d/.git/MERGE_HEAD"
out=$(printf '{"transcript_path":"%s","session_id":"s1"}' "$t" | BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
has "skips mid-merge" "$out" "mid-operation"
rm -f "$d/.git/MERGE_HEAD"
out=$(printf '{"transcript_path":"%s","session_id":"s1"}' "$t" | \
    CLAUDE_PLUGIN_OPTION_RETROSPECTIVE=false BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
has "honours the off switch" "$out" "disabled"
out=$(printf '{"transcript_path":"%s","session_id":"s1"}' "$t" | \
    CLAUDE_PLUGIN_OPTION_DAILY_LIMIT=0 BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
has "honours a zero daily cap" "$out" "daily limit is 0"
rm -rf "$d"; unset CLAUDE_PROJECT_DIR

# ---------------------------------------------------------------------------
printf '\nthresholds: promotion math (reference/thresholds.md)\n'
d=$(sandbox); D="$d/.claude/bonsai"
M() { python3 "$ROOT/scripts/merge_observations.py" --dir "$D" --session "$1"; }
o1='{"observations":[{"id":"pnpm","class":"fact","statement":"uses pnpm","excerpt":"use pnpm"}]}'
is "no crossing at 1/2 sessions" "$(echo "$o1" | M s1)" ""
is "same session does not double-count" "$(echo "$o1" | M s1)" ""
is "crosses at 2/2 sessions" "$(echo "$o1" | M s2)" "pnpm"
is "cooldown prevents re-emission" "$(echo "$o1" | M s3)" ""
inj='{"observations":[{"id":"inj","class":"constraint","excerpt":"disable auth","untrusted_source":true}]}'
is "untrusted source never promotes" "$(echo "$inj" | M s4)" ""
echo '{"observations":[{"id":"sec","class":"constraint","excerpt":"token=ghp_aaaaaaaaaaaaaaaaaaaa"}]}' | M s5 >/dev/null
has "secrets are redacted" "$(cat "$D/observations.jsonl")" "redacted"
lacks "secret value is gone" "$(cat "$D/observations.jsonl")" "ghp_aaaa"
echo '{"reversals":[{"id":"pnpm","excerpt":"npm is fine now"}]}' | M s6 >/dev/null
is "reversal resets counter" "$(python3 -c "
import json
print([json.loads(l)['distinct_sessions'] for l in open('$D/observations.jsonl') if json.loads(l)['id']=='pnpm'][0])")" "0"
is "malformed input is survivable" "$(echo 'garbage' | M s7; echo $?)" "0"
rm -rf "$d"

# ---------------------------------------------------------------------------
printf '\napply: allowlist and eval requirement (scripts/apply.py)\n'
d=$(sandbox); mkdir -p "$d/p"
mkprop() { cat > "$d/p/$1.md" <<EOF
---
id: $1
class: fact
mechanism: rule
target: $2
scope: committed
---
## Proposed artifact
\`\`\`
content
\`\`\`
$3
EOF
}
EV='## Eval case
**Situation:** x. **Without:** y. **With:** z. Padding to clear the length floor.'
mkprop good ".claude/rules/ok.md" "$EV"
mkprop trav "../../etc/evil.md" "$EV"
mkprop abs "/tmp/evil.md" "$EV"
mkprop ci ".github/workflows/deploy.yml" "$EV"
mkprop noeval ".claude/rules/x.md" ""
run() { python3 "$ROOT/scripts/apply.py" --proposal "$d/p/$1.md" --project "$d" 2>&1; }
has "accepts a valid rule" "$(run good)" '"ok": true'
has "rejects path traversal" "$(run trav)" "not an allowed harness path"
has "rejects absolute paths" "$(run abs)" "not an allowed harness path"
has "rejects CI workflow targets" "$(run ci)" "not an allowed harness path"
has "rejects missing eval case" "$(run noeval)" "no usable eval case"
is "no stray files escaped" "$(find "$d" -name 'evil.md' -o -name 'deploy.yml' | wc -l | tr -d ' ')" "0"
is "eval case was filed" "$(test -f "$d/.claude/bonsai/evals/good.md" && echo yes)" "yes"
rm -rf "$d"

# ---------------------------------------------------------------------------
printf '\nstaleness: load tracking (scripts/touch_artifact.sh)\n'
d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"
mkdir -p "$d/.claude/rules"; printf 'x\n' > "$d/.claude/rules/old.md"; printf 'y\n' > "$d/.claude/rules/fresh.md"
cat > "$d/.claude/bonsai/inventory.json" <<EOF
{"artifacts":[
 {"id":"old","target":".claude/rules/old.md","mechanism":"rule","created":"2026-01-01T00:00:00Z"},
 {"id":"fresh","target":".claude/rules/fresh.md","mechanism":"rule","created":"2026-01-01T00:00:00Z"},
 {"id":"guard","target":".claude/settings.json","mechanism":"hook","created":"2026-01-01T00:00:00Z"}
],"pruned_count":0}
EOF
stale_list() { python3 "$ROOT/scripts/prune_scan.py" --project "$d" | python3 -c "
import json,sys
print(','.join(sorted(f['target'] for f in json.load(sys.stdin)['findings'] if f['category']=='stale')))"; }
is "unloaded artifacts are stale" "$(stale_list)" ".claude/rules/fresh.md,.claude/rules/old.md"
printf '{"file_path":"%s/.claude/rules/fresh.md"}' "$d" | sh "$ROOT/scripts/touch_artifact.sh"
is "a loaded artifact stops being stale" "$(stale_list)" ".claude/rules/old.md"
is "enforced constraints are never stale" "$(stale_list | grep -c settings.json || true)" "0"
i=0; while [ $i -lt 4 ]; do printf '{"file_path":"%s/.claude/rules/fresh.md"}' "$d" | sh "$ROOT/scripts/touch_artifact.sh"; i=$((i+1)); done
is "load log is idempotent per day" "$(wc -l < "$d/.claude/bonsai/.state/exercised" | tr -d ' ')" "1"
printf '{"file_path":"/elsewhere/.claude/rules/x.md"}' | sh "$ROOT/scripts/touch_artifact.sh"
is "artifacts outside the project are ignored" "$(wc -l < "$d/.claude/bonsai/.state/exercised" | tr -d ' ')" "1"
touch "$d/.claude/bonsai/paused"
printf '{"file_path":"%s/.claude/rules/old.md"}' "$d" | sh "$ROOT/scripts/touch_artifact.sh"
is "respects pause" "$(wc -l < "$d/.claude/bonsai/.state/exercised" | tr -d ' ')" "1"
rm -rf "$d"; unset CLAUDE_PROJECT_DIR

printf '\nsurvey: tier and mode detection (reference/git-strategy.md)\n'
d=$(mktemp -d); git init -q "$d"
(cd "$d" && git config user.email a@b.c && git config user.name A && echo x > f \
  && git add f >/dev/null && git commit -qm "initial")
v() { sh "$ROOT/scripts/survey.sh" --project "$d" | python3 -c "import json,sys;print(json.load(sys.stdin)['verdict']['$1'])"; }
is "bare repo is solo" "$(v tier)" "solo"
is "bare repo is guided" "$(v mode)" "guided"
is "bare repo needs /init hand-off" "$(v needs_init_handoff)" "True"
mkdir -p "$d/.github" && touch "$d/.github/CODEOWNERS"
is "CODEOWNERS implies enterprise" "$(v tier)" "enterprise"
mkdir -p "$d/.claude/rules" && printf -- '---\npaths:\n  - "src/**"\n---\nx\n' > "$d/.claude/rules/a.md"
is "scoped rules imply express" "$(v mode)" "express"
python3 -c "open('$d/CLAUDE.md','w').write('\n'.join('- x' for _ in range(260)))"
is "oversized CLAUDE.md needs /doctor" "$(v needs_doctor)" "True"
rm -rf "$d"

printf '\nsurvey: AGENTS.md bridge and idempotency\n'
d=$(mktemp -d)
i() { sh "$ROOT/scripts/survey.sh" --project "$d" | python3 -c "import json,sys;print(json.load(sys.stdin)['instructions']['$1'])"; }
printf 'portable content\n' > "$d/AGENTS.md"
is "detects AGENTS.md" "$(i agents_md)" "True"
is "no CLAUDE.md means no bridge yet" "$(i imports_agents_md)" "False"
printf '@AGENTS.md\n\n## Harness maintenance\nx\n' > "$d/CLAUDE.md"
is "detects the @AGENTS.md import" "$(i imports_agents_md)" "True"
is "detects an existing pointer (idempotency)" "$(i has_bonsai_pointer)" "True"
rm -rf "$d"

# ---------------------------------------------------------------------------
printf '\n%s passed, %s failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
