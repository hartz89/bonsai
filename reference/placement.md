# Placement: which artifact, at which scope

*Sources verified 2026-07-26. A stale stamp is a bug — see `docs/backlog.md` C-01.*

How bonsai decides what to build from an observed pattern. Read top to bottom; the gates are ordered
so the cheapest rejection happens first.

- [Gate 0 — should this exist at all?](#gate-0--should-this-exist-at-all)
- [Gate 1 — classify the signal](#gate-1--classify-the-signal)
- [Gate 2 — pick the mechanism](#gate-2--pick-the-mechanism)
- [Gate 3 — pick the scope](#gate-3--pick-the-scope)
- [Gate 4 — pay the context budget](#gate-4--pay-the-context-budget)
- [Anti-patterns that block a proposal](#anti-patterns-that-block-a-proposal)
- [Worked examples](#worked-examples)

Every claim here is cited in [sources.md](./sources.md). When to propose is
[thresholds.md](./thresholds.md); how loudly is [etiquette.md](./etiquette.md).

## Gate 0 — should this exist at all?

Reject before classifying. Most observations should die here — this file exists as much to prevent
artifacts as to create them.

Reject if any holds:

- **Native tooling owns it.** A first CLAUDE.md is `/init`'s job. Trimming a bloated CLAUDE.md,
  finding unused skills/MCP servers/plugins, and flagging slow hooks are `/doctor`'s job. Reject the
  artifact — then classify the observation as a **capability** (Gate 1) and propose the hand-off. That
  path costs no resident context at all, so it is strictly better than a replacement, not a consolation.
- **The model already does it.** If unmodified Claude gets this right, an instruction is pure cost.
  Guidance that merely restates a tool default earns nothing.
- **It's derivable from the repo.** Directory layouts, dependency lists, and framework conventions are
  cheaper to read than to memorize — this is what `/doctor`'s trim pass removes. Keep pitfalls,
  rationale, and conventions that *differ* from defaults.
- **One occurrence.** See [thresholds.md](./thresholds.md). A single correction is a correction.
- **It contradicts an existing artifact.** Two rules that disagree means Claude picks one arbitrarily.
  Resolve the conflict first, then propose.
- **It encodes a person, not a project.** "Ryan prefers X" is not a team convention. Route to personal
  scope (Gate 3) or drop it.

## Gate 1 — classify the signal

Exactly one primary class. If two seem to fit, the earlier row wins.

| Class | Looks like | Test |
| :--- | :--- | :--- |
| **Capability** | work done by hand that a shipped command already does; a symptom `/doctor` or a first-party plugin already reports | Does a first-party capability already cover this, and is there evidence it isn't being used? |
| **Constraint** | "never touch X", "always run Y before Z" | Would a violation be a defect? Must it hold *every* time? |
| **Fact** | build command, where handlers live, which package manager | One line, always true, needed in most sessions |
| **Preference** | "fewer, longer tests", "avoid hasty abstractions" | Taste. A violation is arguable, not wrong |
| **Procedure** | release checklist, triage flow, migration steps | Multi-step, ordered, reusable |
| **Reference** | API surface, schema, design tokens | Lookup material, only sometimes needed |
| **Context-heavy task** | "summarize the PR threads", "audit deps" | Reads a lot, returns a little, needs no conversation history |
| **Repeated prompt** | same opening instruction typed each time | User-initiated, always the same shape |

## Gate 2 — pick the mechanism

| Class | Mechanism | Why not the alternative |
| :--- | :--- | :--- |
| Capability | **No artifact.** A one-line recommendation naming the invocation — or, for team scope, an `enabledPlugins` entry in `.claude/settings.json` | Authoring a rule or skill that restates a shipped command pays resident tokens forever and rots the moment upstream changes it. The native `/plugin` panel already reports context cost, last-updated date, and the full component inventory, so bonsai must not duplicate any of that — its only job here is *why you, and why now* |
| Constraint, mechanically checkable | **`PreToolUse` hook** (deny) or `permissions.deny` | Prose is a request, not a guarantee. *"Model judgments aren't reliable guardrails."* |
| Constraint, needs judgment | **Rule**, labeled as advisory | Don't pretend it's enforced. If it must hold, find a checkable proxy |
| Fact | **CLAUDE.md** | Skills load on demand; a fact needed every session belongs resident |
| Preference, path-correlated | **`.claude/rules/*.md` with `paths:`** | Unscoped costs every engineer context on every unrelated file |
| Preference, global | **CLAUDE.md**, one line | A whole rule file for one sentence is overhead |
| Procedure | **Skill** | *"A 30-line procedure belongs in skills."* Resident procedures are the top cause of CLAUDE.md bloat |
| Reference | **Skill** with `reference/` files | Progressive disclosure: pay only when consulted |
| Context-heavy task | **Subagent**, down-leveled | Keeps intermediate output out of the main window entirely |
| Repeated prompt | **Skill**, `disable-model-invocation: true` | Zero resident cost; the user is the trigger |
| Must happen every time, no thought | **Hook** | Deterministic trigger beats a reminder the model may skip |

Down-leveling a subagent — the cheap win people miss. When proposing one:

```yaml
model: haiku          # or sonnet if it must synthesize, not just extract
tools: Read, Grep, Glob, Bash   # narrowest set that works; omit Write/Edit for read-only work
maxTurns: 12          # bound the cost
effort: low           # extraction rarely needs more
```

Only propose this when the task is genuinely summarizable — it reads broadly and returns a short,
structured result. If the caller needs the intermediate detail, isolation is the wrong tool.

## Gate 3 — pick the scope

| Signal | Location |
| :--- | :--- |
| Team-wide, whole project | `./CLAUDE.md` or `.claude/rules/*.md` (committed) |
| Team-wide, one area | `.claude/rules/*.md` with `paths:`, or a nested `CLAUDE.md` |
| One person's taste | `./CLAUDE.local.md` (gitignored) or `~/.claude/rules/` |
| Applies across the user's repos | `~/.claude/` |
| Needed by a second repo | Package as a plugin |

Two hard rules:

1. **Never write personal preference into a committed file.** Mixing personal and project preferences
   is a named anti-pattern. When intent is ambiguous, ask; don't guess toward the committed file.
2. **Prefer `paths:`-scoped over unscoped.** If a rule correlates with a file pattern, scope it. An
   unscoped rule in a shared repo loads for every engineer on every file and dilutes adherence to
   everything else.

## Gate 4 — pay the context budget

Resident context is a shared budget with a real ceiling, and every token spends a finite attention
budget. Before proposing anything resident:

- **CLAUDE.md must stay under 200 lines.** If the proposal pushes past it, the proposal is not the
  artifact — the proposal is a *refactor*: move procedures to skills, scope rules by path, delegate
  trims to `/doctor`.
- **`@`-imports do not save context.** Imported files load in full at launch. Use them for
  organization, `paths:`-scoped rules for actual savings.
- **Skill descriptions are resident.** Combined `description` text is truncated at 1,536 characters in
  the listing. Put the key use case first; a vague description is worse than none because it misfires.
- **Prefer the mechanism with the lowest resident cost that still works.** Hooks cost zero unless they
  return output. Subagents cost nothing in the main window. Skills cost a description. Rules cost their
  body when unscoped. CLAUDE.md costs its body, always.
- **A `capability` proposal has a resident delta of exactly zero** — the only class that does, because
  bonsai writes nothing. Whenever it genuinely covers the observation it wins Gate 4 outright. The
  cheapest artifact is the one you don't create.

Record the estimated resident-token delta on every proposal. A proposal that grows resident context
without a stated reason is a bug.

## Anti-patterns that block a proposal

Each of these is named in the sources. Any one of them blocks the proposal outright.

1. Growing CLAUDE.md past 200 lines, or putting a procedure in it.
2. Writing an unscoped rule that could have been `paths:`-scoped.
3. Treating a prose instruction as a guardrail when the constraint is mechanically checkable.
4. Mixing personal preference into team-shared files.
5. Proposing a custom output style — it drops the default system prompt's instructions on scope,
   comments, security, and verification. Almost never the right answer; needs an explicit human call.
6. Two artifacts that contradict each other.
7. Duplicating `AGENTS.md` content into `CLAUDE.md` instead of importing it with `@AGENTS.md`.
8. Reference files nested more than one level below `SKILL.md`.
9. Recommending a **third-party** plugin or marketplace. Plugins and marketplaces "can execute arbitrary
   code on your machine with your user privileges", so `capability` proposals are first-party only.
   bonsai does not audit other people's repositories, and a recommendation reads as vetting.
10. Restating anything the native `/plugin` panel already shows — context cost, last-updated date, or the
    component inventory. Duplicating it invites drift against a UI that ships weekly.

## Worked examples

| Observation | Class | Artifact | Scope |
| :--- | :--- | :--- | :--- |
| Corrected "use pnpm not npm" 3× | Fact | CLAUDE.md, one line | Committed |
| "Write fewer, longer tests" said 4× while editing `*.test.ts` | Preference | Rule, `paths: ["**/*.test.ts"]` | Committed |
| Claude edited `.env` once; user was alarmed | Constraint, checkable | `PreToolUse` deny hook | Committed |
| "Avoid hasty abstractions" said repeatedly | Preference | Rule, labeled advisory | Committed |
| Release steps pasted 3× | Procedure | Skill, `disable-model-invocation: true` | Committed |
| PR comment triage done most days, burns context | Context-heavy | Subagent, `model: haiku`, read-only, `maxTurns: 12` | Committed |
| User prefers terse commit messages | Preference, personal | `CLAUDE.local.md` | **Not** committed |
| Existing `AGENTS.md`, no `CLAUDE.md` | — | `CLAUDE.md` with `@AGENTS.md` | Committed |
| No CLAUDE.md at all | — | Hand off to `/init` | — |
| CLAUDE.md is 400 lines | — | Invoke `/doctor`, then propose `paths:` splits | Committed |
| CLAUDE.md grew 60% in a month, `/doctor` never run in any observed session | Capability | Recommend `/doctor` — it proposes the trim itself | — |
| Token cost asked about by hand 3×, no context tooling in use | Capability | Recommend `/context`; `session-report` for per-session detail | — |
| Whole team hand-rolls the same triage, and a first-party plugin covers it | Capability | Propose an `enabledPlugins` entry so teammates are prompted on trust | Committed |
