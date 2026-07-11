#!/usr/bin/env bash
# setup.sh — copy the PES parts box into an app repo.
#
# Usage: setup.sh [target-dir]      (default: current directory)
#
# Copies everything for a full app product (app + data + store automation).
# Never overwrites existing files — safe to re-run. Afterwards: replace
# {{PLACEHOLDER}}s, DELETE what the app doesn't use, follow MIGRATE.md.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$(cd "${1:-.}" && pwd)"
copied=0; skipped=0

copy() { # <template-relative-src> <target-relative-dest>
  local src="$PES_ROOT/templates/$1" dest="$TARGET/$2"
  if [[ -e "$dest" ]]; then echo "  skip   $2"; skipped=$((skipped+1)); return; fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  echo "  create $2"; copied=$((copied+1))
}

echo "PES v$(cat "$PES_ROOT/VERSION") → $TARGET"

# dotfiles
copy assets/gitignore      .gitignore
copy assets/gitattributes  .gitattributes
copy assets/editorconfig   .editorconfig
copy assets/swiftlint.yml  .swiftlint.yml
copy assets/swiftformat    .swiftformat
copy assets/env.example    .env.example

# docs
copy docs/README.template.md    README.md
copy docs/CHANGELOG.template.md CHANGELOG.md
copy docs/CLAUDE.template.md    CLAUDE.md

# github
copy github/PULL_REQUEST_TEMPLATE.md           .github/PULL_REQUEST_TEMPLATE.md
copy github/ISSUE_TEMPLATE/bug-report.yml      .github/ISSUE_TEMPLATE/bug-report.yml
copy github/ISSUE_TEMPLATE/feature-request.yml .github/ISSUE_TEMPLATE/feature-request.yml
copy github/ISSUE_TEMPLATE/config.yml          .github/ISSUE_TEMPLATE/config.yml
copy github/dependabot.yml                     .github/dependabot.yml

# workflows (delete the ones the app doesn't use)
for wf in ci-data deploy-data store-metadata store-screenshots \
          lint pr-guards validate-metadata validate-screenshots validate-release release-merge; do
  copy "workflows/$wf.yml" ".github/workflows/$wf.yml"
done

# Xcode Cloud scripts (must live beside the .xcodeproj)
for cs in ci_post_clone ci_pre_xcodebuild ci_post_xcodebuild; do
  copy "ci_scripts/$cs.sh" "App/ci_scripts/$cs.sh"
done
copy ci_scripts/lib/asc_build_number.rb "App/ci_scripts/lib/asc_build_number.rb"
chmod +x "$TARGET"/App/ci_scripts/*.sh "$TARGET"/App/ci_scripts/lib/*.rb 2>/dev/null || true

# PR-check scripts (used by validate-screenshots.yml / pr-guards.yml)
copy scripts/ci/validate_screenshots.py       scripts/ci/validate_screenshots.py
copy scripts/ci/validate_analytics_events.py  scripts/ci/validate_analytics_events.py

# fastlane
copy fastlane/Gemfile      Gemfile
copy fastlane/Fastfile     fastlane/Fastfile
copy fastlane/Appfile      fastlane/Appfile
copy fastlane/Deliverfile  fastlane/Deliverfile
copy fastlane/metadata-locale.template.json fastlane/metadata/en-US.json

echo
echo "Done: $copied created, $skipped skipped."
echo "Next: git grep -n '{{'   → fill placeholders"
echo "      delete unused parts (no Data/ → remove data workflows, etc.)"
echo "      then follow MIGRATE.md"
