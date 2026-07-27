# Backlog

Itemized work. Reasoning and sequencing live in [roadmap.md](./roadmap.md); capability inventory in
[capabilities.md](./capabilities.md).

Size: **S** hours · **M** a day or two · **L** a week+ · **XL** needs its own design pass.
Phase 0 items block everything else.

Re-prioritized 2026-07-26 — see [roadmap.md](./roadmap.md#phase-2--eval-replay). Measurement (load tracking,
eval replay) moved up; portability moved down, from headline claim to table stakes.

---

---

## Phase 0 — Validate

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| V-01 | Install on 3+ real repos, incl. one multi-contributor, run 2+ weeks | L | The actual deliverable of this phase |
| V-02 | Verify `SessionEnd` fires reliably across exit paths | S | Terminal kill, `/clear`, crash, `exit`. If it misses, the loop silently never runs |
| V-03 | Verify the retrospective returns usable observations from real transcripts | M | Highest-risk unknown. Haiku may be too small |
| V-04 | Verify `/doctor` invocation actually works from inside `/bonsai:init` | S | Documented as a bundled skill; unproven in practice |
| V-05 | Verify `/init` hand-off, both invocable and fallback paths | S | Docs and local skill list disagree; needs empirical answer |
| V-06 | Confirm resident cost with `/context` before/after install | S | Validates the README's headline number |
| V-07 | Log every proposal + verdict + reasoning by hand | M | Manual precursor to P-01. The Phase 1 dataset |
| V-08 | Confirm flow-state guards fire at a sane rate, and implement the three unbuilt ones | M | Target 40–70% skipped. 2026-07-26: the turn-gap, edit-loop and failing-test guards are now implemented in `retro.sh` and asserted in `tests/run.sh`; heuristics are spelled out in `etiquette.md` rule 5. Open half is live rate-confirmation — offline transcripts can't tell us the real skip rate |
| V-09 | Dogfood on bonsai itself and record what it proposes | S | Also the README's opening demo |

---

## Phase 1 — Precision

The premise of this phase: auditing a rule by reading it yields an opinion; measuring whether it was ever
loaded yields a fact. P-09 built that measurement (landed 2026-07-26). **P-01 now leads** — nothing can be
tuned until outcomes are recorded.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| ~~P-09~~ | ~~Extend load tracking to skills and subagents~~ | — | **Done.** `agent_type` verified: `SubagentStart` carries it, it has no output control, and it holds the frontmatter `name`, not the filename. Subagents are now fully tracked. Skills go through a `Skill`-matched `PostToolUse`, which sees model invocations only — no transcript parsing needed, and no `SkillStart` event exists. The hand-typed `/name` path is out of reach on principle, not on effort → **P-12** |
| P-10 | Add a verification signal to the promotion gate | M | Frequency is a weak bar on its own — three repetitions of a bad habit clears it. Add a quality dimension: did a verification pass (green build, passing test), is there a named failure the pattern avoids, was a dead end ruled out? Touches `thresholds.md`, `BASE_THRESHOLDS`, and `merge_observations.py` |
| ~~P-11~~ | ~~Surface load-tracking evidence in the prune report~~ | — | **Done.** `prune_scan.py` emits `days_loaded_in_window`, `window_days`, and `coverage` per finding plus a `load_tracking.evidence` array; `skills/prune/SKILL.md` requires every artifact line to state the count, and to disclaim it when tracking is inactive or coverage is partial. The unit is days-with-a-load, not invocations — the log records at most one per day |
| P-13 | Implement the `capability` proposal class | L | **The cheapest validation path in the roadmap** — needs no eval format, no promotion machinery, and authors no artifact, so the accept-rate stop condition becomes measurable in days. Spec landed 2026-07-26 (`placement.md` Gate 1/2, `thresholds.md`, `CAPABILITY_COOLDOWN_DAYS`, `etiquette.md` rule 4). Remaining: detection signals per capability (never-run `/doctor` against `CLAUDE.md` growth; repeated by-hand work a first-party plugin covers), the `/bonsai:init` wizard steps explaining each in plain English with a benefit and an example, and rendering a proposal that hands over an invocation or an `enabledPlugins` entry. **First-party only**, and bonsai never installs — it proposes. Detection is script work; the plain-English case is the model's |
| P-14 | Team-scoped capability policy | M | Follows P-13. A platform team encodes "this org expects `session-report` and a monthly `/doctor`" once, in `.claude/bonsai/config.json`, and every clone inherits it; `enabledPlugins` in project settings already makes the harness prompt teammates on folder trust. Plausibly the real enterprise unlock, and deliberately **not** in P-13's first pass — personal nudges have to earn their keep before anything is pushed to a whole team |
| P-12 | Track hand-typed `/skill` invocations | M | The gap P-09 left. `PostToolUse` on the `Skill` tool sees model invocations; typing `/name` bypasses the tool entirely and only `UserPromptExpansion` observes it — an event on the user's prompt that can block the expansion, which `etiquette.md` rule 1 forbids. Needs either an upstream side-effect-only event, or a transcript-derived signal computed off the hot path (`retro.sh` already reads the transcript at `SessionEnd`). Until then `prune_scan.py` reports skill staleness as `coverage: "partial"`. **Lead (2026-07-26, C-05 sweep):** `aneym/skill-stats` claims to split activations `byTrigger` into agent vs human and to see `~/.claude/commands` — worth reading how it observes the hand-typed path, and whether it does so without an event that can block a prompt |
| P-01 | Record accept/reject/edit outcomes per proposal in the inventory | M | Nothing can be tuned without this |
| P-02 | Capture reject reasons as structured categories | S | "Wrong mechanism" vs "not a real pattern" imply opposite fixes |
| P-03 | Feed outcomes back into confidence scoring | M | Patterns resembling past rejections should score lower |
| P-04 | Re-tune `thresholds.md` from real data | M | Current numbers are reasoned guesses. Replace them and say so |
| ~~P-05~~ | ~~Add `last_exercised` tracking~~ | — | **Done.** `InstructionsLoaded` hook → append-only load log → `prune_scan.py`. Covers CLAUDE.md and rules |
| P-06 | Improve `bonsai-retrospective` prompt from observed failures | M | Depends on V-03 |
| P-07 | Add a proposal-quality self-check before writing | S | Cheap precision win: reject weak drafts before the human sees them |
| P-08 | Detect and merge near-duplicate observations | M | Model may emit different ids for one pattern; deterministic merge can't catch semantic dupes |

