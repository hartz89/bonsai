# bonsai

**Harness engineering, without the engineering.**

bonsai watches how you actually work, then proposes the agent configuration your project is missing —
the right instruction in the right file at the right scope. And unlike every other tool in this space,
it takes things back out when they stop earning their keep.

It costs **162 tokens** of resident context — about 6% of a `CLAUDE.md` at the documented 200-line limit.
That number is measured by `scripts/footprint.py` against bonsai's own install, not estimated, and
`tests/run.sh` fails if it grows past its ceiling.

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

## No vendor lock-in

Adopting a self-improving harness means betting on a tool ecosystem. bonsai is built so that bet is cheap to
reverse.

Artifacts are authored as a **canonical, tool-agnostic body** plus a **thin per-harness wrapper** carrying
that tool's frontmatter:

```
.harness/rules/testing.md     ← the canonical body. Edit this one.
.claude/rules/testing.md      ← thin wrapper: `paths:` frontmatter
.cursor/rules/testing.mdc     ← thin wrapper: `globs:` frontmatter
AGENTS.md                     ← for tools with no scoping mechanism
```

You edit one file; every harness sees it. Adding a tool means adding a wrapper, not migrating. A parity lint
fails the build if a wrapper ever drifts from its canonical body.

Being straight about the current state: **the wrapper generation is designed, not shipped** — see
[`docs/roadmap.md`](docs/roadmap.md) Phase 2. Today bonsai writes Claude Code artifacts and knows how to
bridge to `AGENTS.md`. Some mechanisms may have no equivalent outside Claude Code at all (enforcement hooks,
model down-leveling), which would make bonsai *better* on Claude Code and merely *useful* elsewhere. That gets
documented rather than discovered.

## It eats its own dog food

bonsai is installed on bonsai. The hooks run on this repository, its tier and mode were auto-detected, and
this project's own instructions use the wrapper pattern — `AGENTS.md` canonical, `CLAUDE.md` a thin import.

It's already paid off: the resident-cost figure above was a *projected* 126 tokens until the dogfood install
measured 162. The estimate was wrong, so the estimate got corrected.

It's also a safety demonstration. `apply.py`'s allowlist permits only harness-config paths, so bonsai **cannot
modify its own `reference/`, `scripts/`, or `skills/`** — the same mechanism that stops it touching your source
code stops it touching its own.

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

bonsai also registers an `InstructionsLoaded` hook that records which instruction artifacts actually load, so
pruning is based on real usage rather than age. That event has no output control, so it cannot interrupt
anything.

Plus `/bonsai:pause` (and `--resume`) to stop observation for a repo in one step.

## How this differs from prior art

There's real work in this space and bonsai overlaps a lot of it. The honest differences, **swept 2026-07-26**
— every claim below is registered in [`docs/claims.md`](./docs/claims.md) with a date, an expiry, and what
would falsify it, because this landscape moves fast enough that a table more than a quarter old is probably
wrong. Two claims that used to be in this section died in that sweep; they're recorded there as retracted
rather than quietly deleted.

**Learning from sessions:**

