import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_context_menu.dart';
import 'package:flutter_directory_tree/src/menu/directory_tree_menu_details.dart';
import 'package:flutter_directory_tree/src/menu/open_tree_context_menu_intent.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sample tree; expanded, its rows are (index: label):
///
/// ```text
/// 0 repo
/// 1   lib
/// 2     src
/// 3       a.dart
/// 4       b.dart
/// 5     main.dart
/// 6   test
/// 7     main_test.dart
/// 8   README.md
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
const mainDart = NodeId('/repo/lib/main.dart');
const testDir = NodeId('/repo/test');
const readme = NodeId('/repo/README.md');

DirectoryTreeController<int> expandedController({
  bool Function(TreeNode<int> node)? selectable,
}) => DirectoryTreeController<int>(
  tree: sampleTree(),
  expansion: const ExpansionState.expanded(),
  selectable: selectable,
);

/// The height of a test row; row `i` spans `[30 * i, 30 * i + 30)`.
const double rowExtent = 30;

/// The size of the host, placed at the top-left corner of the 800 x 600
/// test window; the rest of the window is empty space outside the tree.
const Size hostSize = Size(300, 400);

/// How a test row turns a secondary click into [DirectoryTreeContextMenuState.open].
enum OpenTrigger {
  /// On the pointer up of a secondary tap (a later event than the down).
  secondaryTapUp,

  /// When the gesture arena gives the secondary tap to the row, in a
  /// microtask after the pointer down.
  secondaryTapDown,

  /// Synchronously in the pointer down dispatch, before the menu's own
  /// outside-tap handling sees the same event.
  pointerDown,
}

/// Intents of the test tree's own keys, to show that they stay inert while
/// the menu has keyboard focus.
class MoveDownIntent extends Intent {
  const MoveDownIntent();
}

class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}

/// A minimal tree view: the controller's rows as [rowExtent] tall rows.
class TestRows extends StatelessWidget {
  const TestRows({
    super.key,
    required this.controller,
    required this.trigger,
    this.onRowTap,
    this.onRowPointerDown,
  });

  final DirectoryTreeController<int> controller;
  final OpenTrigger trigger;
  final ValueChanged<NodeId>? onRowTap;
  final VoidCallback? onRowPointerDown;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final row in controller.rows)
          TestRow(
            key: ValueKey<NodeId>(row.id),
            row: row,
            trigger: trigger,
            onTap: onRowTap == null ? null : () => onRowTap!(row.id),
            onPointerDown: onRowPointerDown,
          ),
      ],
    ),
  );
}

class TestRow extends StatelessWidget {
  const TestRow({
    super.key,
    required this.row,
    required this.trigger,
    this.onTap,
    this.onPointerDown,
  });

  final TreeRow<int> row;
  final OpenTrigger trigger;
  final VoidCallback? onTap;

  /// Runs first on every pointer down (with [OpenTrigger.pointerDown]), as
  /// a tree that focuses itself on a click does.
  final VoidCallback? onPointerDown;

  @override
  Widget build(BuildContext context) {
    void openAt(Offset position) =>
        DirectoryTreeContextMenu.maybeOf<int>(context)!
            .open(row: row, globalPosition: position);
    final label = SizedBox(height: rowExtent, child: Text(row.label));
    return switch (trigger) {
      OpenTrigger.secondaryTapUp => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapUp: (details) => openAt(details.globalPosition),
        child: label,
      ),
      OpenTrigger.secondaryTapDown => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onSecondaryTapDown: (details) => openAt(details.globalPosition),
        child: label,
      ),
      OpenTrigger.pointerDown => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          onPointerDown?.call();
          if (event.buttons & kSecondaryMouseButton != 0) {
            openAt(event.position);
          }
        },
        child: GestureDetector(onTap: onTap, child: label),
      ),
    };
  }
}

/// A viewport that attaches itself to the controller like a tree view does
/// and reports [rectFor] as the global bounds of a row.
class FakeViewport extends StatefulWidget {
  const FakeViewport({
    super.key,
    required this.controller,
    required this.rectFor,
    required this.child,
  });

  final DirectoryTreeController<int> controller;
  final Rect? Function(int index) rectFor;
  final Widget child;

  @override
  State<FakeViewport> createState() => FakeViewportState();
}