---

## Runtime robustness — pre-flight and degradation

Lands during Phase 0: a missing dependency would silently invalidate validation itself.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| ~~R-01~~ | `scripts/preflight.sh` — detect `sh`, `git`, `python3`/`python`, `gh`; cache the result | M | **Done.** Pure `sh`, cached at `.claude/bonsai/.state/preflight.json`, `--refresh` to re-probe. `/bonsai:init` gates on it and refuses to install at `unsupported`. Consuming the tier in the *other* skills is R-02 |
| R-02 | Wire the degradation ladder into every skill | M | Full / reduced / manual / unsupported, per `roadmap.md` |
| R-03 | Model-side fallbacks for the Python scripts | L | `apply.py`, `prune_scan.py`, `footprint.py` become in-skill work when Python is absent — slower, costs tokens, still functional |
| R-04 | `merge_observations.py` fallback or graceful off | M | Hardest case: it's on the detached path and owns the counters. Likely "observation off, say why" rather than a shell reimplementation |
| R-05 | Windows support: PowerShell hook variants | L | Hooks accept `shell: "powershell"`. Today bonsai is macOS/Linux-only and doesn't say so |
| ~~R-06~~ | ~~Assert the pure-`sh` invariant in tests~~ | — | **Done.** Structural, and says so: shebang, bashisms, no python in `pending.sh`, and in `retro.sh` python only inside the detached `work()` — with the guards asserted to precede it |
| ~~R-07~~ | ~~Add timeouts to `gh` calls in `survey.sh`~~ | — | **Done.** Portable watchdog (`with_timeout`, `GH_TIMEOUT=5`) in `survey.sh` — no reliance on `timeout(1)`, absent on stock macOS. Same as D-07 |

---

## Phase 2 — Eval replay

Moved ahead of harness-agnosticism 2026-07-26. Replay is what turns pruning from a heuristic into evidence,
and it pairs with P-09: load tracking proves an artifact was never consulted, replay proves it was consulted
and changed nothing. Neither is convincing alone.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| E-01 | On-demand single-case replay, human judges the diff | L | Cheapest useful version. Build this first and learn |
| E-02 | Stabilize the eval case capture format | M | Prerequisite for automation; don't automate against a moving target |
| E-03 | Automated judge pass over replay output | XL | LLM-as-judge on a noisy signal. Hard, easy to fool yourself |
| E-04 | Replay-driven pruning: flag artifacts that change nothing | L | Turns pruning from heuristic into evidence. The real prize — pairs with P-09 |
| E-05 | Cost controls for replay | S | Replay is expensive; needs opt-in and a hard cap |

---

## Phase 3 — Harness-agnosticism (vendor lock-in)

