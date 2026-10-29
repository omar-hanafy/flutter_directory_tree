/// Compiles and runs every Dart example in README.md.
///
/// Each README Dart block appears below verbatim: declarations as they are,
/// statements inside a top-level function (so the formatter wraps them as
/// the README does) that a test runs or pumps. The first test fails when a
/// README block has no copy here, and every `print(...); // output` line in
/// a block is an assertion: the printed value must equal the comment. The
/// second test fails when a block's output goes unchecked, and the third
/// when the README's keyboard table differs from the table generated from
/// [DirectoryTreeShortcuts.defaults]. Edit an example in both places, and
/// the suite proves the README still compiles and tells the truth.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final readme = File('README.md').readAsStringSync();
  final blocks = RegExp(r'```dart\n([\s\S]*?)```')
      .allMatches(readme)
      .map((match) => match.group(1)!)
      .toList();

  /// The README block that contains [line].
  String block(String line) => blocks.singleWhere((b) => b.contains(line));

  test('every README Dart block is compiled by this file', () {
    final source = _normalize(File('test/readme_test.dart').readAsStringSync());
    expect(blocks, isNotEmpty);
    final missing = [
      for (final readmeBlock in blocks)
        if (!source.contains(_normalize(readmeBlock))) readmeBlock,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          'Copy these README blocks into test/readme_test.dart:\n'
          '${missing.join('\n---\n')}',
    );
  });

  test('every README output comment is compared with the output', () {
    final source = File('test/readme_test.dart').readAsStringSync();
    final compared = {
      for (final match in RegExp(
        r"_expectedPrints\(block\('([^']+)'\)\)",
      ).allMatches(source))
        block(match.group(1)!),
    };
    for (final readmeBlock in blocks) {
      final prints = readmeBlock
          .split('\n')
          .where((line) => line.trimLeft().startsWith('print('))
          .toList();
      for (final line in prints) {
        expect(
          _printLine.hasMatch(line),
          isTrue,
          reason: 'Write README prints as `print(...); // output`: $line',
        );
      }
      expect(
        prints.isEmpty || compared.contains(readmeBlock),
        isTrue,
        reason:
            'Compare the output of this block with '
            '_expectedPrints(block(...)):\n$readmeBlock',
      );
    }
  });

  test('the keyboard table matches DirectoryTreeShortcuts.defaults', () {
    final table = _shortcutTable();
    expect(
      readme.contains(table),
      isTrue,
      reason: 'Replace the keyboard table in README.md with:\n$table',
    );
  });

  test('the controller examples', () async {
    final printed = await _prints(_controllerExamples);
    expect(printed, [
      ..._expectedPrints(block('controller.expand(repo);')),
      ..._expectedPrints(block('print(controller.expansion.isExpanded(lib))')),
      ..._expectedPrints(block('print(controller.isSelected(lib))')),
      ..._expectedPrints(block('final matches = controller.rows.where')),
    ]);
  });

  test('the lazy loading example', () async {
    final printed = await _prints(_lazyLoadingExample);
    expect(printed, _expectedPrints(block('Future<List<String>> listFolder')));
  });

  test('openFolder reads a folder and loads subfolders lazily', () async {
    final temp = await Directory.systemTemp.createTemp('readme_test');
    addTearDown(() => temp.delete(recursive: true));
    await File('${temp.path}/README.md').writeAsString('hi');
    await Directory('${temp.path}/lib').create();
    await File('${temp.path}/lib/main.dart').writeAsString('void main() {}');

    final controller = await openFolder(temp.path);
    addTearDown(controller.dispose);
    final name = temp.uri.pathSegments.where((s) => s.isNotEmpty).last;
    expect(controller.rows.map((row) => row.label), [name, 'lib', 'README.md']);
    expect(controller.rows.first.node.data, isA<Directory>());

    final lib = controller.rows[1].id;
    expect(controller.loadStatusOf(lib), DirectoryLoadStatus.notLoaded);
    controller.expand(lib);
    await controller.loadChildren(lib);
    expect(controller.rows.map((row) => row.label), [
      name,
      'lib',
      'main.dart',
      'README.md',
    ]);
  });

  testWidgets('the quick start shows the panel and opens folders', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExplorerPane())),
    );
    expect(find.text('Explorer'), findsOneWidget);
    expect(find.byType(DirectoryTreeSearchField), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('src'), findsNothing);

    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    expect(find.text('src'), findsOneWidget);
  });

  testWidgets('the shortcuts example binds Backspace to the parent row', (
    tester,
  ) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => buildTree(context, controller)),
        ),
      ),
    );
    await tester.tap(find.text('main.dart'));
    await tester.pump(kDoubleTapTimeout);
    expect(controller.focusedRow!.label, 'main.dart');

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(controller.focusedRow!.label, 'lib');
  });

  testWidgets('the context menu deletes the selection', (tester) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _contextMenuExample(controller))),
    );

    await tester.tap(find.text('README.md'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    final readmeId = controller.tree.idOf('/repo/README.md')!;
    expect(controller.isSelected(readmeId), isTrue);
    expect(find.text('Expand all below'), findsOneWidget);

    await tester.tap(find.text('Delete 1'));
    await tester.pumpAndSettle();
    expect(controller.tree.nodeAt('/repo/README.md'), isNull);
    expect(find.text('README.md'), findsNothing);
  });

  testWidgets('the drag and drop handler moves the dropped nodes', (
    tester,
  ) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _dragAndDropExample(controller))),
    );

    final tree = controller.tree;
    final src = tree.nodeAt('/repo/lib/src')!;
    final test = tree.nodeAt('/repo/test')! as DirectoryNode<Object?>;
    controller.select(src.id);
    moveInto(controller, DirectoryTreeDropDetails(nodes: [src], target: test));
    await tester.pump();
    expect(controller.tree.nodeAt('/repo/lib/src'), isNull);
    expect(controller.tree.nodeAt('/repo/test/src/tree.dart'), isNotNull);
    expect(controller.tree.nodeAt('/repo/test/tree_test.dart'), isNotNull);
    expect(find.text('src'), findsOneWidget);
  });

  testWidgets('the checkbox view checks rows without selecting them', (
    tester,
  ) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _checkboxExample(controller))),
    );

    expect(find.byType(Checkbox), findsNWidgets(controller.rows.length));
    await tester.tap(find.byType(Checkbox).at(1)); // lib
    await tester.pump();
    expect(controller.checkedLeaves.map((node) => node.name), [
      'tree.dart',
      'main.dart',
    ]);
    await tester.tap(find.text('README.md'));
    await tester.pump(kDoubleTapTimeout);
    expect(controller.selection.isEmpty, isTrue);
  });

  testWidgets('the picker example returns the chosen folder', (tester) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await _withDebugLog((log) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => _pickerExample(context, controller),
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a folder'), findsOneWidget);
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(log, ['chosen: /repo/lib']);
    });
  });

  testWidgets('the theme extension and the subtree theme apply', (
    tester,
  ) async {
    await tester.pumpWidget(_themeExtensionExample());
    final row = find.byType(DirectoryTreeRow<Object?>).first;
    var resolved = DirectoryTreeTheme.of(tester.element(row));
    expect(resolved.rowExtent, 28);
    expect(resolved.indentWidth, 12);
    expect(resolved.guideStyle, DirectoryTreeGuideStyle.connectors);
    expect(tester.getSize(row).height, 28);

    final controller = _sampleController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _subtreeThemeExample(controller))),
    );
    resolved = DirectoryTreeTheme.of(
      tester.element(find.byType(DirectoryTreeRow<Object?>).first),
    );
    expect(resolved.folderIconColor, Colors.amber);
    final proto = DirectoryTree.fromPaths(['/a/x.proto']).nodeAt('/a/x.proto')!;
    expect(
      resolved.iconSet!.iconFor(proto, expanded: false),
      Icons.schema_outlined,
    );
  });

  testWidgets('the custom row examples', (tester) async {
    final (sizes, view) = _rowSlotsExample();
    addTearDown(sizes.dispose);
    sizes.expand(sizes.tree.roots.single);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));
    expect(find.text('1200'), findsOneWidget);
    expect(find.text('640'), findsNothing); // inside the closed lib

    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DirectoryTreeView(
            controller: controller,
            checkboxMode: DirectoryTreeCheckboxMode.checks,
            rowBuilder: buildRow,
          ),
        ),
      ),
    );
    expect(find.byType(DirectoryTreeExpander<Object?>), findsWidgets);
    await tester.tap(find.byType(DirectoryTreeCheckbox<Object?>).at(1)); // lib
    await tester.pump();
    final lib = controller.tree.idOf('/repo/lib')!;
    expect(controller.checkStateOf(lib), CheckState.checked);

    await tester.tap(find.text('README.md'));
    await tester.pump(kDoubleTapTimeout);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.byType(DirectoryTreeExpander<Object?>).at(1)); // lib
    await tester.pumpAndSettle();
    expect(find.text('main.dart'), findsNothing);
  });

  testWidgets('the sliver example activates with Enter and double-click', (
    tester,
  ) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await _withDebugLog((log) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: _sliverExample(controller))),
      );
      expect(find.text('Open editors'), findsOneWidget);

      await tester.tap(find.text('README.md'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(log, ['open /repo/README.md']);

      await tester.tap(find.text('main.dart'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('main.dart'));
      await tester.pump(kDoubleTapTimeout);
      expect(log, ['open /repo/README.md', 'open /repo/lib/main.dart']);
    });
  });

  testWidgets('the sliver menu example opens on Shift+F10 and right clicks', (
    tester,
  ) async {
    final controller = _sampleController(expanded: true);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _sliverMenuExample(controller))),
    );
    await tester.tap(find.text('README.md'));
    await tester.pump(kDoubleTapTimeout);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsNothing);
    await tester.tap(find.text('main.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('the accessibility example labels the tree and the levels', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final controller = _sampleController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _accessibilityExample(controller))),
    );
    expect(find.bySemanticsLabel('Project files'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('repo')).hint, 'Ebene 1');
    handle.dispose();
  });
}

