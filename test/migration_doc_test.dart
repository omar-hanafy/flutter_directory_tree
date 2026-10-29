/// Compiles and runs every 2.0.0 Dart example in MIGRATION.md.
///
/// Each 2.0.0 block of the guide appears below verbatim: declarations as
/// they are, statements inside a top-level function that a test runs or
/// pumps. Blocks whose first line is `// flutter_directory_tree 1.x` show
/// the old API and are skipped. The first test fails when a 2.0.0 block has
/// no copy here, and every `print(...); // output` line is an assertion:
/// the printed value must equal the comment. The other tests check the
/// behavior changes and recipes that the guide describes.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// The first line of every 1.x block in the guide.
const String _v1Marker = '// flutter_directory_tree 1.x';

void main() {
  final guide = File('MIGRATION.md').readAsStringSync();
  final allBlocks = RegExp(r'```dart\n([\s\S]*?)```')
      .allMatches(guide)
      .map((match) => match.group(1)!)
      .toList();
  final blocks = allBlocks
      .where((block) => !block.startsWith(_v1Marker))
      .toList();

  /// The 2.0.0 block that contains [line].
  String block(String line) => blocks.singleWhere((b) => b.contains(line));

  test('every 2.0.0 Dart block is compiled by this file', () {
    final source = _normalize(
      File('test/migration_doc_test.dart').readAsStringSync(),
    );
    expect(blocks, isNotEmpty);
    expect(
      allBlocks.length,
      greaterThan(blocks.length),
      reason: 'The guide shows 1.x blocks marked with "$_v1Marker".',
    );
    final missing = [
      for (final guideBlock in blocks)
        if (!source.contains(_normalize(guideBlock))) guideBlock,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'Copy these MIGRATION.md blocks into test/migration_doc_test.dart, '
          'or start them with "$_v1Marker" if they show the old API:\n'
          '${missing.join('\n---\n')}',
    );
  });

  test('every 2.0.0 output comment is compared with the output', () {
    final source = File('test/migration_doc_test.dart').readAsStringSync();
    final compared = {
      for (final match in RegExp(
        r"_expectedPrints\(block\('([^']+)'\)\)",
      ).allMatches(source))
        block(match.group(1)!),
    };
    for (final guideBlock in blocks) {
      final prints = guideBlock
          .split('\n')
          .where((line) => line.trimLeft().startsWith('print('))
          .toList();
      for (final line in prints) {
        expect(
          _printLine.hasMatch(line),
          isTrue,
          reason: 'Write guide prints as `print(...); // output`: $line',
        );
      }
      expect(
        prints.isEmpty || compared.contains(guideBlock),
        isTrue,
        reason:
            'Compare the output of this block with '
            '_expectedPrints(block(...)):\n$guideBlock',
      );
    }
  });

  test('the dart fix table lists the transforms of lib/fix_data.yaml', () {
    final fixData = File('lib/fix_data.yaml').readAsStringSync();
    expect(
      RegExp(r'^  - title:', multiLine: true).allMatches(fixData),
      hasLength(7),
    );
    expect(guide, contains('seven transforms in all'));
    for (final name in [
      'indentWidth',
      'rowExtent',
      'removedIndices',
      'insertedIndices',
      "'path'",
    ]) {
      expect(fixData, contains(name));
    }
  });

  group('before and after', () {
    test('a controller and a view', () {
      final (controller, view) = _controllerAndView();
      addTearDown(controller.dispose);
      expect(controller.rows.map((row) => row.label), ['repo']);
      expect(view, isA<DirectoryTreeView<Object?>>());
    });

    test('refreshing the data keeps the state, starting over clears it', () {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      controller.select(lib);
      final next = controller.tree.rebuild(
        (builder) => builder.addFile('/repo/lib/added.dart'),
      );
      _refresh(controller, next);
      expect(controller.tree, same(next));
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.rows.map((row) => row.label), ['repo']);
    });

    test('selection', () {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      final ids = _selection(
        controller,
        controller.tree.idOf('/repo/lib')!,
        controller.tree.idOf('/repo/README.md')!,
      );
      expect(ids.map((id) => id.value), [
        '/repo/lib',
        '/repo/lib/src',
        '/repo/lib/src/tree.dart',
        '/repo/lib/main.dart',
        '/repo/test',
        '/repo/test/tree_test.dart',
        '/repo/README.md',
      ]);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('revealing a node opens its ancestors and selects it', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final id = controller.tree.idOf('/repo/lib/src/tree.dart')!;
      _reveal(controller, id);
      expect(controller.isSelected(id), isTrue);
      expect(controller.focusedRow!.id, id);
      expect(controller.rows.map((row) => row.label), [
        'repo',
        'lib',
        'src',
        'tree.dart',
        'main.dart',
        'test',
        'README.md',
      ]);
    });

    testWidgets('the picker returns nodes, or null on cancel', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      Set<NodeId>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    result = await _picker(context, controller),
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      // The multiple directories picker shows a box per row.
      await tester.tap(find.byType(Checkbox).at(1)); // lib
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(result!.map((id) => id.value), ['/repo/lib']);

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('the theme', () {
      final theme = _theme();
      expect(theme.rowExtent, 24);
      expect(theme.guideStyle, DirectoryTreeGuideStyle.none);
      expect(theme.selectedColor, theme.inactiveSelectedColor);
    });
  });

  group('behavior changes', () {
    test('dropped state values change nothing', () {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      controller.select(lib);
      // ignore: unused_result, the hazard the guide warns about.
      controller.selection.clear();
      expect(controller.isSelected(lib), isTrue);
      controller.clearSelection();
      expect(controller.isSelected(lib), isFalse);
    });

    test('a 1.x string id matches no node and raises no error', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      controller.select(const NodeId('node_main'));
      expect(controller.selection.isEmpty, isTrue);
    });

    testWidgets('the toolbar has no search field', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DirectoryTreeToolbar(controller: controller)),
        ),
      );
      expect(find.byType(TextField), findsNothing);
    });

    test('controller.expandAll opens every folder', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      controller.expandAll();
      expect(controller.rows, hasLength(controller.tree.nodes.length));
    });

    test('a new controller starts collapsed, empty, and case-sensitive', () {
      final controller = DirectoryTreeController(
        tree: DirectoryTree.fromPaths(['/r/README.md', '/r/readme.md']),
      );
      addTearDown(controller.dispose);
      expect(controller.rows.map((row) => row.label), ['r']);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.selectionMode, SelectionMode.multiple);
      expect(controller.tree.fileCount, 2);
    });

    test('single mode toggling the selected row clears it', () {
      final controller = _sample(expanded: true)
        ..selectionMode = SelectionMode.single;
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      controller
        ..toggleSelected(lib)
        ..toggleSelected(lib);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('ListDiff index lists are unmodifiable', () {
      final diff = ListDiff.compute(
        ['a', 'b', 'c'],
        ['c'],
        keyOf: (item) => item,
      );
      expect(diff.removedIndices.sort, throwsUnsupportedError);
    });

    test('collapseAll keeps the top-level rows', () {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      controller.collapseAll();
      expect(controller.rows.map((row) => row.label), ['repo']);
    });

    testWidgets('the default picker mode rejects folders', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      var picked = <TreeNode<Object?>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectoryTreePicker(
              tree: controller.tree,
              onChanged: (nodes) => picked = nodes,
            ),
          ),
        ),
      );
      await tester.tap(find.text('lib'));
      await tester.pump(kDoubleTapTimeout);
      expect(picked, isEmpty);
      await tester.tap(find.text('README.md'));
      await tester.pump(kDoubleTapTimeout);
      expect(picked.single.name, 'README.md');
    });
  });

  group('recipes', () {
    testWidgets('a custom expander toggles the folder', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectoryTreeView(
              controller: controller,
              rowBuilder: plusMinusRow,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(controller.isExpanded(controller.tree.roots.single), isTrue);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(controller.selection.isEmpty, isTrue);
    });

    testWidgets('clicks the app handles check rows', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _appClicks(controller))),
      );
      await tester.tap(find.text('lib'));
      await tester.pump(kDoubleTapTimeout);
      final lib = controller.tree.idOf('/repo/lib')!;
      expect(controller.checkStateOf(lib), CheckState.checked);
      expect(controller.isExpanded(lib), isTrue);
      expect(controller.selection.isEmpty, isTrue);
    });

    testWidgets('a popup menu opens from a secondary click', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => treeWithPopupMenu(context, controller),
            ),
          ),
        ),
      );
      await tester.tap(find.text('main.dart'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Rename main.dart'), findsOneWidget);
    });

    testWidgets('a middle-click reaches the row builder', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await _withDebugLog((log) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: _middleClick(controller))),
        );
        await tester.tap(find.text('main.dart'), buttons: kMiddleMouseButton);
        await tester.pump(kDoubleTapTimeout);
        expect(log, ['open main.dart in a tab']);
        expect(controller.selection.isEmpty, isTrue);
      });
    });

    testWidgets('the panel takes focus with autofocus', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _panel(controller))),
      );
      await tester.pump();
      expect(find.text('Files'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.focusedRow?.label, 'repo');
    });

    testWidgets('the row count follows the rows', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _rowCount(controller))),
      );
      expect(find.text('1 rows'), findsOneWidget);
      controller.expand(controller.tree.roots.single);
      await tester.pump();
      expect(find.text('4 rows'), findsOneWidget);
    });

    test('looking up nodes by key, seeding state, checkboxes', () async {
      final printed = await _prints(() {
        _lookupByKey();
        _seeded();
        _checkboxes();
      });
      expect(printed, [
        ..._expectedPrints(block('final idsByKey = {')),
        ..._expectedPrints(block('final seeded = DirectoryTreeController(')),
        ..._expectedPrints(block('final files = DirectoryTreeController(')),
      ]);
    });

    test('sorting at display time keeps the state', () {
      final controller = DirectoryTreeController(
        tree: DirectoryTree.fromPaths(['/r/b/x.txt', '/r/a.txt']),
        expansion: const ExpansionState.expanded(),
      );
      addTearDown(controller.dispose);
      final b = controller.tree.idOf('/r/b')!;
      controller.select(b);
      expect(controller.rows.map((row) => row.label), [
        'r',
        'b',
        'x.txt',
        'a.txt',
      ]);
      _sortAlphabetically(controller);
      expect(controller.rows.map((row) => row.label), [
        'r',
        'a.txt',
        'b',
        'x.txt',
      ]);
      expect(controller.isSelected(b), isTrue);
    });

    testWidgets('Enter on a file toggles its selection', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _enterOnFile(controller))),
      );
      await tester.tap(find.text('README.md'));
      await tester.pump(kDoubleTapTimeout);
      final readme = controller.tree.idOf('/repo/README.md')!;
      expect(controller.isSelected(readme), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.isSelected(readme), isFalse);
    });

    testWidgets('a fixed page size moves ten rows', (tester) async {
      final controller = DirectoryTreeController(
        tree: DirectoryTree.fromPaths([
          for (var i = 0; i < 40; i++) '/r/file$i.txt',
        ]),
        expansion: const ExpansionState.expanded(),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _fixedPage(controller))),
      );
      await tester.tap(find.text('file0.txt'));
      await tester.pump(kDoubleTapTimeout);
      expect(controller.focusedIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pump();
      expect(controller.focusedIndex, 11);
    });

    test('listening to one kind of change', () async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await _withDebugLog((log) async {
        _listenToSelection(controller);
        controller.expand(controller.tree.idOf('/repo/lib')!); // no change
        controller.collapse(controller.tree.idOf('/repo/test')!);
        controller.select(controller.tree.roots.single);
        controller.focus(controller.tree.idOf('/repo/README.md'));
        expect(log, ['1 selected']);
      });
    });

    testWidgets('icons from node data', (tester) async {
      final cloud = DirectoryTreeController<String>(
        tree: DirectoryTree<String>.build([
          TreeEntry.file('/docs/plan.md', data: 'remote'),
          TreeEntry.file('/docs/notes.md'),
        ]),
        expansion: const ExpansionState.expanded(),
      );
      addTearDown(cloud.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _iconsFromData(cloud))),
      );
      expect(find.byIcon(Icons.cloud_queue), findsOneWidget);
    });

    testWidgets('subtitles in the trailing slot', (tester) async {
      final controller = _sample(expanded: true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _subtitles(controller))),
      );
      expect(find.text('folder'), findsNWidgets(4));
      expect(find.text('file'), findsNWidgets(4));
    });
  });
}

