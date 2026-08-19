# Scripts

| Script | Run from | Purpose |
|---|---|---|
| `setup.sh [dir]` | anywhere | Copy the full parts box into a **new** app repo (never overwrites; delete what the app doesn't use) |
| `update.sh [--check] <dir>` | anywhere | Bring an **existing** app up to this PES version. `--check` reports drift and changes nothing. Always run it first |
| `status.sh [apps-dir]` | anywhere | One table: live version, TestFlight version, tag, PES version, drift and open PRs for every app. Read-only |
| `lint-project.sh <app>…` | anywhere | Build settings that compile but are wrong: literal Info.plist versions, missing `-ObjC`, remote packages, SYSKit vendored but unlinked |
| `validate.sh` | PES repo | Sanity-check this repo before release |
| `bump-version.sh <major\|minor\|patch>` | PES repo | Bump VERSION, stub CHANGELOG section, update README |
| `release.sh` | PES repo | Validate → commit → annotated tag vX.Y.Z (+ major alias) → push |

`update.sh` also syncs `SPM/SYSKit` and `SPM/SYSFirebase` into an app's
`App/Packages/`, and compares third-party package versions against `vendor.json`
— reporting drift without ever touching their contents.
