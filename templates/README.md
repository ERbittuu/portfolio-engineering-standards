# Templates

Battle-tested files copied into app repos by `scripts/setup.sh`. Every one
of these shipped in the reference app; comments inside each file explain
the non-obvious choices (usually a defused landmine — see MIGRATE.md).

| Folder | Contents | Copied to |
|---|---|---|
| `assets/` | gitignore, gitattributes, editorconfig, swiftlint, swiftformat, env.example | repo root (dot-prefixed) |
| `github/` | PR template, issue templates, dependabot | `.github/` |
| `workflows/` | ci-data, deploy-data, store-metadata, store-screenshots, release-tag | `.github/workflows/` |
| `ci_scripts/` | post_clone, pre_xcodebuild (tag→version), post_xcodebuild (dSYMs) | `App/ci_scripts/` |
| `fastlane/` | Fastfile, Deliverfile, Appfile, Gemfile, locale JSON template | `fastlane/` + root Gemfile |
| `docs/` | README / CHANGELOG / SECURITY skeletons | repo root |

After copying: replace every `{{PLACEHOLDER}}` (`git grep '{{'`), delete
what the app doesn't use (no Data pipeline → no data workflows, etc.).
Dotfiles are stored without the leading dot; setup.sh renames on copy.