// Before and after.
(DirectoryTreeController<Object?>, Widget) _controllerAndView() {
  final controller = DirectoryTreeController(
    tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/README.md']),
  );

  final view = DirectoryTreeView(
    controller: controller,
    onActivate: (row) => debugPrint('open ${row.node.path}'),
  );
  return (controller, view);
}

void _refresh(
  DirectoryTreeController<Object?> controller,
  DirectoryTree<Object?> next,
) {
  controller.tree = next; // keeps expansion, selection, checks, and focus

  // Starting over takes three commands (three notifications).
  controller
    ..tree = next
    ..expansion = const ExpansionState.collapsed()
    ..clearSelection();
}

Set<NodeId> _selection(
  DirectoryTreeController<Object?> controller,
  NodeId id,
  NodeId other,
) {
  controller.select(id); // also focuses the row and scrolls to it
  controller.extendSelection(other); // from the anchor that select set
  final ids = controller.selection.selected;
  controller.clearSelection();
  return ids;
}

void _reveal(DirectoryTreeController<Object?> controller, NodeId id) {
  controller.reveal(
    id,
    select: true,
    alignment: 0, // the row at the top, as 1.x did; null scrolls minimally
    duration: const Duration(milliseconds: 220),
  );
}

Future<Set<NodeId>> _picker(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) async {
  final nodes = await showDirectoryTreePicker(
    context: context,
    tree: controller.tree,
    mode: DirectoryTreePickerMode.directories,
    multiple: true,
    initialSelection: controller.selection.selected,
    initialExpansion: controller.expansion,
  );
  final ids = nodes?.map((node) => node.id).toSet() ?? const <NodeId>{};
  return ids;
}

