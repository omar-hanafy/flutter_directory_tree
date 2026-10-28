import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// The row height every test host uses, so positions are easy to compute.
const double rowExtent = 30;

/// The height of the scroll view in the test hosts: ten rows.
const double viewportHeight = 300;

/// The width of the scroll view in the test hosts.
const double viewportWidth = 400;

/// The theme of the test hosts: a fixed row height and no animations.
const DirectoryTreeThemeData testTheme = DirectoryTreeThemeData(
  rowExtent: rowExtent,
  animationDuration: Duration.zero,
);

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

/// The file name of row [i] of [wideTree]: `f0000.txt` and so on.
String wideName(int i) => 'f${i.toString().padLeft(4, '0')}.txt';

/// The id of row [i] of [wideTree] (row 0 is the directory `/w`).
NodeId wideId(int i) => NodeId('/w/${wideName(i)}');

const wideDir = NodeId('/w');

/// A directory `/w` holding [count] files `f0000.txt`, `f0001.txt`, ...,
/// plus [extra] files with the given names.
DirectoryTree<int> wideTree(int count, {List<String> extra = const []}) =>
    DirectoryTree<int>.build([
      for (var i = 0; i < count; i++) TreeEntry<int>.file('/w/${wideName(i)}'),
      for (final name in extra) TreeEntry<int>.file('/w/$name'),
    ]);

/// A controller over [wideTree] with `/w` expanded: row 0 is `w`, row
/// `i + 1` is file `i`.
DirectoryTreeController<int> wideController(int count) =>
    DirectoryTreeController<int>(
      tree: wideTree(count),
      expansion: const ExpansionState.expanded(),
    );

/// A controller over [sampleTree], every directory expanded:
///
/// 0 repo, 1 lib, 2 src, 3 a.dart, 4 b.dart, 5 main.dart, 6 test,
/// 7 main_test.dart, 8 README.md
DirectoryTreeController<int> expandedController({
  DirectoryChildrenLoader<int>? loadChildren,
}) => DirectoryTreeController<int>(
  tree: sampleTree(),
  expansion: const ExpansionState.expanded(),
  loadChildren: loadChildren,
);

/// A test app with a [SliverDirectoryTree] for [controller] inside a
/// [CustomScrollView] of [viewportWidth] x [height] at the top left of the
/// screen, optionally wrapped in a [Focus] with [focusNode].
Widget treeApp<T>({
  required DirectoryTreeController<T> controller,
  DirectoryTreeRowBuilder<T>? rowBuilder,
  DirectoryTreeRowDecorator<T>? rowDecorator,
  DirectoryTreeCheckboxMode checkboxMode = DirectoryTreeCheckboxMode.none,
  bool expandOnTap = true,
  bool selectOnTap = true,
  ValueChanged<TreeRow<T>>? onRowTap,
  ValueChanged<TreeRow<T>>? onActivate,
  void Function(TreeRow<T> row, Offset globalPosition)? onRowSecondaryTap,
  bool secondaryTapOnLongPress = true,
  String Function(int level)? levelSemanticsHint,
  List<Widget> before = const <Widget>[],
  List<Widget> after = const <Widget>[],
  EdgeInsetsGeometry? padding,
  double height = viewportHeight,
  TextDirection textDirection = TextDirection.ltr,
  FocusNode? focusNode,
  ScrollController? scrollController,
  DirectoryTreeThemeData theme = testTheme,
  bool disableAnimations = false,
  Key? sliverKey,
}) {
  Widget sliver = SliverDirectoryTree<T>(
    key: sliverKey,
    controller: controller,
    rowBuilder: rowBuilder,
    rowDecorator: rowDecorator,
    checkboxMode: checkboxMode,
    expandOnTap: expandOnTap,
    selectOnTap: selectOnTap,
    onRowTap: onRowTap,
    onActivate: onActivate,
    onRowSecondaryTap: onRowSecondaryTap,
    secondaryTapOnLongPress: secondaryTapOnLongPress,
    levelSemanticsHint: levelSemanticsHint,
  );
  if (padding != null) sliver = SliverPadding(padding: padding, sliver: sliver);
  Widget view = CustomScrollView(
    controller: scrollController,
    slivers: <Widget>[...before, sliver, ...after],
  );
  if (focusNode != null) view = Focus(focusNode: focusNode, child: view);
  return MaterialApp(
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: textDirection,
          child: DirectoryTreeTheme(
            data: theme,
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: viewportWidth,
                  height: height,
                  child: view,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The row widget of [id] (the sliver's keyed row item).
Finder rowOf(NodeId id) => find.byKey(ValueKey<NodeId>(id));

/// The default row drawn for [id].
Finder defaultRowOf<T>(NodeId id) =>
    find.descendant(of: rowOf(id), matching: find.byType(DirectoryTreeRow<T>));

/// The [DirectoryTreeRow] widget drawn for [id].
DirectoryTreeRow<T> defaultRowWidget<T>(WidgetTester tester, NodeId id) =>
    tester.widget<DirectoryTreeRow<T>>(defaultRowOf<T>(id));

/// The background decoration of the default row of [id].
BoxDecoration rowDecoration<T>(WidgetTester tester, NodeId id) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: defaultRowOf<T>(id),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return box.decoration as BoxDecoration;
}

/// The scroll position of the only scroll view on screen.
ScrollPosition scrollPositionOf(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable)).position;

/// The global top edge of the row of [id].
double rowTop(WidgetTester tester, NodeId id) =>
    tester.getTopLeft(rowOf(id)).dy;

/// Counts [DirectoryTreeRowBuilder] calls per row id.
final class BuildCounter<T> {
  final Map<NodeId, int> counts = <NodeId, int>{};
  final List<DirectoryTreeRowDetails<T>> details =
      <DirectoryTreeRowDetails<T>>[];

  /// A row builder that counts and draws the default row.
  Widget build(BuildContext context, DirectoryTreeRowDetails<T> details) {
    counts.update(details.row.id, (count) => count + 1, ifAbsent: () => 1);
    this.details.add(details);
    return DirectoryTreeRow<T>(details: details);
  }

  /// The ids built since the last call, then forgets them.
  Set<NodeId> take() {
    final ids = counts.keys.toSet();
    counts.clear();
    details.clear();
    return ids;
  }

  /// The total number of builds since the last [take].
  int get total => counts.values.fold(0, (sum, count) => sum + count);
}

/// A loader whose calls stay pending until the test completes them.
final class PendingLoader<T> {
  final Map<NodeId, Completer<Iterable<TreeEntry<T>>>> pending =
      <NodeId, Completer<Iterable<TreeEntry<T>>>>{};
  final List<NodeId> calls = <NodeId>[];

  Future<Iterable<TreeEntry<T>>> call(DirectoryNode<T> directory) {
    calls.add(directory.id);
    final completer = Completer<Iterable<TreeEntry<T>>>();
    pending[directory.id] = completer;
    return completer.future;
  }

  void complete(NodeId id, Iterable<TreeEntry<T>> entries) =>
      pending.remove(id)!.complete(entries);

  void fail(NodeId id, Object error) =>
      pending.remove(id)!.completeError(error, StackTrace.current);
}
