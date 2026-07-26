# Git strategy: match the project's workflow

*Sources verified 2026-07-25. A stale stamp is a bug — see `docs/backlog.md` C-01.*

Harness changes are changes. They belong in version control, held to the same standard as code — and
kept out of the way of feature work. How bonsai commits depends on what kind of project it's in.

- [Detecting the workflow](#detecting-the-workflow)
- [Strategy by workflow](#strategy-by-workflow)
- [Hygiene rules](#hygiene-rules-non-negotiable)
- [What gets committed](#what-gets-committed)
- [Commit messages](#commit-messages)
- [Worktrees](#worktrees)

## Detecting the workflow

Cheap, read-only signals, gathered once at `/bonsai:init` and cached in
`.claude/bonsai/config.json`. Never re-derived per session.

| Signal | Command |
| :--- | :--- |
| Contributor count | `git shortlog -sne --all \| wc -l` |
| Direct-to-main history | ratio of merge commits to total on the default branch |
| PR workflow in use | `gh pr list --state merged --limit 20` |
| Branch protection | `gh api repos/{owner}/{repo}/branches/{main}/protection` (403/404 ⇒ none) |
| Review culture | `CODEOWNERS`, required reviewers in protection, review counts on merged PRs |
| CI | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, etc. |
| Commit convention | do the last ~50 subjects match Conventional Commits, or a ticket prefix? |

Classification, first match wins:

- **enterprise** — branch protection on the default branch, or `CODEOWNERS`, or 15+ contributors
- **team** — a real PR history (most merges arrive via PR) or 2–14 contributors
- **solo** — one contributor, no protection, commits land directly on the default branch

No git repo at all ⇒ treat as `solo`, and don't initialize one. That's the user's call.

## Strategy by workflow

| | solo | team | enterprise |
| :--- | :--- | :--- | :--- |
| Where | current branch (usually `main`) | `bonsai/<slug>` off the default branch | `bonsai/<slug>`, created in a worktree |
| Commit | directly, on accept | on accept, on the branch | on accept, in the worktree |
| Push | only if a remote tracking branch exists and the user has pushed before | ask first | ask first |
| PR | no | offer, don't open unprompted | offer, with `CODEOWNERS` reviewers noted |
| Batching | one commit per `/bonsai:review` session | one branch per review session, all artifacts in it | same |

Escalate one level whenever unsure. Committing to a shared `main` when you should have branched is
much worse than the reverse.

## Hygiene rules (non-negotiable)

1. **Never mix bonsai's changes with the user's.** Commit with explicit pathspecs — only the artifact
   paths bonsai wrote. Never `git add -A`, never `git add .`, never `git commit -a`.
2. **Never commit into a dirty tree in `team`/`enterprise`.** If the user has unstaged or staged work in
   progress, use a [worktree](#worktrees). In `solo`, a pathspec-scoped commit alongside dirty
   unrelated files is acceptable — but say so in the summary.
3. **Never rewrite history.** No `amend`, no `rebase`, no `reset --hard`, no force-push, ever. bonsai
   only adds commits.
4. **Never touch a branch the user is on** beyond the additive commit in `solo` mode. No checkout that
   changes the user's working state without asking. Prefer worktrees over `git checkout`.
5. **Never skip verification.** No `--no-verify`. If a pre-commit hook rejects a bonsai commit, that's
   a real signal — report it, don't bypass it.
6. **Never commit mid-operation.** Bail if `.git/MERGE_HEAD`, `rebase-merge/`, `rebase-apply/`,
   `CHERRY_PICK_HEAD`, or `BISECT_LOG` exists. Matches [etiquette](./etiquette.md) rule 5.
7. **Never push or open a PR without explicit approval.** Both are outward-facing and visible to
   teammates. Prepare locally, then ask.
8. **One commit per review session, not per artifact.** bonsai must not make `git log` noisy.
9. **Respect `.gitignore` and never commit a gitignored path** — including bonsai's own local state.

## What gets committed

The split matters for privacy, not just tidiness. Observation excerpts are verbatim quotes of what the
user said, so they stay machine-local — the same choice Claude Code makes for auto memory.

| Path | Committed | Why |
| :--- | :--- | :--- |
| `CLAUDE.md`, `.claude/rules/`, `.claude/skills/`, `.claude/agents/`, `.claude/settings.json` | ✅ | The artifacts. The whole point |
| `.claude/bonsai/inventory.json` | ✅ | Provenance the team needs to audit and prune |
| `.claude/bonsai/evals/` | ✅ | Eval cases justify the artifacts; teammates should see them |
| `.claude/bonsai/config.json` | ✅ | Team-shared tier and thresholds |
| `.claude/bonsai/observations.jsonl` | ❌ | Verbatim excerpts of the user's conversation. Machine-local |
| `.claude/bonsai/proposals/` | ❌ | Unreviewed drafts, derived from those excerpts |
| `.claude/bonsai/archive/` | ❌ | Declined drafts. Nobody needs them in history |
| `CLAUDE.local.md` | ❌ | Personal by definition |

`/bonsai:init` writes these exclusions to `.gitignore` (appending to an existing `.claude/` section
rather than duplicating one) and reports what it added.

## Commit messages

Match the repo's existing convention — detect it, don't impose one.

Conventional Commits detected:

```
chore(harness): scope testing preferences to test files

Promoted from 4 observations across 4 sessions (2026-07-18 → 2026-07-24).
Adds .claude/rules/testing.md, paths-scoped to **/*.test.ts.
Resident context delta: +0 tokens (loads only on matching files).

bonsai-artifact: rules/testing.md
bonsai-confidence: 0.9
```

No convention detected: same body, plain subject (`Scope testing preferences to test files`).

Rules: state the evidence count and date range, state the resident-token delta, and include the
`bonsai-artifact` trailer so `/bonsai:prune` can find the commit later. Never claim the change was
human-authored, and never add promotional footers.

## Worktrees

In `team`/`enterprise`, or any time the tree is dirty, isolate:

```bash
git worktree add ../.bonsai-worktrees/<slug> -b bonsai/<slug> <default-branch>
```

Branch from the **default branch**, not the user's `HEAD` — harness changes shouldn't inherit in-flight
feature work. Write artifacts there, commit, then report the branch and offer to push. Remove the
worktree once its branch is pushed or the user declines; never leave orphaned worktrees behind.

Subagents that need isolation can use `isolation: worktree` in frontmatter instead of managing this by
hand. Note that a worktree branches from the default branch by default and is auto-removed if the agent
makes no changes.
