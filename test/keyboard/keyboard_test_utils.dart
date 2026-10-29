import 'package:directory_tree/directory_tree.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/controller/directory_loading.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_controller.dart';
import 'package:flutter_directory_tree/src/controller/directory_tree_viewport.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
import 'package:flutter_directory_tree/src/widgets/directory_tree_row_details.dart';
import 'package:flutter_test/flutter_test.dart';

/// A viewport that reports a fixed page size and records [showRow] calls.
final class FakeViewport implements DirectoryTreeViewport {
  FakeViewport({this.pageRowCount = 3});

  @override
  int pageRowCount;

  final List<int> shown = <int>[];

  @override
  Future<void> showRow(
    int index, {
    Duration duration = Duration.zero,
    Curve curve = Curves.easeOutCubic,
    double? alignment,
  }) async {
    shown.add(index);
  }

  @override
  Rect? globalRowRect(int index) => null;
}

/// The test tree (directories first, case-insensitive natural order):
///
/// ```text
/// r
///   alpha
///     a1.txt
///     a2.txt
///   beta
///     deep
///       x.txt
///   empty
///   apple.txt
///   avocado.txt
///   banana.txt
///   my file.txt
///   my notes.md
///   README.md
/// ```
///
/// With only `r` expanded the rows are r (0), alpha (1), beta (2),
/// empty (3), apple.txt (4), avocado.txt (5), banana.txt (6),
/// my file.txt (7), my notes.md (8), README.md (9).
DirectoryTree<Object?> keyboardTree() => DirectoryTree<Object?>.build(const [
  TreeEntry<Object?>.file('/r/alpha/a1.txt'),
  TreeEntry<Object?>.file('/r/alpha/a2.txt'),
  TreeEntry<Object?>.file('/r/beta/deep/x.txt'),
  TreeEntry<Object?>.directory('/r/empty'),
  TreeEntry<Object?>.file('/r/apple.txt'),
  TreeEntry<Object?>.file('/r/avocado.txt'),
  TreeEntry<Object?>.file('/r/banana.txt'),
  TreeEntry<Object?>.file('/r/my file.txt'),
  TreeEntry<Object?>.file('/r/my notes.md'),
  TreeEntry<Object?>.file('/r/README.md'),
]);

const r = NodeId('/r');
const alpha = NodeId('/r/alpha');
const a1 = NodeId('/r/alpha/a1.txt');
const a2 = NodeId('/r/alpha/a2.txt');
const beta = NodeId('/r/beta');
const deep = NodeId('/r/beta/deep');
const empty = NodeId('/r/empty');
const apple = NodeId('/r/apple.txt');
const avocado = NodeId('/r/avocado.txt');
const banana = NodeId('/r/banana.txt');
const myFile = NodeId('/r/my file.txt');
const myNotes = NodeId('/r/my notes.md');
const readme = NodeId('/r/README.md');

/// A controller for [keyboardTree] (or [tree]) with `r` expanded.
DirectoryTreeController<Object?> keyboardController({
  DirectoryTree<Object?>? tree,
  SelectionState selection = const SelectionState.empty(
    mode: SelectionMode.multiple,
  ),
  bool Function(TreeNode<Object?> node)? selectable,
  bool compactFolders = false,
  DirectoryChildrenLoader<Object?>? loadChildren,
}) {
  final controller = DirectoryTreeController<Object?>(
    tree: tree ?? keyboardTree(),
    selection: selection,
    selectable: selectable,
    compactFolders: compactFolders,
    loadChildren: loadChildren,
  );
  controller.expand(controller.tree.roots.first);
  return controller;
}

/// Everything a keyboard test interacts with.
final class KeyboardHarness {
  KeyboardHarness({
    required this.controller,
    required this.viewport,
    required this.treeFocus,
    required this.outsideFocus,
    required this.insideFocus,
    required this.outsideField,
    required this.insideField,
    required this.childKey,
  });

  final DirectoryTreeController<Object?> controller;
  final FakeViewport viewport;

  /// The keyboard widget's focus node.
  final FocusNode treeFocus;

  /// A text field outside the keyboard widget.
  final FocusNode outsideFocus;
  final TextEditingController outsideField;

