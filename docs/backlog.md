# Backlog

Itemized work. Reasoning and sequencing live in [roadmap.md](./roadmap.md); capability inventory in
[capabilities.md](./capabilities.md).

Size: **S** hours · **M** a day or two · **L** a week+ · **XL** needs its own design pass.
Phase 0 items block everything else.

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
| V-08 | Confirm flow-state guards fire at a sane rate | S | Target 40–70% of sessions skipped |
| V-09 | Dogfood on bonsai itself and record what it proposes | S | Also the README's opening demo |

---

## Phase 1 — Precision

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| P-01 | Record accept/reject/edit outcomes per proposal in the inventory | M | Nothing can be tuned without this |
| P-02 | Capture reject reasons as structured categories | S | "Wrong mechanism" vs "not a real pattern" imply opposite fixes |
| P-03 | Feed outcomes back into confidence scoring | M | Patterns resembling past rejections should score lower |
| P-04 | Re-tune `thresholds.md` from real data | M | Current numbers are reasoned guesses. Replace them and say so |
| P-05 | Add `last_exercised` tracking so staleness is real | M | Inventory field exists but nothing writes it — pruning is weaker than advertised until fixed |
| P-06 | Improve `bonsai-retrospective` prompt from observed failures | M | Depends on V-03 |
| P-07 | Add a proposal-quality self-check before writing | S | Cheap precision win: reject weak drafts before the human sees them |
| P-08 | Detect and merge near-duplicate observations | M | Model may emit different ids for one pattern; deterministic merge can't catch semantic dupes |

---

## Phase 2 — Eval replay

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| E-01 | On-demand single-case replay, human judges the diff | L | Cheapest useful version. Build this first and learn |
| E-02 | Stabilize the eval case capture format | M | Prerequisite for automation; don't automate against a moving target |
| E-03 | Automated judge pass over replay output | XL | LLM-as-judge on a noisy signal. Hard, easy to fool yourself |
| E-04 | Replay-driven pruning: flag artifacts that change nothing | L | Turns pruning from heuristic into evidence. The real prize |
| E-05 | Cost controls for replay | S | Replay is expensive; needs opt-in and a hard cap |

---

## Phase 3 — Multi-developer

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| T-01 | Design the shared/private split for team observations | XL | Hashed pattern identities committed, excerpts local. Needs a real design pass |
| T-02 | Cross-developer dedup so N teammates don't file N copies | L | Follows directly from T-01 |
| T-03 | Revisit whether team thresholds should *drop*, not rise | M | Corroboration across people beats repetition by one. Current tier logic may be backwards |
| T-04 | Team-visible proposal mode | M | Proposals are gitignored, so there's nothing to review on a PR |
| T-05 | Respect `CODEOWNERS` when routing proposals | M | Path owner should review guidance for their path |
| T-06 | Test the enterprise worktree path for real | M | Written to spec, never executed |

---

## Runtime robustness — pre-flight and degradation

Lands during Phase 0: a missing dependency would silently invalidate validation itself.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| R-01 | `scripts/preflight.sh` — detect `sh`, `git`, `python3`/`python`, `gh`; cache the result | M | Pure `sh` by necessity. Runs at install, never per session |
| R-02 | Wire the degradation ladder into every skill | M | Full / reduced / manual / unsupported, per `roadmap.md` |
| R-03 | Model-side fallbacks for the Python scripts | L | `apply.py`, `prune_scan.py`, `footprint.py` become in-skill work when Python is absent — slower, costs tokens, still functional |
| R-04 | `merge_observations.py` fallback or graceful off | M | Hardest case: it's on the detached path and owns the counters. Likely "observation off, say why" rather than a shell reimplementation |
| R-05 | Windows support: PowerShell hook variants | L | Hooks accept `shell: "powershell"`. Today bonsai is macOS/Linux-only and doesn't say so |
| R-06 | Assert the pure-`sh` invariant in tests | S | Fail if `pending.sh`/`retro.sh` ever gain a Python dependency |
| R-07 | Add timeouts to `gh` calls in `survey.sh` | S | Same as D-07. A slow network shouldn't stall `/bonsai:init` |

