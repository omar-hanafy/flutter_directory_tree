import 'workload.dart';

/// The result counts every implementation must report for a workload.
///
/// Each count follows from the paths alone, so every implementation (v1, v2,
/// and any later one) is checked against the same numbers. Subject tests
/// assert them, and the runner flags records that disagree.
class WorkloadExpectations {
  WorkloadExpectations._({
    required this.topLevelRows,
    required this.allRows,
    required this.toggleHiddenRows,
    required this.filterRows,
  });

  /// Derives the expected counts from [workload]'s paths. O(total path
  /// length).
  factory WorkloadExpectations(Workload workload) {
    const rootPrefix = '$workloadRoot/';
    final togglePrefix = '${workload.toggleTarget}/';
    final query = workload.filterQuery.toLowerCase();
    final topLevel = <String>{};
    final foldersBelowTarget = <String>{};
    final matchFolders = <String>{};
    for (final path in workload.paths) {
      final cut = path.indexOf('/', rootPrefix.length);
      topLevel.add(cut == -1 ? path : path.substring(0, cut));
      if (path.startsWith(togglePrefix)) {
        for (
          var i = path.indexOf('/', togglePrefix.length);
          i != -1;
          i = path.indexOf('/', i + 1)
        ) {
          foldersBelowTarget.add(path.substring(0, i));
        }
      }
      final name = path.substring(path.lastIndexOf('/') + 1).toLowerCase();
      if (name.contains(query)) {
        for (
          var i = path.indexOf('/', 1);
          i != -1;
          i = path.indexOf('/', i + 1)
        ) {
          matchFolders.add(path.substring(0, i));
        }
      }
    }
    return WorkloadExpectations._(
      topLevelRows: 1 + topLevel.length,
      allRows: workload.size + workload.folderCount,
      toggleHiddenRows:
          workload.toggleTargetFileCount + foldersBelowTarget.length,
      filterRows: workload.filterMatchCount + matchFolders.length,
    );
  }

  /// Rows after `build`: the top folder [workloadRoot] and its children.
  final int topLevelRows;

  /// Rows of the fully expanded tree: every folder (including
  /// [workloadRoot]) and every file.
  final int allRows;

  /// Rows that collapsing [Workload.toggleTarget] hides: every file and
  /// folder below it.
  final int toggleHiddenRows;

  /// Rows after `toggle`.
  int get toggleRows => allRows - toggleHiddenRows;

  /// Rows after `filter`: the matching files plus all their ancestor folders.
  final int filterRows;

  /// Row index of the `select_range` anchor in the fully expanded tree.
  int get selectRangeAnchor => allRows ~/ 4;

  /// Row index the `select_range` operation extends the selection to.
  int get selectRangeTarget => allRows * 3 ~/ 4;

  /// Selected rows after `select_range`.
  int get selectRangeCount => selectRangeTarget - selectRangeAnchor + 1;

  /// Checks the [counts] a subject reported for [operation].
  ///
  /// Returns one message per problem; an empty list means the counts are
  /// consistent. Counts the operation does not define (such as `nodes`, which
  /// differs between implementations) are ignored.
  List<String> check(String operation, Map<String, Object?> counts) {
    final problems = <String>[];
    void expectCount(String key, int expected) {
      final actual = counts[key];
      if (actual != expected) {
        problems.add('$key is $actual, expected $expected');
      }
    }

    switch (operation) {
      case 'build':
        expectCount('rows', topLevelRows);
      case 'expand_all':
        expectCount('rows', allRows);
      case 'toggle':
        expectCount('rows', toggleRows);
        expectCount('hidden_rows', toggleHiddenRows);
      case 'filter':
        expectCount('rows', filterRows);
      case 'select_range':
        expectCount('selected', selectRangeCount);
      case 'first_frame' || 'jump_middle' || 'jump_end':
        expectCount('rows', allRows);
        final built = counts['built_rows'];
        final first = counts['first_index'];
        final last = counts['last_index'];
        if (built is! int || first is! int || last is! int) {
          problems.add('built_rows, first_index, or last_index is missing');
          break;
        }
        if (built < 1 || last - first + 1 != built) {
          problems.add(
            'built_rows is $built, expected the contiguous rows '
            '$first..$last',
          );
        }
        final middle = allRows ~/ 2;
        if (operation == 'first_frame' && first != 0) {
          problems.add('first_index is $first, expected 0');
        } else if (operation == 'jump_middle' &&
            (first > middle || last < middle)) {
          problems.add('rows $first..$last do not contain the middle $middle');
        } else if (operation == 'jump_end' && last != allRows - 1) {
          problems.add('last_index is $last, expected ${allRows - 1}');
        }
      default:
        problems.add('unknown operation "$operation"');
    }
    return problems;
  }
}
