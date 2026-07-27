# Claims register

Every **landscape claim** bonsai makes publicly — "nobody else does X", "the only tool that Y" — with a
verification date, an expiry, and the specific evidence that would kill it.

`reference/` docs carry `Sources verified` stamps because a stale citation makes bonsai confidently wrong.
Claims about what *other* tools do rot faster, and until the 2026-07-26 sweep nothing re-verified them: one
went stale in under a month and was caught only because someone asked in conversation. This file closes that
gap (`docs/backlog.md` C-05).

**Enforced by `scripts/claims_check.py`**, wired into `tests/run.sh`:

- Each `Asserted:` entry is `` `path` — "exact phrase" ``. The script greps the file for that phrase, so
  rewording a claim in the README without updating this file **fails the suite**. Structural drift is a bug,
  not a scheduling problem.
- For a `retracted` claim the check **inverts**: the phrase must be *absent*. A retired claim that creeps
  back into the docs fails too.
- Past its `Re-check` cadence, a claim **warns** in the normal suite and fails under
  `claims_check.py --strict` — the quarterly sweep. The suite never goes red on a date with no code change.

**What the script cannot do:** notice a *new* claim nobody registered. That needs judgment, so it's a
`CONTRIBUTING.md` rule instead of a script pretending to cover it.

**Writing a claim:** state it so evidence can kill it. "We're the best at X" is unfalsifiable and belongs
nowhere. Prefer the narrowest true version — a claim that survives contact is worth more than a bold one
that a reader disproves in one search. When evidence narrows a claim, **soften the live entry and add a
retracted entry with the old wording**, so the register records what we stopped being able to defend.

---

## CLAIM-01 — Load evidence across all three artifact classes

- **Status:** softened
- **Claim:** Nothing else records load events for rules (`InstructionsLoaded`) and subagents
  (`SubagentStart`), only for skills. Other cleanup tooling judges an artifact by reading it, which yields
  an opinion rather than a fact.
- **Asserted:** `README.md` — "Nothing records rule loads or subagent spawns" · `docs/capabilities.md` — "Removal here argues from recorded loads"
- **Verified:** 2026-07-26
- **Re-check:** quarterly
- **Falsified by:** any tool that persists rule-load or subagent-spawn events across sessions and uses them
  to decide removal.
- **History:** narrowed 2026-07-26. The original claim — that nothing tracked artifact loads at all — was
  falsified; see CLAIM-06.
- **Watch:** `aneym/skill-stats` already does this for skills and slash commands via a `PostToolUse` hook
  into SQLite, and its roadmap includes an evidence-ranked, human-gated cleanup sweep. Adding
  `InstructionsLoaded` is a small step from where it is. `egorfedorov/claude-context-optimizer` accumulates
  cross-session usage patterns but over *file reads*, and detects `CLAUDE.md` problems by size.
  `alirezarezvani/ClaudeForge` registers `InstructionsLoaded` but discards it — the handler is a stateless
  line-count validator that persists nothing.

## CLAIM-02 — Usage evidence joined to provenance

- **Status:** softened
- **Claim:** Nothing else can settle an artifact's proposal record with its later usage — "did the rule I
  added six weeks ago ever load?" Additive tools and subtractive tools both exist; none shares the inventory.
- **Asserted:** `README.md` — "did the rule I added six weeks ago ever load?" · `docs/capabilities.md` — "joined to what proposed them"
- **Verified:** 2026-07-26
- **Re-check:** quarterly
- **Falsified by:** any tool whose removal decision can reference the provenance record of its own earlier
  addition.
- **History:** narrowed 2026-07-26 from "nothing shares provenance between them", which was too strong.
- **Watch:** `netresearch/retro-skill` keeps real provenance on promotion — tombstones, `origin_session_id`,
  a content hash as idempotency key — but links *source note → destination*, never *destination → later
  usage*. `aneym/skill-stats` holds an inventory plus activation records plus proposals, but never creates an
  artifact, so it's subtract-and-amend rather than both directions. The two halves exist separately; joining
  them is one integration away.