// The README's import lines are this file's own imports.

// README: Quick start.
class ExplorerPane extends StatefulWidget {
  const ExplorerPane({super.key});

  @override
  State<ExplorerPane> createState() => _ExplorerPaneState();
}

class _ExplorerPaneState extends State<ExplorerPane> {
  late final DirectoryTreeController<Object?> _controller;

  @override
  void initState() {
    super.initState();
    final tree = DirectoryTree.fromPaths([
      '/repo/lib/main.dart',
      '/repo/lib/src/tree.dart',
      '/repo/test/tree_test.dart',
      '/repo/README.md',
    ]);
    _controller = DirectoryTreeController(
      tree: tree,
      expansion: ExpansionState.withExpanded(tree.roots),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DirectoryTreePanel(
      controller: _controller,
      title: const Text('Explorer'),
      onActivate: (row) => debugPrint('open ${row.node.path}'),
    );
  }
}

// README: The controller and Search. The blocks run one after another on
// the same controller, as the README presents them.
void _controllerExamples() {
  final controller = DirectoryTreeController(
    tree: DirectoryTree.fromPaths([
      '/repo/lib/main.dart',
      '/repo/lib/src/tree.dart',
      '/repo/test/tree_test.dart',
      '/repo/README.md',
    ]),
  );
  List<String> labels() => [for (final row in controller.rows) row.label];
  final repo = controller.tree.roots.single;
  final lib = controller.tree.idOf('/repo/lib')!;

  controller.expand(repo);
  print(labels()); // [repo, lib, test, README.md]

  controller.select(lib); // a plain click: selects and focuses the row
  controller.moveFocus(
    TreeFocusMove.next, // the down arrow
    selection: TreeSelectionUpdate.extend, // with Shift
  );
  print(controller.focusedRow!.label); // test
  print(controller.selectedNodes.map((node) => node.name)); // (lib, test)

  controller.toggleChecked(lib); // a click on lib's checkbox
  print(controller.checkStateOf(repo)); // CheckState.partial
  final checked = controller.checkedLeaves.map((node) => node.name);
  print(checked); // (tree.dart, main.dart)

  controller.query = 'tree';
  print(labels()); // [repo, lib, src, tree.dart, test, tree_test.dart]
  print(controller.isExpanded(lib)); // true
  print(controller.expansion.isExpanded(lib)); // false

  final saved = controller.expansion.toJson();
  print(saved); // {default: collapsed, exceptions: [/repo]}

  controller.query = '';
  print(labels()); // [repo, lib, test, README.md]
  print(ExpansionState.fromJson(saved) == controller.expansion); // true

  controller.updateTree(
    (builder) => builder.addFile('/repo/lib/src/rows.dart'),
  );
  print(controller.isSelected(lib)); // true
  print(controller.checkStateOf(lib)); // CheckState.partial

  controller.query = 'ext:dart !test';
  final matches = controller.rows.where((row) => row.isMatch);
  print(matches.map((row) => row.label)); // (rows.dart, tree.dart, main.dart)
  print(labels().first); // repo

  controller.query = 'MAIN';
  final main = controller.rows.singleWhere((row) => row.isMatch);
  print(controller.matchRangesOf(main)); // [(end: 4, start: 0)]
  controller.query = '';

  controller.dispose();
}

// README: Lazy loading.
Future<void> _lazyLoadingExample() async {
  // Stands in for a network or database call.
  Future<List<String>> listFolder(String path) async => switch (path) {
    '/bucket' => ['photos/', 'notes.txt'],
    '/bucket/photos' => ['cat.jpg'],
    _ => [],
  };

  final controller = DirectoryTreeController<Object?>(
    tree: DirectoryTree.fromPaths(['/bucket/']),
    loadChildren: (directory) async {
      final path = directory.path.toString();
      return [
        for (final name in await listFolder(path))
          name.endsWith('/')
              ? TreeEntry.directory('$path/$name')
              : TreeEntry.file('$path/$name'),
      ];
    },
    onLoadError: (directory, error, stackTrace) =>
        debugPrint('Cannot open $directory: $error'),
  );
  final bucket = controller.tree.roots.single;
  print(controller.loadStatusOf(bucket)); // DirectoryLoadStatus.notLoaded

  controller.expand(bucket); // starts the load
  print(controller.loadStatusOf(bucket)); // DirectoryLoadStatus.loading
  await controller.loadChildren(bucket); // waits for the running load
  print(controller.rows.map((row) => row.label)); // (bucket, photos, notes.txt)

  final photos = controller.tree.idOf('/bucket/photos')!;
  controller.expand(photos);
  await controller.loadChildren(photos);
  expect(controller.rows.map((row) => row.label), [
    'bucket',
    'photos',
    'cat.jpg',
    'notes.txt',
  ]);
  controller.dispose();
}

// README: The local file system.
Future<DirectoryTreeController<FileSystemEntity>> openFolder(
  String path,
) async {
  const loader = FileSystemTreeLoader();
  final tree = await loader.loadTree(path); // the folder and its children
  return DirectoryTreeController(
    tree: tree,
    expansion: ExpansionState.withExpanded(tree.roots),
    loadChildren: loader.loadChildren,
  );
}

// README: Keyboard.
Widget buildTree(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) {
  return DirectoryTreeView(
    controller: controller,
    shortcuts: {
      ...DirectoryTreeShortcuts.defaults(
        platform: defaultTargetPlatform,
        textDirection: Directionality.of(context),
      ),
      // Backspace goes to the parent folder, as in some file managers.
      const SingleActivator(LogicalKeyboardKey.backspace):
          const MoveTreeFocusIntent(TreeFocusMove.parent),
    },
  );
}

// README: Context menus.
Widget _contextMenuExample(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    contextMenuBuilder: (context, details) => [
      MenuItemButton(
        onPressed: () => controller.expandSubtree(details.row.id),
        child: const Text('Expand all below'),
      ),
      MenuItemButton(
        onPressed: () => controller.updateTree((builder) {
          for (final node in details.nodes) {
            builder.remove(node.path.toString());
          }
        }),
        child: Text('Delete ${details.nodes.length}'),
      ),
    ],
  );
  return view;
}

