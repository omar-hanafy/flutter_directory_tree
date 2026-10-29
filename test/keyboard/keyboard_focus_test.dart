import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keyboard_test_utils.dart';

/// A text field and then a [DirectoryTreeKeyboard] of [controller] (with
/// a [FakeViewport]) in a [MaterialApp]; nothing has the focus.
Future<({FocusNode tree, FocusNode field})> pumpTree(
  WidgetTester tester,
  DirectoryTreeController<Object?> controller, {
  bool selectionFollowsFocus = true,
}) async {
  controller.attachViewport(FakeViewport());
  final tree = FocusNode(debugLabel: 'tree');
  final field = FocusNode(debugLabel: 'field');
  final text = TextEditingController();
  addTearDown(() {
    tree.dispose();
    field.dispose();
    text.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Material(
        child: Column(
          children: [
            TextField(focusNode: field, controller: text),
            DirectoryTreeKeyboard<Object?>(
              controller: controller,
              focusNode: tree,
              selectionFollowsFocus: selectionFollowsFocus,
              child: const SizedBox(height: 100),
            ),
          ],
        ),
      ),
    ),
  );
  return (tree: tree, field: field);
}

List<NodeId> selectedIds(DirectoryTreeController<Object?> controller) => [
  for (final node in controller.selectedNodes) node.id,
];

/// r, alpha (with a1.txt), zao.txt, zał.txt, łódź.txt.
DirectoryTree<Object?> polishTree() => DirectoryTree<Object?>.build(const [
  TreeEntry<Object?>.file('/r/alpha/a1.txt'),
  TreeEntry<Object?>.file('/r/zao.txt'),
  TreeEntry<Object?>.file('/r/zał.txt'),
  TreeEntry<Object?>.file('/r/łódź.txt'),
]);

const lodz = NodeId('/r/łódź.txt');
const zao = NodeId('/r/zao.txt');
const zal = NodeId('/r/zał.txt');

