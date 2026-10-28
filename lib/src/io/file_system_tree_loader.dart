import 'dart:io';

import 'package:directory_tree/directory_tree.dart';
import 'package:directory_tree/io.dart';
import 'package:flutter/foundation.dart' show immutable;
// Imported only so documentation references to the controller resolve.
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';

/// Reads directory trees from the local file system one level at a time,
/// for tree views that load folders when they are opened.
///
/// [loadTree] reads a directory and as many levels below it as you ask
/// for; [loadChildren] reads the direct children of one directory. Pass
/// [loadChildren] as a tear-off to [DirectoryTreeController.new], and the
/// controller reads a folder only when the user expands it:
///
/// ```dart
/// const loader = FileSystemTreeLoader();
/// final controller = DirectoryTreeController<FileSystemEntity>(
///   tree: await loader.loadTree('/home/me/project'),
///   loadChildren: loader.loadChildren,
///   onLoadError: (directory, error, stackTrace) =>
///       debugPrint('Cannot open $directory: $error'),
/// );
/// ```
///
/// Use it for file browsers and pickers over large or slow directories. To
/// read a whole directory tree at once, use [DirectoryScanner.scanTree]
/// instead.
///
/// Every directory is listed with a [DirectoryScanner], one level deep, and
/// each child becomes an entry of the kind, and with the data, that the
/// scanner reports:
///
/// * a directory: `TreeEntry.directory` with [Directory] data;
/// * a file, or any other entity that is not a directory (a pipe, a
///   socket): `TreeEntry.file` with [File] data;
/// * a symbolic link that is not followed: `TreeEntry.file` with [Link]
///   data (see [followLinks]).
///
/// Each child's entry path is the tree path of the directory that was
/// listed, followed by `/` and the child's name, so the children always
/// land inside that directory whatever spelling the tree uses. Each
/// child's data keeps the path exactly as `dart:io` reports it, and that is
/// the path a later [loadChildren] lists.
///
/// [includeHidden] and then [skip] decide which children are listed; the
/// directory being read is never filtered.
///
/// Requires `dart:io`, so it works on Android, iOS, Linux, macOS, and
/// Windows, but not on the web.
@immutable
final class FileSystemTreeLoader {
  /// Creates a loader; the directory to read is given later to [loadTree]
  /// or [loadChildren], so one loader serves a whole tree.
  ///
  /// By default, hidden entities are left out, symbolic links are not
  /// followed, and nothing else is skipped. A `const` loader works as a
  /// shared default:
  ///
  /// ```dart
  /// const loader = FileSystemTreeLoader(includeHidden: true);
  /// ```
  const FileSystemTreeLoader({
    this.includeHidden = false,
    this.followLinks = false,
    this.skip,
  });

  /// Whether entities whose name starts with `.` are listed.
  ///
  /// When false (the default), hidden files are left out and hidden
  /// directories are neither listed nor read. The directory being read is
  /// always read, even when its own name starts with `.`, such as `.git`.
  /// Only the leading dot counts; Windows hidden attributes are not
  /// consulted.
  final bool includeHidden;

  /// Whether symbolic links are resolved.
  ///
  /// When false (the default), every link is listed as a file with [Link]
  /// data and is never read, so the tree never leaves the directory you
  /// loaded.
  ///
  /// When true, a link to a directory is listed as a directory with
  /// [Directory] data, and its children are read through the link's path
  /// like any other directory's; a link to a file is listed as a file with
  /// [File] data. Both keep the link's own path. A broken link, a link to
  /// the directory being listed, and a link whose target cannot be
  /// resolved stay files with [Link] data.
  ///
  /// A link can lead back to one of its own ancestors. [loadTree] never
  /// reads such a directory ahead of time, so it always finishes; the
  /// directory stays without children and still loads one level each time
  /// it is expanded. Following links costs extra file-system calls: up to
  /// two per link and two per directory read.
  final bool followLinks;

