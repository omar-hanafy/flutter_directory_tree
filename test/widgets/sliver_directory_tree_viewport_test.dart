import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test_utils.dart';

/// The sliver's viewport, as the controller sees it.
DirectoryTreeViewport viewportOf(WidgetTester tester) =>
    tester.state(find.byType(SliverDirectoryTree<int>))
        as DirectoryTreeViewport;

/// A 100-pixel box before the tree.
const Widget header = SliverToBoxAdapter(
  child: SizedBox(key: ValueKey<String>('header'), height: 100),
);

void main() {
  // wideController(100): row 0 is `w`, row i + 1 is file i; 101 rows of
  // 30 px, 3030 px in all, in a 300 px viewport (max scroll 2730).
  group('pageRowCount', () {
    testWidgets('is the number of rows that fit, at least 1', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      expect(viewportOf(tester).pageRowCount, 10);

      await tester.pumpWidget(treeApp(controller: controller, height: 95));
      expect(viewportOf(tester).pageRowCount, 3);

      await tester.pumpWidget(treeApp(controller: controller, height: 10));
      expect(viewportOf(tester).pageRowCount, 1);
    });

    testWidgets('pages the controller focus', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller, height: 150));
      controller.moveFocus(TreeFocusMove.first);
      controller.moveFocus(TreeFocusMove.pageDown);
      expect(controller.focusedIndex, 5);
      await tester.pump();
      // The paged-to row was scrolled into view in that frame.
      expect(rowOf(wideId(4)), findsOneWidget);
    });
  });

  group('showRow', () {
    testWidgets('scrolls minimally when alignment is null', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      final viewport = viewportOf(tester);
      final position = scrollPositionOf(tester);

      await viewport.showRow(50);
      // The row's bottom (51 * 30) meets the viewport's bottom.
      expect(position.pixels, 51 * rowExtent - viewportHeight);
      await tester.pump();
      expect(tester.getBottomLeft(rowOf(wideId(49))).dy, viewportHeight);

      // Already fully visible: nothing moves.
      await viewport.showRow(45);
      expect(position.pixels, 51 * rowExtent - viewportHeight);

      // Above the viewport: the row's top meets the viewport's top.
      await viewport.showRow(10);
      expect(position.pixels, 10 * rowExtent);
      await tester.pump();
      expect(rowTop(tester, wideId(9)), 0);
    });

    testWidgets('aligns rows at 0, 0.5, and 1, clamped to the scroll range', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      final viewport = viewportOf(tester);
      final position = scrollPositionOf(tester);

      await viewport.showRow(50, alignment: 0);
      expect(position.pixels, 50 * rowExtent);
      await viewport.showRow(50, alignment: 1);
      expect(position.pixels, 51 * rowExtent - viewportHeight);
      await viewport.showRow(50, alignment: 0.5);
      expect(
        position.pixels,
        50 * rowExtent - (viewportHeight - rowExtent) / 2,
      );
      await tester.pump();
      expect(tester.getCenter(rowOf(wideId(49))).dy, viewportHeight / 2);

      // The last row cannot reach the top, the first one not the bottom.
      await viewport.showRow(100, alignment: 0);
      expect(position.pixels, position.maxScrollExtent);
      expect(position.pixels, 101 * rowExtent - viewportHeight);
      await viewport.showRow(0, alignment: 1);
      expect(position.pixels, 0);

      // Out-of-range indexes do nothing.
      await viewport.showRow(500);
      await viewport.showRow(-1);
      expect(position.pixels, 0);
    });

    testWidgets('accounts for slivers before the tree and SliverPadding', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          before: const [header],
          padding: const EdgeInsets.only(top: 20, bottom: 10),
        ),
      );
      final viewport = viewportOf(tester);
      final position = scrollPositionOf(tester);
      // Row i starts at 100 (header) + 20 (padding) + 30 i.
      const start = 120.0;
      expect(rowTop(tester, wideDir), start);
      expect(position.maxScrollExtent, start + 3030 + 10 - viewportHeight);

      await viewport.showRow(50, alignment: 0);
      expect(position.pixels, start + 50 * rowExtent);
      await tester.pump();
      expect(rowTop(tester, wideId(49)), 0);

      await viewport.showRow(60);
      expect(position.pixels, start + 61 * rowExtent - viewportHeight);
      await tester.pump();
      expect(tester.getBottomLeft(rowOf(wideId(59))).dy, viewportHeight);

      await viewport.showRow(2);
      expect(position.pixels, start + 2 * rowExtent);
      await viewport.showRow(0, alignment: 0.5);
      expect(position.pixels, 0);
      await viewport.showRow(100, alignment: 0);
      expect(position.pixels, position.maxScrollExtent);
    });

    testWidgets('animates when given a duration', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      final position = scrollPositionOf(tester);
      var done = false;
      unawaited(
        viewportOf(tester)
            .showRow(
              50,
              alignment: 0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.linear,
            )
            .then((_) => done = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(position.pixels, closeTo(25 * rowExtent, 1));
      expect(done, isFalse);
      await tester.pumpAndSettle();
      expect(position.pixels, 50 * rowExtent);
      expect(done, isTrue);
    });

    testWidgets('scrolls to rows that the same command created, in the same '
        'frame', (tester) async {
      final controller = DirectoryTreeController<int>(tree: wideTree(100));
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      expect(controller.rows, hasLength(1));

      // Expands `w` (a reset) and scrolls to file 80 before any layout of
      // the new rows: positions come from the index, not built rows.
      expect(controller.reveal(wideId(80)), isTrue);
      await tester.pump();
      final position = scrollPositionOf(tester);
      expect(position.pixels, 82 * rowExtent - viewportHeight);
      expect(tester.getBottomLeft(rowOf(wideId(80))).dy, viewportHeight);
      await tester.pumpAndSettle();
      expect(position.pixels, 82 * rowExtent - viewportHeight);

      // An aligned reveal of the last row clamps to the new extent.
      controller.collapse(wideDir);
      await tester.pump();
      controller.reveal(wideId(99), alignment: 0);
      await tester.pump();
      expect(position.pixels, 101 * rowExtent - viewportHeight);
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
    });

    testWidgets('keyboard moves keep the focused row visible', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(treeApp(controller: controller));
      controller.moveFocus(TreeFocusMove.last);
      await tester.pump();
      expect(rowOf(wideId(99)), findsOneWidget);
      expect(tester.getBottomLeft(rowOf(wideId(99))).dy, viewportHeight);
      controller.moveFocus(TreeFocusMove.first);
      await tester.pump();
      expect(rowTop(tester, wideDir), 0);
    });

    testWidgets('waits for the first layout before scrolling', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      // Finders cannot walk a viewport before its first layout, so the
      // sliver is found by key.
      final key = GlobalKey();
      await tester.pumpWidget(
        treeApp(controller: controller, sliverKey: key),
        phase: EnginePhase.build,
      );
      final viewport = key.currentState! as DirectoryTreeViewport;
      final future = viewport.showRow(50, alignment: 0);
      await tester.pump();
      await future;
      expect(scrollPositionOf(tester).pixels, 50 * rowExtent);
    });
  });

  group('globalRowRect', () {
    testWidgets('is the bounds of a laid-out row, else null', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, before: const [header]),
      );
      final viewport = viewportOf(tester);
      expect(viewport.globalRowRect(1), tester.getRect(rowOf(wideId(0))));
      expect(
        viewport.globalRowRect(1),
        const Rect.fromLTWH(0, 100 + rowExtent, viewportWidth, rowExtent),
      );
      expect(viewport.globalRowRect(90), isNull);
      expect(viewport.globalRowRect(101), isNull);
      expect(viewport.globalRowRect(-1), isNull);
    });
  });

  group('attachment', () {
    testWidgets('attaches while mounted and moves with the controller', (
      tester,
    ) async {
      final first = wideController(100);
      final second = wideController(100);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final counter = BuildCounter<int>();
      // A 150 px viewport pages by 5 rows; a controller without a viewport
      // pages by 10.
      await tester.pumpWidget(
        treeApp(controller: first, height: 150, rowBuilder: counter.build),
      );
      first.moveFocus(TreeFocusMove.first);
      first.moveFocus(TreeFocusMove.pageDown);
      expect(first.focusedIndex, 5);

      await tester.pumpWidget(
        treeApp(controller: second, height: 150, rowBuilder: counter.build),
      );
      first.moveFocus(TreeFocusMove.pageDown);
      expect(first.focusedIndex, 15);
      second.moveFocus(TreeFocusMove.first);
      second.moveFocus(TreeFocusMove.pageDown);
      expect(second.focusedIndex, 5);
      await tester.pump();
      counter.take();
      // The old controller no longer drives the sliver.
      first.select(wideId(3));
      await tester.pump();
      expect(counter.take(), isEmpty);
      second.select(wideId(3));
      await tester.pump();
      expect(counter.take(), isNotEmpty);

      await tester.pumpWidget(const SizedBox());
      final before = second.focusedIndex;
      second.moveFocus(TreeFocusMove.pageDown);
      expect(second.focusedIndex, before + 10);
      // Commands after the sliver is gone neither scroll nor throw.
      second.reveal(wideId(90));
      await second.ensureVisible(wideId(90));
    });
  });

  group('scroll anchoring', () {
    testWidgets('keeps the first visible row in place when rows are inserted '
        'above it, in the same frame', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      // File 39 (row 40) is the first visible row, 10 px cut off.
      scroll.jumpTo(40 * rowExtent + 10);
      await tester.pump();
      final anchor = wideId(39);
      expect(rowTop(tester, anchor), -10);

      // A refresh adds five files that sort before all the others.
      controller.tree = wideTree(
        100,
        extra: ['a0.txt', 'a1.txt', 'a2.txt', 'a3.txt', 'a4.txt'],
      );
      expect(controller.lastRowsChange.isReset, isTrue);
      await tester.pump();
      expect(rowTop(tester, anchor), -10);
      expect(scroll.offset, 45 * rowExtent + 10);
      expect(rowTop(tester, wideId(40)), 20);
    });

    testWidgets('keeps rows in place when an expansion or a collapse above '
        'them splices rows', (tester) async {
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build([
          for (var i = 0; i < 20; i++)
            TreeEntry<int>.file('/p/a/x${i.toString().padLeft(2, '0')}.txt'),
          for (var i = 0; i < 100; i++)
            TreeEntry<int>.file('/p/z/${wideName(i)}'),
        ]),
        expansion: ExpansionState.withExpanded(const [
          NodeId('/p'),
          NodeId('/p/z'),
        ]),
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      // With minimal roots a and z are the top-level rows, then the files
      // of z: file 30 of z is row 32.
      scroll.jumpTo(32 * rowExtent);
      await tester.pump();
      const anchor = NodeId('/p/z/f0030.txt');
      expect(rowTop(tester, anchor), 0);

      controller.expand(const NodeId('/p/a'));
      expect(controller.lastRowsChange.isReset, isFalse);
      await tester.pump();
      expect(rowTop(tester, anchor), 0);
      expect(scroll.offset, 52 * rowExtent);

      controller.collapse(const NodeId('/p/a'));
      await tester.pump();
      expect(rowTop(tester, anchor), 0);
      expect(scroll.offset, 32 * rowExtent);
    });

    testWidgets('keeps rows in place when a lazy load above them finishes', (
      tester,
    ) async {
      final loader = PendingLoader<int>();
      final controller = DirectoryTreeController<int>(
        tree: DirectoryTree<int>.build([
          const TreeEntry<int>.directory('/p/a'),
          for (var i = 0; i < 100; i++)
            TreeEntry<int>.file('/p/z/${wideName(i)}'),
        ]),
        expansion: const ExpansionState.expanded(),
        loadChildren: loader.call,
      );
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      unawaited(controller.loadChildren(const NodeId('/p/a')));
      await tester.pump();
      expect(loader.calls, [const NodeId('/p/a')]);
      // Rows: a, z, then the files of z; file 30 of z is row 32.
      scroll.jumpTo(32 * rowExtent);
      await tester.pump();
      const anchor = NodeId('/p/z/f0030.txt');
      expect(rowTop(tester, anchor), 0);

      loader.complete(const NodeId('/p/a'), [
        for (var i = 0; i < 7; i++) TreeEntry<int>.file('/p/a/x$i.txt'),
      ]);
      // The first pump lets the load finish, the second draws its frame.
      await tester.pump();
      await tester.pump();
      expect(
        controller.loadStatusOf(const NodeId('/p/a')),
        DirectoryLoadStatus.loaded,
      );
      expect(controller.lastRowsChange.isReset, isFalse);
      expect(rowTop(tester, anchor), 0);
      expect(scroll.offset, 39 * rowExtent);
    });

    testWidgets('anchors the next visible row when the first one is gone', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(40 * rowExtent);
      await tester.pump();
      expect(rowTop(tester, wideId(39)), 0);
      expect(rowTop(tester, wideId(40)), rowExtent);

      // Files 39 and 38 disappear and three files appear above.
      controller.tree = DirectoryTree<int>.build([
        for (final name in ['a0.txt', 'a1.txt', 'a2.txt'])
          TreeEntry<int>.file('/w/$name'),
        for (var i = 0; i < 100; i++)
          if (i != 38 && i != 39) TreeEntry<int>.file('/w/${wideName(i)}'),
      ]);
      await tester.pump();
      expect(rowTop(tester, wideId(40)), rowExtent);
    });

    testWidgets('only clamps the offset when no visible row survives', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();

      controller.tree = wideTree(20);
      await tester.pump();
      expect(scroll.offset, 21 * rowExtent - viewportHeight);
      expect(tester.getBottomLeft(rowOf(wideId(19))).dy, viewportHeight);
      await tester.pumpAndSettle();
      expect(scroll.offset, 21 * rowExtent - viewportHeight);

      // A collapse that removes every visible row clamps too.
      controller.collapseAll();
      await tester.pump();
      expect(scroll.offset, 0);
      expect(rowTop(tester, wideDir), 0);
    });

    testWidgets('keeps the anchor inside the new scroll range', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(80 * rowExtent);
      await tester.pump();
      // The first visible row (file 79) survives at row 86, but only 92
      // rows remain: keeping it at the top would scroll past the end.
      controller.tree = DirectoryTree<int>.build([
        for (var i = 0; i < 6; i++) TreeEntry<int>.file('/w/a$i.txt'),
        for (var i = 0; i < 85; i++) TreeEntry<int>.file('/w/${wideName(i)}'),
      ]);
      await tester.pump();
      final position = scrollPositionOf(tester);
      expect(position.maxScrollExtent, 92 * rowExtent - viewportHeight);
      expect(position.pixels, position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(position.pixels, position.maxScrollExtent);
    });

    testWidgets('after an instant reveal, the revealed row is the anchor until '
        'the next frame', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(40 * rowExtent);
      await tester.pump();

      // The reveal jumps before any layout; a refresh in the same frame
      // then inserts 30 rows above both the old view and the revealed row.
      controller.reveal(wideId(5), alignment: 0);
      expect(scroll.offset, 6 * rowExtent);
      controller.tree = wideTree(
        100,
        extra: [
          for (var i = 0; i < 30; i++) 'a${i.toString().padLeft(2, '0')}',
        ],
      );
      await tester.pump();
      expect(rowTop(tester, wideId(5)), 0);
      expect(scroll.offset, 36 * rowExtent);
    });

    testWidgets('several changes before one frame add up', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(50 * rowExtent);
      await tester.pump();
      final anchor = wideId(49);

      controller
        ..tree = wideTree(100, extra: ['a0.txt', 'a1.txt'])
        ..tree = wideTree(100, extra: ['a0.txt', 'a1.txt', 'a2.txt', 'a3.txt'])
        ..tree = wideTree(100, extra: ['a0.txt']);
      await tester.pump();
      expect(rowTop(tester, anchor), 0);
      expect(scroll.offset, 51 * rowExtent);
    });

    testWidgets('works with slivers before the tree and SliverPadding', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          before: const [header],
          padding: const EdgeInsets.only(top: 20),
        ),
      );
      scroll.jumpTo(120 + 40 * rowExtent + 5);
      await tester.pump();
      final anchor = wideId(39);
      expect(rowTop(tester, anchor), -5);

      controller.tree = wideTree(100, extra: ['a0.txt', 'a1.txt']);
      await tester.pump();
      expect(rowTop(tester, anchor), -5);

      // With the start of the tree on screen, rows simply flow.
      scroll.jumpTo(50);
      await tester.pump();
      final top = rowTop(tester, wideDir);
      controller.tree = wideTree(100, extra: ['a2.txt']);
      await tester.pump();
      expect(rowTop(tester, wideDir), top);
      expect(scroll.offset, 50);
    });

    testWidgets('a tree scrolled past keeps the content after it in place', (
      tester,
    ) async {
      final controller = wideController(20);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      const footer = ValueKey<String>('footer');
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          after: const [
            SliverToBoxAdapter(child: SizedBox(key: footer, height: 1000)),
          ],
        ),
      );
      scroll.jumpTo(21 * rowExtent + 200);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(footer)).dy, -200);

      controller.tree = wideTree(20, extra: ['a0.txt', 'a1.txt', 'a2.txt']);
      await tester.pump();
      expect(tester.getTopLeft(find.byKey(footer)).dy, -200);
    });
  });

  group('scroll anchoring during scroll activities', () {
    // Twenty files that sort before every file of wideTree.
    final early = [
      for (var i = 0; i < 20; i++) 'a${i.toString().padLeft(2, '0')}.txt',
    ];

    // The first fully visible row of [controller] and its top on screen.
    ({NodeId id, double top}) firstRow(
      WidgetTester tester,
      DirectoryTreeController<int> controller,
      double offset,
    ) {
      final id = controller.rows[(offset / rowExtent).ceil()].id;
      return (id: id, top: shownTop(tester, id));
    }

    // Flings up, lets six frames of momentum pass, optionally refreshes the
    // tree with 20 rows above everything, and returns the settled offset.
    Future<double> flingAndSettle(
      WidgetTester tester,
      DirectoryTreeController<int> controller,
      ScrollController scroll, {
      required bool reset,
    }) async {
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -200),
        2000,
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.position.activity, isA<BallisticScrollActivity>());
      final before = firstRow(tester, controller, scroll.offset);
      if (reset) controller.tree = wideTree(1000, extra: early);
      await tester.pump(const Duration(milliseconds: 16));
      // The row moved by one frame of momentum, not by the inserted rows.
      expect(
        (shownTop(tester, before.id) - before.top).abs(),
        lessThan(5 * rowExtent),
      );
      await tester.pumpAndSettle();
      return scroll.offset;
    }

    testWidgets('a reset during a fling keeps the anchor and the momentum', (
      tester,
    ) async {
      final control = wideController(1000);
      addTearDown(control.dispose);
      final controlScroll = ScrollController();
      addTearDown(controlScroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: control, scrollController: controlScroll),
      );
      final expected = await flingAndSettle(
        tester,
        control,
        controlScroll,
        reset: false,
      );
      expect(expected, greaterThan(20 * rowExtent));

      final controller = wideController(1000);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      final offset = await flingAndSettle(
        tester,
        controller,
        scroll,
        reset: true,
      );
      // The fling ends where it would have, moved by the inserted rows.
      expect(offset, closeTo(expected + 20 * rowExtent, rowExtent));
    });

    testWidgets('a reset during an animated reveal keeps the anchor, and the '
        'revealed row still ends where it was asked to be', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      var done = false;
      unawaited(
        controller
            .ensureVisible(
              wideId(70),
              alignment: 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.linear,
            )
            .then((_) => done = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = firstRow(tester, controller, scroll.offset);
      // Twenty rows above the view and five between it and the target.
      controller.tree = wideTree(
        100,
        extra: [...early, for (var i = 0; i < 5; i++) 'f0060_$i.txt'],
      );
      await tester.pump();
      expect(
        (shownTop(tester, before.id) - before.top).abs(),
        lessThan(5 * rowExtent),
      );
      expect(done, isFalse);
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(shownTop(tester, wideId(70)), 0);
    });

    testWidgets('an app animation keeps its absolute target, and scroll '
        'listeners see the real offsets', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final seen = <double>[];
      scroll.addListener(() => seen.add(scroll.offset));
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      unawaited(
        scroll.animateTo(
          40 * rowExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.tree = wideTree(100, extra: early);
      await tester.pumpAndSettle();
      // animateTo(x) ends at x, whatever changed meanwhile.
      expect(scroll.offset, 40 * rowExtent);
      expect(seen.last, scroll.offset);

      // So animateTo(0) still reaches the top.
      unawaited(
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.tree = wideTree(100, extra: [...early, 'a99.txt']);
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(seen.last, 0);
    });

    testWidgets('scroll listeners see the real offsets of a corrected fling '
        'and of a re-aimed reveal', (tester) async {
      final controller = wideController(1000);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final seen = <double>[];
      scroll.addListener(() => seen.add(scroll.offset));
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -200),
        2000,
      );
      await tester.pump(const Duration(milliseconds: 50));
      controller.tree = wideTree(1000, extra: early);
      // The correction itself is silent, as layout corrections are; the
      // restarted fling reports the corrected offsets from its first move.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(seen.last, scroll.offset);
      final afterCorrection = seen.length;
      await tester.pumpAndSettle();
      expect(seen.last, scroll.offset);
      // No value after the correction is off by it: offsets only grow.
      final later = seen.sublist(afterCorrection - 1);
      for (var i = 1; i < later.length; i++) {
        expect(later[i], greaterThanOrEqualTo(later[i - 1]));
      }

      unawaited(
        controller.ensureVisible(
          wideId(600),
          alignment: 0,
          duration: const Duration(milliseconds: 300),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.tree = wideTree(1000, extra: [...early, 'a99.txt']);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      expect(seen.last, scroll.offset);
      await tester.pumpAndSettle();
      expect(seen.last, scroll.offset);
      expect(shownTop(tester, wideId(600)), 0);
    });

    testWidgets('an animated reveal whose row comes into view stops there', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      double? doneAt;
      unawaited(
        controller
            .ensureVisible(
              wideId(60),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.linear,
            )
            .then((_) => doneAt = scroll.offset),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Files 30 to 59 go away: file 60 is now on screen.
      controller.tree = DirectoryTree<int>.build([
        for (var i = 0; i < 100; i++)
          if (i < 30 || i >= 60) TreeEntry<int>.file('/w/${wideName(i)}'),
      ]);
      await tester.pumpAndSettle();
      expect(doneAt, isNotNull);
      expect(scroll.offset, doneAt);
      final top = shownTop(tester, wideId(60));
      expect(top, greaterThanOrEqualTo(0));
      expect(top, lessThanOrEqualTo(viewportHeight - rowExtent));
    });

    testWidgets('an animated reveal started after an idle time keeps '
        'animating when re-aimed', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      // No frames for longer than the animation.
      await tester.binding.delayed(const Duration(seconds: 5));
      unawaited(
        controller.ensureVisible(
          wideId(70),
          alignment: 0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.linear,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      controller.tree = wideTree(100, extra: early);
      await tester.pump(const Duration(milliseconds: 16));
      expect(scroll.position.activity, isA<DrivenScrollActivity>());
      expect(shownTop(tester, wideId(70)), greaterThan(0));
      await tester.pumpAndSettle();
      expect(shownTop(tester, wideId(70)), 0);
    });

    testWidgets('the first visible row stays in place when the row height '
        'changes', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(40 * rowExtent + 10);
      await tester.pump();
      expect(shownTop(tester, wideId(39)), -10);

      await tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          theme: const DirectoryTreeThemeData(
            rowExtent: 50,
            animationDuration: Duration.zero,
          ),
        ),
      );
      expect(shownTop(tester, wideId(39)), -10);
      expect(scroll.offset, 40 * 50 + 10);

      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      expect(shownTop(tester, wideId(39)), -10);
      expect(scroll.offset, 40 * rowExtent + 10);
    });

    testWidgets('when the revealed row disappears before the next frame, the '
        'next row keeps its place', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(40 * rowExtent);
      await tester.pump();

      controller.reveal(wideId(5), alignment: 0);
      expect(scroll.offset, 6 * rowExtent);
      // File 5 goes away and 30 rows appear above it.
      controller.tree = DirectoryTree<int>.build([
        for (var i = 0; i < 30; i++)
          TreeEntry<int>.file('/w/a${i.toString().padLeft(2, '0')}'),
        for (var i = 0; i < 100; i++)
          if (i != 5) TreeEntry<int>.file('/w/${wideName(i)}'),
      ]);
      await tester.pump();
      expect(shownTop(tester, wideId(6)), rowExtent);
      expect(scroll.offset, 35 * rowExtent);
    });
  });

  testWidgets('an animated reveal is aimed again when the row height '
      'changes', (tester) async {
    final controller = wideController(100);
    addTearDown(controller.dispose);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      treeApp(controller: controller, scrollController: scroll),
    );
    var done = false;
    unawaited(
      controller
          .ensureVisible(
            wideId(70),
            alignment: 0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.linear,
          )
          .then((_) => done = true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      treeApp(
        controller: controller,
        scrollController: scroll,
        theme: const DirectoryTreeThemeData(
          rowExtent: 50,
          animationDuration: Duration.zero,
        ),
      ),
    );
    expect(done, isFalse);
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(shownTop(tester, wideId(70)), 0);
    expect(scroll.offset, 71 * 50);
  });

  group('a fling keeps its momentum through a correction', () {
    // Twenty files that sort before every file of wideTree.
    final early = [
      for (var i = 0; i < 20; i++) 'a${i.toString().padLeft(2, '0')}.txt',
    ];

    // Jumps to [start] in a tree of [count] files, flings up at [speed]
    // px/s, lets three frames pass, then applies [change] (when given) and
    // returns the offset right after that frame and the settled offset.
    Future<({double after, double end})> run(
      WidgetTester tester, {
      required int count,
      required double start,
      double speed = 1000,
      Future<void> Function(DirectoryTreeController<int>, ScrollController)?
      change,
    }) async {
      final controller = wideController(count);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(start);
      await tester.pump();
      await tester.flingFrom(
        const Offset(200, 150),
        const Offset(0, -50),
        speed,
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.position.activity, isA<BallisticScrollActivity>());
      if (change != null) await change(controller, scroll);
      await tester.pump(const Duration(milliseconds: 16));
      final after = scroll.offset;
      await tester.pumpAndSettle();
      return (after: after, end: scroll.offset);
    }

    Future<void> insertEarly(
      DirectoryTreeController<int> controller,
      ScrollController scroll,
      int count,
    ) async {
      controller.tree = wideTree(count, extra: early);
    }

    testWidgets('near the end, where the corrected offset passes the old end '
        '(clamping physics)', (tester) async {
      // 201 rows of 30 px: the old scroll range ends at 5730, and the
      // correction moves the offset past it.
      final control = await run(tester, count: 200, start: 5300);
      final moved = await run(
        tester,
        count: 200,
        start: 5300,
        change: (controller, scroll) => insertEarly(controller, scroll, 200),
      );
      // Without the correction the fling stops before the end; with it the
      // same travel ends past the old end.
      expect(control.end, lessThan(5730));
      expect(control.end + 20 * rowExtent, greaterThan(5730));
      expect(moved.end, closeTo(control.end + 20 * rowExtent, 2));
      // It still moves after the correction.
      expect(moved.end - moved.after, greaterThan(50));
    });

    testWidgets('far from the end', (tester) async {
      final control = await run(tester, count: 200, start: 2000);
      final moved = await run(
        tester,
        count: 200,
        start: 2000,
        change: (controller, scroll) => insertEarly(controller, scroll, 200),
      );
      expect(moved.end, closeTo(control.end + 20 * rowExtent, 2));
    });

    testWidgets('near the end with bouncing physics', (tester) async {
      final control = await run(tester, count: 200, start: 5200, speed: 600);
      final moved = await run(
        tester,
        count: 200,
        start: 5200,
        speed: 600,
        change: (controller, scroll) => insertEarly(controller, scroll, 200),
      );
      expect(control.end, lessThan(5730));
      expect(moved.end, closeTo(control.end + 20 * rowExtent, 2));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('near the end when the row height grows', (tester) async {
      Future<void> taller(
        DirectoryTreeController<int> controller,
        ScrollController scroll,
      ) => tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          theme: const DirectoryTreeThemeData(
            rowExtent: 40,
            animationDuration: Duration.zero,
          ),
        ),
      );
      final control = await run(tester, count: 200, start: 5300);
      final grown = await run(tester, count: 200, start: 5300, change: taller);
      // The anchor moved the offset past the old end (5730); the fling
      // keeps what it had left to travel.
      expect(grown.after, greaterThan(5730));
      expect(grown.end - grown.after, closeTo(control.end - control.after, 2));
    });
  });

  group('corrections at the edges and during builds', () {
    // Twenty files that sort before every file of wideTree.
    final early = [
      for (var i = 0; i < 20; i++) 'a${i.toString().padLeft(2, '0')}.txt',
    ];

    // Pulls past the end of a 200-file tree and releases, lets two frames
    // of the spring back pass, then optionally inserts 20 rows above; the
    // distance past the end on each following frame, until it settles.
    Future<List<double>> springBack(
      WidgetTester tester, {
      required bool insert,
    }) async {
      final controller = wideController(200);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(200, 250));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final position = scroll.position;
      expect(position.pixels, greaterThan(position.maxScrollExtent + 20));
      final past = <double>[position.pixels - position.maxScrollExtent];
      final firstId = controller.rows[(position.pixels / rowExtent).ceil()].id;
      final firstTop = shownTop(tester, firstId);
      if (insert) {
        controller.tree = wideTree(200, extra: early);
        await tester.pump(const Duration(milliseconds: 16));
        // The first visible row moved by one frame of the spring at most.
        expect((shownTop(tester, firstId) - firstTop).abs(), lessThan(10));
      } else {
        await tester.pump(const Duration(milliseconds: 16));
      }
      past.add(position.pixels - position.maxScrollExtent);
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        past.add(position.pixels - position.maxScrollExtent);
      }
      await tester.pumpAndSettle();
      past.add(position.pixels - position.maxScrollExtent);
      return past;
    }

    testWidgets(
      'a correction during an overscroll keeps the overscroll and the '
      'spring back',
      (tester) async {
        final control = await springBack(tester, insert: false);
        final moved = await springBack(tester, insert: true);
        // The content stays past the end by what it was, then settles at
        // the end, as without the insert.
        expect(moved[1], greaterThan(0));
        // A fling restarted outside a frame holds its first frame, so the
        // spring may lag one frame, but nothing jumps.
        expect(moved[1], greaterThan(control[1] - 1));
        expect(moved[1], lessThanOrEqualTo(moved[0] + 1));
        for (var i = 1; i < moved.length; i++) {
          expect(moved[i], greaterThanOrEqualTo(-precisionErrorTolerance));
        }
        expect(moved.last, closeTo(0, precisionErrorTolerance));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets('a tree replaced during a build in a fling dispatches no '
        'scroll notification while widgets build', (tester) async {
      final controller = wideController(200);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var tree = wideTree(200);
      var ends = 0;
      var endsWhileBuilding = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                ends++;
                // Scroll-driven UI that sets state here asserts when the
                // notification comes while widgets build.
                if (tester.binding.buildOwner!.debugBuilding) {
                  endsWhileBuilding++;
                }
                return false;
              },
              child: _TreeOnRebuild(
                tree: tree,
                controller: controller,
                child: treeApp(
                  controller: controller,
                  scrollController: scroll,
                ),
              ),
            );
          },
        ),
      );
      scroll.jumpTo(5300);
      await tester.pump();
      await tester.flingFrom(
        const Offset(200, 150),
        const Offset(0, -50),
        1000,
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.position.activity, isA<BallisticScrollActivity>());
      // Five files above the view and the last fifteen go away: the
      // corrected offset lands at the new end, where the fling stops.
      rebuild(() {
        tree = DirectoryTree<int>.build([
          for (var i = 5; i < 185; i++)
            TreeEntry<int>.file('/w/${wideName(i)}'),
        ]);
      });
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(endsWhileBuilding, 0);
      expect(ends, greaterThan(0));
      expect(scroll.offset, scroll.position.maxScrollExtent);
    });

    testWidgets('an animated reveal whose rows change during a build is aimed '
        'after that frame', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var tree = wideTree(100);
      late StateSetter rebuild;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return NotificationListener<ScrollNotification>(
              // Scroll-driven UI sets state; during a build it asserts.
              onNotification: (_) {
                setState(() {});
                return false;
              },
              child: _TreeOnRebuild(
                tree: tree,
                controller: controller,
                child: treeApp(
                  controller: controller,
                  scrollController: scroll,
                ),
              ),
            );
          },
        ),
      );
      var done = false;
      unawaited(
        controller
            .ensureVisible(
              wideId(70),
              alignment: 0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.linear,
            )
            .then((_) => done = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Twenty rows above the view and five between it and the target.
      rebuild(() {
        tree = wideTree(
          100,
          extra: [...early, for (var i = 0; i < 5; i++) 'f0060_$i.txt'],
        );
      });
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(done, isTrue);
      expect(shownTop(tester, wideId(70)), 0);
    });

    testWidgets('an animated reveal whose row comes into view during a build '
        'stops after that frame', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      var tree = wideTree(100);
      late StateSetter rebuild;
      var ends = 0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return NotificationListener<ScrollEndNotification>(
              onNotification: (_) {
                setState(() => ends++);
                return false;
              },
              child: _TreeOnRebuild(
                tree: tree,
                controller: controller,
                child: treeApp(
                  controller: controller,
                  scrollController: scroll,
                ),
              ),
            );
          },
        ),
      );
      double? doneAt;
      unawaited(
        controller
            .ensureVisible(
              wideId(60),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.linear,
            )
            .then((_) => doneAt = scroll.offset),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Files 30 to 59 go away during a build: file 60 is now on screen.
      rebuild(() {
        tree = DirectoryTree<int>.build([
          for (var i = 0; i < 100; i++)
            if (i < 30 || i >= 60) TreeEntry<int>.file('/w/${wideName(i)}'),
        ]);
      });
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(ends, greaterThan(0));
      expect(doneAt, isNotNull);
      expect(scroll.offset, doneAt);
      final top = shownTop(tester, wideId(60));
      expect(top, greaterThanOrEqualTo(0));
      expect(top, lessThanOrEqualTo(viewportHeight - rowExtent));
    });
  });

  group('visible area', () {
    testWidgets('pageRowCount counts only the rows the viewport shows', (
      tester,
    ) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          before: const [
            SliverPersistentHeader(pinned: true, delegate: _PinnedHeader()),
          ],
        ),
      );
      // A pinned 120 px header leaves 180 px: 6 rows.
      expect(viewportOf(tester).pageRowCount, 6);
      scroll.jumpTo(1000);
      await tester.pump();
      expect(viewportOf(tester).pageRowCount, 6);

      // A 100 px header scrolls away; the 20 px padding leaves with it.
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          before: const [header],
          padding: const EdgeInsets.only(top: 20),
        ),
      );
      scroll.jumpTo(0);
      await tester.pump();
      expect(viewportOf(tester).pageRowCount, 6);
      scroll.jumpTo(1000);
      await tester.pump();
      expect(viewportOf(tester).pageRowCount, 10);
    });

    testWidgets('globalRowRect is null for built rows outside the visible '
        'area', (tester) async {
      final controller = wideController(100);
      addTearDown(controller.dispose);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        treeApp(controller: controller, scrollController: scroll),
      );
      scroll.jumpTo(10 * rowExtent + 15);
      await tester.pump();
      final viewport = viewportOf(tester);
      // Row 9 (file 8) is above the view but built for the cache extent.
      expect(
        find.byKey(ValueKey<NodeId>(wideId(8)), skipOffstage: false),
        findsOneWidget,
      );
      expect(viewport.globalRowRect(9), isNull);
      // Rows 10 and 20 are each half visible.
      expect(viewport.globalRowRect(10), tester.getRect(rowOf(wideId(9))));
      expect(viewport.globalRowRect(20), tester.getRect(rowOf(wideId(19))));
      // Row 21 (file 20) is built for the cache extent below the view.
      expect(
        find.byKey(ValueKey<NodeId>(wideId(20)), skipOffstage: false),
        findsOneWidget,
      );
      expect(viewport.globalRowRect(21), isNull);

      // Rows under a pinned header are hidden too.
      await tester.pumpWidget(
        treeApp(
          controller: controller,
          scrollController: scroll,
          before: const [
            SliverPersistentHeader(pinned: true, delegate: _PinnedHeader()),
          ],
        ),
      );
      scroll.jumpTo(10 * rowExtent);
      await tester.pump();
      // The tree starts at 120 px: rows 6 to 9 are on screen but under the
      // header, row 10 is the first visible one.
      expect(
        find.byKey(ValueKey<NodeId>(wideId(8)), skipOffstage: false),
        findsOneWidget,
      );
      expect(viewportOf(tester).globalRowRect(9), isNull);
      expect(viewportOf(tester).globalRowRect(10), isNotNull);
    });
  });
}

