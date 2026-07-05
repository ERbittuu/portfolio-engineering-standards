# Migration Guide

How I move an existing app onto this system. Takes one afternoon if you
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
5. `gh repo create <org>/<Name> --private --source=. --push`, then set
   squash-only merge and auto-delete branches.

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
`apps:sdkconfig` → plist into `App/Resources/`. `firebase.json` and
`.firebaserc` at repo root. Deploy once by hand to confirm. Create a
service account with Hosting rights only → `gh secret set
FIREBASE_SERVICE_ACCOUNT`. Enable Google Analytics in the console — CLI
created projects don't have it. Turn on Crashlytics email alerts.

## 4. Xcode Cloud (30 min)

1. Grant access FIRST: github.com → org settings → GitHub Apps → Xcode
   Cloud → add this repo. Without this the wizard fails with no useful
   error.
2. If the project has an old `xcshareddata/xcodecloud/manifest.json`,
   delete it before onboarding — Xcode tries to match a product that no
   longer exists.
3. Two workflows only. `CI`: branch main + PRs, Files and Folders filter
   set to `App`, one Build action, remove the Test action. `Release`:
   tags **beginning with** `v` (not "is exactly"!), Archive → TestFlight
   Internal.
4. In ci_scripts remember: scripts start inside `ci_scripts/`, so
   `cd "$CI_PRIMARY_REPOSITORY_PATH/App"` before any agvtool call.

## 5. Store automation (30 min)

Set `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_CONTENT` repo secrets (API
key from ASC → Integrations, App Manager role; the .p8 goes to the
password manager, never the repo). Fill `fastlane/metadata/<locale>.json`.
Run the Store Metadata workflow once and then VERIFY on App Store Connect
— a green run alone is not proof, deliver can no-op silently (see
gotchas).

## 6. First release

CHANGELOG section → publish GitHub Release `vX.Y.Z` → Xcode Cloud
archives with the version from the tag, `release-tag.yml` goes green,
build appears in TestFlight → test on device → Submit.

---

## Gotcha table — every one of these cost me real time

| Symptom | Cause / fix |
|---|---|
| Xcode Cloud "Failed to create workflow" | GitHub App has no access to the repo (org owner must add it), or a stale `xcodecloud/manifest.json` in the project — delete it and restart Xcode |
| Onboarding wizard stuck on a dependency repo | You still have remote packages. Make them local (step 2). Also add a GitHub account in Xcode Settings → Accounts |
| `agvtool: There are no Xcode project files` in CI | Xcode Cloud starts scripts inside `ci_scripts/` — cd to the project folder first |
| Tag never triggers the Release workflow | Tag condition is "is exactly v" instead of "beginning with v" |
| deliver crashes on `price_tier` | Apple removed pricing from that API. Manage price in the ASC website, delete price_tier |
| deliver fails on IAP precheck | API key auth can't check IAPs — `precheck_include_in_app_purchases false` |
| deliver says success but ASC shows nothing | Paths resolve from the working directory, not the fastlane folder. Use `./fastlane/metadata`, and in Ruby code anchor with `File.expand_path(..., __dir__)` |
| Upload rejected: invalid characters | No emoji allowed in "What's New" |
| Upload rejected: supportUrl pattern | Placeholder text instead of a real URL |
| "Language cannot be activated" | Store locale list is fixed by Apple. App languages ≠ store languages (Gujarati is not a store locale) |
| Every screenshot appears twice | The old `overwrite_screenshots` path double-uploads. Use the sync lane; delete leftover duplicates via the ASC API |
| Screenshots run red: "failures of processing" | Apple processed slowly after a successful upload. Check the listing before re-running |
| Tag pushed by a workflow triggers nothing | GitHub blocks workflow-created tags from firing other workflows. Humans publish Releases; a workflow that needs follow-up work does it in the same run |
| gcloud dies complaining about Python | `export CLOUDSDK_PYTHON=/opt/homebrew/bin/python3.12` |
| Bundler asks for sudo | Never use system Ruby. Homebrew Ruby + `bundle config set --local path vendor/bundle` |
