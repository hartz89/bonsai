# Etiquette: polite but proactive

*Sources verified 2026-07-26. A stale stamp is a bug — see `docs/backlog.md` C-01.*

bonsai's failure mode is not "missed a pattern." It's "became annoying." An annoying harness tool gets
uninstalled, and then it improves nothing.

Design target: **visible but not chatty, proactive but never in the way, powerful but never
overpowering.** The rules below are hard limits, not aspirations. Most are asserted in `tests/run.sh`; the
ones that aren't are marked below.

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
- No `UserPromptExpansion` hook. It is `UserPromptSubmit`'s sibling: same prompt path, and it can block
  the expansion. This costs bonsai the only signal that sees a `/skill` typed by hand, and that price is
  paid rather than negotiated — see `reference/determinism.md` § Usage tracking coverage.

The mid-session exception, and it is the only one: **silent usage logging**. `InstructionsLoaded`,
`SubagentStart`, and a `Skill`-matched `PostToolUse` each run `touch_artifact.sh`, which appends one line
to a file and exits. The first two have no output control the docs would honour; the third is declared
`async`, which drops `decision`, `permissionDecision`, and `continue`. Nothing reaches context, nothing
reaches the user, and nothing waits on a model. A signal that cannot be observed is not an interruption —
but the bar for adding another one is exactly this: prove the event has no path to the user's attention.

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

**Capability proposals get a harder cap: once per capability per 90 days, accepted or declined.** Every
other class ends in an artifact whose own existence stops it being proposed again. A recommendation to run
`/doctor` leaves nothing behind, so without a clock it would recur forever — and a suggestion repeated
after it was declined is the single fastest way to become the notification people mute. Enforced in
`merge_observations.py` (`CAPABILITY_COOLDOWN_DAYS`), not requested of a model.

### 5. Suppress during rapid iteration

Someone shipping fast does not want a librarian. The retrospective skips entirely when the session
looks like a hot path:

- Fewer than 8 assistant turns — nothing to learn from a quick question *(implemented, asserted)*
- A `.git/MERGE_HEAD`, `rebase-merge/`, `BISECT_LOG` etc. exists — mid-operation *(implemented, asserted)*
- Median turn gap under ~20s across the session — rapid back-and-forth *(implemented, asserted)*
- Over 60% of tool calls are `Edit`/`Write` on the same 1–2 files — tight debug loop *(implemented, asserted)*
- The session ended with failing tests or an unresolved error *(implemented, asserted)*

Suppression means *skip*, not *defer* — do not silently queue a backlog that lands as a pile later.
Patterns worth catching will recur; that's the entire premise.

The last three are heuristics over the transcript JSONL, computed in one `awk` pass in
`scripts/retro.sh` before any model spawns. Stating them precisely, because a guard that suppresses
for reasons nobody can reconstruct is worse than no guard:

| Guard | What is actually measured | Fires when |
| :--- | :--- | :--- |
| Rapid back-and-forth | Seconds between consecutive **human prompts** — not between assistant records, since one turn emits a record per tool call and would score every tool-heavy session as frantic. Tool results, `isMeta` records and subagent sidechains are excluded | ≥8 measurable gaps **and** strictly more than half are under 20s (equivalent to a median under 20s, without the sort) |
| Tight debug loop | Every `tool_use` in the session, and the `file_path` of each `Edit`/`MultiEdit`/`Write`/`NotebookEdit`; the two most-edited paths are summed | ≥10 tool calls **and** the top two files account for >60% of *all* tool calls — reading and running things around an edit is normal work, hammering the same two files is not |
| Ended on a failure | Only the last 20 transcript records, scanned for `is_error: true`, a `<tool_use_error>`, a non-zero failure count (`3 tests failed`), an uppercase `FAILED`, or a Python traceback | Any of those appear in that tail |

Two properties are load-bearing. **Every guard fails open**: an unparseable transcript, absent
timestamps, or a sample below the minimum runs the retrospective rather than suppressing it, because
a missed retrospective is invisible and a wrongly suppressed one is a silent loss. And the
failure guard deliberately does not try to decide whether an error was later resolved — it asks the
cheaper, more honest question "was the last thing that happened a failure", and `0 failed` does not
match.

### 6. Never make the user wait

The retrospective is a detached process spawned at `SessionEnd` and is not awaited. If it is slow,
crashes, or the model is unavailable, the user never learns and never cares. `SessionStart`'s surfacing
script does no model call at all — it counts files, and it must complete in well under a second or
skip itself.

Hard rule: no bonsai code path blocks the user on a model call.

### 7. Opting out must be trivial and obvious

- `/bonsai:pause` stops all observation and surfacing for the current repo, in one step.
- Every notice is traceable to a documented off-switch, and the README documents turning bonsai off before
  it documents configuring it.
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
