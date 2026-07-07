#!/bin/zsh
set -eu

repo_dir="${0:A:h:h}"
cd "$repo_dir"

zsh -n cli/* *.zsh *.sh tests/*.zsh
sh -n cli/remote-layout

for test in tests/*.zsh; do
  [[ "$test" == "tests/ci.zsh" ]] && continue
  zsh "$test"
done

jq . package.json
