import 'dart:async';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts the notifications a controller sends.
final class NotificationCounter {
  NotificationCounter(this.controller) {
    controller.addListener(_onChange);
  }

  final ChangeNotifier controller;
  int count = 0;

  void _onChange() => count++;

  /// The notifications since the last call, resetting the count.
  int take() {
    final result = count;
    count = 0;
    return result;
  }
}

/// Runs [command] and returns how many notifications it sent.
int notificationsOf(ChangeNotifier controller, void Function() command) {
  final counter = NotificationCounter(controller);
  try {
    command();
    return counter.count;
  } finally {
    controller.removeListener(counter._onChange);
  }
}

/// One call of [FakeViewport.showRow].
typedef ShowRowCall = ({
  int index,
  Duration duration,
  Curve curve,
  double? alignment,
});

/// A viewport that records [showRow] calls.
final class FakeViewport implements DirectoryTreeViewport {
  FakeViewport({this.pageRowCount = 5});

  @override
  int pageRowCount;

  final List<ShowRowCall> shown = <ShowRowCall>[];

  @override
  Future<void> showRow(
    int index, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  }) async {
    shown.add((
      index: index,
      duration: duration,
      curve: curve,
      alignment: alignment,
    ));
  }

  @override
  Rect? globalRowRect(int index) => null;
}

/// One pending call of a [FakeLoader].
final class LoaderCall<T> {
  LoaderCall(this.directory);

  final DirectoryNode<T> directory;
  final Completer<Iterable<TreeEntry<T>>> completer =
      Completer<Iterable<TreeEntry<T>>>();

  bool get isPending => !completer.isCompleted;
}

/// A loader whose calls stay pending until the test completes them.
final class FakeLoader<T> {
  final List<LoaderCall<T>> calls = <LoaderCall<T>>[];

  Future<Iterable<TreeEntry<T>>> call(DirectoryNode<T> directory) {
    final call = LoaderCall<T>(directory);
    calls.add(call);
    return call.completer.future;
  }

  /// The calls made for [id], oldest first.
  List<LoaderCall<T>> callsFor(NodeId id) => [
    for (final call in calls)
      if (call.directory.id == id) call,
  ];

  List<LoaderCall<T>> get pending => [
    for (final call in calls)
      if (call.isPending) call,
  ];

  /// Completes the latest pending call for [id] with [entries].
  void complete(NodeId id, Iterable<TreeEntry<T>> entries) =>
      _latestPending(id).completer.complete(entries);

  /// Fails the latest pending call for [id] with [error].
  void fail(NodeId id, Object error) =>
      _latestPending(id).completer.completeError(error, StackTrace.current);

  LoaderCall<T> _latestPending(NodeId id) =>
      callsFor(id).lastWhere((call) => call.isPending);
}

/// Lets scheduled microtasks (loader calls, load completions) run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

/// The labels of [rows], for readable expectations.
List<String> labelsOf(Iterable<TreeRow<Object?>> rows) => [
  for (final row in rows) row.label,
];

/// The ids of [rows].
List<NodeId> idsOf(Iterable<TreeRow<Object?>> rows) => [
  for (final row in rows) row.id,
];

/// The effective filter the controller should use, computed from its public
/// state with the rules of the contract.
TreeFilter? effectiveFilterOf(DirectoryTreeController<Object?> controller) {
  final parsed = TreeQuery.parse(
    controller.query,
    caseSensitive: controller.caseSensitiveQuery,
  );
  final query = parsed.matchesAll ? null : parsed;
  final filter = controller.filter;
  final extra = filter == null || filter.matchesAll ? null : filter;
  if (query == null) return extra;
  if (extra == null) return query;
  return query.and(extra);
}

/// Expects the controller's rows to equal a fresh flatten of its state.
void expectConsistentRows(
  DirectoryTreeController<Object?> controller, {
  String reason = '',
}) {
  final rows = controller.rows;
  final filter = effectiveFilterOf(controller);
  final fresh = controller.tree.flatten(
    expansion: rows.expansion,
    filter: filter,
    expandMatches: false,
    compactFolders: controller.compactFolders,
    showRoots: controller.showRoots,
  );
  expect(identical(rows.tree, controller.tree), isTrue, reason: reason);
  expect(rows.compactFolders, controller.compactFolders, reason: reason);
  expect(rows.showRoots, controller.showRoots, reason: reason);
  expect(rows.filter, filter, reason: reason);
  expect(rows.length, fresh.length, reason: '$reason (row count)');
  for (var i = 0; i < rows.length; i++) {
    expect(rows[i], fresh[i], reason: '$reason (row $i)');
  }
}

/// A sample tree (case sensitive, minimal roots, directories first):
///
/// ```text
/// repo
///   lib
///     src
///       a.dart
///       b.dart
///     main.dart
///   test
///     main_test.dart
///   README.md
/// ```
DirectoryTree<int> sampleTree() => DirectoryTree<int>.build(const [
  TreeEntry.file('/repo/lib/src/a.dart', data: 1),
  TreeEntry.file('/repo/lib/src/b.dart', data: 2),
  TreeEntry.file('/repo/lib/main.dart', data: 3),
  TreeEntry.file('/repo/test/main_test.dart', data: 4),
  TreeEntry.file('/repo/README.md', data: 5),
]);

const repo = NodeId('/repo');
const lib = NodeId('/repo/lib');
const src = NodeId('/repo/lib/src');
const aDart = NodeId('/repo/lib/src/a.dart');
const bDart = NodeId('/repo/lib/src/b.dart');
const mainDart = NodeId('/repo/lib/main.dart');
const testDir = NodeId('/repo/test');
const mainTest = NodeId('/repo/test/main_test.dart');
const readme = NodeId('/repo/README.md');
const unknown = NodeId('/nowhere');
