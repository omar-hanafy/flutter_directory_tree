import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'integration_test_utils.dart';

void main() {
  testWidgets('shows the toolbar, the search field, and the tree', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          title: const Text('Explorer'),
          actions: [
            IconButton(
              tooltip: 'New file',
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        height: 400,
      ),
    );
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.byTooltip('New file'), findsOneWidget);
    expect(find.byType(DirectoryTreeSearchField), findsOneWidget);
    expect(rowOf(repo), findsOneWidget);
  });

  testWidgets('typing in the search field filters the rows', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(DirectoryTreePanel<int>(controller: controller), height: 400),
    );
    await tester.enterText(find.byType(TextField), 'main_test');
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller.query, 'main_test');
    expect(rowOf(mainTest), findsOneWidget);
    expect(rowOf(aDart), findsNothing);
  });

  testWidgets('Down in the search field moves into the tree', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(DirectoryTreePanel<int>(controller: controller), height: 400),
    );
    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'b.dart');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(controller.focusedId, bDart);
    // The tree has the keyboard: the next arrow moves in the rows.
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(controller.focusedId, src);
  });

  testWidgets('Ctrl+F (Cmd+F on Apple platforms) focuses the search field', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(controller: controller, autofocus: true),
        height: 400,
      ),
    );
    await tester.pump();
    final apple =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS;
    await pressWith(
      tester,
      apple ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyF,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasPrimaryFocus, isTrue);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('autofocus gives the tree the keyboard', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(controller: controller, autofocus: true),
        height: 400,
      ),
    );
    await tester.pump();
    // The tree took the focus and, with no focused row, focused the first
    // row without selecting it; the arrows move on from there.
    expect(controller.focusedId, repo);
    expect(controller.selection.isEmpty, isTrue);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(controller.focusedId, lib);
  });

  testWidgets('parts can be hidden or replaced', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          showSearch: false,
          toolbar: const Text('Custom toolbar'),
        ),
        height: 400,
      ),
    );
    expect(find.text('Custom toolbar'), findsOneWidget);
    expect(find.byType(DirectoryTreeToolbar), findsNothing);
    expect(find.byType(DirectoryTreeSearchField), findsNothing);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(controller: controller, showToolbar: false),
        height: 400,
      ),
    );
    expect(find.text('Custom toolbar'), findsNothing);
    expect(find.byType(DirectoryTreeToolbar), findsNothing);
    expect(find.byType(DirectoryTreeSearchField), findsOneWidget);
  });

  testWidgets('works without a Scaffold', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          title: const Text('Files'),
        ),
        height: 400,
        scaffold: false,
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), 'README');
    await tester.pump(const Duration(milliseconds: 200));
    expect(rowOf(readme), findsOneWidget);
  });

  testWidgets('the forwarded view parameters reach the view', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final activated = <NodeId>[];
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
          onActivate: (row) => activated.add(row.id),
          emptyBuilder: (context) => const Text('No files'),
        ),
        height: 400,
      ),
    );
    final view = tester.widget<DirectoryTreeView<int>>(
      find.byType(DirectoryTreeView<int>),
    );
    expect(view.checkboxMode, DirectoryTreeCheckboxMode.checks);
    await doubleClick(tester, rowCenter(tester, readme));
    expect(activated, [readme]);
    controller.query = 'nothing-matches';
    await tester.pump();
    expect(find.text('No files'), findsOneWidget);
  });

  testWidgets('the semantics labels reach the sliver', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          levelSemanticsHint: (level) => 'Ebene $level',
          activateSemanticsLabel: 'Öffnen',
          loadingSemanticsLabel: 'Wird geladen',
          loadFailedSemanticsLabel: 'Laden fehlgeschlagen',
        ),
        height: 400,
      ),
    );
    final sliver = tester.widget<SliverDirectoryTree<int>>(
      find.byType(SliverDirectoryTree<int>),
    );
    expect(sliver.levelSemanticsHint!(2), 'Ebene 2');
    expect(sliver.activateSemanticsLabel, 'Öffnen');
    expect(sliver.loadingSemanticsLabel, 'Wird geladen');
    expect(sliver.loadFailedSemanticsLabel, 'Laden fehlgeschlagen');
  });

  testWidgets('the default toolbar takes localized labels', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          expandAllTooltip: 'Alles ausklappen',
          collapseAllTooltip: 'Alles einklappen',
        ),
        height: 400,
      ),
    );
    expect(find.byTooltip('Alles ausklappen'), findsOneWidget);
    expect(find.byTooltip('Alles einklappen'), findsOneWidget);
    expect(find.byTooltip('Expand all'), findsNothing);
    await tester.tap(find.byTooltip('Alles einklappen'));
    await tester.pump();
    expect(controller.isExpanded(repo), isFalse);
  });

  testWidgets('selectionFollowsFocus reaches the view', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      hostApp(
        DirectoryTreePanel<int>(
          controller: controller,
          selectionFollowsFocus: false,
        ),
        height: 400,
      ),
    );
    final view = tester.widget<DirectoryTreeView<int>>(
      find.byType(DirectoryTreeView<int>),
    );
    expect(view.selectionFollowsFocus, isFalse);
  });
}
