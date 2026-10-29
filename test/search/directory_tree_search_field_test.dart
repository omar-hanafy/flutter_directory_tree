import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_test_utils.dart';

const Duration debounce = Duration(milliseconds: 120);

final Finder field = find.byType(TextField);

/// The value of the text field's controller.
TextEditingValue fieldValue(WidgetTester tester) =>
    tester.widget<TextField>(field).controller!.value;

/// The decoration the search field gave its text field.
InputDecoration fieldDecoration(WidgetTester tester) =>
    tester.widget<TextField>(field).decoration!;

TextEditingValue valueAtEnd(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

/// Key downs that reached an ancestor of the search field.
final List<LogicalKeyboardKey> ancestorKeys = <LogicalKeyboardKey>[];

Widget fieldHost({
  required DirectoryTreeController<Object?> controller,
  Duration debounce = debounce,
  FocusNode? focusNode,
  FocusNode? treeFocusNode,
  bool autofocus = false,
  String? hintText,
  InputDecoration? decoration,
  ThemeData? theme,
  Iterable<LocalizationsDelegate<dynamic>>? localizationsDelegates,
}) {
  return MaterialApp(
    theme: theme,
    localizationsDelegates: localizationsDelegates,
    home: Scaffold(
      body: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) ancestorKeys.add(event.logicalKey);
          return KeyEventResult.ignored;
        },
        child: Column(
          children: <Widget>[
            DirectoryTreeSearchField(
              controller: controller,
              focusNode: focusNode,
              treeFocusNode: treeFocusNode,
              autofocus: autofocus,
              hintText: hintText,
              decoration: decoration,
              debounce: debounce,
            ),
            if (treeFocusNode != null)
              Focus(
                focusNode: treeFocusNode,
                child: const SizedBox(width: 200, height: 200),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TestMaterialLocalizations extends DefaultMaterialLocalizations {
  const _TestMaterialLocalizations();

  @override
  String get searchFieldLabel => 'Suchen';

  @override
  String get clearButtonTooltip => 'Text löschen';
}

class _TestLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _TestLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      SynchronousFuture<MaterialLocalizations>(
        const _TestMaterialLocalizations(),
      );

  @override
  bool shouldReload(_TestLocalizationsDelegate old) => false;
}

void main() {
  late DirectoryTreeController<String> controller;
  late FocusNode fieldFocus;
  late FocusNode treeFocus;

  setUp(() {
    controller = DirectoryTreeController<String>(tree: sampleTree());
    fieldFocus = FocusNode(debugLabel: 'field');
    treeFocus = FocusNode(debugLabel: 'tree');
    ancestorKeys.clear();
  });

  tearDown(() {
    controller.dispose();
    fieldFocus.dispose();
    treeFocus.dispose();
  });

  group('typing', () {
    testWidgets('applies the text after the debounce, once per pause', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      final notifications = NotificationCounter(controller);

      await tester.enterText(field, 'ma');
      await tester.pump(const Duration(milliseconds: 100));
      expect(controller.query, '');

      // Every edit starts the wait again.
      await tester.enterText(field, 'main');
      await tester.pump(const Duration(milliseconds: 119));
      expect(controller.query, '');

      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.query, 'main');
      expect(notifications.count, 1);
      expect(labelsOf(controller.rows), <String>[
        'repo',
        'lib',
        'main.dart',
        'test',
        'main_test.dart',
      ]);
    });

    testWidgets('moving the caret does not restart the wait', (tester) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');
      await tester.pump(const Duration(milliseconds: 100));

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'main',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump(const Duration(milliseconds: 20));

      expect(controller.query, 'main');
    });

    testWidgets('a zero debounce applies every edit immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, debounce: Duration.zero),
      );
      await tester.showKeyboard(field);

      // Synchronously, with no timer and no frame in between.
      tester.testTextInput.updateEditingValue(valueAtEnd('main'));
      expect(controller.query, 'main');
      tester.testTextInput.updateEditingValue(valueAtEnd('mai'));
      expect(controller.query, 'mai');
    });

    testWidgets('a negative debounce applies every edit immediately', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          debounce: const Duration(milliseconds: -5),
        ),
      );
      await tester.showKeyboard(field);

      tester.testTextInput.updateEditingValue(valueAtEnd('lib'));
      expect(controller.query, 'lib');
    });

    testWidgets('keeps a trailing space in the text and the query', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main ');
      await tester.pump(debounce);

      expect(controller.query, 'main ');
      expect(fieldValue(tester), valueAtEnd('main '));
    });

    testWidgets('typing back to the current query drops the waiting text', (
      tester,
    ) async {
      controller.query = 'main';
      await tester.pumpWidget(fieldHost(controller: controller));
      final notifications = NotificationCounter(controller);

      await tester.enterText(field, 'mai');
      await tester.enterText(field, 'main');
      await tester.pump(const Duration(seconds: 1));

      expect(controller.query, 'main');
      expect(notifications.count, 0);
    });

    testWidgets('submitting applies waiting text at once', (tester) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, focusNode: fieldFocus),
      );
      await tester.enterText(field, 'main');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      expect(controller.query, 'main');

      // Then the field gives up focus, as any text field does.
      await tester.pump();
      expect(fieldFocus.hasFocus, isFalse);
    });

    testWidgets('a new debounce applies to the text that is waiting', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, debounce: const Duration(seconds: 5)),
      );
      await tester.enterText(field, 'main');
      await tester.pump(const Duration(seconds: 1));

      await tester.pumpWidget(
        fieldHost(controller: controller, debounce: Duration.zero),
      );
      expect(controller.query, '');
      await tester.pump(Duration.zero);
      expect(controller.query, 'main');
    });
  });

  group('changes from the controller', () {
    testWidgets('starts with the current query', (tester) async {
      controller.query = 'test';
      await tester.pumpWidget(fieldHost(controller: controller));

      expect(fieldValue(tester), valueAtEnd('test'));
    });

    testWidgets('a new query replaces the text, caret at the end', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'mai');
      await tester.pump(debounce);

      controller.query = 'README';
      await tester.pump();

      expect(fieldValue(tester), valueAtEnd('README'));
      expect(find.text('README'), findsOneWidget);
    });

    testWidgets('a new query drops text still waiting for the debounce', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'mai');

      controller.query = 'README';
      await tester.pump(const Duration(seconds: 1));

      expect(controller.query, 'README');
      expect(fieldValue(tester), valueAtEnd('README'));
    });

    testWidgets('the debounced query keeps the caret and the selection', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');
      const selected = TextEditingValue(
        text: 'main',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      tester.testTextInput.updateEditingValue(selected);

      await tester.pump(debounce);

      expect(controller.query, 'main');
      expect(fieldValue(tester), selected);
    });

    testWidgets('a query equal to the text keeps the caret and the selection', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');
      const selected = TextEditingValue(
        text: 'main',
        selection: TextSelection(baseOffset: 3, extentOffset: 1),
      );
      tester.testTextInput.updateEditingValue(selected);
      final notifications = NotificationCounter(controller);

      controller.query = 'main';
      await tester.pump(const Duration(seconds: 1));

      expect(fieldValue(tester), selected);
      // Only the outside change notified: the waiting text was dropped.
      expect(notifications.count, 1);
    });

    testWidgets('other notifications leave the text alone', (tester) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');
      await tester.pump(debounce);
      const selected = TextEditingValue(
        text: 'main',
        selection: TextSelection.collapsed(offset: 2),
      );
      tester.testTextInput.updateEditingValue(selected);

      controller
        ..expandAll()
        ..focus(repo)
        ..select(lib)
        ..caseSensitiveQuery = true;
      await tester.pump();

      expect(fieldValue(tester), selected);
      expect(controller.query, 'main');
    });

    testWidgets('notifications that do not change the query rebuild nothing', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.pumpAndSettle();
      final rebuilds = RebuildCounter.install();
      addTearDown(rebuilds.uninstall);

      controller
        ..expandAll()
        ..focus(lib)
        ..select(mainDart)
        ..selectAll()
        ..compactFolders = true;
      await tester.pump();

      expect(rebuilds.count, 0);
    });

    testWidgets('follows a new controller and drops waiting text', (
      tester,
    ) async {
      final other = DirectoryTreeController<String>(
        tree: sampleTree(),
        query: 'test',
      );
      addTearDown(other.dispose);
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');

      await tester.pumpWidget(fieldHost(controller: other));
      expect(fieldValue(tester), valueAtEnd('test'));

      await tester.pump(const Duration(seconds: 1));
      expect(controller.query, '');
      expect(other.query, 'test');

      // Only the new controller is followed.
      controller.query = 'lib';
      await tester.pump();
      expect(fieldValue(tester).text, 'test');
      other.query = 'README';
      await tester.pump();
      expect(fieldValue(tester), valueAtEnd('README'));

      // Typing goes to the new controller.
      await tester.enterText(field, 'a.dart');
      await tester.pump(debounce);
      expect(other.query, 'a.dart');
      expect(controller.query, 'lib');

      // Once the field is gone, neither controller calls back into it.
      await tester.pumpWidget(const SizedBox());
      other.query = 'test';
      controller.query = 'README';
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dispose drops waiting text and stops listening', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      expect(controller.query, '');

      // A listener left behind would write to its disposed text controller.
      controller.query = 'lib';
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('clear button', () {
    testWidgets('shows only while the field has text', (tester) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      expect(find.byIcon(Icons.clear), findsNothing);

      await tester.enterText(field, 'm');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);
      expect(find.byTooltip('Clear text'), findsOneWidget);

      await tester.enterText(field, '');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsNothing);
    });

    testWidgets('clears the text and the query at once and focuses the '
        'field', (tester) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, focusNode: fieldFocus),
      );
      await tester.enterText(field, 'main');
      await tester.pump(debounce);
      fieldFocus.unfocus();
      await tester.pump();
      expect(fieldFocus.hasFocus, isFalse);

      await tester.tap(find.byIcon(Icons.clear));
      expect(controller.query, '');
      expect(fieldValue(tester).text, '');

      await tester.pump();
      expect(find.byIcon(Icons.clear), findsNothing);
      expect(fieldFocus.hasFocus, isTrue);
    });

    testWidgets('drops text still waiting for the debounce', (tester) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'mai');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump(const Duration(seconds: 1));

      expect(controller.query, '');
      expect(fieldValue(tester).text, '');
    });

    testWidgets('is a labeled button for assistive technologies', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'main');
      await tester.pump();

      expect(find.bySemanticsLabel('Clear text'), findsOneWidget);
      expect(
        tester.getSemantics(find.byIcon(Icons.clear)),
        isSemantics(
          label: 'Clear text',
          tooltip: '',
          isButton: true,
          hasTapAction: true,
        ),
      );
      // No node anywhere carries the tooltip, so the name is read once.
      expect(
        find.semantics.byPredicate((node) => node.tooltip.isNotEmpty),
        findsNothing,
      );
      semantics.dispose();
    });
  });

  group('Escape', () {
    testWidgets('clears a non-empty query and the text at once', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, focusNode: fieldFocus),
      );
      await tester.enterText(field, 'main');
      await tester.pump(debounce);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(controller.query, '');
      expect(fieldValue(tester).text, '');
      expect(ancestorKeys, isEmpty);
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);
    }, variant: TargetPlatformVariant.all());

    testWidgets('clears text still waiting for the debounce', (tester) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, 'mai');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(seconds: 1));

      expect(controller.query, '');
      expect(fieldValue(tester).text, '');
      expect(ancestorKeys, isEmpty);
    });

    testWidgets('clears a query whose deletion is still waiting', (
      tester,
    ) async {
      controller.query = 'main';
      await tester.pumpWidget(fieldHost(controller: controller));
      await tester.enterText(field, '');
      expect(controller.query, 'main');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(controller.query, '');
      expect(ancestorKeys, isEmpty);
    });

    testWidgets('restores the expansion from before the search and keeps the '
        'focused match revealed', (tester) async {
      controller.expand(repo);
      expect(labelsOf(controller.rows), <String>[
        'repo',
        'lib',
        'test',
        'README.md',
      ]);
      await tester.pumpWidget(
        fieldHost(controller: controller, treeFocusNode: treeFocus),
      );
      await tester.enterText(field, 'main');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.focusedId, mainDart);
      expect(controller.isExpanded(testDir), isTrue);

      await tester.showKeyboard(field);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);

      expect(controller.query, '');
      expect(controller.focusedId, mainDart);
      expect(labelsOf(controller.rows), <String>[
        'repo',
        'lib',
        'src',
        'main.dart',
        'test',
        'README.md',
      ]);
      // The search opened test too; only the focused match stays revealed.
      expect(controller.isExpanded(testDir), isFalse);
    });

    testWidgets(
      'is left to the ancestors when the field and the query are empty',
      (tester) async {
        await tester.pumpWidget(fieldHost(controller: controller));
        await tester.showKeyboard(field);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);

        expect(ancestorKeys, <LogicalKeyboardKey>[LogicalKeyboardKey.escape]);
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('clears first, then closes an enclosing dialog', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog(
                  child: DirectoryTreeSearchField(
                    controller: controller,
                    autofocus: true,
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(field, 'main');
      await tester.pump(debounce);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(controller.query, '');
      expect(find.byType(Dialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('Arrow Down', () {
    testWidgets(
      'focuses the first match and moves keyboard focus to the tree',
      (tester) async {
        final viewport = RecordingViewport();
        controller
          ..attachViewport(viewport)
          ..query = 'main';
        await tester.pumpWidget(
          fieldHost(controller: controller, treeFocusNode: treeFocus),
        );
        await tester.showKeyboard(field);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();

        // repo and lib only lead to the matches.
        expect(controller.focusedId, mainDart);
        expect(controller.focusedIndex, 2);
        expect(viewport.shown, <int>[2]);
        expect(treeFocus.hasFocus, isTrue);
        expect(ancestorKeys, isEmpty);
      },
      variant: TargetPlatformVariant.all(),
    );

    testWidgets('applies waiting text before it looks for the match', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, treeFocusNode: treeFocus),
      );
      await tester.enterText(field, 'main');
      expect(controller.query, '');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(controller.query, 'main');
      expect(controller.focusedId, mainDart);
      expect(treeFocus.hasFocus, isTrue);
    });

    testWidgets('focuses the first row when nothing is filtered', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, treeFocusNode: treeFocus),
      );
      await tester.showKeyboard(field);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(controller.focusedId, repo);
      expect(treeFocus.hasFocus, isTrue);
    });

    testWidgets('focuses the first row when no row matches itself', (
      tester,
    ) async {
      controller
        ..revealMatches = false
        ..query = 'a.dart';
      expect(labelsOf(controller.rows), <String>['repo']);
      expect(controller.rows.single.isMatch, isFalse);
      await tester.pumpWidget(
        fieldHost(controller: controller, treeFocusNode: treeFocus),
      );
      await tester.showKeyboard(field);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(controller.focusedId, repo);
      expect(treeFocus.hasFocus, isTrue);
    });

    testWidgets('is left to the text field when there are no rows', (
      tester,
    ) async {
      controller.query = 'nothing matches this';
      expect(controller.rows, isEmpty);
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          focusNode: fieldFocus,
          treeFocusNode: treeFocus,
        ),
      );
      await tester.showKeyboard(field);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(controller.focusedId, isNull);
      expect(treeFocus.hasFocus, isFalse);
      expect(fieldFocus.hasFocus, isTrue);
      expect(ancestorKeys, <LogicalKeyboardKey>[LogicalKeyboardKey.arrowDown]);
    });

    testWidgets('without a tree focus node, keeps keyboard focus', (
      tester,
    ) async {
      controller.query = 'main';
      await tester.pumpWidget(
        fieldHost(controller: controller, focusNode: fieldFocus),
      );
      await tester.showKeyboard(field);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(controller.focusedId, mainDart);
      expect(fieldFocus.hasFocus, isTrue);
      expect(ancestorKeys, isEmpty);
    });

    testWidgets('with Shift keeps its text editing meaning', (tester) async {
      controller.query = 'main';
      await tester.pumpWidget(
        fieldHost(controller: controller, treeFocusNode: treeFocus),
      );
      await tester.showKeyboard(field);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(controller.focusedId, isNull);
      expect(treeFocus.hasFocus, isFalse);
      expect(ancestorKeys, contains(LogicalKeyboardKey.arrowDown));
    });
  });

  testWidgets(
    'leaves Escape and Arrow Down to an input method that is composing',
    (tester) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, treeFocusNode: treeFocus),
      );
      await tester.showKeyboard(field);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'ma',
          selection: TextSelection.collapsed(offset: 2),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(fieldValue(tester).text, 'ma');
      expect(controller.focusedId, isNull);
      expect(treeFocus.hasFocus, isFalse);
      expect(ancestorKeys, <LogicalKeyboardKey>[
        LogicalKeyboardKey.escape,
        LogicalKeyboardKey.arrowDown,
      ]);
    },
    variant: TargetPlatformVariant.all(),
  );

  group('hint and decoration', () {
    testWidgets('the hint defaults to the localized search label', (
      tester,
    ) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      expect(fieldDecoration(tester).hintText, 'Search');
      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('the hint and the clear tooltip follow the app language', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            _TestLocalizationsDelegate(),
          ],
        ),
      );
      expect(find.text('Suchen'), findsOneWidget);

      await tester.enterText(field, 'main');
      await tester.pump();
      expect(find.byTooltip('Text löschen'), findsOneWidget);
    });

    testWidgets('hintText replaces the default hint', (tester) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, hintText: 'Filter files'),
      );
      expect(find.text('Filter files'), findsOneWidget);
      expect(find.text('Search'), findsNothing);
    });

    testWidgets('a hint of the decoration takes precedence', (tester) async {
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          hintText: 'Ignored',
          decoration: const InputDecoration(hintText: 'Mine'),
        ),
      );
      expect(fieldDecoration(tester).hintText, 'Mine');

      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          hintText: 'Ignored',
          decoration: const InputDecoration(hint: Text('A hint widget')),
        ),
      );
      expect(fieldDecoration(tester).hintText, isNull);
      expect(find.text('A hint widget'), findsOneWidget);
      expect(find.text('Ignored'), findsNothing);
    });

    testWidgets('the default decoration has a search icon', (tester) async {
      await tester.pumpWidget(fieldHost(controller: controller));
      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(fieldDecoration(tester).isDense, isTrue);
    });

    testWidgets('a given decoration is used as is, plus hint and clear '
        'button', (tester) async {
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Files'),
        ),
      );
      expect(find.byIcon(Icons.search), findsNothing);
      expect(fieldDecoration(tester).labelText, 'Files');
      expect(fieldDecoration(tester).hintText, 'Search');

      await tester.enterText(field, 'main');
      await tester.pump();
      expect(find.byIcon(Icons.clear), findsOneWidget);
    });

    testWidgets('a suffix icon of the decoration replaces the clear button', (
      tester,
    ) async {
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          decoration: const InputDecoration(suffixIcon: Icon(Icons.tune)),
        ),
      );
      await tester.enterText(field, 'main');
      await tester.pump();

      expect(find.byIcon(Icons.tune), findsOneWidget);
      expect(find.byIcon(Icons.clear), findsNothing);
    });
  });

  group('focus', () {
    testWidgets('uses the given focus node', (tester) async {
      await tester.pumpWidget(
        fieldHost(controller: controller, focusNode: fieldFocus),
      );
      expect(fieldFocus.hasFocus, isFalse);

      await tester.showKeyboard(field);
      expect(fieldFocus.hasFocus, isTrue);
    });

    testWidgets('autofocus focuses the field', (tester) async {
      await tester.pumpWidget(
        fieldHost(
          controller: controller,
          focusNode: fieldFocus,
          autofocus: true,
        ),
      );
      await tester.pump();
      expect(fieldFocus.hasFocus, isTrue);
    });
  });

  testWidgets('works without a Material ancestor', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            child: DirectoryTreeSearchField(controller: controller),
          ),
        ),
      ),
    );
    await tester.enterText(field, 'main');
    await tester.pump(debounce);

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.clear), findsOneWidget);
    expect(controller.query, 'main');
  });

  test('describes its properties', () {
    final description = DirectoryTreeSearchField(
      controller: controller,
      autofocus: true,
      hintText: 'Filter',
      debounce: Duration.zero,
    ).toDiagnosticsNode().getProperties();
    final names = <String?>[for (final property in description) property.name];

    expect(
      names,
      containsAll(<String>['controller', 'autofocus', 'hintText', 'debounce']),
    );
  });
}