  /// A text field inside the keyboard widget's child.
  final FocusNode insideFocus;
  final TextEditingController insideField;

  /// The key of the keyboard widget's child.
  final GlobalKey childKey;

  /// The ids of the visible rows.
  List<NodeId> get rowIds => [for (final row in controller.rows) row.id];

  /// The selected ids in display order.
  List<NodeId> get selectedIds => [
    for (final node in controller.selectedNodes) node.id,
  ];
}

/// Pumps a [DirectoryTreeKeyboard] around a child that holds a text field,
/// next to another text field, inside a [MaterialApp] (so the app's default
/// shortcuts, such as Escape to dismiss, are in place), and gives the tree
/// the keyboard focus.
///
/// [ancestorActions], when given, are registered in an [Actions] widget
/// right above the keyboard widget. [onActivate] receives activated rows.
Future<KeyboardHarness> pumpKeyboard(
  WidgetTester tester, {
  DirectoryTreeController<Object?>? controller,
  Map<ShortcutActivator, Intent>? shortcuts,
  ValueChanged<TreeRow<Object?>>? onActivate,
  DirectoryTreeCheckboxMode checkboxMode = DirectoryTreeCheckboxMode.none,
  bool typeAhead = true,
  Duration typeAheadTimeout = const Duration(seconds: 1),
  TextDirection textDirection = TextDirection.ltr,
  Map<Type, Action<Intent>>? ancestorActions,
  bool focusTree = true,
  bool autofocus = false,
  int pageRowCount = 3,
}) async {
  final treeController = controller ?? keyboardController();
  addTearDown(treeController.dispose);
  final viewport = FakeViewport(pageRowCount: pageRowCount);
  treeController.attachViewport(viewport);
  final treeFocus = FocusNode(debugLabel: 'tree');
  final outsideFocus = FocusNode(debugLabel: 'outside');
  final insideFocus = FocusNode(debugLabel: 'inside');
  final outsideField = TextEditingController(text: 'outside');
  final insideField = TextEditingController(text: 'inside');
  addTearDown(() {
    treeFocus.dispose();
    outsideFocus.dispose();
    insideFocus.dispose();
    outsideField.dispose();
    insideField.dispose();
  });
  final childKey = GlobalKey(debugLabel: 'child');
  await tester.pumpWidget(
    buildKeyboardApp(
      controller: treeController,
      treeFocus: treeFocus,
      outsideFocus: outsideFocus,
      insideFocus: insideFocus,
      outsideField: outsideField,
      insideField: insideField,
      childKey: childKey,
      shortcuts: shortcuts,
      onActivate: onActivate,
      checkboxMode: checkboxMode,
      typeAhead: typeAhead,
      typeAheadTimeout: typeAheadTimeout,
      textDirection: textDirection,
      ancestorActions: ancestorActions,
      autofocus: autofocus,
    ),
  );
  if (focusTree) {
    treeFocus.requestFocus();
    await tester.pump();
  }
  return KeyboardHarness(
    controller: treeController,
    viewport: viewport,
    treeFocus: treeFocus,
    outsideFocus: outsideFocus,
    insideFocus: insideFocus,
    outsideField: outsideField,
    insideField: insideField,
    childKey: childKey,
  );
}

/// The app [pumpKeyboard] pumps; tests that rebuild with other arguments
/// pump it again with the harness's objects.
Widget buildKeyboardApp({
  required DirectoryTreeController<Object?> controller,
  required FocusNode? treeFocus,
  required FocusNode outsideFocus,
  required FocusNode insideFocus,
  required TextEditingController outsideField,
  required TextEditingController insideField,
  required GlobalKey childKey,
  Map<ShortcutActivator, Intent>? shortcuts,
  ValueChanged<TreeRow<Object?>>? onActivate,
  DirectoryTreeCheckboxMode checkboxMode = DirectoryTreeCheckboxMode.none,
  bool typeAhead = true,
  Duration typeAheadTimeout = const Duration(seconds: 1),
  TextDirection textDirection = TextDirection.ltr,
  Map<Type, Action<Intent>>? ancestorActions,
  bool autofocus = false,
}) {
  Widget keyboard = DirectoryTreeKeyboard<Object?>(
    controller: controller,
    focusNode: treeFocus,
    autofocus: autofocus,
    shortcuts: shortcuts,
    onActivate: onActivate,
    checkboxMode: checkboxMode,
    typeAhead: typeAhead,
    typeAheadTimeout: typeAheadTimeout,
    child: SizedBox(
      key: childKey,
      height: 200,
      child: TextField(focusNode: insideFocus, controller: insideField),
    ),
  );
  if (ancestorActions != null) {
    keyboard = Actions(actions: ancestorActions, child: keyboard);
  }
  return MaterialApp(
    home: Directionality(
      textDirection: textDirection,
      child: Material(
        child: Column(
          children: [
            TextField(focusNode: outsideFocus, controller: outsideField),
            keyboard,
          ],
        ),
      ),
    ),
  );
}

