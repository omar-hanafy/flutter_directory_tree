import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/dnd/directory_tree_drag_and_drop.dart';
import 'package:flutter_directory_tree/src/dnd/directory_tree_drop_details.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final tree = DirectoryTree.fromPaths(const [
    '/r/',
    '/r/a/a1.txt',
    '/r/a/a2.txt',
    '/r/a/a3.txt',
    '/r/a/a4.txt',
    '/r/b/',
  ]);
  TreeNode<Object?> node(String path) => tree.nodeAt(path)!;
  final b = node('/r/b') as DirectoryNode<Object?>;
  final a = node('/r/a') as DirectoryNode<Object?>;

  group('DirectoryTreeDropDetails', () {
    test('compares nodes in order and the target by value', () {
      final one = DirectoryTreeDropDetails<Object?>(
        nodes: [node('/r/a/a1.txt'), node('/r/a/a2.txt')],
        target: b,
      );
      final same = DirectoryTreeDropDetails<Object?>(
        nodes: [node('/r/a/a1.txt'), node('/r/a/a2.txt')],
        target: b,
      );
      expect(one, same);
      expect(one.hashCode, same.hashCode);

      expect(
        one,
        isNot(
          DirectoryTreeDropDetails<Object?>(
            nodes: [node('/r/a/a2.txt'), node('/r/a/a1.txt')],
            target: b,
          ),
        ),
      );
      expect(
        one,
        isNot(DirectoryTreeDropDetails<Object?>(nodes: one.nodes, target: a)),
      );
    });

    test('nodes of a rebuilt tree compare by value', () {
      final rebuilt = tree.rebuild((builder) {});
      final details = DirectoryTreeDropDetails<Object?>(
        nodes: [node('/r/a/a1.txt')],
        target: b,
      );
      expect(
        DirectoryTreeDropDetails<Object?>(
          nodes: [rebuilt.nodeAt('/r/a/a1.txt')!],
          target: rebuilt.nodeAt('/r/b')! as DirectoryNode<Object?>,
        ),
        details,
      );
    });

    test('toString shows the target and at most three paths', () {
      expect(
        DirectoryTreeDropDetails<Object?>(
          nodes: [node('/r/a/a1.txt')],
          target: b,
        ).toString(),
        'DirectoryTreeDropDetails(1 node: /r/a/a1.txt -> /r/b)',
      );
      expect(
        DirectoryTreeDropDetails<Object?>(
          nodes: [
            for (final name in ['a1', 'a2', 'a3', 'a4']) node('/r/a/$name.txt'),
          ],
          target: b,
        ).toString(),
        'DirectoryTreeDropDetails(4 nodes: /r/a/a1.txt, /r/a/a2.txt, '
        '/r/a/a3.txt, ... -> /r/b)',
      );
    });
  });

  group('DirectoryTreeDragAndDrop', () {
    void onDrop(DirectoryTreeDropDetails<Object?> details) {}
    bool canDrag(List<TreeNode<Object?>> nodes) => true;
    bool canDrop(DirectoryTreeDropDetails<Object?> details) => true;
    Widget feedback(BuildContext context, List<TreeNode<Object?>> nodes) =>
        const SizedBox();

    test('defaults to a 700 ms auto-expand delay', () {
      const DirectoryTreeDragAndDrop<Object?> config =
          DirectoryTreeDragAndDrop<Object?>(onDrop: _ignore);
      expect(config.autoExpandDelay, const Duration(milliseconds: 700));
    });

    test('compares callbacks and the delay', () {
      final config = DirectoryTreeDragAndDrop<Object?>(
        onDrop: onDrop,
        canDrag: canDrag,
        canDrop: canDrop,
        feedbackBuilder: feedback,
      );
      final same = DirectoryTreeDragAndDrop<Object?>(
        onDrop: onDrop,
        canDrag: canDrag,
        canDrop: canDrop,
        feedbackBuilder: feedback,
      );
      expect(config, same);
      expect(config.hashCode, same.hashCode);

      expect(config, isNot(DirectoryTreeDragAndDrop<Object?>(onDrop: onDrop)));
      expect(
        config,
        isNot(
          DirectoryTreeDragAndDrop<Object?>(
            onDrop: (details) {},
            canDrag: canDrag,
            canDrop: canDrop,
            feedbackBuilder: feedback,
          ),
        ),
      );
      expect(
        DirectoryTreeDragAndDrop<Object?>(onDrop: onDrop),
        isNot(
          DirectoryTreeDragAndDrop<Object?>(
            onDrop: onDrop,
            autoExpandDelay: null,
          ),
        ),
      );
    });

    test('equality never fails a type check across type arguments', () {
      final typed = DirectoryTreeDragAndDrop<String>(
        onDrop: (details) {},
        canDrop: (details) => details.target.data!.isEmpty,
      );
      final DirectoryTreeDragAndDrop<Object?> widened = typed;
      final loose = DirectoryTreeDragAndDrop<Object?>(onDrop: onDrop);

      expect(widened == loose, isFalse);
      expect(loose == widened, isFalse);
      expect(widened, typed);
      expect(widened.autoExpandDelay, const Duration(milliseconds: 700));
    });

    test('toString names the delay and the optional callbacks', () {
      expect(
        DirectoryTreeDragAndDrop<Object?>(onDrop: onDrop).toString(),
        'DirectoryTreeDragAndDrop(autoExpandDelay: 0:00:00.700000)',
      );
      expect(
        DirectoryTreeDragAndDrop<Object?>(
          onDrop: onDrop,
          canDrag: canDrag,
          canDrop: canDrop,
          autoExpandDelay: null,
          feedbackBuilder: feedback,
        ).toString(),
        'DirectoryTreeDragAndDrop(autoExpandDelay: null, canDrag, canDrop, '
        'feedbackBuilder)',
      );
    });
  });

  test('DirectoryTreeDragAndDropScope describes its properties', () {
    final controller = DirectoryTreeController<Object?>(tree: tree);
    addTearDown(controller.dispose);
    final builder = DiagnosticPropertiesBuilder();
    DirectoryTreeDragAndDropScope<Object?>(
      controller: controller,
      dragAndDrop: const DirectoryTreeDragAndDrop<Object?>(onDrop: _ignore),
      onLongPressWithoutDrag: (row, position) {},
      child: const SizedBox(),
    ).debugFillProperties(builder);

    final names = [for (final property in builder.properties) property.name];
    expect(names, containsAll(['controller', 'dragAndDrop']));
    final flag = builder.properties.singleWhere(
      (property) => property.name == 'onLongPressWithoutDrag',
    );
    expect(flag.toDescription(), 'has onLongPressWithoutDrag');
  });
}

void _ignore(DirectoryTreeDropDetails<Object?> details) {}
