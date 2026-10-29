import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// The height of every test row.
const double rowExtent = 30;

/// The width of the test list.
const double listWidth = 400;

/// A small tree; with `/r/c` collapsed its rows are, from y = 0 in steps of
/// [rowExtent]: r, a, a1.txt, a2.txt, b, sub, s1.txt, b1.txt, c, top.txt.
DirectoryTree<Object?> sampleTree() => DirectoryTree.fromPaths(const [
  '/r/',
  '/r/a/a1.txt',
  '/r/a/a2.txt',
  '/r/b/b1.txt',
  '/r/b/sub/s1.txt',
  '/r/c/c1.txt',
  '/r/top.txt',
]);

/// A tree of ten folders `/r/d0` to `/r/d9` with ten files each, 111 rows
/// when expanded: r, d0, f00.txt to f09.txt, d1, and so on.
DirectoryTree<Object?> bigTree() => DirectoryTree.fromPaths([
  '/r/',
  for (var folder = 0; folder < 10; folder++)
    for (var file = 0; file < 10; file++) '/r/d$folder/f$folder$file.txt',
]);

/// A controller for [tree] with everything expanded except [collapsed].
DirectoryTreeController<Object?> controllerFor(
  DirectoryTree<Object?> tree, {
  List<String> collapsed = const [],
  DirectoryChildrenLoader<Object?>? loadChildren,
}) => DirectoryTreeController<Object?>(
  tree: tree,
  expansion: ExpansionState.withCollapsed([
    for (final path in collapsed) tree.idOf(path)!,
  ]),
  loadChildren: loadChildren,
);

/// The details a tree sliver would give the decorator of [row].
DirectoryTreeRowDetails<Object?> detailsFor(
  DirectoryTreeController<Object?> controller,
  TreeRow<Object?> row,
  int index,
) => DirectoryTreeRowDetails<Object?>(
  controller: controller,
  row: row,
  index: index,
  isSelected: controller.isSelected(row.id),
  isFocused: controller.focusedId == row.id,
  hasFocus: false,
  isHovered: false,
  checkboxMode: DirectoryTreeCheckboxMode.none,
  checkState: null,
  loadStatus: controller.loadStatusOf(row.id),
  isExpandable: controller.isExpandable(row.id),
  matchRanges: controller.matchRangesOf(row),
);

/// The rows of [controller] in a [CustomScrollView], each decorated with
/// [DirectoryTreeDragAndDropScope.decorateRow], as a tree sliver builds
/// them.
class DecoratedRows extends StatelessWidget {
  const DecoratedRows({
    super.key,
    required this.controller,
    this.scrollController,
    this.rowContent,
  });

  final DirectoryTreeController<Object?> controller;
  final ScrollController? scrollController;
  final Widget Function(TreeRow<Object?> row)? rowContent;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rows = controller.rows;
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverFixedExtentList(
              itemExtent: rowExtent,
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final row = rows[index];
                  return KeyedSubtree(
                    key: ValueKey<NodeId>(row.id),
                    child: DirectoryTreeDragAndDropScope.decorateRow(
                      context,
                      detailsFor(controller, row, index),
                      rowContent?.call(row) ?? Text(row.label),
                    ),
                  );
                },
                childCount: rows.length,
                findChildIndexCallback: (key) {
                  final id = (key as ValueKey<NodeId>).value;
                  final index = controller.rows.indexOfNode(id);
                  return index < 0 || controller.rows[index].id != id
                      ? null
                      : index;
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A test app: a [DirectoryTreeDragAndDropScope] around [DecoratedRows],
/// in a [listWidth] by [height] box at the top left of the screen.
class DndHost extends StatelessWidget {
  const DndHost({
    super.key,
    required this.controller,
    required this.dragAndDrop,
    this.onLongPressWithoutDrag,
    this.scrollController,
    this.rowContent,
    this.height = 600,
    this.textDirection = TextDirection.ltr,
  });

  final DirectoryTreeController<Object?> controller;
  final DirectoryTreeDragAndDrop<Object?> dragAndDrop;
  final void Function(TreeRow<Object?> row, Offset globalPosition)?
  onLongPressWithoutDrag;
  final ScrollController? scrollController;
  final Widget Function(TreeRow<Object?> row)? rowContent;
  final double height;
  final TextDirection textDirection;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Directionality(
          textDirection: textDirection,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: listWidth,
              height: height,
              child: DirectoryTreeDragAndDropScope<Object?>(
                controller: controller,
                dragAndDrop: dragAndDrop,
                onLongPressWithoutDrag: onLongPressWithoutDrag,
                child: DecoratedRows(
                  controller: controller,
                  scrollController: scrollController,
                  rowContent: rowContent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A long press reported by a scope.
typedef LongPress = ({TreeRow<Object?> row, Offset position});

/// Records what a scope reports, and finds rows by path.
final class DndRecorder {
  DndRecorder(this.controller);

  final DirectoryTreeController<Object?> controller;
  final List<DirectoryTreeDropDetails<Object?>> drops = [];
  final List<LongPress> longPresses = [];

  void onDrop(DirectoryTreeDropDetails<Object?> details) => drops.add(details);

  void onLongPress(TreeRow<Object?> row, Offset position) =>
      longPresses.add((row: row, position: position));

  NodeId id(String path) => controller.tree.idOf(path)!;

  Finder row(String path) => find.byKey(ValueKey<NodeId>(id(path)));
}

/// The paths of [nodes], for readable expectations.
List<String> pathsOf(Iterable<TreeNode<Object?>> nodes) => [
  for (final node in nodes) node.path.toString(),
];

/// Starts a mouse drag at [from] and moves it to [to] in one move.
Future<TestGesture> startMouseDrag(
  WidgetTester tester,
  Offset from,
  Offset to,
) async {
  final gesture = await tester.startGesture(
    from,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.moveTo(to);
  await tester.pump();
  return gesture;
}

/// Starts a touch long press at [from] and waits until it is recognized.
Future<TestGesture> startLongPress(WidgetTester tester, Offset from) async {
  final gesture = await tester.startGesture(from);
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
  return gesture;
}

/// The drop-target color of the theme of the (first) test rows.
Color dropTargetColorOf(WidgetTester tester) =>
    DirectoryTreeTheme.of(tester.element(find.byType(DecoratedRows).first))
        .dropTargetColor!;

/// Whether the row [finder] paints the drop-target tint.
bool isTinted(WidgetTester tester, Finder finder) {
  final color = dropTargetColorOf(tester);
  // The object behind PaintPattern is also the Matcher that `paints` is.
  final matcher = (paints..rect(color: color)) as Matcher;
  return matcher.matches(tester.renderObject(finder), <Object?, Object?>{});
}