/// The global top edge of the row of [id], or infinity when the row is not
/// built (so a row that jumped out of view fails a closeness check).
double shownTop(WidgetTester tester, NodeId id) {
  final finder = find.byKey(ValueKey<NodeId>(id), skipOffstage: false);
  return finder.evaluate().isEmpty
      ? double.infinity
      : tester.getTopLeft(finder).dy;
}

/// Sets [controller]'s tree to [tree] when rebuilt with a new one, during
/// the build, as a widget that owns a controller for its tree does.
class _TreeOnRebuild extends StatefulWidget {
  const _TreeOnRebuild({
    required this.tree,
    required this.controller,
    required this.child,
  });

  final DirectoryTree<int> tree;
  final DirectoryTreeController<int> controller;
  final Widget child;

  @override
  State<_TreeOnRebuild> createState() => _TreeOnRebuildState();
}

class _TreeOnRebuildState extends State<_TreeOnRebuild> {
  @override
  void didUpdateWidget(_TreeOnRebuild oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tree, widget.tree)) {
      widget.controller.tree = widget.tree;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A pinned header 120 px high.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  const _PinnedHeader();

  @override
  double get minExtent => 120;

  @override
  double get maxExtent => 120;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      const SizedBox.expand();

  @override
  bool shouldRebuild(_PinnedHeader oldDelegate) => false;
}
