#!/usr/bin/env bash
# update.sh — bring an app repo up to the current PES version.
#
# Usage:
#   update.sh --check <app-dir>    report drift, change nothing
#   update.sh <app-dir>            rewrite the managed files
#
# setup.sh creates an app and never overwrites anything, which is right for
# a new repo and useless for an existing one — it is why apps drift. This
# does the other half: it owns a fixed set of files and replaces them
# outright, leaving everything the app customises alone.
#
# Placeholders are re-rendered from the app itself, so there is nothing to
# keep in sync by hand.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PES_VERSION="$(tr -d '[:space:]' < "$PES_ROOT/VERSION")"

CHECK=0
if [[ "${1:-}" == "--check" ]]; then CHECK=1; shift; fi
TARGET="$(cd "${1:?usage: update.sh [--check] <app-dir>}" && pwd)"

# Whole directories PES owns, copied wholesale.
MANAGED_DIRS=(
  "App/Packages/SYSKit"
  "App/Packages/SYSFirebase"
)

# Files PES owns. Anything not listed here belongs to the app.
MANAGED=(
  ".github/workflows/pr.yml"
  ".github/workflows/main.yml"
  ".github/workflows/release.yml"
  ".github/dependabot.yml"
  ".github/PULL_REQUEST_TEMPLATE.md"
  ".github/ISSUE_TEMPLATE/bug-report.yml"
  ".github/ISSUE_TEMPLATE/feature-request.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  "App/ci_scripts/ci_post_clone.sh"
  "App/ci_scripts/ci_pre_xcodebuild.sh"
  "App/ci_scripts/ci_post_xcodebuild.sh"
  "scripts/ci/validate_screenshots.py"
  "scripts/ci/validate_analytics_events.py"
  "scripts/ci/validate_config.py"
  "App/Source/Shared/SYSConfig.swift"
  ".editorconfig"
  ".gitattributes"
  ".githooks/pre-commit"
  ".githooks/pre-push"
  ".githooks/commit-msg"
)

# Where each managed file comes from in templates/.
src_for() {
  case "$1" in
    .github/workflows/*)     echo "workflows/$(basename "$1")" ;;
    .github/ISSUE_TEMPLATE/*) echo "github/ISSUE_TEMPLATE/$(basename "$1")" ;;
    .github/*)               echo "github/$(basename "$1")" ;;
    App/ci_scripts/*)        echo "ci_scripts/$(basename "$1")" ;;
    scripts/ci/*)            echo "scripts/ci/$(basename "$1")" ;;
    App/Source/Shared/SYSConfig.swift) echo "app/SYSConfig.swift" ;;
    .editorconfig)           echo "assets/editorconfig" ;;
    .gitattributes)          echo "assets/gitattributes" ;;
    .githooks/*)             echo "githooks/$(basename "$1")" ;;
    *) return 1 ;;
  esac
}

# Values come from the app, never from a file you have to maintain.
detect() {
  PROJECT_NAME="$(find "$TARGET/App" -maxdepth 1 -name '*.xcodeproj' -exec basename {} .xcodeproj \; 2>/dev/null | head -1)"
  OWNER_REPO="$(git -C "$TARGET" remote get-url origin 2>/dev/null \
                 | sed -E 's|.*github\.com[:/]||; s|\.git$||')"
  OWNER="${OWNER_REPO%%/*}"
  REPO="${OWNER_REPO##*/}"
  FIREBASE_PROJECT_ID="$(python3 -c "