class FakeViewportState extends State<FakeViewport>
    implements DirectoryTreeViewport {
  /// The indexes [globalRowRect] was asked for.
  final List<int> rectQueries = <int>[];

  @override
  void initState() {
    super.initState();
    widget.controller.attachViewport(this);
  }

  @override
  void didUpdateWidget(FakeViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detachViewport(this);
      widget.controller.attachViewport(this);
    }
  }

  @override
  void dispose() {
    widget.controller.detachViewport(this);
    super.dispose();
  }

  @override
  int get pageRowCount => 10;

  @override
  Future<void> showRow(
    int index, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  }) async {}

  @override
  Rect? globalRowRect(int index) {
    rectQueries.add(index);
    return widget.rectFor(index);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The bounds of row [index] of [TestRows] inside a host at the origin.
Rect rowRect(int index) =>
    Rect.fromLTWH(0, rowExtent * index, hostSize.width, rowExtent);

/// An app with a [DirectoryTreeContextMenu] of [hostSize] at the top-left
/// corner around a focusable [TestRows] (focus node [treeFocus]) whose keys
/// map Shift+F10 to [OpenTreeContextMenuIntent], the down arrow to a focus
/// move, and Escape to clearing the selection.
///
/// [viewportRect] adds a [FakeViewport]; [wrapTree] wraps the rows (for
/// example in a scroll view); [wrapHost] wraps the host; [outside] is
/// placed in the empty area to the right of the host.
Widget menuApp({
  required DirectoryTreeController<int> controller,
  required DirectoryTreeMenuBuilder<int> builder,
  FocusNode? treeFocus,
  OpenTrigger trigger = OpenTrigger.secondaryTapUp,
  TextDirection textDirection = TextDirection.ltr,
  Rect? Function(int index)? viewportRect,
  Widget Function(Widget rows)? wrapTree,
  Widget Function(Widget host)? wrapHost,
  Widget? outside,
  ValueChanged<NodeId>? onRowTap,
  VoidCallback? onRowPointerDown,
  Key? hostKey,
}) {
  Widget tree = TestRows(
    controller: controller,
    trigger: trigger,
    onRowTap: onRowTap,
    onRowPointerDown: onRowPointerDown,
  );
  if (wrapTree != null) tree = wrapTree(tree);
  if (viewportRect != null) {
    tree = FakeViewport(
      controller: controller,
      rectFor: viewportRect,
      child: tree,
    );
  }
  tree = Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.f10, shift: true):
          OpenTreeContextMenuIntent(),
      SingleActivator(LogicalKeyboardKey.arrowDown): MoveDownIntent(),
      SingleActivator(LogicalKeyboardKey.escape): ClearSelectionIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        MoveDownIntent: CallbackAction<MoveDownIntent>(
          onInvoke: (_) => controller.moveFocus(TreeFocusMove.next),
        ),
        ClearSelectionIntent: CallbackAction<ClearSelectionIntent>(
          onInvoke: (_) {
            controller.clearSelection();
            return null;
          },
        ),
      },
      child: Focus(focusNode: treeFocus, child: tree),
    ),
  );
  Widget host = DirectoryTreeContextMenu<int>(
    key: hostKey,
    controller: controller,
    builder: builder,
    child: tree,
  );
  if (wrapHost != null) host = wrapHost(host);
  return MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: Material(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: hostSize.width,
              height: hostSize.height,
              child: host,
            ),
            if (outside != null)
              Positioned(left: 400, top: 100, width: 300, child: outside),
          ],
        ),
      ),
    ),
  );
}

/// Records the menus a builder opened and the items chosen.
final class MenuLog {
  final List<DirectoryTreeMenuDetails<int>> opened =
      <DirectoryTreeMenuDetails<int>>[];
  final List<String> pressed = <String>[];

  /// Called by an item's onPressed with whether [treeFocus] had focus then.
  final List<bool> treeFocusedWhenPressed = <bool>[];

  /// A builder with the items `Rename <label>`, `Delete <node count>`, and
  /// `Copy path`; with [emptyFor], no items for the rows it accepts.
  DirectoryTreeMenuBuilder<int> builder({
    FocusNode? treeFocus,
    bool Function(TreeRow<int> row)? emptyFor,
  }) => (context, details) {
    opened.add(details);
    if (emptyFor != null && emptyFor(details.row)) return const <Widget>[];
    void press(String item) {
      pressed.add(item);
      if (treeFocus != null) {
        treeFocusedWhenPressed.add(treeFocus.hasPrimaryFocus);
      }
    }

    return [
      MenuItemButton(
        onPressed: () => press('rename ${details.row.label}'),
        child: Text('Rename ${details.row.label}'),
      ),
      MenuItemButton(
        onPressed: () => press('delete ${details.nodes.length}'),
        child: Text('Delete ${details.nodes.length}'),
      ),
      MenuItemButton(
        onPressed: () => press('copy path'),
        child: const Text('Copy path'),
      ),
    ];
  };
}

/// The state of the only [DirectoryTreeContextMenu] in the tree.
DirectoryTreeContextMenuState<int> menuState(WidgetTester tester) =>
    tester.state<DirectoryTreeContextMenuState<int>>(
      find.byType(DirectoryTreeContextMenu<int>),
    );

/// The center of the row of [id] in the test tree.
Offset rowCenter(WidgetTester tester, NodeId id) =>
    tester.getCenter(find.byKey(ValueKey<NodeId>(id)));

/// Clicks at [position] with a mouse [buttons], then lets the menu appear
/// (or go away) and focus settle.
Future<void> click(
  WidgetTester tester,
  Offset position, {
  int buttons = kPrimaryMouseButton,
}) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: buttons,
  );
  await gesture.addPointer(location: position);
  await gesture.down(position);
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
  await tester.pump();
  await tester.pump();
}

/// A secondary mouse click at [position].
Future<void> rightClick(WidgetTester tester, Offset position) =>
    click(tester, position, buttons: kSecondaryMouseButton);

/// Presses Shift+F10 and lets the menu appear and take focus; returns
/// whether a widget handled the F10 key.
Future<bool> pressShiftF10(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  final handled = await tester.sendKeyEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
  await tester.pump();
  return handled;
}

/// Sends [key] and lets the result settle.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
  await tester.pump();
}

/// The bounds of the menu item that shows [text].
Rect itemRect(WidgetTester tester, String text) =>
    tester.getRect(find.widgetWithText(MenuItemButton, text));

/// The bounds of the open menu's panel: the nearest [Material] above its
/// items.
Rect menuPanelRect(WidgetTester tester) => tester.getRect(
  find
      .ancestor(
        of: find.byType(MenuItemButton).first,
        matching: find.byType(Material),
      )
      .first,
);

/// Whether the menu item that shows [text] has keyboard focus.
bool itemHasFocus(WidgetTester tester, String text) =>
    Focus.of(tester.element(find.text(text))).hasPrimaryFocus;

/// The labels of the visible menu items, top to bottom.
List<String> menuLabels(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: find.byType(MenuItemButton),
            matching: find.byType(Text),
          )
          .evaluate())
    (element.widget as Text).data!,
];
