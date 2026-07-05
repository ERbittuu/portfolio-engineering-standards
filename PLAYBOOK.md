# Playbook

How every app of mine works. Around 15 minutes to read, and that is the
complete system. Reference app: Prarthana.

---

## 1. Repo layout

One private repo per app. Everything the app needs lives in it:

```
my-app/
├── README.md  CHANGELOG.md
├── .gitignore .gitattributes .editorconfig
├── .swiftlint.yml .swiftformat
├── .env.example                 # documents every secret; real values never committed
├── firebase.json  .firebaserc   # must stay at root — Firebase CLI expects it here
├── .github/workflows/           # all automation
├── App/                         # only what Xcode compiles
│   ├── <Name>.xcodeproj
│   ├── Source/<Feature>/        # group by feature, not by type
│   ├── Resources/               # assets, xcstrings, PrivacyInfo, GoogleService-Info
│   ├── Config/                  # entitlements
│   ├── Packages/                # local copies of all dependencies (see section 4)
│   └── ci_scripts/              # must stay next to the .xcodeproj — Apple rule
├── fastlane/ + Gemfile          # store content tooling, runs in CI
│   ├── metadata/<locale>.json   # store text — single source of truth
│   └── screenshots/<locale>/
├── Data/                        # content pipeline, only if the app ships remote content
│   ├── build.py  index.json  source/
│   └── build/                   # generated, gitignored, CI rebuilds it
└── docs/decisions/              # short ADRs for decisions I will forget the reason for
```

Two locations are fixed by the tools and cannot move: `firebase.json` at
root, and `ci_scripts/` next to the xcodeproj. Everything else follows one
idea: App = compile, Data = content, fastlane = store, .github = automation.

No empty folders. No unused files. Bundle IDs never change — they are the
App Store identity, even if the app name changed over the years.

## 2. Who does what

| Actor | Job |
|---|---|
| GitHub | Everything starts here — push, merge, or publish a Release |
| GitHub Actions (Ubuntu) | Data deploy, store metadata, store screenshots, release fan-out |
| Xcode Cloud (Apple Macs) | Build the app. CI on pushes, TestFlight on tags |
| Me | Write code, merge PRs, publish Releases, test on device, press Submit |

Nothing runs on my Mac for a release. My Mac is for writing code.

## 3. The workflows

| Workflow | Trigger | Does |
|---|---|---|
| Xcode Cloud `CI` | push/PR touching `App/` (set the folder filter!) | Build only. No Test action until real test targets exist |
| Xcode Cloud `Release` | tag beginning with `v` | Archive → TestFlight Internal |
| `ci-data.yml` | PR/push touching `Data/` | Runs the data build — that is the validation |
| `deploy-data.yml` | merge touching `Data/` | Build + deploy to Firebase Hosting |
| `store-metadata.yml` | merge touching `fastlane/metadata/` | Store text → App Store Connect |
| `store-screenshots.yml` | merge touching `fastlane/screenshots/` | Screenshots → App Store Connect (sync mode) |
| `release-tag.yml` | tag `v*` | CHANGELOG check → metadata push → GitHub Release notes |

Every repo keeps its own copies of these files. I do not share workflows
between repos — copies are readable and can never break another app.

Rules for all workflows: explicit `permissions`, `concurrency` group,
`timeout-minutes`, folder path filters, Ubuntu runners (Mac minutes are
for Xcode Cloud only).

## 4. Dependencies: everything local, nothing remote

**Hard rule: the project resolves zero remote packages.** No Package.resolved,
no third-party git URLs, no network needed to build.

- Swift libraries → copy the source of the exact release into
  `App/Packages/<Name>/` as a local package. Keep the upstream LICENSE.
  Write the version and update steps in the Package.swift header.
- Firebase → Google ships an official binary zip for manual integration.
  Copy only the xcframeworks for the products I use into a local
  `FirebaseKit` package (binaryTargets). Add `-ObjC` to the app target
  linker flags. Keep `upload-symbols` in `FirebaseKit/Tools/`.

Why I do this: builds work offline, Xcode Cloud never asks for access to
somebody's repo, and no upstream change can break my build. The cost is
manual updates — I check vendored versions about twice a year, and that
is a fair trade.

Before adding any dependency at all, ask: is writing it myself cheaper in
the long run? Usually yes.

## 5. Releases: the tag is the version

Version numbers are not stored in the repo. `MARKETING_VERSION` in the
project is a dev placeholder only.

To release: update CHANGELOG.md, then on github.com → Releases → Draft a
new release → tag `vX.Y.Z` → Publish. That one tag does everything:

- Xcode Cloud archives it. `ci_pre_xcodebuild.sh` sets the marketing
  version from the tag and the build number from `CI_BUILD_NUMBER`.
- `release-tag.yml` fails loudly if CHANGELOG has no section for that
  version, pushes store metadata, and fills the Release notes from the
  CHANGELOG.

After that only the human steps remain: install from TestFlight, test on
a real device, Submit in App Store Connect (phased release on, manual
release). Rollback plan: pause phased release, ship the next patch tag.
Never move or reuse a published tag.

## 6. Store content

- `fastlane/metadata/<locale>.json` is the source of truth. The
  `generate_metadata` lane converts it to the txt files deliver needs.
- The metadata lane is text-only. The screenshots lane uses
  `sync_screenshots` (checksum based, safe to re-run). Never mix them —
  the old overwrite path uploads everything twice.
- Auth is an App Store Connect API key in repo secrets (`ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`). Never Apple ID login.
- Things Apple rejects that I learned the hard way: emoji in "What's New",
  placeholder URLs, and store locales that don't exist (Hindi is a store
  locale, Gujarati is not — app languages and store languages are
  different lists).
- Local `bundle exec fastlane ...` still works as a fallback with
  `fastlane/.env`, but CI is the normal path.

## 7. Firebase

Hosting serves the content that `Data/build.py` produces (zips +
manifest.json; short cache for JSON, longer for zips). Analytics and
Crashlytics: one prod project, SDKs disabled in Debug builds, dSYMs
uploaded by `ci_post_xcodebuild.sh`. Deploy auth is a service account
JSON in the `FIREBASE_SERVICE_ACCOUNT` secret with Hosting rights only.

Anything more (Firestore, RTDB, Functions) has to justify itself through
[decisions/firebase-services.md](decisions/firebase-services.md) first —
and then the separate dev/prod project rule applies.

## 8. Git

Trunk-based. `main` is always releasable. Short branches (`feat/`,
`fix/`), squash merge only, branches auto-delete. Commit format:
`type: what it does` with types feat/fix/chore/docs/refactor/test/ci.
Secrets never in the repo. Private repos by default.

## 9. Once per app

- [ ] 2FA everywhere; ASC API key in password manager + repo secrets only
- [ ] PrivacyInfo.xcprivacy present; ASC privacy labels updated in the same release that adds any SDK
- [ ] Crashlytics email alerts on
- [ ] String catalogs from day one; automatic signing everywhere
- [ ] Old endpoints that shipped binaries still call: freeze, never delete

---

If reality and this playbook disagree, one of them gets fixed the same
week. A playbook that drifts is useless.
