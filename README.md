# bonsai

**Harness engineering, without the engineering.**

bonsai watches how you actually work, then proposes the agent configuration your project is missing —
the right instruction in the right file at the right scope. And unlike every other tool in this space,
it takes things back out when they stop earning their keep.

It costs about **126 tokens** of resident context — roughly 5% of a `CLAUDE.md` at the documented
200-line limit. That number is measured by `scripts/footprint.py`, and `tests/run.sh` fails if it grows
past its ceiling.

```bash
/plugin marketplace add hartz89/bonsai
/plugin install bonsai
/bonsai:init
```

---

## The problem

Claude Code gives you seven ways to steer it: `CLAUDE.md`, path-scoped rules, skills, subagents, hooks,
permissions, output styles. Each has different loading behavior, different context cost, and different
enforcement guarantees. Choosing correctly is genuinely hard, so most projects end up with one of two
outcomes:

- **A bare `CLAUDE.md`**, and Claude re-learns your conventions every session.
- **A 400-line `CLAUDE.md`**, loaded into every request forever, where adherence quietly degrades
  because every token spends a finite attention budget.

The fix isn't more discipline. It's a tool that notices the pattern, knows which of the seven mechanisms
fits, and — critically — prunes what's gone stale.

## How it works

```
  you work normally
        │
        ▼
  SessionEnd ──▶ Haiku reads the transcript in a separate process   ← 0 tokens in your context
        │        and notes what you had to correct
        ▼
  observations.jsonl ──▶ thresholds evaluated in code, not by a model
        │
        ▼  (only when a pattern actually earns it)
  a proposal is drafted
        │
        ▼
  SessionStart ──▶ "2 bonsai proposals pending — /bonsai:review"    ← one line, once
        │
        ▼
  you approve the diff ──▶ artifact written, provenance + eval case recorded, committed
        │
        ▼
  /bonsai:prune ──▶ stale, unused, and contradictory artifacts come back out
```

The observation pass runs **after your session ends, in a different process.** It cannot slow you down,
interrupt you, or consume your context window.

## What it decides for you

Given a pattern, bonsai routes it to the mechanism that actually fits:

| What it sees | What it builds | Resident cost |
| :--- | :--- | ---: |
| "use pnpm, not npm" (3rd time) | One line in `CLAUDE.md` | ~10 tokens |
| Test-style feedback while editing `*.test.ts` | A rule scoped to `paths: ["**/*.test.ts"]` | **0** |
| Claude touched `.env` and you flinched | A `PreToolUse` hook that blocks it | **0** |
| Release steps pasted a third time | A skill you invoke with `/release` | **0** |
| PR triage burning 40 files of context daily | A Haiku subagent, read-only, turn-bounded | **0** |
| Your personal commit-message taste | `CLAUDE.local.md` — never your team's problem | — |

Two distinctions it takes seriously:

**Enforcement vs hope.** "Never edit `.env`" is mechanically checkable, so it becomes a hook. "Avoid
hasty abstractions" is a judgment call, so it becomes a rule that says out loud that it's advisory.
Anthropic's guidance is blunt about this: *"Model judgments aren't reliable guardrails."* bonsai won't
sell you a wish as a guarantee.

**Scoped vs global.** If guidance correlates with a directory or file type, it gets `paths:` frontmatter
and costs nothing until Claude touches a matching file. An unscoped rule in a shared repo loads for every
engineer on every file and dilutes adherence to everything else.

## It won't get in your way

The design target was *polite but proactive*. Concretely:

- **Zero mid-session interruptions.** bonsai speaks at session boundaries only. No `Stop` hook, no
  `PostToolUse` output, and **no blocking hook anywhere in its own machinery** — it structurally cannot
  halt your work.
- **It skips you when you're in flow.** Sessions under 8 turns, tight edit loops, sessions ending in
  failing tests, and mid-rebase/merge/bisect states are skipped — decided in shell, before any model
  spawns, so a skipped session costs exactly nothing.
- **Silence when idle.** Nothing pending means no output. Not "nothing to report" — nothing.
- **It backs off when ignored.** Proposals get quieter, then auto-archive after 7 sessions. Silence is
  treated as an answer. It never escalates.
- **One line, once.** Never repeated within a session, never the proposal content.
- **Bounded cost.** Haiku, `effort: low`, capped turns, 1 run/hour, 6/day by default, and
  `retrospective: false` makes it fully manual.

## It doesn't reinvent what Claude Code already does

bonsai drives the native tooling instead of duplicating it — you likely haven't run these, and that's
the point:

- No `CLAUDE.md`? It hands off to **`/init`**. It won't author your first one.
- `CLAUDE.md` too long, or full of stuff Claude could just read? It invokes **`/doctor`**, which already
  proposes trims and finds unused skills, MCP servers, and slow hooks.
