// Compile-time check that the keyboard library's public names do not clash
// with Flutter's own libraries (cupertino and material also export
// widgets): an ambiguous name fails to compile here.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_keyboard.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the keyboard names resolve next to material, cupertino, services, '
      'and widgets', () {
    final types = <Type>[
      MoveTreeFocusIntent,
      ExpandTreeNodeIntent,
      CollapseTreeNodeIntent,
      ExpandTreeSubtreeIntent,
      ActivateTreeNodeIntent,
      ToggleTreeSelectionIntent,
      SelectAllTreeNodesIntent,
      ClearTreeSelectionIntent,
      OpenTreeContextMenuIntent,
      DirectoryTreeShortcuts,
      DirectoryTreeKeyboard,
      // One name from each Flutter library, so none of the imports is
      // unused.
      CupertinoButton,
      MaterialApp,
      LogicalKeyboardKey,
      Shortcuts,
    ];
    expect(types.toSet(), hasLength(types.length));
  });
}
