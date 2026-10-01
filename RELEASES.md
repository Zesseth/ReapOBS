# Release Strategy

This document describes how ReapOBS versions are numbered and how releases
are published. It is intentionally simple: this is a small, single-maintainer
project.

## Versioning

Version numbers follow `vMAJOR.MINOR.PATCH` (semantic versioning, currently
MAJOR = 1):

| Segment | Bumped when | Example |
|---------|-------------|---------|
| PATCH    | The release contains only bug fixes | `v1.0.1` |
| MINOR    | The release adds at least one new feature; PATCH resets to 0 | `v1.1.0` |
| MAJOR    | Breaking changes or a major rework — no schedule, decided case by case by the maintainer | `v2.0.0` |

The version number counts **releases, not individual changes**: a segment
bumps by exactly one per published release, no matter how many fixes or
features the release contains. Unrelated fixes shipped together in one
release (e.g. two bug fixes) still result in a single PATCH bump — the
individual changes are listed in the release notes instead. Gaps in the
numbering never occur; `v1.0.2` simply means "the second bug-fix release
after `v1.0.0`", not "the second fix".

## Process

- `main` is the only development branch and the only source of releases.
  All fixes and features are merged into `main` first; nothing is released
  from feature branches.
- **Releases are cut manually by the maintainer.** There is no automatic
  release cadence: a version is published when the maintainer decides it is
  time for one.
- GitHub **milestones** are used to group the issues and PRs planned for the
  next release. When a release is published, its milestone (if any) is
  closed at the same time.
- Releases are tagged from `main` only — no long-lived release branches.

## Cutting a release

1. Make sure `main` is up to date and the regression tests pass:
   ```bash
   lua5.3 tests/test_bug_regressions.lua
   ```
2. Create an annotated tag on `main` and push it:
   ```bash
   git tag -a vX.Y.Z -m "Version vX.Y.Z: short summary"
   git push origin vX.Y.Z
   ```
3. Publish a GitHub Release for the tag with release notes (web UI or
   `gh release create vX.Y.Z --title "..." --notes "..."`):
   - **Fixed:** closed bug issues, e.g. `Fixed #10 — REC STOP marker position`
   - **Added:** new features and documentation
   - Mention whether the release was live-tested with OBS + REAPER.

## Release history

| Version | Date       | Content |
|---------|------------|---------|
| `v1.0.0` | 2026-06-28 | First stable release (core scripts and installer) |
| `v1.0.1` | 2026-10-01 | Bug fixes: REC STOP marker position (#10), corrupted UTF-8 characters (#11); added regression tests and TESTING.md |
