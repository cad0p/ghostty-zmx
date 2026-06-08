# Release control

ghostty-zmx uses `cad0p/semver-calver-release` for release control, with `package.json` as the SemVer base version source. This package is shell-only for v0.1 and does not publish to npm.

The `validate-package-version` workflow is intentionally deferred until after this first PR lands with `package.json` on `main`. That action reads `origin/main:package.json`, which does not exist before this PR is merged.

## Pre-merge verification

Run these checks before publishing a release candidate:

```sh
zsh -n session-manager.zsh install.sh uninstall.sh tests/*.zsh
zsh tests/install-uninstall.zsh
zsh tests/snapshot-scrollback.zsh
zsh tests/restore-id-map.zsh
zsh tests/release-control.zsh
jq . package.json
```

Installer and uninstaller smoke tests should run with a temporary `HOME`, stubbed external commands, and `GHOSTTY_ZMX_TEST_GHOSTTY_CONFIG` pointed at a temporary file. Cover interactive decline, interactive acceptance, `./install.sh --yes`, repeated install idempotency, symlink refusal for install/data/state targets, stale runtime flag cleanup, conflict warnings, `uninstall.sh --yes` preserving data/state/install directories, interactive uninstall decline/acceptance, runtime-directory cleanup, and explicit `--remove-install-dir --remove-data --remove-state` deletion flags. Experimental setup cleanup is manual/out-of-band for v0.1 and is documented in the README/design rather than tested as installer migration behavior.

Before merging, sanity-check `.github/workflows/release.yml` for YAML validity in the repository's workflow tooling and confirm the draft release job still targets GitHub releases only.
