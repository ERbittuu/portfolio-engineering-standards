# Changelog

## [1.1.0] - 2026-07-07

Releases move from tag-driven to branch-driven, and a PR-check layer gets
added — both learned the hard way on a real release, not designed upfront.

### Added
- `release/X.Y.Z` branches replace direct tag pushes for shipping (PLAYBOOK
  §5). Xcode Cloud archives straight from the branch, any number of times;
  a tag gets created exactly once, on merge, as a pure record that
  triggers nothing. `templates/ci_scripts/lib/asc_build_number.rb` reads
  the version from the branch name and asks App Store Connect for the
  right build number live.
- PR-check layer (PLAYBOOK §4): `lint.yml`, `validate-metadata.yml`,
  `validate-screenshots.yml`, `validate-release.yml`, `pr-guards.yml`
  (secret scan, dependency drift guard, optional app-specific sanity
  checks). All trigger on every PR and skip their own work when nothing
  relevant changed, so they always report a status — a path-filtered
  *trigger* silently never runs at all for unrelated PRs, which is worse
  than no check.
- `deploy-data.yml` smoke-tests the live manifest and a sample bundle
  right after every Firebase Hosting deploy.
- Documented, in MIGRATE.md's gotcha table: Xcode Cloud's own
  auto-incrementing build-number counter can't be disabled and overrides
  anything a script sets; GitHub Free doesn't support branch protection on
  private repos; `dorny/paths-filter` needs `pull-requests: read`;
  gitleaks scans a PR's commits individually, not as one diff, which
  produces false alarms on repos that squash-merge.

### Changed
- `release-tag.yml` replaced by `release-merge.yml` (fires on release
  branch merge, not tag push).
- Per-app `docs/decisions/` dropped from the repo layout (PLAYBOOK §1) —
  decisions belong here, where they help the next app too.

## [1.0.0] - 2026-07-05

First release. Playbook, migration guide with gotcha table, decision
guides, and the full template set (workflows, ci_scripts, fastlane,
dotfiles) — all taken from the first app running on this system.
