import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tree = DirectoryTree.fromPaths(['/r/a.txt', '/r/b.txt']);
  final rows = tree.flatten();
  final equalRows = tree.flatten();

  test('reset has no block', () {
    final change = TreeRowsChange.reset(previous: rows);
    expect(change.isReset, isTrue);
    expect(change.previous, same(rows));
    expect(change.index, 0);
    expect(change.removed, 0);
    expect(change.inserted, 0);
    expect(change.toString(), 'TreeRowsChange.reset()');
  });

  test('splice keeps its block', () {
    final change = TreeRowsChange.splice(
      previous: rows,
      index: 1,
      removed: 0,
      inserted: 2,
    );
    expect(change.isReset, isFalse);
    expect(change.index, 1);
    expect(change.removed, 0);
    expect(change.inserted, 2);
    expect(
      change.toString(),
      'TreeRowsChange.splice(index: 1, removed: 0, inserted: 2)',
    );
  });

  test('equality compares previous by identity and the rest by value', () {
    TreeRowsChange splice(TreeRows<Object?>? previous, int inserted) =>
        TreeRowsChange.splice(
          previous: previous,
          index: 1,
          removed: 0,
          inserted: inserted,
        );
    expect(splice(rows, 2), splice(rows, 2));
    expect(splice(rows, 2).hashCode, splice(rows, 2).hashCode);
    expect(rows, equalRows);
    expect(splice(rows, 2), isNot(splice(equalRows, 2)));
    expect(splice(rows, 2), isNot(splice(rows, 3)));
    expect(
      TreeRowsChange.reset(previous: rows),
      isNot(
        TreeRowsChange.splice(
          previous: rows,
          index: 0,
          removed: 0,
          inserted: 0,
        ),
      ),
    );
    expect(
      const TreeRowsChange.reset(previous: null),
      const TreeRowsChange.reset(previous: null),
    );
  });

  test('rejects negative numbers', () {
    var negative = -1;
    expect(
      () => TreeRowsChange.splice(
        previous: null,
        index: negative,
        removed: 0,
        inserted: 0,
      ),
      throwsAssertionError,
    );
    expect(
      () => TreeRowsChange.splice(
        previous: null,
        index: 0,
        removed: negative,
        inserted: 0,
      ),
      throwsAssertionError,
    );
    negative--;
    expect(
      () => TreeRowsChange.splice(
        previous: null,
        index: 0,
        removed: 0,
        inserted: negative,
      ),
      throwsAssertionError,
    );
  });
}
