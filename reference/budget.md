# The cost contract

bonsai asks to live in every session of your project. That's a privilege, and it comes with a bill:
resident context tokens, marginal tokens per session, and money for the observation passes.

This document states that bill in numbers, and `scripts/footprint.py` measures the real one. If bonsai
exceeds these budgets, that's a bug — `tests/` asserts them.

**The goal is net-negative.** bonsai must save more context than it spends. If it can't demonstrate
that, it shouldn't be installed.

## Budget 1 — resident context

Tokens bonsai adds to *every* request, forever. The only budget that compounds, and the one that causes
context rot, so it's capped hardest.

Measured by `scripts/footprint.py`, asserted by `tests/run.sh`:

All measured by `footprint.py` against bonsai's own dogfood install:

| Item | Tokens | Notes |
| :--- | ---: | :--- |
| `/bonsai:promote` description | 82 | The **only** model-invocable skill — it has to be, since the CLAUDE.md pointer tells Claude to call it |
| `CLAUDE.md` pointer stanza | 65 | 4 lines, the only prose bonsai adds |
| `SessionStart` notice | ~15 | Only when proposals are pending; one line |
| `/bonsai:init`, `:review`, `:prune`, `:pause` descriptions | **0** | `disable-model-invocation: true`, so invisible until you type them |
| **Total** | **162** | **Hard ceiling: 350** |

For scale: ~6% of a `CLAUDE.md` at the documented 200-line limit.

The 350 ceiling has deliberate headroom — it's the number a PR must stay under, not a target. Note that this
table previously *projected* 29 tokens for the pointer stanza; dogfooding measured 65 and the estimate was
corrected. Prefer measurement to projection here, always.

For scale: a CLAUDE.md at the documented 200-line limit is roughly 2,500 tokens. bonsai's entire
permanent footprint is about a tenth of that — and the artifacts it creates are subject to
[placement.md](./placement.md)'s Gate 4, which prefers zero-resident mechanisms.

Consequences we accept to hold this line:

- **Exactly one model-invocable skill.** `/bonsai:promote` has to be — the `CLAUDE.md` pointer tells Claude
  to call it. Everything else is `disable-model-invocation: true` and therefore free at rest. Any PR making
  a second skill model-invocable is spending ~50 tokens in every session of every install, forever, and
  needs to justify that.
- **Command surface is a budget too, even at zero tokens.** `/bonsai:prune` reports footprint rather than
  shipping a separate `/bonsai:status` — not because a status skill would cost tokens (it wouldn't), but
  because every entry in the user's `/` autocomplete is something they have to learn and choose between.
  Five commands is the ceiling.
- **No MCP server.** It would add tool definitions to every session for work that scripts do.
- **No output style.** They're never compacted, and they drop the default system prompt's instructions.
- **Reference docs are never resident.** `reference/*.md` is read on demand by the skill that needs it,
  which is the entire point of progressive disclosure.

## Budget 2 — marginal tokens per session

Tokens bonsai adds to a session you're actually working in.

| Path | Cost in your context |
| :--- | :--- |
| Observation (`SessionEnd`) | **0** — separate detached process, not your session |
| Surfacing (`SessionStart`) | ~15, and only when something is pending |
| Proposal drafting | **0** — runs in the detached process |
| `/bonsai:review` | Only when you invoke it |
| Idle session, nothing pending | **0** |

A session where you never invoke bonsai and have nothing pending costs the resident ~260 and nothing
else. That's the common case and it's the one that had to be cheap.

## Budget 3 — money

The detached passes are real API calls. Bounded by construction:

- `model: haiku`, `effort: low`, `maxTurns: 12` on the retrospective
- At most 1 run per repo per hour
- At most `daily_limit` runs per day (default 6)
- Skipped entirely for sessions under 8 turns, hot-path sessions, and mid-git-operation states — and
  the skip is decided in shell, before any model spawns, so a skipped session costs exactly nothing
- A second pass only when a threshold actually crossed, which is rare by design
- `retrospective: false` in plugin config makes bonsai fully manual

Input size is the transcript, so cost scales with session length. For current Haiku pricing, ask
`/claude-api` — this document deliberately states no dollar figures it would get wrong.

## Budget 4 — attention

The budget nobody accounts for and everybody feels. Enforced by
[etiquette.md](./etiquette.md), summarized:

- Zero mid-session interruptions. Session boundaries only.
- One line, once. Never repeated in a session.
- Silence when idle — no "nothing to report."
- Back off when ignored; auto-archive at 7 sessions. Never escalate.
- Suppressed entirely during rapid iteration.

## What bonsai must give back

Being cheap isn't enough; it has to pay for itself. The mechanisms by which it does:

| Saving | How |
| :--- | :--- |
| Down-leveled subagents | Moves context-heavy work out of your window and onto a cheaper model |
| Path-scoped rules | Guidance that would have been resident becomes conditional |
| Pruning | Removes artifacts that are costing resident tokens and doing nothing |
| CLAUDE.md refactors | Delegates to `/doctor`, then splits what remains by path |
| Fewer re-explanations | The point of the whole exercise |

`/bonsai:prune` reports both sides of this ledger. A single accepted subagent proposal typically saves
more per invocation than bonsai's entire resident footprint costs per session — that's the trade being
offered, and it should be stated plainly rather than assumed.

## Accountability

- `scripts/footprint.py` computes actual resident cost, artifacts created, and estimated savings.
- `/bonsai:prune` reports it in one line.
- `tests/test_budget.sh` fails if resident cost exceeds the 350-token ceiling.
- Token counts are estimates (~4 chars/token) and labeled as such. For exact accounting, `/context` is
  authoritative — and comparing `/context` before and after installing bonsai is the honest test.
