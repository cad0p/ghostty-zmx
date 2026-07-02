#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
cd "$repo_dir"

zsh -n session-manager-lib.zsh session-manager-early.zsh session-manager.zsh install.sh uninstall.sh tests/*.zsh

for test in tests/*.zsh; do
  [[ "$test" == "tests/ci.zsh" ]] && continue
  zsh "$test"
done

jq . package.json
