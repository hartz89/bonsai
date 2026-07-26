# The determinism boundary

*Sources verified 2026-07-26. A stale stamp is a bug — see `docs/backlog.md` C-01.*

Anything the same every time belongs in a script. Anything requiring judgment belongs to the model.
Getting this wrong is the most expensive mistake bonsai can make, because bonsai's cost is paid on every
session of every repo that installs it.

**Rule: the model decides; scripts observe, compute, and apply.**

A model that counts files, parses `git log`, or increments a counter is burning tokens on work that a
20-line script does perfectly, faster, and identically every time. Worse, it does it *unreliably* — the
whole reason `merge_observations.py` owns the counters is that a model inventing a new id for a
recurring pattern would silently reset its own threshold.

## Scripted — never left to the model

| Work | Where |
| :--- | :--- |
| Environment pre-flight: which of `sh`, `git`, `python3`/`python`, `gh` exist, and the resulting degradation tier | `scripts/preflight.sh` |
| Surveying the repo: which instruction files exist, line counts, which rules have `paths:`, what's installed | `scripts/survey.sh` |
| Workflow tier detection: contributor counts, merge ratios, branch protection, commit convention | `scripts/survey.sh` |
| Observation bookkeeping: id matching, one-per-session de-duplication, expiry, reversals, confidence | `scripts/merge_observations.py` |
| Threshold evaluation | `scripts/merge_observations.py` |
| Secret redaction | `scripts/merge_observations.py` (enforced, not trusted to the agent) |
| Proposal counting, etiquette back-off, archiving | `scripts/pending.sh` |
| Cost guards: turn counts, rate limits, daily caps, mid-operation detection | `scripts/retro.sh` |
| Resident-token estimates | `scripts/apply.py` |
| Applying an approved proposal, updating the inventory, filing the eval case | `scripts/apply.py` |
| Recording which harness artifacts are actually exercised, for staleness | `scripts/touch_artifact.sh` |
| Counting loads within the staleness window, for the prune report | `scripts/prune_scan.py` |
| Measuring bonsai's own resident footprint against its ceiling | `scripts/footprint.py` |
| Checking the backlog against git history | `scripts/backlog_check.py` |
| Staleness and orphan detection for pruning | `scripts/prune_scan.py` |

### Usage tracking coverage

`touch_artifact.sh` appends one `<date> <relpath>` line per artifact per day to
`.claude/bonsai/.state/exercised`. One log, three events, none of which can block:

| Artifact | Event | Payload field | Coverage |
| :--- | :--- | :--- | :--- |
| `CLAUDE.md`, `.claude/rules/*.md` | `InstructionsLoaded` | `file_path` | Complete — no decision control, exit code ignored |
| `.claude/agents/*.md` | `SubagentStart` | `agent_type` | Complete — no decision control, stderr to user only |
| `.claude/skills/*/SKILL.md` | `PostToolUse`, matcher `Skill` | `tool_input.skill` | **Partial** — model invocations only |

The skill gap is deliberate, not unbuilt. Typing `/name` never produces a tool call, and the only event
that observes it, `UserPromptExpansion`, sits on the user's prompt and can block the expansion — which
`etiquette.md` rule 1 forbids outright. `prune_scan.py` therefore marks skill staleness as
`coverage: "partial"` so a heavily-used slash-invoked skill is never reported as dead on this evidence
alone. Tracked in `docs/backlog.md` P-12.

`agent_type` is the agent's frontmatter `name`, not its filename, and plugin-supplied agents arrive
plugin-scoped (`my-plugin:reviewer`). The script resolves the frontmatter name and drops anything that
doesn't resolve to a file inside the project, so an unrecognised payload degrades to no data rather than
to wrong data.

## Model-owned — genuinely needs judgment

- Classifying a signal (constraint vs preference vs procedure). This is the hard call and the whole
  value of `placement.md`.
- Drafting the artifact's actual prose.
- Deciding whether a pattern generalizes or was a one-off.
- Reconciling a conflict between two existing artifacts.
- Explaining a proposal to a human in guided mode.

## Consequences for skill authoring

A skill body should read as: *run this script, then apply judgment to its output.* If a skill instructs
the agent to gather facts step by step, that's a script waiting to be written.

Concretely, a skill should never tell the model to:

- `Read` a file only to count its lines — `wc -l` in the survey does that
- Check whether a path exists — the survey already reported it
- Run a sequence of `git` commands whose output feeds a fixed calculation
- Re-derive something already cached in `.claude/bonsai/config.json`

## Output contract

Scripts emit JSON on stdout and nothing else, so a skill can consume one tool result instead of a dozen.
Errors go to stderr and exit 0 — bonsai never breaks a session over its own bookkeeping. `BONSAI_DEBUG=1`
turns on stderr logging.

Scripts stay POSIX `sh` where the logic is simple enough, and Python 3 where JSON or arithmetic makes
shell error-prone. No runtime dependencies beyond `git`, `python3`, and optionally `gh`.

Which of those are actually present is itself a scripted question, answered once at install by
`scripts/preflight.sh` and cached in `.claude/bonsai/.state/preflight.json`. It is pure `sh` by
necessity — a probe for a missing interpreter cannot need that interpreter — and it never re-probes on
the hot path, because environment detection on every `SessionStart` would violate the cost contract.
The tiers it reports (`full` / `reduced` / `manual` / `unsupported`) are defined in `docs/roadmap.md`.
A missing dependency yields a named one-line fix; bonsai never runs it.

## Test the scripts, not the prompts

Script behavior is assertable, and the fixtures in `tests/` assert it. Every guard in `etiquette.md` and
every threshold in `thresholds.md` is enforced by scripted code precisely so it can be tested — a
promise that only lives in a prompt is a promise that silently regresses.
