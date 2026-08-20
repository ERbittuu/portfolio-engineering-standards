# Changelog

## [1.10.3] - 2026-08-20

Everything here was found pushing Colorful's first release to the App Store.

### Fixed
- `Deliverfile` no longer sets `automatic_release` or `phased_release`. App Store
  Connect rejects the ENTIRE metadata PATCH with "The attribute 'releaseType' can
  not be modified" whenever the version has no build attached — the state every
  first release is in — and it fails even when the value being sent matches what
  the version already has. `phased_release` is worse: Apple does not offer phased
  release for an app's first version at all. deliver omits `releaseType` when
  `automatic_release` is nil, so leaving both unset is the fix. This blocked the
  metadata push for a real app; every app adopting PES would have hit it on its
  first release.
- `validate_metadata` now recognises the scaffold's own text. It only ever looked
  for the string `UPDATE THIS`, which `metadata-locale.template.json` never
  emits — so "First paragraph of the store description." and
  "comma,separated,max,100,chars" passed every PR check and were one merge away
  from the live listing. It now fails on each string the template seeds, and on
  any unsubstituted `{{PLACEHOLDER}}`.
- `scripts/ci/validate_screenshots.py` moved from MANAGED to SEEDED in
  `update.sh`. The file carries a `{{ EDIT ... for this app }}` marker and must
  differ per app — a landscape-only app transposes every dimension — but being
  MANAGED meant `update.sh` overwrote those edits on the next update. A file that
  is meant to be edited per app cannot be one PES overwrites.

### Added
- `scripts/ci/validate_urls.py`, wired into `pr.yml`'s `validate-metadata` job:
  fetches every URL the app ships — `support_url`, `privacy_url` and
  `marketing_url` from the store metadata, plus anything under `links` in
  `config.json` — and fails on a 4xx/5xx. Every existing check validated URL
  *shape*, and shape is not the failure mode: PES itself scaffolds
  `https://<owner>.github.io/<repo>/privacy`, which is well-formed and 404s until
  someone enables GitHub Pages. Apple requires a working privacy URL and rejects
  the listing over a dead one, at submission, long after CI went green. Network
  and DNS errors are reported as warnings rather than failures — a check that
  fails on runner flake is a check people learn to re-run.

## [1.10.2] - 2026-08-20

### Removed
- The SYSKit test step from the app `pre-push` hook. It is vendored unchanged and
  tested at source in this repo's CI, so running it per app bought nothing — the
  same reasoning that removed the `syskit-tests` job from `pr.yml` in 1.9.2. It
  also could not run reliably from a hook: `DEVELOPER_DIR` fixes the toolchain but
  not the SDK, so `swift` still compiled against the Command Line Tools SDK and
  failed the manifest with an error that reads like broken code. A hook that
  blocks pushes for reasons unrelated to the change is a hook that gets bypassed.

## [1.10.1] - 2026-08-20

### Fixed
- `pre-push` pins `DEVELOPER_DIR`. A git hook does not inherit the shell's
  toolchain selection, so `swift test` resolved against the Command Line Tools
  SDK while compiling with Xcode's — the SDK and compiler versions disagreed and
  the manifest failed to build. It only ever failed during an actual push and
  passed every time it was run by hand, which made it look like a flake. Added to
  the gotcha table.

## [1.10.0] - 2026-08-20

### Added
- `main.yml` gains a `deploy-config` job, and `firebase.json` is now a template.
  Config was validated on every PR and **deployed by nothing** — the remote half
  of remote config did not exist, so every app would have shipped reading only
  its bundled copy while appearing fully wired. Found by migrating a real app.
  It publishes the same `config.json` the app ships, then verifies the served
  `configVersion` matches what was shipped; a green deploy is not proof the file
  is being served.
- `update.sh` seeds `firebase.json` alongside `config.json` and
  `AnalyticsManager.swift` for apps adopting SYSKit later.

### Fixed
- The vendored-source pre-commit hook blocked `.vendor-version`, which
  `update.sh` itself writes into each vendored package — PES tooling produced a
  change PES hooks refused to commit.
- `update.sh` now seeds app-owned files an existing app is missing. `setup.sh`
  ships them for new apps, so only apps adopting SYSKit later hit this, and they
  hit it as a red `validate-config` with no obvious cause.

## [1.9.2] - 2026-08-20

