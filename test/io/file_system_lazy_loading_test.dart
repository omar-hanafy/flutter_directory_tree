@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'io_test_utils.dart';

/// The failures a controller reported to its onLoadError.
final class LoadErrors {
  final List<(NodeId, Object)> calls = [];

  void call(NodeId directory, Object error, StackTrace stackTrace) =>
      calls.add((directory, error));
}

void main() {
  late Directory base;

  setUp(() {
    base = tempDirectory();
    create(base, standardFixture);
  });

  /// A controller over [base] read by [loader] to [depth], with hidden
  /// roots unless [showRoots], disposed after the test.
  Future<DirectoryTreeController<FileSystemEntity>> controllerFor(
    FileSystemTreeLoader loader, {
    LoadErrors? errors,
    int depth = 1,
    bool showRoots = false,
  }) async {
    final controller = DirectoryTreeController<FileSystemEntity>(
      tree: await loader.loadTree(base.path, depth: depth),
      showRoots: showRoots,
      loadChildren: loader.loadChildren,
      onLoadError: errors?.call,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  /// The id of [relative] below [base] in the controller's tree.
  NodeId idOf(
    DirectoryTreeController<FileSystemEntity> controller,
    String relative,
  ) => controller.tree.idOf('${base.path}/$relative')!;

  test('with hidden roots, folders load as they are expanded', () async {
    const loader = FileSystemTreeLoader();
    final errors = LoadErrors();
    final controller = await controllerFor(loader, errors: errors);
    final root = controller.tree.roots.single;
    expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows), ['a', 'empty', 'top.txt']);

    final a = idOf(controller, 'a');
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.notLoaded);
    expect(controller.isExpandable(a), isTrue);
    controller.expand(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.loading);
    await controller.loadChildren(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows), ['a', 'b', 'a.txt', 'empty', 'top.txt']);
    final aTxt = idOf(controller, 'a/a.txt');
    expect(controller.loadStatusOf(aTxt), DirectoryLoadStatus.loaded);
    expect(
      controller.tree[aTxt]!.data,
      isA<File>().having(
        (file) => file.path,
        'path',
        '${base.path}${Platform.pathSeparator}a${Platform.pathSeparator}a.txt',
      ),
    );

    final b = idOf(controller, 'a/b');
    expect(controller.loadStatusOf(b), DirectoryLoadStatus.notLoaded);
    controller.expand(b);
    await controller.loadChildren(b);
    expect(controller.loadStatusOf(b), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows), [
      'a',
      'b',
      'c',
      'b.txt',
      'a.txt',
      'empty',
      'top.txt',
    ]);
    expect(
      [for (final row in controller.rows) row.depth],
      [0, 1, 2, 2, 1, 0, 0],
    );
    expect(
      controller.loadStatusOf(idOf(controller, 'a/b/c')),
      DirectoryLoadStatus.notLoaded,
    );

    // An empty folder loads once, then has nothing left to expand.
    final empty = idOf(controller, 'empty');
    controller.expand(empty);
    await controller.loadChildren(empty);
    expect(controller.loadStatusOf(empty), DirectoryLoadStatus.loaded);
    expect(controller.isExpandable(empty), isFalse);
    expect(errors.calls, isEmpty);
  });

  test('a tree read to depth 0 loads its hidden root right away', () async {
    final controller = await controllerFor(
      const FileSystemTreeLoader(),
      depth: 0,
    );
    final root = controller.tree.roots.single;
    expect(controller.loadStatusOf(root), DirectoryLoadStatus.loading);
    expect(controller.rows, isEmpty);
    await controller.loadChildren(root);
    expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows), ['a', 'empty', 'top.txt']);
  });

  test('a shown root loads when it is expanded', () async {
    final controller = await controllerFor(
      const FileSystemTreeLoader(),
      depth: 0,
      showRoots: true,
    );
    final root = controller.tree.roots.single;
    expect(controller.loadStatusOf(root), DirectoryLoadStatus.notLoaded);
    expect(controller.rows, hasLength(1));
    controller.expand(root);
    await controller.loadChildren(root);
    expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows).skip(1), ['a', 'empty', 'top.txt']);
  });

  test('hidden-file and skip rules apply to every load', () async {
    final loader = FileSystemTreeLoader(
      includeHidden: true,
      skip: (entity) => entity is File && entity.path.endsWith('.txt'),
    );
    final controller = await controllerFor(loader);
    expect(labelsOf(controller.rows), ['.hidden', 'a', 'empty', '.env']);

    final hidden = idOf(controller, '.hidden');
    controller.expand(hidden);
    await controller.loadChildren(hidden);
    // Its only file is skipped.
    expect(controller.loadStatusOf(hidden), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows), ['.hidden', 'a', 'empty', '.env']);

    final a = idOf(controller, 'a');
    controller.expand(a);
    await controller.loadChildren(a);
    expect(labelsOf(controller.rows), ['.hidden', 'a', 'b', 'empty', '.env']);

    // The default loader leaves hidden entities out at every level.
    File('${base.path}/a/.secret').createSync();
    final plain = await controllerFor(const FileSystemTreeLoader());
    final plainA = idOf(plain, 'a');
    plain.expand(plainA);
    await plain.loadChildren(plainA);
    expect(labelsOf(plain.rows), ['a', 'b', 'a.txt', 'empty', 'top.txt']);
  });

  test('reloadChildren picks up changes on disk', () async {
    final controller = await controllerFor(const FileSystemTreeLoader());
    final a = idOf(controller, 'a');
    controller.expand(a);
    await controller.loadChildren(a);
    expect(labelsOf(controller.rows), ['a', 'b', 'a.txt', 'empty', 'top.txt']);

    File('${base.path}/a/new.txt').createSync();
    File('${base.path}/a/a.txt').deleteSync();
    await controller.reloadChildren(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.loaded);
    expect(labelsOf(controller.rows), [
      'a',
      'b',
      'new.txt',
      'empty',
      'top.txt',
    ]);
  });

  test('a folder deleted from disk fails to load and is reported', () async {
    final errors = LoadErrors();
    final controller = await controllerFor(
      const FileSystemTreeLoader(),
      errors: errors,
    );
    final a = idOf(controller, 'a');
    Directory('${base.path}/a').deleteSync(recursive: true);
    controller.expand(a);
    await controller.loadChildren(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.failed);
    expect(controller.loadErrorOf(a), isA<PathNotFoundException>());
    expect(errors.calls, hasLength(1));
    expect(errors.calls.single.$1, a);
    expect(errors.calls.single.$2, same(controller.loadErrorOf(a)));
  });

  test('an exception from skip fails the load and is reported', () async {
    var throwing = false;
    final loader = FileSystemTreeLoader(
      skip: (entity) => throwing ? throw StateError('skip') : false,
    );
    final errors = LoadErrors();
    final controller = await controllerFor(loader, errors: errors);
    final a = idOf(controller, 'a');
    throwing = true;
    controller.expand(a);
    await controller.loadChildren(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.failed);
    expect(controller.loadErrorOf(a), isStateError);
    expect(errors.calls.single.$1, a);
  });

  test('an unreadable folder fails, is reported, and loads on retry', () async {
    final errors = LoadErrors();
    final controller = await controllerFor(
      const FileSystemTreeLoader(),
      errors: errors,
    );
    final a = idOf(controller, 'a');
    lock('${base.path}/a');
    controller.expand(a);
    await controller.loadChildren(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.failed);
    expect(controller.loadErrorOf(a), isA<PathAccessException>());
    expect(errors.calls, hasLength(1));
    expect(errors.calls.single.$1, a);
    expect(errors.calls.single.$2, isA<PathAccessException>());
    // The folder stays expanded, with no children, and can be retried.
    expect(controller.isExpanded(a), isTrue);
    expect(controller.isExpandable(a), isTrue);
    expect(labelsOf(controller.rows), ['a', 'empty', 'top.txt']);

    unlock('${base.path}/a');
    await controller.loadChildren(a);
    expect(controller.loadStatusOf(a), DirectoryLoadStatus.loaded);
    expect(controller.loadErrorOf(a), isNull);
    expect(labelsOf(controller.rows), ['a', 'b', 'a.txt', 'empty', 'top.txt']);
    expect(errors.calls, hasLength(1));
  }, skip: canChmod ? false : 'needs chmod and a non-root user');

  test(
    'a folder unreadable during loadTree loads when expanded later',
    () async {
      lock('${base.path}/a');
      final errors = LoadErrors();
      final controller = await controllerFor(
        const FileSystemTreeLoader(),
        errors: errors,
        depth: 3,
      );
      final a = idOf(controller, 'a');
      expect(controller.loadStatusOf(a), DirectoryLoadStatus.notLoaded);
      unlock('${base.path}/a');
      controller.expand(a);
      await controller.loadChildren(a);
      expect(controller.loadStatusOf(a), DirectoryLoadStatus.loaded);
      expect(labelsOf(controller.rows), [
        'a',
        'b',
        'a.txt',
        'empty',
        'top.txt',
      ]);
      expect(errors.calls, isEmpty);
    },
    skip: canChmod ? false : 'needs chmod and a non-root user',
  );
}
