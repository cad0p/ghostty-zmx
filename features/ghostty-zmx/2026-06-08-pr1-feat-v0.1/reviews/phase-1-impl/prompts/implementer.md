## Context

This is the implementation phase for ghostty-zmx v0.1. The repository is newly bootstrapped and draft PR #1 is already open. The canonical spec is locked and lives in this repo. Implement the zsh-only package that extracts the proven experimental Ghostty+zmx integration into installable files, with migration from the current experimental user config and release-grade docs/checklists.

## Canonical spec

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md` — READ IT IN FULL FIRST. Pay particular attention to Installation behavior, Migration from the experimental setup, Restore algorithm, Close cleanup and reaper, Scrollback snapshots, Reboot scrollback restore, E2E automation configuration, Locked decisions before implementation, and Release readiness criteria.

## Methodology

`/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md` — discipline rules apply.

## Working directory + branch

`/Users/piercarlocadoppi/Documents/open-source/github/cad0p/ghostty-zmx`

Branch: `feat/v0.1`, already pushed, with draft PR #1 open: https://github.com/cad0p/ghostty-zmx/pull/1. Push your commits to this branch. Do not open, close, merge, or mark the PR ready.

## Existing experimental implementation references

Read these as implementation references; do not edit them from the implementation subagent unless a test explicitly operates on disposable copies:

- Current experimental `.zshrc`: `/Users/piercarlocadoppi/.zshrc`
- Stable backup: `/Users/piercarlocadoppi/.zshrc.stable-zmx-ghostty`
- Final backup: `/Users/piercarlocadoppi/.zshrc.final`
- Current Ghostty config: `/Users/piercarlocadoppi/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

The current experimental config is intentionally old-form and must be supported by migration:

- inline `.zshrc` block headed `zmx session management` and ending with `# end zmx session management`,
- Ghostty config contains `env = ZMX_AUTO_ATTACH=1`,
- Ghostty config contains `confirm-close-surface = false`,
- runtime data is under `${XDG_DATA_HOME:-$HOME/.local/share}/zmx/`.

## Scope commits, one commit each

### Commit A: release metadata and workflow

Add release-control metadata using `cad0p/semver-calver-release`:

- add `package.json` with package name `ghostty-zmx`, version `0.1.0`, repository metadata, useful keywords, and no npm-publishing assumptions,
- add `.github/workflows/release.yml` using `cad0p/semver-calver-release/release@v1`, with no npm publish job,
- document in a short repo artifact or README draft note that `validate-package-version` is intentionally deferred until after this first PR lands with `package.json` on `main`, because that action reads `origin/main:package.json`,
- do not add the validation workflow in this PR unless you can prove it passes before `package.json` exists on `main`.

Tests/checks before committing: `jq . package.json` and workflow YAML sanity by inspection.

Commit subject: `chore: add release metadata`

### Commit B: package skeleton and session manager

Create the v0.1 package file layout in the repository. Extract the current stable zsh integration into `session-manager.zsh` with paths renamed from the experimental `zmx` namespace to `ghostty-zmx`:

- package source file location in the repo should be clear and mirrored by the installer into `~/.config/ghostty-zmx/session-manager.zsh`,
- managed data path defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/ghostty-zmx`,
- managed state/debug path defaults to `${XDG_STATE_HOME:-$HOME/.local/state}/ghostty-zmx`,
- runtime flags and generated scripts use `/tmp/ghostty-zmx-*`,
- auto-attach env var is `GHOSTTY_ZMX_AUTO_ATTACH=1`, not `ZMX_AUTO_ATTACH=1`,
- session naming uses full logical window/tab hex plus eight terminal characters,
- restore remains serial and queue-based,
- physical-to-logical id map is preserved,
- reaper only manages sessions listed in ghostty-zmx's managed `sessions` file.

Tests/checks before committing: `zsh -n` on the shell file.

Commit subject: `feat: add zsh session manager`

### Commit C: installer, uninstall, and migration

Add shell installer and uninstall scripts. They must be zsh/shell only and satisfy the design:

- interactive by default,
- `--yes` non-interactive mode,
- verify `zmx`, `osascript`, and `zsh`,
- install `session-manager.zsh` and `uninstall.sh` under `~/.config/ghostty-zmx/`,
- append one guarded source line to `.zshrc`, idempotently,
- detect and remove the experimental inline zmx block from `.zshrc`,
- manage only the `# BEGIN ghostty-zmx` / `# END ghostty-zmx` Ghostty config section,
- set `env = GHOSTTY_ZMX_AUTO_ATTACH=1`, `window-save-state = never`, and required `confirm-close-surface = true` inside that section,
- leave conflicting settings outside the managed section untouched and warn,
- remove or warn on `quit-after-last-window-closed = true`,
- copy old experimental `~/.local/share/zmx/sessions` to the new ghostty-zmx sessions file when present,
- do not migrate old queue/first/map runtime files,
- clean stale `/tmp/zmx-restore-*`, `/tmp/zmx-restoring-*`, `/tmp/zmx-reaper-*` flags,
- preserve live zmx sessions,
- print a reminder to clean up old experimental files after testing,
- save timestamped backups of edited files,
- uninstall removes the source line and managed Ghostty block, leaves sessions alive by default, and asks before deleting data/state directories.

Tests/checks before committing: syntax checks plus installer dry-run or temp-HOME tests for interactive-decline and `--yes` paths where practical.

Commit subject: `feat: add installer migration and uninstall`

