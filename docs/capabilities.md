# Capability ledger

Working inventory of what bonsai actually does, kept current during the build. Source material for the
README and for social copy — every "why it matters" line here should be defensible, and anything not yet
`done` must not be claimed publicly.

Status: `done` · `partial` · `planned`

## The core loop

| Capability | What it does | Why a consumer cares | Status |
| :--- | :--- | :--- | :--- |
| Detached observation | A `SessionEnd` hook spawns a Haiku pass over the finished transcript in a separate process | Learns from your work at **zero cost to your context window** — it isn't in your session | done |
| Deterministic thresholds | `merge_observations.py` owns id matching, one-per-session de-dup, 45-day expiry, reversals, confidence | Patterns get promoted on evidence, not on a model's mood. Counters can't silently reset | done |
| Proposal queue | Crossings become drafts in `.claude/bonsai/proposals/`, never live config | **Nothing enters your always-on context without you seeing it.** Also the prompt-injection mitigation | done |
| One-line surfacing | A `SessionStart` script counts pending proposals and emits a single line, no model call | You find out at a session boundary, never mid-task | done |
| Enforced application | `apply.py` writes the artifact, files the eval case, records provenance — with a target-path allowlist | A poisoned proposal can't write outside harness paths. Enforced in code, not requested of a model | done |
| Manual promotion | `/bonsai:promote` runs the same policy interactively | Power users can codify on demand instead of waiting for thresholds | done |
| Review & apply | `/bonsai:review` renders diffs and applies on approval | The human stays the decision-maker | done |
| Pruning | `/bonsai:prune` demotes stale, unused, and conflicting artifacts, and reports the footprint ledger | Most cleanup tools judge an artifact by reading it. Removal here argues from recorded loads — across rules, skills, *and* subagents, joined to what proposed them (`docs/claims.md` CLAIM-01, narrowed 2026-07-26) | done |
| Load tracking | `InstructionsLoaded`, `SubagentStart`, and a `Skill`-matched `PostToolUse` hook log which rules, subagents, and skills are actually exercised; staleness is measured from real usage, and the prune report states the count | Makes pruning evidence-based rather than a guess. None of the three can return output or block, so they cannot interrupt. Skills are covered on the model-invoked path only | done |

## Placement intelligence

| Capability | What it does | Why a consumer cares | Status |
| :--- | :--- | :--- | :--- |
| Seven-mechanism routing | Routes each pattern to CLAUDE.md, `.claude/rules/`, a skill, a subagent, a hook, or a permission | Most people never learn this decision surface. It's the actual expertise being packaged | done |
| Constraint vs preference | Mechanically checkable rules become hooks/permissions; judgment calls become advisory rules, labeled as such | Stops you shipping unenforceable wishes. *"Model judgments aren't reliable guardrails"* | done |
| Path scoping | Guidance that correlates with a directory or file type becomes a `paths:`-scoped rule | Zero resident context cost, and teammates don't load rules irrelevant to their work | done |
| Model down-leveling | Context-heavy read-mostly tasks become Haiku subagents with narrowed tools and bounded turns | Moves expensive work off your main model. Usually where bonsai pays for itself | done |
| Personal vs team | Personal taste routes to `CLAUDE.local.md` / user rules, never committed files | Your preferences don't become your team's problem | done |
| Budget gate | Every proposal carries a resident-token delta; CLAUDE.md over 200 lines triggers a refactor, not an append | Directly prevents the context bloat that degrades every session | done |
| Capability routing | Routes an observation to a shipped first-party command or plugin instead of authoring anything — `/doctor`, `/context`, `session-report` — with evidence for why *this* project, *now* | The only proposal class with a **zero** resident-token delta. Anthropic ships the capability and states its cost; nothing else knows from your sessions that you'd benefit today. Capped at once per capability per 90 days | planned (P-13) |

## Good citizenship