/// Presses [key] with the given modifiers held, then pumps a frame.
///
/// Returns whether the framework handled the key press.
Future<bool> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
  bool meta = false,
  bool alt = false,
  String? character,
}) async {
  final modifiers = <LogicalKeyboardKey>[
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (control) LogicalKeyboardKey.controlLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
    if (alt) LogicalKeyboardKey.altLeft,
  ];
  for (final modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  final handled = await tester.sendKeyEvent(
    key,
    character: character,
    platform: simulatorPlatformFor(key),
  );
  for (final modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pump();
  return handled;
}

/// The platform the key simulator should describe [key] with: `null` (the
/// platform under test) unless that platform's legacy key-code table lacks
/// the key, then `'web'`.
///
/// The simulator also sends each key as a legacy raw event, which asserts
/// for keys missing from the table (NumpadEnter on Windows, NumpadSubtract
/// on Linux). The [KeyEvent]s that focus handlers receive do not depend on
/// this platform, so describing such a key as a web key changes nothing for
/// the code under test.
String? simulatorPlatformFor(LogicalKeyboardKey key) {
  bool known(Map<int, LogicalKeyboardKey> table) =>
      table.values.any((known) => known.keyId == key.keyId);
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows when !known(kWindowsToLogicalKey) => 'web',
    TargetPlatform.linux when !known(kGlfwToLogicalKey) => 'web',
    _ => null,
  };
}

/// Types the `*` character the way a US keyboard does: Shift+8.
Future<bool> typeAsterisk(WidgetTester tester) =>
    press(tester, LogicalKeyboardKey.digit8, shift: true, character: '*');

/// Types [text] one character at a time (letters, digits, space, `.`, `/`,
/// `-`), holding Shift for capital letters, and pumps after each.
///
/// Returns whether the framework handled every key press.
Future<bool> typeText(WidgetTester tester, String text) async {
  var handled = true;
  for (final character in text.split('')) {
    final lower = character.toLowerCase();
    final key = switch (lower) {
      ' ' => LogicalKeyboardKey.space,
      '.' => LogicalKeyboardKey.period,
      '/' => LogicalKeyboardKey.slash,
      '-' => LogicalKeyboardKey.minus,
      _ => LogicalKeyboardKey.findKeyByKeyId(lower.codeUnitAt(0))!,
    };
    final shift = character != lower;
    // Not `handled &= await press(...)`: dart2wasm (Dart 3.13) emits
    // invalid Wasm for a compound assignment whose right side awaits.
    final pressed = await press(
      tester,
      key,
      shift: shift,
      character: character,
    );
    handled = handled && pressed;
  }
  return handled;
}

/// Counts the notifications [controller] sends while it is attached.
final class Notifications {
  Notifications(this.controller) {
    controller.addListener(_count);
  }

  final ChangeNotifier controller;
  int count = 0;

  void _count() => count++;

  /// The notifications since the previous call.
  int take() {
    final result = count;
    count = 0;
    return result;
  }

  void dispose() => controller.removeListener(_count);
}

/// Clears the keyboard cursor while the tree keeps the keyboard focus.
///
/// A tree that gains the focus without a focused row focuses one, so tests
/// of the "nothing focused" state clear it afterwards.
Future<void> clearRowFocus(WidgetTester tester, KeyboardHarness h) async {
  h.controller.focus(null);
  await tester.pump();
  expect(h.controller.focusedId, isNull);
  expect(h.treeFocus.hasPrimaryFocus, isTrue);
}
