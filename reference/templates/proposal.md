---
# Identity
id: <kebab-slug>                    # stable; matches the observation id where possible
created: <YYYY-MM-DD>
bonsai-version: 0.1.0

# Classification — see placement.md
class: constraint | fact | preference | procedure | reference | context-heavy | repeated-prompt
mechanism: hook | rule | claude-md | skill | subagent | permission
target: <path the artifact will be written to>
scope: committed | personal | user-global

# Evidence — see thresholds.md
confidence: 0.0-1.0
distinct-sessions: <n>
threshold-required: <n>
first-seen: <YYYY-MM-DD>
last-seen: <YYYY-MM-DD>

# Budget
resident-token-delta: <n>           # 0 for path-scoped rules, hooks, and subagents
pending-since-sessions: 0           # incremented by the surfacing script; drives etiquette back-off

# Lifecycle
status: pending | accepted | declined | archived
---

# <One-line statement of what this artifact does>

## Why this mechanism

One or two sentences. Name the class, name the mechanism, and name the alternative you rejected and
why. In express mode this section is skipped when the mapping is obvious.

## Evidence

Verbatim excerpts, one per line, each with its session id and date. No paraphrase.

- `abc123` 2026-07-18 — "no, use pnpm here"
- `def456` 2026-07-21 — "again — pnpm, npm lockfiles break the install"

## Proposed artifact

The complete file content, fenced, exactly as it will be written. Include frontmatter if the target
takes frontmatter (`paths:` for a scoped rule, the full schema for a subagent).

## Eval case

Copied to `.claude/bonsai/evals/<id>.md` on accept. A proposal without this is rejected by
`/bonsai:review`.

**Situation:** <what the user was doing>
**Without the artifact:** <what actually happened, from the evidence>
**With the artifact:** <the behavior this should produce>

## Blast radius

- Resident context: <delta and when it loads>
- Who it affects: <just me | everyone on the repo | everyone in this directory>
- Enforced or advisory: <hook/permission = enforced; prose = advisory, say so>
- Reversal: <the single command or file deletion that undoes this>