import json,sys
try:    print(json.load(open('$TARGET/.firebaserc'))['projects']['default'])
except Exception: print('')" 2>/dev/null)"

  BUNDLE_ID="$(sed -n 's/.*app_identifier *"\([^"]*\)".*/\1/p' "$TARGET/fastlane/Appfile" 2>/dev/null | head -1)"
  CONFIG_URL=""
  [[ -n "$FIREBASE_PROJECT_ID" ]] && CONFIG_URL="https://$FIREBASE_PROJECT_ID.web.app/config.json"

  [[ -n "$PROJECT_NAME" ]] || { echo "FAIL: no .xcodeproj under $TARGET/App" >&2; exit 1; }
  [[ -n "$OWNER_REPO"   ]] || { echo "FAIL: no github origin remote in $TARGET" >&2; exit 1; }
}

render() { # <template-src> -> stdout
  sed -e "s|{{PROJECT_NAME}}|$PROJECT_NAME|g" \
      -e "s|{{OWNER}}|$OWNER|g" \
      -e "s|{{REPO}}|$REPO|g" \
      -e "s|{{FIREBASE_PROJECT_ID}}|$FIREBASE_PROJECT_ID|g" \
      -e "s|{{BUNDLE_ID}}|$BUNDLE_ID|g" \
      -e "s|{{CONFIG_URL}}|$CONFIG_URL|g" \
      "$PES_ROOT/templates/$1"
}

detect
current="$(cat "$TARGET/.pes-version" 2>/dev/null | tr -d '[:space:]' || true)"

echo "$(basename "$TARGET"): PES ${current:-unknown} -> $PES_VERSION"
echo "  project=$PROJECT_NAME  repo=$OWNER/$REPO  firebase=${FIREBASE_PROJECT_ID:-none}"
echo

changed=0 missing=0
for rel in "${MANAGED[@]}"; do
  src="$(src_for "$rel")" || continue
  [[ -f "$PES_ROOT/templates/$src" ]] || continue

  if [[ ! -f "$TARGET/$rel" ]]; then
    echo "  ADD     $rel"; missing=$((missing+1))
  elif ! render "$src" | diff -q - "$TARGET/$rel" >/dev/null 2>&1; then
    echo "  UPDATE  $rel"; changed=$((changed+1))
  fi

  if [[ $CHECK -eq 0 ]]; then
    mkdir -p "$TARGET/$(dirname "$rel")"
    render "$src" > "$TARGET/$rel"
    [[ "$rel" == *.sh ]] && chmod +x "$TARGET/$rel"
  fi
done

# SYSKit and its Firebase adapter: ours, so they are replaced wholesale.
for rel in "${MANAGED_DIRS[@]}"; do
  src="$PES_ROOT/SPM/$(basename "$rel")"
  [[ -d "$src" ]] || continue

  if [[ ! -d "$TARGET/$rel" ]]; then
    echo "  ADD     $rel/"; missing=$((missing+1))
  elif ! diff -rq "$src" "$TARGET/$rel" >/dev/null 2>&1; then
    echo "  UPDATE  $rel/"; changed=$((changed+1))
  fi

  if [[ $CHECK -eq 0 ]]; then
    mkdir -p "$TARGET/$(dirname "$rel")"
    rm -rf "$TARGET/$rel"
    # .build and .swiftpm are local artefacts, never vendored.
    rsync -a --exclude '.build' --exclude '.swiftpm' "$src/" "$TARGET/$rel/"
  fi
done

# Third-party packages: report version drift, never touch contents. Apps
# deliberately vendor different product subsets — ABCLearning excludes Analytics
# for the Kids Category — so copying contents could break store compliance.
if [[ -f "$PES_ROOT/vendor.json" && -d "$TARGET/App/Packages" ]]; then
  while IFS='|' read -r name want; do
    [[ -n "$name" ]] || continue
    dir="$TARGET/App/Packages/$name"
    [[ -d "$dir" ]] || continue          # app does not use this package

    have=""
    [[ -f "$dir/.vendor-version" ]] && have="$(tr -d '[:space:]' < "$dir/.vendor-version")"
    if [[ -z "$have" ]]; then
      if [[ $CHECK -eq 1 ]]; then
        echo "  VENDOR  $name — no .vendor-version (would record $want)"
      else
        printf '%s\n' "$want" > "$dir/.vendor-version"
        echo "  VENDOR  $name — recorded $want"
      fi
    elif [[ "$have" != "$want" ]]; then
      echo "  VENDOR  $name  $have -> $want  (re-vendor by hand, then update .vendor-version)"
    fi
  done < <(python3 -c "
import json,sys
data = json.load(open('$PES_ROOT/vendor.json'))
for name, meta in data['packages'].items():
    print(f\"{name}|{meta['version']}\")
")
fi

# Workflow files PES no longer ships. Left in place, but called out —
# deleting a workflow is the app owner's call, not this script's.
if [[ -d "$TARGET/.github/workflows" ]]; then
  for f in "$TARGET/.github/workflows"/*.yml; do
    [[ -e "$f" ]] || continue
    name="$(basename "$f")"
    case "$name" in pr.yml|main.yml|release.yml) ;;
      *) echo "  EXTRA   .github/workflows/$name  (not part of PES $PES_VERSION — review and delete)" ;;
    esac
  done
fi

# Files the app owns but that started from a template: report only.
for rel in .gitignore .swiftlint.yml; do
  case "$rel" in
    .gitignore)     src="assets/gitignore" ;;
    .swiftlint.yml) src="assets/swiftlint.yml" ;;
  esac
  if [[ -f "$TARGET/$rel" ]] && ! diff -q "$PES_ROOT/templates/$src" "$TARGET/$rel" >/dev/null 2>&1; then
    echo "  DIFFERS $rel  (app-owned — check intentionally, not overwritten)"
  fi
done

# core.hooksPath is per-clone git config, not a file, so it cannot be copied —
# it has to be set. A repo with .githooks/ but no hooksPath looks protected and
# is not.
if git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1; then
  hooks_path="$(git -C "$TARGET" config core.hooksPath 2>/dev/null || true)"
  if [[ "$hooks_path" != ".githooks" ]]; then
    echo "  HOOKS   core.hooksPath is '${hooks_path:-unset}' — hooks are NOT active"
    if [[ $CHECK -eq 0 ]]; then
      git -C "$TARGET" config core.hooksPath .githooks
      chmod +x "$TARGET"/.githooks/* 2>/dev/null || true
      echo "  HOOKS   set core.hooksPath=.githooks"
    fi
  fi
fi

echo
if [[ $CHECK -eq 1 ]]; then
  echo "Check only. $changed to update, $missing to add. Re-run without --check to apply."
else
  printf '%s\n' "$PES_VERSION" > "$TARGET/.pes-version"
  echo "Updated to PES $PES_VERSION. Wrote .pes-version. Review the diff and commit."
fi
