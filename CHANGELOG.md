# Changelog

All notable changes to this project will be documented in this file.

## [calver-released]

<!-- USER-EDITABLE SECTION START -->
<!-- Add your curated release notes here. -->
<!-- USER-EDITABLE SECTION END -->

### 🚀 Features

- *(v0.2)* Remote SSH/tsh session inheritance ([#18](https://github.com/cad0p/ghostty-zmx/pull/18))
- *(v0.2)* Ship frozen v0.1 fallback manager for 1.3.x surfaces ([#20](https://github.com/cad0p/ghostty-zmx/pull/20))

### 🐛 Bug Fixes

- *(v0.2)* Correct widget error on unreachable host + newline formatting ([#21](https://github.com/cad0p/ghostty-zmx/pull/21))
- *(v0.2)* Stray poller self-heal, close-no-reopen, split-inherits-remote ([#25](https://github.com/cad0p/ghostty-zmx/pull/25))
- *(v0.2)* Record intercepted ssh handoffs in zsh history ([#26](https://github.com/cad0p/ghostty-zmx/pull/26))

### 🚜 Refactor

- *(v0.2)* Poller sources manager instead of inlining 400 lines of dup ([#23](https://github.com/cad0p/ghostty-zmx/pull/23))

### 📚 Documentation

- Document Homebrew install paths ([#17](https://github.com/cad0p/ghostty-zmx/pull/17))


## [0.1.4] - 2026-06-12

<!-- USER-EDITABLE SECTION START -->
Homebrew release publishing follow-up.

This release fixes the in-release Homebrew publisher so the local publishing action is checked out before it runs.
<!-- USER-EDITABLE SECTION END -->

### ⚙️ Miscellaneous Tasks

- Checkout before local Homebrew action ([#15](https://github.com/cad0p/ghostty-zmx/pull/15))


## [0.1.3] - 2026-06-12

<!-- USER-EDITABLE SECTION START -->
Homebrew publishing now runs as part of Auto Release.

This release removes manual Homebrew release workflows, publishes the correct tap directly after a tag is created, and fixes the bump helper used for signed auto-merged tap PRs.
<!-- USER-EDITABLE SECTION END -->

### ⚙️ Miscellaneous Tasks

- Avoid gh pr create --json for Homebrew bump PRs ([#11](https://github.com/cad0p/ghostty-zmx/pull/11))
- Always request Homebrew auto-merge ([#12](https://github.com/cad0p/ghostty-zmx/pull/12))
- Publish Homebrew from release workflow ([#13](https://github.com/cad0p/ghostty-zmx/pull/13))


## [0.1.2] - 2026-06-12

<!-- USER-EDITABLE SECTION START -->
Release-process hardening for Homebrew publishing.

This release adds stable and prerelease Homebrew workflows, preserves Tap Trust during formula bumps, signs Homebrew bump commits, and enables tap bump PR auto-merge after CI passes.
<!-- USER-EDITABLE SECTION END -->

### ⚙️ Miscellaneous Tasks

- Add Homebrew release automation ([#5](https://github.com/cad0p/ghostty-zmx/pull/5))
- Harden Homebrew release workflows ([#8](https://github.com/cad0p/ghostty-zmx/pull/8))
- Auto-merge Homebrew tap bump PRs ([#10](https://github.com/cad0p/ghostty-zmx/pull/10))


## [0.1.1] - 2026-06-11

<!-- USER-EDITABLE SECTION START -->
Release-process follow-up after the initial v0.1.0 package release.

This release wires up the draft changelog workflow, adds CI coverage for the shell-only implementation, and documents the upstream AppleScript/zmx references developers should keep open.
<!-- USER-EDITABLE SECTION END -->

### ⚙️ Miscellaneous Tasks

- Add release and test workflows ([#2](https://github.com/cad0p/ghostty-zmx/pull/2))
- Add release PR validation ([#4](https://github.com/cad0p/ghostty-zmx/pull/4))


