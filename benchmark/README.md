# flutter_directory_tree benchmarks

Performance benchmarks that compare `flutter_directory_tree` 1.0.0 (the
release on pub.dev) with the 2.0.0 rewrite in this repository, on identical
generated inputs, through each version's public API, in two modes: JIT
(`flutter test`, debug mode) and AOT (a macOS app built in profile mode).

This directory is excluded from the published package (`.pubignore`) and from
the root analyzer (`analysis_options.yaml`). Every subdirectory is its own pub
package with its own `pubspec.yaml`, `pubspec.lock`, and
`analysis_options.yaml`.

| Directory | Contents |
|---|---|
| `workloads/` | Pure Dart. The seeded path generator ported from directory_tree's benchmarks (same algorithm, seeds, and fingerprints), the operation catalog, the line protocol between the processes and the runner, and `WorkloadExpectations`, the counts every operation must report. |
| `harness/` | Flutter. The `BenchSubject` interface, the driver (warm-up and timed runs, frame timing, JSON lines), and the two entry points: `defineJitBenchmark` (a widget test) and `runAotBenchmark` (an app that exits when it is done). |
| `v1/` | Flutter app. The subject for `flutter_directory_tree: 1.0.0` and `directory_tree: 1.0.0` from pub.dev, exactly. `macos/` is the runner of the AOT build. |
| `v2/` | Flutter app. The subject for the 2.0.0 code in this repository: `flutter_directory_tree` by path from the repository root, and directory_tree 2.0.0 from pub.dev. `macos/` is the runner of the AOT build. See [The v2 subject](#the-v2-subject). |
| `runner/` | Pure Dart CLI. Runs every implementation in both modes, enforces the per-step time budget, merges the records into `results.jsonl`, and writes `RESULTS.md`. |
| `RESULTS.md` | The latest report. |
| `results.jsonl` | Every stored record, one JSON object per line (the source of `RESULTS.md`). |

## Running

The full matrix (every implementation, mode, shape, and size):

```sh
cd benchmark/runner
dart pub get
dart run bin/run.dart
```

Useful flags (`dart run bin/run.dart --help` lists them all):

```sh
dart run bin/run.dart --modes aot                 # AOT only
dart run bin/run.dart --sizes 10k,100k            # skip the 1M workloads
dart run bin/run.dart --impls v2 --sizes 1m       # re-measure one column
dart run bin/run.dart --operations build,filter   # a subset of operations
dart run bin/run.dart --no-build                  # reuse the AOT app builds
dart run bin/run.dart --report-only               # rebuild RESULTS.md only
```

For each implementation `benchmark/<impl>` (an implementation without a
`pubspec.yaml` is skipped) the runner does this:

- JIT: `flutter pub get` once, then for every workload
  `flutter test --no-pub -r expanded bench/jit_bench_test.dart`.
- AOT (macOS only): `flutter pub get` and `flutter build macos --profile`
  once, then for every workload it launches
  `build/macos/Build/Products/Profile/<app>.app/Contents/MacOS/<app>`
  directly.

It passes the workload in the `FDT_BENCH_ARGS` environment variable, runs one
process per implementation, mode, and workload, one at a time, and keeps the
Mac and its display awake (`caffeinate`) while it runs. New records replace
stored ones with the same implementation, mode, shape, size, and operation,
so a subset can be re-measured without losing the rest; `--fresh` starts
over. `results.jsonl` is rewritten after every workload, so an interrupted
session keeps what it measured. Every record stores the machine, OS, Flutter
SDK, Dart version, and build mode it was measured with, and `RESULTS.md`
lists every environment that contributed.

One workload without the runner (no time budget then):

```sh
cd benchmark/v1
flutter pub get

# JIT
FDT_BENCH_ARGS="--shape deep --size 100k" flutter test bench/jit_bench_test.dart -r expanded

# AOT: build once, then launch the app directly (arguments or FDT_BENCH_ARGS)
flutter build macos --profile
build/macos/Build/Products/Profile/fdt_bench_v1.app/Contents/MacOS/fdt_bench_v1 --shape deep --size 100k

# AOT through the tool
FDT_BENCH_ARGS="--shape deep --size 100k" flutter run --profile -d macos --no-dds
```

`--no-dds` matters: the app exits as soon as it is done, and without the flag
the tool reports a crash when it cannot attach its development service to the
exited app (the records are printed anyway).

Arguments: `--shape deep|wide` (default `deep`), `--size` (`10000`, `100k`,
`1m`; default `10k`), `--runs` (default 5), `--warmup` (default 1), `--seed`,
and `--operations a,b,...` (default all). Each process prints one line per
event, `FDT_BENCH {json}` (macOS apps prefix it with `flutter: `): `start`,
`workload`, a `phase` before every step, a `record` per operation, and `done`.
See `workloads/lib/src/events.dart`.

## Checks (CI)

Each package's `test/` holds only cheap correctness checks (counts, ranges,
fingerprints; no timing assertions). The timing runs live outside `test/`
(`<impl>/bench/jit_bench_test.dart` and `<impl>/lib/main.dart`), so
`flutter test` never runs them.

