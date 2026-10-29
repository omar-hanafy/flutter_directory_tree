# flutter_directory_tree - agent guide (maintainers)

Flutter package: a virtualized, keyboard-first directory tree view built on
`package:directory_tree` (the pure-Dart core, a separate repository). The
public API is `lib/flutter_directory_tree.dart`, which re-exports ALL of
`package:directory_tree/directory_tree.dart` and this package's `lib/src/`
tree (controller, sliver and rows, keyboard, context menu, drag and drop,
search, theme, view, panel, picker). `lib/io.dart` is a second, optional
library with `FileSystemTreeLoader` and the core's `DirectoryScanner`; it
needs `dart:io` and is not available on the web.

The core owns all tree logic (`DirectoryTree`, `TreeRows`, `ExpansionState`,
`SelectionState`, `TreeQuery`). `DirectoryTreeController<T>` holds the
immutable core values for one view and swaps them on every command; widgets
read the controller and call its commands. Read the core's real code
before relying on its behavior, and fix core bugs in the core repository,
not here.

## Validation gates (run before claiming any change done)

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos              # every lint is a gate
dart run tool/check_repo.dart              # em-dash, changelog, platform imports, deprecations
dart fix test_fixes --compare-to-golden    # dart fix migrations stay valid
flutter test
flutter test --platform chrome             # compiled to JavaScript
CHROME_EXECUTABLE=/path/to/chrome flutter test --platform chrome --wasm
(cd example && flutter analyze --fatal-infos && flutter test)
flutter pub publish --dry-run              # must stay at 0 warnings
pana --flutter-sdk "$FLUTTER_ROOT" --exit-code-threshold 0 .
```

`--wasm` needs a Chrome with WebAssembly garbage collection; point
`CHROME_EXECUTABLE` at a recent Chrome for Testing build when the system
Chrome is not one.

CI (`.github/workflows/ci.yml`) runs all of these. It also runs the tests
on the minimum Flutter version with the lowest dependency versions, on
Windows and macOS, and on the beta channel, and it analyzes and tests every
package under `benchmark/`. "CI / Pana" requires a perfect score with a
pinned pana version, so avoid changes that cost points (missing doc
comments, dependency issues, format drift).

During development `pubspec_overrides.yaml` files point `directory_tree` at
a local checkout of the core. They are pub-ignored, and
`dart tool/check_repo.dart --release` fails while any of them exists, so
`flutter pub publish --dry-run` reports them until the release commit
deletes them. Never put a path dependency in `pubspec.yaml`.

`analysis_options.yaml` is strict; `test/analysis_options.yaml` relaxes
only documentation and API-shape rules. Never weaken a rule to get a green
run; fix the code, or add an `// ignore:` whose comment says why.

## Conventions

- Public API docs follow [docs_guide.md](docs_guide.md): the first sentence
  says what the declaration does or changes, then when to use it, then the
  contract (nulls, ranges, errors, complexity, side effects) with
  `[references]`. Members that throw say what they throw.
- Controller invariants, enforced by the controller tests:
  - Every command that changes observable state notifies exactly once,
    after all of its changes; a command that changes nothing does not
    notify.
  - Whenever listeners run, `rows` equal a full `DirectoryTree.flatten` of
    the effective state (`rows.expansion`, the effective filter,
    `compactFolders`, `showRoots`).
  - Unknown `NodeId`s are never an error: commands ignore them and queries
    answer `null`, `false`, -1, or an empty result.
- Performance: no O(n) work per frame, per focus change, or per selection
  change. Full passes happen only on a new tree, a filter change, and bulk
  commands. Traversals are iterative, since trees may be thousands of
  levels deep. Assert costs in tests with counters (builder calls, filter
  calls, rows touched), never with wall-clock time.
- No public getter or field of a non-widget class may expose a function
  type with `T` in a parameter position: it throws a `TypeError` when read
  through a `<Object?>` reference. Store such callbacks privately. Widget
  fields are exempt, as in Flutter.
- Only `lib/io.dart` and `lib/src/io/` may import `dart:io` (and
  `package:directory_tree/io.dart`). Nothing under `lib/` imports
  `dart:html`, `dart:js*`, `dart:ffi`, `dart:isolate`, or `dart:mirrors`.
  `tool/check_repo.dart` enforces this.
- User-visible strings come from `MaterialLocalizations` when Flutter has
  them; every other string is a constructor parameter with an English
  default.
- Never use the em-dash character in this repository's files; use `-`
  (`tool/check_repo.dart` enforces it).
- Every `@Deprecated` message says "removed in X.0.0";
  `tool/check_repo.dart` fails once the package reaches that major, so
  deprecations cannot outlive their release.
- Tests live in `test/`, in folders that mirror `lib/src/`. Use
  `@TestOn('vm')` only for code that needs `dart:io`.
