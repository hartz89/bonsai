# Etiquette: polite but proactive

bonsai's failure mode is not "missed a pattern." It's "became annoying." An annoying harness tool gets
uninstalled, and then it improves nothing.

Design target: **visible but not chatty, proactive but never in the way, powerful but never
overpowering.** The rules below are hard limits, not aspirations. Each is testable, and the fixtures in
`tests/` assert them.

## The seven rules

### 1. Never interrupt work in progress

bonsai speaks at **session boundaries only**. Observation happens on `SessionEnd`, in a separate
headless process, after the user has stopped working. Surfacing happens on `SessionStart`, before the
user has started. There is no mid-session path to the user's attention.

Specifically forbidden in bonsai's own machinery:

- No `Stop` hook. It fires on every turn completion — the single worst place to be chatty.
- No `PostToolUse` hook that returns output. Hook output lands in context and reads as interruption.
- No `UserPromptSubmit` hook. Never touch the user's prompt.
- **No blocking hook, ever.** bonsai never returns exit code 2 and never sets `decision: block`. It has
  no business stopping anyone's work. (bonsai may *propose* a blocking hook for the user's project —
  that's the user's guardrail, approved by them, and not bonsai's own behavior.)

### 2. One line, once

The `SessionStart` notice is a single line: a count and how to act on it.

```
2 bonsai proposals pending — /bonsai:review
```

Never the proposal content. Never a second reminder in the same session. Never a justification of why
bonsai is useful. If the user ignores it, that is an answer.

### 3. Silence is the default state

With nothing high-confidence pending, bonsai emits **zero** output. Not "no proposals at this time" —
nothing. A tool that reports its own idleness is chatty.

The same applies to `/bonsai:init` on an already-healthy repo: report what it checked in two or three
lines and stop. Finding nothing to do is a success, and should read like one.

### 4. Back off when ignored — never escalate

The opposite of most notification systems. Ignored proposals get quieter:

| Sessions a proposal has been pending | Behavior |
| :--- | :--- |
| 1–3 | Counted in the one-line notice |
| 4–6 | Still counted, but no longer itemized in `/bonsai:review`'s default view |
| 7+ | Auto-archived to `.claude/bonsai/archive/`, silently, with a note in the inventory |

Archiving is not deletion, and a re-observed pattern can resurface — but at a raised threshold, since
the user has now implicitly declined it once. bonsai never re-proposes the same artifact at the same
confidence twice.

### 5. Suppress during rapid iteration

Someone shipping fast does not want a librarian. The retrospective skips entirely when the session
looks like a hot path:

- Fewer than 8 assistant turns (nothing to learn from a quick question)
- Median turn gap under ~20s across the session (rapid back-and-forth)
- More than 60% of tool calls are `Edit`/`Write` on the same 1–2 files (tight debug loop)
- The session ended with failing tests or an unresolved error (the user is mid-problem)
- A `.git/MERGE_HEAD`, `rebase-merge/`, or `BISECT_LOG` exists (mid-operation)

Suppression means *skip*, not *defer* — do not silently queue a backlog that lands as a pile later.
Patterns worth catching will recur; that's the entire premise.

### 6. Never make the user wait

The retrospective is a detached process spawned at `SessionEnd` and is not awaited. If it is slow,
crashes, or the model is unavailable, the user never learns and never cares. `SessionStart`'s surfacing
script does no model call at all — it counts files, and it must complete in well under a second or
skip itself.

Hard rule: no bonsai code path blocks the user on a model call.

### 7. Opting out must be trivial and obvious

- `/bonsai:pause` stops all observation and surfacing for the current repo, in one step.
- Every notice is traceable to a documented off-switch; the README's second section is how to turn it
  off, not how to configure it.
- `/plugin uninstall bonsai` leaves the repo working. Generated artifacts are plain files the user
  owns and keeps; only bonsai's own state directory is bonsai's to clean up.

## Cost etiquette

Annoyance is also measured in dollars.

- Retrospective defaults: `model: haiku`, `maxTurns` bounded, `effort: low`.
- At most one retrospective per repo per hour, and at most a configured number per day (default 6).
- Skipped sessions cost nothing — the guards in rule 5 are checked in shell before any model spawns.
- The daily cap and the enable flag are surfaced in `plugin.json` `userConfig`, not buried.

## What "proactive" still means

Politeness is not passivity. bonsai should:

- Do the install-time harvest thoroughly and propose real artifacts on day one, rather than waiting
  weeks to earn its keep.
- Say plainly when something is wrong — a 400-line CLAUDE.md, contradictory rules, a rule that should
  be a hook — once, with the fix attached.
- Prefer one substantive, well-evidenced proposal over five speculative ones. Precision buys the
  standing to interrupt at all.