## Phase 2 — Harness-agnosticism (vendor lock-in)

Moved ahead of eval replay: replay built on Claude-only assumptions would need rebuilding.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| X-00 | Verified capability matrix: Claude Code, Cursor, Codex/`AGENTS.md`, Copilot | M | Per mechanism class, cited. Gates everything else. Cursor *has* glob scoping, so `adapters/agents-md.md` is currently wrong about it being Claude-only |
| X-01a | Verify whether `.claude/rules/*.md` supports `@` imports | S | **Do this first.** Determines whether wrappers can reference or must inline |
| W-01 | Define the canonical-body layout (`.harness/`) and wrapper contract | L | The core lock-in mechanism. One source of truth, thin per-harness wrappers |
| W-02 | Generate Claude Code wrappers from canonical bodies | M | Depends on X-01a |
| W-03 | Generate Cursor wrappers (`globs:` frontmatter) | M | The real test of the seam — Cursor has its own scoped-rule format |
| W-04 | `scripts/lint_parity.py` — fail when a wrapper drifts from its canonical body | M | What makes inlining safe. Joins `tests/run.sh` |
| W-05 | Propose the parity check as an artifact in consumer repos | M | Pre-commit or CI. A generated guardrail protecting generated config |
| X-02 | Test on a repo genuinely using two tools | M | Validates the seam end to end |
| X-03 | Document degradation honestly in the README | S | Enforcement and down-leveling may be Claude-only. Say so rather than let a Cursor user discover it |

## Phase 5 — Ecosystem

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| Z-01 | Submit to community plugin lists | S | Only after Phase 1 |
| Z-02 | Write the launch post | M | `capabilities.md` has the angles |

---

## Continuous — Corpus freshness

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| C-01 | Automate monthly re-verification of `sources.md` | M | Re-fetch canonical docs, diff against assertions, open an issue per drift |
| C-02 | Add verification-date stamps to every `reference/` doc | S | Treat a stale stamp as a bug |
| C-03 | Watch for native promote/prune shipping upstream | — | Ongoing. Triggers the fold-in-and-archive path |
| C-04 | Re-verify the `/init` vs `/doctor` invocability question | S | Explicitly flagged uncertain in `sources.md` |

---

## Known defects and gaps

Real issues in what's already shipped. Not features.

| ID | Item | Size | Notes |
| :--- | :--- | :--- | :--- |
| D-01 | `last_exercised` is never written | M | Same as P-05. Staleness detection is currently inert — the honest caveat behind the pruning claim |
| D-02 | No `/bonsai:pause` test coverage | S | The pause *mechanism* is tested via `pending.sh`; the skill isn't |
| D-03 | `retro.sh` field parsing is `sed`-based | S | Fine for well-formed hook JSON; would break on escaped quotes in a path |
| D-04 | Rate-limit slot is claimed before work succeeds | S | A crashed pass burns the hour. Intentional (prevents thundering herd) but worth revisiting |
| D-05 | `prune_scan.py` `redundant` detection is keyword-based | M | Will produce false positives; `prune` is report-only so the blast radius is low |
| D-06 | No integration test for the full hook round trip | L | Unit-tested in pieces; the seams are unproven |
| D-07 | `survey.sh` `gh` calls have no timeout | S | A slow network could stall `/bonsai:init` |
| D-08 | Nested `CLAUDE.md` placement is documented but unimplemented | M | Monorepo guidance exists in `placement.md`; no code path produces it |

---

## Picking up work

Phase 0 first, and V-02/V-03/V-04 before anything else — they're cheap and they de-risk the most.

Anything touching behavior described in `reference/` updates that doc in the same change, with a citation.
See [CONTRIBUTING.md](../CONTRIBUTING.md).
