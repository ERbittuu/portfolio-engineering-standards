# Portfolio Engineering Standards

This is my personal playbook for building and shipping iOS apps. I maintain
multiple apps alone, so I need every project to work the same way — same
folder structure, same automation, same release process. This repo is the
single source of truth for all of that.

Everything here comes from a real shipping app (Prarthana), not from
theory. If a rule is written here, it is because I actually use it in
production.

## How I use this repo

| File | When I open it |
|---|---|
| [PLAYBOOK.md](PLAYBOOK.md) | To remember how the system works — repo layout, CI/CD, releases, store automation. One read covers everything |
| [MIGRATE.md](MIGRATE.md) | When moving an app onto this system. Step by step, with a list of every problem I already hit so I don't hit it twice |
| [decisions/](decisions/) | When choosing between tools or Firebase services |
| [templates/](templates/) | Ready files that `scripts/setup.sh` copies into a new repo |

## My core rules

1. Keep it simple. If the current solution works, don't touch it.
2. Automate everything except what Apple forces a human to do.
3. **No remote packages. All dependencies live inside the repo** — source
   copies for Swift libraries, official binary zip for Firebase. Builds
   should never depend on someone else's server.
4. The git tag is the app version. Never store version numbers in the repo.
5. One private repo per app. App code, data, store content, automation —
   all in one place.

## Starting a new app

```sh
cd my-app && git init -b main
/path/to/portfolio-engineering-standards/scripts/setup.sh
# then follow MIGRATE.md
```

## Versioning this repo

Simple SemVer, see [VERSION](VERSION) and [CHANGELOG.md](CHANGELOG.md).
Release with `scripts/bump-version.sh` then `scripts/release.sh`.

Current version: **1.0.0**
