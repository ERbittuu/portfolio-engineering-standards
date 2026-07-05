#!/usr/bin/env bash
# validate.sh — sanity checks for the PES repo itself (run before release).
set -euo pipefail

PES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PES_ROOT"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# 1. Required files
for f in README.md PLAYBOOK.md MIGRATE.md CHANGELOG.md VERSION LICENSE SECURITY.md; do
  [[ -f "$f" ]] || err "missing $f"
done

# 2. VERSION / CHANGELOG / README consistency
version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "VERSION '$version' is not X.Y.Z"
grep -q "^## \[$version\]" CHANGELOG.md || err "CHANGELOG.md has no section for $version"
grep -q "Current version: \*\*$version\*\*" README.md || err "README version line != $version"

# 3. Shell templates and scripts parse
for s in scripts/*.sh templates/ci_scripts/*.sh; do
  bash -n "$s" || err "$s has syntax errors"
done
for s in scripts/*.sh; do [[ -x "$s" ]] || err "$s not executable"; done

# 4. Workflow YAML parses (ruby is always present on macOS)
for y in templates/workflows/*.yml templates/github/*.yml templates/github/ISSUE_TEMPLATE/*.yml; do
  ruby -ryaml -e "YAML.safe_load(File.read('$y'), aliases: true)" >/dev/null 2>&1 || err "$y invalid YAML"
done

# 5. Core docs contain no unresolved {{PLACEHOLDER}}
# (MIGRATE.md and templates/ legitimately mention the token syntax)
if grep -rnE '\{\{[A-Z][A-Z_]*\}\}' README.md PLAYBOOK.md decisions/ 2>/dev/null \
    | grep -v 'adr-template.md'; then
  err "placeholder tokens found in core docs"
fi

if [[ $fail -eq 0 ]]; then echo "OK: PES v$version validates clean."; else exit 1; fi
