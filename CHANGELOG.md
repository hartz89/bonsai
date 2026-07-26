# Changelog

bonsai pins an explicit `version` in `.claude-plugin/plugin.json`, which means **consumers receive changes only
when that version is bumped** — pushing commits to `main` alone does nothing for installed users. That's
deliberate while the project is pre-validation: `main` moves faster than anything anyone should be running.

Versions follow [semver](https://semver.org). Every release bumps `plugin.json` and adds an entry here.

## [Unreleased]

Changes on `main` that installed users do **not** yet have.

### Added
- `InstructionsLoaded` hook (`scripts/touch_artifact.sh`) recording which instruction artifacts actually load,
  so `/bonsai:prune` measures staleness from real usage rather than age
- `scripts/backlog_check.py` — fails the suite when `docs/backlog.md` disagrees with git history
- `docs/roadmap.md` and `docs/backlog.md`
- `AGENTS.md` as the canonical instruction set, with `CLAUDE.md` as a thin wrapper
- `/bonsai:pause` (and `--resume`)
- Kill criteria in the README

### Fixed
- Confidence floor made any pattern that exactly met its threshold unpromotable
- Stale day-counter cleanup deleted the counter it had just written
- A crossed observation re-emitted indefinitely when the drafting pass failed
- False-positive conflict findings between disjoint monorepo rule scopes

### Changed
- Resident cost corrected from a projected 126 tokens to a measured 162

## [0.1.0] — 2026-07-26

Initial release. Not yet validated on real projects; see the roadmap's Phase 0.

- The observe → propose → review → prune loop
- Five commands: `init`, `review`, `promote`, `prune`, `pause`
- `reference/` design corpus, every normative claim cited
- 55 assertions, no runtime dependencies beyond `sh`, `git`, `python3`

---

## Release checklist

1. `sh tests/run.sh` — all green, including the backlog check
2. Move `[Unreleased]` entries into a new version section
3. Bump `version` in `.claude-plugin/plugin.json` — **without this, nobody gets the release**
4. Tag: `git tag -a v0.2.0 -m "..." && git push --tags`
5. Verify: `claude plugin update bonsai` on a test install actually pulls it