### Fixed
- CI is green. The two fixes that got it there landed after 1.9.1 was tagged, so
  they were in no release: `SYSNetwork` needed `FoundationNetworking` (Linux keeps
  `URLSession` and `HTTPURLResponse` there rather than in `Foundation`), and the
  tests moved to macOS once it was clear `URLSession`'s async API does not exist
  in swift-corelibs-foundation at all.

## [1.9.1] - 2026-08-20

### Fixed
- CI's first run failed: `swift-actions/setup-swift` returned 404. SYSKit's tests
  now run on macOS, which is free for this public repo and is the platform SYSKit
  ships to. Linux was the original plan, but `SYSNetwork` uses URLSession's async
  API and swift-corelibs-foundation does not provide it — working around that for
  a platform SYSKit never runs on is not worth it. `SYSLogger` and `SYSNetwork`
  still guard their imports with `canImport`, which costs nothing and keeps the
  door open.
- `pr.yml` no longer re-runs SYSKit's tests in every app. The package is vendored
  unchanged and tested at source here, so running it again in five private repos
  bought no new information and would have billed macOS minutes to do it.

### Removed
- The git hooks briefly installed on this repo. PES defines how *apps* work and
  is not an app: nothing here has `App/Packages`, `App/Resources/config.json`,
  `App/*.xcodeproj` or `App/Source`, so five of the checks silently no-opped
  while looking like protection, and the one that mattered tested nothing because
  the package lives at `SPM/SYSKit` rather than `App/Packages/SYSKit`. The
  branch-name rule did not apply either — releases here come from `main` via
  `release.sh`, not release branches. CI stays: testing the output this repo
  ships is not the same as applying app rules to it.

## [1.9.0] - 2026-08-20

### Added
- **CI for this repo.** `validate.sh` existed long before anything ran it, and in
  that time collected real failures nobody saw — the README version line had
  drifted two releases behind and PLAYBOOK.md tripped the placeholder check. It
  now runs on every PR, alongside the SYSKit tests and a scaffold job that builds
  a throwaway app from `setup.sh` and checks it passes its own PR checks. That
  last one exists because it has already failed: a scaffolded app had no
  `AnalyticsManager.swift` while the guard for it ran on every PR.
- `scripts/lint-project.sh` — build settings that compile and are still wrong.
  CI builds the app, so anything that compiles passes: a literal
  `CFBundleShortVersionString` silently beats `MARKETING_VERSION`, so CI stamps
  the version, reports success and ships the wrong number every release. Also
  catches missing `-ObjC` (Firebase fails at runtime, not build time), remote
  packages, and SYSKit vendored but never linked in Xcode.
- `update.sh` reports when SYSKit is on disk but absent from `project.pbxproj`.
  Linking it is a pbxproj edit, deliberately not automated across every app — a
  bad edit is slower to unpick than doing it by hand. Without the warning,
  "files copied" looks exactly like a finished migration.

### Fixed
- Published the GitHub Release for v1.4.0, which had been tagged but never
  released.

## [1.8.0] - 2026-08-20

### Added
- `scripts/status.sh` — one read-only table showing, for every app: the version
  live on the App Store, the highest version merged to main, the newest tag, the
  PES version it is on, how far it has drifted, and open PRs. All of it was
  already discoverable and none of it was in one place, which took eight commands
  across three tools to assemble — so nobody assembled it, and an app sitting
  five workflows behind went unnoticed for weeks.
- Live versions come from Apple's public lookup, so it needs no App Store
  Connect key. TestFlight versions come from merged `release/*` PR head refs
  rather than branch names, because release branches are deleted on merge and
  ref names therefore miss every shipped version.

## [1.7.1] - 2026-08-20

### Added
- `commit-msg` hook enforcing Conventional Commits and a 72-character subject,
  adopted from Prarthana, which had already written it. CHANGELOG sections are
  written from these messages, so the format is load-bearing.
- `pre-commit` also blocks `.env`, `.p8`, `.p12`, `.mobileprovision` and
  `.certSigningRequest` by name — cheaper and more reliable than a scanner for
  the files that leak most often — blocks hand-edits inside `App/Packages`
  (except our own `SYS*` packages, which live there too), and lints only the
  staged Swift files. All three came from Prarthana's hooks, which were ahead of
  what PES shipped.

