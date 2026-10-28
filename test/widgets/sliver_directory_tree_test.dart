import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row.dart';
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_utils.dart';

void main() {
  group('rows', () {
    testWidgets('builds one row per visible row, keyed by its id', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));

      final ids = [for (final row in controller.rows) row.id];
      expect(ids, hasLength(9));
      for (var i = 0; i < ids.length; i++) {
        expect(rowOf(ids[i]), findsOneWidget);
        expect(rowTop(tester, ids[i]), i * rowExtent);
        expect(
          tester.getSize(rowOf(ids[i])),
          const Size(viewportWidth, rowExtent),
        );
      }
      expect(find.text('README.md'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
      expect(find.byType(DirectoryTreeRow<int>), findsNWidgets(9));
    });

    testWidgets('uses SliverFixedExtentList with the theme row extent', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          theme: const DirectoryTreeThemeData(
            rowExtent: 24,
            animationDuration: Duration.zero,
          ),
        ),
      );
      final list = tester.widget<SliverFixedExtentList>(
        find.byType(SliverFixedExtentList),
      );
      expect(list.itemExtent, 24);
      expect(list.delegate.estimatedChildCount, 9);
      expect(rowTop(tester, readme), 8 * 24);
      // The delegate finds a row's index by its key, and only for the row
      // keyed by exactly that id.
      final delegate = list.delegate as SliverChildBuilderDelegate;
      expect(delegate.findChildIndexCallback!(ValueKey<NodeId>(readme)), 8);
      expect(
        delegate.findChildIndexCallback!(
          const ValueKey<NodeId>(NodeId('/nowhere')),
        ),
        isNull,
      );
    });

    testWidgets('moves the elements of rows that stay, by id', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      final readmeElement = tester.element(rowOf(readme));
      final mainElement = tester.element(rowOf(mainDart));

      controller.collapse(src);
      await tester.pump();
      expect(rowOf(aDart), findsNothing);
      expect(tester.element(rowOf(readme)), same(readmeElement));
      expect(tester.element(rowOf(mainDart)), same(mainElement));
      expect(rowTop(tester, readme), 6 * rowExtent);

      // A reset that reorders rows keeps them too.
      controller.collapseAll();
      await tester.pump();
      controller.expandAll();
      await tester.pump();
      expect(rowTop(tester, readme), 8 * rowExtent);
      expect(find.byType(DirectoryTreeRow<int>), findsNWidgets(9));
    });

    testWidgets('100k rows build only the visible window while jumping', (
      tester,
    ) async {
      const count = 100000;
      final controller = wideController(count);
      addTearDown(controller.dispose);
      final counter = BuildCounter<int>();
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          rowBuilder: counter.build,
          scrollController: scroll,
        ),
      );
      expect(controller.rows, hasLength(count + 1));
      // The viewport shows 10 rows; the default cache extent (250 px) adds
      // at most 9 rows after them at the top of the list.
      const window = 10 + 9 + 2;
      expect(counter.take().length, lessThanOrEqualTo(window));

      for (final target in [50000, 99990, 1234, 77777]) {
        scroll.jumpTo(target * rowExtent);
        await tester.pump();
        final built = counter.take();
        // A jump far away builds a fresh window: rows above it in the
        // cache extent, the visible rows, and rows below in the cache.
        expect(built.length, lessThanOrEqualTo(window + 9), reason: '$target');
        final children = tester
            .renderObject<RenderSliverFixedExtentList>(
              find.byType(SliverFixedExtentList),
            )
            .childCount;
        expect(children, lessThanOrEqualTo(window + 9), reason: '$target');
        final first = target > count - 9 ? count - 9 : target;
        expect(
          find.text(wideName(first)),
          findsOneWidget,
          reason: 'row of file $first is on screen',
        );
      }
    });

    testWidgets('an empty tree builds no rows', (tester) async {
      final controller = DirectoryTreeController<int>();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      expect(find.byType(DirectoryTreeRow<int>), findsNothing);
      controller.tree = sampleTree();
      await tester.pump();
      expect(find.byType(DirectoryTreeRow<int>), findsOneWidget);
    });
  });

  group('row builder and decorator', () {
    testWidgets('rowBuilder replaces the default row', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          rowBuilder: (context, details) =>
              Text('#${details.index} ${details.row.label}'),
        ),
      );
      expect(find.byType(DirectoryTreeRow<int>), findsNothing);
      expect(find.text('#8 README.md'), findsOneWidget);
    });

    testWidgets('rowDecorator wraps the interactive row', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final decorated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          rowDecorator: (context, details, child) {
            decorated.add(details.row.id);
            return ColoredBox(
              key: ValueKey<String>('decorated ${details.row.id.value}'),
              color: Colors.transparent,
              child: child,
            );
          },
        ),
      );
      expect(decorated, hasLength(9));
      final box = find.byKey(ValueKey<String>('decorated ${readme.value}'));
      expect(box, findsOneWidget);
      // The decorator sits outside the click handling, so a click on it
      // still reaches the row.
      await tester.tap(box);
      expect(controller.selection.selected, {readme});
    });

    testWidgets('a new rowBuilder rebuilds every row', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          rowBuilder: (context, details) => Text('a ${details.row.label}'),
        ),
      );
      expect(find.text('a README.md'), findsOneWidget);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          rowBuilder: (context, details) => Text('b ${details.row.label}'),
        ),
      );
      expect(find.text('a README.md'), findsNothing);
      expect(find.text('b README.md'), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('each row is a node with its label, state, and level', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController()..select(lib);
      addTearDown(controller.dispose);
      controller.collapse(src);
      await tester.pumpWidget(treeApp(controller: controller));

      expect(
        tester.getSemantics(rowOf(lib)),
        matchesSemantics(
          label: 'lib',
          hint: 'Level 2',
          isSelected: true,
          hasSelectedState: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(rowOf(src)),
        matchesSemantics(
          label: 'src',
          hint: 'Level 3',
          hasSelectedState: true,
          hasExpandedState: true,
          hasTapAction: true,
        ),
      );
      // Files have no expanded state; the label is not read twice.
      expect(
        tester.getSemantics(rowOf(readme)),
        matchesSemantics(
          label: 'README.md',
          hint: 'Level 2',
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );

      // The tap action is a plain click.
      tester.semantics.tap(find.semantics.byLabel('README.md'));
      await tester.pump();
      expect(controller.selection.selected, {readme});
      expect(controller.focusedId, readme);
      semantics.dispose();
    });

    testWidgets('rows report checked and mixed states with checkboxes', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController()..toggleChecked(aDart);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
        ),
      );
      expect(
        tester.getSemantics(rowOf(aDart)),
        isSemantics(
          label: 'a.dart',
          hasCheckedState: true,
          isChecked: true,
          isCheckStateMixed: false,
        ),
      );
      expect(
        tester.getSemantics(rowOf(src)),
        isSemantics(
          label: 'src',
          hasCheckedState: true,
          isChecked: false,
          isCheckStateMixed: true,
        ),
      );
      expect(
        tester.getSemantics(rowOf(readme)),
        isSemantics(
          hasCheckedState: true,
          isChecked: false,
          isCheckStateMixed: false,
        ),
      );
      semantics.dispose();
    });

    testWidgets('the long-press action is the secondary tap', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      final taps = <(NodeId, Offset)>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onRowSecondaryTap: (row, position) => taps.add((row.id, position)),
          levelSemanticsHint: (level) => 'Ebene $level',
        ),
      );
      expect(
        tester.getSemantics(rowOf(readme)),
        isSemantics(
          hint: 'Ebene 2',
          hasLongPressAction: true,
          hasTapAction: true,
        ),
      );
      tester.semantics.longPress(find.semantics.byLabel('README.md'));
      await tester.pump();
      expect(taps.single.$1, readme);
      expect(taps.single.$2, tester.getCenter(rowOf(readme)));
      expect(controller.selection.selected, {readme});
      semantics.dispose();
    });

    testWidgets('rows without a secondary handler have no long-press action', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      expect(
        tester.getSemantics(rowOf(readme)),
        isSemantics(hasLongPressAction: false),
      );
      semantics.dispose();
    });
  });

  group('right-to-left', () {
    testWidgets('mirrors the row content', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, textDirection: TextDirection.rtl),
      );
      final row = tester.getRect(rowOf(lib));
      final label = tester.getRect(find.text('lib'));
      final icon = tester.getRect(
        find.descendant(
          of: defaultRowOf<int>(lib),
          matching: find.byIcon(Icons.folder_open_outlined),
        ),
      );
      final chevron = tester.getRect(
        find.descendant(
          of: defaultRowOf<int>(lib),
          matching: find.byIcon(Icons.chevron_right),
        ),
      );
      // Start edge on the right: indentation, chevron, icon, then label.
      expect(chevron.left, greaterThan(icon.right - 1));
      expect(icon.left, greaterThan(label.right - 1));
      expect(chevron.right, lessThan(row.right - 16));
      // The expanded chevron turns toward the bottom the other way round.
      final rotation = tester.widget<AnimatedRotation>(
        find.descendant(
          of: defaultRowOf<int>(lib),
          matching: find.byType(AnimatedRotation),
        ),
      );
      expect(rotation.turns, -0.25);
    });
  });

  testWidgets('describes its configuration', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    final description = SliverDirectoryTree<int>(
      controller: controller,
      expandOnTap: false,
      checkboxMode: DirectoryTreeCheckboxMode.checks,
      onActivate: (_) {},
    ).toStringDeep();
    expect(description, contains('no expand on tap'));
    expect(description, contains('checkboxMode: checks'));
    expect(description, contains('has onActivate'));
  });
}
