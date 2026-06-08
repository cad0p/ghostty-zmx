## Context

This is the implementation-fixer prompt for ghostty-zmx v0.1. The fixer applies accepted findings from the consolidated tracker only. Do not re-review the entire PR and do not address declined findings.

## Methodology

Read `/Users/piercarlocadoppi/Documents/personal/github/cad0p/Goldmine/open-source/github/pi-shipit/methodology.md` for discipline rules.

## Tracker

`features/ghostty-zmx/2026-06-08-pr1-feat-v0.1/deferred.md` is the canonical findings tracker. Your scope is only the rows assigned by the per-pass scope ticket.

## Commit discipline

- One cohesive change = one commit.
- Tests/checks green between commits.
- Push after each commit.
- Use `git add <specific>`, never `git add .`.
- Conventional commit subjects only.
- Do not use orchestration-internal vocabulary in commit subjects/bodies, source comments, README, or test names. Finding-ID footers in commit messages are allowed if useful.

## Do NOT

- Do not edit the user's real `.zshrc` or real Ghostty config.
- Do not open, close, merge, or mark the PR ready.
- Do not re-open declined findings unless your assigned change invalidates the tracker rationale; report that to the orchestrator instead.
- Do not address findings outside the per-pass scope ticket.

## When done

Report:

- Commit SHAs per assigned scope.
- Checks/tests run.
- Tracker rows you believe are fixed.
- Deviations or concerns.
- Push confirmation.