| Package | Command | What it checks |
|---|---|---|
| `workloads/` | `dart test` | Fingerprints pinned at 10k, 100k, and 1M (equal to directory_tree's), the generator's properties, `WorkloadExpectations` against the row counts directory_tree's v1 and v2 benchmarks measured, the catalog, the line format. |
| `harness/` | `flutter test` | The driver with a reference subject built on plain lists: every operation reports the expected counts, the event sequence, failures and blocked operations, operations a subject cannot measure, frame measurement, `RowBuildProbe`, argument parsing. |
| `v1/` | `flutter test` | Every operation through the harness on deep and wide 10k: all counts equal `WorkloadExpectations`; the views build only the rows on screen. |
| `v2/` | `flutter test` | Every operation through the harness on deep and wide 10k: all counts equal `WorkloadExpectations`, and `nodes` is files plus folders; `toggle` is one incremental splice of exactly the hidden rows, reusing the other row objects; the frame operations are recorded as not available until the views land. |
| `runner/` | `dart test` | The watchdog (timeouts in every phase, restarts, blocked and unavailable operations, crashes) with scripted processes, killing a real process tree, the report. |

Every package is also clean under `dart format` and
`flutter analyze --fatal-infos` (`dart analyze --fatal-infos` for the pure
Dart `workloads/` and `runner/`).

## Workloads

`Workload.generate(shape, size, seed: ...)` returns `size` unique absolute
POSIX paths under `/repo`. It is a port of directory_tree's generator (its
own mulberry32 PRNG, so a seed gives the same list on every machine and SDK),
and `workloads/test/` pins the fingerprints to the values directory_tree's
suite records, so both suites measure the same trees.

- `deep`: project-like trees. Files sit 1-14 segments below `/repo` (most at
  7-14), directories hold about 5-30 entries, mixed extensions.
- `wide`: shallow trees. Files sit 2-3 segments below `/repo` in directories
  of about 1,000-3,000 files each at 10k, 3,000-9,500 at 100k, and
  10,000-30,000 at 1M.

Sizes: 10,000, 100,000, and 1,000,000 files. Each workload also defines a
toggle target (a directory near the middle holding 5-25% of the files) and a
filter query (`legacy`, a substring of about 3% of the file names and of no
directory name). `RESULTS.md` lists each workload's folder count, rows, depth,
toggle target, matches, and fingerprint; `dart run bin/stats.dart` in
`workloads/` prints more.

`WorkloadExpectations` derives from the paths alone the counts every
implementation must report (rows after each operation, the rows a jump must
land on). The subject tests assert them, and `RESULTS.md` lists every record
that disagrees.

## Operations

All operations go through one controller per process. `build` leaves the top
folder expanded; `expand_all` starts from that state; every later operation
starts from the fully expanded tree with no search query and no selection
(restored, untimed, by its set-up). A step that restores state before a run
(re-expanding the toggle target, clearing the query, selecting the anchor) is
never timed.

| Operation | Measured | 1.0.0 calls | Counts |
|---|---|---|---|
| `build` | Paths to a ready controller: build the tree, create the controller (top folder expanded). The `TreeEntry` list is created untimed. | `TreeBuilder().build(entries: ..., expandFoldersByDefault: false, selectNewFilesByDefault: false)`, then `DirectoryTreeController(data:, selection: SelectionController(mode: SelectionMode.multi))`; its `autoExpandVisibleRoot` expands `/repo`. | `rows` (top folder and its children), `nodes` |
| `expand_all` | Expand every folder. | `controller.expand(visibleRootId, recursive: true)`. | `rows` |
| `toggle` | Collapse the toggle target and update the rows. | `controller.toggle(id)` (a full re-flatten: 1.0.0 has no incremental update). | `rows`, `hidden_rows` |
| `filter` | Apply the search query. | `controller.filterQuery = 'legacy'`. | `rows` (matches plus ancestors) |
| `select_range` | Extend the selection from the row at 1/4 to the row at 3/4 (half the rows), as Shift+click does. | `selectOnly(anchor)` untimed, then `controller.selectRange(anchorId:, toId:)`. | `selected` |
| `first_frame` | The frame that mounts a tree view over the fully expanded tree, in an empty 400 x 600 box. | `DirectoryTreeView(controller:, scrollController:, nodeBuilder:)` with a `TreeNodeTile` row (Material icon from `MaterialIconProvider`, default label, tap selects). | `rows`, `built_rows`, `first_index`, `last_index` |
| `jump_middle` | With the view at the top (an untimed frame), `jumpTo(maxScrollExtent / 2)` and the frame after it. | Same view. | Same |
| `jump_end` | The same with `jumpTo(maxScrollExtent)`. | Same view. | Same |