  /// Decides which entities to leave out; return true to omit one.
  ///
  /// Called once for every listed entity that passes [includeHidden], with
  /// the object that becomes the entry's data: a [Directory], a [File], or
  /// a [Link] (see [followLinks]). An omitted directory is never read. Never
  /// called for the directory being read. `null` (the default) keeps
  /// everything.
  ///
  /// It runs synchronously while a directory is listed. An exception it
  /// throws makes [loadTree] or [loadChildren] complete with that
  /// exception.
  final bool Function(FileSystemEntity entity)? skip;

  /// Reads the directory at [path] and [depth] levels below it into a new
  /// tree built with [options].
  ///
  /// The tree holds the directory itself (a directory entry with
  /// [Directory] data, so with the default [TreeRoots.minimal] roots it is
  /// the single top-level node) and its contents down to [depth] levels:
  /// 1 (the default) lists its children, 2 adds their children, and 0 lists
  /// nothing. Directories on the last level are in the tree without
  /// children. Give the tree to a [DirectoryTreeController] whose loader is
  /// [loadChildren], and those directories load when they are expanded.
  /// An empty directory looks the same as one that was not read yet, so the
  /// controller lists it once more when it is first expanded.
  ///
  /// [path] is read as given, so a relative path gives a relative tree,
  /// whose later loads resolve against the current directory of that
  /// moment. A relative path that climbs above its start, such as `..` or
  /// `../project`, is read through its absolute form instead, as
  /// [DirectoryScanner.scanTree] does. Entry paths are parsed by
  /// [TreeOptions.paths].
  ///
  /// Completes with an [ArgumentError] when [depth] is negative, a
  /// [PathNotFoundException] when nothing exists at [path], a
  /// [FileSystemException] when [path] is not a directory or cannot be
  /// listed completely (for example a [PathAccessException] without read
  /// permission), and any exception [skip] throws.
  ///
  /// A directory below [path] that cannot be listed does not fail the
  /// call: it stays in the tree without children, so the controller tries
  /// again when it is expanded and reports the failure through its
  /// `onLoadError`. To be told about every failure right away, scan with a
  /// [DirectoryScanner] and its `onError` instead.
  ///
  /// Reads one directory at a time with asynchronous `dart:io` calls, so
  /// the UI stays responsive. Takes one directory listing per directory
  /// above the last level, and O(n log n) time for the n entities read.
  Future<DirectoryTree<FileSystemEntity>> loadTree(
    String path, {
    TreeOptions options = const TreeOptions(),
    int depth = 1,
  }) async {
    if (depth < 0) {
      throw ArgumentError.value(depth, 'depth', 'must be >= 0');
    }
    final policy = options.paths;
    final readPath = _readPath(path, policy);
    final base = policy.tryParse(readPath)?.toString() ?? readPath;
    final List<TreeEntry<FileSystemEntity>> children;
    if (depth == 0) {
      // The scanner checks that readPath is a directory, with the same
      // errors as a listing, without listing it.
      await DirectoryScanner(
        followLinks: followLinks,
        maxDepth: 0,
      ).scan(readPath);
      children = const <TreeEntry<FileSystemEntity>>[];
    } else {
      children = await _list(readPath, base);
    }
    final entries = <TreeEntry<FileSystemEntity>>[
      TreeEntry<FileSystemEntity>.directory(base, data: Directory(readPath)),
      ...children,
    ];
    if (depth > 1) await _listBelow(readPath, children, depth, entries);
    return DirectoryTree<FileSystemEntity>.build(entries, options: options);
  }

