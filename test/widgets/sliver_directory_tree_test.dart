import 'dart:ui' show CheckedState;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
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

  group('screen readers', () {
    SemanticsData dataOf(WidgetTester tester, NodeId id) =>
        tester.getSemantics(rowOf(id)).getSemanticsData();

    CustomSemanticsAction? customAction(
      WidgetTester tester,
      NodeId id,
      String label,
    ) {
      final ids = dataOf(tester, id).customSemanticsActionIds ?? const [];
      for (final id in ids) {
        final action = CustomSemanticsAction.getAction(id);
        if (action?.label == label) return action;
      }
      return null;
    }

    testWidgets('the keyboard-focused row is the focused node while the tree '
        'has focus', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final counter = BuildCounter<int>();
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          focusNode: focusNode,
          rowBuilder: counter.build,
        ),
      );
      controller.focus(lib);
      focusNode.requestFocus();
      await tester.pump();
      expect(tester.getSemantics(rowOf(lib)), isSemantics(isFocused: true));
      expect(tester.getSemantics(rowOf(lib)), isSemantics(isFocusable: true));
      expect(tester.getSemantics(rowOf(src)), isSemantics(isFocused: false));

      // A focus move changes two rows and rebuilds only those.
      counter.take();
      controller.moveFocus(TreeFocusMove.next);
      await tester.pump();
      expect(counter.take(), {lib, src});
      expect(tester.getSemantics(rowOf(src)), isSemantics(isFocused: true));
      expect(tester.getSemantics(rowOf(lib)), isSemantics(isFocused: false));

      // Without keyboard focus no row claims it.
      focusNode.unfocus();
      await tester.pumpAndSettle();
      expect(tester.getSemantics(rowOf(src)), isSemantics(isFocused: false));
      semantics.dispose();
    });

    testWidgets('an Open action activates rows when onActivate is set', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      final open = customAction(tester, readme, 'Open');
      expect(open, isNotNull);
      tester.semantics.customAction(find.semantics.byLabel('README.md'), open!);
      await tester.pump();
      expect(activated, [readme]);
      expect(controller.selection.selected, {readme});
      expect(controller.focusedId, readme);

      // A directory toggles once, as with Enter or a double-click.
      tester.semantics.customAction(find.semantics.byLabel('src'), open);
      await tester.pump();
      expect(activated, [readme, src]);
      expect(controller.isExpanded(src), isFalse);

      // Without onActivate there is no such action.
      await tester.pumpWidget(treeApp(controller: controller));
      expect(customAction(tester, readme, 'Open'), isNull);
      semantics.dispose();
    });

    testWidgets('expandable rows offer expand or collapse', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController()..collapse(src);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, expandOnTap: false),
      );
      expect(dataOf(tester, src).hasAction(SemanticsAction.expand), isTrue);
      expect(dataOf(tester, src).hasAction(SemanticsAction.collapse), isFalse);
      expect(dataOf(tester, lib).hasAction(SemanticsAction.collapse), isTrue);
      expect(dataOf(tester, readme).hasAction(SemanticsAction.expand), isFalse);
      tester.semantics.performAction(
        find.semantics.byLabel('src'),
        SemanticsAction.expand,
      );
      await tester.pump();
      expect(controller.isExpanded(src), isTrue);
      expect(controller.focusedId, src);
      tester.semantics.performAction(
        find.semantics.byLabel('src'),
        SemanticsAction.collapse,
      );
      await tester.pump();
      expect(controller.isExpanded(src), isFalse);
      // Neither selects.
      expect(controller.selection.isEmpty, isTrue);
      semantics.dispose();
    });

    testWidgets('loading and failed rows say so, and failed rows offer a '
        'retry', (tester) async {
      final semantics = tester.ensureSemantics();
      final loader = PendingLoader<int>();
      const lazy = NodeId('/lazy');
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry<int>.directory('/lazy'),
        ]),
        loadChildren: loader.call,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      controller.expand(lazy);
      await tester.pump();
      await tester.pump();
      expect(tester.getSemantics(rowOf(lazy)), isSemantics(value: 'Loading'));

      loader.fail(lazy, StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getSemantics(rowOf(lazy)),
        isSemantics(label: 'lazy', value: 'Failed to load'),
      );
      // The expander does not add a node of its own that says Expand.
      expect(find.semantics.byLabel('Expand'), findsNothing);
      final retry = customAction(tester, lazy, 'Refresh');
      expect(retry, isNotNull);
      tester.semantics.customAction(find.semantics.byLabel('lazy'), retry!);
      await tester.pump();
      await tester.pump();
      expect(loader.calls, [lazy, lazy]);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      semantics.dispose();
    });

    testWidgets('checkboxes add no node of their own; tapping a row toggles '
        'its box', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
        ),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      // One node per row.
      expect(
        find.semantics.byPredicate(
          (node) =>
              node.getSemanticsData().flagsCollection.isChecked !=
              CheckedState.none,
        ),
        findsNWidgets(9),
      );
      tester.semantics.tap(find.semantics.byLabel('a.dart'));
      await tester.pump();
      expect(controller.checkStateOf(aDart), CheckState.checked);
      expect(controller.focusedId, aDart);
      expect(controller.selection.isEmpty, isTrue);
      tester.semantics.tap(find.semantics.byLabel('a.dart'));
      await tester.pump();
      expect(controller.checkStateOf(aDart), CheckState.unchecked);

      // In selection mode a tap toggles that row only.
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.selection,
        ),
      );
      tester.semantics.tap(find.semantics.byLabel('lib'));
      tester.semantics.tap(find.semantics.byLabel('README.md'));
      await tester.pump();
      expect(controller.selection.selected, {lib, readme});
      semantics.dispose();
    });

    testWidgets('a box that cannot change leaves the tap a plain click', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        expansion: const ExpansionState.expanded(),
        checks: const SelectionState.empty(mode: SelectionMode.single),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
        ),
      );
      // src has two leaves: single-mode checks cannot hold it.
      tester.semantics.tap(find.semantics.byLabel('src'));
      await tester.pump();
      expect(controller.checks.isEmpty, isTrue);
      expect(controller.selection.selected, {src});
      semantics.dispose();
    });

    testWidgets('the labels are parameters', (tester) async {
      final semantics = tester.ensureSemantics();
      final loader = PendingLoader<int>();
      const lazy = NodeId('/lazy');
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry<int>.directory('/lazy'),
        ]),
        loadChildren: loader.call,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: CustomScrollView(
            slivers: [
              SliverDirectoryTree<int>(
                controller: controller,
                onActivate: (_) {},
                activateSemanticsLabel: 'Öffnen',
                loadingSemanticsLabel: 'Lädt',
                loadFailedSemanticsLabel: 'Fehler',
              ),
            ],
          ),
        ),
      );
      expect(customAction(tester, lazy, 'Öffnen'), isNotNull);
      expect(customAction(tester, lazy, 'Open'), isNull);
      controller.expand(lazy);
      await tester.pump();
      await tester.pump();
      expect(tester.getSemantics(rowOf(lazy)), isSemantics(value: 'Lädt'));
      loader.fail(lazy, StateError('offline'));
      await tester.pump();
      await tester.pump();
      expect(tester.getSemantics(rowOf(lazy)), isSemantics(value: 'Fehler'));
      semantics.dispose();
    });

    testWidgets(
      'VoiceOver platforms also get custom expand and collapse actions',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final controller = expandedController()..collapse(src);
        addTearDown(controller.dispose);
        await tester.pumpWidget(treeApp(controller: controller));
        // Web screen readers get no custom actions.
        final voiceOver =
            !kIsWeb &&
            (defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS);
        final expand = customAction(tester, src, 'Expand');
        final collapse = customAction(tester, lib, 'Collapse');
        expect(expand != null, voiceOver);
        expect(collapse != null, voiceOver);
        expect(customAction(tester, readme, 'Expand'), isNull);
        if (expand != null) {
          tester.semantics.customAction(find.semantics.byLabel('src'), expand);
          await tester.pump();
          expect(controller.isExpanded(src), isTrue);
          tester.semantics.customAction(
            find.semantics.byLabel('lib'),
            collapse!,
          );
          await tester.pump();
          expect(controller.isExpanded(lib), isFalse);
        }
        semantics.dispose();
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('default rows meet the screen reader guidelines', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final loader = PendingLoader<int>();
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry<int>.directory('/a/lazy'),
          TreeEntry<int>.file('/a/b/c.txt'),
          TreeEntry<int>.file('/a/d.txt'),
        ]),
        expansion: const ExpansionState.expanded(),
        loadChildren: loader.call,
      );
      addTearDown(controller.dispose);
      for (final mode in DirectoryTreeCheckboxMode.values) {
        await tester.pumpWidget(
          treeApp(
            controller: controller,
            checkboxMode: mode,
            onActivate: (_) {},
            onRowSecondaryTap: (_, _) {},
          ),
        );
        await tester.pump();
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      }
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
    expect(description, isNot(contains('activateSemanticsLabel')));
    final localized = SliverDirectoryTree<int>(
      controller: controller,
      activateSemanticsLabel: 'Öffnen',
      loadingSemanticsLabel: 'Lädt',
      loadFailedSemanticsLabel: 'Fehler',
    ).toStringDeep();
    expect(localized, contains('activateSemanticsLabel: "Öffnen"'));
    expect(localized, contains('loadingSemanticsLabel: "Lädt"'));
    expect(localized, contains('loadFailedSemanticsLabel: "Fehler"'));
  });
}
