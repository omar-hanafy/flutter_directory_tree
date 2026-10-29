import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_directory_tree/src/controller/tree_focus_move.dart';
import 'package:flutter_directory_tree/src/keyboard/directory_tree_shortcuts.dart';
import 'package:flutter_directory_tree/src/keyboard/tree_intents.dart';
import 'package:flutter_test/flutter_test.dart';

// The expected bindings, written out independently of the implementation.

const _move = MoveTreeFocusIntent.new;

final Map<ShortcutActivator, Intent> _everywhere = <ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.arrowUp): _move(
    TreeFocusMove.previous,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowDown): _move(
    TreeFocusMove.next,
  ),
  const SingleActivator(LogicalKeyboardKey.home): _move(TreeFocusMove.first),
  const SingleActivator(LogicalKeyboardKey.end): _move(TreeFocusMove.last),
  const SingleActivator(LogicalKeyboardKey.pageUp): _move(TreeFocusMove.pageUp),
  const SingleActivator(LogicalKeyboardKey.pageDown): _move(
    TreeFocusMove.pageDown,
  ),
  for (final (key, move) in _moves)
    SingleActivator(key, shift: true): _move(
      move,
      selection: TreeSelectionUpdate.extend,
    ),
  const SingleActivator(LogicalKeyboardKey.numpadAdd):
      const ExpandTreeNodeIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadSubtract):
      const CollapseTreeNodeIntent(),
  const CharacterActivator('*'): const ExpandTreeSubtreeIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadMultiply):
      const ExpandTreeSubtreeIntent(),
  const SingleActivator(LogicalKeyboardKey.enter):
      const ActivateTreeNodeIntent(),
  const SingleActivator(LogicalKeyboardKey.numpadEnter):
      const ActivateTreeNodeIntent(),
  const SingleActivator(LogicalKeyboardKey.space):
      const ToggleTreeSelectionIntent(),
  const SingleActivator(LogicalKeyboardKey.space, control: true):
      const ToggleTreeSelectionIntent(),
  const SingleActivator(LogicalKeyboardKey.escape):
      const ClearTreeSelectionIntent(),
  const SingleActivator(LogicalKeyboardKey.f10, shift: true):
      const OpenTreeContextMenuIntent(),
  const SingleActivator(LogicalKeyboardKey.contextMenu):
      const OpenTreeContextMenuIntent(),
};

const _moves = <(LogicalKeyboardKey, TreeFocusMove)>[
  (LogicalKeyboardKey.arrowUp, TreeFocusMove.previous),
  (LogicalKeyboardKey.arrowDown, TreeFocusMove.next),
  (LogicalKeyboardKey.home, TreeFocusMove.first),
  (LogicalKeyboardKey.end, TreeFocusMove.last),
  (LogicalKeyboardKey.pageUp, TreeFocusMove.pageUp),
  (LogicalKeyboardKey.pageDown, TreeFocusMove.pageDown),
];

const Map<ShortcutActivator, Intent> _leftToRight = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowRight): ExpandTreeNodeIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft): CollapseTreeNodeIntent(),
};

const Map<ShortcutActivator, Intent> _rightToLeft = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.arrowRight): CollapseTreeNodeIntent(),
  SingleActivator(LogicalKeyboardKey.arrowLeft): ExpandTreeNodeIntent(),
};

const Map<ShortcutActivator, Intent> _appleOnly = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      SelectAllTreeNodesIntent(),
  SingleActivator(LogicalKeyboardKey.arrowDown, meta: true):
      ActivateTreeNodeIntent(),
  SingleActivator(LogicalKeyboardKey.arrowUp, meta: true): MoveTreeFocusIntent(
    TreeFocusMove.parent,
  ),
};

final Map<ShortcutActivator, Intent> _othersOnly = <ShortcutActivator, Intent>{
  const SingleActivator(LogicalKeyboardKey.keyA, control: true):
      const SelectAllTreeNodesIntent(),
  for (final (key, move) in _moves)
    SingleActivator(key, control: true): _move(
      move,
      selection: TreeSelectionUpdate.keep,
    ),
};

bool _isApple(TargetPlatform platform) =>
    platform == TargetPlatform.macOS || platform == TargetPlatform.iOS;