- Auto memory off? It points you at **`/memory`**, because the whole loop depends on it.

bonsai only builds the part that doesn't exist: the promote-and-prune ratchet, mechanism selection,
provenance, and eval capture.

## Safety

An agent with write access to its own always-on instructions is a real risk — poison `CLAUDE.md` once and
it's in every future session. So:

- **Nothing enters always-on context without your approval.** The proposal queue is the whole mitigation.
- **`apply.py` enforces a target-path allowlist in code.** Path traversal, absolute paths, and
  `.github/workflows/` targets are rejected — not discouraged in a prompt, *rejected*.
- **Instruction-like text found in files, dependencies, or fetched pages is never treated as a
  directive.** It's flagged `untrusted_source` and can't promote on its own.
- **Secrets are redacted mechanically** before anything is written to disk.
- **Your conversation excerpts stay machine-local and gitignored.** Only artifacts, inventory, and eval
  cases are committed.

## Git hygiene

bonsai matches your project's workflow rather than assuming one:

| Detected | Behavior |
| :--- | :--- |
| **solo** — 1 contributor, no branch protection | Commits directly to your current branch |
| **team** — PR history or 2–14 contributors | Branches as `bonsai/<slug>`; offers a PR |
| **enterprise** — branch protection or `CODEOWNERS` | Branches in a **worktree** so harness work never tangles with in-flight features |

Always: explicit pathspecs (never `git add -A`), one commit per review session, no history rewriting,
no `--no-verify`, and never a push or PR without asking.

## Commands

| Command | Does |
| :--- | :--- |
| `/bonsai:init` | Survey, delegate to `/init` and `/doctor`, detect tier and mode, propose what's missing. Re-runnable |
| `/bonsai:review` | Show pending proposals as diffs with evidence and cost; apply what you approve |
| `/bonsai:promote` | Codify a pattern now, without waiting for a threshold |
| `/bonsai:prune` | Audit and remove what no longer earns its keep; report the footprint ledger |

Plus `/bonsai:pause` (and `--resume`) to stop observation for a repo in one step.

## How this differs from prior art

There's real work in this space and bonsai overlaps some of it. The honest differences:

| Project | What it does | What bonsai adds |
| :--- | :--- | :--- |
| [obra/superpowers](https://github.com/obra/superpowers) | Large curated skill library | Generates artifacts from *your* project rather than shipping a library |
| [affaan-m/ECC](https://github.com/affaan-m/ECC) | Harness optimization: skills, instincts, memory | A measured context budget and a removal path |
| [ChristopherA's bootstrap seed](https://gist.github.com/ChristopherA/fd2985551e765a86f4fbb24080263a2f) | Self-improving seed prompt in `CLAUDE.md` | Versioned and upgradeable — policy lives in a plugin, not splatted into your file |
| [UniM0cha/claude-self-improving-skills](https://github.com/UniM0cha/claude-self-improving-skills) | Hermes-style learning loop | Mechanism *selection* across all seven primitives, not just skills |
| [TerenceBristol/claude-improve](https://github.com/TerenceBristol/claude-improve) | Per-conversation retrospective | Detached and rate-limited, so it costs nothing in your session |

**The one nobody else does: garbage collection.** Every project above is additive-only. A harness that
only grows is a harness that gets worse at month six, because resident context is a shared attention
budget. `/bonsai:prune` is the reason this is called bonsai.

## Design docs

The reasoning is checked in, and every normative claim is cited:

| Doc | Covers |
| :--- | :--- |
| [`reference/placement.md`](reference/placement.md) | Which artifact, at which scope — the seven-mechanism decision procedure |
| [`reference/thresholds.md`](reference/thresholds.md) | What earns promotion; evidence, counting, confidence |
| [`reference/etiquette.md`](reference/etiquette.md) | The seven rules for not being annoying |
| [`reference/budget.md`](reference/budget.md) | The cost contract, in numbers |
| [`reference/git-strategy.md`](reference/git-strategy.md) | Workflow detection and commit hygiene |
| [`reference/determinism.md`](reference/determinism.md) | What's scripted vs left to the model, and why |
| [`reference/sources.md`](reference/sources.md) | Every claim → canonical source |

## Turning it off

```bash
/bonsai:pause              # stop observing this repo
/plugin uninstall bonsai   # remove entirely
```

Artifacts bonsai created are plain files you own and keep. Only its own state directory goes away.

## Requirements

Claude Code v2.1.196+, `python3`, `git`. `gh` optional (improves workflow detection). No runtime
dependencies.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `sh tests/run.sh` — 46 assertions, no dependencies. If you change
behavior described in `reference/`, update the doc and its citation in the same PR.

MIT licensed.