// README: Drag and drop.
void moveInto(
  DirectoryTreeController<Object?> controller,
  DirectoryTreeDropDetails<Object?> details,
) {
  final tree = controller.tree;
  final target = details.target.path.toString();
  controller.updateTree((builder) {
    for (final node in details.nodes) {
      final from = node.path.toString();
      final parent = from.substring(0, from.lastIndexOf('/'));
      for (final moved in [node, ...tree.descendantsOf(node.id)]) {
        final to = '$target${moved.path.toString().substring(parent.length)}';
        if (moved.isFile) {
          builder.addFile(to);
        } else {
          builder.addDirectory(to);
        }
      }
      builder.remove(from);
    }
  });
}

Widget _dragAndDropExample(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    dragAndDrop: DirectoryTreeDragAndDrop(
      onDrop: (details) => moveInto(controller, details),
    ),
  );
  return view;
}

// README: Checkboxes and the picker.
Widget _checkboxExample(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    checkboxMode: DirectoryTreeCheckboxMode.checks,
    selectOnTap: false,
  );
  return view;
}

Future<void> _pickerExample(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) async {
  final picked = await showDirectoryTreePicker(
    context: context,
    tree: controller.tree,
    mode: DirectoryTreePickerMode.directories,
    title: 'Choose a folder',
  );
  if (picked != null) debugPrint('chosen: ${picked.single.path}');
}