| Project | What it does | What bonsai adds |
| :--- | :--- | :--- |
| [netresearch/retro-skill](https://github.com/netresearch/retro-skill) | The closest comparable. Reads a session transcript for friction and routes each finding to one of six destinations with per-proposal approval; ships eval fixtures and tombstoned provenance | Evals as a *gate* rather than a suggestion, a measured resident budget, and routing to the harness's own token-saving mechanisms — `paths:` scoping, permissions, cheaper-model subagents |
| [Kulaxyz/self-learning-skills](https://github.com/Kulaxyz/self-learning-skills) | Harvests a verified "golden path" from a session into a skill or rule, with promotion gates and `AGENTS.md` adapters | A removal path. Nothing there tracks an artifact after it's written |
| [claude-reflect](https://github.com/jeremylongshore/claude-code-plugins-plus-skills) | Detects in-session corrections and queues them into `CLAUDE.md` | An approval gate, a placement decision, and an expiry on unconfirmed evidence. Its own docs note that once applied, "entries are permanent" |
| [anthropics/claude-md-management](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/claude-md-management) | Official plugin. Scores `CLAUDE.md` against quality criteria and captures session learnings via `/revise-claude-md` | Measurement and routing — it improves the file you have rather than deciding which of seven mechanisms a pattern belongs in |
| [obra/superpowers](https://github.com/obra/superpowers) | Large curated skill library | Generates artifacts from *your* project rather than shipping a library |

**Measuring and pruning context:**

| Project | What it does | What bonsai adds |
| :--- | :--- | :--- |
| [aneym/skill-stats](https://github.com/aneym/skill-stats) | Records every skill activation through a `PostToolUse` hook into a local database and reports dormant skills. **Falsified our load-tracking claim as originally worded** | Coverage of rules (`InstructionsLoaded`) and subagents (`SubagentStart`), not skills alone — and a promotion side, so usage can settle the record of what proposed the artifact |
| [YawLabs/ctxlint](https://github.com/YawLabs/ctxlint) | Static linter for agent context files; 34 checks including always-loaded-vs-conditional token accounting, `--strict` fails CI | Runtime usage data. Its staleness check is static file analysis; bonsai's is a load record |
| [cuttlesoft/token-guard](https://cuttlesoft.com/blog/2026/02/10/token-guard-keeping-your-agent-context-lean-in-ci/) | GitHub Action that fails the build when instruction files exceed a token threshold | Nothing on enforcement — this does it well. bonsai's distinction is holding *itself* to the contract, publishing its own measured resident cost |
| [egorfedorov/claude-context-optimizer](https://github.com/egorfedorov/claude-context-optimizer) | Tracks per-session token spend and learns cross-session file-affinity patterns; flags `CLAUDE.md` bloat by size | Load evidence about *config artifacts* rather than file reads, and a build gate rather than advice |
| [alirezarezvani/ClaudeForge](https://github.com/alirezarezvani/claudeforge) | Maintains `CLAUDE.md`; a 150-line cap enforced at load time, plus drift audits | Its `InstructionsLoaded` hook is a stateless line-cap validator — the load event triggers a size check and is then discarded. bonsai accumulates it |
| `/doctor` (built in) | Trims `CLAUDE.md`, flags unused skills, MCP servers, and slow hooks | Nothing — `/bonsai:init` calls it rather than reimplementing it |

**What's actually unoccupied, as of the last sweep:** load evidence across *all three* artifact classes,
joined to the record of what proposed them. Others audit config by reading it, which yields an opinion.
skill-stats records real skill activations — but only for skills. Nothing records rule loads or subagent
spawns, and nothing joins usage back to provenance, so nothing else can ask the question bonsai exists to
ask: **did the rule I added six weeks ago ever load?** A harness that can't distinguish live config from dead
config only grows. It's the reason this is called bonsai.

## What would make this project stop

Stated in the README rather than buried, because a tool that can't name its own failure conditions will
rationalize instead. From [`docs/roadmap.md`](docs/roadmap.md):

- **If fewer than ~40% of proposals get accepted** after tuning, the classification isn't good enough and
  bonsai is noise with extra steps.
- **If Anthropic ships native promotion and pruning** — and the Agent Skills post explicitly anticipates
  agents that "create, edit, and evaluate Skills on their own" — the right move is to fold this reference
  corpus into whatever they ship and archive the plugin, not compete with it.
- **If the retrospective needs a frontier model** rather than Haiku, the cost story collapses and bonsai
  should become manual-only.

Also worth knowing: **bonsai has not yet run for a sustained period on anyone else's project.** The scripts
are covered by 53 assertions and the guidance is cited, but Phase 0 of the roadmap is validation for exactly
this reason. Early adopters are early adopters.

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
| [`adapters/claude-code.md`](adapters/claude-code.md) | Exact paths and frontmatter per Claude Code mechanism |
| [`adapters/agents-md.md`](adapters/agents-md.md) | The portable subset, and the three gaps it can't cover |
| [`docs/roadmap.md`](docs/roadmap.md) | Phases, exit criteria, and kill conditions |

## Turning it off

```bash
/bonsai:pause              # stop observing this repo
/plugin uninstall bonsai   # remove entirely
```

Artifacts bonsai created are plain files you own and keep. Only its own state directory goes away.

## Installing on a team

For yourself, `/plugin marketplace add hartz89/bonsai` then `/plugin install bonsai` is enough. For a work
repo where teammates should get it automatically, commit this to `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "bonsai": { "source": { "source": "github", "repo": "hartz89/bonsai" } }
  },
  "enabledPlugins": ["bonsai@bonsai"]
}
```

Teammates are prompted to install when they trust the project folder — nobody has to run
`/plugin marketplace add` by hand. Install scopes: `user` (`~/.claude/settings.json`, personal), `project`
(committed, team-wide), `local` (gitignored), `managed` (org policy).

### How updates reach you

bonsai sets an explicit `version` in `plugin.json`, so **you only receive changes when a release bumps it**.
Commits landing on `main` don't reach installed users. That's intentional while the project is pre-validation —
`main` moves faster than anything you should be running.

- `/plugin update bonsai` — pull the latest release
- `/plugin marketplace update` — refresh the catalog itself
- Background auto-updates check the resolved version and skip when it matches what you have
- `CHANGELOG.md` records what's in each release and what's still unreleased on `main`

To pin harder, the marketplace source accepts a `ref` (branch or tag, though not a bare SHA), so you can track
a tag instead of the default branch.

For enterprise environments, `strictKnownMarketplaces` in managed settings restricts which marketplaces anyone
can add; pair it with `extraKnownMarketplaces` to register approved ones automatically. Stable-vs-early-access
rollout is done by pointing user groups at different marketplaces via managed settings.

One caveat if you ever fork this privately: background auto-updates disable git credential helpers, so private
marketplaces over HTTPS can fail intermittently. SSH remotes are unaffected.

## Requirements

Claude Code v2.1.196+, `python3`, `git`. `gh` optional (improves workflow detection). No runtime
dependencies.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `sh tests/run.sh` — 53 assertions, no dependencies. If you change
behavior described in `reference/`, update the doc and its citation in the same PR.

MIT licensed.
