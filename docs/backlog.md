# Backlog

Itemized work. Reasoning and sequencing live in [roadmap.md](./roadmap.md); capability inventory in
[capabilities.md](./capabilities.md).

Size: **S** hours · **M** a day or two · **L** a week+ · **XL** needs its own design pass.
Phase 0 items block everything else.

Re-prioritized 2026-07-26 — see [roadmap.md](./roadmap.md#phase-2--eval-replay). Measurement (load tracking,
eval replay) moved up; portability moved down, from headline claim to table stakes.

Groomed 2026-07-26, after a landscape sweep retracted two differentiator claims and found `/context`,
`/doctor`'s trim, and native plugin dormancy tracking had shipped upstream. Net effect: **three items
dropped, four gated, two closed by evidence already in hand, one promoted out of a deferred phase.** The
test applied was the roadmap's own — anything that presumed a user, a harness, or a subsystem that doesn't
exist yet is a guess dressed as progress, and carrying it as planned work implies a plan.

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
| R-03 | Model-side fallbacks for the Python scripts | L | `apply.py`, `prune_scan.py`, `footprint.py` become in-skill work when Python is absent — slower, costs tokens, still functional. **Gated 2026-07-26: not until a real user lacks `python3`.** `python3` ships with macOS and every mainstream Linux; R-02 already makes the degradation *legible*, which is the part that matters. Reimplementing three scripts against a hypothetical is exactly the fat this pass is trimming |
| R-04 | `merge_observations.py` fallback or graceful off | S | Same gate as R-03, but resolve the *decision* now and cheaply: it owns the counters on the detached path, so the answer is "observation off, say why" — not a shell reimplementation. Downgraded M→S accordingly; it's a paragraph in `roadmap.md`, not a subsystem |
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

## Phase 3 — Multi-harness generalization

Demoted from Phase 2 on 2026-07-26: portability is table stakes, not a differentiator. **Reframed the same
week**: the deliverable is not a conversion layer — 1:1 migration is a prompt, not a product, and the
rulesync cohort already moves text between formats. The deliverable is the *generalization process*: taking
a repo from one harness to several, honestly. That's G-01, and everything else in this phase is a component
of it.

**Groomed 2026-07-26.** This phase carried ten items — a whole wrapper-generation and parity-linting
subsystem — for a goal the same grooming pass demoted to table stakes. Building it now would be the
roadmap's own named failure: a guess dressed as progress, three layers deep, for a second harness no user
has asked for. The verification items are cheap and stay. The generator collapses to one design item,
explicitly gated.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| G-01 | `/bonsai:generalize` — the multi-harness generalization skill | XL | **The phase's centerpiece; when its gate opens, it outranks everything outside Phase 0.** Gated on a real multi-harness repo in front of us. Four outputs: (1) the canonical split — portable core in `AGENTS.md`, per-harness wrappers adding only what's harness-specific; (2) a **gap ledger** — per mechanism with no portable form (hooks, model routing, permissions), an explicit *enforced-here / advisory-there / absent-there* decision, recorded in the repo; (3) honest degradation prose, never implied parity; (4) an offered **eval** — the same task battery under each harness, because a generalization without an eval is a claim, not a migration. Capability mapping is researched fresh per-repo (model work), so nothing here maintains a rotting cross-harness index. Detection is a `capability`-class trigger: `survey.sh` already reports second-tool evidence, so bonsai *proposes* the run and the skill stays user-invoked. Absorbs the intent of W-01's seam and X-00's matrix as components. Deliberately in-repo, not a second project — extraction waits for demand independent of bonsai (see `roadmap.md` § Phase 3) |
| X-01a | Verify whether `.claude/rules/*.md` supports `@` imports | S | **Do this first.** Determines whether wrappers can reference or must inline. Cheap, and the answer constrains the seam whether or not the seam gets built |
| X-00 | Verified capability matrix: Claude Code, Cursor, Codex/`AGENTS.md`, Copilot | M | Per mechanism class, cited. Worth doing on its own merits — it's the honest-degradation table the README needs — independent of any generator. Absorbs X-04, which was a survey of the same ground. Feeds G-01's gap ledger, but note G-01 researches capability equivalence *fresh per run*; this matrix documents bonsai's own rendering targets, it is not the skill's knowledge base |
| X-03 | Document degradation honestly in the README | S | Enforcement and down-leveling may be Claude-only. Say so rather than let a Cursor user discover it. Follows X-00 and needs no code |
| W-01 | Design the canonical-body/wrapper seam | XL | **Gated: do not start until a real user runs bonsai on a second harness** — the same gate as G-01, of which this is now output (1). Absorbs the former W-02/W-03/W-04 (per-harness generation and the parity linter) — splitting a design that doesn't exist yet into four implementation tickets was false precision. The architectural commitment in `roadmap.md` § 1 stands regardless; it constrains how artifacts are written today, which costs nothing and is the actual value |
| ~~W-02~~ | ~~Generate Claude Code wrappers from canonical bodies~~ | — | **Absorbed into W-01 on 2026-07-26.** Kept as a row rather than deleted, because git history references the ID |
| ~~W-03~~ | ~~Generate Cursor wrappers (`globs:` frontmatter)~~ | — | **Absorbed into W-01.** Was billed as "the real test of the seam", which is an argument for it being part of the design, not a follow-on ticket |
| ~~W-04~~ | ~~`scripts/lint_parity.py` — fail when a wrapper drifts~~ | — | **Absorbed into W-01.** Drift protection is a property the seam must have, not a separate deliverable |
| ~~W-05~~ | ~~Propose the parity check as an artifact in consumer repos~~ | — | **Dropped 2026-07-26.** A generated guardrail protecting generated config, for a generator that doesn't exist, in repos that don't use two harnesses. Speculation on speculation. If W-01 ever lands and drift is a real observed problem, re-file it then |
| ~~X-04~~ | ~~Survey existing cross-tool artifact layouts before designing the seam~~ | — | **Done 2026-07-26**, by the C-05 sweep rather than deliberately: `wshobson/agents` renders one source to five harnesses via `make generate-all`, and `AGENTS.md` is a Linux Foundation standard read by most tools. That *is* the survey, and its conclusion is why this phase got demoted. Remaining specifics fold into X-00 |
| X-02 | Test on a repo genuinely using two tools | M | Validates the seam end to end. Gated behind W-01, so equally not now |

