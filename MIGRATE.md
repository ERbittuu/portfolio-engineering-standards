# Migration Guide

How I move an existing app onto this system. Takes an afternoon if you
follow the order. This is the exact sequence I used for Prarthana,
including every problem I hit — read the gotcha table at the bottom
BEFORE debugging anything, the answer is probably already there.

Needed on the Mac: Homebrew Ruby on PATH, `gh` CLI logged in, `firebase`
CLI logged in, Xcode signed into the team.

## 1. Repo (30 min)

1. `git init -b main`, copy the standard `.gitignore` first, then one
   snapshot commit of everything as-is. Safety point before touching
   anything.
2. Restructure to the playbook layout: project + sources + `ci_scripts/`
   under `App/`, content under `Data/`, `fastlane/` + `Gemfile` at root,
   entitlements into `App/Config/` (update `CODE_SIGN_ENTITLEMENTS` paths
   in the pbxproj).
3. Run `scripts/setup.sh` from this repo. Fill every `{{PLACEHOLDER}}`
   (`git grep '{{'`), delete the parts this app doesn't need.
4. Clean legacy naming: entry struct, `productName` in pbxproj, file
   headers. Bundle IDs stay — they are store identity, forever.
5. `gh repo create <org>/<Name> --private --source=. --push`.

## 2. Make all dependencies local (1 hr)

List remote deps from `Package.resolved`, then one by one:

- Swift library → download the exact pinned release tag, copy `Sources/`
  + `LICENSE` + a small `Package.swift` into `App/Packages/<Name>/`.
  Delete any `Documentation.docc` folder — old manifests try to compile
  its sample code and the build fails.
- Firebase → download the matching `Firebase.zip` release. Copy the
  xcframeworks of the needed products into `App/Packages/FirebaseKit/`
  (binaryTarget package, products named `FirebaseAnalytics` /
  `FirebaseCrashlytics`). Add `-ObjC` to `OTHER_LDFLAGS`. Copy
  `upload-symbols` into `FirebaseKit/Tools/`.
- In the pbxproj, replace every `XCRemoteSwiftPackageReference` with an
  `XCLocalSwiftPackageReference` and remove the `package =` line from the
  matching product dependency.
- Delete every `Package.resolved`. Then check:
  `xcodebuild -resolvePackageDependencies` must list only local packages,
  and a full simulator build must pass.

## 3. Firebase (30 min, if used)

`firebase projects:create <name>-prod` → `firebase apps:create ios` →
`apps:sdkconfig` → plist into `App/Resources/`. **Check
`IS_ANALYTICS_ENABLED` is `true` in that plist right now** — it's easy for
this to sit at `false` silently, and nothing errors when it does; you just
lose every analytics event with no signal that anything's wrong.
`firebase.json` and `.firebaserc` at repo root. Deploy once by hand to
confirm. Create a service account with Hosting rights only → `gh secret
set FIREBASE_SERVICE_ACCOUNT`. Enable Google Analytics in the console —
CLI created projects don't have it. Turn on Crashlytics email alerts.

## 4. Xcode Cloud (30 min)

1. Grant access FIRST: github.com → org settings → GitHub Apps → Xcode
   Cloud → add this repo. Without this the wizard fails with no useful
   error.
2. If the project has an old `xcshareddata/xcodecloud/manifest.json`,
   delete it before onboarding — Xcode tries to match a product that no
   longer exists.
3. Two workflows. `CI`: branch `main` + PRs, Files and Folders filter set
   to `App`, one Build action, remove the Test action. `Release`: **Branch
   Changes**, pattern `release/` with "is prefix" checked, Files and
   Folders filter set to `App`, Archive → TestFlight Internal. Not a tag
   condition — see PLAYBOOK §5 for why releases are branch-driven here.
4. Add `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_CONTENT` as **Environment
   Variables on the Release workflow** (Edit → Environment → Add, three
   times, mark each Secret, then actually hit Save — an edit that isn't
   explicitly saved silently reverts). This is a separate store from
   GitHub Secrets; Xcode Cloud can't read those. Paste the key carefully —
   see the gotcha table, that field does not reliably preserve a
   multi-line paste.
5. In ci_scripts remember: scripts start inside `ci_scripts/`, so
   `cd "$CI_PRIMARY_REPOSITORY_PATH/App"` before any agvtool call.

## 5. PR checks (30 min)

