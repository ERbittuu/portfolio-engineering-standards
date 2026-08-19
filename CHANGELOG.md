# Changelog

## [1.3.0] - 2026-08-19

### Changed
- **Ten workflow files consolidated into three**: `pr.yml` (every PR check as
  a separate job), `main.yml` (store metadata, store screenshots, data deploy
  — each path-gated), `release.yml` (tag + GitHub Release). GitHub reports a
  status per job, so the same individual checks stay visible; what goes away
  is nine copies of the same trigger/permissions/concurrency boilerplate and
  ten files to keep in sync per app. `main.yml`'s manual button takes a `job`
  input so the three merge-time jobs can still be run individually, as the
  separate workflows allowed.
- **Xcode Cloud runs one workflow, `Release`.** The CI workflow is gone: it
  compiled pull requests, but its results never appear in `gh pr checks`, so
  it was verification you had to open App Store Connect to read. Compile
  errors now surface on the release branch. Nothing in `ci_scripts/` changes —
  both hooks were already gated on `CI_XCODEBUILD_ACTION = archive`.

### Removed
- `templates/ci_scripts/lib/asc_build_number.rb` and its call from
  `ci_pre_xcodebuild.sh`. It authenticated to App Store Connect to compute a
  build number that Xcode Cloud then overwrote with its own counter at export
  time — work whose result was always discarded. Removing it means the archive
  path needs no credentials and makes no network call that could fail it.

### Changed
- **The App Store Connect API key now lives in GitHub Secrets only.** Xcode
  Cloud needs no environment variables; MIGRATE.md step 4 is now "nothing to
  configure". Store metadata and screenshot workflows are unaffected.
- `ci_pre_xcodebuild.sh` stamps `MARKETING_VERSION` only. `CURRENT_PROJECT_VERSION`
  is left alone, since Xcode Cloud overwrites `CFBundleVersion` regardless.

### Fixed
- `validate.sh` failed on this repo: the README version line had drifted to
  1.1.0 (VERSION was edited without `bump-version.sh`), and PLAYBOOK.md tripped
  the placeholder check by documenting the token syntax, which MIGRATE.md was
  already exempted for.
- Retired three gotcha-table entries that described failures no longer
  reachable (ASC key parsing and env-var persistence in Xcode Cloud).

## [1.2.0] - 2026-07-12

The whole portfolio (Prarthana, 1tattooz, ABCLearning, Drawing) was
brought to byte-level consistency with these templates — every file
identical across apps modulo declared parameters (app name, bundle id,
locales, and which optional parts an app uses). The template fixes below
came out of that pass; every one was found live in at least one app.

### Added
- PLAYBOOK §1: canonical `App/Source/` layout — exactly `App/`,
  `Features/<Name>/`, `Shared/`; `Shared/AnalyticsManager.swift` is a
  fixed path the analytics PR check greps. All four apps restructured.
- PLAYBOOK §10: complete from-scratch recipe for a NEW app (Xcode
  project settings, setup.sh, ASC key in its three places, Xcode Cloud
  workflows, prove-the-automation dry run).
- Fastfile: three standard manual lanes — `promo`, `pricing`,
  `review_notes` (ENV-overridable contact info). Lane names
  `validate_metadata`/`metadata`/`screenshots` documented as a contract
  with the workflows.
- `pr-guards.yml`: `firebase-config-guard` (asserts `IS_ANALYTICS_ENABLED`
  true) is now standard for any app with a `GoogleService-Info.plist` —
  the flag was found sitting at `false` on two more live apps.
- MIGRATE gotchas: agvtool is a silent no-op with generated Info.plists;
  ASC API transient failures need retry; lane renames break workflows;
  dSYM upload paths must carry the `App/` prefix; membershipExceptions
  must move together with restructured source folders.

### Changed
- `ci_pre_xcodebuild.sh`: versions are stamped into `MARKETING_VERSION` /
  `CURRENT_PROJECT_VERSION` build settings via sed — agvtool never worked
  on these projects (`GENERATE_INFOPLIST_FILE=YES`). Also accepts
  two-component `release/X.Y` branches.
- `asc_build_number.rb`: retries transient network errors and 429/5xx
  with exponential backoff.
- `env.example`: variable names now match what the Fastfile actually
  reads (`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_CONTENT`), replacing
  the stale `APP_STORE_CONNECT_*` names that documented nothing.
- `Appfile`: standard four-line form with `FASTLANE_APPLE_ID` /
  `FASTLANE_ITC_TEAM_ID` ENV fallbacks.
- `release-merge.yml`: GitHub Release title is `<AppName> X.Y.Z` so
  cross-repo notification feeds read unambiguously.

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
