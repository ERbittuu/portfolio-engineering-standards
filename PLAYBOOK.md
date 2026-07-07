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
├── scripts/ci/                  # PR-check scripts the workflows call into
├── App/                         # only what Xcode compiles
│   ├── <Name>.xcodeproj
│   ├── Source/<Feature>/        # group by feature, not by type
│   ├── Resources/               # assets, xcstrings, PrivacyInfo, GoogleService-Info
│   ├── Config/                  # entitlements
│   ├── Packages/                # local copies of all dependencies (see section 4)
│   └── ci_scripts/              # must stay next to the .xcodeproj — Apple rule
│       └── lib/                 # helpers ci_scripts call into (kept out of the three magic filenames)
├── fastlane/ + Gemfile          # store content tooling, runs in CI
│   ├── metadata/<locale>.json   # store text — single source of truth
│   └── screenshots/<locale>/
└── Data/                        # content pipeline, only if the app ships remote content
    ├── build.py  index.json  source/
    └── build/                   # generated, gitignored, CI rebuilds it
```

Two locations are fixed by the tools and cannot move: `firebase.json` at
root, and `ci_scripts/` next to the xcodeproj. Everything else follows one
idea: App = compile, Data = content, fastlane = store, .github = automation.

No empty folders. No unused files. Bundle IDs never change — they are the
App Store identity, even if the app name changed over the years. No
per-app decision docs either — the reasoning for a choice belongs in
*this* repo (see [decisions/](decisions/)), where it helps the next app
too, not buried in one app's history.

## 2. Who does what

| Actor | Job |
|---|---|
| GitHub | Everything starts here — push a branch, open a PR, merge it |
| GitHub Actions (Ubuntu) | PR checks, data deploy, store metadata, store screenshots, tagging a shipped release |
| Xcode Cloud (Apple Macs) | Build the app. CI on pushes/PRs, TestFlight archives on release branches |
| Me | Write code, review my own PRs, merge, test on device, press Submit |

Nothing runs on my Mac for a release. My Mac is for writing code.

## 3. Branches

One permanent branch: `main`. Everything else is short-lived and gets
deleted on merge — including release branches. A second permanent branch
(`develop`, a long-lived `release`, whatever) only earns its keep when
you're coordinating multiple people; solo, it's just two branches to keep
in sync for no benefit.

**Work branches** — `code/*`, `data/*`, `metadata/*` (or `feat/`/`fix/`,
pick one convention and keep it). Branch from `main`, PR into `main`,
squash merge, auto-delete. The prefix is for your own readability — the
automation reacts to which files changed, not the branch name.

**Release branches** — `release/X.Y.Z`, one per version, created only when
you're actually about to ship (section 5 covers the whole flow).

No separate hotfix branch type. A bug in a shipped version is just a
normal work branch off `main`, followed by a new `release/X.Y.Z+1` when
you're ready to ship the fix.

## 4. PR checks

Every PR gets a handful of automated checks before you merge it. None of
them hard-block the merge button right now — GitHub only offers real
branch protection on a private repo with a paid plan — so treat a red
check as "don't merge this," not as something that'll physically stop
you.

| Check | Runs on | Catches |
|---|---|---|
| `lint.yml` | any PR, skips if no `.swift` changed | SwiftLint, non-strict (a fresh migration inherits style debt — don't fail day-one PRs over it) |
| `validate-metadata.yml` | any PR, skips if `fastlane/metadata/` unchanged | Every App Store rejection worth catching before merge: emoji, placeholder text, over-limit fields, unsupported locales |
| `validate-screenshots.yml` | any PR, skips if `fastlane/screenshots/` unchanged | Wrong pixel dimensions, incomplete locale sets, corrupt files |
| `validate-release.yml` | any PR, skips unless it's from a `release/*` branch | CHANGELOG has a section for this version; the version is actually newer than the last tag |
| `pr-guards.yml` | every PR, always | Secret scanning, a guard against remote dependencies creeping back in, plus whatever app-specific sanity checks earn their place (Firebase config, Analytics limits — see the file for examples) |

The "skip rather than don't-trigger" pattern matters: a workflow that's
*path-filtered at the trigger level* never produces a check run at all
for a PR that doesn't touch those paths — and a required check with no
run blocks a merge forever, if you ever do get branch protection working.
Trigger on every PR, skip the work inside the job instead.

## 5. Releases: a release branch, not a tag push

Version numbers are not stored in the repo. `MARKETING_VERSION` in the
project is a dev placeholder only.

To release:

1. `main` already has everything you want to ship (it always does — work
   only lands there through merged PRs). Branch: `release/X.Y.Z`.
2. Add the CHANGELOG section for that version, push the branch.
3. Xcode Cloud archives directly from that branch — no tag needed. Push
   again as many times as TestFlight testing needs; each push is a new
   build, no new branch required for a rebuild.
4. Happy with what's in TestFlight? Merge the branch into `main`. That
   merge is the **only** moment a tag gets created (`vX.Y.Z`), and it's
   permanent — a tag here is a historical record, it never triggers
   anything and never moves.
5. Test on a real device. Submit in App Store Connect (phased release on,
   manual release). Rollback: pause phased release, ship the next patch.

`App/ci_scripts/ci_pre_xcodebuild.sh` reads the marketing version straight
from the branch name (`release/1.8.0` → `1.8.0`) and asks App Store
Connect for the build number: last build already uploaded for that exact
version, plus one, or 1 if none exist. See
`App/ci_scripts/lib/asc_build_number.rb`.

**Read this before relying on that build number resetting per version:**
Xcode Cloud maintains its own global, sequential build-number counter per
app (App Store Connect → Xcode Cloud → Settings → Build Number) and
overwrites `CFBundleVersion` with it at archive time — regardless of what
a script sets beforehand. It isn't a toggle, and it isn't exposed through
the App Store Connect API. In practice the marketing-version stamping
still works correctly and is what actually matters; the build number just
climbs forever instead of resetting per version, same as it does for most
iOS teams. Keep the lookup logic anyway — it's harmless, and correct the
day Apple exposes a way to disable their auto-numbering.

Why a branch instead of a tag: a tag is a single, immovable point — great
for "this is what shipped," terrible for "I need three more builds while
QA finds things." A branch can be pushed to any number of times; the tag
only gets created once, at the very end, once you're sure. This also
means the tag never needs to move or be recreated, which a purely
tag-driven scheme forces you into the moment a release needs more than
one build.

## 6. Store content

- `fastlane/metadata/<locale>.json` is the source of truth. The
  `generate_metadata` lane converts it to the txt files deliver needs;
  `validate_metadata` (used by the PR check) parses the same files without
  pushing anything.
- The metadata lane is text-only. The screenshots lane uses
  `sync_screenshots` (checksum based, safe to re-run). Never mix them —
  the old overwrite path uploads everything twice.
- Auth is an App Store Connect API key in repo secrets (`ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`). Never Apple ID login. Xcode Cloud
  needs its own copy of the same key as Environment Variables on the
  Release workflow — it can't read GitHub Secrets, and pasting a
  multi-line key into that UI field is unreliable (see MIGRATE.md).
- Things Apple rejects that I learned the hard way: emoji in "What's New",
  placeholder URLs, and store locales that don't exist (Hindi is a store
  locale, Gujarati is not — app languages and store languages are
  different lists).
- Local `bundle exec fastlane ...` still works as a fallback with
  `fastlane/.env`, but CI is the normal path.

## 7. Firebase

Hosting serves the content that `Data/build.py` produces (zips +
manifest.json; short cache for JSON, longer for zips). `deploy-data.yml`
smoke-tests the live manifest and one sample bundle right after every
deploy — the blast radius of a broken deploy is every app install, so
catching it before a user does is worth the ten extra seconds.

Analytics and Crashlytics: one prod project, SDKs disabled in Debug
builds, dSYMs uploaded by `ci_post_xcodebuild.sh`. If you log custom
Analytics events, keep them in one file as an enum (name + parameters per
case) — it's what makes `scripts/ci/validate_analytics_events.py`
possible, and it means `grep`ing one file shows everything the app ever
reports. Deploy auth is a service account JSON in the
`FIREBASE_SERVICE_ACCOUNT` secret with Hosting rights only.

Anything more (Firestore, RTDB, Functions) has to justify itself through
[decisions/firebase-services.md](decisions/firebase-services.md) first —
and then the separate dev/prod project rule applies.

## 8. Git

Trunk-based, one permanent branch (section 3). Squash merge only, branches
auto-delete. Commit format: `type: what it does` with types
feat/fix/chore/docs/refactor/test/ci. Secrets never in the repo. Private
repos by default.

## 9. Once per app

- [ ] 2FA everywhere; ASC API key in password manager + repo secrets +
      Xcode Cloud Environment Variables (three separate places, same key)
- [ ] PrivacyInfo.xcprivacy present; ASC privacy labels updated in the same release that adds any SDK
- [ ] Crashlytics email alerts on
- [ ] String catalogs from day one; automatic signing everywhere
- [ ] Old endpoints that shipped binaries still call: freeze, never delete
- [ ] Branch protection: enable it if the repo is public or on a paid
      plan; otherwise the PR checks are advisory only — know that going in

---

If reality and this playbook disagree, one of them gets fixed the same
week. A playbook that drifts is useless.
