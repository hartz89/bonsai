---
name: pause
description: Stop or resume bonsai's observation and surfacing for this repository.
disable-model-invocation: true
argument-hint: "[--resume]"
allowed-tools: Read, Bash(test *), Bash(rm *), Bash(touch *), Bash(date *)
---

# bonsai:pause

One step off, one step on. This is a first-class command rather than a config field because an off-switch
you have to look up isn't an off-switch ([etiquette.md](../../reference/etiquette.md) rule 7).

## Pause (default)

Create `.claude/bonsai/paused` containing the date and, if the user gave one, the reason.

Everything stops immediately: `scripts/retro.sh` exits before spawning any model, and
`scripts/pending.sh` emits nothing. Both check for this file first. Existing proposals and artifacts are
left exactly as they are — pausing is not uninstalling.

Confirm in one line, and say how to undo it:

```
bonsai paused for this repo. /bonsai:pause --resume to turn it back on.
```

## Resume (`--resume`)

Delete the file. Report in one line whether anything is pending:

```
bonsai resumed. 2 proposals still pending — /bonsai:review
```

## Notes

- Already in the requested state? Say so in one line. Don't re-do it, and don't explain yourself.
- This is per-repository. For a global off switch, set `retrospective: false` in the plugin's config via
  `/plugin`, or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` to disable the underlying memory that feeds it.
- Never argue with the decision or pitch the feature. The user asked for quiet; be quiet.
