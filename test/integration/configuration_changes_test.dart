import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

/// The states that must survive a configuration change: the scrollable
/// (scroll position) and the keyboard widget (type-ahead search).
(ScrollableState, State) treeStates(WidgetTester tester) => (
  tester.state<ScrollableState>(treeScrollable.first),
  tester.state(find.byType(DirectoryTreeKeyboard<int>)),
);

/// The scrollable of the tree, not of a search field.
final Finder treeScrollable = find.descendant(
  of: find.byType(DirectoryTreeView<int>),
  matching: find.byType(Scrollable),
);

ScrollPosition treePosition(WidgetTester tester) =>
    tester.state<ScrollableState>(treeScrollable.first).position;

/// Pumps every widget of [configurations] in turn and checks that the
/// scroll offset, the keyboard focus, and the tree's states survive each.
Future<void> expectStateKept(
  WidgetTester tester,
  List<(String, Widget)> configurations, {
  required FocusNode focusNode,
}) async {
  await tester.pumpWidget(configurations.first.$2);
  focusNode.requestFocus();
  await tester.pump();
  treePosition(tester).jumpTo(100 * rowExtent);
  await tester.pump();
  final states = treeStates(tester);
  for (final (name, widget) in configurations.skip(1)) {
    await tester.pumpWidget(widget);
    await tester.pump();
    expect(treePosition(tester).pixels, 100 * rowExtent, reason: name);
    expect(identical(treeStates(tester).$1, states.$1), isTrue, reason: name);
    expect(identical(treeStates(tester).$2, states.$2), isTrue, reason: name);
    expect(focusNode.hasPrimaryFocus, isTrue, reason: name);
  }
}

void main() {
  testWidgets('the view keeps its state when parts come and go', (
    tester,
  ) async {
    final controller = wideController(300);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final dnd = DirectoryTreeDragAndDrop<int>(onDrop: (_) {});
    List<Widget> menu(BuildContext context, DirectoryTreeMenuDetails<int> d) =>
        const [];
    Widget view({
      DirectoryTreeDragAndDrop<int>? dragAndDrop,
      DirectoryTreeMenuBuilder<int>? contextMenuBuilder,
      void Function(TreeRow<int>, Offset)? onRowSecondaryTap,
      String? semanticLabel,
      bool showScrollbar = true,
      EdgeInsetsGeometry? padding,
    }) => hostApp(
      DirectoryTreeView<int>(
        controller: controller,
        focusNode: focusNode,
        dragAndDrop: dragAndDrop,
        contextMenuBuilder: contextMenuBuilder,
        onRowSecondaryTap: onRowSecondaryTap,
        semanticLabel: semanticLabel,
        showScrollbar: showScrollbar,
        padding: padding,
      ),
    );
    await expectStateKept(tester, focusNode: focusNode, [
      ('plain', view()),
      ('drag and drop', view(dragAndDrop: dnd)),
      ('menu', view(dragAndDrop: dnd, contextMenuBuilder: menu)),
      ('no drag and drop', view(contextMenuBuilder: menu)),
      ('secondary tap only', view(onRowSecondaryTap: (_, _) {})),
      ('semantic label', view(semanticLabel: 'Files')),
      ('no scrollbar', view(semanticLabel: 'Files', showScrollbar: false)),
      ('padding', view(showScrollbar: false, padding: EdgeInsets.zero)),
      ('plain again', view()),
    ]);
  });

  testWidgets('the panel keeps its state when parts come and go', (
    tester,
  ) async {
    final controller = wideController(300);
    addTearDown(controller.dispose);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    Widget panel({bool showSearch = true, bool showToolbar = true}) => hostApp(
      DirectoryTreePanel<int>(
        controller: controller,
        focusNode: focusNode,
        showSearch: showSearch,
        showToolbar: showToolbar,
      ),
      height: 500,
    );
    await expectStateKept(tester, focusNode: focusNode, [
      ('plain', panel()),
      ('no search', panel(showSearch: false)),
      ('no toolbar', panel(showSearch: false, showToolbar: false)),
      ('search only', panel(showToolbar: false)),
      ('plain again', panel()),
    ]);
  });

  testWidgets('the picker keeps its state when the search field comes and '
      'goes', (tester) async {
    final tree = wideTree(300);
    Widget picker({bool showSearch = true}) => hostApp(
      DirectoryTreePicker<int>(
        tree: tree,
        showSearch: showSearch,
        initialExpansion: const ExpansionState.expanded(),
      ),
      height: 400,
    );
    await tester.pumpWidget(picker());
    treePosition(tester).jumpTo(100 * rowExtent);
    await tester.pump();
    final states = treeStates(tester);
    await tester.pumpWidget(picker(showSearch: false));
    expect(treePosition(tester).pixels, 100 * rowExtent);
    expect(identical(treeStates(tester).$1, states.$1), isTrue);
    await tester.pumpWidget(picker());
    expect(treePosition(tester).pixels, 100 * rowExtent);
    expect(identical(treeStates(tester).$2, states.$2), isTrue);
  });
}