---

## Phase 4 — Multi-developer

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| T-01 | Design the shared/private split for team observations | XL | Hashed pattern identities committed, excerpts local. Needs a real design pass |
| T-02 | Cross-developer dedup so N teammates don't file N copies | L | Follows directly from T-01 |
| T-03 | Revisit whether team thresholds should *drop*, not rise | M | Corroboration across people beats repetition by one. Current tier logic may be backwards |
| T-04 | Team-visible proposal mode | M | Proposals are gitignored, so there's nothing to review on a PR |
| ~~T-05~~ | ~~Respect `CODEOWNERS` when routing proposals~~ | — | **Dropped 2026-07-26.** Presumes team-visible proposals (T-04), a `CODEOWNERS` file, and a review culture that routes config changes by path — three assumptions stacked on a phase gated behind Phase 0. The idea is fine; carrying it as planned work implies a plan. Re-file if T-04 ships and routing turns out to be a real complaint |
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
| ~~C-04~~ | ~~Re-verify the `/init` vs `/doctor` invocability question~~ | S | **Done 2026-07-26.** [Skills](https://code.claude.com/docs/en/skills) resolves it: "A few built-in commands are also available through the Skill tool, including `/init`, `/review`, and `/security-review`." `/doctor` became a bundled skill in v2.1.205. Both hand-offs are invocable; the fallback stays for older builds. `sources.md` no longer hedges and the `AGENTS.md` gotcha shrank to one line — a small resident-context win. Live confirmation remains V-04/V-05 |
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
| D-13 | `adapters/agents-md.md` conflated "no `AGENTS.md` equivalent" with "Claude-only" | S | Partly fixed 2026-07-26: the table now says path scoping has no equivalent *in `AGENTS.md`* (plain Markdown, no frontmatter) rather than implying no other tool has it. **Still unverified:** whether Cursor's `.cursor/rules/` `globs:` frontmatter is current, and what Copilot and Codex offer. Was buried in X-00, a now-gated Phase 3 item — a possibly-wrong doc claim shouldn't wait on a deferred phase (invariant 1) |
| D-12 | `skills/init` `allowed-tools` doesn't permit the scripts it invokes | S | Frontmatter allows `Bash(git *)`/`Bash(gh *)` but not `Bash(sh *)` or `Bash(python3 *)`, yet the skill runs `survey.sh`, `preflight.sh`, and `footprint.py`. Verify what the harness actually enforces, then fix the frontmatter — and audit the other four skills for the same gap |

---

## Picking up work

Phase 0 first, and V-02/V-03/V-04 before anything else — they're cheap and they de-risk the most. Note
what Phase 0 requires: *live sessions*, not more code. The 2026-07-26 batch cleared most of what could be
built offline (P-09/P-11, R-01, the V-08 guards, the small defects); what remains in Phase 0 is using
bonsai for real and writing down what happens.

Good offline picks while validation runs, in order: **P-13** (the `capability` class — the cheapest way to
test the central premise, and it needs no eval format or promotion machinery), **D-12** (verify what
`allowed-tools` actually enforces), **X-01a** and **D-13** (cheap doc-verification with empirical checks),
then **P-01** (Phase 1's lead — outcome recording).

X-00 and the Phase 3 items are no longer good offline picks: the seam they serve is gated on a second
harness nobody has asked for. The exception is the *trigger*: the moment a real multi-harness repo is in
front of us (an enterprise project, say), **G-01 jumps the queue** — it's ranked as the highest-value gated
item in the backlog, and its first real run makes the design decisions speculation can't. C-04 is closed; the `/init` and `/doctor` invocability question is answered in
the docs, and what remains is live confirmation (V-04/V-05), not research.

Anything touching behavior described in `reference/` updates that doc in the same change, with a citation.
See [CONTRIBUTING.md](../CONTRIBUTING.md).