void main() {
  for (final platform in TargetPlatform.values) {
    for (final direction in TextDirection.values) {
      test('${platform.name}, ${direction.name}: exactly the documented '
          'bindings', () {
        final expected = <ShortcutActivator, Intent>{
          ..._everywhere,
          ...direction == TextDirection.rtl ? _rightToLeft : _leftToRight,
          ...(_isApple(platform) ? _appleOnly : _othersOnly),
        };
        final actual = DirectoryTreeShortcuts.defaults(
          platform: platform,
          textDirection: direction,
        );
        // Activators compare by identity, so the expected keys are built
        // with the same constructor arguments and looked up one by one.
        expect(actual, hasLength(expected.length));
        for (final MapEntry(key: activator, value: intent)
            in expected.entries) {
          final match = actual.entries.where(
            (entry) => _sameActivator(entry.key, activator),
          );
          expect(
            match,
            hasLength(1),
            reason: '${activator.debugDescribeKeys()} is bound once',
          );
          expect(
            match.single.value,
            intent,
            reason: '${activator.debugDescribeKeys()} -> $intent',
          );
        }
      });
    }
  }

  test('each platform family and direction shares one constant map', () {
    Map<ShortcutActivator, Intent> of(TargetPlatform platform) =>
        DirectoryTreeShortcuts.defaults(
          platform: platform,
          textDirection: TextDirection.ltr,
        );
    expect(of(TargetPlatform.windows), same(of(TargetPlatform.linux)));
    expect(of(TargetPlatform.windows), same(of(TargetPlatform.android)));
    expect(of(TargetPlatform.windows), same(of(TargetPlatform.fuchsia)));
    expect(of(TargetPlatform.macOS), same(of(TargetPlatform.iOS)));
    expect(of(TargetPlatform.macOS), isNot(same(of(TargetPlatform.windows))));
  });

  test('the returned map is unmodifiable', () {
    final map = DirectoryTreeShortcuts.defaults(
      platform: TargetPlatform.linux,
      textDirection: TextDirection.ltr,
    );
    expect(
      () => map[const SingleActivator(LogicalKeyboardKey.f2)] =
          const ActivateTreeNodeIntent(),
      throwsUnsupportedError,
    );
  });

  test('a copy with a spread can be changed', () {
    final map = <ShortcutActivator, Intent>{
      ...DirectoryTreeShortcuts.defaults(
        platform: TargetPlatform.linux,
        textDirection: TextDirection.ltr,
      ),
      const SingleActivator(LogicalKeyboardKey.f2):
          const ActivateTreeNodeIntent(),
    };
    expect(
      map[const SingleActivator(LogicalKeyboardKey.f2)],
      const ActivateTreeNodeIntent(),
    );
  });

  test('the right-to-left maps swap only the arrows', () {
    final ltr = DirectoryTreeShortcuts.defaults(
      platform: TargetPlatform.windows,
      textDirection: TextDirection.ltr,
    );
    final rtl = DirectoryTreeShortcuts.defaults(
      platform: TargetPlatform.windows,
      textDirection: TextDirection.rtl,
    );
    const right = SingleActivator(LogicalKeyboardKey.arrowRight);
    const left = SingleActivator(LogicalKeyboardKey.arrowLeft);
    expect(rtl[right], ltr[left]);
    expect(rtl[left], ltr[right]);
    final others = {...ltr.keys}
      ..remove(right)
      ..remove(left);
    for (final activator in others) {
      expect(rtl[activator], ltr[activator]);
    }
  });
}

/// Whether two activators describe the same key combination.
bool _sameActivator(ShortcutActivator a, ShortcutActivator b) {
  if (a is SingleActivator && b is SingleActivator) {
    return a.trigger == b.trigger &&
        a.control == b.control &&
        a.shift == b.shift &&
        a.alt == b.alt &&
        a.meta == b.meta &&
        a.numLock == b.numLock &&
        a.includeRepeats == b.includeRepeats;
  }
  if (a is CharacterActivator && b is CharacterActivator) {
    return a.character == b.character &&
        a.control == b.control &&
        a.alt == b.alt &&
        a.meta == b.meta &&
        a.includeRepeats == b.includeRepeats;
  }
  return false;
}
