#!/bin/sh
# Xcode Cloud pre-build script
# Runs before every archive build on Apple's CI servers.
#
# Versioning model (PLAYBOOK §5):
#   - The Release workflow triggers on pushes to release/X.Y.Z branches only
#     — never on tags. A tag is created once, after that branch merges to
#     main, purely as a permanent record. It never triggers a build.
#   - Marketing version comes straight from the branch name.
#   - Build number comes from App Store Connect itself: the last build
#     already uploaded for this exact version, plus one — or 1 if this is
#     the first build of the version.
#
# IMPORTANT CAVEAT, read before relying on this: Xcode Cloud maintains its
# own global, sequential build-number counter per app (App Store Connect →
# Xcode Cloud → Settings → Build Number) and OVERWRITES CFBundleVersion
# with it at archive/export time — regardless of what agvtool sets here.
# This isn't a toggle you can turn off, and it isn't exposed via the App
# Store Connect API. In practice: the code below still runs and still sets
# a value, and the marketing-version stamping half of it works correctly
# and matters — but the build number Apple actually ships with will climb
# forever from Xcode Cloud's own counter, not reset per version like the
# lookup below computes. Keep the lookup anyway (harmless, and correct if
# Apple ever exposes a way to disable their auto-numbering) but don't
# expect the "resets per version" property to actually hold. See
# MIGRATE.md's gotcha table.

set -e

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  # agvtool operates on the project in the current directory; Xcode Cloud
  # starts scripts in ci_scripts/, so move to the project folder first.
  cd "$CI_PRIMARY_REPOSITORY_PATH/App"

  case "$CI_BRANCH" in
    release/[0-9]*.[0-9]*.[0-9]*)
      VERSION="${CI_BRANCH#release/}"
      ;;
    *)
      echo "error: archive triggered from branch '$CI_BRANCH', not release/X.Y.Z — refusing to build" >&2
      exit 1
      ;;
  esac

  echo "Marketing version: $VERSION"
  agvtool new-marketing-version "$VERSION"

  BUILD=$(ruby "$CI_PRIMARY_REPOSITORY_PATH/App/ci_scripts/lib/asc_build_number.rb" "$VERSION" "{{BUNDLE_ID}}")
  echo "Build number (next after App Store Connect's last build for $VERSION): $BUILD"
  agvtool new-version -all "$BUILD"
fi
