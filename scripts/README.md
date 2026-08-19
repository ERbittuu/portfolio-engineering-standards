# Scripts

| Script | Run from | Purpose |
|---|---|---|
| `setup.sh [dir]` | anywhere | Copy the full parts box into a **new** app repo (never overwrites; delete what the app doesn't use) |
| `update.sh [--check] <dir>` | anywhere | Bring an **existing** app up to this PES version. `--check` reports drift and changes nothing. Always run it first |
| `validate.sh` | PES repo | Sanity-check this repo before release |
| `bump-version.sh <major\|minor\|patch>` | PES repo | Bump VERSION, stub CHANGELOG section, update README |
| `release.sh` | PES repo | Validate → commit → annotated tag vX.Y.Z (+ major alias) → push |
