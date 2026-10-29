import 'dart:io';

import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

/// Creates a temporary directory that is deleted after the current test.
Directory tempDirectory() {
  final directory = Directory.systemTemp.createTempSync('fdt_io_test');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// Creates directories (paths ending in '/') and files under [base].
void create(Directory base, List<String> paths) {
  for (final path in paths) {
    final full = '${base.path}/$path';
    if (path.endsWith('/')) {
      Directory(full).createSync(recursive: true);
    } else {
      File(full).createSync(recursive: true);
    }
  }
}

/// The standard fixture: a nested folder, hidden entries, an empty folder,
/// and a file at the top.
const List<String> standardFixture = [
  'a/a.txt',
  'a/b/b.txt',
  'a/b/c/deep.txt',
  '.hidden/inner.txt',
  '.env',
  'empty/',
  'top.txt',
];

/// Whether the tests can make a directory unreadable with chmod: a POSIX
/// system and a user that is not root (root reads everything).
bool get canChmod {
  if (Platform.isWindows) return false;
  final id = Process.runSync('id', ['-u']);
  return id.exitCode == 0 && (id.stdout as String).trim() != '0';
}

/// Removes every permission from the directory at [path] until the current
/// test ends.
void lock(String path) {
  final result = Process.runSync('chmod', ['000', path]);
  expect(result.exitCode, 0, reason: 'chmod 000 $path: ${result.stderr}');
  addTearDown(() => Process.runSync('chmod', ['755', path]));
}

/// Gives the directory at [path] its permissions back.
void unlock(String path) {
  final result = Process.runSync('chmod', ['755', path]);
  expect(result.exitCode, 0, reason: 'chmod 755 $path: ${result.stderr}');
}

/// The most specific of Link, Directory, and File for [data], or `none`.
String dataType(FileSystemEntity? data) => switch (data) {
  Link() => 'Link',
  Directory() => 'Directory',
  File() => 'File',
  null => 'none',
  _ => 'unexpected $data',
};

/// The nodes of a tree with a single top-level node, in pre-order, as
/// `kind:path:Data` with paths relative to that node (`.` for itself).
List<String> describeTree(DirectoryTree<FileSystemEntity> tree) {
  final root = tree.rootNodes.single.path;
  return [
    for (final node in tree.nodes)
      '${node.isDirectory ? 'd' : 'f'}:${node.path.relativeTo(root)}:'
          '${dataType(node.data)}',
  ];
}

/// Loader entries as `kind:path:Data`, with paths relative to the tree
/// path [base] they must lie under.
List<String> describeEntries(
  String base,
  Iterable<TreeEntry<FileSystemEntity>> entries,
) {
  final prefix = base.endsWith('/') ? base : '$base/';
  return [
    for (final entry in entries)
      '${entry.isDirectory ? 'd' : 'f'}:'
          '${_under(prefix, entry.path)}:${dataType(entry.data)}',
  ];
}

String _under(String prefix, String path) {
  expect(path.startsWith(prefix), isTrue, reason: '$path is not under $prefix');
  return path.substring(prefix.length);
}

/// The last segment of a `dart:io` path, splitting on both separators.
String nameOf(String path) => path.split(RegExp(r'[/\\]')).last;

/// The directory node at the `dart:io` [path] in [tree].
DirectoryNode<FileSystemEntity> directoryAt(
  DirectoryTree<FileSystemEntity> tree,
  String path,
) {
  final node = tree.nodeAt(path);
  expect(node, isA<DirectoryNode<FileSystemEntity>>(), reason: path);
  return node! as DirectoryNode<FileSystemEntity>;
}

/// The labels of [rows], for readable expectations.
List<String> labelsOf(Iterable<TreeRow<Object?>> rows) => [
  for (final row in rows) row.label,
];