## CLAIM-03 — Eval capture as a promotion gate

- **Status:** active
- **Claim:** No other tool *refuses* to promote a pattern into configuration without a replayable case filed
  alongside it. Where evals appear elsewhere, they are advisory.
- **Asserted:** `reference/thresholds.md` — "Eval capture is mandatory" · `README.md` — "Evals as a *gate* rather than a suggestion"
- **Verified:** 2026-07-26
- **Re-check:** quarterly
- **Falsified by:** any tool that blocks promotion when no eval case is supplied.
- **Watch:** `netresearch/retro-skill` is the near-miss and explicitly declines to gate — it proposes an eval
  stub alongside a fix, and operates normally when evals are absent. It ships ~10 of its own eval fixtures,
  so it dogfoods harder than its README implies. `wshobson/agents` has a three-layer evaluation framework,
  but it measures quality rather than gating promotion. **This is the only claim the 2026-07-26 sweep left
  undamaged.**

## CLAIM-04 — A cost contract bonsai holds itself to

- **Status:** softened
- **Claim:** Tools that enforce a context budget enforce it on *your* files. bonsai publishes **its own**
  measured resident footprint and breaks its build on it. Not a category gap — a self-discipline claim.
- **Asserted:** `docs/capabilities.md` — "computes bonsai's own resident cost against a 350-token ceiling" · `docs/capabilities.md` — "It measures its own footprint against a token ceiling, and the test fails if it exceeds it"
- **Verified:** 2026-07-26
- **Re-check:** quarterly
- **Falsified by:** any comparable tool publishing its own resident cost as a measured number enforced in CI.
- **History:** narrowed 2026-07-26. The original — that nobody publishes a token number a build breaks on —
  was falsified; see CLAIM-07.
- **Watch:** state this as "we hold ourselves to the contract we sell", never as novelty. Budget enforcement
  in CI is a solved, shipped problem: `cuttlesoft/token-guard` fails builds on a token threshold across six
  harnesses, and `YawLabs/ctxlint` has already named and measured the always-loaded-vs-conditional
  distinction (`tier-tokens`) with `--strict` failing CI. Claiming otherwise reads as not having looked.

## CLAIM-05 — Routing to the harness's own token-saving mechanisms

- **Status:** softened
- **Claim:** No other tool routes an observed pattern to `paths:`-scoped rules, `.claude/settings.json`
  permissions, or down-leveled subagents — the Claude Code mechanisms that *save* resident tokens rather
  than spend them. The taxonomy is public; the automation is unoccupied.
- **Asserted:** `README.md` — "routing to the harness's own token-saving mechanisms" · `docs/capabilities.md` — "Seven-mechanism routing"
- **Verified:** 2026-07-26
- **Re-check:** quarterly
- **Falsified by:** any tool that proposes a `paths:`-scoped rule, a permission entry, or a cheaper-model
  subagent from observed usage.
- **History:** narrowed 2026-07-26 on two fronts — "mechanisms that save tokens rather than spend them" was
  false in general, and the placement taxonomy itself is published guidance.
- **Watch:** claim the *implementation*, never the insight: the seven-mechanism decision surface is
  documented in Anthropic's own "Steering Claude Code" post and widely written up. `netresearch/retro-skill`
  already routes away from instruction text toward checkpoints and harness artifacts (pre-commit hooks,
  linters, CI) — token-saving destinations, just git/CI ones rather than the harness's. `wshobson/agents`
  emits permission blocks and model-tier assignments, but statically curated, never observed-then-proposed.

## CLAIM-09 — No first-party staleness tracking or rule pruning

- **Status:** active
- **Claim:** Anthropic ships measurement (`/context`) and `CLAUDE.md` trimming (`/doctor`), but nothing
  first-party tracks config staleness across sessions or prunes rules on recorded usage. Across 273 official
  marketplace entries, `prune`, `stale`, and `hygiene` return zero matches.