Copy `lint.yml`, `pr-guards.yml`, `validate-metadata.yml`,
`validate-screenshots.yml`, `validate-release.yml` from
`templates/workflows/` (setup.sh already did this — just confirm they're
there and fill in `scripts/ci/validate_screenshots.py`'s `STORE_LOCALES`
and `REQUIRED` for this app's actual locales and device sizes). Open a
throwaway PR touching each relevant path once to confirm each check
actually *runs* rather than silently never triggering — a check that
never fires is worse than no check, because it looks like coverage that
isn't there.

If the repo is private and on GitHub's Free plan, branch protection
(classic or Rulesets) isn't available — the checks still run and show
red/green on every PR, they just don't block the merge button. Know that
going in rather than discovering it when you try to configure it.

## 6. Store automation (30 min)

Set `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_CONTENT` repo secrets (API
key from ASC → Integrations, App Manager role; the .p8 goes to the
password manager, never the repo — this is the same key you also added to
Xcode Cloud in step 4, just a separate copy). Fill
`fastlane/metadata/<locale>.json`. Run the Store Metadata workflow once
and then VERIFY on App Store Connect — a green run alone is not proof,
deliver can no-op silently (see gotchas).

## 7. First release

1. `git checkout -b release/X.Y.Z` off `main`.
2. Add the CHANGELOG section for that version. Push.
3. Xcode Cloud builds from the branch directly. Watch it in App Store
   Connect (or `gh run list` won't show it — it's not a GitHub Actions
   run). If it fails, fix and push again to the same branch; no new
   branch needed for a rebuild.
4. Build appears in TestFlight → install → test on a real device.
5. Happy? Open a PR from the release branch to `main`, let
   `validate-release.yml` confirm the CHANGELOG + version checks, merge.
   That merge creates tag `vX.Y.Z` and publishes the GitHub Release —
   automatic, `release-merge.yml` does it.
6. Submit in App Store Connect.

---

## Gotcha table — every one of these cost me real time

| Symptom | Cause / fix |
|---|---|
| Xcode Cloud "Failed to create workflow" | GitHub App has no access to the repo (org owner must add it), or a stale `xcodecloud/manifest.json` in the project — delete it and restart Xcode |
| Onboarding wizard stuck on a dependency repo | You still have remote packages. Make them local (step 2). Also add a GitHub account in Xcode Settings → Accounts |
| `agvtool: There are no Xcode project files` in CI | Xcode Cloud starts scripts inside `ci_scripts/` — cd to the project folder first |
| Release workflow never triggers | Branch condition pattern is wrong, or "is prefix" isn't checked — `release/1.8.0` needs to match a `release/` prefix, not an exact string |
| `ASC_KEY_ID not set` in an Xcode Cloud build log, even though you added it | The env var edit wasn't actually saved — re-open the workflow editor and confirm it's still listed, re-save if not |
| `Could not parse PKey: no start line` from `asc_build_number.rb` | Xcode Cloud's Environment Variable text field doesn't reliably preserve a multi-line paste — it can strip the BEGIN/END markers or flatten the newlines entirely. The template script normalizes all of these forms automatically; if you hit this with your own script, reconstruct the PEM structure defensively rather than trusting the paste |
| Build number doesn't reset per version despite the ASC lookup working correctly | Xcode Cloud has its own global sequential build-number counter (App Store Connect → Xcode Cloud → Settings → Build Number) that overwrites `CFBundleVersion` at archive time regardless of what a script sets. Not a bug, not fixable — see PLAYBOOK §5 |
| `gh api .../branches/main/protection` returns 403 "Upgrade to GitHub Pro" | Branch protection (classic or Rulesets) needs a paid plan for a private repo. Public repos and paid orgs get it free |
| `dorny/paths-filter` fails with "Resource not accessible by integration" | The workflow's `permissions:` block needs `pull-requests: read` — `contents: read` alone isn't enough for it to list a PR's changed files |
| `pr-guards.yml`'s secret-scan flags its own source code | gitleaks' `private-key` rule matches the literal `-----BEGIN PRIVATE KEY-----` string anywhere, including inside a script that reconstructs that string as marker text, not a real key. Confirm it's a false positive with a local scan, then suppress with an inline `# gitleaks:allow` comment |
| Secret-scan false positive persists after adding `gitleaks:allow` | gitleaks scans each commit in a PR's range individually — a comment added in a *later* commit doesn't retroactively clear a finding from an *earlier* commit in the same PR. Since every PR here squash-merges anyway, scan the working tree at HEAD (`--no-git`, no `--log-opts` range) instead of git history |
| Tag never triggers the Release workflow | You're still using a tag-based Release trigger — this system is branch-driven now (PLAYBOOK §5), no tag condition should exist on that workflow at all |
| deliver crashes on `price_tier` | Apple removed pricing from that API. Manage price in the ASC website, delete price_tier |
| deliver fails on IAP precheck | API key auth can't check IAPs — `precheck_include_in_app_purchases false` |
| deliver says success but ASC shows nothing | Paths resolve from the working directory, not the fastlane folder. Use `./fastlane/metadata`, and in Ruby code anchor with `File.expand_path(..., __dir__)` |
| Upload rejected: invalid characters | No emoji allowed in "What's New" — `validate-metadata.yml` catches this before merge now |
| Upload rejected: supportUrl pattern | Placeholder text instead of a real URL — also caught pre-merge now |
| "Language cannot be activated" | Store locale list is fixed by Apple. App languages ≠ store languages (Gujarati is not a store locale, for example) |
| Every screenshot appears twice | The old `overwrite_screenshots` path double-uploads. Use the sync lane; delete leftover duplicates via the ASC API |
| Screenshots run red: "failures of processing" | Apple processed slowly after a successful upload. Check the listing before re-running |
| Tag pushed by a workflow triggers nothing | GitHub blocks workflow-created tags from firing other workflows. Irrelevant now that releases are branch-driven and the tag is created by a workflow on purpose — it's *supposed* to trigger nothing |
| gcloud dies complaining about Python | `export CLOUDSDK_PYTHON=/opt/homebrew/bin/python3.12` |
| Bundler asks for sudo | Never use system Ruby. Homebrew Ruby + `bundle config set --local path vendor/bundle` |
| Need to trigger an Xcode Cloud build without waiting for a real push | The App Store Connect API supports a manual build run: `POST /v1/ciBuildRuns` with `relationships.workflow` and `relationships.sourceBranchOrTag` pointing at a `scmGitReferences` id (fetch it from `/v1/scmRepositories/{id}/gitReferences`). Useful for testing a workflow config change against an existing branch |
