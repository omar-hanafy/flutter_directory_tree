import 'package:directory_tree/directory_tree.dart';
// Imported only so documentation references to the controller resolve.
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';

/// Loads the children of a lazily loaded directory.
///
/// Pass one to [DirectoryTreeController.new] as `loadChildren`. The
/// controller calls it with the [DirectoryNode] whose contents are wanted
/// (when [DirectoryTreeController.expand] opens a directory that was never
/// loaded or waits to be listed again, or from
/// [DirectoryTreeController.loadChildren] and
/// [DirectoryTreeController.reloadChildren]) and puts the entries it
/// returns into [DirectoryTreeController.tree] in place of the directory's
/// contents. A directory below it that the entries name without contents
/// keeps the contents it had, until it is listed itself (see
/// [DirectoryTreeController.reloadChildren]).
///
/// Return entries strictly inside `directory`, usually its direct children.
/// Deeper entries are accepted too (their missing parent directories are
/// created), so one call may load several levels. Entries that are not
/// strictly inside `directory`, including `directory` itself and paths the
/// tree's [PathPolicy] cannot parse, are ignored. Containment is compared by
/// [NodeId], so under [PathPolicy.caseInsensitive] a differently cased path
/// is still inside.
///
/// The controller applies the result of at most one call at a time per
/// directory and never calls the loader synchronously from the command that
/// triggered it. A call it discarded (a new [DirectoryTreeController.tree],
/// or the listing of a reloaded ancestor, arrived first) may still be
/// running when it calls the loader again for the same directory. The
/// discarded call's result is ignored, so the loader may cancel it; a loader
/// that keeps request state per directory must not let the earlier call
/// clear or answer the newer one.
/// A thrown error or a failed future marks the directory
/// [DirectoryLoadStatus.failed] and is reported through
/// [DirectoryLoadErrorCallback]; it never escapes to the caller.
typedef DirectoryChildrenLoader<T> = Future<Iterable<TreeEntry<T>>> Function(
  DirectoryNode<T> directory,
);

/// Reports that loading the children of [directory] failed with [error].
///
/// Pass one to [DirectoryTreeController.new] as `onLoadError` to log the
/// failure or show it to the user. It runs after the directory's status has
/// become [DirectoryLoadStatus.failed] and listeners have been notified. The
/// error is also kept for [DirectoryTreeController.loadErrorOf]. The futures
/// returned by [DirectoryTreeController.loadChildren] and
/// [DirectoryTreeController.reloadChildren] never complete with the error.
typedef DirectoryLoadErrorCallback = void Function(
  NodeId directory,
  Object error,
  StackTrace stackTrace,
);

/// The lazy-loading state of a directory, as reported by
/// [DirectoryTreeController.loadStatusOf].
///
/// A load moves a directory from [notLoaded] or [failed] to [loading] and
/// then to [loaded] or [failed], with a notification at each step.
enum DirectoryLoadStatus {
  /// The children are unknown: the directory has no children in the tree,
  /// the controller has a loader, and no load ran since the tree was set.
  notLoaded,

  /// A load of the children is in progress.
  loading,

  /// The children are known: they are in the tree, a load finished (even
  /// with no entries), or there is no loader to ask. Files are always
  /// loaded.
  loaded,

  /// The latest load failed; [DirectoryTreeController.loadErrorOf] holds
  /// the error. Expanding the directory or calling
  /// [DirectoryTreeController.loadChildren] tries again.
  failed,
}
