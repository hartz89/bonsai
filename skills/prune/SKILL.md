---
name: prune
description: Audit this project's agent configuration and remove what no longer earns its keep. Finds stale, unused, contradictory, and misplaced harness artifacts, delegates CLAUDE.md trimming to /doctor, and reports bonsai's own context footprint.
disable-model-invocation: true
argument-hint: "[--apply] [--verbose]"
allowed-tools: Read, Glob, Grep, Bash(python3 *), Bash(git *), Bash(wc *)
---

# bonsai:prune

The half nobody else builds. A harness that only grows gets worse at month six — every resident token
spends a finite attention budget, so removal is as valuable as addition.

Default is report-only. `--apply` proposes removals through the normal review gate; it never deletes
unilaterally.

## Procedure

1. **Delegate first.** Invoke `/doctor`. It already trims derivable content from a checked-in
   `CLAUDE.md`, finds unused skills, MCP servers, and plugins, and flags slow hooks. Everything it
   covers is out of scope here — report what it found and move on.

2. **Scan deterministically.**

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/prune_scan.py --project . --plugin-root ${CLAUDE_PLUGIN_ROOT}
   ```

   Returns findings by category. Do not re-derive any of it by reading files yourself — that's the
   determinism boundary, and the scan is cheaper and exact.

3. **Judge each finding.** The scan finds candidates; you decide. This is the part that needs judgment:

   | Finding | What to weigh |
   | :--- | :--- |
   | `stale` — never exercised since creation | Genuinely dead, or just guarding something rare? A security constraint that never fires is *working*. Never prune enforced constraints on staleness alone |
   | `orphan` — inventory entry with no file, or artifact with no provenance | Orphans are usually safe to reconcile. An artifact with no provenance may be hand-written by a human — leave it, just report it |
   | `unscoped` — a rule with no `paths:` whose content clearly correlates with a path | Propose adding `paths:`. This is a *fix*, not a removal, and it's often the highest-value finding |
   | `conflict` — two artifacts giving contradictory guidance | Must be resolved. Conflicting instructions mean Claude picks arbitrarily. Ask the user which wins |
   | `oversized` — CLAUDE.md over 200 lines after `/doctor` | Propose path-scoped splits for what remains |
   | `redundant` — guidance a linter or formatter now enforces | Safe to remove; the tool is the artifact |
   | `superseded` — an artifact the codebase has moved past | Check git history before claiming this |

4. **Demote rather than delete.** Preferred order: **scope it** (add `paths:`) → **move it** (CLAUDE.md
   to a rule, rule to a skill) → **archive it** (out of context, retained on disk) → delete. Deletion is
   the last resort, and the artifact's eval case in `.claude/bonsai/evals/` is retained either way.

5. **Replay eval cases when it's cheap.** If an artifact has an eval case and you can tell from the
   current codebase that the situation no longer arises, say so — that's the strongest evidence for
   demotion. Do not spawn model runs to replay cases in v1; automated replay isn't built yet, and
   pretending otherwise would be worse than admitting it.

6. **Report the ledger.** Always, even with nothing to prune:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/footprint.py --plugin-root ${CLAUDE_PLUGIN_ROOT} --project . --format line
   ```

   One line for bonsai's own cost, one for the artifacts it maintains, one for what pruning would
   recover. This is the accountability surface for the whole tool — never skip it.

7. **Route removals through review.** With `--apply`, write each removal as a proposal to
   `.claude/bonsai/proposals/` using the standard template, with the removal as the artifact content and
   the scan finding as the evidence. Then tell the user to run `/bonsai:review`. Same gate as additions:
   bonsai does not get to quietly delete a team's configuration.

## Never

- Delete anything without approval, at any confidence.
- Prune an artifact a human wrote by hand without flagging it as human-authored first.
- Prune an enforced constraint (hook or permission) because it hasn't fired. Not firing is success.
- Touch `CLAUDE.local.md` or user-level config — those are personal, and not this repo's business.
- Report zero findings as a problem. A lean harness is the goal; finding nothing means it's working.
