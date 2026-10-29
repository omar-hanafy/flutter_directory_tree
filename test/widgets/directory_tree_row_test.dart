import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_utils.dart';

const Color _selected = Color(0xFFAA0000);
const Color _inactive = Color(0xFF777777);
const Color _hover = Color(0xFF00AA00);
const Color _border = Color(0xFF0000AA);
const Color _label = Color(0xFF111111);
const Color _selectedLabel = Color(0xFF222222);
const Color _dimmed = Color(0xFF333333);

final DirectoryTreeThemeData _colors = testTheme.copyWith(
  selectedColor: _selected,
  inactiveSelectedColor: _inactive,
  hoverColor: _hover,
  focusedBorderColor: _border,
  focusedBorderWidth: 2,
  labelStyle: const TextStyle(color: _label),
  selectedLabelStyle: const TextStyle(color: _selectedLabel),
  dimmedLabelStyle: const TextStyle(color: _dimmed),
  matchHighlightStyle: const TextStyle(fontWeight: FontWeight.w900),
);

DirectoryTreeLabel _labelOf(WidgetTester tester, NodeId id) =>
    tester.widget<DirectoryTreeLabel>(
      find.descendant(of: rowOf(id), matching: find.byType(DirectoryTreeLabel)),
    );

Finder _iconIn(NodeId id, IconData icon) =>
    find.descendant(of: rowOf(id), matching: find.byIcon(icon));

