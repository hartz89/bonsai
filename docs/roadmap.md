# Roadmap

How bonsai should evolve, and the order that matters. Itemized work lives in
[backlog.md](./backlog.md); this file is the reasoning.

**The governing constraint: bonsai has never run.** Every script is unit-tested and every claim in
`reference/` is cited, but no skill has executed in a live session. The model-facing half — whether
classification is any good, whether the retrospective returns usable observations, whether proposals are
worth reading — is entirely unvalidated. Until that changes, any new feature is a guess dressed as
progress.

---

# Cross-cutting commitments

Three concerns that aren't phases. They constrain every decision from now on, because retrofitting any of
them later is expensive.

## 1. Harness-agnostic by construction

**The goal is that bonsai works for anyone using Claude Code, Cursor, Codex, or whatever ships next.** That
is an architectural commitment starting now, even though the adapters themselves wait for Phase 3 — every
Claude-specific assumption baked into the core is one that has to be unpicked later.

**Avoiding vendor lock-in is table stakes, not a differentiator** — cross-tool layouts already ship
elsewhere (see Phase 3). It stays a cross-cutting commitment anyway: anyone adopting a self-improving
harness is making a bet on a tool ecosystem, and bonsai should make that bet cheap to reverse. Lead with
the measurement, build the portability in regardless.

### The mechanism: canonical definitions, thin per-harness wrappers

One canonical body per artifact, plus a thin wrapper per harness supplying that harness's frontmatter and
living at that harness's path:

```
.harness/rules/testing.md          ← canonical body. Tool-agnostic prose. The single source of truth.
                                     Edit this one.
.claude/rules/testing.md           ← thin wrapper: `paths:` frontmatter + import of the canonical body
.cursor/rules/testing.mdc          ← thin wrapper: `globs:` frontmatter + same body
AGENTS.md                          ← references it for tools with no scoping mechanism
```

This is strictly better than having adapters *regenerate* each artifact, which is what earlier drafts of this
roadmap specified. Regeneration means N copies that drift and N places to edit. Wrappers mean the human edits
one file, every harness sees the change, and switching tools is adding a wrapper — not a migration.

**This project dogfoods the pattern**: `AGENTS.md` is canonical, `CLAUDE.md` is a thin wrapper importing it
plus Claude-specific notes.

**Open implementation question (X-01a), and it gates the design:** does `.claude/rules/*.md` support `@`
imports the way `CLAUDE.md` does? Confirmed: the rules directory supports **symlinks**, which handles the case
where no harness-specific frontmatter is needed — but a symlink can't add `paths:`, and `paths:` is precisely
the harness-specific part. Verify before building.

### Drift control: parity linting

Whichever mechanism wins, drift is the failure mode — and it's a *scripted* concern, squarely on the
deterministic side of `reference/determinism.md`. `scripts/lint_parity.py` (W-04) walks the canonical bodies
and their wrappers and fails when they disagree.

This is what makes the inline-copy fallback acceptable rather than a compromise: if rules can't import, a
generated wrapper may inline the canonical body, because a lint turns drift into a **test failure** instead of
a latent bug. Same reasoning applies to skills and agents, where frontmatter differs per harness but the body
shouldn't.

Two consequences worth stating:

- Parity lint joins `tests/run.sh`, so this repo can't ship a drifted wrapper.
- For *consumers*, bonsai should **propose the parity check as an artifact** — a pre-commit hook or CI step in
  their repo. A generated guardrail protecting generated config is exactly the kind of thing bonsai should be
  producing, and it's a strong demo of the enforcement-vs-advisory distinction.

Concretely, from now on:

- Nothing in `scripts/` or the promotion policy hardcodes a Claude Code path. Targets come from the adapter.
- `placement.md` reasons in **mechanism classes** (resident instruction, scoped instruction, procedure,
  isolated worker, enforcement) rather than Claude primitives. The Claude mapping lives in
  `adapters/claude-code.md`, where it already does.
- A capability the target harness lacks degrades explicitly and says so, rather than silently producing an
  artifact nobody reads.

**What's needed first is a verified capability matrix**, and it's more nuanced than "Claude Code vs
portable." Path scoping, for instance, is *not* Claude-only — Cursor rules support glob scoping — while
`AGENTS.md` has no equivalent. The current `adapters/agents-md.md` treats path scoping as a portability gap,
which is right for `AGENTS.md` and wrong for Cursor. That needs to be researched per-target and written down
before more adapters get built (X-00).

