import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// A sample tree with `String` data, so every widget under test receives a
/// `DirectoryTreeController<String>` through its
/// `DirectoryTreeController<Object?>` parameter:
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
DirectoryTree<String> sampleTree() => DirectoryTree<String>.build(const [
  TreeEntry.file('/repo/lib/src/a.dart', data: 'a'),
  TreeEntry.file('/repo/lib/src/b.dart', data: 'b'),
  TreeEntry.file('/repo/lib/main.dart', data: 'main'),
  TreeEntry.file('/repo/test/main_test.dart', data: 'main test'),
  TreeEntry.file('/repo/README.md', data: 'readme'),
]);

const repo = NodeId('/repo');
const lib = NodeId('/repo/lib');
const mainDart = NodeId('/repo/lib/main.dart');
const testDir = NodeId('/repo/test');

/// The labels of [rows], for readable expectations.
List<String> labelsOf(Iterable<TreeRow<Object?>> rows) => [
  for (final row in rows) row.label,
];

/// Counts the notifications of a [Listenable].
final class NotificationCounter {
  NotificationCounter(Listenable listenable) {
    listenable.addListener(() => count++);
  }

  int count = 0;
}

/// Counts every widget build while installed, through
/// [debugOnRebuildDirtyWidget].
final class RebuildCounter {
  RebuildCounter.install() {
    debugOnRebuildDirtyWidget = (_, _) => count++;
  }

  int count = 0;

  void uninstall() => debugOnRebuildDirtyWidget = null;
}

/// A viewport that records the rows it was asked to show.
final class RecordingViewport implements DirectoryTreeViewport {
  final List<int> shown = <int>[];

  @override
  int get pageRowCount => 5;

  @override
  Future<void> showRow(
    int index, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  }) async {
    shown.add(index);
  }

  @override
  Rect? globalRowRect(int index) => null;
}
