# Release control

ghostty-zmx uses `cad0p/semver-calver-release` for release control, with `package.json` as the SemVer base version source. This package is shell-only for v0.1 and does not publish to npm.

The `validate-package-version` workflow is intentionally deferred until after this first PR lands with `package.json` on `main`. That action reads `origin/main:package.json`, which does not exist before this PR is merged.

## Pre-merge verification

Run these checks before publishing a release candidate:

```sh
zsh -n session-manager.zsh install.sh uninstall.sh tests/*.zsh
jq . package.json
```

Installer and uninstaller smoke tests should run with a temporary `HOME`, stubbed external commands, and `GHOSTTY_ZMX_GHOSTTY_CONFIG` pointed at a temporary file. Cover interactive decline, `./install.sh --yes`, repeated install idempotency, migration cleanup of the old env line and exact experimental `confirm-close-surface = false`, valid-session migration, conflict warnings, `uninstall.sh --yes` preserving data/state/install directories, and explicit `--remove-install-dir --remove-data --remove-state` deletion flags.

Before merging, sanity-check `.github/workflows/release.yml` for YAML validity in the repository's workflow tooling and confirm the draft release job still targets GitHub releases only.