void main() {
  group('background and border', () {
    testWidgets('selection uses the active color only while the tree has '
        'keyboard focus', (tester) async {
      final controller = expandedController()..select(readme);
      addTearDown(controller.dispose);
      final focusNode = FocusNode(debugLabel: 'tree');
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, theme: _colors, focusNode: focusNode),
      );
      expect(rowDecoration<int>(tester, readme).color, _inactive);
      expect(rowDecoration<int>(tester, readme).border, isNull);
      expect(rowDecoration<int>(tester, mainDart).color, isNull);

      focusNode.requestFocus();
      await tester.pump();
      expect(rowDecoration<int>(tester, readme).color, _selected);
      expect(
        rowDecoration<int>(tester, readme).border,
        Border.all(color: _border, width: 2),
      );
      expect(rowDecoration<int>(tester, mainDart).color, isNull);
      expect(rowDecoration<int>(tester, mainDart).border, isNull);
      expect(
        rowDecoration<int>(tester, readme).borderRadius,
        DirectoryTreeTheme.of(tester.element(rowOf(readme))).rowBorderRadius,
      );
    });

    testWidgets('the focused border follows the keyboard cursor', (
      tester,
    ) async {
      final controller = expandedController()..focus(mainDart);
      addTearDown(controller.dispose);
      final focusNode = FocusNode(debugLabel: 'tree');
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, theme: _colors, focusNode: focusNode),
      );
      expect(rowDecoration<int>(tester, mainDart).border, isNull);
      focusNode.requestFocus();
      await tester.pump();
      expect(rowDecoration<int>(tester, mainDart).border, isNotNull);
      expect(rowDecoration<int>(tester, mainDart).color, isNull);
      controller.focus(readme);
      await tester.pump();
      expect(rowDecoration<int>(tester, mainDart).border, isNull);
      expect(rowDecoration<int>(tester, readme).border, isNotNull);
    });

    testWidgets('hover tints only unselected rows', (tester) async {
      final controller = expandedController()..select(readme);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller, theme: _colors));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: tester.getCenter(rowOf(mainDart)));
      await tester.pump();
      expect(rowDecoration<int>(tester, mainDart).color, _hover);
      await mouse.moveTo(tester.getCenter(rowOf(readme)));
      await tester.pump();
      expect(rowDecoration<int>(tester, mainDart).color, isNull);
      expect(rowDecoration<int>(tester, readme).color, _inactive);
    });
  });

  group('label', () {
    testWidgets('uses the selected, dimmed, or plain style', (tester) async {
      final controller = expandedController()..query = 'main';
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller, theme: _colors));
      // repo, lib, and test are shown only because they contain matches.
      expect(_labelOf(tester, repo).style!.color, _dimmed);
      expect(_labelOf(tester, lib).style!.color, _dimmed);
      expect(_labelOf(tester, mainDart).style!.color, _label);
      expect(_labelOf(tester, mainTest).style!.color, _label);

      controller
        ..select(mainDart)
        ..toggleSelected(lib);
      await tester.pump();
      expect(_labelOf(tester, mainDart).style!.color, _selectedLabel);
      expect(_labelOf(tester, lib).style!.color, _selectedLabel);

      controller.query = '';
      await tester.pump();
      expect(_labelOf(tester, repo).style!.color, _label);
    });

    testWidgets('highlights the parts that match the query', (tester) async {
      final controller = expandedController()..query = 'main';
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller, theme: _colors));
      expect(_labelOf(tester, mainDart).matchRanges, [(start: 0, end: 4)]);
      expect(_labelOf(tester, mainTest).matchRanges, [(start: 0, end: 4)]);
      expect(_labelOf(tester, lib).matchRanges, isEmpty);

      final text = tester.widget<RichText>(
        find.descendant(
          of: find.descendant(
            of: rowOf(mainDart),
            matching: find.byType(DirectoryTreeLabel),
          ),
          matching: find.byType(RichText),
        ),
      );
      final spans = <TextSpan>[];
      text.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) spans.add(span);
        return true;
      });
      expect(spans.map((span) => span.text), ['main', '.dart']);
      expect(spans.first.style!.fontWeight, FontWeight.w900);
      expect(spans.last.style, isNull);
    });

    testWidgets('shows the row label of compacted folders', (tester) async {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry<int>.file('/repo/lib/src/utils/a.dart'),
          TreeEntry<int>.file('/repo/README.md'),
        ]),
        expansion: const ExpansionState.expanded(),
        compactFolders: true,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      // The row is keyed by its deepest directory and reads as the chain.
      const utils = NodeId('/repo/lib/src/utils');
      expect(find.text('lib/src/utils'), findsOneWidget);
      expect(
        find.descendant(of: rowOf(utils), matching: find.text('lib/src/utils')),
        findsOneWidget,
      );
    });
  });

  group('icons and parts', () {
    testWidgets('icons follow the node kind and expansion', (tester) async {
      final controller = expandedController()..collapse(src);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller, theme: _colors));
      final theme = DirectoryTreeTheme.of(tester.element(rowOf(lib)));
      expect(_iconIn(lib, Icons.folder_open_outlined), findsOneWidget);
      expect(_iconIn(src, Icons.folder_outlined), findsOneWidget);
      final mainIcon = DirectoryTreeIconSet.material.iconFor(
        controller.tree[mainDart]!,
        expanded: false,
      );
      expect(_iconIn(mainDart, mainIcon), findsOneWidget);
      expect(
        tester.widget<Icon>(_iconIn(lib, Icons.folder_open_outlined)).color,
        theme.folderIconColor,
      );
      expect(
        tester.widget<Icon>(_iconIn(mainDart, mainIcon)).color,
        theme.iconColor,
      );
      expect(
        tester.widget<Icon>(_iconIn(mainDart, mainIcon)).size,
        theme.iconSize,
      );
    });

    testWidgets('indents by depth and passes guides only to connectors', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      DirectoryTreeIndentGuides guidesOf(NodeId id) =>
          tester.widget<DirectoryTreeIndentGuides>(
            find.descendant(
              of: rowOf(id),
              matching: find.byType(DirectoryTreeIndentGuides),
            ),
          );
      expect(
        tester
            .getSize(
              find.descendant(
                of: rowOf(aDart),
                matching: find.byType(DirectoryTreeIndentGuides),
              ),
            )
            .width,
        3 * 16,
      );
      expect(guidesOf(aDart).depth, 3);
      expect(guidesOf(aDart).guides, isEmpty);
      expect(guidesOf(readme).isLast, isTrue);

      await tester.pumpWidget(
        treeApp(
          controller: controller,
          theme: testTheme.copyWith(
            guideStyle: DirectoryTreeGuideStyle.connectors,
          ),
        ),
      );
      final aRow = controller.rows[controller.rows.indexOfNode(aDart)];
      expect(guidesOf(aDart).guides, aRow.guides);
    });

    testWidgets('expander, leading, title, and trailing replace their parts', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          rowBuilder: (context, details) => DirectoryTreeRow(
            details: details,
            expander: const SizedBox(width: 20, child: Text('>')),
            leading: const Icon(Icons.star),
            title: Text('title ${details.row.label}'),
            trailing: Text('size ${details.row.node.data ?? '-'}'),
          ),
        ),
      );
      expect(find.byType(DirectoryTreeExpander<int>), findsNothing);
      expect(find.byType(DirectoryTreeLabel), findsNothing);
      expect(find.byIcon(Icons.star), findsNWidgets(9));
      expect(find.text('title README.md'), findsOneWidget);
      expect(find.text('size 5'), findsOneWidget);
      expect(find.text('size -'), findsNWidgets(4));
      // The trailing widget sits at the end edge.
      expect(
        tester.getTopRight(find.text('size 5')).dx,
        lessThanOrEqualTo(viewportWidth),
      );
      expect(
        tester.getTopLeft(find.text('size 5')).dx,
        greaterThan(tester.getTopRight(find.text('title README.md')).dx),
      );
    });

    testWidgets('a row outside the sliver keeps its label semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController();
      addTearDown(controller.dispose);
      final row = controller.rows[8];
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              height: 30,
              child: DirectoryTreeRow<int>(
                details: DirectoryTreeRowDetails<int>(
                  controller: controller,
                  row: row,
                  index: 8,
                  isSelected: false,
                  isFocused: false,
                  hasFocus: false,
                  isHovered: false,
                  checkboxMode: DirectoryTreeCheckboxMode.none,
                  checkState: null,
                  loadStatus: DirectoryLoadStatus.loaded,
                  isExpandable: false,
                  matchRanges: const [],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('README.md'), findsOneWidget);
      semantics.dispose();
    });
  });

  group('expander', () {
    testWidgets('is an empty box for rows that cannot expand', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      final expander = find.descendant(
        of: rowOf(readme),
        matching: find.byType(DirectoryTreeExpander<int>),
      );
      expect(tester.getSize(expander).width, 20);
      expect(
        find.descendant(of: expander, matching: find.byType(Icon)),
        findsNothing,
      );
    });

    testWidgets('shows lazy-loading states and retries a failed load', (
      tester,
    ) async {
      final loader = PendingLoader<int>();
      const lazy = NodeId('/lazy');
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build(const [
          TreeEntry<int>.directory('/lazy'),
        ]),
        loadChildren: loader.call,
      );
      addTearDown(controller.dispose);
      final activated = <NodeId>[];
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          onActivate: (row) => activated.add(row.id),
        ),
      );
      // Not loaded yet: a chevron that loads on click.
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.notLoaded);
      expect(_iconIn(lazy, Icons.chevron_right), findsOneWidget);

      await tester.tap(_iconIn(lazy, Icons.chevron_right));
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      await tester.pump();
      await tester.pump();
      expect(loader.calls, [lazy]);
      expect(
        find.descendant(
          of: rowOf(lazy),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(_iconIn(lazy, Icons.chevron_right), findsNothing);

      loader.fail(lazy, StateError('no access'));
      await tester.pump();
      await tester.pump();
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.failed);
      expect(_iconIn(lazy, Icons.error_outline), findsOneWidget);
      expect(
        tester.widget<Icon>(_iconIn(lazy, Icons.error_outline)).color,
        Theme.of(tester.element(rowOf(lazy))).colorScheme.error,
      );

      // A click on the error icon loads again.
      await tester.tap(_iconIn(lazy, Icons.error_outline));
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      await tester.pump();
      await tester.pump();
      expect(loader.calls, [lazy, lazy]);
      loader.complete(lazy, const [TreeEntry<int>.file('/lazy/x.txt')]);
      await tester.pump();
      await tester.pump();
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
      expect(rowOf(const NodeId('/lazy/x.txt')), findsOneWidget);
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: rowOf(lazy),
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns,
        0.25,
      );
      // The expander clicks never selected or activated the row.
      expect(controller.selection.isEmpty, isTrue);
      expect(activated, isEmpty);
      expect(controller.focusedId, lazy);
    });

    testWidgets('a failed load can be retried even after a collapse', (
      tester,
    ) async {
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
      loader.fail(lazy, StateError('offline'));
      await tester.pump();
      await tester.pump();
      controller.collapse(lazy);
      await tester.pump();
      expect(_iconIn(lazy, Icons.error_outline), findsOneWidget);
      await tester.tap(_iconIn(lazy, Icons.error_outline));
      expect(controller.isExpanded(lazy), isTrue);
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
      await tester.pump();
      await tester.pump();
      loader.complete(lazy, const []);
      await tester.pump();
      await tester.pump();
      expect(controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
    });

    testWidgets('is a button labeled Expand or Collapse', (tester) async {
      final semantics = tester.ensureSemantics();
      final controller = expandedController()..collapse(src);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      expect(
        tester.getSemantics(
          find.descendant(
            of: rowOf(lib),
            matching: find.byType(DirectoryTreeExpander<int>),
          ),
        ),
        matchesSemantics(label: 'Collapse', isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(
          find.descendant(
            of: rowOf(src),
            matching: find.byType(DirectoryTreeExpander<int>),
          ),
        ),
        matchesSemantics(label: 'Expand', isButton: true, hasTapAction: true),
      );
      tester.semantics.tap(find.semantics.byLabel('Expand'));
      await tester.pump();
      expect(controller.isExpanded(src), isTrue);
      expect(controller.selection.isEmpty, isTrue);
      semantics.dispose();
    });
  });

  group('checkbox', () {
    Checkbox checkboxOf(WidgetTester tester, NodeId id) =>
        tester.widget<Checkbox>(
          find.descendant(of: rowOf(id), matching: find.byType(Checkbox)),
        );

    testWidgets('checks mode: a tri-state box bound to the checks', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
        ),
      );
      expect(find.byType(Checkbox), findsNWidgets(9));
      expect(checkboxOf(tester, aDart).tristate, isTrue);
      expect(checkboxOf(tester, aDart).value, isFalse);

      await tester.tap(
        find.descendant(of: rowOf(aDart), matching: find.byType(Checkbox)),
      );
      await tester.pump();
      expect(controller.checkStateOf(aDart), CheckState.checked);
      expect(checkboxOf(tester, aDart).value, isTrue);
      expect(checkboxOf(tester, src).value, isNull);
      expect(checkboxOf(tester, repo).value, isNull);

      // A partial directory becomes checked with its whole subtree.
      await tester.tap(
        find.descendant(of: rowOf(lib), matching: find.byType(Checkbox)),
      );
      await tester.pump();
      expect(controller.checkStateOf(lib), CheckState.checked);
      expect(checkboxOf(tester, mainDart).value, isTrue);
      expect(checkboxOf(tester, src).value, isTrue);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, lib);
    });

    testWidgets('selection mode: mirrors the selection, one row at a time', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.selection,
        ),
      );
      expect(checkboxOf(tester, lib).tristate, isFalse);
      await tester.tap(
        find.descendant(of: rowOf(lib), matching: find.byType(Checkbox)),
      );
      await tester.pump();
      // A directory's box selects only the directory, and adds to the
      // selection instead of replacing it.
      expect(controller.selection.selected, {lib});
      expect(checkboxOf(tester, lib).value, isTrue);
      expect(checkboxOf(tester, mainDart).value, isFalse);
      await tester.tap(
        find.descendant(of: rowOf(readme), matching: find.byType(Checkbox)),
      );
      await tester.pump();
      expect(controller.selection.selected, {lib, readme});

      controller.select(mainDart);
      await tester.pump();
      expect(checkboxOf(tester, mainDart).value, isTrue);
      expect(checkboxOf(tester, lib).value, isFalse);
      expect(checkboxOf(tester, readme).value, isFalse);
    });

    testWidgets('selection mode: rows that cannot be selected are disabled', (
      tester,
    ) async {
      final controller = DirectoryTreeController<int>(
        tree: sampleTree(),
        expansion: const ExpansionState.expanded(),
        selectable: (node) => node.isFile,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          checkboxMode: DirectoryTreeCheckboxMode.selection,
        ),
      );
      expect(checkboxOf(tester, lib).onChanged, isNull);
      expect(checkboxOf(tester, readme).onChanged, isNotNull);
    });

    testWidgets('checks mode: boxes that cannot be checked are disabled', (
      tester,
    ) async {
      // In single mode only a node with at most one leaf can be checked.
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
      expect(checkboxOf(tester, src).onChanged, isNull);
      expect(checkboxOf(tester, testDir).onChanged, isNotNull);
      expect(checkboxOf(tester, aDart).onChanged, isNotNull);

      // A checked node can always be unchecked.
      controller.setChecked(mainTest, checked: true);
      await tester.pump();
      expect(checkboxOf(tester, testDir).value, isTrue);
      expect(checkboxOf(tester, testDir).onChanged, isNotNull);

      // Switching to multiple mode enables every box.
      controller.checks = const SelectionState.empty(
        mode: SelectionMode.multiple,
      );
      await tester.pump();
      expect(checkboxOf(tester, src).onChanged, isNotNull);
      controller.checks = const SelectionState.empty(
        mode: SelectionMode.single,
      );
      await tester.pump();
      expect(checkboxOf(tester, src).onChanged, isNull);
    });

    testWidgets('none mode shows no checkbox', (tester) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(DirectoryTreeCheckbox<int>), findsNothing);
    });

    testWidgets('takes no keyboard focus and works without a Scaffold', (
      tester,
    ) async {
      final controller = expandedController();
      addTearDown(controller.dispose);
      final row = controller.rows[8];
      await tester.pumpWidget(
        MaterialApp(
          home: DirectoryTreeCheckbox<int>(
            details: DirectoryTreeRowDetails<int>(
              controller: controller,
              row: row,
              index: 8,
              isSelected: false,
              isFocused: false,
              hasFocus: false,
              isHovered: false,
              checkboxMode: DirectoryTreeCheckboxMode.checks,
              checkState: CheckState.unchecked,
              loadStatus: DirectoryLoadStatus.loaded,
              isExpandable: false,
              matchRanges: const [],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Checkbox));
      expect(controller.checkStateOf(readme), CheckState.checked);
      expect(
        FocusManager.instance.primaryFocus?.context?.widget,
        isNot(isA<Checkbox>()),
      );
    });
  });
}
