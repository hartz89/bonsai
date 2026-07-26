# Adapter: Claude Code

Renders an artifact plan to Claude Code primitives. This is the default and the most capable target — all
seven mechanisms are available.

`placement.md` decides *which* mechanism. This document is the mechanical detail of writing each one
correctly: exact paths, exact frontmatter, and the mistakes that make an artifact silently inert.

## Targets

| Mechanism | Path | Loads |
| :--- | :--- | :--- |
| Fact / global rule | `CLAUDE.md` | Every session, in full. Hard cap 200 lines |
| Scoped guidance | `.claude/rules/<topic>.md` with `paths:` | Only when Claude touches a matching file |
| Unscoped rule | `.claude/rules/<topic>.md` | Every session — same priority as `.claude/CLAUDE.md` |
| Directory guidance | `<dir>/CLAUDE.md` | On demand, when Claude reads files in that directory |
| Procedure / reference | `.claude/skills/<name>/SKILL.md` | Description at start; body when invoked |
| Isolated task | `.claude/agents/<name>.md` | Metadata at start; runs in its own window |
| Enforcement | `.claude/settings.json` → `hooks.PreToolUse` or `permissions.deny` | Fires deterministically; zero context |
| Personal | `CLAUDE.local.md` or `~/.claude/rules/` | Gitignored / user-global |

## Frontmatter that must be right

**Path-scoped rule** — the highest-value artifact bonsai produces:

```markdown
---
paths:
  - "src/**/*.{ts,tsx}"
  - "tests/**/*.test.ts"
---

# Topic

- Concrete, verifiable instruction.
```

Omitting `paths:` silently converts this into an always-resident rule — the single most common way to
accidentally bloat a shared repo. Brace groups multiply: a rule's whole `paths:` list shares a budget of
1,000 expanded patterns. Escape a literal `[` as `\[`, or the pattern matches nothing.

**Skill:**

```markdown
---
name: release
description: <what it does and when to use it — key use case first>
disable-model-invocation: true   # for anything with side effects
allowed-tools: Read, Bash(git *)
---
```

`description` is resident, and combined description text is truncated at 1,536 characters in the listing.
A vague description is worse than none: it misfires and loads the wrong skill.

**Down-leveled subagent** — where bonsai usually pays for itself:

```markdown
---
name: pr-triage
description: <when Claude should delegate to this>
model: haiku
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit
maxTurns: 12
effort: low
---
```

Always set `maxTurns` — an unbounded subagent is an unbounded bill. Narrow `tools` to the minimum; omit
write tools for read-only work.

**Enforcement hook:**

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Edit|Write",
        "hooks": [{ "type": "command", "command": "...", "timeout": 5 }] }
    ]
  }
}
```

Exit code 2 blocks the call. Always merge into existing hook arrays — `scripts/apply.py` does this; never
hand-write `settings.json`, or you will clobber the user's config.

## Rules for this adapter

1. **Merge, never replace.** `settings.json`, `.gitignore`, and `CLAUDE.md` all commonly have existing
   content. `apply.py` handles the merge; use it.
2. **Nested over root in monorepos.** Multiple package manifests means guidance belongs in the owning
   package's `.claude/`, not the repo root, so other teams don't pay for it.
3. **One topic per rule file.** `.claude/rules/testing.md`, not `.claude/rules/misc.md`. Rules are
   discovered recursively, so subdirectories are fine.
4. **Reference files one level below `SKILL.md`.** Deeper nesting means Claude won't reliably find them.
   Add a table of contents to any reference file over 100 lines.
5. **`@`-imports don't save context.** Imported files load in full at launch. Use them for organization;
   use `paths:` for actual savings.
6. **Never write an output style.** It replaces the default system prompt's instructions on scope,
   comments, security, and verification. Requires an explicit human decision, never a proposal.

## Verification after writing

- `/context` — confirm the artifact loaded, and that resident cost moved as predicted
- `/memory` — confirm which instruction files are actually in play
- `/doctor` — confirm nothing became unused or slow
- For a path-scoped rule, touch a matching file and confirm the rule appears; scoping bugs are invisible
  otherwise
