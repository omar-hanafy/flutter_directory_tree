import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_utils.dart';

const Duration _duration = Duration(milliseconds: 200);

final DirectoryTreeThemeData _animated = testTheme.copyWith(
  animationDuration: _duration,
);

/// The opacity of the insert transition of the row of [id], or null when
/// the row has none.
double? _insertOpacity(WidgetTester tester, NodeId id) {
  final fades = find.descendant(
    of: rowOf(id),
    matching: find.byType(FadeTransition),
  );
  if (fades.evaluate().isEmpty) return null;
  return tester.widget<FadeTransition>(fades.first).opacity.value;
}

Offset _insertOffset(WidgetTester tester, NodeId id) => tester
    .widget<SlideTransition>(
      find.descendant(of: rowOf(id), matching: find.byType(SlideTransition)),
    )
    .position
    .value;

void main() {
  testWidgets('rows inserted by an expansion fade and slide in', (
    tester,
  ) async {
    final controller = expandedController()..collapse(src);
    addTearDown(controller.dispose);
    await tester.pumpWidget(treeApp(controller: controller, theme: _animated));
    for (final row in controller.rows) {
      expect(_insertOpacity(tester, row.id), isNull);
    }

    controller.expand(src);
    await tester.pump();
    expect(_insertOpacity(tester, aDart), 0);
    expect(_insertOpacity(tester, bDart), 0);
    expect(_insertOffset(tester, aDart).dy, lessThan(0));
    // The expanded row and the rows that moved down do not animate.
    expect(_insertOpacity(tester, src), isNull);
    expect(_insertOpacity(tester, mainDart), isNull);
    expect(_insertOpacity(tester, readme), isNull);

    await tester.pump(_duration ~/ 2);
    final opacity = _insertOpacity(tester, aDart)!;
    expect(opacity, greaterThan(0));
    expect(opacity, lessThan(1));

    await tester.pumpAndSettle();
    expect(_insertOpacity(tester, aDart), 1);
    expect(_insertOffset(tester, aDart), Offset.zero);
    // The animation never changes the row's slot.
    expect(rowTop(tester, aDart), 3 * rowExtent);
  });

  testWidgets('rows a lazy load inserted fade in', (tester) async {
    final loader = PendingLoader<int>();
    final controller = DirectoryTreeController<int>(
      tree: DirectoryTree<int>.build(const [TreeEntry<int>.directory('/lazy')]),
      loadChildren: loader.call,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(treeApp(controller: controller, theme: _animated));
    controller.expand(const NodeId('/lazy'));
    await tester.pump();
    await tester.pump();
    loader.complete(const NodeId('/lazy'), const [
      TreeEntry<int>.file('/lazy/x.txt'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(controller.lastRowsChange.isReset, isFalse);
    expect(_insertOpacity(tester, const NodeId('/lazy/x.txt')), 0);
    await tester.pumpAndSettle();
    expect(_insertOpacity(tester, const NodeId('/lazy/x.txt')), 1);
  });

  testWidgets('rows do not animate after a reset', (tester) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(treeApp(controller: controller, theme: _animated));
    controller.collapseAll();
    await tester.pump();
    controller.expandAll();
    expect(controller.lastRowsChange.isReset, isTrue);
    await tester.pump();
    for (final row in controller.rows) {
      expect(_insertOpacity(tester, row.id), isNull, reason: row.label);
    }
    controller.tree = DirectoryTree<int>.build(const [
      TreeEntry<int>.file('/repo/new.txt'),
      TreeEntry<int>.file('/repo/README.md'),
    ]);
    await tester.pump();
    expect(_insertOpacity(tester, const NodeId('/repo/new.txt')), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('rows scrolled into view do not animate, even inserted ones', (
    tester,
  ) async {
    final controller = DirectoryTreeController<int>(tree: wideTree(100));
    addTearDown(controller.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      treeApp(
        controller: controller,
        theme: _animated,
        scrollController: scroll,
      ),
    );
    controller.expand(wideDir);
    await tester.pump();
    // The rows on screen right after the expansion animate.
    expect(_insertOpacity(tester, wideId(0)), 0);
    await tester.pumpAndSettle();

    // Inserted rows that only come into view later appear as they are.
    scroll.jumpTo(60 * rowExtent);
    await tester.pump();
    expect(rowOf(wideId(60)), findsOneWidget);
    expect(_insertOpacity(tester, wideId(60)), isNull);
    expect(_insertOpacity(tester, wideId(65)), isNull);
  });

  testWidgets('no row animation with disabled animations or a zero duration', (
    tester,
  ) async {
    final controller = expandedController()..collapse(src);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      treeApp(
        controller: controller,
        theme: _animated,
        disableAnimations: true,
      ),
    );
    controller.expand(src);
    await tester.pump();
    expect(_insertOpacity(tester, aDart), isNull);

    controller.collapse(src);
    await tester.pumpWidget(treeApp(controller: controller));
    controller.expand(src);
    await tester.pump();
    expect(_insertOpacity(tester, aDart), isNull);
  });

  testWidgets('the chevron turns toward the bottom while expanded', (
    tester,
  ) async {
    final controller = expandedController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(treeApp(controller: controller, theme: _animated));
    AnimatedRotation rotationOf(NodeId id) => tester.widget<AnimatedRotation>(
      find.descendant(of: rowOf(id), matching: find.byType(AnimatedRotation)),
    );
    expect(rotationOf(lib).turns, 0.25);
    expect(rotationOf(lib).duration, _duration);

    controller.collapse(lib);
    await tester.pump();
    expect(rotationOf(lib).turns, 0);
    final turning = tester.widget<RotationTransition>(
      find.descendant(
        of: rowOf(lib),
        matching: find.byType(RotationTransition),
      ),
    );
    await tester.pump(_duration ~/ 2);
    expect(turning.turns.value, greaterThan(0));
    expect(turning.turns.value, lessThan(0.25));
    await tester.pumpAndSettle();
    expect(turning.turns.value, 0);

    await tester.pumpWidget(
      treeApp(
        controller: controller,
        theme: _animated,
        disableAnimations: true,
      ),
    );
    expect(rotationOf(lib).duration, Duration.zero);
  });
}