Honest caveat: enforcement hooks and model down-leveling may have no equivalent anywhere but Claude Code. If
so, bonsai is genuinely *better* on Claude Code and merely *useful* elsewhere. That's an acceptable outcome —
but it should be stated in the README rather than discovered by a disappointed Cursor user.

## 2. Runtime robustness — pre-flight and self-healing

bonsai currently assumes `python3` and POSIX `sh`. Both assumptions will fail for real users:

- **`python3` is not installed by default on Windows**, and may be `python` or absent on minimal containers.
- **Every hook script is POSIX `sh`.** On Windows, hooks can specify `shell: "powershell"`, which bonsai
  doesn't do. So today bonsai is effectively macOS/Linux-only, and nothing says so.
- `gh` is optional but its absence silently downgrades tier detection.

A missing dependency must never break a session, and must never fail *silently* either. The required
behavior is a **degradation ladder**, checked once at install and cached:

| Tier | Available | bonsai does |
| :--- | :--- | :--- |
| Full | `python3`, `sh`, `git` | Everything |
| Reduced | `sh`, `git`, no `python3` | Surfacing and guards still work (`pending.sh` and `retro.sh` are already pure `sh`). Threshold merging and `apply.py` fall back to the model doing the work in-skill — slower and costs tokens, but functional |
| Manual | `sh` only | Observation off. `/bonsai:promote` and `/bonsai:review` still work; the agent does the bookkeeping |
| Unsupported | none of the above | Refuse to install, with a clear reason. Never a half-installed state |

Two design rules that fall out of this:

1. **`pending.sh` and `retro.sh` must stay pure `sh` forever.** They're on the hot path; a Python dependency
   there would make a missing interpreter break every session start. This is now an invariant, not an accident.
2. **Pre-flight runs at install and is cached**, not re-checked per session. Probing the environment on every
   `SessionStart` violates the cost contract.

Self-healing should be *offering*, not *doing*: detect the gap, name the one-line fix (`brew install python3`),
and degrade gracefully in the meantime. bonsai does not install software on someone's machine.

## 3. Corpus freshness

**The existential risk, and the least glamorous work.**

`reference/` encodes Claude Code behavior as of 2026-07-25. Claude Code ships fast — the docs are littered
with `min-version` notes for changes within single point releases. When behavior drifts, bonsai doesn't
degrade gracefully; it starts confidently giving wrong advice, at scale, in other people's repositories.

- **Re-verify `sources.md` monthly.** Re-fetch each canonical doc, diff against what `reference/` asserts,
  open an issue per drift. Automatable, and a fitting use of `/loop` or a scheduled task.
- **Stamp every reference doc** with its verification date; treat a stale stamp as a bug.
- **Re-verify the comparative claims quarterly**, via `docs/claims.md` and
  `scripts/claims_check.py --strict`. Landscape claims rot faster than citations: the 2026-07-26 sweep
  retracted two of five, one of them four days after its falsifier shipped. A confidently wrong "nobody else
  does X" is the same failure as a stale `reference/` doc, one level up — and it's the one a reader can
  disprove in a single search, so it costs more credibility than it looks like it should.
- **Watch specifically for**: new hook events or types, changes to `SessionStart`/`SessionEnd` output control,
  skill frontmatter additions, `disable-model-invocation` semantics, and whether `/init` becomes
  model-invocable. This risk multiplies with each harness supported.
- **Watch for obsolescence.** If Anthropic ships native promotion or pruning, fold in and archive rather than
  compete.

---

# Phases

## Phase 0 — Validate (blocking)

Nothing else starts until this finishes. The work here is *using* bonsai, not building it.

**Do:** install on real projects and live with it. Fix what breaks. Write down every proposal it makes and
whether it was any good.

**Explicitly do not:** add features or expand the reference corpus. If a gap is found, record it in the
backlog and keep validating.

The one exception is pre-flight (R-01/R-02): a missing dependency would silently invalidate the validation
itself, so environment detection lands first.

**Exit criteria** — all of them:

- Run on **3+ real repos** for **2+ weeks**, including at least one with more than one contributor
- At least **one accepted artifact the author wouldn't have written themselves** — the whole premise. If
  every accepted proposal is something you'd have done anyway, bonsai is a reminder, not a tool
