---
name: init
description: Set up or upgrade bonsai in this repository. Surveys existing agent configuration, hands off to Claude Code's own /init and /doctor where they already do the job, detects the project's workflow tier, and proposes the harness artifacts the repo is actually missing. Safe to re-run.
disable-model-invocation: true
argument-hint: "[--express | --guided | --dry-run]"
allowed-tools: Read, Glob, Grep, Bash(git *), Bash(gh *), Bash(test *), Bash(wc *)
---

# bonsai:init

Survey, delegate, then propose. Never write an artifact in this skill without showing it first.

Read `${CLAUDE_PLUGIN_ROOT}/reference/placement.md` before proposing anything, and
`${CLAUDE_PLUGIN_ROOT}/reference/etiquette.md` before writing any user-facing output. Load
`git-strategy.md` and `thresholds.md` when you reach the phases that need them.

Re-running is expected and must be idempotent: if `.claude/bonsai/config.json` exists, this is an
upgrade — reconcile, report only what changed, and never duplicate a stanza or re-propose something in
`archive/`.

## Phase 1 — Survey (one call)

```
sh ${CLAUDE_PLUGIN_ROOT}/scripts/survey.sh --project .
```

One JSON object covering instruction files and their line counts, rules and how many are `paths:`-scoped,
skills/agents/hooks/MCP, auto-memory state, style tooling, git shape, and a `verdict` with the detected
tier, mode, and whether `/init` or `/doctor` hand-off is needed.

Do not re-derive any of this by hand — no `Read` to count lines, no `test -f`, no `git log` pipelines.
That's the determinism boundary (`${CLAUDE_PLUGIN_ROOT}/reference/determinism.md`), and re-deriving it
costs the user tokens for an answer the script already has.

Two fields deserve attention: `repo.style_tools` disqualifies any style guidance those tools already
enforce, and `memory.auto_memory` gates the whole observation loop.

## Phase 2 — Delegate before building

bonsai does not reimplement native tooling. Apply this table, then stop and let the hand-off happen
before continuing:

| Found | Do |
| :--- | :--- |
| No `CLAUDE.md` anywhere | Hand off to `/init`. Try invoking it; if unavailable, tell the user to type `/init`, then re-run this skill. Do **not** author a first CLAUDE.md yourself |
| `CLAUDE.md` over 200 lines, or full of derivable content | Invoke `/doctor` — it already proposes trims. Only afterward propose `paths:`-scoped splits for what remains |
| Unused skills / MCP servers / plugins, or slow hooks | Invoke `/doctor`. It detects all of these |
| Auto memory disabled | Tell the user to enable it via `/memory`. Note plainly that observation won't work without it |
| `AGENTS.md` but no `CLAUDE.md` | Propose a `CLAUDE.md` containing `@AGENTS.md`. Never duplicate the content |
| `.cursorrules` / copilot instructions but no `CLAUDE.md` | Mention that `/init` reads these and will fold them in |

`/doctor` is a bundled skill, so you can invoke it directly. `/init` is documented as a built-in
command and may not be invocable — attempt it, fall back to asking, and assert nothing either way.

## Phase 3 — Pick a mode

`--guided` / `--express` override; otherwise infer:

- **express** when the repo already shows harness fluency: `paths:`-scoped rules exist, or there are
  project skills/agents/hooks. Terse diffs, no teaching, no explanation of what a rule is.
- **guided** otherwise. Explain each proposal in one or two plain sentences: which mechanism, why that
  one, what it costs in resident context. Teaching is the deliverable here.

Either way, obey the etiquette budgets. Guided means *clearer*, not longer.

## Phase 4 — Harvest

Delegate to the `bonsai-scout` subagent. Pass it the Phase 1 survey so it doesn't repeat the work. It
returns candidate observations with evidence; it does not decide placement.

Skip the harvest entirely if the repo has no git history and no existing instruction files — there is
nothing to learn from yet, and the steady-state loop will pick things up.

## Phase 5 — Install bonsai itself

Ask once, showing exactly what will be written. The user invoked this skill, so installing bonsai is
consented — but the resident-context stanza must still be shown verbatim before it lands.

1. `.claude/bonsai/config.json` — detected tier, mode, thresholds, git strategy
2. `.gitignore` — the exclusions from `reference/git-strategy.md`, appended to an existing `.claude/`
   section rather than creating a second one
3. The five-line pointer in `CLAUDE.md`. Show it exactly as written in the README. If a
   `## Harness maintenance` section already exists, reconcile it — never append a duplicate
4. Hooks in `.claude/settings.json`, merging into existing hook arrays rather than replacing them

If the user declines the pointer, everything else still works — `/bonsai:promote` and `/bonsai:review`
are manual entrypoints. Say so and move on without arguing.

## Phase 6 — Propose

Run each candidate through `placement.md`'s gates and `thresholds.md`. Most candidates should die at
Gate 0; that is the expected outcome, not a failure.

Write survivors to `.claude/bonsai/proposals/<slug>.md` using
`${CLAUDE_PLUGIN_ROOT}/reference/templates/proposal.md`. Each needs provenance, a resident-token delta,
and an eval case. **Write nothing to a real artifact path in this phase.** `/bonsai:review` applies.

With `--dry-run`, print the proposals and write nothing at all.

## Phase 7 — Report

At most ~12 lines. In express mode, at most 6.

```
bonsai 0.1.0 · team tier · express mode

Delegated   /doctor → 3 CLAUDE.md trims pending your review
Installed   config, .gitignore (4 entries), SessionEnd + SessionStart hooks
Proposed    2 artifacts — /bonsai:review
Skipped     6 candidates (below threshold or already covered by eslint)
```

Then stop. Do not summarize what bonsai is, restate the roadmap, or suggest next steps beyond the one
command. If nothing needed doing, say that in two lines — finding a healthy repo is a success.
