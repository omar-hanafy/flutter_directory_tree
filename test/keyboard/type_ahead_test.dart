import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keyboard_test_utils.dart';

/// r, alpha (directory with x.txt), a*b.txt, beta.txt.
DirectoryTree<Object?> asteriskTree() => DirectoryTree<Object?>.build(const [
  TreeEntry<Object?>.file('/r/alpha/x.txt'),
  TreeEntry<Object?>.file('/r/a*b.txt'),
  TreeEntry<Object?>.file('/r/beta.txt'),
]);

const aStarB = NodeId('/r/a*b.txt');
const betaTxt = NodeId('/r/beta.txt');

void main() {
  group('matching', () {
    testWidgets('one letter cycles through the rows that start with it', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      final visited = <NodeId?>[];
      for (var i = 0; i < 4; i++) {
        await typeText(tester, 'a');
        visited.add(h.controller.focusedId);
      }
      // After the last row that starts with "a" it wraps to the first one.
      expect(visited, [alpha, apple, avocado, alpha]);
      expect(h.selectedIds, [alpha]);
    });

    testWidgets('typing more of a name moves to it and then stays', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'av');
      expect(h.controller.focusedId, avocado);
      expect(h.selectedIds, [avocado]);
      await typeText(tester, 'oc');
      expect(h.controller.focusedId, avocado);
    });

    testWidgets('a longer search starts at the focused row and wraps', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      // "a" cycles from alpha to apple; "al" then searches from apple to
      // the end, wraps around, and finds alpha again.
      await typeText(tester, 'a');
      expect(h.controller.focusedId, apple);
      await typeText(tester, 'l');
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('case is ignored, also for repeated letters', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(banana);
      await typeText(tester, 'R');
      expect(h.controller.focusedId, readme);
      // "Rr" is one repeated letter, so it cycles on to the next row.
      await typeText(tester, 'r');
      expect(h.controller.focusedId, r);
    });

    testWidgets('a search without a match consumes the key and changes '
        'nothing', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      expect(await typeText(tester, 'z'), isTrue);
      expect(notifications.count, 0);
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('each key press that finds a new row notifies once', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      final notifications = Notifications(h.controller);
      addTearDown(notifications.dispose);
      await typeText(tester, 'a');
      expect(notifications.take(), 1);
      await typeText(tester, 'v');
      expect(notifications.take(), 1);
      // Still on avocado: nothing changes.
      await typeText(tester, 'o');
      expect(notifications.take(), 0);
      expect(h.viewport.shown.last, h.controller.focusedIndex);
    });

    testWidgets('with nothing focused the search starts at the first row', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      expect(h.controller.focusedId, isNull);
      await typeText(tester, 'r');
      expect(h.controller.focusedId, r);
      await typeText(tester, 'r');
      expect(h.controller.focusedId, readme);
    });

    testWidgets('compacted rows match their joined label', (tester) async {
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(
          tree: DirectoryTree<Object?>.build(const [
            TreeEntry<Object?>.file('/r/lib/src/utils/x.dart'),
            TreeEntry<Object?>.file('/r/lab.txt'),
            TreeEntry<Object?>.file('/r/library.txt'),
          ]),
          compactFolders: true,
        ),
      );
      h.controller.select(r);
      await typeText(tester, 'lib/s');
      expect(h.controller.focusedId, const NodeId('/r/lib/src/utils'));
      expect(h.controller.focusedRow!.label, 'lib/src/utils');
    });

    testWidgets('letters outside ASCII and emoji match', (tester) async {
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(
          tree: DirectoryTree<Object?>.build(const [
            TreeEntry<Object?>.file('/r/Ärger.txt'),
            TreeEntry<Object?>.file('/r/über.txt'),
            TreeEntry<Object?>.file('/r/\u{1F642} smile.txt'),
          ]),
        ),
      );
      h.controller.select(r);
      await press(tester, LogicalKeyboardKey.keyU, character: 'ü');
      expect(h.controller.focusedRow!.label, 'über.txt');
      await tester.pump(const Duration(seconds: 1));
      await press(tester, LogicalKeyboardKey.keyA, character: 'ä');
      expect(h.controller.focusedRow!.label, 'Ärger.txt');
      await tester.pump(const Duration(seconds: 1));
      await press(tester, LogicalKeyboardKey.keyS, character: '\u{1F642}');
      expect(h.controller.focusedRow!.label, '\u{1F642} smile.txt');
      // The same emoji again is one repeated character: it cycles (and
      // wraps back to the only row with it).
      await press(tester, LogicalKeyboardKey.keyS, character: '\u{1F642}');
      expect(h.controller.focusedRow!.label, '\u{1F642} smile.txt');
    });

    testWidgets('unselectable rows get the focus but not the selection', (
      tester,
    ) async {
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(selectable: (node) => node.isDirectory),
      );
      h.controller.select(r);
      await typeText(tester, 'a');
      expect(h.controller.focusedId, alpha);
      expect(h.selectedIds, [alpha]);
      await typeText(tester, 'a');
      expect(h.controller.focusedId, apple);
      expect(h.selectedIds, [alpha]);
    });

    testWidgets('key repeats add the character again', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      expect(h.controller.focusedId, alpha);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyA, character: 'a');
      expect(h.controller.focusedId, apple);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyA, character: 'a');
      expect(h.controller.focusedId, avocado);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    });
  });

  group('the search text', () {
    testWidgets('resets typeAheadTimeout after the latest character', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'a');
      expect(h.controller.focusedId, alpha);
      await tester.pump(const Duration(seconds: 1));
      // A new search for "v" finds nothing, where "av" would find avocado.
      await typeText(tester, 'v');
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('lasts until the timeout', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'a');
      await tester.pump(const Duration(milliseconds: 999));
      await typeText(tester, 'v');
      expect(h.controller.focusedId, avocado);
    });

    testWidgets('restarts the timeout with every character', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'm');
      await tester.pump(const Duration(milliseconds: 700));
      await typeText(tester, 'y');
      await tester.pump(const Duration(milliseconds: 700));
      // 1.4 s after "m", but only 0.7 s after "y": "my n" still matches.
      await typeText(tester, ' n');
      expect(h.controller.focusedId, myNotes);
    });

    testWidgets('follows a custom typeAheadTimeout', (tester) async {
      final h = await pumpKeyboard(
        tester,
        typeAheadTimeout: const Duration(milliseconds: 200),
      );
      h.controller.select(r);
      await typeText(tester, 'a');
      await tester.pump(const Duration(milliseconds: 199));
      await typeText(tester, 'v');
      expect(h.controller.focusedId, avocado);
      await tester.pump(const Duration(milliseconds: 200));
      await typeText(tester, 'a');
      // A new one-letter search cycles on from avocado.
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('resets when another key is pressed', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'b');
      expect(h.controller.focusedId, beta);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(h.controller.focusedId, alpha);
      // "a" alone cycles from alpha to apple; "ba" would have found banana.
      await typeText(tester, 'a');
      expect(h.controller.focusedId, apple);
    });

    testWidgets('survives Shift, so capital letters join it', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'my N');
      expect(h.controller.focusedId, myNotes);
    });

    testWidgets('resets when the tree loses the focus', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'b');
      expect(h.controller.focusedId, beta);
      h.outsideFocus.requestFocus();
      await tester.pump();
      h.treeFocus.requestFocus();
      await tester.pump();
      await typeText(tester, 'a');
      expect(h.controller.focusedId, apple);
    });

    testWidgets('resets when typeAhead is turned off and on', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'b');
      Widget build({required bool typeAhead}) => buildKeyboardApp(
        controller: h.controller,
        treeFocus: h.treeFocus,
        outsideFocus: h.outsideFocus,
        insideFocus: h.insideFocus,
        outsideField: h.outsideField,
        insideField: h.insideField,
        childKey: h.childKey,
        typeAhead: typeAhead,
      );
      await tester.pumpWidget(build(typeAhead: false));
      await tester.pumpWidget(build(typeAhead: true));
      await typeText(tester, 'a');
      expect(h.controller.focusedId, apple);
    });
  });

  group('Space', () {
    testWidgets('joins a search in progress instead of toggling', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'my');
      expect(h.controller.focusedId, myFile);
      expect(h.selectedIds, [myFile]);
      expect(await typeText(tester, ' '), isTrue);
      expect(h.selectedIds, [myFile]);
      await typeText(tester, 'n');
      expect(h.controller.focusedId, myNotes);
      expect(h.selectedIds, [myNotes]);
    });

    testWidgets('toggles the selection again once the search ended', (
      tester,
    ) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(r);
      await typeText(tester, 'my');
      await tester.pump(const Duration(seconds: 1));
      await typeText(tester, ' ');
      expect(h.controller.selection.isEmpty, isTrue);
    });
  });

  group('characters that stay out of the search', () {
    testWidgets('a character bound to a shortcut, such as *, never joins it', (
      tester,
    ) async {
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(tree: asteriskTree()),
      );
      h.controller.select(r);
      await typeText(tester, 'a');
      expect(h.controller.focusedId, alpha);
      await typeAsterisk(tester);
      // The shortcut ran...
      expect(h.controller.isExpanded(alpha), isTrue);
      // ...and ended the search: "b" alone finds beta.txt, where "a*b"
      // would have found a*b.txt.
      await typeText(tester, 'b');
      expect(h.controller.focusedId, betaTxt);
    });

    testWidgets('with shortcuts that do not bind *, it joins the search', (
      tester,
    ) async {
      final shortcuts = <ShortcutActivator, Intent>{
        ...DirectoryTreeShortcuts.defaults(
          platform: TargetPlatform.android,
          textDirection: TextDirection.ltr,
        ),
      }..remove(const CharacterActivator('*'));
      final h = await pumpKeyboard(
        tester,
        controller: keyboardController(tree: asteriskTree()),
        shortcuts: shortcuts,
      );
      h.controller.select(r);
      await typeText(tester, 'a');
      await typeAsterisk(tester);
      expect(h.controller.focusedId, aStarB);
      expect(h.controller.isExpanded(alpha), isFalse);
    });

    testWidgets('a bound character stays out also while its key repeats', (
      tester,
    ) async {
      var cleared = 0;
      final h = await pumpKeyboard(
        tester,
        shortcuts: const <ShortcutActivator, Intent>{
          CharacterActivator('x', includeRepeats: false):
              ClearTreeSelectionIntent(),
        },
        ancestorActions: <Type, Action<Intent>>{
          ClearTreeSelectionIntent: CallbackAction<ClearTreeSelectionIntent>(
            onInvoke: (_) => cleared++,
          ),
        },
      );
      h.controller.select(r);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyX, character: 'x');
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyX, character: 'x');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyX);
      expect(cleared, 1);
      // An "x" in the search would make "xa" match nothing.
      await typeText(tester, 'a');
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('Ctrl, Meta, and Alt keep characters out', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      expect(
        await press(tester, LogicalKeyboardKey.keyB, control: true),
        isFalse,
      );
      expect(await press(tester, LogicalKeyboardKey.keyB, meta: true), isFalse);
      expect(
        await press(tester, LogicalKeyboardKey.keyB, alt: true, character: 'b'),
        isFalse,
      );
      expect(h.controller.focusedId, alpha);
    });

    testWidgets('control and private-use characters stay out', (tester) async {
      final h = await pumpKeyboard(tester);
      h.controller.select(alpha);
      for (final character in ['\u0001', '\u007f', '\u0085', '']) {
        expect(
          await press(tester, LogicalKeyboardKey.keyB, character: character),
          isFalse,
        );
      }
      // None of them started a search: "a" alone cycles to apple.
      await typeText(tester, 'a');
      expect(h.controller.focusedId, apple);
    });

    testWidgets(
      'with typeAhead off, characters are left to the widgets above',
      (tester) async {
        final h = await pumpKeyboard(tester, typeAhead: false);
        h.controller.select(r);
        expect(await typeText(tester, 'a'), isFalse);
        expect(h.controller.focusedId, r);
        // Shortcuts still work.
        h.controller.select(beta);
        await typeAsterisk(tester);
        expect(h.controller.isExpanded(deep), isTrue);
      },
    );
  });
}