DirectoryTreeThemeData _theme() {
  const theme = DirectoryTreeThemeData(
    rowExtent: 24, // dart fix
    indentWidth: 12, // dart fix
    guideStyle: DirectoryTreeGuideStyle.none,
    selectedColor: Color(0x332196F3),
    inactiveSelectedColor: Color(0x332196F3),
    rowBorderRadius: BorderRadius.zero,
  );
  return theme;
}

// Recipes.
Widget plusMinusRow(
  BuildContext context,
  DirectoryTreeRowDetails<Object?> details,
) {
  final row = details.row;
  return DirectoryTreeRow(
    details: details,
    expander: SizedBox(
      width: 20, // the theme's expanderSize, so rows line up
      child: details.isExpandable
          ? IconButton(
              iconSize: 14,
              padding: EdgeInsets.zero,
              icon: Icon(row.isExpanded ? Icons.remove : Icons.add),
              onPressed: () => details.controller.toggleExpansion(row.id),
            )
          : null,
    ),
  );
}

Widget _appClicks(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    selectOnTap: false, // a click only focuses the row
    expandOnTap: false, // folders open with the arrow and the keyboard
    onRowTap: (row) => controller.toggleChecked(row.id),
  );
  return view;
}

Widget treeWithPopupMenu(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) {
  return DirectoryTreeView(
    controller: controller,
    onRowSecondaryTap: (row, position) => showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(value: 'rename', child: Text('Rename ${row.label}')),
      ],
    ),
  );
}