- **Zero unsolicited interruptions** experienced as annoying, self-reported honestly
- Measured resident cost matches the README's claim, verified with `/context` before and after
- The `SessionEnd` → `SessionStart` round trip observed working end to end at least 10 times

**Most likely failure modes**, in order of probability:

1. The retrospective returns vague or wrong observations. Haiku may be too small; `retrospective_model` is
   the escape hatch, but if Sonnet is required the cost story changes and `budget.md` needs rewriting.
2. `SessionEnd` doesn't fire reliably (terminal kill, crash), so observation silently never happens.
   `PreCompact` is the fallback; if both miss, the loop needs a different trigger.
3. Proposals are technically correct but not worth the interruption. Hardest failure to detect, because
   nothing errors — it just isn't useful.
4. Delegation to `/init` fails because it isn't model-invocable in practice.

## Phase 1 — Precision

Once it runs, make it *right*. The only metric that matters is **proposal accept rate**.

Every threshold in `thresholds.md` is currently a number I made up. They're reasoned, but they're guesses, and
they should be replaced with numbers derived from what people actually accept.

**Work:** instrument outcomes — accept / reject / edit per proposal, with structured reject reasons — and feed
both back into confidence scoring. Tune thresholds from the data. Fix `placement.md` wherever classification
demonstrably went wrong.

