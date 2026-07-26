@AGENTS.md

## Claude Code

- Use plan mode for changes to `reference/` or `scripts/`. `reference/` is the specification and `scripts/`
  enforce it, so both deserve a design pass before edits.

## Harness maintenance

This repo self-maintains its agent config. When you notice a repeated correction, a workflow explained 3+
times, or a context-heavy task a cheaper model could handle, run `/bonsai:promote`.
Inventory and provenance: `.claude/bonsai/`
