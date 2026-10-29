// Which SliverDirectoryTree states show each controller. This library is not
// exported by the package.
import 'package:flutter/widgets.dart';
// Imported only so documentation references resolve.
import 'package:flutter_directory_tree/src/widgets/sliver_directory_tree.dart';

final Expando<List<State>> _slivers = Expando<List<State>>(
  'SliverDirectoryTree states',
);

/// Records that the mounted [SliverDirectoryTree] state [sliver] shows
/// [controller]. O(1).
void registerTreeSliver(Object controller, State sliver) {
  (_slivers[controller] ??= <State>[]).add(sliver);
}

/// Forgets what [registerTreeSliver] recorded for [controller] and
/// [sliver]. O(slivers of the controller).
void unregisterTreeSliver(Object controller, State sliver) {
  final slivers = _slivers[controller];
  if (slivers == null) return;
  slivers.remove(sliver);
  if (slivers.isEmpty) _slivers[controller] = null;
}

/// The mounted [SliverDirectoryTree] states that show [controller], in the
/// order they were created or got the controller; usually one per view.
List<State> treeSliversOf(Object controller) =>
    List<State>.unmodifiable(_slivers[controller] ?? const <State>[]);