// README: Theming.
Widget _themeExtensionExample() {
  final app = MaterialApp(
    theme: ThemeData(
      extensions: const [
        DirectoryTreeThemeData(
          rowExtent: 28,
          indentWidth: 12,
          guideStyle: DirectoryTreeGuideStyle.connectors,
        ),
      ],
    ),
    home: const Scaffold(body: ExplorerPane()),
  );
  return app;
}

Widget _subtreeThemeExample(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeTheme(
    data: DirectoryTreeThemeData(
      folderIconColor: Colors.amber,
      iconSet: DirectoryTreeIconSet.material.copyWith(
        extensions: {
          ...DirectoryTreeIconSet.material.extensions,
          'proto': Icons.schema_outlined,
        },
      ),
    ),
    child: DirectoryTreeView(controller: controller),
  );
  return view;
}

// README: Custom rows.
(DirectoryTreeController<int>, Widget) _rowSlotsExample() {
  final sizes = DirectoryTreeController<int>(
    tree: DirectoryTree<int>.build([
      TreeEntry.file('/repo/README.md', data: 1200),
      TreeEntry.file('/repo/lib/main.dart', data: 640),
    ]),
  );
  final view = DirectoryTreeView(
    controller: sizes,
    rowBuilder: (context, details) => DirectoryTreeRow(
      details: details,
      trailing: Text('${details.row.node.data ?? ''}'),
    ),
  );
  return (sizes, view);
}