void main() {
  group('the tree gains the focus without a focused row', () {
    testWidgets('Tab focuses the first row without selecting it', (
      tester,
    ) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      final nodes = await pumpTree(tester, controller);
      nodes.field.requestFocus();
      await tester.pump();
      expect(controller.focusedId, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(nodes.tree.hasPrimaryFocus, isTrue);
      expect(controller.focusedId, r);
      expect(controller.selection.isEmpty, isTrue);
    });

    testWidgets('the first shown selected row gets the cursor', (tester) async {
      // a1 is selected but inside the collapsed alpha; banana and apple
      // have rows, apple first.
      final controller = keyboardController(
        selection: SelectionState(
          mode: SelectionMode.multiple,
          selected: const [a1, banana, apple],
        ),
      );
      addTearDown(controller.dispose);
      final nodes = await pumpTree(tester, controller);
      nodes.tree.requestFocus();
      await tester.pump();
      expect(controller.focusedId, apple);
      expect(selectedIds(controller), [a1, apple, banana]);
    });

    testWidgets('a selection of every row stops at the first row', (
      tester,
    ) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      controller
        ..selectAll()
        ..focus(null);
      final nodes = await pumpTree(tester, controller);
      nodes.tree.requestFocus();
      await tester.pump();
      expect(controller.focusedId, r);
    });

    testWidgets('a focused row keeps the cursor', (tester) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      controller.focus(banana);
      final nodes = await pumpTree(tester, controller);
      nodes.tree.requestFocus();
      await tester.pump();
      expect(controller.focusedId, banana);
    });

    testWidgets('an empty tree stays without a focused row', (tester) async {
      final controller = DirectoryTreeController<Object?>();
      addTearDown(controller.dispose);
      final nodes = await pumpTree(tester, controller);
      nodes.tree.requestFocus();
      await tester.pump();
      expect(controller.focusedId, isNull);
    });

    testWidgets('a text field inside the tree taking the focus moves no '
        'cursor; the tree node itself taking it afterwards does', (
      tester,
    ) async {
      // keyboard_test_utils' app: a text field inside the keyboard widget.
      final h = await pumpKeyboard(tester, focusTree: false);
      h.controller.focus(null);
      await tester.pump();
      final focused = <NodeId?>[];
      void record() => focused.add(h.controller.focusedId);
      h.controller.addListener(record);
      addTearDown(() => h.controller.removeListener(record));
      h.insideFocus.requestFocus();
      await tester.pump();
      expect(h.treeFocus.hasFocus, isTrue);
      expect(h.controller.focusedId, isNull);
      expect(h.viewport.shown, isEmpty);
      expect(focused, isEmpty);
      // From the field to the tree's own node: hasFocus stays true, the
      // primary focus arrives.
      h.treeFocus.requestFocus();
      await tester.pump();
      expect(h.controller.focusedId, r);
    });

    testWidgets('a new focus node is followed', (tester) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget app(FocusNode node) => MaterialApp(
        home: DirectoryTreeKeyboard<Object?>(
          controller: controller,
          focusNode: node,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(app(first));
      await tester.pumpWidget(app(second));
      second.requestFocus();
      await tester.pump();
      expect(controller.focusedId, r);
    });
  });

  group('selectionFollowsFocus: false', () {
    Future<DirectoryTreeController<Object?>> pick(WidgetTester tester) async {
      final controller = keyboardController(
        selection: SelectionState(
          mode: SelectionMode.multiple,
          selected: const [apple, readme],
          anchor: apple,
        ),
      );
      addTearDown(controller.dispose);
      final nodes = await pumpTree(
        tester,
        controller,
        selectionFollowsFocus: false,
      );
      controller.focus(alpha);
      nodes.tree.requestFocus();
      await tester.pump();
      return controller;
    }

    testWidgets('every focus move keeps the selection', (tester) async {
      final controller = await pick(tester);
      final moves = <(LogicalKeyboardKey, {bool shift, bool control}), NodeId>{
        (LogicalKeyboardKey.arrowDown, shift: false, control: false): beta,
        (LogicalKeyboardKey.arrowDown, shift: true, control: false): empty,
        (LogicalKeyboardKey.arrowUp, shift: true, control: false): beta,
        (LogicalKeyboardKey.arrowDown, shift: false, control: true): empty,
        (LogicalKeyboardKey.end, shift: false, control: false): readme,
        (LogicalKeyboardKey.home, shift: true, control: false): r,
        (LogicalKeyboardKey.pageDown, shift: false, control: false): empty,
        (LogicalKeyboardKey.pageUp, shift: true, control: false): r,
      };
      for (final MapEntry(key: (key, :shift, :control), value: id)
          in moves.entries) {
        await press(tester, key, shift: shift, control: control);
        expect(controller.focusedId, id, reason: '$key');
        expect(selectedIds(controller), [apple, readme], reason: '$key');
      }
    });

    testWidgets('Right and Left move without selecting', (tester) async {
      final controller = await pick(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.isExpanded(alpha), isTrue);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.focusedId, a1);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(controller.focusedId, alpha);
      expect(selectedIds(controller), [apple, readme]);
    });

    testWidgets('type-ahead moves without selecting', (tester) async {
      final controller = await pick(tester);
      await typeText(tester, 'ban');
      expect(controller.focusedId, banana);
      expect(selectedIds(controller), [apple, readme]);
    });

    testWidgets('Space still toggles the focused row', (tester) async {
      final controller = await pick(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.space);
      expect(selectedIds(controller), [beta, apple, readme]);
    });

    testWidgets('the default moves and selects', (tester) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      final nodes = await pumpTree(tester, controller);
      controller.select(alpha);
      nodes.tree.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(selectedIds(controller), [a1]);
      await typeText(tester, 'ban');
      expect(selectedIds(controller), [banana]);
    });

    testWidgets('debugFillProperties shows the flag when false', (
      tester,
    ) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      String describe({required bool follows}) {
        final builder = DiagnosticPropertiesBuilder();
        DirectoryTreeKeyboard<Object?>(
          controller: controller,
          selectionFollowsFocus: follows,
          child: const SizedBox(),
        ).debugFillProperties(builder);
        return builder.properties
            .where((p) => !p.isFiltered(DiagnosticLevel.info))
            .map((p) => p.toString())
            .join('\n');
      }

      expect(
        describe(follows: false),
        contains('selection does not follow focus'),
      );
      expect(
        describe(follows: true),
        isNot(contains('selection does not follow focus')),
      );
    });
  });

  group('type-ahead with text modifiers', () {
    Future<DirectoryTreeController<Object?>> pumpPolish(
      WidgetTester tester,
    ) async {
      final controller = keyboardController(tree: polishTree());
      addTearDown(controller.dispose);
      final nodes = await pumpTree(tester, controller);
      nodes.tree.requestFocus();
      await tester.pump();
      return controller;
    }

    testWidgets('Option types letters on Apple platforms and Android', (
      tester,
    ) async {
      final controller = await pumpPolish(tester);
      // Option+L types ł on the Polish Pro layout.
      expect(
        await press(tester, LogicalKeyboardKey.keyL, alt: true, character: 'ł'),
        isTrue,
      );
      expect(controller.focusedId, lodz);
      // Ctrl+Option is a shortcut there.
      controller.focus(r);
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: true,
          alt: true,
          character: 'z',
        ),
        isFalse,
      );
      expect(controller.focusedId, r);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets(
      'a text modifier character continues the search',
      (tester) async {
        final controller = await pumpPolish(tester);
        await typeText(tester, 'za');
        expect(controller.focusedId, zao);
        // ł with Option, or with AltGr on Windows: "zał" moves on.
        final windows = defaultTargetPlatform == TargetPlatform.windows;
        await press(
          tester,
          LogicalKeyboardKey.keyL,
          control: windows,
          alt: true,
          character: 'ł',
        );
        expect(controller.focusedId, zal);
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.windows,
      }),
    );

    testWidgets('AltGr (Ctrl and Alt) types letters on Windows', (
      tester,
    ) async {
      final controller = await pumpPolish(tester);
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyL,
          control: true,
          alt: true,
          character: 'ł',
        ),
        isTrue,
      );
      expect(controller.focusedId, lodz);
      // Alt alone opens menus on Windows.
      controller.focus(r);
      expect(
        await press(tester, LogicalKeyboardKey.keyZ, alt: true, character: 'z'),
        isFalse,
      );
      expect(controller.focusedId, r);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('Ctrl with Alt, and Alt alone, stay out on Linux', (
      tester,
    ) async {
      final controller = await pumpPolish(tester);
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyL,
          control: true,
          alt: true,
          character: 'ł',
        ),
        isFalse,
      );
      expect(
        await press(tester, LogicalKeyboardKey.keyZ, alt: true, character: 'z'),
        isFalse,
      );
      expect(controller.focusedId, r);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Ctrl alone and Meta stay out everywhere', (tester) async {
      final controller = await pumpPolish(tester);
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyZ,
          control: true,
          character: 'z',
        ),
        isFalse,
      );
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyZ,
          meta: true,
          character: 'z',
        ),
        isFalse,
      );
      expect(
        await press(
          tester,
          LogicalKeyboardKey.keyZ,
          meta: true,
          alt: true,
          character: 'z',
        ),
        isFalse,
      );
      expect(controller.focusedId, r);
    }, variant: TargetPlatformVariant.all());
  });
}
