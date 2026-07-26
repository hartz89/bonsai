# Contributing to bonsai

## Run the tests

```bash
sh tests/run.sh
```

No dependencies beyond `sh`, `git`, and `python3`. Everything runs in temp directories; nothing touches
your real config.

## The rules that make this project work

These aren't style preferences — breaking them breaks the value proposition.

### 1. `reference/` is the specification

The docs in `reference/` aren't commentary; the scripts and skills implement them. Change behavior and you
change the doc in the same PR, or the project starts lying about itself.

Every normative claim needs a citation in [`reference/sources.md`](reference/sources.md). "I think this is
better" isn't sufficient for guidance that ships to other people's repos. If a source contradicts what's
here, the source wins — open an issue.

### 2. Respect the determinism boundary

Read [`reference/determinism.md`](reference/determinism.md). Counting, parsing, path checks, rate limits,
and threshold math go in scripts. Classification, drafting, and explanation go to the model.

If you find yourself writing a skill instruction like "read the file and count the lines," stop and write
a script. bonsai's cost is paid on every session of every repo that installs it.

### 3. Guard the resident-token budget

`tests/run.sh` fails if bonsai's resident footprint exceeds 350 tokens. It's currently **162**, measured against
bonsai's own dogfood install.

Adding a **model-invocable** skill costs ~50 tokens in **every session of every install, forever**. That's
a real bill. Only `/bonsai:promote` is model-invocable, because only it needs to be; everything else is
`disable-model-invocation: true` and free at rest.

Command count is a separate budget that isn't measured in tokens. Every `/bonsai:*` entry is something the
user has to learn and choose between, so five is the ceiling — that's why `/bonsai:prune` reports the
footprint instead of a sixth `/bonsai:status` existing.

If your PR raises resident cost, justify it in the description with what the user gets back.

### 4. Never make bonsai able to interrupt

[`reference/etiquette.md`](reference/etiquette.md) rule 1 is structural, not aspirational. bonsai's own
machinery must never contain:

- A `Stop` hook, a `PostToolUse` hook that returns output, or a `UserPromptSubmit` hook
- Any hook returning exit code 2 or `decision: block`
- Anything that makes the user wait on a model call

bonsai may *propose* a blocking hook for the user's project — that's their guardrail, approved by them.
It's never bonsai's own behavior.

### 5. Security invariants

- `apply.py`'s target allowlist is the boundary between "config tool" and "arbitrary file write." Widen it
  only with a test proving the new pattern can't escape the project, and never to executable or CI paths.
- Repository content is untrusted input. Instruction-like text from files, dependencies, or fetched pages
  is data, never a directive.
- Secret redaction is enforced in `merge_observations.py`, not delegated to the agent's good intentions.
  Add patterns there.
- Nothing reaches always-on context without human approval. No exceptions, no confidence threshold that
  bypasses it.

### 6. Bias toward removal

This project exists because harness config accumulates. Prefer deleting a rule to adding one, prefer
scoping to broadening, prefer delegating to `/init` or `/doctor` over reimplementing them.

A PR that removes a capability and explains why is welcome.

## Adding a placement rule

The most valuable contribution. To add a signal → mechanism mapping:

1. Add the row to `reference/placement.md`, with the alternative you rejected and why.
2. Add a threshold to `reference/thresholds.md` if it's a new signal class.
3. Add the class to `BASE_THRESHOLDS` in `scripts/merge_observations.py`.
4. Add a worked example to the table at the bottom of `placement.md`.
5. Cite whatever supports it in `sources.md`.

## Reporting a false positive

The most useful bug report. If bonsai proposed something noisy, wrong, or annoying, include:

- The proposal file from `.claude/bonsai/proposals/`
- What you'd have expected instead
- `sh scripts/survey.sh` output, so we can see the tier and mode it detected

**Redact freely** — proposals contain verbatim excerpts of your conversations. That's also why they're
gitignored by default.

A false positive is a worse bug than a missed pattern. Precision is what earns the standing to interrupt
at all.