| Capability | What it does | Why a consumer cares | Status |
| :--- | :--- | :--- | :--- |
| Measured footprint | `footprint.py` computes bonsai's own resident cost against a 350-token ceiling | The cost claim is **testable**, not asserted. **Measured at 162 tokens**, enforced by `tests/run.sh` | done |
| Zero-cost skills | Four of five skills are `disable-model-invocation`, so they cost nothing until invoked | Only `/bonsai:promote` is resident, because only it needs to be | done |
| Flow-state protection | Skips sessions under 8 turns, hot-path edit loops, failing-test endings, mid-rebase/merge/bisect | Won't tap you on the shoulder mid-sprint. Guards run in shell before any model spawns | done |
| Back-off, never escalate | Ignored proposals get quieter, then auto-archive at 7 sessions | The opposite of a nag. Silence is treated as an answer | done |
| Cost ceilings | Haiku, `effort: low`, `maxTurns` bounded, 1/hour, 6/day default, fully disableable | You can't get surprised by a bill | done |
| Never blocks | No `Stop` hook, no `PostToolUse` output, no blocking exit codes anywhere in bonsai's own machinery | It cannot get in your way, structurally | done |
| Silence when idle | Nothing pending means no output at all | No "nothing to report" noise | done |

## Fit and hygiene

| Capability | What it does | Why a consumer cares | Status |
| :--- | :--- | :--- | :--- |
| Delegates, doesn't reinvent | Hands off to `/init` for bootstrap and `/doctor` for trims and unused-artifact detection | Uses the tools Anthropic already ships. Less to trust, less to maintain | done |
| Tier detection | Classifies solo / team / enterprise from contributors, merge ratio, branch protection, CODEOWNERS | Thresholds and git strategy scale to the project instead of assuming one | done |
| Git strategy by tier | Solo commits directly; team and enterprise branch, and use worktrees when the tree is dirty | Harness changes stay reviewable and never tangle with your feature work | done |
| Guided vs express mode | Auto-detected from existing harness maturity | Teaches a newcomer; gets out of an expert's way | done |
| Privacy split | Observation excerpts stay gitignored and machine-local; artifacts, inventory, and evals are committed | Your verbatim conversation never lands in a shared repo | done |
| Portability seam | Artifacts render to Claude Code primitives or to the portable `AGENTS.md` + `SKILL.md` subset | Not a dead end if you add another agent tool | partial |
| Cited guidance | Every normative claim in `reference/` traces to a canonical Anthropic/standards source | You can check the homework instead of trusting a blog post | done |

## Deliberately not built

Worth stating publicly — it's the YAGNI story, and it's differentiating.

- No MCP server. It would add tool definitions to every session for work scripts already do.
- No custom output style. Never compacted, and it drops the default system prompt's engineering instructions.
- No fifth skill for status reporting. `/bonsai:prune` reports footprint instead — a skill isn't worth 50 resident tokens forever.
- No automated eval replay in v1. Cases are captured; replay lands once the format is proven.
- No agent teams integration. Experimental and disabled by default.

## Angles for social copy

Claims that are true, specific, and non-obvious. Verify each against the ledger above before posting —
anything marked `planned` or `partial` must be framed as roadmap, not shipped. Anything comparative must
also clear `docs/claims.md`; the 2026-07-26 sweep retracted two claims that had been live in this list.

1. "Your CLAUDE.md is a landfill. bonsai asks a question nothing else can: did the rule I added six weeks
   ago ever load?" *(Not "the only tool that takes things out" — that was false and is retracted. Cleanup
   tooling exists; usage-based cleanup exists for skills. The narrow, true version is above.)*
2. "It learns from your sessions at zero context cost — the observation pass runs in a different process."
3. "It measures its own footprint against a token ceiling, and the test fails if it exceeds it. 162 tokens."
4. "It won't interrupt you mid-sprint. It detects hot-path sessions in shell and skips before spending a token."
5. "It knows the difference between a rule you can enforce and a preference you can only hope for — and routes them differently."
6. "It doesn't reinvent `/init` or `/doctor`. It drives them for you."
7. "Nothing it writes reaches your always-on context without you approving the diff."
8. **Dogfooding**: "bonsai runs bonsai. The first thing it caught was our own README overstating how cheap it
   was — projected 126 tokens, measured 162. We fixed the number." Self-deprecating, specific, and proves the
   measurement is real rather than marketing.
9. **Dogfooding as safety**: "It can't edit its own source. The allowlist that stops it touching your code
   stops it touching ours."
10. **Lock-in** (frame as roadmap, Phase 2 — *not* shipped): "Canonical rule bodies with thin per-harness
    wrappers, and a lint that fails when they drift. Switching agent tools should be adding a wrapper, not a
    migration."
11. **Honesty angle**: "The roadmap has a section called 'What would make us stop.'" Unusual enough to be
    worth a post on its own.
