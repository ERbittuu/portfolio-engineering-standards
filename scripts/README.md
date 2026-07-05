# Scripts

| Script | Run from | Purpose |
|---|---|---|
| `setup.sh [dir]` | anywhere | Copy the full parts box into an app repo (never overwrites; delete what the app doesn't use) |
| `validate.sh` | PES repo | Sanity-check this repo before release |
| `bump-version.sh <major\|minor\|patch>` | PES repo | Bump VERSION, stub CHANGELOG section, update README |
| `release.sh` | PES repo | Validate → commit → annotated tag vX.Y.Z (+ major alias) → push |
