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

# --- begin: pre-flight (R-01) ----------------------------------------------
printf '\npre-flight: dependency detection and the degradation ladder (docs/roadmap.md)\n'

pf_get() { printf '%s' "$1" | python3 -c "import json,sys;print(json.load(sys.stdin)$2)" 2>/dev/null; }

# A PATH containing everything preflight.sh itself needs — but no python interpreter.
pf_fakebin() {
    b=$(mktemp -d)
    for t in sh git gh uname date sed awk grep head cat mkdir mv rm dirname; do
        p=$(command -v "$t" 2>/dev/null) || continue
        case "$p" in /*) ln -s "$p" "$b/$t" 2>/dev/null ;; esac
    done
    printf '%s' "$b"
}

# Healthy environment: the suite already requires sh, git and python3 to run at all.
d=$(mktemp -d)
out=$(sh "$ROOT/scripts/preflight.sh" --project "$d")
printf '%s' "$out" | python3 -c "import json,sys;json.load(sys.stdin)" 2>/dev/null \
    && ok "emits well-formed JSON" || no "emits well-formed JSON" "$out"
is "healthy environment is full tier" "$(pf_get "$out" "['tier']")" "full"
is "full tier is installable" "$(pf_get "$out" "['installable']")" "True"
is "first probe is not cached" "$(pf_get "$out" "['cached']")" "False"
is "cache file written" "$(test -f "$d/.claude/bonsai/.state/preflight.json" && echo yes)" "yes"

out=$(sh "$ROOT/scripts/preflight.sh" --project "$d")
is "second call reports a cache hit" "$(pf_get "$out" "['cached']")" "True"

# Reuse means reuse: doctor the cache and the next call must return the doctored value untouched.
sed 's/"tier": "full"/"tier": "manual"/' "$d/.claude/bonsai/.state/preflight.json" > "$d/pf.tmp"
mv "$d/pf.tmp" "$d/.claude/bonsai/.state/preflight.json"
is "cached result is reused, not re-probed" \
    "$(pf_get "$(sh "$ROOT/scripts/preflight.sh" --project "$d")" "['tier']")" "manual"
is "--refresh re-probes" \
    "$(pf_get "$(sh "$ROOT/scripts/preflight.sh" --project "$d" --refresh)" "['tier']")" "full"
rm -rf "$d"

# No python3: reduced tier, with a named fix and no attempt to install anything.
b=$(pf_fakebin); d=$(mktemp -d)
out=$(PATH="$b" sh "$ROOT/scripts/preflight.sh" --project "$d")
is "no python3 degrades to reduced" "$(pf_get "$out" "['tier']")" "reduced"
is "reduced tier still installs" "$(pf_get "$out" "['installable']")" "True"
is "python is reported absent" "$(pf_get "$out" "['commands']['python']['present']")" "False"
fix=$(printf '%s' "$out" | python3 -c "
import json,sys
print(next((m['fix'] for m in json.load(sys.stdin)['missing'] if m['command']=='python3'), ''))")
[ -n "$fix" ] && ok "names a one-line fix for python3 ($fix)" || no "names a one-line fix for python3"
rm -rf "$d"

# No git either: manual tier.
rm -f "$b/git"
d=$(mktemp -d)
out=$(PATH="$b" sh "$ROOT/scripts/preflight.sh" --project "$d")
is "no git degrades to manual" "$(pf_get "$out" "['tier']")" "manual"
rm -rf "$d"

# gh is optional and must never change the tier on its own.
b2=$(pf_fakebin); rm -f "$b2/gh"; d=$(mktemp -d)
out=$(PATH="$b2:$(dirname "$(command -v python3)")" sh "$ROOT/scripts/preflight.sh" --project "$d")
is "missing gh stays full tier" "$(pf_get "$out" "['tier']")" "full"
optional=$(printf '%s' "$out" | python3 -c "
import json,sys
print(next((m['required'] for m in json.load(sys.stdin)['missing'] if m['command']=='gh'), 'absent'))")
is "gh is reported as optional" "$optional" "False"
rm -rf "$d" "$b2"

# No sh at all: unsupported, and the skill must refuse to install.
rm -f "$b/sh"
d=$(mktemp -d)
out=$(PATH="$b" /bin/sh "$ROOT/scripts/preflight.sh" --project "$d")
is "no sh is unsupported" "$(pf_get "$out" "['tier']")" "unsupported"
is "unsupported refuses install" "$(pf_get "$out" "['installable']")" "False"
rm -rf "$d" "$b"

# Cannot do its job: exit 0, empty stdout, complaint on stderr only.
out=$(sh "$ROOT/scripts/preflight.sh" --project /nonexistent/bonsai/project 2>/dev/null)
rc=$?
is "unusable project exits 0" "$rc" "0"
is "unusable project writes nothing to stdout" "$out" ""
err=$(sh "$ROOT/scripts/preflight.sh" --project /nonexistent/bonsai/project 2>&1 >/dev/null)
has "unusable project explains itself on stderr" "$err" "cannot cd"

# The init skill must gate on pre-flight (R-01; wiring the ladder into every skill is R-02).
has "init runs pre-flight first" "$(cat "$ROOT/skills/init/SKILL.md")" "preflight.sh"
# --- end: pre-flight (R-01) --------------------------------------------------
# --- begin: skill/subagent usage tracking + load evidence (P-09, P-11) ------
printf '\nstaleness: subagents, skills, and reported load evidence\n'
d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"
mkdir -p "$d/.claude/agents" "$d/.claude/skills/deploy" "$d/.claude/rules"
printf -- '---\nname: reviewer\n---\nx\n' > "$d/.claude/agents/reviewer.md"
printf -- '---\nname: renamed-agent\n---\nx\n' > "$d/.claude/agents/on-disk.md"
printf -- '---\nname: deploy\n---\nx\n' > "$d/.claude/skills/deploy/SKILL.md"
printf 'x\n' > "$d/.claude/rules/r.md"
t() { sh "$ROOT/scripts/touch_artifact.sh"; }
log="$d/.claude/bonsai/.state/exercised"
logged() { [ -f "$log" ] && cut -d' ' -f2- "$log" | sort -u | tr '\n' ',' || printf ''; }

printf '{"hook_event_name":"SubagentStart","agent_type":"reviewer","agent_id":"a1"}' | t
is "SubagentStart maps agent_type to the agent file" "$(logged)" ".claude/agents/reviewer.md,"
printf '{"hook_event_name":"SubagentStart","agent_type":"renamed-agent","agent_id":"a2"}' | t
has "resolves a frontmatter name that differs from the filename" "$(logged)" ".claude/agents/on-disk.md"
printf '{"hook_event_name":"SubagentStart","agent_type":"bonsai:scout"}' | t
lacks "plugin-scoped agents are not project artifacts" "$(logged)" "scout"
printf '{"hook_event_name":"SubagentStart","agent_type":"../../etc/passwd"}' | t
lacks "path traversal in agent_type is dropped" "$(logged)" "passwd"
printf '{"hook_event_name":"SubagentStart","agent_type":"Explore"}' | t
lacks "unknown agents are not invented" "$(logged)" "Explore"

printf '{"hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"deploy"}}' | t
has "PostToolUse on Skill maps to SKILL.md" "$(logged)" ".claude/skills/deploy/SKILL.md"
printf '{"hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"nope"}}' | t
lacks "unknown skills are not invented" "$(logged)" "nope"
printf '{"hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' | t
is "non-Skill tools log nothing" "$(logged | tr ',' '\n' | grep -c .)" "3"

# agent_type rides along on every event fired inside a subagent; file_path still wins.
printf '{"hook_event_name":"InstructionsLoaded","agent_type":"reviewer","file_path":"%s/.claude/rules/r.md"}' "$d" | t
has "a load inside a subagent credits the rule, not the agent" "$(logged)" ".claude/rules/r.md"

# --- the report line: counting in the script, prose in the skill (P-11) -----
cat > "$d/.claude/bonsai/inventory.json" <<EOF
{"artifacts":[
 {"id":"dead","target":".claude/rules/dead.md","mechanism":"rule","created":"2020-01-01T00:00:00Z"},
 {"id":"sk","target":".claude/skills/deploy/SKILL.md","mechanism":"skill","created":"2020-01-01T00:00:00Z"}
],"pruned_count":0}
EOF
printf 'x\n' > "$d/.claude/rules/dead.md"
q() { python3 "$ROOT/scripts/prune_scan.py" --project "$d" | python3 -c "import json,sys;$1"; }
is "window is reported alongside the count" \
  "$(q "print(json.load(sys.stdin)['load_tracking']['window_days'])")" "60"
is "a never-loaded artifact reports zero days in the window" \
  "$(q "print([f['days_loaded_in_window'] for f in json.load(sys.stdin)['findings'] if f['target']=='.claude/rules/dead.md'])")" \
  "[0]"
is "a loaded artifact carries evidence even when not stale" \
  "$(q "print([e['days_loaded_in_window'] for e in json.load(sys.stdin)['load_tracking']['evidence'] if e['target']=='.claude/skills/deploy/SKILL.md'])")" \
  "[1]"
is "skill coverage is flagged partial" \
  "$(q "print([e['coverage'] for e in json.load(sys.stdin)['load_tracking']['evidence'] if e['target'].startswith('.claude/skills/')])")" \
  "['partial']"
is "rule coverage is flagged full" \
  "$(q "print([e['coverage'] for e in json.load(sys.stdin)['load_tracking']['evidence'] if e['target']=='.claude/rules/dead.md'])")" \
  "['full']"
is "load tracking is active once anything is logged" \
  "$(q "print(json.load(sys.stdin)['load_tracking']['active'])")" "True"
rm -f "$log"
is "the inactive caveat appears when nothing is logged" \
  "$(q "print(json.load(sys.stdin)['load_tracking']['active'])")" "False"
has "the inactive caveat explains itself" \
  "$(q "print(json.load(sys.stdin)['load_tracking']['hint'])")" "weak evidence"
rm -rf "$d"; unset CLAUDE_PROJECT_DIR


# bonsai's own hooks must stay unable to reach the user (reference/etiquette.md rule 1).
hj=$(cat "$ROOT/hooks/hooks.json")
lacks "no Stop hook" "$hj" '"Stop"'
lacks "no UserPromptSubmit hook" "$hj" '"UserPromptSubmit"'
lacks "no UserPromptExpansion hook" "$hj" '"UserPromptExpansion"'
is "every PostToolUse hook is async and Skill-matched" \
  "$(printf '%s' "$hj" | python3 -c "
import json,sys
e=json.load(sys.stdin)['hooks'].get('PostToolUse',[])
print(all(m.get('matcher')=='Skill' and all(h.get('async') for h in m['hooks']) for m in e))")" "True"
# --- end: skill/subagent usage tracking + load evidence ---------------------

# ---------------------------------------------------------------------------
# BEGIN R-07/D-07 block
printf '\nsurvey: gh calls have a timeout (docs/backlog.md R-07/D-07)\n'
BIN=$(mktemp -d)
cat > "$BIN/gh" <<'EOF'
#!/bin/sh
sleep 30
EOF
chmod +x "$BIN/gh"
d=$(mktemp -d); git init -q "$d"
(cd "$d" && git config user.email a@b.c && git config user.name A && echo x > f \
  && git add f >/dev/null && git commit -qm "initial") >/dev/null 2>&1
start=$(date +%s)
out=$(PATH="$BIN:$PATH" sh "$ROOT/scripts/survey.sh" --project "$d")
elapsed=$(( $(date +%s) - start ))
is "a hanging gh does not stall the survey past its timeout" "$([ "$elapsed" -lt 25 ] && echo yes)" "yes"
prot=$(printf '%s' "$out" | python3 -c "import json,sys;print(json.load(sys.stdin)['repo']['branch_protection'])")
is "a timed-out gh degrades exactly like a missing gh" "$prot" "unknown"
rm -rf "$d" "$BIN"
# END R-07/D-07 block

# ---------------------------------------------------------------------------
# BEGIN D-02 block
printf '\npause: skill/mechanism consistency (docs/backlog.md D-02)\n'
SKILL="$ROOT/skills/pause/SKILL.md"
has "pause skill stays non-model-invocable (invariant 3)" "$(cat "$SKILL")" "disable-model-invocation: true"
has "pause skill documents the marker pending.sh checks" "$(cat "$SKILL")" '\.claude/bonsai/paused'
has "pending.sh checks the path the skill documents" "$(cat "$ROOT/scripts/pending.sh")" '\$DIR/paused'
has "retro.sh checks the path the skill documents" "$(cat "$ROOT/scripts/retro.sh")" '\$DIR/paused'

d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"
t="$d/transcript.jsonl"; i=0; while [ $i -lt 20 ]; do echo '{"role":"assistant"}' >> "$t"; i=$((i+1)); done
touch "$d/.claude/bonsai/paused"
out=$(printf '{"transcript_path":"%s","session_id":"s1"}' "$t" | BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
has "retro.sh actually honours the marker the skill creates" "$out" "paused"
rm -rf "$d"; unset CLAUDE_PROJECT_DIR
# END D-02 block
# === BEGIN flow-state guards (V-08) =========================================================
#
# Every "does not suppress" case is asserted by forcing a *later* guard to fire: with
# CLAUDE_PLUGIN_OPTION_DAILY_LIMIT=0, reaching "daily limit is 0" proves the flow-state guards let
# the session through, and does it without ever spawning a model.

printf '\netiquette: flow-state guards (reference/etiquette.md rule 5)\n'

# Fake transcript records, shaped like the real JSONL (see reference/sources.md, uncertain claims).
say()  { printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n' >> "$1"; }
fill() { n=0; while [ "$n" -lt "$2" ]; do say "$1"; n=$((n+1)); done; }
ask()  { printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":"go"},"timestamp":"%s"}\n' "$2" >> "$1"; }
call() { printf '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"%s","input":{"file_path":"%s"}}]}}\n' "$2" "$3" >> "$1"; }
result(){ printf '{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"tool_result","content":"%s","is_error":%s}]},"timestamp":"2026-07-26T10:00:00.000Z"}\n' "$2" "$3" >> "$1"; }

d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"
retro() { printf '{"transcript_path":"%s","session_id":"s1"}' "$1" | \
    CLAUDE_PLUGIN_OPTION_DAILY_LIMIT=0 BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1; }

# --- guard: median gap between human prompts under 20s ---
t="$d/rapid.jsonl"; i=0
while [ $i -lt 9 ]; do ask "$t" "2026-07-26T10:00:0$i.000Z"; say "$t"; i=$((i+1)); done
has "skips rapid back-and-forth" "$(retro "$t")" "rapid iteration"

t="$d/paced.jsonl"; i=0
while [ $i -lt 9 ]; do ask "$t" "2026-07-26T10:0$i:00.000Z"; say "$t"; i=$((i+1)); done
out=$(retro "$t")
lacks "a paced session is not rapid iteration" "$out" "rapid iteration"
has "...and reaches the later guards" "$out" "daily limit is 0"

# Fail open: same 1s cadence, timestamps stripped. Unmeasurable must never mean suppressed.
t="$d/notime.jsonl"; i=0
while [ $i -lt 9 ]; do printf '{"type":"user","message":{"role":"user","content":"go"}}\n' >> "$t"; say "$t"; i=$((i+1)); done
has "missing timestamps fail open" "$(retro "$t")" "daily limit is 0"

# Under the 8-gap floor the median is noise, so it must not suppress even though every gap is 1s.
t="$d/thin.jsonl"; i=0
while [ $i -lt 4 ]; do ask "$t" "2026-07-26T10:00:0$i.000Z"; say "$t"; i=$((i+1)); done
fill "$t" 6
has "too few gaps to take a median" "$(retro "$t")" "daily limit is 0"

# --- guard: >60% of tool calls are Edit/Write on the same 1-2 files ---
t="$d/loop.jsonl"; i=0
while [ $i -lt 5 ]; do call "$t" Edit "/p/a.py"; call "$t" Edit "/p/b.py"; i=$((i+1)); done
call "$t" Read "/p/c.py"; call "$t" Read "/p/d.py"
has "skips a tight edit loop" "$(retro "$t")" "tight edit loop"

# Same 12 tool calls, but the edits are spread and reading dominates.
t="$d/spread.jsonl"
call "$t" Edit "/p/a.py"; call "$t" Edit "/p/b.py"; call "$t" Edit "/p/c.py"
i=0; while [ $i -lt 9 ]; do call "$t" Read "/p/r$i.py"; i=$((i+1)); done
out=$(retro "$t")
lacks "spread-out edits are not a loop" "$out" "tight edit loop"
has "...and reach the later guards" "$out" "daily limit is 0"

# Under the 10-call floor the ratio is noise: 2 edits on one file is 100% and must not suppress.
t="$d/fewtools.jsonl"; call "$t" Edit "/p/a.py"; call "$t" Edit "/p/a.py"; fill "$t" 8
has "too few tool calls to judge a loop" "$(retro "$t")" "daily limit is 0"

# --- guard: the session ended on a failure ---
t="$d/broke.jsonl"; fill "$t" 10; result "$t" "boom" "true"
has "skips a session ending in an error" "$(retro "$t")" "ended on a failure"

t="$d/redtests.jsonl"; fill "$t" 10
result "$t" "3 tests failed" "false"
has "skips a session ending with failing tests" "$(retro "$t")" "ended on a failure"

t="$d/greentests.jsonl"; fill "$t" 10
result "$t" "53 passed, 0 failed" "false"
out=$(retro "$t")
lacks "a zero failure count is not a failure" "$out" "ended on a failure"
has "...and reaches the later guards" "$out" "daily limit is 0"

# Recency is the whole point: an error 25 records back was survived, not left unresolved.
t="$d/recovered.jsonl"; fill "$t" 5; result "$t" "boom" "true"; fill "$t" 25
has "an old, recovered error does not suppress" "$(retro "$t")" "daily limit is 0"

# Subagent sidechains must not be counted as the user's own frantic typing.
t="$d/side.jsonl"; i=0
while [ $i -lt 9 ]; do
    printf '{"type":"user","isSidechain":true,"message":{"role":"user","content":"go"},"timestamp":"2026-07-26T10:00:0%s.000Z"}\n' "$i" >> "$t"
    i=$((i+1))
done
fill "$t" 10
has "sidechain records are excluded from the gap census" "$(retro "$t")" "daily limit is 0"

rm -rf "$d"; unset CLAUDE_PROJECT_DIR

printf '\nretro: hook payload parsing (scripts/retro.sh field())\n'
d=$(sandbox); export CLAUDE_PROJECT_DIR="$d"
qdir="$d/we\"ird"; mkdir -p "$qdir"; t="$qdir/t.jsonl"; fill "$t" 10
esc=$(printf '%s' "$t" | sed 's/"/\\"/g')
out=$(printf '{"transcript_path":"%s","session_id":"s1"}' "$esc" | \
    CLAUDE_PLUGIN_OPTION_DAILY_LIMIT=0 BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
lacks "an escaped quote in transcript_path survives extraction" "$out" "no transcript"
has "...and the transcript is actually read" "$out" "daily limit is 0"

# A value that merely *contains* the key text must not be mistaken for the key.
t2="$d/real.jsonl"; fill "$t2" 10
out=$(printf '{"note":"see \\"transcript_path\\": \\"/nope\\"","transcript_path":"%s","session_id":"s1"}' "$t2" | \
    CLAUDE_PLUGIN_OPTION_DAILY_LIMIT=0 BONSAI_DEBUG=1 sh "$ROOT/scripts/retro.sh" 2>&1)
has "a decoy key inside a string value is ignored" "$out" "daily limit is 0"
rm -rf "$d"; unset CLAUDE_PROJECT_DIR

# === END flow-state guards ==================================================================

# ---------------------------------------------------------------------------
printf '\n%s passed, %s failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
