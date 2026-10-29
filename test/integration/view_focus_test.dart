import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

/// Records [controller.focusedId] at every notification.
List<NodeId?> recordFocus(DirectoryTreeController<Object?> controller) {
  final focused = <NodeId?>[];
  void record() => focused.add(controller.focusedId);
  controller.addListener(record);
  addTearDown(() => controller.removeListener(record));
  return focused;
}

void main() {
  group('the cursor when the tree gains the keyboard focus', () {
    for (final selectOnTap in [true, false]) {
      testWidgets('a click on an unfocused tree focuses only the clicked row '
          '(selectOnTap: $selectOnTap)', (tester) async {
        final controller = expandedController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          hostApp(
            DirectoryTreeView<int>(
              controller: controller,
              selectOnTap: selectOnTap,
            ),
          ),
        );
        final focused = recordFocus(controller);
        await click(tester, rowCenter(tester, readme));
        expect(focused, isNotEmpty);
        expect(focused.toSet(), {readme});
        expect(controller.focusedId, readme);
      });
    }

    testWidgets('a right-click on an unfocused tree focuses only that row', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        hostApp(
          DirectoryTreeView<int>(
            controller: controller,
            onRowSecondaryTap: (_, _) {},
          ),
        ),
      );
      final focused = recordFocus(controller);
      await rightClick(tester, rowCenter(tester, mainDart));
      expect(focused.toSet(), {mainDart});
    });

    testWidgets('Tab into the view shows the cursor on the first row', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final field = FocusNode();
      addTearDown(field.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: field),
                SizedBox(
                  height: 300,
                  child: DirectoryTreeTheme(
                    data: testTheme,
                    child: DirectoryTreeView<int>(controller: controller),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      field.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.focusedId, repo);
      expect(controller.selection.isEmpty, isTrue);
      final details = tester.widget<DirectoryTreeRow<int>>(
        find.descendant(
          of: rowOf(repo),
          matching: find.byType(DirectoryTreeRow<int>),
        ),
      );
      // The row draws the keyboard cursor.
      expect(details.details.isFocused, isTrue);
      expect(details.details.hasFocus, isTrue);
    });
  });
}
