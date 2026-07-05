#!/usr/bin/env bash
# release.sh — release the PES repo at the version in VERSION.
# Validates, commits pending release edits, tags vX.Y.Z (annotated),
# fast-forwards the major alias tag (vX) used by workflow callers, pushes.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PES_ROOT"

version="$(tr -d '[:space:]' < VERSION)"
tag="v$version"
major_tag="v${version%%.*}"

scripts/validate.sh

# CHANGELOG must not still contain empty stub bullets for this release
if awk "/^## \[$version\]/,/^## \[/" CHANGELOG.md | grep -q '^- *$'; then
  echo "FAIL: CHANGELOG section for $version still has empty '- ' bullets." >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "FAIL: tag $tag already exists. Bump the version first." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Committing release changes..."
  git add -A
  git commit -m "chore: release $tag"
fi

git tag -a "$tag" -m "PES $tag"
git tag -f "$major_tag" "$tag^{}"

echo
echo "Tagged $tag (and moved $major_tag)."
read -r -p "Push main + tags to origin? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  git push origin main
  git push origin "$tag"
  git push -f origin "$major_tag"
  echo "Pushed. Now create the GitHub Release for $tag with the CHANGELOG section."
else
  echo "Not pushed. When ready:"
  echo "  git push origin main '$tag' && git push -f origin '$major_tag'"
fi