- **Asserted:** `docs/roadmap.md` — "durable cross-session load tracking for rules or subagents" · `README.md` — "the parts Anthropic now does natively"
- **Verified:** 2026-07-26
- **Re-check:** monthly
- **Falsified by:** `/doctor` gaining durable cross-session usage data, or any first-party plugin that
  proposes configuration from observed sessions. Either one is C-03's archive trigger, not merely a narrowing.
- **History:** added 2026-07-26 as the mechanical half of C-03, which had been "ongoing" with nothing behind
  it. **Monthly**, not quarterly — this is the claim whose falsification ends the project, so it earns the
  tightest cadence in the register.
- **Watch:** the direction of travel is unfavourable. Four native capabilities landed in ~6 months, and
  skill-listing overflow already evicts descriptions "starting with the skills you invoke least" — bonsai's
  own thesis, in-house, if only in-memory and for skills. `claude-md-management` is additive and effectively
  unmaintained (4 commits, nothing substantive since 2026-01-20), but `claude-code-setup`'s
  `claude-automation-recommender` already recommends hooks, subagents, and skills from repo analysis, and
  `skill-creator` ships an eval harness. The pieces are assembling first-party.

---

## Retracted

Kept rather than deleted. A register that only records surviving claims teaches nothing about how fast this
landscape moves — and the `Asserted:` entries below are checked in reverse, so retired wording that creeps
back into the docs fails the suite.

## CLAIM-06 — Nobody tracks artifact loads at all

- **Status:** retracted
- **Claim:** *(retired)* bonsai is the only tool that records which config artifacts actually load; everything
  else judges by reading.
- **Asserted:** `README.md` — "The one nobody else does: removal on measured evidence" · `docs/capabilities.md` — "The differentiator: other cleanup tools judge an artifact by reading it"
- **Verified:** 2026-07-26
- **Re-check:** annual
- **Falsified by:** already falsified — `aneym/skill-stats` (created 2026-07-08) registers a `PostToolUse`
  hook on the `Skill` tool, persists each activation to SQLite, and reports dormant skills with zero
  activations in a window. Exactly the mechanism this claim said was unoccupied.
- **History:** retracted 2026-07-26, ~4 days after the falsifier shipped. Survives only in the narrower form
  at CLAIM-01. Nothing noticed on its own — the sweep this register exists to schedule is what caught it.

## CLAIM-07 — Nobody publishes a token number a build breaks on

- **Status:** retracted
- **Claim:** *(retired)* Every tool claims to be lightweight; none publishes a resident-token number enforced
  by CI.
- **Verified:** 2026-07-26
- **Re-check:** annual
- **Falsified by:** already falsified — `cuttlesoft/token-guard` is a GitHub Action that fails the check when
  instruction files exceed a configurable token threshold, and `YawLabs/ctxlint` ships a `tier-tokens` check
  distinguishing always-loaded from conditional content, with `--strict` exiting non-zero.
- **History:** retracted 2026-07-26. Never asserted in a tracked file — it lived in the private prior-art
  review and shaped roadmap framing, which is exactly how an unexamined claim survives. Survives narrowed at
  CLAIM-04.

## CLAIM-08 — The only tool that takes things out

- **Status:** retracted
- **Claim:** *(retired)* bonsai is the only one of these tools that removes configuration.
- **Asserted:** `docs/capabilities.md` — "bonsai is the only one of these tools that takes things"
- **Verified:** 2026-07-26
- **Re-check:** annual
- **Falsified by:** already falsified several times over — Context Cleanup audits for redundancy and
  contradiction, `YawLabs/ctxlint` has staleness and orphan checks, ClaudeForge prunes stale references, and
  `aneym/skill-stats` reports dormant skills. Removal tooling is a populated category.
- **History:** retracted 2026-07-26. Had been sitting in the social-copy list as claim 1, which is the worst
  place for a false comparative — it was the line most likely to be posted publicly.
