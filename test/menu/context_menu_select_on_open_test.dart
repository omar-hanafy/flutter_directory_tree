import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

// Stand-ins for the names the DirectoryTreeContextMenu sample uses.
final class File {
  const File();
}

final List<String> sampleLog = [];

void rename(TreeNode<File> node) => sampleLog.add('rename ${node.label}');

void delete(List<TreeNode<File>> nodes) =>
    sampleLog.add('delete ${nodes.length}');

/// The class sample of DirectoryTreeContextMenu, verbatim from its
/// documentation.
Widget sample(DirectoryTreeController<File> controller) =>
    DirectoryTreeContextMenu<File>(
      controller: controller,
      builder: (context, details) => [
        MenuItemButton(
          onPressed: () => rename(details.row.node),
          child: const Text('Rename'),
        ),
        MenuItemButton(
          onPressed: () => delete(details.nodes),
          child: const Text('Delete'),
        ),
      ],
      // The Builder's context is below the menu host, so maybeOf finds it.
      child: Builder(
        builder: (context) => CustomScrollView(
          slivers: [
            SliverDirectoryTree<File>(
              controller: controller,
              onRowSecondaryTap: (row, globalPosition) =>
                  DirectoryTreeContextMenu.maybeOf<File>(context)
                      ?.open(row: row, globalPosition: globalPosition),
            ),
          ],
        ),
      ),
    );

DirectoryTree<File> fileTree() => DirectoryTree<File>.build(const [
  TreeEntry<File>.file('/repo/lib/main.dart'),
  TreeEntry<File>.file('/repo/README.md'),
]);

Future<void> secondaryClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  await gesture.addPointer(location: tester.getCenter(finder));
  await gesture.down(tester.getCenter(finder));
  await tester.pump();
  await gesture.up();
  await gesture.removePointer();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the class sample opens the menu from onRowSecondaryTap', (
    tester,
  ) async {
    sampleLog.clear();
    final controller = DirectoryTreeController<File>(
      tree: fileTree(),
      expansion: const ExpansionState.expanded(),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: sample(controller))),
    );
    await secondaryClick(tester, find.text('README.md'));
    expect(find.text('Rename'), findsOneWidget);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(sampleLog, ['rename README.md']);
  });

  group('selectOnOpen', () {
    late DirectoryTreeController<File> controller;
    late List<List<String>> menus;
    late GlobalKey<DirectoryTreeContextMenuState<File>> host;

    Future<void> pumpHost(
      WidgetTester tester, {
      required bool selectOnOpen,
    }) async {
      controller = DirectoryTreeController<File>(
        tree: fileTree(),
        expansion: const ExpansionState.expanded(),
        selection: SelectionState(
          mode: SelectionMode.multiple,
          selected: [controller0Id('/repo/lib/main.dart')],
        ),
      );
      addTearDown(controller.dispose);
      menus = [];
      host = GlobalKey<DirectoryTreeContextMenuState<File>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectoryTreeContextMenu<File>(
              key: host,
              controller: controller,
              selectOnOpen: selectOnOpen,
              builder: (context, details) {
                menus.add([for (final node in details.nodes) node.label]);
                return [
                  MenuItemButton(onPressed: () {}, child: const Text('Item')),
                ];
              },
              child: CustomScrollView(
                slivers: [SliverDirectoryTree<File>(controller: controller)],
              ),
            ),
          ),
        ),
      );
    }

    TreeRow<File> rowNamed(String label) =>
        controller.rows.firstWhere((row) => row.label == label);

    testWidgets('true selects an unselected row first', (tester) async {
      await pumpHost(tester, selectOnOpen: true);
      host.currentState!.open(
        row: rowNamed('README.md'),
        globalPosition: Offset.zero,
      );
      await tester.pumpAndSettle();
      expect(menus, [
        ['README.md'],
      ]);
      expect(
        [for (final n in controller.selectedNodes) n.label],
        ['README.md'],
      );
    });

    testWidgets('false only focuses an unselected row', (tester) async {
      await pumpHost(tester, selectOnOpen: false);
      host.currentState!.open(
        row: rowNamed('README.md'),
        globalPosition: Offset.zero,
      );
      await tester.pumpAndSettle();
      expect(menus, [
        ['README.md'],
      ]);
      expect(
        [for (final n in controller.selectedNodes) n.label],
        ['main.dart'],
      );
      expect(controller.focusedRow?.label, 'README.md');
    });

    testWidgets('false acts on the selection for a selected row', (
      tester,
    ) async {
      await pumpHost(tester, selectOnOpen: false);
      host.currentState!.open(
        row: rowNamed('main.dart'),
        globalPosition: Offset.zero,
      );
      await tester.pumpAndSettle();
      expect(menus, [
        ['main.dart'],
      ]);
    });

    testWidgets('debugFillProperties shows false', (tester) async {
      final builder = DiagnosticPropertiesBuilder();
      DirectoryTreeContextMenu<File>(
        controller: DirectoryTreeController<File>(),
        selectOnOpen: false,
        builder: (_, _) => const [],
        child: const SizedBox(),
      ).debugFillProperties(builder);
      expect(
        builder.properties.map((p) => p.toString()),
        contains('no select on open'),
      );
    });
  });
}

/// The id of [path] in [fileTree].
NodeId controller0Id(String path) => fileTree().idOf(path)!;
