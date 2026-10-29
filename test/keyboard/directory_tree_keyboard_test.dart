import 'dart:async';

import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keyboard_test_utils.dart';

/// Windows, Linux, and macOS: the bindings every platform shares.
TargetPlatformVariant get everyDesktop => TargetPlatformVariant.desktop();

/// Windows and Linux: Ctrl bindings.
TargetPlatformVariant get windowsAndLinux => TargetPlatformVariant(
  const <TargetPlatform>{TargetPlatform.windows, TargetPlatform.linux},
);

/// macOS: Cmd bindings.
TargetPlatformVariant get macOS =>
    TargetPlatformVariant.only(TargetPlatform.macOS);

/// What a binding test can check after its key press.
final class BindingResult {
  BindingResult(this.harness, this.handled, this.activated, this.menus);

  final KeyboardHarness harness;
  final bool handled;
  final List<TreeRow<Object?>> activated;
  final int menus;

  DirectoryTreeController<Object?> get controller => harness.controller;
}

/// Pumps the harness, runs [arrange] on its controller, presses [key] with
/// the modifiers, and runs [verify]; once per platform of [variant].
///
/// An ancestor action records [OpenTreeContextMenuIntent] (standing in for
/// the context menu host) and `onActivate` records activated rows.
void bindingTest(
  String description, {
  required LogicalKeyboardKey key,
  bool shift = false,
  bool control = false,
  bool meta = false,
  String? character,
  required void Function(DirectoryTreeController<Object?> controller) arrange,
  required void Function(BindingResult result) verify,
  required TargetPlatformVariant variant,
}) {
  testWidgets(description, (tester) async {
    final activated = <TreeRow<Object?>>[];
    var menus = 0;
    final harness = await pumpKeyboard(
      tester,
      onActivate: activated.add,
      ancestorActions: <Type, Action<Intent>>{
        OpenTreeContextMenuIntent: CallbackAction<OpenTreeContextMenuIntent>(
          onInvoke: (_) {
            menus++;
            return null;
          },
        ),
      },
    );
    arrange(harness.controller);
    final handled = await press(
      tester,
      key,
      shift: shift,
      control: control,
      meta: meta,
      character: character,
    );
    verify(BindingResult(harness, handled, activated, menus));
  }, variant: variant);
}

