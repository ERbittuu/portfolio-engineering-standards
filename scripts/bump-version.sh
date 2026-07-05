#!/usr/bin/env bash
# bump-version.sh — bump VERSION, stub a CHANGELOG section, update README.
# Usage: bump-version.sh <major|minor|patch>
# Then: fill in the CHANGELOG section and run release.sh.
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PES_ROOT"

part="${1:-}"
[[ "$part" =~ ^(major|minor|patch)$ ]] || { echo "Usage: bump-version.sh <major|minor|patch>" >&2; exit 1; }

old="$(tr -d '[:space:]' < VERSION)"
IFS=. read -r maj min pat <<<"$old"
case "$part" in
  major) new="$((maj + 1)).0.0" ;;
  minor) new="$maj.$((min + 1)).0" ;;
  patch) new="$maj.$min.$((pat + 1))" ;;
esac
today="$(date +%Y-%m-%d)"

printf '%s\n' "$new" > VERSION

# Insert a stub section above the previous latest entry.
awk -v new="$new" -v date="$today" '
  !inserted && /^## \[/ {
    print "## [" new "] - " date
    print ""
    print "### Added"
    print "- "
    print ""
    print "### Changed"
    print "- "
    print ""
    print "### Fixed"
    print "- "
    print ""
    inserted = 1
  }
  { print }
' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md

# Update the README version line.
sed -i '' "s/Current version: \*\*$old\*\*/Current version: **$new**/" README.md

echo "Bumped $old -> $new"
echo "Now edit CHANGELOG.md: fill in the [$new] section, delete empty subsections,"
echo "then run scripts/release.sh"