### Fixed
- `update.sh --check` printed a shell error and could not read existing
  `.vendor-version` files: the input redirect is evaluated before `2>/dev/null`,
  so the failure was reported rather than suppressed. It now guards the file
  explicitly and says "would record" in check mode, since it records nothing.

## [1.7.0] - 2026-08-20

### Added
- **Git hooks**, in `.githooks/` and activated via `core.hooksPath`. On GitHub
  Free a private repo has no branch protection, so every CI check reports and
  none of them block — hooks are the only place something can actually be
  stopped, so they cover the cases where finding out later is too late.
- `pre-push` validates the branch name. This is not style: `release.yml` takes
  the tag straight from the branch name, so `release/v2.9.0` or `release/2.9`
  produce a wrong tag or none at all. It also runs the SYSKit tests when that
  package changed — about a second, no simulator.
- `pre-commit` rejects files over 5MB (history is forever; one app carries a
  vendored folder 300x the size of the same library elsewhere), scans for
  secrets (a secret pushed to GitHub is compromised even if the branch is
  deleted straight after — the CI guard only fires once that has happened),
  blocks remote SwiftPM packages, and validates `config.json`.
- Both are escapable with `--no-verify`, and the secret scan skips with a note
  when gitleaks isn't installed rather than blocking work on a missing tool.
- `update.sh` reports when `core.hooksPath` is unset and sets it when applying.
  `.git/hooks` is not versioned, so a clone without that config silently has no
  hooks — which looks like protection and is not.

## [1.6.0] - 2026-08-20

### Changed
- `SYSKitFirebase` is now `SYSFirebase`, so our own packages read as a set:
  `SYSKit`, `SYSFirebase`. Free to do now — no app has adopted them yet.
- Documented the rule that **`SYS` means our code**. Vendored third-party
  packages keep their own names: `FirebaseKit` holds Google's xcframeworks,
  `Kingfisher` is Kingfisher. That distinction is load-bearing rather than
  cosmetic — it is what `.swiftlint.yml` excludes from linting and what
  `update.sh` reports on but never overwrites, so prefixing someone else's
  binaries with our studio prefix would blur the line those tools rely on.

## [1.5.1] - 2026-08-20

### Fixed
- `setup.sh` now ships `App/Source/Shared/AnalyticsManager.swift`. Without it a
  freshly scaffolded app failed its own `analytics-event-guard` on the first PR:
  that job runs on every PR with no path filter, and the validator errors when
  the file is missing. It also left the shared `SYSAnalytics` half-shown, since
  the manager needs an app-side event enum and nothing demonstrated one.
  The template uses `case .x(let y)` — the form the validator can actually see.

## [1.5.0] - 2026-08-20

### Added
- **SYSKit** — the shared layer every app vendors, in `SPM/`. Two packages, kept
  apart on purpose: `SYSKit` has **no dependencies**, so `swift test` runs it on a
  plain Linux runner with no Xcode, no simulator and no Firebase; `SYSKitFirebase`
  holds the single file that imports Firebase and only resolves once vendored
  beside FirebaseKit in an app. An earlier single-package version could not build
  in this repo at all, which would have made the CI test job impossible.
- It contains **no screens** and imports no UI framework. `SYSBootstrap.start()`
  returns state and the app renders it, so the one UIKit app uses it unchanged —
  `await` works the same from a scene delegate as from a SwiftUI `.task`, and no
  entry-point migration is needed.