Demoted from Phase 2 on 2026-07-26. Portability is table stakes, not a differentiator — cross-tool artifact
formats are well-trodden ground. It stays an architectural commitment, because the canonical-body/wrapper seam
constrains every design decision from now on, but it's no longer something to lead with.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| X-04 | Survey existing cross-tool artifact layouts before designing the seam | S | **Do this before W-01.** This is solved ground; a design pass that ignores existing conventions invents an incompatible one |
| X-00 | Verified capability matrix: Claude Code, Cursor, Codex/`AGENTS.md`, Copilot | M | Per mechanism class, cited. Gates everything else. Cursor *has* glob scoping, so `adapters/agents-md.md` is currently wrong about it being Claude-only |
| X-01a | Verify whether `.claude/rules/*.md` supports `@` imports | S | **Do this first.** Determines whether wrappers can reference or must inline |
| W-01 | Define the canonical-body layout (`.harness/`) and wrapper contract | L | The core lock-in mechanism. One source of truth, thin per-harness wrappers |
| W-02 | Generate Claude Code wrappers from canonical bodies | M | Depends on X-01a |
| W-03 | Generate Cursor wrappers (`globs:` frontmatter) | M | The real test of the seam — Cursor has its own scoped-rule format |
| W-04 | `scripts/lint_parity.py` — fail when a wrapper drifts from its canonical body | M | What makes inlining safe. Joins `tests/run.sh` |
| W-05 | Propose the parity check as an artifact in consumer repos | M | Pre-commit or CI. A generated guardrail protecting generated config |
| X-02 | Test on a repo genuinely using two tools | M | Validates the seam end to end |
| X-03 | Document degradation honestly in the README | S | Enforcement and down-leveling may be Claude-only. Say so rather than let a Cursor user discover it |

---

## Phase 4 — Multi-developer

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| T-01 | Design the shared/private split for team observations | XL | Hashed pattern identities committed, excerpts local. Needs a real design pass |
| T-02 | Cross-developer dedup so N teammates don't file N copies | L | Follows directly from T-01 |
| T-03 | Revisit whether team thresholds should *drop*, not rise | M | Corroboration across people beats repetition by one. Current tier logic may be backwards |
| T-04 | Team-visible proposal mode | M | Proposals are gitignored, so there's nothing to review on a PR |
| T-05 | Respect `CODEOWNERS` when routing proposals | M | Path owner should review guidance for their path |
| T-06 | Test the enterprise worktree path for real | M | Written to spec, never executed |

---

## Phase 5 — Ecosystem

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| Z-01 | Submit to community plugin lists | S | Only after Phase 1 |
| ~~Z-02~~ | ~~Write the launch post~~ | — | **Done.** Drafts for X, Reddit, Show HN, LinkedIn, and a blog outline in `.local/social/` (gitignored) |
| Z-05 | Publish the long-form posts | S | Gated on Phase 0. Show HN and LinkedIn drive installs, and adoption before validation is harmful. Short-form build-in-public posts are safe now |
| Z-03 | Decide release cadence and whether to keep the pinned `version` | S | Pinned means consumers stay on 0.1.0 while `main` iterates — right for now, revisit at 1.0 |
| Z-04 | Verify `claude plugin update` actually delivers a bump end to end | S | Never tested. The whole distribution story rests on it |

---

## Continuous — Corpus freshness

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| C-01 | Automate monthly re-verification of `sources.md` | M | Re-fetch canonical docs, diff against assertions, open an issue per drift |
| ~~C-02~~ | ~~Add verification-date stamps to every `reference/` doc~~ | — | **Done.** Every `reference/` and `adapters/` doc carries a `Sources verified` stamp |
| C-03 | Watch for native promote/prune shipping upstream | — | Ongoing. Triggers the fold-in-and-archive path. **Assessed 2026-07-26: partially fired** — `/context`, `/doctor`'s CLAUDE.md trim (v2.1.206+), `MEMORY.md` size policing (v2.1.210) and skill-listing eviction by invocation frequency all shipped natively, displacing measurement and a share of CLAUDE.md pruning. Durable load tracking for rules/subagents, session-observed promotion, and eval gating have not. Full assessment in `docs/roadmap.md` § What would make us stop; registered as CLAIM-09 so the checker dates it. Fires properly if `/doctor` gains cross-session usage data or a first-party plugin proposes config from observed sessions |
| C-04 | Re-verify the `/init` vs `/doctor` invocability question | S | Explicitly flagged uncertain in `sources.md` |
| ~~C-05~~ | ~~Extend the freshness sweep to differentiator claims~~ | M | **Done.** `docs/claims.md` registers every comparative claim with a date, a cadence, and a `Falsified by:` line; `scripts/claims_check.py` resolves each to its exact public wording (and asserts retracted wording stays gone), warning on age and failing under `--strict`. The first sweep retracted **two of five** claims: `aneym/skill-stats` records skill-activation events (killing the load-tracking claim as worded, 4 days after it shipped), and `cuttlesoft/token-guard` plus `YawLabs/ctxlint` already fail CI on context-token thresholds. ClaudeForge's `InstructionsLoaded` hook re-confirmed as a stateless line-cap validator |
| ~~C-06~~ | ~~Record the landscape review so it isn't re-done~~ | — | **Done.** `.local/prior-art.md` (gitignored — the conclusions belong in the docs, the project-by-project reasoning doesn't) |
| C-07 | Schedule the quarterly claims sweep | S | C-05 built the register and the checker, but `claims_check.py --strict` only *reports* age — nothing performs the research. Same automation gap as C-01, and the same fix: a scheduled task that re-reads each `Watch:` line, re-probes the named projects, and opens an issue per drift. The 2026-07-26 sweep only happened because someone asked in conversation |
| C-08 | Decide whether to delegate context budgeting to `ctxlint` / `token-guard` | M | Invariant 9 says delegate rather than reimplement, and both tools do CI token enforcement on instruction files well — `ctxlint` already distinguishes always-loaded from conditional content. `footprint.py` measures bonsai's *own* cost, which stays ours (CLAIM-04), but proposing one of these as a consumer-repo artifact may beat growing our own budget checker. Surfaced by the C-05 sweep |

