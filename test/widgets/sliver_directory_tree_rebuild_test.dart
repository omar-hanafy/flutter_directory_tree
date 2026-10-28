import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_utils.dart';

void main() {
  // Rows of expandedController(): 0 repo, 1 lib, 2 src, 3 a.dart,
  // 4 b.dart, 5 main.dart, 6 test, 7 main_test.dart, 8 README.md.

  testWidgets('selection changes rebuild only the rows whose details changed', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final counter = BuildCounter<int>();
    await tester.pumpWidget(
      treeApp(controller: controller, rowBuilder: counter.build),
    );
    expect(counter.take(), hasLength(9));

    controller.select(mainDart);
    await tester.pump();
    expect(counter.counts, {mainDart: 1});
    counter.take();

    // The old row loses selection and focus, the new one gains both.
    controller.select(readme);
    await tester.pump();
    expect(counter.counts, {mainDart: 1, readme: 1});
    counter.take();

    // Toggling adds aDart and moves the focus from readme.
    controller.toggleSelected(aDart);
    await tester.pump();
    expect(counter.take(), {aDart, readme});

    controller.extendSelection(mainDart);
    await tester.pump();
    // aDart stays selected and the anchor; bDart and mainDart join it,
    // readme leaves it, and the focus moves from aDart to mainDart.
    expect(counter.take(), {aDart, bDart, mainDart, readme});

    controller.clearSelection();
    await tester.pump();
    expect(counter.take(), {aDart, bDart, mainDart});
  });

  testWidgets('focus changes rebuild only the old and new focused rows', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final counter = BuildCounter<int>();
    await tester.pumpWidget(
      treeApp(controller: controller, rowBuilder: counter.build),
    );
    counter.take();

    controller.focus(bDart);
    await tester.pump();
    expect(counter.take(), {bDart});
    controller.moveFocus(
      TreeFocusMove.next,
      selection: TreeSelectionUpdate.keep,
    );
    await tester.pump();
    expect(counter.take(), {bDart, mainDart});
    controller.focus(null);
    await tester.pump();
    expect(counter.take(), {mainDart});
  });

  testWidgets('check changes rebuild the toggled row and the ancestors whose '
      'state changed', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final counter = BuildCounter<int>();
    await tester.pumpWidget(
      treeApp(
        controller: controller,
        rowBuilder: counter.build,
        checkboxMode: DirectoryTreeCheckboxMode.checks,
      ),
    );
    counter.take();

    controller.toggleChecked(aDart);
    await tester.pump();
    // a.dart checked; src, lib, and repo became partial.
    expect(counter.take(), {aDart, src, lib, repo});

    controller.toggleChecked(bDart);
    await tester.pump();
    // src became checked; lib and repo stay partial.
    expect(counter.take(), {bDart, src});

    controller.uncheckAll();
    await tester.pump();
    expect(counter.take(), {aDart, bDart, src, lib, repo});
  });

  testWidgets('notifications that change no visible row rebuild nothing', (
    tester,
  ) async {
    final controller = expandedController()..collapse(src);
    addTearDown(controller.dispose);
    final counter = BuildCounter<int>();
    await tester.pumpWidget(
      treeApp(controller: controller, rowBuilder: counter.build),
    );
    counter.take();

    // Selecting a hidden node notifies but changes no visible row.
    controller.select(aDart, focus: false);
    expect(controller.isSelected(aDart), isTrue);
    await tester.pump();
    expect(counter.take(), isEmpty);
    // So does the case sensitivity of an empty query.
    controller.caseSensitiveQuery = true;
    await tester.pump();
    expect(counter.take(), isEmpty);
    // And an unrelated rebuild of the app.
    await tester.pumpWidget(
      treeApp(controller: controller, rowBuilder: counter.build),
    );
    expect(counter.take(), isEmpty);
  });

  testWidgets('an incremental expansion builds only the new rows and the rows '
      'whose index or state changed', (tester) async {
    final controller = expandedController()..collapse(src);
    addTearDown(controller.dispose);
    final counter = BuildCounter<int>();
    await tester.pumpWidget(
      treeApp(controller: controller, rowBuilder: counter.build),
    );
    counter.take();

    controller.expand(src);
    await tester.pump();
    // src changed (expanded), a.dart and b.dart are new, and the rows
    // below moved down by two (their index is part of the details); repo
    // and lib above the change were not touched.
    expect(counter.take(), {
      src,
      aDart,
      bDart,
      mainDart,
      testDir,
      mainTest,
      readme,
    });
  });

  testWidgets('the tree gaining keyboard focus rebuilds the visible rows', (
    tester,
  ) async {
    final controller = expandedController()..select(readme);
    addTearDown(controller.dispose);
    final counter = BuildCounter<int>();
    final focusNode = FocusNode(debugLabel: 'tree');
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      treeApp(
        controller: controller,
        rowBuilder: counter.build,
        focusNode: focusNode,
      ),
    );
    expect(counter.details.every((details) => !details.hasFocus), isTrue);
    counter.take();

    // Focus changes apply in a microtask, so settle rather than pump once.
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    // Every row's details carry the tree focus.
    expect(counter.details.every((details) => details.hasFocus), isTrue);
    expect(counter.total, 9);
    expect(counter.take(), hasLength(9));

    focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(counter.details.every((details) => !details.hasFocus), isTrue);
    expect(counter.total, 9);
  });

  testWidgets('theme changes reach rows without new details', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(treeApp(controller: controller));
    Color? iconColor() => tester
        .widget<Icon>(
          find.descendant(of: rowOf(readme), matching: find.byType(Icon)),
        )
        .color;
    expect(iconColor(), isNot(Colors.pink));
    await tester.pumpWidget(
      treeApp(
        controller: controller,
        theme: testTheme.copyWith(iconColor: Colors.pink),
      ),
    );
    expect(iconColor(), Colors.pink);
  });
}
