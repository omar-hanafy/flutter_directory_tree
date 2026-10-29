@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_directory_tree_example/demos/file_system/file_system_browser_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lets real file system work finish and pumps until [finder] finds
/// something, or fails after about five seconds.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fdt_example_');
    await File('${root.path}/visible.txt').writeAsString('v');
    await File('${root.path}/.hidden_file').writeAsString('h');
    await File('${root.path}/folder/inner.txt').create(recursive: true);
    await File('${root.path}/locked/secret.txt').create(recursive: true);
  });

  tearDown(() async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', '${root.path}/locked']);
    }
    await root.delete(recursive: true);
  });

  Future<void> pumpBrowser(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FileSystemBrowser(rootPath: root.path)),
      ),
    );
    await waitFor(tester, find.text('visible.txt'));
  }

  testWidgets('lists the folder lazily and hides dot files by default', (
    tester,
  ) async {
    await pumpBrowser(tester);
    expect(find.text('folder'), findsOneWidget);
    expect(find.text('.hidden_file'), findsNothing);
    // folder's contents are read only when it opens.
    expect(find.text('inner.txt'), findsNothing);
    await tester.tap(find.text('folder'));
    await waitFor(tester, find.text('inner.txt'));
  });

  testWidgets('the hidden-files toggle reloads the folder', (tester) async {
    await pumpBrowser(tester);
    await tester.tap(find.byTooltip('Show hidden files'));
    await waitFor(tester, find.text('.hidden_file'));
    await tester.tap(find.byTooltip('Hide hidden files'));
    // The reload empties the folder at once and then lists it again.
    await tester.pump();
    expect(find.text('.hidden_file'), findsNothing);
    await waitFor(tester, find.text('visible.txt'));
    expect(find.text('.hidden_file'), findsNothing);
  });

  testWidgets('a folder that cannot be read reports it in a SnackBar', (
    tester,
  ) async {
    await tester.runAsync(
      () => Process.run('chmod', ['000', '${root.path}/locked']),
    );
    await pumpBrowser(tester);
    await tester.tap(find.text('locked'));
    await waitFor(tester, find.textContaining('Could not open locked'));
    expect(find.text('secret.txt'), findsNothing);
  }, skip: Platform.isWindows);

  testWidgets('a missing root folder shows the error instead of a tree', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FileSystemBrowser(rootPath: '${root.path}/does_not_exist'),
        ),
      ),
    );
    await waitFor(tester, find.textContaining('Could not read'));
  });
}
