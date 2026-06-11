# Release control

ghostty-zmx uses `cad0p/semver-calver-release` for release control, with `package.json` as the SemVer base version source. This package is shell-only for v0.1 and does not publish to npm.

## Workflows

- `.github/workflows/test.yml` runs `zsh tests/ci.zsh` on pull requests and `main`.
- `.github/workflows/validate-package-version.yml` blocks non-release branches from changing `package.json` version and validates release-branch version format.
- `.github/workflows/release.yml` uses `cad0p/semver-calver-release/release@v1` for GitHub releases and draft changelog PR maintenance.

The release workflow supports the action's draft changelog PR flow:

1. Pushes to `main` create the normal calver prerelease and update `release/from-v0.1.0` with accumulated changelog entries.
2. Pushes to `release/from-v0.1.0` update that draft changelog branch only; they do not create tags or releases.
3. Merging `release/from-v0.1.0` to `main` creates the next base release from the curated `CHANGELOG.md` on that branch.

For step 1 to create or update the draft changelog PR automatically, the repository must allow GitHub Actions to create pull requests: GitHub repo settings → Actions → General → enable the setting for Actions-created pull requests.

## Pre-merge verification

Run these checks before publishing a release candidate:

```sh
zsh tests/ci.zsh
```

`tests/ci.zsh` runs shell syntax checks, the installer/uninstaller smoke test, scrollback snapshot coverage, restore id-map coverage, release-control coverage, and package metadata validation.

Installer and uninstaller smoke tests run with a temporary `HOME`, stubbed external commands, and the internal temporary Ghostty config override. Keep coverage for interactive and `--yes` flows, idempotency, conflict warnings, symlink refusal, safe runtime cleanup, non-destructive uninstall defaults, and explicit deletion flags. Experimental setup cleanup is manual/out-of-band for v0.1.

Before merging, sanity-check workflow YAML in the repository's workflow tooling and confirm release jobs still target GitHub releases only.
