# Sources

Every normative claim in `reference/` traces to one of these. When guidance here conflicts with a
source, the source wins — open an issue.

Verified 2026-07-25 against Claude Code v2.1.2xx docs.

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
| [Skills](https://code.claude.com/docs/en/skills) | Frontmatter schema; `disable-model-invocation`; `context: fork` + `agent`; skill locations and precedence; description truncated at 1,536 chars |
| [Subagents](https://code.claude.com/docs/en/sub-agents) | Frontmatter schema including `model`, `tools`, `maxTurns`, `effort`, `memory`, `skills`; what loads at startup |
| [Hooks](https://code.claude.com/docs/en/hooks) | Event list; hook types (`command`, `http`, `mcp_tool`, `prompt`, `agent`); per-event output control |
| [Plugins reference](https://code.claude.com/docs/en/plugins-reference) | Plugin layout; `plugin.json` schema; `userConfig`; `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}`; `pluginConfigs` read only from user/managed settings |
| [Commands](https://code.claude.com/docs/en/commands) | Which `/`-entries are built-in commands vs bundled skills — determines what bonsai can invoke |

## Portability

| Source | What it establishes |
| :--- | :--- |
| [AGENTS.md](https://agents.md) | The cross-tool instruction convention; stewarded by the Agentic AI Foundation under the Linux Foundation since 2025-12-09 |
| [How Claude remembers your project § AGENTS.md](https://code.claude.com/docs/en/memory#agents-md) | Claude Code does **not** read `AGENTS.md`; the canonical bridge is a `CLAUDE.md` containing `@AGENTS.md` |

## Prior art

Read before contributing; bonsai deliberately overlaps some of these and deliberately diverges from
all of them on garbage collection. See the README's positioning section.

- [obra/superpowers](https://github.com/obra/superpowers) — large curated skill library, incl. skill-authoring guidance
- [affaan-m/ECC](https://github.com/affaan-m/ECC) — harness optimization: skills, instincts, memory, security
- [ChristopherA's bootstrap seed](https://gist.github.com/ChristopherA/fd2985551e765a86f4fbb24080263a2f) — ~1400-token self-improving seed prompt; origin of "promote after 2 behavior changes"
- [UniM0cha/claude-self-improving-skills](https://github.com/UniM0cha/claude-self-improving-skills) — Hermes-style closed learning loop
- [TerenceBristol/claude-improve](https://github.com/TerenceBristol/claude-improve) — retrospective-per-conversation skill

## Claims deliberately marked uncertain

Recorded so they get re-verified rather than calcifying:

- **`/init` invocability.** [Commands](https://code.claude.com/docs/en/commands) documents `/init` as a
  built-in command (not model-invocable), but some builds expose an `init` *skill* in the model's skill
  list. bonsai attempts invocation and falls back to instructing the user. Do not assert either way.
- **`prompt` and `agent` hook types** are documented experimental. bonsai does not depend on them; the
  retrospective runs as a `command` hook shelling out to a headless process instead.
- **Agent teams** are experimental and disabled by default. Out of scope for v1.
