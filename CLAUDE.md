@AGENTS.md

## Claude Code

This project's canonical instructions live in `AGENTS.md`, imported above. This file adds only what's
specific to Claude Code — the same thin-wrapper pattern bonsai generates for consumers.

- Use plan mode for changes to `reference/` or `scripts/`. `reference/` is the specification and `scripts/`
  enforce it, so both deserve a design pass before edits.
- When editing `reference/`, re-read the cited source in `reference/sources.md` first. Docs move fast, and a
  confidently wrong reference doc is the project's worst failure mode.
- Run `sh tests/run.sh` before any commit. It's fast and has no dependencies.

## Harness maintenance

This repo self-maintains its agent config. When you notice a repeated correction, a workflow explained 3+
times, or a context-heavy task a cheaper model could handle, run `/bonsai:promote`.
Inventory and provenance: `.claude/bonsai/`