  /// Lists the direct children of [directory] on disk.
  ///
  /// Pass it as a tear-off to [DirectoryTreeController.new] as
  /// `loadChildren`: the controller calls it when a directory without
  /// children is expanded and merges the entries into its tree.
  ///
  /// It lists `directory.data.path`: the path `dart:io` reported for the
  /// directory, or the one [loadTree] was given. A node without data, such
  /// as an inferred directory, is listed at its tree path instead
  /// ([TreePath.toString], whose `/` separators `dart:io` accepts on
  /// Windows too). Each entry's path is the directory's tree path followed
  /// by `/` and the child's name, so the controller always accepts it as
  /// inside the directory. Children are filtered by [includeHidden] and
  /// [skip], and links are handled by [followLinks], exactly as in
  /// [loadTree]. Grandchildren are never read, so a subdirectory comes back
  /// without children and loads when it is expanded in turn.
  ///
  /// Completes with a [PathNotFoundException] when the directory no longer
  /// exists, a [FileSystemException] when it is not a directory or cannot
  /// be listed completely (for example a [PathAccessException] without
  /// read permission), and any exception [skip] throws. A partial listing
  /// is never returned. The controller turns the error into
  /// [DirectoryLoadStatus.failed], keeps it for
  /// [DirectoryTreeController.loadErrorOf], and passes it to its
  /// `onLoadError`; expanding the directory again retries.
  ///
  /// Takes one asynchronous directory listing and O(k log k) time for the
  /// k children.
  Future<Iterable<TreeEntry<FileSystemEntity>>> loadChildren(
    DirectoryNode<FileSystemEntity> directory,
  ) {
    final base = directory.path.toString();
    return _list(directory.data?.path ?? base, base);
  }

  /// Lists the directory at [path] one level deep and returns entries for
  /// its children, placed under the tree path [base].
  ///
  /// Throws what [DirectoryScanner.scan] throws, and the first listing
  /// failure that the scanner reported to its `onError`: a full scan keeps
  /// going after one, but a lazy load must not show a partial listing as
  /// complete.
  Future<List<TreeEntry<FileSystemEntity>>> _list(
    String path,
    String base,
  ) async {
    final failures = <FileSystemException>[];
    // With followLinks, the scanner also reports a link whose target cannot
    // be resolved to onError, and then still lists it, as a Link that skip
    // sees. Its error carries the link's own path, while a listing failure
    // carries the directory's path or that of an entity that was not
    // listed, so the links skip saw tell the two apart.
    final links = followLinks ? <String>{} : null;
    final userSkip = skip;
    final scanned = await DirectoryScanner(
      includeHidden: includeHidden,
      followLinks: followLinks,
      maxDepth: 1,
      skip: links == null
          ? userSkip
          : (entity) {
              if (entity is Link) links.add(entity.path);
              return userSkip != null && userSkip(entity);
            },
      onError: failures.add,
    ).scan(path);
    for (final failure in failures) {
      if (links == null || !links.contains(failure.path)) throw failure;
    }
    // The scanner lists the directory itself too, as the only entry with
    // exactly the scanned path; every child's path is longer.
    return <TreeEntry<FileSystemEntity>>[
      for (final entry in scanned)
        if (entry.path != path) _placed(entry, base),
    ];
  }

  /// Lists the directories among [children] of the directory at [rootPath],
  /// and the directories below them, down to [depth] levels below that
  /// directory, adding every entry to [entries].
  ///
  /// The walk is depth first with an explicit stack, like the scanner's,
  /// so very deep trees cannot overflow the call stack. A directory that
  /// cannot be listed is left without children; the controller loads it
  /// when it is expanded and reports the error then. With [followLinks],
  /// the real paths of the directories on the current branch are tracked:
  /// a directory whose real path is already on the branch was reached again
  /// through a link, and listing it would repeat the branch until [depth]
  /// runs out, so it is left without children too.
  Future<void> _listBelow(
    String rootPath,
    List<TreeEntry<FileSystemEntity>> children,
    int depth,
    List<TreeEntry<FileSystemEntity>> entries,
  ) async {
    final active = <String>{
      if (followLinks) await Directory(rootPath).resolveSymbolicLinks(),
    };
    final stack = <_Step>[];
    _pushDirectories(stack, children, 1);
    while (stack.isNotEmpty) {
      switch (stack.removeLast()) {
        case _Leave(:final resolved):
          active.remove(resolved);
        case _Visit(:final path, :final base, :final level):
          String? resolved;
          if (followLinks) {
            try {
              resolved = await Directory(path).resolveSymbolicLinks();
            } on FileSystemException {
              continue;
            }
            if (active.contains(resolved)) continue;
          }
          final List<TreeEntry<FileSystemEntity>> listed;
          try {
            listed = await _list(path, base);
          } on FileSystemException {
            continue;
          }
          entries.addAll(listed);
          if (resolved != null) {
            active.add(resolved);
            // Below the children pushed next, so it pops after their
            // whole subtrees.
            stack.add(_Leave(resolved));
          }
          if (level + 1 < depth) _pushDirectories(stack, listed, level + 1);
      }
    }
  }