Widget _middleClick(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    rowBuilder: (context, details) => GestureDetector(
      onTertiaryTapUp: (_) => debugPrint('open ${details.row.label} in a tab'),
      child: DirectoryTreeRow(details: details),
    ),
  );
  return view;
}

Widget _panel(DirectoryTreeController<Object?> controller) {
  final panel = DirectoryTreePanel(
    controller: controller,
    autofocus: true,
    title: const Text('Files'),
  );
  return panel;
}

Widget _rowCount(DirectoryTreeController<Object?> controller) {
  final panel = DirectoryTreePanel(
    controller: controller,
    actions: [
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => Text('${controller.rows.length} rows'),
      ),
    ],
  );
  return panel;
}

void _lookupByKey() {
  final tree = DirectoryTree<String>.build([
    TreeEntry.file('/repo/lib/main.dart', data: 'main'),
    TreeEntry.file('/repo/README.md', data: 'readme'),
  ]);
  final idsByKey = {for (final node in tree.nodes) ?node.data: node.id};
  final keyed = DirectoryTreeController<String>(tree: tree);
  keyed.reveal(idsByKey['main']!, select: true, scroll: false);
  print(keyed.selectedNodes.single.name); // main.dart
  keyed.dispose();
}

void _seeded() {
  final paths = ['/repo/lib/main.dart', '/repo/README.md'];
  final tree = DirectoryTree.fromPaths(
    paths,
    options: const TreeOptions(paths: PathPolicy.caseInsensitive),
  );
  final seeded = DirectoryTreeController(
    tree: tree,
    expansion: const ExpansionState.expanded(), // every folder open
    checks: const SelectionState.empty(mode: SelectionMode.multiple)
        .addAll(tree.files.map((file) => file.id)), // every file checked
  );
  print(seeded.rows.length); // 4
  print(seeded.checkedLeaves.length); // 2
  seeded.dispose();
}

