#!/bin/sh
# Xcode Cloud pre-build script.
# Archive builds get: build number from CI_BUILD_NUMBER, marketing version
# from the tag (the tag IS the version — PLAYBOOK §5). No version numbers
# are ever committed to the repo.
set -e

if [ "$CI_XCODEBUILD_ACTION" = "archive" ]; then
  # agvtool operates on the project in the current directory; Xcode Cloud
  # starts scripts in ci_scripts/, so move to the project folder first.
  cd "$CI_PRIMARY_REPOSITORY_PATH/App"

  echo "Setting build number to $CI_BUILD_NUMBER"
  agvtool new-version -all "$CI_BUILD_NUMBER"

  if [ -n "$CI_TAG" ]; then
    case "$CI_TAG" in
      v[0-9]*.[0-9]*)
        echo "Setting marketing version from tag: ${CI_TAG#v}"
        agvtool new-marketing-version "${CI_TAG#v}"
        ;;
      *)
        echo "error: tag '$CI_TAG' does not match vX.Y[.Z] — refusing to archive" >&2
        exit 1
        ;;
    esac
  fi
fi