- Every Dart block of README.md is copied verbatim into
  `test/readme_test.dart`, and every 2.0.0 block of MIGRATION.md into
  `test/migration_doc_test.dart` (1.x blocks start with
  `// flutter_directory_tree 1.x` and are skipped). The tests run or pump
  each block and check each `print(...); // output` comment, and the README
  keyboard table is compared with `DirectoryTreeShortcuts.defaults`. Edit
  an example in both places.
- A bug fix needs a regression test that fails on the old code.

## Breaking changes and `dart fix`

- Every rename ships a transform in `lib/fix_data.yaml` and a fixture pair
  in `test_fixes/` (`<case>.dart` compiles against the previous release,
  `<case>.dart.expect` is the hand-written result). Keep the transforms of
  earlier releases.
- Re-exported core renames need their own transforms here, with
  `uris: ['flutter_directory_tree.dart']`: the core's fix data reaches only
  files that import `package:directory_tree`.
- Only pure 1:1 renames belong in fix data. A rename whose result would
  compile but behave differently (for example a mutable 1.x call that is
  now an immutable value) is a manual step in MIGRATION.md.
- Prove a migration with the dart-tools data-driven-fixes verifier
  (`verify_fixes.py . --baseline <previous version>`): the fixtures compile
  against the baseline, and a separate consumer reaches every golden with
  no errors left.
- Breaking releases update MIGRATION.md (mapping, behavior changes,
  recipes) and the CHANGELOG entry in the same pull request.

## Release process

1. The version bump lands through a pull request to `main`. Branch
   protection requires "CI / Test on stable", "CI / Pana", and
   "pub-dry-run / dry-run"; there are no direct pushes.
2. The `CHANGELOG.md` entry and the `pubspec.yaml` version change in the
   same pull request. The first CHANGELOG heading must be the pubspec
   version (`tool/check_repo.dart` checks it).
3. The release commit deletes every `pubspec_overrides.yaml`, once the
   `directory_tree` version it needs is on pub.dev.
4. On merge, the auto-release workflow creates the tag
   `flutter_directory_tree-v<version>` and a GitHub release when the
   version value changed; the tag triggers trusted publishing to pub.dev
   (OIDC, no stored credentials). Never reuse or overwrite a tag.

## AI coding assistants

- Canonical tree: `tooling/ai/flutter-directory-tree/` with one shared
  `skills/` set (`use-flutter-directory-tree`,
  `migrate-flutter-directory-tree-v1-to-v2`), `assets/icon.png`, an
  `evals/` suite for `claude plugin eval`, and three manifests:
  `plugin.json` (Agent Plugins 1.0, read by Codex, Antigravity, and other
  Agent Plugins clients), `.claude-plugin/plugin.json` (Claude Code), and
  `.codex-plugin/plugin.json` (legacy, for older Codex releases). Catalogs:
  `.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json`
  at the repository root; Antigravity has no third-party marketplace and
  installs the plugin folder by its GitHub `tree/main/...` URL.
- All three manifests' `version` must equal the `pubspec.yaml` version,
  and their shared metadata must match; the Codex interface appears in
  `plugin.json` (`extensions["com.openai"].interface`) and in the legacy
  manifest, identically. `tool/validate_agent_plugin.dart` enforces this,
  plus the icon, the skill frontmatter and size limits, the eval layout,
  the install commands in README.md and the plugin README, and the
  `.pubignore` exclusions.
- Skill facts must match the source. `test/agent_skill_claims_test.dart`
  compiles every 2.x Dart block of the skills (blocks that start with
  `// flutter_directory_tree 1.x` are skipped), requires every API name a
  skill mentions to have a compiled use in its `_names` map (removed 1.x
  names go in `_v1Names`, words that are not API names in `_notApi`), and
  asserts the behavior the skills describe. When a change in `lib/` makes a
  skill wrong, fix the skill and the claims test in the same pull request.
- `tool/verify_agent_hosts.dart` installs the plugin in throwaway Claude
  Code, Codex, and Antigravity profiles (never the real ones) and requires
  the pubspec version and byte-identical skills; `--github <ref>` installs
  from GitHub the way users do. The Agent plugin workflow
  (`.github/workflows/agent-plugin.yml`) runs it on plugin pull requests
  and weekly with each host's current release; a weekly failure usually
  means a host changed its plugin contract. The plugin README's "Keeping it
  current" section is the refresh checklist.
- Both tools import only `dart:` libraries, so they run with plain `dart`
  and need no resolved dependencies:

  ```bash
  dart tool/validate_agent_plugin.dart
  dart tool/verify_agent_hosts.dart --require claude,codex,agy  # needs the three CLIs
  flutter test test/agent_skill_claims_test.dart
  ```

- A future breaking release ships a
  `migrate-flutter-directory-tree-vX-to-vY` skill before it is tagged.
- The plugin tree, `tool/`, and this file are excluded from the pub.dev
  archive by `.pubignore`; the catalogs live in hidden directories, which
  pub never archives.

## Files that are not published

`.pubignore` keeps `tool/`, `benchmark/`, this file, `CLAUDE.md`, and
`docs_guide.md` out of the pub.dev archive. `docs_guide.md` stays at the
repository root as the documentation standard.
