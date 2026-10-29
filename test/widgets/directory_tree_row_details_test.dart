import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controller = DirectoryTreeController<Object?>(
    tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/README.md']),
    expansion: const ExpansionState.expanded(),
  );
  tearDownAll(controller.dispose);

  DirectoryTreeRowDetails<Object?> details({
    TreeRow<Object?>? row,
    bool isSelected = false,
    List<({int start, int end})> matchRanges = const [],
  }) => DirectoryTreeRowDetails<Object?>(
    controller: controller,
    row: row ?? controller.rows.first,
    index: 0,
    isSelected: isSelected,
    isFocused: false,
    hasFocus: false,
    isHovered: false,
    checkboxMode: DirectoryTreeCheckboxMode.none,
    checkState: null,
    loadStatus: DirectoryLoadStatus.loaded,
    isExpandable: true,
    matchRanges: matchRanges,
  );

  test('equal details compare equal and hash alike', () {
    final a = details(matchRanges: [(start: 0, end: 2)]);
    final b = details(matchRanges: [(start: 0, end: 2)]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('any changed field makes details unequal', () {
    final base = details();
    expect(base.copyWith(isSelected: true), isNot(base));
    expect(base.copyWith(isHovered: true), isNot(base));
    expect(base.copyWith(index: 1), isNot(base));
    expect(base.copyWith(matchRanges: [(start: 0, end: 1)]), isNot(base));
    expect(base.copyWith(row: controller.rows[1]), isNot(base));
  });

  test('rows compare by identity', () {
    final rows = controller.tree.flatten();
    // An equal row from another flatten is a different object.
    expect(rows.first, controller.rows.first);
    expect(details(row: rows.first), isNot(details()));
  });

  test('copyWith keeps unspecified fields', () {
    final base = details(isSelected: true);
    final hovered = base.copyWith(isHovered: true);
    expect(hovered.isSelected, isTrue);
    expect(hovered.controller, same(controller));
    expect(hovered.toString(), contains('hovered'));
  });
}