void _checkboxes() {
  final files = DirectoryTreeController(
    tree: DirectoryTree.fromPaths([
      '/repo/lib/main.dart',
      '/repo/lib/src/tree.dart',
      '/repo/README.md',
    ]),
  );
  final lib = files.tree.idOf('/repo/lib')!;
  files.setChecked(lib, checked: true); // was selectSubtree(libId)
  print(files.checkStateOf(files.tree.roots.single)); // CheckState.partial
  print(files.checkedLeaves.map((node) => node.name)); // (tree.dart, main.dart)
  files.dispose();
}

void _sortAlphabetically(DirectoryTreeController<Object?> controller) {
  controller.tree = DirectoryTree.build(
    controller.tree.entries,
    options: controller.tree.options.copyWith(order: TreeOrder.alphabetical),
  );
}

Widget _enterOnFile(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    onActivate: (row) {
      if (row.node.isFile) controller.toggleSelected(row.id);
    },
  );
  return view;
}

Widget _fixedPage(DirectoryTreeController<Object?> controller) {
  final view = Actions(
    actions: {
      MoveTreeFocusIntent: CallbackAction<MoveTreeFocusIntent>(
        onInvoke: (intent) => controller.moveFocus(
          intent.move,
          selection: intent.selection,
          pageSize: 10,
        ),
      ),
    },
    child: DirectoryTreeView(controller: controller),
  );
  return view;
}

void _listenToSelection(DirectoryTreeController<Object?> controller) {
  var lastSelection = controller.selection;
  controller.addListener(() {
    if (identical(controller.selection, lastSelection)) return;
    lastSelection = controller.selection;
    debugPrint('${lastSelection.length} selected');
  });
}

Widget _iconsFromData(DirectoryTreeController<String> cloud) {
  final view = DirectoryTreeView(
    controller: cloud,
    rowBuilder: (context, details) => DirectoryTreeRow(
      details: details,
      leading: details.row.node.data == 'remote'
          ? const Icon(Icons.cloud_queue, size: 18)
          : null, // null keeps the default icon
    ),
  );
  return view;
}

Widget _subtitles(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    rowBuilder: (context, details) => DirectoryTreeRow(
      details: details,
      trailing: Text(
        details.row.node.isDirectory ? 'folder' : 'file',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ),
  );
  return view;
}

/// The four-file tree of the README, collapsed or with every folder open.
DirectoryTreeController<Object?> _sample({bool expanded = false}) =>
    DirectoryTreeController(
      tree: DirectoryTree.fromPaths([
        '/repo/lib/main.dart',
        '/repo/lib/src/tree.dart',
        '/repo/test/tree_test.dart',
        '/repo/README.md',
      ]),
      expansion: expanded
          ? const ExpansionState.expanded()
          : const ExpansionState.collapsed(),
    );

/// Runs [body] with [debugPrint] recording into the list it receives, and
/// restores [debugPrint] before the test binding checks it.
Future<void> _withDebugLog(Future<void> Function(List<String> log) body) async {
  final log = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) => log.add(message ?? '');
  try {
    await body(log);
  } finally {
    debugPrint = original;
  }
}

/// Trims every line, collapses inner whitespace, and drops blank lines, so
/// indentation inside a test does not hide a copied block.
String _normalize(String code) => code
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
    .where((line) => line.isNotEmpty)
    .join('\n');

/// A `print(...); // output` line; group 1 is the promised output.
final RegExp _printLine = RegExp(
  r'^\s*print\(.*\);\s*// (.*)$',
  multiLine: true,
);

/// The outputs that `print(...); // output` lines in [block] promise.
List<String> _expectedPrints(String block) => [
  for (final match in _printLine.allMatches(block)) match.group(1)!,
];

/// Runs [body] and returns everything it printed.
Future<List<String>> _prints(FutureOr<void> Function() body) async {
  final printed = <String>[];
  await runZoned(
    () async => body(),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => printed.add(line),
    ),
  );
  return printed;
}
