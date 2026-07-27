# Adapter: portable (`AGENTS.md` + `SKILL.md`)

*Sources verified 2026-07-25. A stale stamp is a bug — see `docs/backlog.md` C-01.*

Renders an artifact plan to the cross-tool substrate, for repos where more than one agent tool is in use.

`AGENTS.md` is a community convention stewarded by the Agentic AI Foundation under the Linux Foundation,
read by Codex, Cursor, Copilot, Gemini CLI, Aider, Windsurf, Zed and others. Agent Skills (`SKILL.md`) is
an open cross-vendor spec. Between them they cover roughly half of what Claude Code can express — that
gap is the whole reason this adapter exists as a separate document.

## The critical fact

**Claude Code does not read `AGENTS.md`.** The canonical bridge is a `CLAUDE.md` that imports it:

```markdown
@AGENTS.md

## Claude Code
<Claude-specific additions here>
```

Never duplicate content across both files. Two copies drift, and drifted instructions mean the agent picks
one arbitrarily. `bonsai` writes the import and appends Claude-specific content *below* it.

A symlink (`ln -s AGENTS.md CLAUDE.md`) also works when there's nothing Claude-specific to add, but
requires Administrator or Developer Mode on Windows — prefer the import.

## Mapping

| Artifact plan | Claude Code | Portable rendering |
| :--- | :--- | :--- |
| Fact | `CLAUDE.md` line | `AGENTS.md` line ✅ |
| Procedure | Skill | `SKILL.md` ✅ (name + description frontmatter is the portable subset) |
| Reference | Skill + `reference/` files | `SKILL.md` + bundled files ✅ |
| Global preference | `CLAUDE.md` line | `AGENTS.md` line ✅ |
| **Path-scoped preference** | Rule with `paths:` | ⚠️ **No equivalent in `AGENTS.md`** — it is plain Markdown with no frontmatter. *Not* the same as Claude-only: Cursor has glob-scoped rules in its own `.cursor/rules/` format, so a Cursor-specific wrapper may well carry the scope. Unverified — see `docs/backlog.md` D-13 |
| **Enforced constraint** | `PreToolUse` hook / `permissions.deny` | ⚠️ **No portable equivalent** |
| **Down-leveled task** | Subagent with `model: haiku` | ⚠️ **No portable equivalent** |
| Personal preference | `CLAUDE.local.md` | Tool-specific; keep out of `AGENTS.md` |

## Handling the three gaps

These are the mechanisms that carry most of bonsai's value, and they have no form in `AGENTS.md` itself.
That is a statement about `AGENTS.md`, not about other tools — some have native equivalents in their own
formats, which is the whole point of a per-harness wrapper. Degrade honestly rather than silently:

**Path-scoped rules.** Write the Claude Code rule as the primary artifact. In `AGENTS.md`, add the guidance
with its scope stated in prose:

```markdown
- In `**/*.test.ts`: prefer fewer, longer tests. (Enforced as a path-scoped rule for Claude Code.)
```

The portable version costs resident context in other tools that the Claude Code version doesn't. Say so in
the proposal's blast-radius section — the user is accepting a real cost for portability.

**Enforced constraints.** There is no portable enforcement. Write the hook for Claude Code, and in
`AGENTS.md` state the constraint as prose while explicitly marking it unenforced elsewhere:

```markdown
- Never modify `.env`. (Blocked by a hook in Claude Code; advisory in other tools.)
```

Never imply portable enforcement that doesn't exist.

**Down-leveled subagents.** Cannot be expressed portably at all. Keep it Claude-Code-only and don't
mention it in `AGENTS.md` — a reference to a subagent another tool can't spawn is noise.

## When to use this adapter

Only when the repo shows evidence of another agent tool: `.cursorrules`, `.cursor/rules/`,
`.github/copilot-instructions.md`, `.windsurfrules`, `.clinerules`, `.devin/rules/`, or an existing
`AGENTS.md`. `scripts/survey.sh` reports all of these.

Absent that evidence, render Claude-Code-native and skip the portable layer. Writing `AGENTS.md` into a
repo that has only ever used Claude Code adds a file nobody reads — exactly the kind of speculative
artifact Gate 0 exists to reject.

## Precedence when both exist

`AGENTS.md` holds tool-agnostic content. `CLAUDE.md` holds the `@AGENTS.md` import plus Claude-specific
additions. When a fact belongs in both, it goes in `AGENTS.md` only — the import carries it.

`/bonsai:prune` treats content duplicated across the two as a `conflict` finding, because it is one.