void main() {
  group('default bindings on Windows, Linux, and macOS', () {
    bindingTest(
      'Down moves to the next row and selects it',
      key: LogicalKeyboardKey.arrowDown,
      arrange: (c) => c.select(r),
      verify: (result) {
        expect(result.handled, isTrue);
        expect(result.controller.focusedId, alpha);
        expect(result.harness.selectedIds, [alpha]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Up moves to the previous row and selects it',
      key: LogicalKeyboardKey.arrowUp,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.handled, isTrue);
        expect(result.controller.focusedId, r);
        expect(result.harness.selectedIds, [r]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+Down extends the selection',
      key: LogicalKeyboardKey.arrowDown,
      shift: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.focusedId, beta);
        expect(result.harness.selectedIds, [alpha, beta]);
        expect(result.controller.selection.anchor, alpha);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+Up extends the selection',
      key: LogicalKeyboardKey.arrowUp,
      shift: true,
      arrange: (c) => c.select(beta),
      verify: (result) {
        expect(result.controller.focusedId, alpha);
        expect(result.harness.selectedIds, [alpha, beta]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Home moves to the first row',
      key: LogicalKeyboardKey.home,
      arrange: (c) => c.select(banana),
      verify: (result) {
        expect(result.controller.focusedId, r);
        expect(result.harness.selectedIds, [r]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'End moves to the last row',
      key: LogicalKeyboardKey.end,
      arrange: (c) => c.select(r),
      verify: (result) {
        expect(result.controller.focusedId, readme);
        expect(result.harness.selectedIds, [readme]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+Home extends the selection to the first row',
      key: LogicalKeyboardKey.home,
      shift: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.focusedId, r);
        expect(result.harness.selectedIds, [r, alpha]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+End extends the selection to the last row',
      key: LogicalKeyboardKey.end,
      shift: true,
      arrange: (c) => c.select(banana),
      verify: (result) {
        expect(result.controller.focusedId, readme);
        expect(result.harness.selectedIds, [banana, myFile, myNotes, readme]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      "PageDown moves by the viewport's page",
      key: LogicalKeyboardKey.pageDown,
      arrange: (c) => c.select(r),
      verify: (result) {
        // The fake viewport shows 3 rows.
        expect(result.controller.focusedId, empty);
        expect(result.harness.selectedIds, [empty]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      "PageUp moves by the viewport's page",
      key: LogicalKeyboardKey.pageUp,
      arrange: (c) => c.select(readme),
      verify: (result) {
        expect(result.controller.focusedId, banana);
        expect(result.harness.selectedIds, [banana]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+PageDown extends the selection by a page',
      key: LogicalKeyboardKey.pageDown,
      shift: true,
      arrange: (c) => c.select(r),
      verify: (result) {
        expect(result.controller.focusedId, empty);
        expect(result.harness.selectedIds, [r, alpha, beta, empty]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+PageUp extends the selection by a page',
      key: LogicalKeyboardKey.pageUp,
      shift: true,
      arrange: (c) => c.select(readme),
      verify: (result) {
        expect(result.controller.focusedId, banana);
        expect(result.harness.selectedIds, [banana, myFile, myNotes, readme]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Right expands a collapsed directory',
      key: LogicalKeyboardKey.arrowRight,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isTrue);
        expect(result.controller.focusedId, alpha);
        expect(result.harness.rowIds.sublist(1, 4), [alpha, a1, a2]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Right moves into an expanded directory',
      key: LogicalKeyboardKey.arrowRight,
      arrange: (c) => c
        ..expand(alpha)
        ..select(alpha),
      verify: (result) {
        expect(result.controller.focusedId, a1);
        expect(result.harness.selectedIds, [a1]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Left collapses an expanded directory',
      key: LogicalKeyboardKey.arrowLeft,
      arrange: (c) => c
        ..expand(alpha)
        ..select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isFalse);
        expect(result.controller.focusedId, alpha);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Left moves from a collapsed row to its parent',
      key: LogicalKeyboardKey.arrowLeft,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.focusedId, r);
        expect(result.harness.selectedIds, [r]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Enter toggles a directory and calls onActivate',
      key: LogicalKeyboardKey.enter,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isTrue);
        expect([for (final row in result.activated) row.id], [alpha]);
        expect(result.activated.single.isExpanded, isTrue);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'NumpadEnter toggles a directory and calls onActivate',
      key: LogicalKeyboardKey.numpadEnter,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isTrue);
        expect([for (final row in result.activated) row.id], [alpha]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Space toggles the selection of the focused row',
      key: LogicalKeyboardKey.space,
      arrange: (c) => c
        ..select(alpha)
        ..focus(beta),
      verify: (result) {
        expect(result.handled, isTrue);
        expect(result.harness.selectedIds, [alpha, beta]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Ctrl+Space toggles the selection of the focused row',
      key: LogicalKeyboardKey.space,
      control: true,
      arrange: (c) => c
        ..select(alpha)
        ..focus(beta),
      verify: (result) {
        expect(result.harness.selectedIds, [alpha, beta]);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Escape clears the selection',
      key: LogicalKeyboardKey.escape,
      arrange: (c) => c
        ..select(alpha)
        ..extendSelection(banana),
      verify: (result) {
        expect(result.handled, isTrue);
        expect(result.controller.selection.isEmpty, isTrue);
        expect(result.controller.focusedId, banana);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'the * character expands the whole subtree',
      key: LogicalKeyboardKey.digit8,
      shift: true,
      character: '*',
      arrange: (c) => c.select(beta),
      verify: (result) {
        expect(result.controller.isExpanded(beta), isTrue);
        expect(result.controller.isExpanded(deep), isTrue);
        expect(
          result.harness.rowIds.contains(const NodeId('/r/beta/deep/x.txt')),
          isTrue,
        );
      },
      variant: everyDesktop,
    );

    bindingTest(
      'NumpadMultiply expands the whole subtree',
      key: LogicalKeyboardKey.numpadMultiply,
      character: '*',
      arrange: (c) => c.select(beta),
      verify: (result) {
        expect(result.controller.isExpanded(beta), isTrue);
        expect(result.controller.isExpanded(deep), isTrue);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'NumpadAdd expands',
      key: LogicalKeyboardKey.numpadAdd,
      character: '+',
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isTrue);
        expect(result.controller.focusedId, alpha);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'NumpadSubtract collapses',
      key: LogicalKeyboardKey.numpadSubtract,
      character: '-',
      arrange: (c) => c
        ..expand(alpha)
        ..select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isFalse);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'Shift+F10 opens the context menu',
      key: LogicalKeyboardKey.f10,
      shift: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.handled, isTrue);
        expect(result.menus, 1);
      },
      variant: everyDesktop,
    );

    bindingTest(
      'the context menu key opens the context menu',
      key: LogicalKeyboardKey.contextMenu,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.handled, isTrue);
        expect(result.menus, 1);
      },
      variant: everyDesktop,
    );
  });

  group('default bindings on Windows and Linux', () {
    bindingTest(
      'Ctrl+A selects every row',
      key: LogicalKeyboardKey.keyA,
      control: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.harness.selectedIds, result.harness.rowIds);
        expect(result.harness.selectedIds, hasLength(10));
      },
      variant: windowsAndLinux,
    );

    bindingTest(
      'Ctrl+Down moves without selecting',
      key: LogicalKeyboardKey.arrowDown,
      control: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.focusedId, beta);
        expect(result.harness.selectedIds, [alpha]);
      },
      variant: windowsAndLinux,
    );

    bindingTest(
      'Ctrl+Up moves without selecting',
      key: LogicalKeyboardKey.arrowUp,
      control: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.focusedId, r);
        expect(result.harness.selectedIds, [alpha]);
      },
      variant: windowsAndLinux,
    );

    bindingTest(
      'Ctrl+Home moves without selecting',
      key: LogicalKeyboardKey.home,
      control: true,
      arrange: (c) => c.select(banana),
      verify: (result) {
        expect(result.controller.focusedId, r);
        expect(result.harness.selectedIds, [banana]);
      },
      variant: windowsAndLinux,
    );

    bindingTest(
      'Ctrl+End moves without selecting',
      key: LogicalKeyboardKey.end,
      control: true,
      arrange: (c) => c.select(r),
      verify: (result) {
        expect(result.controller.focusedId, readme);
        expect(result.harness.selectedIds, [r]);
      },
      variant: windowsAndLinux,
    );

    bindingTest(
      'Ctrl+PageDown moves without selecting',
      key: LogicalKeyboardKey.pageDown,
      control: true,
      arrange: (c) => c.select(r),
      verify: (result) {
        expect(result.controller.focusedId, empty);
        expect(result.harness.selectedIds, [r]);
      },
      variant: windowsAndLinux,
    );

    bindingTest(
      'Ctrl+PageUp moves without selecting',
      key: LogicalKeyboardKey.pageUp,
      control: true,
      arrange: (c) => c.select(readme),
      verify: (result) {
        expect(result.controller.focusedId, banana);
        expect(result.harness.selectedIds, [readme]);
      },
      variant: windowsAndLinux,
    );

    for (final (name, key) in <(String, LogicalKeyboardKey)>[
      ('Cmd+A', LogicalKeyboardKey.keyA),
      ('Cmd+Down', LogicalKeyboardKey.arrowDown),
      ('Cmd+Up', LogicalKeyboardKey.arrowUp),
    ]) {
      bindingTest(
        '$name is not bound',
        key: key,
        meta: true,
        arrange: (c) => c.select(alpha),
        verify: (result) {
          expect(result.controller.focusedId, alpha);
          expect(result.harness.selectedIds, [alpha]);
          expect(result.controller.isExpanded(alpha), isFalse);
          expect(result.activated, isEmpty);
        },
        variant: windowsAndLinux,
      );
    }
  });

  group('default bindings on macOS', () {
    bindingTest(
      'Cmd+A selects every row',
      key: LogicalKeyboardKey.keyA,
      meta: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.harness.selectedIds, result.harness.rowIds);
      },
      variant: macOS,
    );

    bindingTest(
      'Cmd+Down activates the focused row',
      key: LogicalKeyboardKey.arrowDown,
      meta: true,
      arrange: (c) => c.select(alpha),
      verify: (result) {
        expect(result.controller.isExpanded(alpha), isTrue);
        expect([for (final row in result.activated) row.id], [alpha]);
      },
      variant: macOS,
    );

    bindingTest(
      'Cmd+Up moves to the parent row',
      key: LogicalKeyboardKey.arrowUp,
      meta: true,
      arrange: (c) => c
        ..expand(alpha)
        ..select(a2),
      verify: (result) {
        expect(result.controller.focusedId, alpha);
        expect(result.harness.selectedIds, [alpha]);
        expect(result.controller.isExpanded(alpha), isTrue);
      },
      variant: macOS,
    );

    for (final (name, key) in <(String, LogicalKeyboardKey)>[
      ('Ctrl+A', LogicalKeyboardKey.keyA),
      ('Ctrl+Down', LogicalKeyboardKey.arrowDown),
      ('Ctrl+Up', LogicalKeyboardKey.arrowUp),
      ('Ctrl+Home', LogicalKeyboardKey.home),
      ('Ctrl+End', LogicalKeyboardKey.end),
      ('Ctrl+PageDown', LogicalKeyboardKey.pageDown),
      ('Ctrl+PageUp', LogicalKeyboardKey.pageUp),
    ]) {
      bindingTest(
        '$name is not bound',
        key: key,
        control: true,
        arrange: (c) => c.select(alpha),
        verify: (result) {
          expect(result.controller.focusedId, alpha);
          expect(result.harness.selectedIds, [alpha]);
        },
        variant: macOS,
      );
    }
  });

  group('right-to-left', () {
    testWidgets('Left expands and moves in, Right collapses and moves out', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester, textDirection: TextDirection.rtl);
      h.controller.select(alpha);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.controller.isExpanded(alpha), isTrue);
      expect(h.controller.focusedId, alpha);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.controller.focusedId, a1);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(h.controller.focusedId, alpha);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(h.controller.isExpanded(alpha), isFalse);
      expect(h.controller.focusedId, alpha);
    }, variant: everyDesktop);

    testWidgets('NumpadAdd and NumpadSubtract keep their meaning', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester, textDirection: TextDirection.rtl);
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.numpadAdd, character: '+');
      expect(h.controller.isExpanded(alpha), isTrue);
      await press(tester, LogicalKeyboardKey.numpadSubtract, character: '-');
      expect(h.controller.isExpanded(alpha), isFalse);
    });

    testWidgets('a direction change at runtime swaps the arrows', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      await tester.pumpWidget(
        buildKeyboardApp(
          controller: h.controller,
          treeFocus: h.treeFocus,
          outsideFocus: h.outsideFocus,
          insideFocus: h.insideFocus,
          outsideField: h.outsideField,
          insideField: h.insideField,
          childKey: h.childKey,
          textDirection: TextDirection.rtl,
        ),
      );
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(h.controller.isExpanded(alpha), isFalse);
      expect(h.controller.focusedId, r);
    });
  });

  group('ExpandTreeNodeIntent and CollapseTreeNodeIntent', () {
    testWidgets('Right on a file or a leaf directory changes nothing', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);

      h.controller.select(apple);
      notifications.take();
      expect(await press(tester, LogicalKeyboardKey.arrowRight), isTrue);
      expect(notifications.take(), 0);

      h.controller.select(empty);
      notifications.take();
      expect(await press(tester, LogicalKeyboardKey.arrowRight), isTrue);
      expect(notifications.take(), 0);
      expect(h.controller.isExpanded(empty), isFalse);
    });

    testWidgets('Right on an expanded empty directory changes nothing', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller
        ..expand(empty)
        ..select(empty);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(notifications.count, 0);
      expect(h.controller.focusedId, empty);
    });

    testWidgets(
      'Left collapses an expanded empty directory, then moves to the parent',
      (tester) async {
        final h = await pumpKeyboard(tester);
        h.controller
          ..expand(empty)
          ..select(empty);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(h.controller.isExpanded(empty), isFalse);
        expect(h.controller.focusedId, empty);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(h.controller.focusedId, r);
      },
    );

    testWidgets('Left on a top-level collapsed row consumes the key', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller
        ..collapse(r)
        ..select(r);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), isTrue);
      expect(notifications.count, 0);
      expect(h.treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('with nothing focused, Right and Left consume their keys', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      expect(await press(tester, LogicalKeyboardKey.arrowRight), isTrue);
      expect(await press(tester, LogicalKeyboardKey.arrowLeft), isTrue);
      expect(notifications.count, 0);
      expect(h.controller.focusedId, isNull);
    });

    testWidgets('compacted rows expand, collapse, and step as one row', (
      tester,
    ) async {
      final controller = keyboardController(
        tree: DirectoryTree<Object?>.build(const [
          TreeEntry<Object?>.file('/r/lib/src/utils/x.dart'),
          TreeEntry<Object?>.file('/r/top.txt'),
        ]),
        compactFolders: true,
      );
      const utils = NodeId('/r/lib/src/utils');
      const x = NodeId('/r/lib/src/utils/x.dart');
      final h = await pumpKeyboard(tester, controller: controller);
      expect(h.controller.rows[1].label, 'lib/src/utils');
      h.controller.select(utils);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(h.controller.isExpanded(utils), isTrue);
      expect(h.rowIds, contains(x));

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(h.controller.focusedId, x);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.controller.focusedId, utils);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(h.controller.isExpanded(utils), isFalse);
      expect(h.rowIds, isNot(contains(x)));
    });

    group('lazy directories', () {
      late List<Completer<Iterable<TreeEntry<Object?>>>> loads;
      late List<NodeId> loaded;

      DirectoryTreeController<Object?> lazyController() {
        loads = <Completer<Iterable<TreeEntry<Object?>>>>[];
        loaded = <NodeId>[];
        Future<Iterable<TreeEntry<Object?>>> loader(
          DirectoryNode<Object?> directory,
        ) {
          final completer = Completer<Iterable<TreeEntry<Object?>>>();
          loads.add(completer);
          loaded.add(directory.id);
          return completer.future;
        }

        return keyboardController(
          tree: DirectoryTree<Object?>.build(const [
            TreeEntry<Object?>.directory('/r/lazy'),
            TreeEntry<Object?>.file('/r/file.txt'),
          ]),
          loadChildren: loader,
        );
      }

      const lazy = NodeId('/r/lazy');
      const child = NodeId('/r/lazy/child.txt');

      testWidgets('Right starts the load, then moves into the children', (
        tester,
      ) async {
        final h = await pumpKeyboard(tester, controller: lazyController());
        h.controller.select(lazy);
        expect(h.controller.isExpandable(lazy), isTrue);
        expect(h.controller.loadStatusOf(lazy), DirectoryLoadStatus.notLoaded);

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(h.controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);
        expect(h.controller.isExpanded(lazy), isTrue);
        expect(loaded, [lazy]);

        // While it loads, Right has nowhere to go and starts nothing new.
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(loaded, [lazy]);
        expect(h.controller.focusedId, lazy);

        loads.single.complete(const [
          TreeEntry<Object?>.file('/r/lazy/child.txt'),
        ]);
        await tester.pump();
        expect(h.controller.loadStatusOf(lazy), DirectoryLoadStatus.loaded);
        expect(h.rowIds, contains(child));

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(h.controller.focusedId, child);
      });

      testWidgets('Right retries a failed load', (tester) async {
        final h = await pumpKeyboard(tester, controller: lazyController());
        h.controller.select(lazy);
        await press(tester, LogicalKeyboardKey.arrowRight);
        loads.single.completeError(StateError('offline'));
        await tester.pump();
        expect(h.controller.loadStatusOf(lazy), DirectoryLoadStatus.failed);
        expect(h.controller.isExpanded(lazy), isTrue);

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(loaded, [lazy, lazy]);
        expect(h.controller.loadStatusOf(lazy), DirectoryLoadStatus.loading);

        loads.last.complete(const [
          TreeEntry<Object?>.file('/r/lazy/child.txt'),
        ]);
        await tester.pump();
        expect(h.rowIds, contains(child));
      });

      testWidgets('Right starts the load of a directory expandAll opened', (
        tester,
      ) async {
        final h = await pumpKeyboard(tester, controller: lazyController());
        h.controller
          ..expandAll()
          ..select(lazy);
        await tester.pump();
        expect(loaded, isEmpty);
        expect(h.controller.isExpanded(lazy), isTrue);

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(loaded, [lazy]);
      });

      testWidgets('Left collapses a loading directory', (tester) async {
        final h = await pumpKeyboard(tester, controller: lazyController());
        h.controller.select(lazy);
        await press(tester, LogicalKeyboardKey.arrowRight);
        await press(tester, LogicalKeyboardKey.arrowLeft);
        expect(h.controller.isExpanded(lazy), isFalse);
        expect(h.controller.focusedId, lazy);
      });
    });
  });

  group('ActivateTreeNodeIntent', () {
    testWidgets('Enter toggles a directory both ways with onActivate', (
      tester,
    ) async {
      final activated = <TreeRow<Object?>>[];
      final h = await pumpKeyboard(tester, onActivate: activated.add);
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.enter);
      await press(tester, LogicalKeyboardKey.enter);
      expect([for (final row in activated) row.id], [alpha, alpha]);
      expect([for (final row in activated) row.isExpanded], [true, false]);
      expect(h.controller.isExpanded(alpha), isFalse);
    });

    testWidgets('Enter on a file only calls onActivate', (tester) async {
      final activated = <TreeRow<Object?>>[];
      final h = await pumpKeyboard(tester, onActivate: activated.add);
      h.controller.select(apple);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      expect(await press(tester, LogicalKeyboardKey.enter), isTrue);
      expect([for (final row in activated) row.id], [apple]);
      expect(notifications.count, 0);
    });

    testWidgets('without onActivate, Enter toggles a directory', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.enter);
      expect(h.controller.isExpanded(alpha), isTrue);
    });

    testWidgets('without onActivate, Enter on a file does nothing', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(apple);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      await press(tester, LogicalKeyboardKey.enter);
      expect(notifications.count, 0);
    });

    testWidgets('with nothing focused, Enter reaches the widgets above', (
      tester,
    ) async {
      var activations = 0;
      final h = await pumpKeyboard(
        tester,
        // The app's default shortcuts map Enter to ActivateIntent, and on
        // the web to ButtonActivateIntent.
        ancestorActions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => activations++,
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => activations++,
          ),
        },
      );
      expect(h.controller.focusedId, isNull);
      await press(tester, LogicalKeyboardKey.enter);
      expect(activations, 1);
    });
  });

  group('ToggleTreeSelectionIntent', () {
    testWidgets('Space toggles a selected row off in multiple mode', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.controller.selection.isEmpty, isTrue);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.selectedIds, [alpha]);
    });

    testWidgets('Space selects the focused row in single mode', (tester) async {
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(
          selection: const SelectionState.empty(mode: SelectionMode.single),
        ),
      );
      h.controller
        ..select(alpha)
        ..focus(beta);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.selectedIds, [beta]);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.selectedIds, [beta]);
    });

    testWidgets('Space toggles the check in checks mode', (tester) async {
      final h = await pumpKeyboard(
        tester,
        checkboxMode: DirectoryTreeCheckboxMode.checks,
      );
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.controller.checkStateOf(alpha), CheckState.checked);
      expect(h.controller.checkStateOf(r), CheckState.partial);
      expect(h.selectedIds, [alpha]);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.controller.checkStateOf(alpha), CheckState.unchecked);
    });

    testWidgets('Space toggles the selection in selection checkbox mode', (
      tester,
    ) async {
      final h = await pumpKeyboard(
        tester,
        checkboxMode: DirectoryTreeCheckboxMode.selection,
      );
      h.controller
        ..select(alpha)
        ..focus(beta);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.selectedIds, [alpha, beta]);
      expect(h.controller.checks.isEmpty, isTrue);
    });

    testWidgets('with nothing focused, Space is left to the widgets above', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      expect(await press(tester, LogicalKeyboardKey.space), isFalse);
      expect(h.controller.selection.isEmpty, isTrue);
    });
  });

  group('ClearTreeSelectionIntent and SelectAllTreeNodesIntent', () {
    testWidgets(
      'Escape with an empty selection reaches the dialog above the tree',
      (tester) async {
        var dismissals = 0;
        final h = await pumpKeyboard(
          tester,
          ancestorActions: <Type, Action<Intent>>{
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) => dismissals++,
            ),
          },
        );
        h.controller.select(alpha);
        await press(tester, LogicalKeyboardKey.escape);
        expect(h.controller.selection.isEmpty, isTrue);
        expect(dismissals, 0);
        await press(tester, LogicalKeyboardKey.escape);
        expect(dismissals, 1);
      },
    );

    testWidgets('Ctrl+A in single mode is left to the widgets above', (
      tester,
    ) async {
      var selectAlls = 0;
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(
          selection: const SelectionState.empty(mode: SelectionMode.single),
        ),
        ancestorActions: <Type, Action<Intent>>{
          SelectAllTextIntent: CallbackAction<SelectAllTextIntent>(
            onInvoke: (_) => selectAlls++,
          ),
        },
      );
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.keyA, control: true);
      expect(h.selectedIds, [alpha]);
      expect(selectAlls, 1);
    }, variant: windowsAndLinux);
  });

  group('MoveTreeFocusIntent', () {
    testWidgets('with nothing focused, Down goes to the first row', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.focusedId, r);
      expect(h.selectedIds, [r]);
    });

    testWidgets('with nothing focused, Up goes to the last row', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(h.controller.focusedId, readme);
    });

    testWidgets('a move notifies once and scrolls the row into view', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      h.viewport.shown.clear();
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(notifications.count, 1);
      expect(h.viewport.shown, [1]);
    });

    testWidgets('moves at the edges consume the key and keep the focus', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      expect(await press(tester, LogicalKeyboardKey.arrowUp), isTrue);
      expect(h.treeFocus.hasPrimaryFocus, isTrue);
      expect(h.controller.focusedId, r);

      h.controller.select(readme);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), isTrue);
      expect(h.treeFocus.hasPrimaryFocus, isTrue);
      expect(h.controller.focusedId, readme);
    });

    testWidgets('an empty tree consumes the arrows', (tester) async {
      final h = await pumpKeyboard(
        tester,
        controller: DirectoryTreeController<Object?>(),
      );
      expect(await press(tester, LogicalKeyboardKey.arrowDown), isTrue);
      expect(await press(tester, LogicalKeyboardKey.arrowRight), isTrue);
      expect(h.treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('Tab still moves the focus out of the tree', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.tab);
      expect(h.treeFocus.hasPrimaryFocus, isFalse);
    });
  });

  group('ExpandTreeSubtreeIntent', () {
    testWidgets('* on a file changes nothing', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(apple);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      await typeAsterisk(tester);
      expect(notifications.count, 0);
    });

    testWidgets('* with nothing focused is not consumed', (tester) async {
      final h = await pumpKeyboard(tester);
      expect(await typeAsterisk(tester), isFalse);
      expect(h.controller.isExpanded(alpha), isFalse);
    });
  });

  group('OpenTreeContextMenuIntent', () {
    testWidgets('without a menu host the keys do nothing and throw nothing', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      expect(await press(tester, LogicalKeyboardKey.f10, shift: true), isFalse);
      expect(await press(tester, LogicalKeyboardKey.contextMenu), isFalse);
      expect(tester.takeException(), isNull);
      expect(notifications.count, 0);
      expect(
        Actions.maybeFind<OpenTreeContextMenuIntent>(
          h.childKey.currentContext!,
        ),
        isNull,
      );
    });
  });

  group('overridable actions', () {
    final cases = <(String, Intent, Future<bool> Function(WidgetTester))>[
      (
        'MoveTreeFocusIntent',
        const MoveTreeFocusIntent(TreeFocusMove.next),
        (tester) => press(tester, LogicalKeyboardKey.arrowDown),
      ),
      (
        'ExpandTreeNodeIntent',
        const ExpandTreeNodeIntent(),
        (tester) => press(tester, LogicalKeyboardKey.arrowRight),
      ),
      (
        'CollapseTreeNodeIntent',
        const CollapseTreeNodeIntent(),
        (tester) => press(tester, LogicalKeyboardKey.arrowLeft),
      ),
      (
        'ExpandTreeSubtreeIntent',
        const ExpandTreeSubtreeIntent(),
        typeAsterisk,
      ),
      (
        'ActivateTreeNodeIntent',
        const ActivateTreeNodeIntent(),
        (tester) => press(tester, LogicalKeyboardKey.enter),
      ),
      (
        'ToggleTreeSelectionIntent',
        const ToggleTreeSelectionIntent(),
        (tester) => press(tester, LogicalKeyboardKey.space),
      ),
      (
        'SelectAllTreeNodesIntent',
        const SelectAllTreeNodesIntent(),
        (tester) => press(tester, LogicalKeyboardKey.keyA, control: true),
      ),
      (
        'ClearTreeSelectionIntent',
        const ClearTreeSelectionIntent(),
        (tester) => press(tester, LogicalKeyboardKey.escape),
      ),
    ];

    for (final (name, intent, pressKey) in cases) {
      testWidgets('an ancestor Actions replaces the $name action', (
        tester,
      ) async {
        final received = <Intent>[];
        final activated = <TreeRow<Object?>>[];
        final h = await pumpKeyboard(
          tester,
          onActivate: activated.add,
          ancestorActions: <Type, Action<Intent>>{
            intent.runtimeType: CallbackAction<Intent>(
              onInvoke: (intent) {
                received.add(intent);
                return null;
              },
            ),
          },
        );
        h.controller.select(alpha);
        final notifications = Notifications(h.controller);
        addTearDown(notifications.dispose);

        expect(await pressKey(tester), isTrue);
        expect(received, [intent]);
        expect(notifications.count, 0);
        expect(activated, isEmpty);
      }, variant: windowsAndLinux);
    }

    testWidgets('an override can run the default through callingAction', (
      tester,
    ) async {
      final override = _LoggingAction<ExpandTreeNodeIntent>();
      final h = await pumpKeyboard(
        tester,
        ancestorActions: <Type, Action<Intent>>{ExpandTreeNodeIntent: override},
      );
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(override.invocations, 1);
      expect(h.controller.isExpanded(alpha), isTrue);
    });

    testWidgets('an override decides whether the key is consumed', (
      tester,
    ) async {
      final h = await pumpKeyboard(
        tester,
        ancestorActions: <Type, Action<Intent>>{
          MoveTreeFocusIntent: DoNothingAction(consumesKey: false),
        },
      );
      h.controller.select(alpha);
      expect(await press(tester, LogicalKeyboardKey.arrowDown), isFalse);
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('Actions.invoke from inside the tree runs the default action', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(beta);
      final context = h.childKey.currentContext!;
      Actions.invoke(context, const ExpandTreeSubtreeIntent());
      expect(h.controller.isExpanded(deep), isTrue);
      Actions.invoke(
        context,
        const MoveTreeFocusIntent(
          TreeFocusMove.last,
          selection: TreeSelectionUpdate.keep,
        ),
      );
      expect(h.controller.focusedId, const NodeId('/r/README.md'));
      expect(h.selectedIds, [beta]);
    });

    testWidgets('Actions.invoke from inside the tree finds the override', (
      tester,
    ) async {
      final received = <Intent>[];
      final h = await pumpKeyboard(
        tester,
        ancestorActions: <Type, Action<Intent>>{
          ClearTreeSelectionIntent: CallbackAction<ClearTreeSelectionIntent>(
            onInvoke: received.add,
          ),
        },
      );
      h.controller.select(alpha);
      Actions.invoke(
        h.childKey.currentContext!,
        const ClearTreeSelectionIntent(),
      );
      expect(received, hasLength(1));
      expect(h.selectedIds, [alpha]);
    });
  });

  group('focus', () {
    Future<void> expectInert(WidgetTester tester, KeyboardHarness h) async {
      h.controller.select(alpha);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      final keys = <(LogicalKeyboardKey, bool, bool)>[
        (LogicalKeyboardKey.arrowDown, false, false),
        (LogicalKeyboardKey.arrowUp, false, false),
        (LogicalKeyboardKey.arrowRight, false, false),
        (LogicalKeyboardKey.arrowDown, true, false),
        (LogicalKeyboardKey.home, false, false),
        (LogicalKeyboardKey.end, false, false),
        (LogicalKeyboardKey.pageDown, false, false),
        (LogicalKeyboardKey.space, false, false),
        (LogicalKeyboardKey.space, false, true),
        (LogicalKeyboardKey.enter, false, false),
        (LogicalKeyboardKey.numpadEnter, false, false),
        (LogicalKeyboardKey.escape, false, false),
        (LogicalKeyboardKey.keyA, false, true),
        (LogicalKeyboardKey.numpadAdd, false, false),
        (LogicalKeyboardKey.numpadMultiply, false, false),
        (LogicalKeyboardKey.contextMenu, false, false),
      ];
      for (final (key, shift, control) in keys) {
        await press(tester, key, shift: shift, control: control);
      }
      await typeAsterisk(tester);
      // Characters are not taken by the tree: the platform would hand them
      // to the focused text field.
      expect(await typeText(tester, 'b'), isFalse);
      expect(notifications.count, 0);
      expect(h.controller.focusedId, alpha);
      expect(h.selectedIds, [alpha]);
      expect(h.controller.isExpanded(alpha), isFalse);
    }

    Future<void> expectArrowsMoveTheCaret(
      WidgetTester tester,
      FocusNode focus,
      TextEditingController field,
    ) async {
      // On the web the browser moves the caret itself, which a widget test
      // cannot observe; the inert tree is what the callers check there.
      if (kIsWeb) return;
      field.selection = TextSelection.collapsed(offset: field.text.length);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(
        field.selection,
        TextSelection.collapsed(offset: field.text.length - 1),
      );
      expect(focus.hasPrimaryFocus, isTrue);
    }

    testWidgets('keys are inert while a text field elsewhere has the focus', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.outsideFocus.requestFocus();
      await tester.pump();
      await expectInert(tester, h);
      await expectArrowsMoveTheCaret(tester, h.outsideFocus, h.outsideField);
    }, variant: windowsAndLinux);

    testWidgets('keys are inert while a text field inside the tree has the '
        'focus', (tester) async {
      final h = await pumpKeyboard(tester);
      h.insideFocus.requestFocus();
      await tester.pump();
      expect(h.treeFocus.hasFocus, isTrue);
      expect(h.treeFocus.hasPrimaryFocus, isFalse);
      await expectInert(tester, h);
      await expectArrowsMoveTheCaret(tester, h.insideFocus, h.insideField);
    }, variant: windowsAndLinux);

    testWidgets('the keys work again once the tree has the focus back', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.insideFocus.requestFocus();
      await tester.pump();
      h.treeFocus.requestFocus();
      await tester.pump();
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.focusedId, beta);
    });

    testWidgets('autofocus gives the tree the focus', (tester) async {
      final h = await pumpKeyboard(tester, focusTree: false, autofocus: true);
      await tester.pump();
      expect(h.treeFocus.hasPrimaryFocus, isTrue);
    });

    testWidgets('without a focus node, the widget owns one', (tester) async {
      final controller = keyboardController();
      addTearDown(controller.dispose);
      final childKey = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: DirectoryTreeKeyboard<Object?>(
            controller: controller,
            autofocus: true,
            child: SizedBox(key: childKey),
          ),
        ),
      );
      await tester.pump();
      final node = Focus.of(childKey.currentContext!);
      expect(node.debugLabel, 'DirectoryTreeKeyboard');
      expect(node.hasPrimaryFocus, isTrue);
      controller.select(alpha);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(controller.focusedId, beta);
      // Unmounting disposes the owned node without errors.
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });

    testWidgets('a given focus node is used and never disposed', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      expect(Focus.of(h.childKey.currentContext!), same(h.treeFocus));
      await tester.pumpWidget(const SizedBox());
      // Still usable: a disposed node would assert here.
      h.treeFocus.addListener(_noop);
      h.treeFocus.removeListener(_noop);
    });

    testWidgets('a new focus node takes over', (tester) async {
      final h = await pumpKeyboard(tester);
      final other = FocusNode(debugLabel: 'other');
      addTearDown(other.dispose);
      Widget build(FocusNode? node) => buildKeyboardApp(
        controller: h.controller,
        treeFocus: node,
        outsideFocus: h.outsideFocus,
        insideFocus: h.insideFocus,
        outsideField: h.outsideField,
        insideField: h.insideField,
        childKey: h.childKey,
      );

      await tester.pumpWidget(build(other));
      other.requestFocus();
      await tester.pump();
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.focusedId, beta);

      // Back to an owned node.
      await tester.pumpWidget(build(null));
      Focus.of(h.childKey.currentContext!).requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.focusedId, empty);
      expect(other.hasFocus, isFalse);
    });
  });

  group('widget updates', () {
    testWidgets('a new controller takes effect at once', (tester) async {
      final h = await pumpKeyboard(tester);
      final next = keyboardController();
      addTearDown(next.dispose);
      await tester.pumpWidget(
        buildKeyboardApp(
          controller: next,
          treeFocus: h.treeFocus,
          outsideFocus: h.outsideFocus,
          insideFocus: h.insideFocus,
          outsideField: h.outsideField,
          insideField: h.insideField,
          childKey: h.childKey,
        ),
      );
      next.select(alpha);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(next.focusedId, beta);
      expect(h.controller.focusedId, isNull);
    });

    testWidgets('custom shortcuts replace the defaults', (tester) async {
      final h = await pumpKeyboard(
        tester,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.keyJ): MoveTreeFocusIntent(
            TreeFocusMove.next,
          ),
        },
      );
      h.controller.select(alpha);
      await press(tester, LogicalKeyboardKey.keyJ);
      expect(h.controller.focusedId, beta);
      // Down is not bound any more; the app's default traversal gets it.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(h.controller.focusedId, beta);
    });

    testWidgets('checkboxMode and onActivate changes apply to the next key', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      final activated = <TreeRow<Object?>>[];
      await tester.pumpWidget(
        buildKeyboardApp(
          controller: h.controller,
          treeFocus: h.treeFocus,
          outsideFocus: h.outsideFocus,
          insideFocus: h.insideFocus,
          outsideField: h.outsideField,
          insideField: h.insideField,
          childKey: h.childKey,
          checkboxMode: DirectoryTreeCheckboxMode.checks,
          onActivate: activated.add,
        ),
      );
      h.controller.select(apple);
      await press(tester, LogicalKeyboardKey.space);
      expect(h.controller.checkStateOf(apple), CheckState.checked);
      await press(tester, LogicalKeyboardKey.enter);
      expect([for (final row in activated) row.id], [apple]);
    });
  });

  testWidgets('debugFillProperties describes the configuration', (
    tester,
  ) async {
    final controller = keyboardController();
    addTearDown(controller.dispose);
    final builder = DiagnosticPropertiesBuilder();
    DirectoryTreeKeyboard<Object?>(
      controller: controller,
      autofocus: true,
      onActivate: (_) {},
      checkboxMode: DirectoryTreeCheckboxMode.checks,
      typeAhead: false,
      typeAheadTimeout: const Duration(milliseconds: 500),
      child: const SizedBox(),
    ).debugFillProperties(builder);
    final description = [
      for (final property in builder.properties)
        if (!property.isFiltered(DiagnosticLevel.info)) property.toString(),
    ];
    expect(description, contains('autofocus'));
    expect(description, contains('has onActivate'));
    expect(description, contains('checkboxMode: checks'));
    expect(description, contains('type-ahead off'));
    expect(description, contains('typeAheadTimeout: 0:00:00.500000'));

    expect(description.join('\n'), isNot(contains('shortcuts')));

    final custom = DiagnosticPropertiesBuilder();
    DirectoryTreeKeyboard<Object?>(
      controller: controller,
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyJ): MoveTreeFocusIntent(
          TreeFocusMove.next,
        ),
      },
      child: const SizedBox(),
    ).debugFillProperties(custom);
    final customDescription = [
      for (final property in custom.properties)
        if (!property.isFiltered(DiagnosticLevel.info)) property.toString(),
    ];
    // Only the controller and the custom shortcuts differ from the defaults.
    expect(customDescription, hasLength(2));
    expect(customDescription.first, startsWith('controller: '));
    expect(
      customDescription.last,
      startsWith('shortcuts: {{Key J}: MoveTreeFocusIntent'),
    );
  });

  test('the defaults the widget uses are those of DirectoryTreeShortcuts', () {
    expect(
      DirectoryTreeShortcuts.defaults(
        platform: TargetPlatform.android,
        textDirection: TextDirection.ltr,
      )[const SingleActivator(LogicalKeyboardKey.arrowRight)],
      const ExpandTreeNodeIntent(),
    );
  });
}

void _noop() {}

/// An override that counts its invocations and then runs the default
/// action it overrides.
final class _LoggingAction<T extends Intent> extends Action<T> {
  int invocations = 0;

  @override
  Object? invoke(T intent) {
    invocations++;
    return callingAction?.invoke(intent);
  }
}