---

## Known defects and gaps

Real issues in what's already shipped. Not features.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| ~~D-01~~ | ~~`last_exercised` is never written~~ | — | **Fixed.** See P-05. Skills and subagents tracked since 2026-07-26 (P-09); only the hand-typed `/name` path remains → P-12 |
| ~~D-02~~ | ~~No `/bonsai:pause` test coverage~~ | — | **Done.** `tests/run.sh` now asserts the skill's `disable-model-invocation: true`, and that it documents the same `.claude/bonsai/paused` marker `pending.sh` and `retro.sh` actually check |
| ~~D-03~~ | ~~`retro.sh` field parsing is `sed`-based~~ | — | **Done.** Replaced with a pure-`awk` JSON string scanner: escapes honoured, and a key is only a key when a colon and a string follow it |
| D-04 | Rate-limit slot is claimed before work succeeds | S | A crashed pass burns the hour. Intentional (prevents thundering herd) but worth revisiting |
| D-05 | `prune_scan.py` `redundant` detection is keyword-based | M | Will produce false positives; `prune` is report-only so the blast radius is low |
| D-06 | No integration test for the full hook round trip | L | Unit-tested in pieces; the seams are unproven |
| ~~D-07~~ | ~~`survey.sh` `gh` calls have no timeout~~ | — | **Done.** Same as R-07 |
| D-08 | Nested `CLAUDE.md` placement is documented but unimplemented | M | Monorepo guidance exists in `placement.md`; no code path produces it |
| ~~D-09~~ | The "additive-only" claim is too broad to be true | S | **Done.** Narrowed in `README.md` and `docs/capabilities.md`: cleanup tooling exists, but it judges an artifact by reading it. What holds is that nothing else records whether an artifact was ever *loaded* |
| ~~D-10~~ | Prior-art table is out of date | S | **Done.** Rebuilt against the strongest current set (self-learning-skills, ClaudeForge, Context Cleanup, claude-reflect) and dated, since it goes stale in about a quarter. Re-verify under C-05 |
| ~~D-11~~ | Roadmap calls harness-agnosticism a "headline selling point" | S | **Done.** Cross-cutting commitment 1 now reads "table stakes, not a differentiator" and points at Phase 3 for the reasoning. The architectural discipline stands; the marketing claim is gone |
| D-12 | `skills/init` `allowed-tools` doesn't permit the scripts it invokes | S | Frontmatter allows `Bash(git *)`/`Bash(gh *)` but not `Bash(sh *)` or `Bash(python3 *)`, yet the skill runs `survey.sh`, `preflight.sh`, and `footprint.py`. Verify what the harness actually enforces, then fix the frontmatter — and audit the other four skills for the same gap |

---

## Picking up work

Phase 0 first, and V-02/V-03/V-04 before anything else — they're cheap and they de-risk the most. Note
what Phase 0 requires: *live sessions*, not more code. The 2026-07-26 batch cleared most of what could be
built offline (P-09/P-11, R-01, the V-08 guards, the small defects); what remains in Phase 0 is using
bonsai for real and writing down what happens.

Good offline picks while validation runs, in order: **X-01a** and **C-04** (cheap doc-verification with
empirical checks), **X-00** (the capability matrix that gates every adapter), **D-12** (verify what
`allowed-tools` actually enforces), then **P-01** (Phase 1's lead — outcome recording).

Anything touching behavior described in `reference/` updates that doc in the same change, with a citation.
See [CONTRIBUTING.md](../CONTRIBUTING.md).
