# Code style baseline

This is the initial formalization of conventions established in our previous projects.
The general principles apply across languages; the Swift section records the existing
Apple IIgs Player Builder baseline. Project-specific conventions belong in each
project's own guidance. Changes to this baseline should be explicit and reviewable.

## General principles

- Optimize for readability and maintainability. Give types, variables, and functions
  descriptive domain names; brevity is not a goal.
- Keep responsibilities cohesive and files focused. Separate presentation, domain
  policy, persistence, and platform integration. Moving a large class into extensions
  does not establish architectural separation.
- Apply SOLID principles pragmatically. Make dependencies and ownership explicit.
  Use narrow interfaces and dependency injection where substitution, testing, or
  resource ownership warrants them. Avoid speculative layers and abstractions.
- Prefer straightforward control flow. Make side effects and state changes apparent.
- Handle or propagate errors. Do not silently swallow failures. Give users actionable
  errors and keep sensitive data out of logs.
- Prefer existing platform and project facilities before introducing dependencies or
  custom infrastructure.
- Document intent, contracts, lifetime constraints, and surprising behavior. Avoid
  comments that merely repeat the code.
- Preserve persisted formats and user-visible behavior during readability refactors.
- Preserve unrelated local work; keep formatting and refactoring scoped to the task.
- Verify changes with configured checks, relevant behavioral tests, and the app build.
  Exclude generated and vendored code from first-party style enforcement.

## Swift

The checked-in `.swift-format` and `.swiftlint.yml` are copied from the established
`Emulation wrapper` baseline. Do not replace them with formatter defaults.

- Use four spaces and a 110-column target, with at most one consecutive blank line.
- Separate methods, type declarations, and logical sections with blank lines.
- Use one enum case and one variable declaration per line. Do not use semicolon-separated statements.
- Use lowerCamelCase members and UpperCamelCase types; preserve imported API names.
- Prefer explicit returns and straightforward loops where appropriate.
- Keep `///` documentation directly above its declaration and attributes. Put any
  separating blank line before the documentation, never between it and the declaration.
- Use descriptive domain files and focused extensions for navigation.
- Let swift-format own layout and naming. SwiftLint checks focused likely mistakes
  and documentation placement, without competing size or shorthand preferences.
- Wrap imported C APIs in focused native Swift adapters. Keep handles, pointers,
  constants, callbacks, and cleanup private. Expose Swift values, errors, and lifetime
  semantics; copy borrowed results and document thread affinity.

Run `zsh swift-baseline.sh format`, then `zsh swift-baseline.sh check`, relevant tests,
and the app build. The script discovers first-party code in `Sources`, `Tests`, and
`scripts`; update these paths if the project layout changes.

## Bootlegger application

- Use `nl.theredhead` as the base for app, helper, and test bundle identifiers.
- Keep document state and playback ownership independent for each project window.
- Keep project persistence separate from media playback, audio export, and views.
- Keep the original imported video unchanged; store the project's copy and metadata
  in its document bundle. Keep exported audio outside the bundle.

## Provenance

This baseline draws from the parent workspace's `AGENTS.md`, the `Emulation wrapper`
formatter and lint configuration, architecture guidance in Android Files and 86Box
Builder and Player, and naming/error-handling guidance in routeros-fleet. It does not
import project-specific UI frameworks, localization requirements, or old commit/push
authorizations. Future cross-project adoption should use this document as a starting
point and record intentional differences locally.