### Commit D: debug logging

Add mandatory debug logging support controlled by `GHOSTTY_ZMX_DEBUG=1`:

- log path `${GHOSTTY_ZMX_STATE_HOME}/debug.log`,
- include shell init, path resolution, Ghostty PID detection, restore-driver election, session grouping, queue activity, AppleScript timing, id-map writes, reaper decisions, scrollback snapshots, reboot/fresh-session detection, and zmx print/attach failures,
- avoid logging terminal history contents.

Tests/checks before committing: syntax checks and a small temp test proving debug disabled creates no log and enabled writes event lines without full history content.

Commit subject: `feat: add debug logging`

### Commit E: scrollback snapshots

Implement reaper-owned snapshotting on detach:

- snapshot before kill or preserve decision,
- default to `GHOSTTY_ZMX_SCROLLBACK_LINES=1000`,
- write plain `.txt` files under `${GHOSTTY_ZMX_STATE_HOME}/history/<session>.txt`,
- use truncation at snapshot time,
- delete snapshot immediately for intentionally closed/unlogged sessions,
- keep/overwrite snapshot for Cmd-Q-shaped detach preservation.

Tests/checks before committing: syntax checks and any feasible function-level/temp-path test. Do not depend on live Ghostty for this commit unless needed.

Commit subject: `feat: snapshot managed scrollback`

### Commit F: reboot scrollback injection

Add missing/fresh session restore flow before attaching:

- detect whether the zmx session exists,
- if missing and snapshot exists, run `zmx run "$SESSION_NAME" true` or an equivalent tested primitive,
- inject exact banner and saved text using `zmx print`,
- attach only after injection attempt,
- log failures without printing history contents.

Exact banner:

`[ghostty-zmx restored saved scrollback from a previous boot; process state was not restored]`

Tests/checks before committing: syntax checks and a real zmx CLI smoke test if possible using disposable session names. Verify `zmx history` contains injected text after the flow.

Commit subject: `feat: restore saved scrollback into fresh sessions`

### Commit G: README and operational docs

Write README documentation for v0.1:

- tested environment including Ghostty 1.3.1 and zmx 0.6.x,
- install and uninstall,
- `--yes` mode,
- migration from experimental config,
- release control via `cad0p/semver-calver-release`,
- required Ghostty managed config and conflict-warning behavior,
- recommended but user-controlled Ghostty cwd inheritance settings,
- usage model,
- debug logging,
- state/data paths,
- close semantics,
- reboot scrollback semantics and limitations,
- unsupported `quit-after-last-window-closed = true`,
- SSH/remote support deferred to v0.2,
- cleanup reminder for old experimental files after testing.

Tests/checks before committing: grep README for stale `ZMX_AUTO_ATTACH` references; ensure no unsupported claim of live process reboot persistence.

Commit subject: `docs: document ghostty-zmx v0.1`

### Commit H: manual E2E checklist/scripts

Add durable manual E2E checklist or scripts/snippets covering the scenarios in the design:

- Cmd-Q restore,
- working-directory inheritance observation,
- pane close cleanup,
- window close cleanup,
- close all windows cleanup,
- Cmd-Q does not clean,
- reboot-scrollback simulation,
- unmanaged sessions not reaped,
- automated tests temporarily disabling `confirm-close-surface` and restoring the user's config afterward.

These can be docs/checklists plus helper scripts if safe. Avoid destructive actions without explicit user confirmation.

Tests/checks before committing: syntax checks for any scripts; docs mention E2E must run from iTerm2/outside managed Ghostty/zmx.

Commit subject: `test: add manual e2e checklist`

## Exit criteria

- All shell files pass `zsh -n` or `sh -n` as appropriate.
- Installer interactive and `--yes` paths have at least temp-HOME coverage or a clear documented manual verification path.
- The repository has a coherent v0.1 package layout.
- Commits are pushed to `feat/v0.1` after each commit.
- Report any deviations from the canonical spec with rationale.

## Commit discipline

- One scope commit per section above.
- Use `git add <specific>`, never `git add .`.
- Push after each commit.
- Tests/checks green between commits.
- SSH-signed Conventional Commits.

## When done

Report back:

- Commit SHAs per scope commit.
- Tests/checks run before and after.
- Deviations from spec and rationale.
- Concerns for reviewers.
- Confirmation commits are pushed to the draft PR branch.

## Do NOT

Do not use orchestration-internal vocabulary in commit subjects/bodies, source comments, README, or test names. Avoid tokens such as round identifiers, pass identifiers, finding IDs, design alternative labels, or implementation-scope numbering in user-facing artifacts. Commit subjects must be timeless Conventional Commit subjects.

Do not edit the user's real `.zshrc` or real Ghostty config as part of implementation tests. Use temp HOME / temp config fixtures unless the orchestrator explicitly instructs otherwise.

Do not open, close, merge, or mark the PR ready.

## Resources

- Canonical spec: `features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/design.md`
- Methodology: `/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md`
- PR: https://github.com/cad0p/ghostty-zmx/pull/1
- Current experimental `.zshrc`: `/Users/piercarlocadoppi/.zshrc`
- Current Ghostty config: `/Users/piercarlocadoppi/Library/Application Support/com.mitchellh.ghostty/config.ghostty`

Phase lens selection for subsequent review: correctness, coverage, cleanness/API surface, security/adversarial.

Time budget: 90 minutes. If budget is hit, stop at the last clean pushed commit and report what's left.