1.0.0's builder marks every folder expanded and every file selected by
default, and its controller adopts both; the subject turns both off so the
controller starts the way 2.0.0's does. 1.0.0 also stores two extra nodes
(its hidden root and the "tree" container), so `nodes` is size + folders + 2
for v1.

## Measurement

- Controller operations: a `Stopwatch` around the one call, in the process's
  main isolate.
- Frame operations: the harness mounts `BenchHost` once (a `MaterialApp`
  whose only content is a 400 x 600 box at the top left, the same in the
  800 x 600 test surface and the 800 x 600 macOS window) and swaps the view
  under test into it. It times one frame on the UI thread, from the frame's
  first transient callback (registered before the change) to its first
  post-frame callback: animations, build, layout, paint, and compositing.
  It excludes the vsync wait and raster (GPU) time. In JIT that is the frame
  `WidgetTester.pump` runs, in AOT a real frame of the window. `built_rows`
  counts the rows built during that frame; `first_index` and `last_index`
  are their range.
- Modes: `jit` is `flutter test` (debug build, JIT compiler, asserts on,
  semantics off); `aot` is the macOS profile build (AOT compiler, asserts
  off). As a precaution the window stays above other windows and the app
  holds an activity that disables App Nap, since macOS may throttle a hidden
  or napping app.
- Each operation runs its warm-up runs (default 1) and its timed runs
  (default 5); the record has the median, minimum, and maximum in
  milliseconds.
- Time budget: every step (workload generation, an operation's set-up, each
  warm-up or timed run) must start within the budget (default 60 s,
  `--budget-ms`) of the previous one. The process prints a `phase` line before
  each step. When none arrives in time, the runner kills the process and every
  process it started (`flutter test` runs the test in a `flutter_tester` child
  next to a compiler process), records the operation with `timeout_ms` and
  `timeout_phase` instead of numbers, and starts a new process with the
  remaining operations. An operation whose prerequisites timed out or failed
  is recorded as blocked (`blocked_by`) rather than spending the budget
  again. A process that crashes fails the operation it was in.
- Unavailable operations: a subject whose implementation lacks the API for
  an operation (`BenchSubject.unavailableReason`) gets a record with
  `unavailable` (the reason) instead of numbers. It is not a failure: the
  process and the runner exit successfully, nothing is blocked by it,
  `RESULTS.md` shows "not available" with the reason in the details, and a
  later run that measures it replaces the record.

A record looks like this (one line in `results.jsonl`):

```json
{"implementation":"v1","mode":"aot","build_mode":"profile","shape":"deep","size":10000,"operation":"toggle","runs":5,"warmup":1,"seed":20261028,"fingerprint":"131893f6","median_ms":1.303,"min_ms":1.278,"max_ms":3.277,"rows":10647,"hidden_rows":898,"dart":"3.13.5 (stable) (Tue Sep 29 01:00:52 2026 -0700) on \"macos_arm64\"","budget_ms":60000,"machine":"Apple M2 Pro (arm64), 12 logical cores, 16 GB","os":"macOS 27.0.1 (26A434)","flutter":"Flutter 3.47.7 (stable, framework abaf9c5237, engine deb287481e)"}
```

## The v2 subject

`benchmark/v2` measures the 2.0.0 code in this repository. It was created
with `flutter create --empty --platforms=macos --project-name fdt_bench_v2
--org com.example v2` and given v1's `MainFlutterWindow.swift` (the
benchmark window settings) and `analysis_options.yaml`. Its `pubspec.yaml`
depends on the repository root by path, which resolves directory_tree 2.0.0
from pub.dev. `v1/` resolves directory_tree 1.0.0 from pub.dev, whose code
(`TreeBuilder`, `TreeData`, `VisibleNode`) does not exist in 2.0.0, so the
two subjects never share a lock file.

`lib/v2_subject.dart` runs the operations through the public 2.0.0 API,
from the same starting states as v1's subject:

