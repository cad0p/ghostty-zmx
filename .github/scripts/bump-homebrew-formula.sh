#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "usage: $0 <tap-name> <tap-repo> <formula> <tag> <release-url> <pr-message> <auto-merge>" >&2
  exit 2
fi

tap_name="$1"
tap_repo="$2"
formula="$3"
tag="$4"
release_url="$5"
pr_message="$6"
auto_merge="$7"
version="${tag#v}"
repo="cad0p/${tap_repo}"
branch="homebrew-bump/${formula}-${version}"
workdir="$(mktemp -d)"

cleanup() {
  rm -rf "$workdir"
}
trap cleanup EXIT

enable_auto_merge() {
  local pr_number="$1"

  if [ "$auto_merge" != "true" ]; then
    echo "Auto-merge disabled for ${repo}#${pr_number}"
    return
  fi

  if [ "$(gh pr view "$pr_number" --repo "$repo" --json autoMergeRequest --jq '.autoMergeRequest')" = "null" ]; then
    gh pr merge "$pr_number" --repo "$repo" --auto --squash --delete-branch
  else
    echo "Auto-merge already enabled for ${repo}#${pr_number}"
  fi
}

export HOMEBREW_GITHUB_API_TOKEN="${HOMEBREW_APP_TOKEN:?HOMEBREW_APP_TOKEN is required}"
export GH_TOKEN="${HOMEBREW_APP_TOKEN}"

brew tap --force "$tap_name" "https://github.com/${repo}"
cd "$(brew --repository "$tap_name")"
if brew trust --help >/dev/null 2>&1; then
  brew trust --tap "$tap_name"
  brew trust --formula neurosnap/tap/zmx
fi
brew tap neurosnap/tap
if brew trust --help >/dev/null 2>&1; then
  brew trust --formula neurosnap/tap/zmx
fi

brew bump-formula-pr \
  --write-only \
  --commit \
  --no-audit \
  --no-browse \
  --no-fork \
  --force \
  --version "$version" \
  --message "$pr_message" \
  "${tap_name}/${formula}"

git remote set-url origin "https://x-access-token:${HOMEBREW_APP_TOKEN}@github.com/${repo}.git"
git push --force origin "HEAD:${branch}"

body="Update ${formula} to ${version}.\n\nRelease: ${release_url}"

if existing_pr="$(gh pr list --repo "$repo" --head "$branch" --json number --jq '.[0].number // empty')"; then
  if [ -n "$existing_pr" ]; then
    gh pr edit "$existing_pr" \
      --repo "$repo" \
      --title "chore: bump ${formula} to ${version}" \
      --body "$body"
    echo "Updated existing Homebrew bump PR: ${repo}#${existing_pr}"
    enable_auto_merge "$existing_pr"
    exit 0
  fi
fi

gh pr create \
  --repo "$repo" \
  --head "$branch" \
  --base main \
  --title "chore: bump ${formula} to ${version}" \
  --body "$body"

pr_number="$(gh pr list --repo "$repo" --head "$branch" --state open --json number --jq '.[0].number')"

echo "Created Homebrew bump PR: ${repo}#${pr_number}"
enable_auto_merge "$pr_number"
