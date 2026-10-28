@TestOn('vm')
library;

import 'dart:io';

// The Flutter libraries apps import next to this package. With all of them
// and the main library in scope, a name clash with what io.dart exports is
// an "ambiguous import" compile error.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/io.dart';
import 'package:flutter_test/flutter_test.dart';

import 'io_test_utils.dart';

bool skipNothing(FileSystemEntity entity) => false;

/// [path], a `dart:io` path below [base], relative to it with `/`.
String relativeTo(Directory base, String path) =>
    path.substring(base.path.length + 1).replaceAll(r'\', '/');

final Matcher notADirectory = isA<FileSystemException>().having(
  (error) => error,
  'type',
  isNot(isA<PathNotFoundException>()),
);

/// A tree holding only the directory at the `dart:io` [path], with
/// [Directory] data, and that directory's node.
DirectoryNode<FileSystemEntity> lone(String path) => directoryAt(
  DirectoryTree<FileSystemEntity>.build([
    TreeEntry<FileSystemEntity>.directory(path, data: Directory(path)),
  ]),
  path,
);

/// Builds, under [base], a directory holding `lnk`: a relative link to a
/// directory whose resolved path is longer than PATH_MAX, so following it
/// works (it is a directory) while resolving it fails. Returns that
/// directory, or `null` when this platform resolves the link anyway.
String? unresolvableLinkFixture(Directory base) {
  final pathMax = Platform.isMacOS ? 1024 : 4096;
  // Deep enough that the directory's path ends within 250 characters of
  // PATH_MAX, so the 300-character target below goes past it.
  const segment = 101; // '/' plus a 100-character name
  final count = (pathMax - 150 - base.path.length) ~/ segment;
  final directory = [base.path, ...List.filled(count, 'd' * 100)].join('/');
  Directory(directory).createSync(recursive: true);
  // The target's absolute path is longer than PATH_MAX, so it can only be
  // created and deleted through paths relative to the current directory.
  final top = 't' * 100;
  final target = '$top/$top/$top';
  void inDirectory(void Function() body) {
    final saved = Directory.current;
    Directory.current = directory;
    try {
      body();
    } finally {
      Directory.current = saved;
    }
  }

  inDirectory(() => Directory(target).createSync(recursive: true));
  addTearDown(
    () => inDirectory(() => Directory(top).deleteSync(recursive: true)),
  );
  final link = Link('$directory/lnk')..createSync(target);
  if (FileSystemEntity.typeSync(link.path) != FileSystemEntityType.directory) {
    return null;
  }
  try {
    link.resolveSymbolicLinksSync();
    return null;
  } on FileSystemException {
    return directory;
  }
}

void main() {
  late Directory base;

  setUp(() {
    base = tempDirectory();
    create(base, standardFixture);
  });

  group('FileSystemTreeLoader', () {
    test('io.dart exports the loader and the scanner', () {
      const exported = <Type>[FileSystemTreeLoader, DirectoryScanner];
      expect(exported, hasLength(2));
      // The tear-off fits the controller's loader type.
      const loader = FileSystemTreeLoader();
      final DirectoryChildrenLoader<FileSystemEntity> load =
          loader.loadChildren;
      expect(load, loader.loadChildren);
      // One name from each Flutter library keeps its import in use, so the
      // names above resolve with all of them in scope.
      expect(MaterialApp, isNotNull);
      expect(CupertinoApp, isNotNull);
      expect(LogicalKeyboardKey.enter, isNotNull);
    });

    test('defaults, equality, and toString', () {
      const loader = FileSystemTreeLoader();
      expect(loader.includeHidden, isFalse);
      expect(loader.followLinks, isFalse);
      expect(loader.skip, isNull);
      expect(loader, const FileSystemTreeLoader());
      expect(loader.hashCode, const FileSystemTreeLoader().hashCode);
      expect(
        FileSystemTreeLoader(skip: skipNothing),
        FileSystemTreeLoader(skip: skipNothing),
      );
      expect(
        FileSystemTreeLoader(skip: skipNothing).hashCode,
        FileSystemTreeLoader(skip: skipNothing).hashCode,
      );
      expect(loader, isNot(const FileSystemTreeLoader(includeHidden: true)));
      expect(loader, isNot(const FileSystemTreeLoader(followLinks: true)));
      expect(loader, isNot(FileSystemTreeLoader(skip: skipNothing)));
      // Closures compare by identity.
      expect(
        FileSystemTreeLoader(skip: (_) => false),
        isNot(FileSystemTreeLoader(skip: (_) => false)),
      );
      expect(
        loader.toString(),
        'FileSystemTreeLoader(includeHidden: false, followLinks: false, '
        'skip: none)',
      );
      expect(
        FileSystemTreeLoader(
          includeHidden: true,
          followLinks: true,
          skip: skipNothing,
        ).toString(),
        'FileSystemTreeLoader(includeHidden: true, followLinks: true, '
        'skip: set)',
      );
    });
  });

  group('loadTree', () {
    test('depth 1 reads the directory and its children', () async {
      final tree = await const FileSystemTreeLoader().loadTree(base.path);
      expect(describeTree(tree), [
        'd:.:Directory',
        'd:a:Directory',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
      expect(tree.issues, isEmpty);
      final root = tree.rootNodes.single;
      expect(root.path, TreePath.parse(base.path));
      expect(root.data!.path, base.path);
      final a = directoryAt(tree, '${base.path}/a');
      expect(a.hasChildren, isFalse);
      // The entry path is the tree path; the data keeps the dart:io path.
      expect(a.entry!.path, '${root.path}/a');
      expect(a.data!.path, '${base.path}${Platform.pathSeparator}a');
    });

    test('depth 2 reads the grandchildren, and no further', () async {
      final tree = await const FileSystemTreeLoader().loadTree(
        base.path,
        depth: 2,
      );
      expect(describeTree(tree), [
        'd:.:Directory',
        'd:a:Directory',
        'd:a/b:Directory',
        'f:a/a.txt:File',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
      expect(directoryAt(tree, '${base.path}/a/b').hasChildren, isFalse);
    });

    test('depth 0 gives the directory alone', () async {
      final tree = await const FileSystemTreeLoader().loadTree(
        base.path,
        depth: 0,
      );
      expect(describeTree(tree), ['d:.:Directory']);
      expect(tree.rootNodes.single.data!.path, base.path);
    });

    test('every depth matches a scan with that maxDepth', () async {
      for (var depth = 0; depth <= 4; depth++) {
        final tree = await const FileSystemTreeLoader().loadTree(
          base.path,
          depth: depth,
        );
        final scanned = await DirectoryScanner(maxDepth: depth)
            .scanTree(base.path);
        expect(
          [for (final node in tree.nodes) (node.path, node.kind)],
          [for (final node in scanned.nodes) (node.path, node.kind)],
          reason: 'depth $depth',
        );
        expect(
          [for (final node in tree.nodes) node.data?.path],
          [for (final node in scanned.nodes) node.data?.path],
          reason: 'depth $depth',
        );
        expect(describeTree(tree), describeTree(scanned));
      }
    });

    test('a large depth reads everything', () async {
      final tree = await const FileSystemTreeLoader().loadTree(
        base.path,
        depth: 1000,
      );
      expect(
        describeTree(tree),
        describeTree(await const DirectoryScanner().scanTree(base.path)),
      );
      expect(describeTree(tree), contains('f:a/b/c/deep.txt:File'));
    });

    test('a negative depth is an ArgumentError', () async {
      await expectLater(
        const FileSystemTreeLoader().loadTree(base.path, depth: -1),
        throwsArgumentError,
      );
    });

    test('builds the tree with the given options', () async {
      const options = TreeOptions(
        paths: PathPolicy.caseInsensitive,
        order: TreeOrder.alphabetical,
      );
      final tree = await const FileSystemTreeLoader().loadTree(
        base.path,
        options: options,
        depth: 2,
      );
      expect(tree.options, options);
      expect(describeTree(tree), [
        'd:.:Directory',
        'd:a:Directory',
        'f:a/a.txt:File',
        'd:a/b:Directory',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
      expect(tree.nodeAt('${base.path}/A/B'), isNotNull);
    });

    test('includeHidden reads hidden entries at every level', () async {
      final tree = await const FileSystemTreeLoader(includeHidden: true)
          .loadTree(base.path, depth: 2);
      expect(describeTree(tree), [
        'd:.:Directory',
        'd:.hidden:Directory',
        'f:.hidden/inner.txt:File',
        'd:a:Directory',
        'd:a/b:Directory',
        'f:a/a.txt:File',
        'd:empty:Directory',
        'f:.env:File',
        'f:top.txt:File',
      ]);
    });

    test('a hidden directory is read when it is the one loaded', () async {
      final tree = await const FileSystemTreeLoader().loadTree(
        '${base.path}/.hidden',
      );
      expect(describeTree(tree), ['d:.:Directory', 'f:inner.txt:File']);
    });

    test('skip leaves entities out and a skipped directory unread', () async {
      final seen = <String>[];
      final loader = FileSystemTreeLoader(
        skip: (entity) {
          seen.add('${dataType(entity)}:${relativeTo(base, entity.path)}');
          return entity is Directory && nameOf(entity.path) == 'a';
        },
      );
      final tree = await loader.loadTree(base.path, depth: 3);
      expect(describeTree(tree), [
        'd:.:Directory',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
      // Never called for the loaded directory, hidden entities, or anything
      // inside a.
      expect(
        seen,
        unorderedEquals(['Directory:a', 'Directory:empty', 'File:top.txt']),
      );
    });

    test('an exception from skip fails the call, at any level', () async {
      await expectLater(
        FileSystemTreeLoader(skip: (entity) => throw StateError('skip'))
            .loadTree(base.path),
        throwsStateError,
      );
      await expectLater(
        FileSystemTreeLoader(
          skip: (entity) =>
              nameOf(entity.path) == 'b.txt' ? throw StateError('deep') : false,
        ).loadTree(base.path, depth: 3),
        throwsStateError,
      );
    });

    test('a missing path is a PathNotFoundException', () async {
      for (final depth in [0, 1, 2]) {
        await expectLater(
          const FileSystemTreeLoader().loadTree(
            '${base.path}/missing',
            depth: depth,
          ),
          throwsA(isA<PathNotFoundException>()),
          reason: 'depth $depth',
        );
      }
    });

    test('a file path is a FileSystemException', () async {
      for (final depth in [0, 1, 2]) {
        await expectLater(
          const FileSystemTreeLoader().loadTree(
            '${base.path}/top.txt',
            depth: depth,
          ),
          throwsA(notADirectory),
          reason: 'depth $depth',
        );
      }
    });

    group('relative paths', () {
      test('a relative path gives a relative tree', () async {
        Directory('.dart_tool').createSync(recursive: true);
        final relative = Directory('.dart_tool').createTempSync('fdt_io_test');
        addTearDown(() => relative.deleteSync(recursive: true));
        create(relative, ['a/a.txt', 'top.txt']);
        const loader = FileSystemTreeLoader();
        final tree = await loader.loadTree(relative.path);
        final root = tree.rootNodes.single;
        expect(root.path.isAbsolute, isFalse);
        expect(root.path, TreePath.parse(relative.path));
        expect(describeTree(tree), [
          'd:.:Directory',
          'd:a:Directory',
          'f:top.txt:File',
        ]);
        final a = directoryAt(tree, '${relative.path}/a');
        expect(a.data!.isAbsolute, isFalse);
        expect(
          describeEntries(a.path.toString(), await loader.loadChildren(a)),
          ['f:a.txt:File'],
        );
      });

      test(
        'a relative path climbing above its start is read as absolute',
        () async {
          // Reach base from the current directory through more `..`
          // segments than the current directory has, without changing
          // Directory.current (it is process-wide). `..` at a root stays
          // there, so the path escapes its start even from a root.
          final current = TreePath.parse(Directory.current.absolute.path);
          final target = TreePath.parse(base.absolute.path);
          if (current.root != target.root) {
            markTestSkipped('the temp directory is on another drive');
            return;
          }
          final escaping = [
            for (var i = 0; i <= current.segments.length; i++) '..',
            ...target.segments,
          ].join(Platform.pathSeparator);
          expect(TreePath.tryParse(escaping), isNull);
          final tree = await const FileSystemTreeLoader().loadTree(escaping);
          final root = tree.rootNodes.single;
          expect(root.path, target);
          expect(describeTree(tree), [
            'd:.:Directory',
            'd:a:Directory',
            'd:empty:Directory',
            'f:top.txt:File',
          ]);
        },
      );
    });
  });

  group('loadChildren', () {
    late DirectoryTree<FileSystemEntity> tree;

    setUp(() async {
      tree = await const FileSystemTreeLoader().loadTree(base.path);
    });

    test('lists only the direct children, inside the directory', () async {
      final a = directoryAt(tree, '${base.path}/a');
      final children = await const FileSystemTreeLoader().loadChildren(a);
      expect(
        describeEntries(a.path.toString(), children),
        unorderedEquals(['f:a.txt:File', 'd:b:Directory']),
      );
      for (final entry in children) {
        expect(
          entry.data!.path,
          '${a.data!.path}${Platform.pathSeparator}${nameOf(entry.path)}',
        );
      }
      // Merged, the subdirectory has no children yet, ready to load.
      final merged = tree.rebuild((builder) => builder.addAll(children));
      expect(describeTree(merged), [
        'd:.:Directory',
        'd:a:Directory',
        'd:a/b:Directory',
        'f:a/a.txt:File',
        'd:empty:Directory',
        'f:top.txt:File',
      ]);
      expect(directoryAt(merged, '${base.path}/a/b').hasChildren, isFalse);
    });

    test('an empty directory has no children', () async {
      expect(
        await const FileSystemTreeLoader().loadChildren(
          directoryAt(tree, '${base.path}/empty'),
        ),
        isEmpty,
      );
    });

    test(
      'lists the data path and places entries under the tree path',
      () async {
        final folder = directoryAt(
          DirectoryTree<FileSystemEntity>.build([
            TreeEntry<FileSystemEntity>.directory(
              '/virtual/folder',
              data: Directory('${base.path}/a'),
            ),
          ]),
          '/virtual/folder',
        );
        final children = await const FileSystemTreeLoader().loadChildren(
          folder,
        );
        expect([
          for (final entry in children) entry.path,
        ], unorderedEquals(['/virtual/folder/a.txt', '/virtual/folder/b']));
        final separator = Platform.pathSeparator;
        expect(
          [for (final entry in children) entry.data!.path],
          unorderedEquals([
            '${base.path}/a${separator}a.txt',
            '${base.path}/a${separator}b',
          ]),
        );
      },
    );

    test('lists the tree path of a directory without data', () async {
      final a = directoryAt(
        DirectoryTree<FileSystemEntity>.build([
          TreeEntry<FileSystemEntity>.directory('${base.path}/a'),
        ]),
        '${base.path}/a',
      );
      expect(a.data, isNull);
      expect(
        describeEntries(
          a.path.toString(),
          await const FileSystemTreeLoader().loadChildren(a),
        ),
        unorderedEquals(['f:a.txt:File', 'd:b:Directory']),
      );
    });

    test('lists hidden children only with includeHidden', () async {
      final root = tree.rootNodes.single as DirectoryNode<FileSystemEntity>;
      final rootPath = root.path.toString();
      expect(
        describeEntries(
          rootPath,
          await const FileSystemTreeLoader().loadChildren(root),
        ),
        unorderedEquals([
          'd:a:Directory',
          'd:empty:Directory',
          'f:top.txt:File',
        ]),
      );
      expect(
        describeEntries(
          rootPath,
          await const FileSystemTreeLoader(includeHidden: true)
              .loadChildren(root),
        ),
        unorderedEquals([
          'd:.hidden:Directory',
          'd:a:Directory',
          'd:empty:Directory',
          'f:.env:File',
          'f:top.txt:File',
        ]),
      );
    });

    test('a hidden directory lists its children', () async {
      final hidden = lone('${base.path}/.hidden');
      expect(
        describeEntries(
          hidden.path.toString(),
          await const FileSystemTreeLoader().loadChildren(hidden),
        ),
        ['f:inner.txt:File'],
      );
    });

    test('skip sees every child once and never the directory', () async {
      final seen = <String>[];
      final loader = FileSystemTreeLoader(
        includeHidden: true,
        skip: (entity) {
          seen.add('${dataType(entity)}:${relativeTo(base, entity.path)}');
          return entity is File;
        },
      );
      final root = tree.rootNodes.single as DirectoryNode<FileSystemEntity>;
      expect(
        describeEntries(root.path.toString(), await loader.loadChildren(root)),
        unorderedEquals([
          'd:.hidden:Directory',
          'd:a:Directory',
          'd:empty:Directory',
        ]),
      );
      expect(
        seen,
        unorderedEquals([
          'Directory:.hidden',
          'Directory:a',
          'Directory:empty',
          'File:.env',
          'File:top.txt',
        ]),
      );
    });

    test('an exception from skip fails the load', () async {
      await expectLater(
        FileSystemTreeLoader(skip: (entity) => throw StateError('skip'))
            .loadChildren(directoryAt(tree, '${base.path}/a')),
        throwsStateError,
      );
    });

    test('a missing directory is a PathNotFoundException', () async {
      await expectLater(
        const FileSystemTreeLoader().loadChildren(lone('${base.path}/gone')),
        throwsA(isA<PathNotFoundException>()),
      );
    });

    test('a directory that is now a file is a FileSystemException', () async {
      await expectLater(
        const FileSystemTreeLoader().loadChildren(lone('${base.path}/top.txt')),
        throwsA(notADirectory),
      );
    });
  });

  group('a backslash in a POSIX name', () {
    setUp(() => create(base, [r'w/x\y.txt']));

    test('stays one segment when the policy says so', () async {
      const literal = TreeOptions(
        paths: PathPolicy(backslashIsSeparator: false),
      );
      const loader = FileSystemTreeLoader();
      final path = '${base.path}/w';
      final tree = await loader.loadTree(path, options: literal);
      expect(describeTree(tree), ['d:.:Directory', r'f:x\y.txt:File']);
      final lazy = await loader.loadTree(path, options: literal, depth: 0);
      final children = await loader.loadChildren(
        lazy.rootNodes.single as DirectoryNode<FileSystemEntity>,
      );
      expect(
        describeTree(lazy.rebuild((builder) => builder.addAll(children))),
        ['d:.:Directory', r'f:x\y.txt:File'],
      );
    });

    test('is split by the default policy, as a scan does', () async {
      final path = '${base.path}/w';
      final tree = await const FileSystemTreeLoader().loadTree(path);
      expect(describeTree(tree), [
        'd:.:Directory',
        'd:x:none',
        'f:x/y.txt:File',
      ]);
      expect(
        describeTree(tree),
        describeTree(await const DirectoryScanner().scanTree(path)),
      );
    });
  }, skip: Platform.isWindows ? r'\ separates paths on Windows' : false);

  group(
    'links',
    () {
      setUp(() {
        Link('${base.path}/file-link').createSync('${base.path}/top.txt');
        Link('${base.path}/dir-link').createSync('${base.path}/a/b');
        Link('${base.path}/broken').createSync('${base.path}/nowhere');
      });

      test('are files with Link data when not followed', () async {
        final tree = await const FileSystemTreeLoader().loadTree(
          base.path,
          depth: 2,
        );
        expect(describeTree(tree), [
          'd:.:Directory',
          'd:a:Directory',
          'd:a/b:Directory',
          'f:a/a.txt:File',
          'd:empty:Directory',
          'f:broken:Link',
          'f:dir-link:Link',
          'f:file-link:Link',
          'f:top.txt:File',
        ]);
      });

      test('are resolved when followed, as a scan does', () async {
        const loader = FileSystemTreeLoader(followLinks: true);
        for (var depth = 1; depth <= 4; depth++) {
          final tree = await loader.loadTree(base.path, depth: depth);
          final scanned = await DirectoryScanner(
            followLinks: true,
            maxDepth: depth,
          ).scanTree(base.path);
          expect(
            describeTree(tree),
            describeTree(scanned),
            reason: 'depth $depth',
          );
        }
        final tree = await loader.loadTree(base.path, depth: 2);
        expect(describeTree(tree), [
          'd:.:Directory',
          'd:a:Directory',
          'd:a/b:Directory',
          'f:a/a.txt:File',
          'd:dir-link:Directory',
          'd:dir-link/c:Directory',
          'f:dir-link/b.txt:File',
          'd:empty:Directory',
          'f:broken:Link',
          'f:file-link:File',
          'f:top.txt:File',
        ]);
        // A followed link keeps its own path.
        expect(
          tree.nodeAt('${base.path}/dir-link/b.txt')!.data!.path,
          '${base.path}/dir-link/b.txt',
        );
      });

      test('skip sees the resolved entity of a followed link', () async {
        final types = <String, String>{};
        final loader = FileSystemTreeLoader(
          followLinks: true,
          skip: (entity) {
            types[relativeTo(base, entity.path)] = dataType(entity);
            return entity is Directory && nameOf(entity.path) == 'dir-link';
          },
        );
        final tree = await loader.loadTree(base.path, depth: 2);
        expect(tree.nodeAt('${base.path}/dir-link'), isNull);
        expect(types['dir-link'], 'Directory');
        expect(types['file-link'], 'File');
        expect(types['broken'], 'Link');
        expect(types.keys, isNot(contains('dir-link/b.txt')));
        final root = tree.rootNodes.single as DirectoryNode<FileSystemEntity>;
        expect(
          describeEntries(
            root.path.toString(),
            await loader.loadChildren(root),
          ),
          unorderedEquals([
            'd:a:Directory',
            'd:empty:Directory',
            'f:broken:Link',
            'f:file-link:File',
            'f:top.txt:File',
          ]),
        );
      });

      test('loadChildren reads a followed link through its path', () async {
        const loader = FileSystemTreeLoader(followLinks: true);
        final tree = await loader.loadTree(base.path);
        final link = directoryAt(tree, '${base.path}/dir-link');
        expect(link.data, isA<Directory>());
        final children = await loader.loadChildren(link);
        expect(
          describeEntries(link.path.toString(), children),
          unorderedEquals(['f:b.txt:File', 'd:c:Directory']),
        );
        expect(
          [for (final entry in children) entry.data!.path],
          unorderedEquals([
            '${base.path}/dir-link/b.txt',
            '${base.path}/dir-link/c',
          ]),
        );
      });

      test('a link to the directory being listed stays a Link', () async {
        Link('${base.path}/a/here').createSync('.');
        const loader = FileSystemTreeLoader(followLinks: true);
        final a = directoryAt(
          await loader.loadTree(base.path),
          '${base.path}/a',
        );
        expect(
          describeEntries(a.path.toString(), await loader.loadChildren(a)),
          unorderedEquals(['f:a.txt:File', 'd:b:Directory', 'f:here:Link']),
        );
      });

      test(
        'loadTree does not read a link back to an ancestor ahead of time',
        () async {
          Link('${base.path}/a/b/up').createSync(base.path);
          const loader = FileSystemTreeLoader(followLinks: true);
          final tree = await loader.loadTree(base.path, depth: 1000);
          // Everything else is read, once.
          expect(describeTree(tree), [
            'd:.:Directory',
            'd:a:Directory',
            'd:a/b:Directory',
            'd:a/b/c:Directory',
            'f:a/b/c/deep.txt:File',
            'd:a/b/up:Directory',
            'f:a/b/b.txt:File',
            'f:a/a.txt:File',
            'd:dir-link:Directory',
            'd:dir-link/c:Directory',
            'f:dir-link/c/deep.txt:File',
            'd:dir-link/up:Directory',
            'f:dir-link/b.txt:File',
            'd:empty:Directory',
            'f:broken:Link',
            'f:file-link:File',
            'f:top.txt:File',
          ]);
          // It still loads on demand, one level at a time.
          final up = directoryAt(tree, '${base.path}/a/b/up');
          expect(
            describeEntries(up.path.toString(), await loader.loadChildren(up)),
            unorderedEquals([
              'd:a:Directory',
              'd:dir-link:Directory',
              'd:empty:Directory',
              'f:broken:Link',
              'f:file-link:File',
              'f:top.txt:File',
            ]),
          );
        },
      );

      test(
        'a followed link whose target cannot be resolved stays a Link',
        () async {
          final directory = unresolvableLinkFixture(base);
          if (directory == null) {
            markTestSkipped('this platform resolves paths over PATH_MAX');
            return;
          }
          // The scanner reports the link to onError, which a listing
          // failure would use too; the load must still succeed.
          final errors = <FileSystemException>[];
          await DirectoryScanner(
            followLinks: true,
            maxDepth: 1,
            onError: errors.add,
          ).scan(directory);
          expect(errors.single.path, '$directory/lnk');

          const loader = FileSystemTreeLoader(followLinks: true);
          final node = lone(directory);
          expect(
            describeEntries(
              node.path.toString(),
              await loader.loadChildren(node),
            ),
            unorderedEquals(['d:${'t' * 100}:Directory', 'f:lnk:Link']),
          );
          final tree = await loader.loadTree(directory, depth: 2);
          expect(describeTree(tree), contains('f:lnk:Link'));
        },
      );
    },
    skip: Platform.isWindows
        ? 'symbolic links need privileges on Windows'
        : false,
  );

  group('unreadable directories', () {
    test('loadTree of one is a PathAccessException', () async {
      lock('${base.path}/a');
      await expectLater(
        const FileSystemTreeLoader().loadTree('${base.path}/a'),
        throwsA(isA<PathAccessException>()),
      );
    });

    test('below the first level, one stays without children', () async {
      lock('${base.path}/a/b');
      for (final loader in const [
        FileSystemTreeLoader(),
        FileSystemTreeLoader(followLinks: true),
      ]) {
        final tree = await loader.loadTree(base.path, depth: 3);
        expect(describeTree(tree), [
          'd:.:Directory',
          'd:a:Directory',
          'd:a/b:Directory',
          'f:a/a.txt:File',
          'd:empty:Directory',
          'f:top.txt:File',
        ], reason: '$loader');
      }
    });

    test('loadChildren of one is a PathAccessException', () async {
      final tree = await const FileSystemTreeLoader().loadTree(base.path);
      lock('${base.path}/a');
      await expectLater(
        const FileSystemTreeLoader().loadChildren(
          directoryAt(tree, '${base.path}/a'),
        ),
        throwsA(isA<PathAccessException>()),
      );
    });
  }, skip: canChmod ? false : 'needs chmod and a non-root user');
}
