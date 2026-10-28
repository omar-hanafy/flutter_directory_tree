import 'package:fdt_bench_workloads/workloads.dart';
import 'package:flutter/widgets.dart';

/// Called by a subject's row builder with the index of every row it builds.
typedef RowBuiltCallback = void Function(int index);

/// One implementation under test, created once per benchmark process.
///
/// The operations (see `benchOperations`) share one controller over the
/// workload, which the subject creates lazily so any operation can be the
/// first one a process runs (the runner restarts a process after a timeout
/// with the remaining operations):
///
/// * `build` creates a new controller from the paths in every run, with only
///   the top folder expanded. The last one may become the shared controller.
/// * Every later operation's [setUp] brings the shared controller to its
///   starting state: for `expand_all`, only the top folder expanded; for the
///   others, every folder expanded, no search query, and no selection.
///
/// Controller operations (`build`, `expand_all`, `toggle`, `filter`,
/// `select_range`): the harness calls [setUp], then [beforeRun] and [run]
/// for every warm-up and timed run, then [counts] and [tearDown]. Only [run]
/// is timed.
///
/// Frame operations (`first_frame`, `jump_middle`, `jump_end`): the harness
/// calls [setUp], mounts [buildView] in the benchmark host, times the frames
/// itself, and reads [viewRowCount]; then it calls [tearDown].
abstract class BenchSubject {
  /// Prepares [operation], without timing it.
  void setUp(String operation);

  /// Restores the starting state before each run of a controller operation,
  /// without timing it. Does nothing by default.
  void beforeRun(String operation) {}

  /// Performs the controller [operation] once. Only this call is timed.
  void run(String operation);

  /// The counts describing the result of the last [run] of [operation],
  /// computed without timing.
  ///
  /// Use the keys that `WorkloadExpectations.check` verifies: `rows` for
  /// `build`, `expand_all`, and `filter`; `rows` and `hidden_rows` for
  /// `toggle`; `selected` for `select_range`. Extra keys (such as `nodes`)
  /// are reported as is.
  Map<String, Object> counts(String operation);

  /// Called after an operation's last run, without timing. Does nothing by
  /// default.
  void tearDown(String operation) {}

  /// Builds the tree view over the shared, fully expanded controller.
  ///
  /// The view must use [scrollController] and call [onRowBuilt] with the row
  /// index every time it builds a row widget.
  Widget buildView({
    required ScrollController scrollController,
    required RowBuiltCallback onRowBuilt,
  });

  /// The number of rows the view built by [buildView] lists.
  int get viewRowCount;

  /// Releases the controllers. Called once, at the end. Does nothing by
  /// default.
  void dispose() {}
}

/// Creates the subject for a workload.
typedef SubjectFactory = BenchSubject Function(Workload workload);
