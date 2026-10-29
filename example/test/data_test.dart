import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree_example/data/large_tree.dart';
import 'package:flutter_directory_tree_example/data/sample_project.dart';
import 'package:flutter_directory_tree_example/data/tree_edits.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> pathsOf(DirectoryTree<Object?> tree) => [
  for (final node in tree.nodes) node.path.toString(),
];

DirectoryTree<int> build(List<TreeEntry<int>> entries) =>
    DirectoryTree<int>.build(entries);

void main() {
  final entries = <TreeEntry<int>>[
    const TreeEntry<int>.file('/r/a/x.txt', data: 1),
    const TreeEntry<int>.file('/r/a/y.txt', data: 2),
    const TreeEntry<int>.file('/r/b/z.txt', data: 3),
    const TreeEntry<int>.directory('/r/c'),
  ];

  group('TreeEdits', () {
    test('rename moves the node and everything inside it', () {
      final tree = build(TreeEdits.rename(entries, '/r/a', '/r/d'));
      expect(tree.nodeAt('/r/a'), isNull);
      expect(tree.nodeAt('/r/d/x.txt')?.data, 1);
      expect(tree.nodeAt('/r/d/y.txt')?.data, 2);
      // A sibling that only shares the prefix is untouched.
      final prefixed = TreeEdits.rename(
        [...entries, const TreeEntry<int>.file('/r/ab.txt')],
        '/r/a',
        '/r/d',
      );
      expect(prefixed.map((entry) => entry.path), contains('/r/ab.txt'));
    });

    test('delete removes subtrees and keeps the parents', () {
      final tree = build(
        TreeEdits.delete(entries, ['/r/b/z.txt'], keepParents: ['/r/b']),
      );
      expect(tree.nodeAt('/r/b/z.txt'), isNull);
      expect(tree.nodeAt('/r/b'), isA<DirectoryNode<int>>());
      final whole = build(TreeEdits.delete(entries, ['/r/a']));
      expect(pathsOf(whole), isNot(contains('/r/a/x.txt')));
    });

    test('move keeps names and data and leaves the old folder', () {
      final tree = build(entries);
      final moved = build(
        TreeEdits.move(entries, [
          tree.nodeAt('/r/a/x.txt')!.path,
          tree.nodeAt('/r/b/z.txt')!.path,
        ], tree.nodeAt('/r/c')!.path),
      );
      expect(moved.nodeAt('/r/c/x.txt')?.data, 1);
      expect(moved.nodeAt('/r/c/z.txt')?.data, 3);
      expect(moved.nodeAt('/r/b'), isA<DirectoryNode<int>>());
      expect(moved.childrenOf(moved.nodeAt('/r/b')!.id), isEmpty);
    });

    test('a moved folder takes its contents along', () {
      final tree = build(entries);
      final moved = build(
        TreeEdits.move(entries, [
          tree.nodeAt('/r/a')!.path,
        ], tree.nodeAt('/r/c')!.path),
      );
      expect(moved.nodeAt('/r/c/a/x.txt')?.data, 1);
      expect(moved.nodeAt('/r/a'), isNull);
    });
  });

  group('generated data', () {
    test('the large tree has exactly the requested node count', () {
      final tree = DirectoryTree<Object?>.build(largeTreeEntries());
      expect(tree.length, 100000);
      expect(tree.rootNodes.single.path.toString(), largeRoot);
      expect(
        DirectoryTree<Object?>.build(largeTreeEntries(nodeCount: 5000)).length,
        5000,
      );
    });

    test('the sample project has one root and stable sizes', () {
      final first = sampleProjectTree();
      final second = sampleProjectTree();
      expect(first.rootNodes.single.path.toString(), sampleRoot);
      expect(first.nodes, orderedEquals(second.nodes));
      expect(first.issues, isEmpty);
    });

    test('formatters', () {
      expect(formatCount(100000), '100,000');
      expect(formatCount(999), '999');
      expect(formatSize(512), '512 B');
      expect(formatSize(2048), '2.0 KB');
    });
  });
}
