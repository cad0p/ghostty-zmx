#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
workflow="$repo_dir/.github/workflows/release.yml"

jq -e '.name == "ghostty-zmx" and .version == "0.1.0" and .private == true and .license == "MIT"' "$repo_dir/package.json" >/dev/null
grep -q 'uses: cad0p/semver-calver-release/release@v1' "$workflow" || { print -u2 'release workflow action missing'; exit 1; }
grep -q 'contents: write' "$workflow" || { print -u2 'release workflow contents permission missing'; exit 1; }
grep -Eq "(^- main$|branches: \[main|['\"]main['\"])" "$workflow" || { print -u2 'release workflow main-branch trigger missing'; exit 1; }
grep -q 'validate-package-version' "$repo_dir/RELEASE.md" || { print -u2 'release docs do not explain deferred package-version validation'; exit 1; }
