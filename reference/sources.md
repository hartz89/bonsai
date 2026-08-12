# Sources

Every normative claim in `reference/` traces to one of these. When guidance here conflicts with a
source, the source wins — open an issue.

Verified 2026-07-25 against Claude Code v2.1.2xx docs. Hooks re-verified 2026-07-26 for usage tracking
(`SubagentStart`, `PostToolUse` on the `Skill` tool, `UserPromptExpansion`, `async`).

## Primary — mechanism selection and context cost

| Source | What it establishes |
| :--- | :--- |
| [Steering Claude Code: when to use CLAUDE.md, skills, hooks, and subagents](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more) | The seven mechanisms, their loading/persistence/context-cost tradeoffs, and the named anti-patterns |
| [Extend Claude Code](https://code.claude.com/docs/en/features-overview) | "Build your setup over time" trigger table; per-feature context cost; layering and precedence rules |
| [How Claude remembers your project](https://code.claude.com/docs/en/memory) | CLAUDE.md scopes and load order; 200-line target; `.claude/rules/` and `paths:` frontmatter; auto memory; `AGENTS.md` import pattern |
| [Effective context engineering for AI agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents) | "Smallest set of high-signal tokens"; context rot and finite attention budget; just-in-time retrieval; structured note-taking |

## Primary — artifact authoring

| Source | What it establishes |
| :--- | :--- |
| [Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills) | Three-tier progressive disclosure; "start with evaluation"; split when unwieldy; references one level deep; TOC for files over 100 lines |
| [Agent Skills specification](https://github.com/agentskills/agentskills) · [agentskills.io](https://agentskills.io) | Cross-vendor `SKILL.md` standard — the portable substrate |
| [Skills](https://code.claude.com/docs/en/skills) | Frontmatter schema; `disable-model-invocation`; `context: fork` + `agent`; skill locations and precedence; description truncated at 1,536 chars. *Verified 2026-07-26:* the listing is budgeted (~1% of the context window, `skillListingBudgetFraction`) and **overflow is evicted by usage frequency** — "starting with the skills you invoke least". Upstream precedent for pruning resident config on a usage signal, not a semantic one |
| [Subagents](https://code.claude.com/docs/en/sub-agents) | Frontmatter schema including `model`, `tools`, `maxTurns`, `effort`, `memory`, `skills`; what loads at startup |
| [Hooks](https://code.claude.com/docs/en/hooks) | Event list; hook types (`command`, `http`, `mcp_tool`, `prompt`, `agent`); per-event output control |
| [Hooks § SubagentStart](https://code.claude.com/docs/en/hooks#subagentstart) | *Verified 2026-07-26.* Fires when a subagent is spawned; input carries `agent_id` and `agent_type`; matcher filters on agent type. Output control: **No** — "Shows stderr to user only", and it "can't block subagent creation" |
| [Hooks § common input fields](https://code.claude.com/docs/en/hooks#common-input-fields) | *Verified 2026-07-26.* `agent_type` is the custom subagent's frontmatter `name`, "not the filename", and for plugin subagents "the plugin-scoped identifier such as `my-plugin:reviewer`". It is also present on *any* event firing inside a subagent — hence `touch_artifact.sh` checks `hook_event_name` before trusting it |
| [Hooks § UserPromptExpansion](https://code.claude.com/docs/en/hooks#userpromptexpansion) | *Verified 2026-07-26.* The only event that sees a hand-typed `/skill`: "a `PreToolUse` hook matching the `Skill` tool fires only when Claude calls the tool, but typing `/skillname` directly bypasses `PreToolUse`." It can block the expansion, so `etiquette.md` rule 1 rules it out. There is no `SkillStart`/`SkillEnd` event |
| [Hooks § run hooks in the background](https://code.claude.com/docs/en/hooks#run-hooks-in-the-background) | *Verified 2026-07-26.* `"async": true` on a `command` hook runs it without blocking, and "response fields like `decision`, `permissionDecision`, and `continue` have no effect" — what makes a `PostToolUse` usage log safe |
| [Tools reference](https://code.claude.com/docs/en/tools-reference) | *Verified 2026-07-26.* `Skill` is a real tool name usable as a hook matcher: a skill "runs through the existing `Skill` tool rather than adding a new tool entry" |
| [Plugins reference](https://code.claude.com/docs/en/plugins-reference) | Plugin layout; `plugin.json` schema; `userConfig`; `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; `pluginConfigs` read only from user/managed settings |
| [Commands](https://code.claude.com/docs/en/commands) | Which `/`-entries are built-in commands vs bundled skills — determines what bonsai can invoke |

## Capability recommendations

Establishes what bonsai must **not** rebuild, and how a `capability` proposal hands off. All verified
2026-07-26.

| Source | What it establishes |
| :--- | :--- |
| [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins) | `/plugin install <name>@<marketplace>`; install scopes (user / project / local / managed). The details pane already reports a **Context cost** estimate "so you can see how many tokens the plugin will add to your context window every turn" (v2.1.143+), a **Last updated** date (v2.1.144+), and a **Will install** component inventory (v2.1.145+) — bonsai must not duplicate any of these |
| [Discover plugins § Configure team marketplaces](https://code.claude.com/docs/en/discover-plugins#configure-team-marketplaces) | `extraKnownMarketplaces` and `enabledPlugins` in a project's `.claude/settings.json`: "When team members trust the repository folder, Claude Code prompts them to install these marketplaces and plugins." The team-distribution path for a `capability` proposal — bonsai proposes the entry, the harness does the prompting |
| [Discover plugins § Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) | Native plugin dormancy: a **Not used recently** group for plugins "haven't used in at least two weeks, over a span of at least 10 sessions", with a **Last used** line (v2.1.187+). First-party usage tracking, for plugins — so `capability` proposals must target capability *absence*, never plugin dormancy, which is covered |
| [Discover plugins § Security](https://code.claude.com/docs/en/discover-plugins#security) | "Plugins and marketplaces are highly trusted components that can execute arbitrary code on your machine with your user privileges." The reason `capability` recommendations are first-party only (`placement.md` anti-pattern 9) |

## Portability

| Source | What it establishes |
| :--- | :--- |
| [AGENTS.md](https://agents.md) | The cross-tool instruction convention; stewarded by the Agentic AI Foundation under the Linux Foundation since 2025-12-09 |
| [How Claude remembers your project § AGENTS.md](https://code.claude.com/docs/en/memory#agents-md) | Claude Code does **not** read `AGENTS.md`; the canonical bridge is a `CLAUDE.md` containing `@AGENTS.md` |

## Prior art

Read before contributing; bonsai deliberately overlaps a lot of this. **What we claim is different from it
lives in [`docs/claims.md`](../docs/claims.md)**, each entry dated and falsifiable — do not assert novelty
from this list alone. Swept 2026-07-26.

- [netresearch/retro-skill](https://github.com/netresearch/retro-skill) — transcript friction analysis routed to six destinations with per-proposal approval; the closest comparable
- [aneym/skill-stats](https://github.com/aneym/skill-stats) — `PostToolUse` skill-activation records in SQLite, dormancy reporting. Falsified CLAIM-06
- [YawLabs/ctxlint](https://github.com/YawLabs/ctxlint) — static linter for agent context files; always-loaded-vs-conditional token accounting, `--strict` fails CI
- [cuttlesoft/token-guard](https://cuttlesoft.com/blog/2026/02/10/token-guard-keeping-your-agent-context-lean-in-ci/) — GitHub Action failing builds on instruction-file token thresholds. Falsified CLAIM-07
- [egorfedorov/claude-context-optimizer](https://github.com/egorfedorov/claude-context-optimizer) — cross-session file-read affinity patterns; `CLAUDE.md` bloat by size
- [alirezarezvani/ClaudeForge](https://github.com/alirezarezvani/claudeforge) — `CLAUDE.md` maintenance; `InstructionsLoaded` used as a stateless line-cap validator
- [Kulaxyz/self-learning-skills](https://github.com/Kulaxyz/self-learning-skills) — golden-path harvesting into skills/rules with `AGENTS.md` adapters
- [anthropics/claude-md-management](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/claude-md-management) — official `CLAUDE.md` quality scoring and session-learning capture
- [obra/superpowers](https://github.com/obra/superpowers) — large curated skill library, incl. skill-authoring guidance
- [affaan-m/ECC](https://github.com/affaan-m/ECC) — harness optimization: skills, instincts, memory, security
- [ChristopherA's bootstrap seed](https://gist.github.com/ChristopherA/fd2985551e765a86f4fbb24080263a2f) — ~1400-token self-improving seed prompt; origin of "promote after 2 behavior changes"
- [UniM0cha/claude-self-improving-skills](https://github.com/UniM0cha/claude-self-improving-skills) — Hermes-style closed learning loop
- [TerenceBristol/claude-improve](https://github.com/TerenceBristol/claude-improve) — retrospective-per-conversation skill

## Claims deliberately marked uncertain

Recorded so they get re-verified rather than calcifying:

- **`apply.py`'s shrink thresholds have no upstream source.** *Added 2026-08-11 (D-14).* "Refuse when an
  existing file of ≥10 non-blank lines would keep less than half of them" is calibration derived from one
  field incident — `sharpshooter` lost an 80-line `CLAUDE.md` to a 2-line fragment — not from any
  published guidance. The ratio is a guess chosen to catch that shape of failure while leaving a genuine
  rewrite alone. **Falsifier:** a real proposal that legitimately trims a file by more than half gets
  refused, or a fragment small enough to slip under the ratio destroys a file anyway. Either means
  re-tune the numbers, and the unconditional backup under `.state/backups/` is what makes both survivable.

- ~~**`/init` invocability.**~~ **Resolved 2026-07-26** (was: "do not assert either way").
  [Skills](https://code.claude.com/docs/en/skills) states it directly: "A few built-in commands are also
  available through the Skill tool, including `/init`, `/review`, and `/security-review`. Other built-in
  commands such as `/compact` are not." `/doctor` is a bundled skill as of v2.1.205. So both hand-offs are
  invocable. bonsai keeps the fallback path anyway — it costs one branch and covers older builds — but the
  docs no longer disagree, and `reference/` should stop hedging as though they do. Empirical confirmation on
  a live session is still V-04/V-05.
- **`prompt` and `agent` hook types** are documented experimental. bonsai does not depend on them; the
  retrospective runs as a `command` hook shelling out to a headless process instead.
- **Agent teams** are experimental and disabled by default. Out of scope for v1.
- **The `Skill` tool's `tool_input` schema.** *Checked 2026-07-26.* The hooks reference enumerates
  `tool_input` fields for `Bash`, `Write`, `Edit`, `Read`, `Glob`, `Grep`, `WebFetch`, `WebSearch`,
  `Agent`, `AskUserQuestion`, and `ExitPlanMode` — but not `Skill`. `touch_artifact.sh` reads
  `tool_input.skill` because that is the field the runtime presents, not because a doc says so, and it
  requires the resolved path to exist under `.claude/skills/` before logging anything. If the field is
  renamed upstream, skill tracking silently stops rather than recording the wrong artifact. Re-verify
  when the tool-input tables gain a `Skill` entry.
- **The transcript JSONL record shape.** [Hooks](https://code.claude.com/docs/en/hooks) specifies that a
  hook payload carries `transcript_path`, but not what is inside the file. The flow-state guards in
  `etiquette.md` rule 5 read `type`, `timestamp`, `isSidechain`, `isMeta`, `tool_use`/`tool_result`
  blocks and `Edit`/`Write` `file_path` inputs — all *observed* in v2.1.220 transcripts, not specified
  anywhere. Treat every field as optional: each guard fails open (runs the retrospective) when it
  cannot compute its signal, so a format change costs suppression accuracy and nothing else.
