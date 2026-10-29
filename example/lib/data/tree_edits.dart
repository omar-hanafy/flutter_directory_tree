import 'package:flutter_directory_tree/flutter_directory_tree.dart';

/// Edits on a list of tree entries, the way an app edits its own data
/// before it builds a new [DirectoryTree] and gives it to the controller.
///
/// Every function returns a new list and keeps the input as it is. Paths
/// are canonical strings such as `/acme_app/lib/main.dart`.
abstract final class TreeEdits {
  /// Whether [path] is [prefix] itself or lies inside it.
  static bool isWithin(String path, String prefix) =>
      path == prefix || path.startsWith('$prefix/');

  /// A copy of [entry] at [path], with the same kind and data.
  static TreeEntry<T> withPath<T>(TreeEntry<T> entry, String path) =>
      entry.isFile
      ? TreeEntry<T>.file(path, data: entry.data)
      : TreeEntry<T>.directory(path, data: entry.data);

  /// [entries] plus a new file at [path] with [data].
  static List<TreeEntry<T>> addFile<T>(
    List<TreeEntry<T>> entries,
    String path, {
    T? data,
  }) => [...entries, TreeEntry<T>.file(path, data: data)];

  /// [entries] with everything at or inside [from] moved to [to].
  static List<TreeEntry<T>> rename<T>(
    List<TreeEntry<T>> entries,
    String from,
    String to,
  ) => [
    for (final entry in entries)
      if (isWithin(entry.path, from))
        withPath(entry, to + entry.path.substring(from.length))
      else
        entry,
  ];

  /// [entries] without the nodes at [paths] and everything inside them.
  ///
  /// Each parent directory in [keepParents] becomes an explicit directory
  /// entry, so a folder stays in the tree when its last child goes away.
  static List<TreeEntry<T>> delete<T>(
    List<TreeEntry<T>> entries,
    Iterable<String> paths, {
    Iterable<String> keepParents = const [],
  }) {
    final removed = paths.toList();
    final kept = <TreeEntry<T>>[
      for (final entry in entries)
        if (!removed.any((path) => isWithin(entry.path, path))) entry,
    ];
    for (final parent in keepParents) {
      if (!removed.any((path) => isWithin(parent, path))) {
        kept.add(TreeEntry<T>.directory(parent));
      }
    }
    return kept;
  }

  /// [entries] with the nodes at [paths] moved into the directory [target],
  /// keeping their names.
  ///
  /// The old parent directories stay in the tree as explicit directories.
  static List<TreeEntry<T>> move<T>(
    List<TreeEntry<T>> entries,
    List<TreePath> paths,
    TreePath target,
  ) {
    var next = entries;
    for (final path in paths) {
      final parent = path.parent;
      next = rename(next, path.toString(), target.child(path.name).toString());
      if (parent != null && !parent.isRoot) {
        next = [...next, TreeEntry<T>.directory(parent.toString())];
      }
    }
    return next;
  }
}
