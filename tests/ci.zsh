#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
cd "$repo_dir"

zsh -n session-manager-lib.zsh session-manager-early.zsh session-manager.zsh ghostty-zmx install.sh install-lib.sh install-dev.sh install-server.sh uninstall.sh tests/*.zsh
sh -n ghostty-zmx-remote-layout

for test in tests/*.zsh; do
  [[ "$test" == "tests/ci.zsh" ]] && continue
  zsh "$test"
done

jq . package.json
