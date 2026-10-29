import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'menu_test_utils.dart';

void main() {
  late DirectoryTreeController<int> controller;

  setUp(() => controller = expandedController());
  tearDown(() => controller.dispose());

  DirectoryTreeMenuDetails<int> detailsFor(
    NodeId id, {
    DirectoryTreeController<int>? owner,
    TreeRow<int>? row,
    List<TreeNode<int>>? nodes,
    Offset globalPosition = const Offset(40, 75),
  }) {
    final resolved = row ?? controller.rows.rowOf(id)!;
    return DirectoryTreeMenuDetails<int>(
      controller: owner ?? controller,
      row: resolved,
      nodes: nodes ?? [resolved.node],
      globalPosition: globalPosition,
    );
  }

  test('details with the same controller and equal values are equal', () {
    final a = detailsFor(lib);
    final b = detailsFor(lib);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('a row of another flatten of the same state counts as equal', () {
    final sameRow = controller.tree
        .flatten(expansion: const ExpansionState.expanded())
        .rowOf(lib)!;
    expect(identical(sameRow, controller.rows.rowOf(lib)), isFalse);

    final a = detailsFor(lib);
    final b = detailsFor(lib, row: sameRow);

    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('every field takes part in equality', () {
    final base = detailsFor(lib);
    final other = expandedController();
    addTearDown(other.dispose);

    expect(base == detailsFor(lib, owner: other), isFalse);
    expect(base == detailsFor(src), isFalse);
    expect(
      base ==
          detailsFor(lib, nodes: controller.rows.map((r) => r.node).toList()),
      isFalse,
    );
    expect(
      base == detailsFor(lib, globalPosition: const Offset(40, 76)),
      isFalse,
    );
    expect(base == Object(), isFalse);
  });

  test('toString names the row, the number of nodes, and the position', () {
    final details = detailsFor(
      lib,
      nodes: [
        controller.rows.rowOf(lib)!.node,
        controller.rows.rowOf(readme)!.node,
      ],
    );

    expect(
      details.toString(),
      'DirectoryTreeMenuDetails(lib, nodes: 2, '
      'globalPosition: Offset(40.0, 75.0))',
    );
  });
}