| Operation | 2.0.0 calls |
|---|---|
| entries (untimed) | `[for (final p in workload.paths) TreeEntry<Never>.file(p)]` |
| `build` | `DirectoryTree<Never>.build(entries)`, then `DirectoryTreeController<Never>(tree:, expansion: ExpansionState.withExpanded([tree.idOf(workloadRoot)!]))`; counts `rows: controller.rows.length` and `nodes: tree.length` (files plus folders: 2.0.0 stores no extra nodes) |
| `expand_all` | before each run `controller..collapseAll()..expand(rootId)`; run `controller.expandAll()` |
| `toggle` | before each run re-expand the target when it is collapsed; run `controller.toggleExpansion(targetId)`, an incremental collapse (one splice of the target's rows, which the test checks) |
| `filter` | before each run `controller.query = ''`; run `controller.query = workload.filterQuery` |
| `select_range` | anchor and target are the ids of rows `length ~/ 4` and `length * 3 ~/ 4`; before each run `controller.select(anchor, focus: false)`; run `controller.extendSelection(target, focus: false)`; counts `selected: controller.selection.length` |
| views | `DirectoryTreeView<Never>(controller:, scrollController:, rowBuilder:)` under `DirectoryTreeTheme(data: DirectoryTreeThemeData(rowExtent: 28))`; each row is the default `DirectoryTreeRow` inside a `RowBuildProbe` |

`focus: false` matches 1.0.0, whose controller has no keyboard focus.

### The v2 views

The frame operations mount `DirectoryTreeView<Never>`, the widget an app
uses: the sliver with its keyboard handling and scrollbar. The rows have
1.0.0's 28 px height (`benchRowExtent`), so both versions show the same
rows. 2.0.0's default extent depends on the platform density (28 px on
macOS, 36 px in `flutter test`, whose default target is Android), which
would make the frame operations compare different amounts of content.
Rows are counted with `RowBuildProbe` (in `harness/lib/src/frames.dart`)
rather than in the `rowBuilder` closure: 2.0.0 caches row widgets per id,
so a remounted row may not call the builder again, but its probe still
builds. `v2/test/v2_subject_test.dart` checks the frame records the way
v1's test does: every record passes `WorkloadExpectations.check`, and
`built_rows` is within 22 to 42 (28 px rows in the 600 px box plus the
cache extent).

Measure both versions in one session, so the columns share the machine's
state:

```sh
dart run bin/run.dart --impls v1,v2
```

`RESULTS.md` then fills the v2 columns and the speedups (v1 / v2) for both
modes.

## Caveats

- Wall-clock numbers depend on the machine, its load, its thermal state, and
  power settings. Compare columns only when they come from the same
  environment and session, and close other heavy processes first. The v1
  baseline in `RESULTS.md` (2026-10-29) was measured while other development
  sessions were building and testing on the same machine (load average
  about 6 to 13 on 12 cores), so some medians are noisy, the JIT frame
  operations at 10k most of all; the fastest-run tables are steadier.
- JIT numbers are debug-mode numbers: asserts run (1.0.0's builder validates
  the whole tree in an assert), and debug widget code is slower. Use them to
  compare versions under `flutter test`, not as what users see.
- JIT medians of sub-millisecond operations can include JIT tiering: the
  first calls of a code path run before the compiler has optimized it, and
  one warm-up run is not always enough. For example, 2.0.0's `expand_all` on
  deep 10k took 7.7, 9.4, 0.95, and 2.0 ms on its first four calls and about
  0.3 ms from the fifth on. The fastest-run table is closer to the steady
  state, and AOT builds have no tiering; `--warmup 5` compares steady states
  in JIT.
- Garbage collection dominates the spread on the 100k and 1M workloads, so
  `RESULTS.md` also has a fastest-run table per mode.
- Frame operations measure UI-thread time only; raster (GPU) time is not
  included.
- The frame operations change no controller state, so they do not measure
  what a view does when the controller notifies. 1.0.0's `DirectoryTreeView`
  copies the whole row list and diffs it against the previous one on every
  notification, including selection changes; a frame-level selection
  operation would show that cost.
- `toggle` compares different algorithms on purpose: 1.0.0 re-flattens the
  whole tree, 2.0.0 updates the rows incrementally.
- `filter` uses a plain substring query; 1.0.0's `ext:` and `!` syntax is not
  exercised.
- AOT runs need a Mac with a display. The runner's `caffeinate` keeps it
  from sleeping; keep the screen unlocked too, since frame delivery to a
  locked session was not tested (a stalled frame shows up as a timeout).
  The app window floats above other windows while a run is in progress.
- Generator changes alter the fingerprints and invalidate stored results;
  regenerate everything (`--fresh`) after such a change.