**Target:** ≥70% of proposals accepted on first review. Below ~40% after tuning, the classification isn't
good enough and bonsai is noise — see [kill criteria](#what-would-make-us-stop).

A false positive is worse than a missed pattern. Tune toward fewer, better proposals rather than coverage.

## Phase 2 — Eval replay

Promoted ahead of harness-agnosticism on 2026-07-26, reversing the earlier ordering. The reasoning that put
portability first — that replay built on Claude-only assumptions would need rebuilding — is still true, but
it's outweighed. Cross-tool artifact formats are well-trodden ground; evidence-based pruning isn't. Some rework
is a cheaper price than deferring the thing only this project is trying to do.

The honest differentiator, and currently the biggest gap between what bonsai claims and what it does. v1
*captures* eval cases; it can't yet answer **"does this artifact actually change behavior?"**

Without replay, pruning rests on staleness heuristics — an artifact is suspect because it's old, not because
it's proven useless. That's the one place bonsai's story is thinner than it sounds.

**Cheapest first:**

1. **On-demand single-case replay.** Run one captured case headless, with and without the artifact; show the
   human both outputs. No automated judgment. Useful immediately, cheap to build.
2. **Automated judgment.** A judge pass scores whether the expected behavior appeared. Hard — LLM-as-judge on
   a noisy signal.
3. **Regression suite.** Replay all cases on demand; flag artifacts that no longer change anything.

**Known hard problems:** nondeterminism means one run proves little; replay costs real money; and "did it
help" is often genuinely ambiguous. Build step 1, learn, and don't promise 2–3 until it teaches us something.

Replay and load tracking (P-09) are two halves of one claim. Load tracking says an artifact was never
*consulted*; replay says it was consulted and *changed nothing*. Together they're the evidence base for
pruning. Neither is convincing alone.

## Phase 3 — Multi-harness generalization

Demoted from Phase 2 on the same review. Cross-tool artifact layouts — `AGENTS.md`, per-harness adapters, broad
tool detection — are established practice, so this is table stakes rather than something to lead with.

**Reframed 2026-07-26: the product here is the generalization process, not a conversion layer.** Two
findings forced it. First, 1:1 harness migration is a prompt, not a product — a model sitting inside the
repo, with full context on what the config *means*, out-converts any text mover; and the text movers
(rulesync and its cohort, 20+ targets, `import`/`convert` commands) already exist, while `AGENTS.md`
convergence shrinks the syntactic problem every quarter. Second, what none of them do is reason about
**capability equivalence**: which mechanisms have no portable form, what degrades to advisory prose, and
whether the generalized config still behaves. That's the unoccupied ground, and it's G-01:

- **The canonical split** — portable core in `AGENTS.md`, per-harness wrappers adding only what's
  harness-specific (the W-01 seam, as a component rather than a deliverable).
- **A gap ledger** — an explicit *enforced-here / advisory-there / absent-there* decision per non-portable
  mechanism, recorded in the repo instead of silently meaning different things in different tools.
- **An offered eval** — the same task battery under each harness. A generalization without an eval is a
  claim, not a migration.

Two design commitments, both learned the hard way this same week: capability mapping is **researched fresh
per run** (model work), never maintained as a cross-harness index — the claims register retracted two of
five entries at its *first* sweep, and that rot rate times N harnesses is a full-time job with no moat.
And G-01 lives **in bonsai, not a second repository** — its seed is `adapters/` plus `survey.sh`'s
multi-tool detection, detection routes through the `capability` proposal class ("this repo runs two
harnesses with divergent config — run `/bonsai:generalize`"), and two zero-user products are worse than
one. Extraction waits for demand independent of the observe-and-propose loop; starting in-repo makes that
split cheap, starting split makes the merge-back expensive.

What survives the demotion: portability remains a **cross-cutting commitment** (above), because every
Claude-specific assumption baked in now is one to unpick later. What doesn't: treating it as a headline claim.
And survey the existing conventions before designing the seam (X-04) — inventing an incompatible layout would
defeat the purpose.

**Sequence** (gated on a real multi-harness repo; when the gate opens, G-01 outranks everything outside
Phase 0):

1. **Verified capability matrix** across Claude Code, Cursor, Codex/`AGENTS.md`, and Copilot — per mechanism
   class, what each target actually supports, cited like everything else in `reference/`. Documents bonsai's
   own rendering targets; it is not G-01's knowledge base.
2. **Refactor the artifact plan** to be explicitly harness-neutral, if Phase 0/1 revealed leakage.
3. **Spec and build G-01** against the triggering repo — canonical split, gap ledger, degradation prose,
   the eval offer. The first real run settles the design decisions speculation can't.
4. **Implement the `AGENTS.md` and Cursor adapters as code** in its service — Cursor is the real test,
   since its scoped-rule format exercises the seam rather than the lowest common denominator.
5. **Test on a repo genuinely using two tools**, and state the degradation honestly in the README.

Windows support belongs here too (R-05): a PowerShell path for the hook scripts is a portability problem of
the same shape.

## Phase 4 — Multi-developer

A real architectural gap, not a feature request. Observations are machine-local by design (they contain
verbatim conversation excerpts). So on a team of five, five people independently observe the same pattern,
each crosses their own threshold, and **each proposes the same artifact.** Nobody has seen this yet because
bonsai hasn't run on a team repo — but it follows from the design.

Tensions to resolve:

- **Dedup needs shared state; privacy forbids sharing excerpts.** Likely shape: a committed ledger of *hashed
  pattern identities* and counts, excerpts staying local. bonsai learns "three teammates hit this" without
  publishing what anyone said.
- **Team thresholds may need to *drop*, not rise.** Corroboration across people is stronger evidence than
  repetition by one person. The current `enterprise` tier raises thresholds; that may be backwards.
- **Reviewing a harness proposal as a team.** Proposals are gitignored, so there's no PR to comment on.
- **Who owns the harness?** Respect `CODEOWNERS` and route proposals to whoever owns the path.

## Phase 5 — Ecosystem

Distribution: community plugin lists, a launch writeup, conference or blog surface. Deliberately last —
adoption before validation is actively harmful, because a tool giving bad harness advice at scale is worse
than no tool.

---

## Metrics that matter

Track from Phase 1 onward. Everything else is vanity.

| Metric | Target | Why |
| :--- | :--- | :--- |
| Proposal accept rate | ≥70% | The precision signal. The single most important number |
| Resident tokens | ≤350 | The cost contract, already enforced by tests |
| Unsolicited interruptions / week | ~0 | Annoyance is the uninstall trigger |
| Pruned : added ratio | → 1:1 in steady state | If this stays near 0:1, bonsai is just another accumulator |
| Time to first accepted artifact | < 1 week | The install-time harvest exists so this isn't weeks |
| Sessions skipped by flow guards | 40–70% | Too low means intrusive; too high means it never learns |
| Install success rate across environments | ~100% | Nobody should get a half-installed state |

---

## What would make us stop

Stated upfront, because a project that can't name its own failure conditions will rationalize instead.

- **Accept rate stays below ~40% after Phase 1 tuning.** The classification isn't good enough; bonsai is
  noise with extra steps, and shipping wider would be irresponsible.
- **Anthropic ships native promote/prune.** Likely — the Agent Skills post explicitly anticipates agents that
  "create, edit, and evaluate Skills on their own." Correct response: fold the reference corpus into whatever
  ships, archive the plugin, say so plainly in the README.

  **Assessed 2026-07-26 (C-03): partially fired. Not yet the archive trigger.** What shipped natively in
  roughly the preceding six months, all of it free and installed by default:

  | Native capability | What it displaces |
  | :--- | :--- |
  | `/context` — window breakdown by system prompt, tools, MCP, subagents *with load source*, memory, skills | Most of the footprint ledger |
  | `/doctor` — CLAUDE.md trim proposing removal of content Claude can derive from the codebase, human-confirmed (v2.1.206+) | A real share of `/bonsai:prune`, on the `CLAUDE.md` mechanism |
  | `MEMORY.md` measured after writes, with shortening guidance (v2.1.210, narrowed v2.1.211) | The budget nudge, for auto-memory |
  | Skill-listing overflow evicting descriptions "starting with the skills you invoke least" | Usage-based pruning — *for skill descriptions*, in-memory, not durable |

  What has **not** shipped: durable cross-session load tracking for rules or subagents, promotion from
  observed sessions, eval-gated promotion, provenance joined to usage, or routing across all seven
  mechanisms. Across 273 official marketplace entries, `prune`, `stale`, and `hygiene` return zero matches;
  the one official config-hygiene plugin (`claude-md-management`) has four commits in its history, no
  substantive change since 2026-01-20, and targets `.claude.local.md` — a filename that does not exist.

  **Two events fire this condition properly:** `/doctor` gaining durable cross-session usage data, or any
  first-party plugin that proposes configuration from observed sessions. Either one, archive.

  **What it changes now:** stop claiming the parts that shipped — measurement and `CLAUDE.md` trimming are
  Anthropic's, and `/bonsai:init` should keep delegating rather than narrating. The honest remaining scope is
  narrower than v1 was scoped for. Note the direction of travel too: the harness evicting resident config on
  an invocation-frequency signal is bonsai's own thesis, implemented in-house.

  **The reframe (2026-07-26): treat native capability as supply, not competition.** Every capability
  Anthropic ships has until now *shrunk* bonsai's scope, which makes the roadmap a losing race against a
  weekly release cadence. The `capability` placement class inverts that: a shipped feature nobody uses
  becomes something to route people to, so each release *grows* the surface bonsai works on. The gap it
  addresses is real and adjacent to what's built — Anthropic ships the capability and states its cost, but
  nothing knows from observed work that *this* project would benefit *now*. `pluginSuggestionMarketplaces`
  is the closest native equivalent and keys off the working directory, not observed usage.

  This is also the cheapest thing in the roadmap to validate. A `capability` proposal needs no eval-case
  format, no promotion machinery, and no authored artifact — so the accept-rate stop condition above becomes
  measurable in days rather than after Phase 2. If bonsai's central premise is wrong, this is where it shows
  up first and least expensively.
- **Retrospective quality requires a frontier model.** If Haiku can't do it and Sonnet+ is needed every
  session, the cost story collapses and bonsai should become manual-only.
- **Nobody accepts a proposal they wouldn't have written themselves.** Then it's a reminder system, and should
  be rewritten as something much smaller.

---

## Deliberately not planned

The YAGNI list. These come up naturally and should keep being declined. Where the reasoning needs more than
a line, it lives in [`docs/design-notes.md`](./design-notes.md):

- **A vector database for the learning loop.** Embeddings are a recall tool over unbounded history; residency
  is a judgment call over a bounded, approved set. Never in the resident path — possibly, someday, in
  candidate recall. See `design-notes.md`.
- **A skills marketplace or library.** `obra/superpowers` does this well. bonsai generates from *your* project.
- **A web dashboard.** The artifacts are files. `git log` and `/bonsai:prune` are the interface.
- **An MCP server.** Would add tool definitions to every session for work scripts already do.
- **Agent-teams integration.** Experimental and disabled by default.
- **Installing dependencies on the user's machine.** Detect, name the fix, degrade. Never install.
- **Supporting every agent tool.** Claude Code, Cursor, and `AGENTS.md` done well beats six done badly.
- **Auto-applying anything resident.** Not a feature, ever. The approval gate is the security model.