  /// Pushes a visit for every directory among [entries], at [level].
  static void _pushDirectories(
    List<_Step> stack,
    List<TreeEntry<FileSystemEntity>> entries,
    int level,
  ) {
    for (final entry in entries) {
      final data = entry.data;
      if (entry.isDirectory && data != null) {
        stack.add(_Visit(data.path, entry.path, level));
      }
    }
  }

  /// [entry] with its path moved under the tree path [base], keeping its
  /// kind and data.
  static TreeEntry<FileSystemEntity> _placed(
    TreeEntry<FileSystemEntity> entry,
    String base,
  ) {
    final name = _nameOf(entry.path);
    // Only path roots (`/`, `C:/`, `//server/share/`) end with a separator.
    final path = base.endsWith('/') ? '$base$name' : '$base/$name';
    return entry.isDirectory
        ? TreeEntry<FileSystemEntity>.directory(path, data: entry.data)
        : TreeEntry<FileSystemEntity>.file(path, data: entry.data);
  }

  /// The path [loadTree] reads for [path]: [path] itself when [policy]
  /// parses it, and its absolute form when only that parses (a relative
  /// path that climbs above its start), as `DirectoryScanner.scanTree`
  /// does.
  ///
  /// An empty path stays empty so the scanner reports it as missing rather
  /// than reading the current directory, and a path that is invalid in both
  /// forms is kept so the scanner reports the caller's spelling.
  static String _readPath(String path, PathPolicy policy) {
    if (path.isEmpty || policy.tryParse(path) != null) return path;
    final absolute = Directory(path).absolute.path;
    return policy.tryParse(absolute) == null ? path : absolute;
  }

  /// The last segment of a path `dart:io` listed (listed paths never end
  /// with a separator). Only `/` separates on POSIX, where `\` is a legal
  /// character in names; Windows also separates with `\`.
  static String _nameOf(String path) {
    var end = path.lastIndexOf('/');
    if (Platform.isWindows) {
      final backslash = path.lastIndexOf(r'\');
      if (backslash > end) end = backslash;
    }
    return path.substring(end + 1);
  }

  /// Whether [other] is a [FileSystemTreeLoader] with equal settings.
  ///
  /// [skip] is compared with `==`, so two loaders built with separate
  /// closures are not equal even when the closures behave the same; pass
  /// the same function (for example a top-level function tear-off) to make
  /// them equal.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileSystemTreeLoader &&
          other.includeHidden == includeHidden &&
          other.followLinks == followLinks &&
          other.skip == skip;

  @override
  int get hashCode => Object.hash(includeHidden, followLinks, skip);

  @override
  String toString() =>
      'FileSystemTreeLoader(includeHidden: $includeHidden, '
      'followLinks: $followLinks, '
      'skip: ${skip == null ? 'none' : 'set'})';
}

/// One step of the walk in [FileSystemTreeLoader._listBelow].
sealed class _Step {
  const _Step();
}

/// A directory to list: [path] is where `dart:io` finds it, [base] is its
/// path in the tree, and [level] is its distance from the directory that
/// [FileSystemTreeLoader.loadTree] reads.
final class _Visit extends _Step {
  const _Visit(this.path, this.base, this.level);

  final String path;
  final String base;
  final int level;
}

/// Marks that the walk finished the subtree of a directory, so its real
/// path [resolved] leaves the current branch.
final class _Leave extends _Step {
  const _Leave(this.resolved);

  final String resolved;
}