Widget buildRow(
  BuildContext context,
  DirectoryTreeRowDetails<Object?> details,
) {
  final row = details.row;
  return Padding(
    padding: EdgeInsetsDirectional.only(start: 16.0 * row.depth),
    child: Row(
      children: [
        DirectoryTreeExpander(details: details),
        DirectoryTreeCheckbox(details: details),
        Expanded(
          // The row's semantics node already carries the label.
          child: ExcludeSemantics(
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (details.isSelected) const Icon(Icons.check, size: 16),
      ],
    ),
  );
}

// README: Composing with slivers.
Widget _sliverExample(DirectoryTreeController<Object?> controller) {
  final explorer = DirectoryTreeKeyboard(
    controller: controller,
    onActivate: (row) => debugPrint('open ${row.node.path}'),
    child: CustomScrollView(
      slivers: [
        const SliverToBoxAdapter(child: ListTile(title: Text('Open editors'))),
        SliverDirectoryTree(
          controller: controller,
          onActivate: (row) => debugPrint('open ${row.node.path}'),
        ),
      ],
    ),
  );
  return explorer;
}

// README: Composing with slivers, the context menu.
Widget _sliverMenuExample(DirectoryTreeController<Object?> controller) {
  final withMenu = DirectoryTreeContextMenu(
    controller: controller,
    builder: (context, details) => [
      MenuItemButton(
        onPressed: () => debugPrint('rename ${details.row.node.path}'),
        child: const Text('Rename'),
      ),
    ],
    child: DirectoryTreeKeyboard(
      controller: controller,
      child: Builder(
        builder: (context) => CustomScrollView(
          slivers: [
            SliverDirectoryTree(
              controller: controller,
              onRowSecondaryTap: (row, globalPosition) =>
                  DirectoryTreeContextMenu.maybeOf<Object?>(context)
                      ?.open(row: row, globalPosition: globalPosition),
            ),
          ],
        ),
      ),
    ),
  );
  return withMenu;
}

// README: Accessibility.
Widget _accessibilityExample(DirectoryTreeController<Object?> controller) {
  final view = DirectoryTreeView(
    controller: controller,
    semanticLabel: 'Project files',
    levelSemanticsHint: (level) => 'Ebene $level',
  );
  return view;
}

/// The four-file tree most README examples use, collapsed or with every
/// folder open.
DirectoryTreeController<Object?> _sampleController({bool expanded = false}) =>
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

/// The README keyboard table, generated from the default bindings for
/// Windows and macOS in a left-to-right layout.
///
/// Fails when a binding fits no row or more than one, so a new default
/// binding cannot go undocumented.
String _shortcutTable() {
  final windows = DirectoryTreeShortcuts.defaults(
    platform: TargetPlatform.windows,
    textDirection: TextDirection.ltr,
  );
  final macOS = DirectoryTreeShortcuts.defaults(
    platform: TargetPlatform.macOS,
    textDirection: TextDirection.ltr,
  );
  // The README says Linux and Android use the Windows bindings, and iOS
  // the macOS ones.
  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    expect(
      DirectoryTreeShortcuts.defaults(
        platform: platform,
        textDirection: TextDirection.ltr,
      ),
      windows,
    );
  }
  expect(
    DirectoryTreeShortcuts.defaults(
      platform: TargetPlatform.iOS,
      textDirection: TextDirection.ltr,
    ),
    macOS,
  );

  bool move(Intent intent, TreeSelectionUpdate selection) =>
      intent is MoveTreeFocusIntent &&
      intent.move != TreeFocusMove.parent &&
      intent.selection == selection;
  final rows = <(String, bool Function(Intent))>[
    (
      'Move the focus and select that row',
      (intent) => move(intent, TreeSelectionUpdate.replace),
    ),
    (
      'Move the focus and extend the selection from the anchor',
      (intent) => move(intent, TreeSelectionUpdate.extend),
    ),
    (
      'Move the focus without changing the selection',
      (intent) => move(intent, TreeSelectionUpdate.keep),
    ),
    (
      'Move to the parent row and select it',
      (intent) =>
          intent is MoveTreeFocusIntent && intent.move == TreeFocusMove.parent,
    ),
    (
      'Open the folder, or move into an open folder',
      (intent) => intent is ExpandTreeNodeIntent,
    ),
    (
      'Close the folder, or move to the parent row',
      (intent) => intent is CollapseTreeNodeIntent,
    ),
    (
      'Open the folder and every folder below it',
      (intent) => intent is ExpandTreeSubtreeIntent,
    ),
    (
      'Activate the row: a folder opens or closes, then `onActivate` runs',
      (intent) => intent is ActivateTreeNodeIntent,
    ),
    (
      "Toggle the focused row's selection (its check in checks mode)",
      (intent) => intent is ToggleTreeSelectionIntent,
    ),
    (
      'Select every visible row (multiple selection mode only)',
      (intent) => intent is SelectAllTreeNodesIntent,
    ),
    ('Clear the selection', (intent) => intent is ClearTreeSelectionIntent),
    (
      'Open the context menu of the focused row',
      (intent) => intent is OpenTreeContextMenuIntent,
    ),
  ];

  for (final bindings in [windows, macOS]) {
    for (final MapEntry(key: activator, value: intent) in bindings.entries) {
      expect(
        rows.where((row) => row.$2(intent)).length,
        1,
        reason: 'Describe $activator => $intent in exactly one table row.',
      );
    }
  }

  String keys(
    Map<ShortcutActivator, Intent> bindings,
    bool Function(Intent) test,
  ) {
    final names = [
      for (final MapEntry(key: activator, value: intent) in bindings.entries)
        if (test(intent)) _keyName(activator),
    ];
    return names.isEmpty ? 'none' : names.join(', ');
  }

  final buffer = StringBuffer()
    ..writeln('| Action | Windows and Linux | macOS |')
    ..writeln('| --- | --- | --- |');
  for (final (action, test) in rows) {
    buffer.writeln(
      '| $action | ${keys(windows, test)} | ${keys(macOS, test)} |',
    );
  }
  return buffer.toString();
}

/// How the README writes [activator], such as `Shift+Page Up`.
String _keyName(ShortcutActivator activator) {
  if (activator is CharacterActivator) return '`${activator.character}`';
  final single = activator as SingleActivator;
  final key = _keyNames[single.trigger];
  if (key == null) fail('Name ${single.trigger} in _keyNames.');
  return [
    if (single.control) 'Ctrl',
    if (single.meta) 'Cmd',
    if (single.alt) 'Alt',
    if (single.shift) 'Shift',
    key,
  ].join('+');
}

final Map<LogicalKeyboardKey, String> _keyNames = {
  LogicalKeyboardKey.arrowUp: 'Up',
  LogicalKeyboardKey.arrowDown: 'Down',
  LogicalKeyboardKey.arrowLeft: 'Left',
  LogicalKeyboardKey.arrowRight: 'Right',
  LogicalKeyboardKey.home: 'Home',
  LogicalKeyboardKey.end: 'End',
  LogicalKeyboardKey.pageUp: 'Page Up',
  LogicalKeyboardKey.pageDown: 'Page Down',
  LogicalKeyboardKey.numpadAdd: 'Numpad +',
  LogicalKeyboardKey.numpadSubtract: 'Numpad -',
  LogicalKeyboardKey.numpadMultiply: 'Numpad *',
  LogicalKeyboardKey.enter: 'Enter',
  LogicalKeyboardKey.numpadEnter: 'Numpad Enter',
  LogicalKeyboardKey.space: 'Space',
  LogicalKeyboardKey.escape: 'Escape',
  LogicalKeyboardKey.f10: 'F10',
  LogicalKeyboardKey.contextMenu: 'Menu',
  LogicalKeyboardKey.keyA: 'A',
};

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
