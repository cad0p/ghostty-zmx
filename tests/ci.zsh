#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
cd "$repo_dir"

zsh -n session-manager-lib.zsh session-manager-early.zsh session-manager.zsh ghostty-zmx install.sh install-server.sh uninstall.sh e2e/setup-ghostty-tip.zsh tests/*.zsh
sh -n ghostty-zmx-remote-layout

for test in tests/*.zsh; do
  [[ "$test" == "tests/ci.zsh" ]] && continue
  zsh "$test"
done

jq . package.json
