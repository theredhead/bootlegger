# Bootlegger development

Read `CODEX_TASK_BOOTLEGGER.md` for product scope and `CODE_STYLE.md` for coding
conventions. Follow the checked-in Swift formatter and lint configurations.

Run `zsh swift-baseline.sh format`, then `zsh swift-baseline.sh check`, relevant tests,
and the app build when implementation exists. Keep generated and vendored code out
of these checks. Apple Music import verification is performed by the user; document
manual verification steps and report any unverified metadata behavior accurately.
