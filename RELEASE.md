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

Installer and uninstaller smoke tests run with a temporary `HOME`, stubbed external commands, and the internal temporary Ghostty config override. Keep coverage for interactive and `--yes` flows, idempotency, conflict warnings, symlink refusal, safe runtime cleanup, non-destructive uninstall defaults, and explicit deletion flags. Experimental setup cleanup is manual/out-of-band for v0.1.

Before merging, sanity-check `.github/workflows/release.yml` for YAML validity in the repository's workflow tooling and confirm the draft release job still targets GitHub releases only.
