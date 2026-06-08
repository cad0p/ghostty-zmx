# Release control

ghostty-zmx uses `cad0p/semver-calver-release` for release control, with `package.json` as the SemVer base version source. This package is shell-only for v0.1 and does not publish to npm.

The `validate-package-version` workflow is intentionally deferred until after this first PR lands with `package.json` on `main`. That action reads `origin/main:package.json`, which does not exist before this PR is merged.