- Modules: `SYSConfig` (moved here from each app's Shared folder), `SYSNetwork`
  (JSON, file download, ETag, retry, Firebase Storage URLs), `SYSSettings` (typed
  UserDefaults — raw `UserDefaults` appears in 16 files across the apps),
  `SYSLogger` (quiet in release, non-fatal error reporting), `SYSLifecycle`,
  `SYSOnboarding` (versioned, so a new flow can re-show), `SYSUpdate`,
  `SYSMaintenance`, `SYSWhatsNew`, `SYSRating`, `SYSVersion`, `SYSAnalytics`.
- 22 unit tests, run by a new `syskit-tests` job in `pr.yml`. They cover the
  failures that are silent rather than loud: `"1.10.0"` not sorting below
  `"1.9.0"`, a stored `false` not reading as unset, Storage paths encoding `/`
  as `%2F`, and unknown config keys not breaking decode.
- `vendor.json` records the canonical **version** of each third-party package —
  never the binaries, which would put hundreds of megabytes into a repo that is
  cloned constantly. Apps record what they have in `App/Packages/<Name>/.vendor-version`
  and `update.sh --check` reports drift. Contents are never copied: apps
  deliberately vendor different product subsets, and ABCLearning excludes Firebase
  Analytics because the Kids Category forbids third-party measurement SDKs —
  overwriting that would be a store compliance problem caused by automation.
- Config gains `whatsNew` (release notes per version, localised) and
  `urls.appStore`, both checked by `validate_config.py`.

### Changed
- `.swiftlint.yml` excludes vendored third-party packages individually instead of
  excluding `App/Packages` wholesale. SYSKit lives there and is ours — the blanket
  exclusion would have left the one library shared by every app as the only code
  nobody lints.
- `setup.sh` and `update.sh` vendor and sync SYSKit; `update.sh` copies whole
  package directories rather than file-by-file.

## [1.4.0] - 2026-08-20

### Added
- **Standard remote config.** `App/Source/Shared/SYSConfig.swift` is one shared
  file, identical in every app — apps put their own values under the `app` key
  rather than forking it. Each app ships `App/Resources/config.json` and serves
  that same file from its Firebase Hosting, so a bundled copy and a served copy
  cannot drift. At launch it loads locally (bundled, or a cached fetch with a
  higher `configVersion`), then refreshes in the background for the next launch;
  a fetched config never applies mid-session. No internet, malformed JSON, a
  non-2xx response, or a config older than the one in hand all fall back
  silently, so the app can never end up worse off than what shipped. The cache
  lives in Application Support, not Caches, which the system may purge.
  Standard keys: `update` (with force and recommended versions), `maintenance`
  kill switch, `flags`, `rating`, `urls`, `content`, `crossPromo`. Messages take
  either a bare string or a per-language map resolved against the device
  language. Version comparison is numeric, never string — `"1.10.0"` sorts below
  `"1.9.0"` as text, which works for years and then breaks at the first
  double-digit minor.
- `scripts/ci/validate_config.py` and a `validate-config` job in `pr.yml`.
  Config reaches every user at once and they cannot roll it back, so it gets the
  strictest check here: schema, required keys, version formats, and a refusal of
  any `minimumVersion` above the version currently live on the App Store — that
  combination blocks 100% of users with no version available to update to.
- `scripts/update.sh [--check] <app-dir>` — brings an existing app up to the
  current PES version. `setup.sh` never overwrites, which is right for a new
  repo and useless for an existing one; that gap is why apps drifted silently
  (one sat five workflows behind, another kept a non-standard `.gitignore` for
  weeks). It rewrites only the files PES owns, re-renders placeholders from the
  app itself so there is nothing to keep in sync by hand, and reports — but
  never touches — app-owned files and workflows PES no longer ships.
  `--check` changes nothing and is the intended first run.
- `.pes-version` in each app, written by `setup.sh` and `update.sh`, so it is
  finally possible to answer which apps are behind.

### Removed
- `.swiftformat` and its copy step. The config shipped to every app but nothing
  ever ran SwiftFormat — not a workflow, not a script, not even the tool being
  installed. It also carried `--header strip`, so switching it on would have
  deleted the header comment from every source file. SwiftLint already covers
  what matters.
- `templates/docs/SECURITY.template.md`. `setup.sh` never copied it and no app
  has ever had a SECURITY.md.

### Changed
- Dependabot also watches `bundler`. fastlane is what talks to App Store
  Connect, so a stale pin breaks the store workflows when Apple changes an API.

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

### Changed
- **Releases merge after Apple approves, not before** (PLAYBOOK §5, MIGRATE §7).
  A tag now exists only for a version that actually reached users, so the newest
  tag answers "what is live?", and a rejected build leaves nothing behind. It
  also removes the window where content deployed while the build that understood
  it was still in review. Previously the merge happened first, which is how one
  app ended up merging the same release branch three times after rejections.
- `main.yml`'s `store-metadata` and `store-screenshots` also run on `release/*`
  pushes, so App Store text and screenshots are in place before you submit.
  `deploy-data` stays main-only, deliberately: content goes live the moment it
  deploys, with no review in between. Path diffing happens only on `main` — the
  first push of a release branch has nothing to diff against, so store content
  always syncs there rather than depending on how an action handles an empty
  base.
- `release.yml` verifies the release and tag exist after creating them. A green
  step is not proof — this reported success while leaving no tag and no release
  behind on a real app.

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
