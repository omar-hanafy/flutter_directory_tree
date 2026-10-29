/// Every factual claim the AI plugin skills make, asserted against the API.
///
/// `tooling/ai/flutter-directory-tree/skills/` tells coding assistants how
/// to use this package. Those files are excluded from the pub archive, so
/// nothing else in the build notices them going stale, and a wrong skill is
/// worse than a missing one: it makes an assistant confidently write broken
/// code. This file holds them to the API in three ways:
///
/// * Every 2.x Dart block of a skill is copied here verbatim and compiled,
///   and the tests below run or pump it. Blocks that start with
///   `// flutter_directory_tree 1.x` show the old API and are skipped.
/// * Every API name a skill mentions in inline code (and every
///   CamelCase name in a skill description) must be a key of [_names], whose
///   value is code that uses that name, so the compiler proves it exists.
///   Removed 1.x names are listed in [_v1Names] instead, and none of them may
///   be declared in the 2.x sources.
/// * The behavior the skills describe is asserted by the groups below.
///
/// AGENTS.md requires skill facts to match the source. When a claim here
/// changes, update the skill in the same change.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/io.dart';
import 'package:flutter_test/flutter_test.dart';

const String _skillsDir = 'tooling/ai/flutter-directory-tree/skills';
const String _useSkill = '$_skillsDir/use-flutter-directory-tree';
const String _migrateSkill =
    '$_skillsDir/migrate-flutter-directory-tree-v1-to-v2';

/// The first line of every 1.x block in the skills.
const String _v1Marker = '// flutter_directory_tree 1.x';

void main() {
  final skillFiles = {
    for (final file
        in Directory(_skillsDir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.md')))
      file.path: file.readAsStringSync(),
  };
  final blocks = [
    for (final text in skillFiles.values)
      for (final match in RegExp(r'```dart\n([\s\S]*?)```').allMatches(text))
        match.group(1)!,
  ];
  final currentBlocks = blocks
      .where((block) => !block.startsWith(_v1Marker))
      .toList();

  group('the skills as text', () {
    test('both skills exist', () {
      expect(File('$_useSkill/SKILL.md').existsSync(), isTrue);
      expect(File('$_migrateSkill/SKILL.md').existsSync(), isTrue);
    });

    test('every 2.x Dart block of the skills is compiled by this file', () {
      final source = _normalize(
        File('test/agent_skill_claims_test.dart').readAsStringSync(),
      );
      expect(currentBlocks, isNotEmpty);
      expect(
        blocks.length,
        greaterThan(currentBlocks.length),
        reason: 'The migration skill shows 1.x code marked "$_v1Marker".',
      );
      final missing = [
        for (final block in currentBlocks)
          if (!source.contains(_normalize(block))) block,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'Copy these skill blocks into test/agent_skill_claims_test.dart, '
            'or start them with "$_v1Marker" if they show the old API:\n'
            '${missing.join('\n---\n')}',
      );
    });

    test('every API name in the skills exists', () {
      final unknown = <String>{};
      final v1Advice = <String>{};
      skillFiles.forEach((path, text) {
        final file = path.split('/skills/').last;
        for (final (:name, :line) in _mentionedNames(text)) {
          if (_names.containsKey(name) || _notApi.contains(name)) continue;
          if (!_v1Names.contains(name)) {
            unknown.add('$name ($file)');
          } else if (path.startsWith(_useSkill) && !_namesOldApi(line, name)) {
            v1Advice.add('$name ($file): $line');
          }
        }
      });
      expect(
        unknown,
        isEmpty,
        reason:
            'These names are not in _names (code that uses them), _v1Names, '
            'or _notApi. Fix the skill, or add a use of the real API.',
      );
      expect(
        v1Advice,
        isEmpty,
        reason:
            'The use skill may name a removed 1.x API only in the "Wrong '
            'guess" column of its table or on a line that says "1.x".',
      );
    });

    test('every Dart block of the skills is complete', () {
      for (final block in blocks) {
        expect(_isBalanced(block), isTrue, reason: block);
      }
    });

    test('every _names entry uses the name it lists', () {
      final source = File('test/agent_skill_claims_test.dart')
          .readAsStringSync();
      final start = source.indexOf(
        '\nfinal Map<String, void Function()> _names = {',
      );
      final region = source.substring(start, source.indexOf('\n};', start));
      final keys = RegExp(
        r"^  '(\w+)':",
        multiLine: true,
      ).allMatches(region).toList();
      expect(keys.length, _names.length);
      for (var i = 0; i < keys.length; i++) {
        final name = keys[i].group(1)!;
        final body = region.substring(
          keys[i].end,
          i + 1 < keys.length ? keys[i + 1].start : region.length,
        );
        expect(
          RegExp('(?<![A-Za-z0-9_])$name(?![A-Za-z0-9_])').hasMatch(body),
          isTrue,
          reason: 'The _names entry "$name" must use $name.',
        );
      }
    });

    test('no removed 1.x name is declared in the 2.x sources', () {
      final roots = [Directory('lib'), _packageRoot('directory_tree')];
      final code = StringBuffer();
      for (final root in roots) {
        for (final file
            in root
                .listSync(recursive: true)
                .whereType<File>()
                .where((file) => file.path.endsWith('.dart'))) {
          code.writeln(_stripComments(file.readAsStringSync()));
        }
      }
      final text = code.toString();
      final declared = [
        for (final name in _v1Names.where(
          (name) => name.startsWith(RegExp('[A-Z]')),
        ))
          if (RegExp(
            '(class|enum|typedef|mixin|extension type(?: const)?|extension) '
            '$name(?![A-Za-z0-9_])',
          ).hasMatch(text))
            name,
      ];
      expect(declared, isEmpty, reason: 'Still in the 2.x API: $declared');
      expect(_v1Names.intersection(_names.keys.toSet()), isEmpty);
    });

    test('the skill descriptions fit every host', () {
      for (final MapEntry(key: path, value: text) in skillFiles.entries) {
        if (!path.endsWith('SKILL.md')) continue;
        final description = RegExp(
          r'^description: (.*)$',
          multiLine: true,
        ).firstMatch(text)!.group(1)!;
        expect(description.length, lessThanOrEqualTo(1024), reason: path);
        expect(description.contains(': '), isFalse, reason: path);
        expect(
          text.contains(String.fromCharCode(0x2014)),
          isFalse,
          reason: path,
        );
      }
    });
  });

  group('use-flutter-directory-tree', () {
    test('commands notify once, and a command that changes nothing does '
        'not notify', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      final lib = controller.tree.idOf('/repo/lib')!;

      controller.expand(lib);
      expect(notifications, 1);
      controller.expand(lib);
      expect(notifications, 1);
      controller.setChecked(lib, checked: true);
      expect(notifications, 2);
    });

    test('unknown ids are ignored, and queries answer null, false, -1, or '
        'an empty result', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      const unknown = NodeId('/elsewhere');

      controller
        ..expand(unknown)
        ..select(unknown)
        ..toggleChecked(unknown)
        ..focus(unknown);
      expect(notifications, 0);
      expect(controller.tree.nodeAt('/repo/LIB'), isNull);
      final wrongCase = controller.tree.idOf('/repo/LIB')!; // parses: an id
      expect(controller.tree.contains(wrongCase), isFalse);
      expect(controller.tree.contains(unknown), isFalse);
      expect(controller.isExpanded(unknown), isFalse);
      expect(controller.rows.indexOfNode(unknown), -1);
      expect(controller.reveal(unknown), isFalse);
      expect(controller.revealPath('/nope'), isNull);
      expect(controller.checkStateOf(unknown), CheckState.unchecked);
    });

    test('state values are immutable: a dropped result changes nothing', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final repo = controller.tree.roots.single;
      final lib = controller.tree.idOf('/repo/lib')!;
      controller.select(lib);

      final cleared = controller.selection.clear();
      expect(cleared.isEmpty, isTrue);
      expect(controller.isSelected(lib), isTrue);
      final collapsed = controller.expansion.collapse(repo);
      expect(collapsed.isExpanded(repo), isFalse);
      expect(controller.isExpanded(repo), isTrue);

      controller.expansion = controller.expansion.expandAll([lib]);
      expect(controller.isExpanded(lib), isTrue);
      controller.clearSelection();
      expect(controller.selection.isEmpty, isTrue);
    });

    test('select focuses the row; focus: false leaves the focus', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      final readme = controller.tree.idOf('/repo/README.md')!;

      controller.select(lib);
      expect(controller.focusedId, lib);
      controller.select(readme, focus: false);
      expect(controller.focusedId, lib);
      expect(controller.selectedNodes.single.name, 'README.md');

      controller.toggleSelected(lib);
      controller.extendSelection(readme);
      expect(controller.selection.anchor, lib);
      expect(controller.selectedNodes.map((node) => node.name), [
        'lib',
        'test',
        'README.md',
      ]);
    });

    test('the selection defaults: the controller is multiple, a bare '
        'SelectionState.empty() is single', () {
      final controller = DirectoryTreeController<Object?>();
      addTearDown(controller.dispose);
      expect(controller.selectionMode, SelectionMode.multiple);
      expect(controller.checks.mode, SelectionMode.multiple);
      expect(const SelectionState.empty().mode, SelectionMode.single);
    });

    test('clearing the search keeps the folders that lead to the focused '
        'row open, and they join the requested expansion', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      final src = controller.tree.idOf('/repo/lib/src')!;
      final test = controller.tree.idOf('/repo/test')!;
      final match = controller.tree.idOf('/repo/lib/src/tree.dart')!;

      controller.query = 'tree';
      expect(controller.isExpanded(test), isTrue); // tree_test.dart matched
      controller.select(match);
      controller.query = '';
      expect(controller.focusedId, match);
      expect(controller.rows.indexOfNode(match), isNot(-1));
      expect(controller.isExpanded(test), isFalse);
      expect(controller.expansion.isExpanded(lib), isTrue);
      expect(controller.expansion.isExpanded(src), isTrue);
      expect(controller.expansion.isExpanded(test), isFalse);
      expect(
        _normalize(File('$_useSkill/SKILL.md').readAsStringSync()),
        contains('except the ones leading to the focused row'),
      );
    });

    test('the performance lines match the controller and core docs', () {
      final skill = File('$_useSkill/SKILL.md').readAsStringSync();
      final controller = File(
        'lib/src/controller/directory_tree_controller.dart',
      ).readAsStringSync();
      final rows = File(
        '${_packageRoot('directory_tree').path}/src/view/tree_rows.dart',
      ).readAsStringSync();
      for (final (member, cost) in [
        ('select', 'O(log rows)'),
        ('toggleSelected', 'O(selection size + log rows)'),
        ('extendSelection', 'O(range size + log rows)'),
      ]) {
        expect(_normalize(skill), contains('`$member` '), reason: member);
        expect(_normalize(skill), contains(cost), reason: member);
        expect(
          _docOf(controller, 'void $member('),
          contains(cost),
          reason: 'the dartdoc of $member',
        );
      }
      expect(_normalize(skill), contains('plus copying the row list'));
      expect(
        _normalize(skill),
        contains('the expansion state, which grows with its exceptions'),
      );
      final expansion = File(
        '${_packageRoot('directory_tree').path}/src/view/expansion_state.dart',
      ).readAsStringSync();
      for (final member in [
        'ExpansionState expand(',
        'ExpansionState collapse(',
      ]) {
        expect(
          _docOf(expansion, member),
          contains('copies the exceptions, in O(number of exceptions)'),
          reason: member,
        );
      }
      for (final member in [
        'TreeRows<T> expandNode(',
        'TreeRows<T> collapseNode(',
      ]) {
        expect(
          _docOf(rows, member),
          contains('plus copying the row list and the expansion states'),
          reason: member,
        );
      }
    });

    testWidgets('composedExplorer: the menu host above the keyboard opens '
        'from Shift+F10 and from a secondary tap', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      expect(
        currentBlocks.where((b) => b.contains('Widget composedExplorer(')),
        hasLength(1),
        reason: 'The use skill shows this composition.',
      );
      await tester.pumpWidget(_app(composedExplorer(controller)));
      expect(find.text('Open editors'), findsOneWidget);

      await tester.tap(find.text('test'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(find.text('Expand all below'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Expand all below'), findsNothing);

      await tester.tap(find.text('README.md'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Expand all below'), findsOneWidget);
    });

    testWidgets('DraggableExplorer: a touch long press without a drag opens '
        'the menu through the key', (tester) async {
      expect(
        currentBlocks.where((b) => b.contains('class DraggableExplorer ')),
        hasLength(1),
        reason: 'The use skill shows the drag and drop stack.',
      );
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(_app(DraggableExplorer(controller: controller)));

      await tester.longPress(find.text('README.md'));
      await tester.pumpAndSettle();
      expect(find.text('Expand all below'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Expand all below'), findsNothing);

      await tester.tap(find.text('test'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Expand all below'), findsOneWidget);
    });

    testWidgets('maybeOf from the drag and drop scope above the host finds '
        'nothing, so the touch menu never opens', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => DirectoryTreeDragAndDropScope<Object?>(
              controller: controller,
              dragAndDrop: DirectoryTreeDragAndDrop(onDrop: (details) {}),
              onLongPressWithoutDrag: (row, globalPosition) =>
                  DirectoryTreeContextMenu.maybeOf<Object?>(context)
                      ?.open(row: row, globalPosition: globalPosition),
              child: DirectoryTreeContextMenu<Object?>(
                controller: controller,
                builder: (context, details) => [
                  MenuItemButton(onPressed: () {}, child: const Text('Rename')),
                ],
                child: DirectoryTreeKeyboard(
                  controller: controller,
                  child: CustomScrollView(
                    slivers: [
                      SliverDirectoryTree(
                        controller: controller,
                        rowDecorator:
                            DirectoryTreeDragAndDropScope.decorateRow<Object?>,
                        secondaryTapOnLongPress: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.longPress(find.text('README.md'));
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsNothing);
    });

    testWidgets('a menu host inside the keyboard widget opens only from '
        'secondary taps, as the skill warns', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          DirectoryTreeKeyboard(
            controller: controller,
            child: DirectoryTreeContextMenu<Object?>(
              controller: controller,
              builder: (context, details) => [
                MenuItemButton(onPressed: () {}, child: const Text('Rename')),
              ],
              child: Builder(
                builder: (context) => CustomScrollView(
                  slivers: [
                    SliverDirectoryTree(
                      controller: controller,
                      onRowSecondaryTap: (row, globalPosition) =>
                          DirectoryTreeContextMenu.maybeOf<Object?>(context)
                              ?.open(row: row, globalPosition: globalPosition),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('test'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsNothing);

      await tester.tap(find.text('README.md'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsOneWidget);
    });

    test('a search changes the effective expansion, not the requested one, '
        'and clearing it closes what it opened', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      final before = controller.expansion;

      controller.query = 'tree';
      expect(controller.isFiltering, isTrue);
      expect(controller.isExpanded(lib), isTrue);
      expect(controller.rows.expansion.isExpanded(lib), isTrue);
      expect(controller.expansion.isExpanded(lib), isFalse);
      final saved = controller.expansion.toJson();
      expect(jsonDecode(jsonEncode(saved)), saved);

      controller.query = '';
      expect(controller.isExpanded(lib), isFalse);
      expect(controller.expansion, before);
      expect(ExpansionState.fromJson(saved), controller.expansion);
    });

    test('expandAll opens every folder and starts no loads; collapseAll '
        'keeps the top-level rows', () async {
      var loads = 0;
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths([
          '/repo/lib/main.dart',
          '/repo/empty/',
          '/repo/README.md',
        ]),
        loadChildren: (directory) async {
          loads++;
          return const [];
        },
      );
      addTearDown(controller.dispose);

      controller.expandAll();
      await pumpEventQueue();
      expect(controller.rows.length, controller.tree.length);
      expect(loads, 0);
      controller.collapseAll();
      expect(controller.rows.map((row) => row.label), ['repo']);
    });

    test('checks are tri-state and separate from the selection', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final repo = controller.tree.roots.single;
      final lib = controller.tree.idOf('/repo/lib')!;

      controller.setChecked(lib, checked: true);
      expect(controller.checkStateOf(lib), CheckState.checked);
      expect(controller.checkStateOf(repo), CheckState.partial);
      expect(controller.checkedLeaves.map((node) => node.name), [
        'tree.dart',
        'main.dart',
      ]);
      expect(controller.checkedRoots.map((node) => node.name), ['lib']);
      expect(controller.selection.isEmpty, isTrue);

      controller.checkAll();
      expect(controller.checkedRoots.map((node) => node.name), ['repo']);
      controller.uncheckAll();
      expect(controller.checks.isEmpty, isTrue);
    });

    test('a failed load calls onLoadError, completes without an error, and '
        'opening the folder again retries', () async {
      var fail = true;
      final errors = <NodeId>[];
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(['/bucket/']),
        loadChildren: (directory) async {
          if (fail) throw StateError('offline');
          return [TreeEntry.file('${directory.path}/notes.txt')];
        },
        onLoadError: (directory, error, stackTrace) => errors.add(directory),
      );
      addTearDown(controller.dispose);
      final bucket = controller.tree.roots.single;

      expect(controller.loadStatusOf(bucket), DirectoryLoadStatus.notLoaded);
      controller.expand(bucket);
      expect(controller.loadStatusOf(bucket), DirectoryLoadStatus.loading);
      await controller.loadChildren(bucket);
      expect(controller.loadStatusOf(bucket), DirectoryLoadStatus.failed);
      expect(controller.loadErrorOf(bucket), isA<StateError>());
      expect(errors, [bucket]);

      fail = false;
      controller
        ..collapse(bucket)
        ..expand(bucket);
      await controller.loadChildren(bucket);
      expect(controller.loadStatusOf(bucket), DirectoryLoadStatus.loaded);
      expect(controller.rows.map((row) => row.label), ['bucket', 'notes.txt']);
    });

    test('reloadChildren keeps the rows while it loads, keeps an open '
        'subfolder of a one-level listing and lists it again, and keeps the '
        'contents when it fails', () async {
      var listings = 0;
      var failRoot = false;
      final relistA = Completer<void>();
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(['/root/']),
        // One level per listing; the second listing of a waits for relistA
        // and adds c.txt.
        loadChildren: (directory) async {
          switch (directory.path.toString()) {
            case '/root':
              if (failRoot) throw StateError('offline');
              return [TreeEntry.directory('/root/a')];
            case '/root/a':
              listings++;
              if (listings > 1) await relistA.future;
              return [
                TreeEntry.file('/root/a/b.txt'),
                if (listings > 1) TreeEntry.file('/root/a/c.txt'),
              ];
          }
          return const [];
        },
      );
      addTearDown(controller.dispose);
      List<String> labels() => [for (final row in controller.rows) row.label];
      final root = controller.tree.roots.single;
      controller.expand(root);
      await controller.loadChildren(root);
      final a = controller.tree.idOf('/root/a')!;
      controller.expand(a);
      await controller.loadChildren(a);
      final b = controller.tree.idOf('/root/a/b.txt')!;
      controller.select(b);
      expect(labels(), ['root', 'a', 'b.txt']);

      final reload = controller.reloadChildren(root);
      expect(labels(), ['root', 'a', 'b.txt']);
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.loading);
      await reload;
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
      expect(labels(), ['root', 'a', 'b.txt']); // a listed empty, kept
      expect(controller.isExpanded(a), isTrue);
      expect(controller.loadStatusOf(a), DirectoryLoadStatus.loading);
      relistA.complete();
      await controller.loadChildren(a);
      expect(labels(), ['root', 'a', 'b.txt', 'c.txt']);
      expect(controller.isSelected(b), isTrue);
      expect(controller.focusedId, b);

      failRoot = true;
      await controller.reloadChildren(root);
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.failed);
      expect(labels(), ['root', 'a', 'b.txt', 'c.txt']);
      failRoot = false;
      controller
        ..collapse(root)
        ..expand(root);
      await controller.loadChildren(root);
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
      final skill = _normalize(File('$_useSkill/SKILL.md').readAsStringSync());
      expect(
        skill,
        contains(
          'the folder keeps its rows, and the loads below it keep running',
        ),
      );
      expect(skill, contains('A failed reload changes nothing below it'));
    });

    test('a reload restarts after updateTree, and a failed reload leaves '
        'the loads below it running', () async {
      final pending = <String, List<Completer<List<TreeEntry<Object?>>>>>{};
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(['/root/']),
        loadChildren: (directory) {
          final completer = Completer<List<TreeEntry<Object?>>>();
          (pending[directory.path.toString()] ??= []).add(completer);
          return completer.future;
        },
      );
      addTearDown(controller.dispose);
      List<String> labels() => [for (final row in controller.rows) row.label];
      final root = controller.tree.roots.single;
      controller.expand(root);
      await pumpEventQueue();
      pending['/root']!.last.complete([TreeEntry.directory('/root/a')]);
      await pumpEventQueue();
      expect(labels(), ['root', 'a']);

      // An updateTree during a reload of an open folder starts it again,
      // and the first reload's future completes with the restarted one.
      var reloaded = false;
      unawaited(controller.reloadChildren(root).then((_) => reloaded = true));
      await pumpEventQueue();
      expect(pending['/root'], hasLength(2));
      controller.updateTree((builder) => builder.addFile('/root/x.txt'));
      await pumpEventQueue();
      expect(pending['/root'], hasLength(3));
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.loading);
      // The discarded listing still answers after the restart: its result
      // is ignored, and it neither completes nor clears the newer load.
      pending['/root']![1].complete([TreeEntry.file('/root/stale.txt')]);
      await pumpEventQueue();
      expect(reloaded, isFalse);
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.loading);
      expect(controller.tree.nodeAt('/root/stale.txt'), isNull);
      pending['/root']!.last.complete([
        TreeEntry.directory('/root/a'),
        TreeEntry.file('/root/y.txt'),
      ]);
      await pumpEventQueue();
      expect(reloaded, isTrue);
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
      expect(labels(), ['root', 'a', 'y.txt']);

      // A failed reload leaves the load running below it alone.
      final a = controller.tree.idOf('/root/a')!;
      controller.expand(a);
      await pumpEventQueue();
      unawaited(controller.reloadChildren(root));
      await pumpEventQueue();
      pending['/root']!.last.completeError(StateError('offline'));
      await pumpEventQueue();
      expect(controller.loadStatusOf(root), DirectoryLoadStatus.failed);
      expect(controller.loadStatusOf(a), DirectoryLoadStatus.loading);
      pending['/root/a']!.last.complete([TreeEntry.file('/root/a/b.txt')]);
      await pumpEventQueue();
      expect(controller.loadStatusOf(a), DirectoryLoadStatus.loaded);
      expect(labels(), ['root', 'a', 'b.txt', 'y.txt']);
      final skill = _normalize(File('$_useSkill/SKILL.md').readAsStringSync());
      expect(
        skill,
        contains(
          'After a new tree, a refresh that was still running starts again '
          'at once when its folder is open',
        ),
      );
      expect(skill, contains('a failed one waits for the next expand'));
      expect(
        _normalize(
          File('$_useSkill/references/api-quick-reference.md')
              .readAsStringSync(),
        ),
        allOf(
          contains(
            'completes with the next load of the same folder that starts '
            'before the discarded loader returns',
          ),
          contains(
            'must not let the earlier call clear or answer the newer one',
          ),
        ),
      );
    });

    test(
      'after a new tree, a failed refresh waits for the next expand',
      () async {
        var calls = 0;
        var fail = false;
        final controller = DirectoryTreeController<Object?>(
          tree: DirectoryTree.fromPaths(['/root/']),
          loadChildren: (directory) async {
            calls++;
            if (fail) throw StateError('offline');
            return [TreeEntry.file('/root/a.txt')];
          },
        );
        addTearDown(controller.dispose);
        final root = controller.tree.roots.single;
        controller.expand(root);
        await controller.loadChildren(root);
        fail = true;
        await controller.reloadChildren(root);
        expect(controller.loadStatusOf(root), DirectoryLoadStatus.failed);
        expect(calls, 2);

        fail = false;
        controller.updateTree((builder) => builder.addFile('/root/b.txt'));
        await pumpEventQueue();
        expect(
          calls,
          2,
          reason: 'a failed refresh does not start again at once',
        );
        controller.expand(root);
        await controller.loadChildren(root);
        expect(calls, 3);
        expect(controller.loadStatusOf(root), DirectoryLoadStatus.loaded);
      },
    );

    test('while filtering, expand loads a folder without a row only when '
        'the filter would show it', () async {
      final loaded = <String>[];
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(['/r/apple/', '/r/box/', '/r/x.txt']),
        query: 'apple',
        revealMatches: false, // r stays collapsed: its folders have no rows
        loadChildren: (directory) async {
          loaded.add(directory.name);
          return const [];
        },
      );
      addTearDown(controller.dispose);
      final apple = controller.tree.idOf('/r/apple')!;
      final box = controller.tree.idOf('/r/box')!;
      expect(controller.rows.indexOfNode(apple), -1);
      controller
        ..expand(apple)
        ..expand(box);
      await pumpEventQueue();
      expect(loaded, ['apple']);
      final reference = _normalize(
        File('$_useSkill/references/api-quick-reference.md').readAsStringSync(),
      );
      expect(reference, contains('a match inside a collapsed folder loads'));
    });

    test('a folder that stops continuing a compacted chain takes the state '
        'of its deepest folder', () {
      for (final open in [true, false]) {
        final tree = DirectoryTree.fromPaths(['/r/lib/src/a.dart', '/r/x.txt']);
        final lib = tree.idOf('/r/lib')!;
        final src = tree.idOf('/r/lib/src')!;
        final controller = DirectoryTreeController<Object?>(
          tree: tree,
          // lib's own state is the opposite of the row's (src's).
          expansion: ExpansionState.withExpanded([
            tree.roots.single,
            if (open) src else lib,
          ]),
          compactFolders: true,
        );
        addTearDown(controller.dispose);
        expect(controller.rows.rowOf(lib)!.label, 'lib/src');
        controller.updateTree((builder) => builder.addFile('/r/lib/b.dart'));
        expect(controller.isExpanded(lib), open, reason: 'open: $open');
        expect(controller.rows.rowOf(lib)!.label, 'lib');
      }
      final reference = _normalize(
        File('$_useSkill/references/api-quick-reference.md').readAsStringSync(),
      );
      expect(
        reference,
        contains('takes the state of the chain\'s deepest folder'),
      );
    });

    test('during a search, a folder that leaves a compacted chain stays '
        'collapsed when the user collapsed its row', () {
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(['/r/lib/src/a.dart', '/r/x.txt']),
        expansion: const ExpansionState.expanded(),
        compactFolders: true,
        query: 'a.dart',
      );
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/r/lib')!;
      expect(controller.rows.rowOf(lib)!.label, 'lib/src');
      final src = controller.rows.rowOf(lib)!.id; // the row's id: src
      controller.collapse(lib); // the user closes the row that held a match
      expect(controller.isExpanded(src), isFalse);
      expect(controller.isExpanded(lib), isTrue); // lib's own state differs

      controller.updateTree((builder) => builder.addFile('/r/lib/b.dart'));
      expect(controller.rows.rowOf(lib)!.label, 'lib');
      expect(controller.isExpanded(lib), isFalse);
      final reference = _normalize(
        File('$_useSkill/references/api-quick-reference.md').readAsStringSync(),
      );
      expect(
        reference,
        contains('a row that held a match and that the user collapsed stays'),
      );
    });

    testWidgets('a compacted row shows the load of a folder above its node', (
      tester,
    ) async {
      final pending = <String, Completer<List<TreeEntry<Object?>>>>{};
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths(['/r/lib/src/a.dart', '/r/README.md']),
        expansion: const ExpansionState.expanded(),
        compactFolders: true,
        loadChildren: (directory) =>
            (pending[directory.path.toString()] =
                    Completer<List<TreeEntry<Object?>>>())
                .future,
      );
      addTearDown(controller.dispose);
      final statuses = <String, DirectoryLoadStatus>{};
      await tester.pumpWidget(
        _app(
          DirectoryTreeView(
            controller: controller,
            rowBuilder: (context, details) {
              statuses[details.row.label] = details.loadStatus;
              return DirectoryTreeRow(details: details);
            },
          ),
        ),
      );
      final lib = controller.tree.idOf('/r/lib')!;
      expect(controller.rows.rowOf(lib)!.label, 'lib/src');
      unawaited(controller.reloadChildren(lib));
      await tester.pump();
      expect(controller.loadStatusOf(lib), DirectoryLoadStatus.loading);
      expect(statuses['lib/src'], DirectoryLoadStatus.loading);
      pending['/r/lib']!.completeError(StateError('offline'));
      await tester.pump();
      expect(statuses['lib/src'], DirectoryLoadStatus.failed);
      expect(
        _normalize(File('$_useSkill/SKILL.md').readAsStringSync()),
        contains('A compacted row shows the load status of every folder in it'),
      );
    });

    test('lastRowsChange: previous is set while listeners run and null '
        'after a new tree', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final changes = <TreeRowsChange>[];
      TreeRows<Object?>? previousInListener;
      controller.addListener(() {
        changes.add(controller.lastRowsChange);
        previousInListener = controller.lastRowsChange.previous;
      });
      final lib = controller.tree.idOf('/repo/lib')!;

      controller.expand(lib);
      expect(changes.single.isReset, isFalse);
      expect(changes.single.index, 2);
      expect(changes.single.inserted, 2);
      expect(changes.single.removed, 0);

      controller.tree = DirectoryTree.fromPaths(['/repo/a.txt']);
      expect(previousInListener, isNotNull);
      expect(controller.lastRowsChange.isReset, isTrue);
      expect(controller.lastRowsChange.previous, isNull);
    });

    test('a new tree keeps the state by id and moves the focus to the '
        'nearest surviving ancestor', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final lib = controller.tree.idOf('/repo/lib')!;
      controller.expand(lib);
      final main = controller.tree.idOf('/repo/lib/main.dart')!;
      controller
        ..select(main)
        ..toggleSelected(lib, focus: false);
      expect(controller.focusedId, main);

      controller.updateTree((builder) => builder.remove('/repo/lib/main.dart'));
      expect(controller.focusedId, lib);
      expect(controller.isExpanded(lib), isTrue);
      expect(controller.selection.selected, {lib});
    });

    test('the default roots are the outermost folders that hold entries', () {
      List<String> roots(TreeOptions options) => [
        for (final node in DirectoryTree.fromPaths([
          '/repo/lib/a.dart',
          '/repo/docs/',
        ], options: options).rootNodes)
          node.name,
      ];

      expect(roots(const TreeOptions()), ['docs', 'lib']);
      expect(roots(const TreeOptions(roots: TreeRoots.commonAncestor())), [
        'repo',
      ]);
      expect(roots(const TreeOptions(roots: TreeRoots.fixed(['/repo']))), [
        'repo',
      ]);
    });

    test('the search syntax table', () {
      final tree = DirectoryTree.fromPaths([
        '/r/lib/a.dart',
        '/r/lib/src/b.dart',
        '/r/pkg.dart/',
        '/r/MAIN.md',
        '/r/my notes.txt',
        '/r/my_notes.txt',
        '/r/test/',
        '/r/a.dart.bak',
      ]);
      List<String> matching(String query, {bool caseSensitive = false}) {
        final parsed = TreeQuery.parse(query, caseSensitive: caseSensitive);
        return [
          for (final node in tree.nodes)
            if (parsed.matches(node)) node.path.toString(),
        ];
      }

      expect(matching('main'), ['/r/MAIN.md']);
      expect(matching('main', caseSensitive: true), isEmpty);
      expect(matching('"my notes"'), ['/r/my notes.txt']);
      expect(matching('*.dart'), [
        '/r/lib/src/b.dart',
        '/r/lib/a.dart',
        '/r/pkg.dart', // a glob matches directory names too
      ]);
      expect(matching('ext:dart'), ['/r/lib/src/b.dart', '/r/lib/a.dart']);
      expect(matching('ext:dart,md'), [
        '/r/lib/src/b.dart',
        '/r/lib/a.dart',
        '/r/MAIN.md',
      ]);
      expect(matching('type:dir'), [
        '/r',
        '/r/lib',
        '/r/lib/src',
        '/r/pkg.dart',
        '/r/test',
      ]);
      expect(matching('path:lib/src'), ['/r/lib/src', '/r/lib/src/b.dart']);
      expect(matching('lib/'), ['/r/lib/src', '/r/lib/a.dart']);
      expect(matching('test'), ['/r/test']);
      expect(matching('!test'), isNot(contains('/r/test')));
      expect(() => TreeQuery.parse('"unclosed ext: !'), returnsNormally);
      final filter = TreeFilter.where<Object?>((node) => node.name == 'test');
      expect(filter.matches(tree.nodeAt('/r/test')!), isTrue);
    });

    test('the default keys of each platform', () {
      Intent? intent(
        Map<ShortcutActivator, Intent> map,
        LogicalKeyboardKey key, {
        bool control = false,
        bool meta = false,
        bool shift = false,
      }) {
        for (final MapEntry(key: activator, value: intent) in map.entries) {
          if (activator is SingleActivator &&
              activator.trigger == key &&
              activator.control == control &&
              activator.meta == meta &&
              activator.shift == shift &&
              !activator.alt) {
            return intent;
          }
        }
        return null;
      }

      Map<ShortcutActivator, Intent> keys(
        TargetPlatform platform, [
        TextDirection direction = TextDirection.ltr,
      ]) => DirectoryTreeShortcuts.defaults(
        platform: platform,
        textDirection: direction,
      );

      final mac = keys(TargetPlatform.macOS);
      final windows = keys(TargetPlatform.windows);
      const a = LogicalKeyboardKey.keyA;
      expect(intent(mac, a, meta: true), isA<SelectAllTreeNodesIntent>());
      expect(intent(mac, a, control: true), isNull);
      expect(
        intent(windows, a, control: true),
        isA<SelectAllTreeNodesIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.arrowDown, control: true),
        const MoveTreeFocusIntent(
          TreeFocusMove.next,
          selection: TreeSelectionUpdate.keep,
        ),
      );
      expect(intent(mac, LogicalKeyboardKey.arrowDown, control: true), isNull);
      expect(
        intent(mac, LogicalKeyboardKey.arrowUp, meta: true),
        const MoveTreeFocusIntent(TreeFocusMove.parent),
      );
      expect(
        intent(mac, LogicalKeyboardKey.arrowDown, meta: true),
        isA<ActivateTreeNodeIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.arrowDown, shift: true),
        const MoveTreeFocusIntent(
          TreeFocusMove.next,
          selection: TreeSelectionUpdate.extend,
        ),
      );
      expect(
        intent(windows, LogicalKeyboardKey.arrowRight),
        isA<ExpandTreeNodeIntent>(),
      );
      expect(
        intent(
          keys(TargetPlatform.windows, TextDirection.rtl),
          LogicalKeyboardKey.arrowRight,
        ),
        isA<CollapseTreeNodeIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.enter),
        isA<ActivateTreeNodeIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.space),
        isA<ToggleTreeSelectionIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.escape),
        isA<ClearTreeSelectionIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.f10, shift: true),
        isA<OpenTreeContextMenuIntent>(),
      );
      expect(
        intent(windows, LogicalKeyboardKey.numpadMultiply),
        isA<ExpandTreeSubtreeIntent>(),
      );
      expect(keys(TargetPlatform.iOS), same(mac));
      expect(keys(TargetPlatform.android), same(windows));
    });

    test('the default row height follows density and tap target size', () {
      double extent(TargetPlatform platform, {VisualDensity? density}) =>
          DirectoryTreeThemeData.fallback(
            ThemeData(platform: platform, visualDensity: density),
          ).rowExtent!;

      expect(extent(TargetPlatform.android), 48);
      expect(extent(TargetPlatform.iOS), 48);
      expect(extent(TargetPlatform.macOS), 28);
      expect(extent(TargetPlatform.windows), 28);
      expect(extent(TargetPlatform.linux, density: VisualDensity.standard), 36);
    });

    testWidgets('rows grow with the text scale unless rowExtent is set', (
      tester,
    ) async {
      final extents = <String, double>{};
      Widget probe(String name, double scale, {double? rowExtent}) =>
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: DirectoryTreeTheme(
              data: DirectoryTreeThemeData(rowExtent: rowExtent),
              child: Builder(
                builder: (context) {
                  extents[name] = DirectoryTreeTheme.of(context).rowExtent!;
                  return const SizedBox();
                },
              ),
            ),
          );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Column(
            children: [
              probe('default', 1),
              probe('large text', 2),
              probe('explicit', 2, rowExtent: 30),
            ],
          ),
        ),
      );
      expect(extents['default'], 28);
      expect(extents['large text'], greaterThan(28));
      expect(extents['explicit'], 30);
    });

    test('the theme resolves every default the skills name', () {
      final theme = DirectoryTreeThemeData.fallback(ThemeData());
      expect(theme.indentWidth, 16);
      expect(theme.expanderSize, 20);
      expect(theme.iconSize, 18);
      expect(theme.rowBorderRadius, const BorderRadius.all(Radius.circular(4)));
      expect(theme.guideStyle, DirectoryTreeGuideStyle.indent);
      expect(theme.animationDuration, const Duration(milliseconds: 150));
      expect(theme.iconSet, DirectoryTreeIconSet.material);
    });

    test('constructor defaults', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final view = DirectoryTreeView(controller: controller);
      expect(view.autofocus, isFalse);
      expect(view.selectOnTap, isTrue);
      expect(view.expandOnTap, isTrue);
      expect(view.selectionFollowsFocus, isTrue);
      expect(view.checkboxMode, DirectoryTreeCheckboxMode.none);
      expect(DirectoryTreePanel(controller: controller).autofocus, isFalse);
      expect(
        DirectoryTreeSearchField(controller: controller).debounce,
        const Duration(milliseconds: 120),
      );
      expect(
        DirectoryTreeDragAndDrop<Object?>(onDrop: (details) {}).autoExpandDelay,
        const Duration(milliseconds: 700),
      );
      expect(
        DirectoryTreePicker(tree: controller.tree).mode,
        DirectoryTreePickerMode.files,
      );
      expect(SliverDirectoryTree(controller: controller).rowDecorator, isNull);
      const loader = FileSystemTreeLoader();
      expect(loader.includeHidden, isFalse);
      expect(loader.followLinks, isFalse);
    });

    test('compactFolders joins chains of single folders into one row', () {
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths([
          '/repo/lib/src/a.dart',
          '/repo/README.md',
        ]),
        expansion: const ExpansionState.expanded(),
        compactFolders: true,
      );
      addTearDown(controller.dispose);
      final row = controller.rows[1];
      expect(row.label, 'lib/src');
      expect(row.chain.map((node) => node.name), ['lib', 'src']);
      expect(controller.rows.rowOf(controller.tree.idOf('/repo/lib')!), row);
    });

    testWidgets('selectionFollowsFocus: false moves the focus without '
        'selecting, and Space toggles', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          DirectoryTreeView(
            controller: controller,
            selectionFollowsFocus: false,
          ),
        ),
      );
      await tester.tap(find.text('test'));
      await tester.pump(kDoubleTapTimeout);
      final test = controller.tree.idOf('/repo/test')!;
      final readme = controller.tree.idOf('/repo/README.md')!;
      expect(controller.selection.selected, {test});

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.focusedId, isNot(test));
      expect(controller.selection.selected, {test});

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.focusedId, readme);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.selection.selected, {test, readme});
    });

    testWidgets('a click selects and toggles a folder; Enter toggles it and '
        'then calls onActivate', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      final activated = <String>[];
      await tester.pumpWidget(
        _app(
          DirectoryTreeView(
            controller: controller,
            onActivate: (row) => activated.add(row.label),
          ),
        ),
      );
      final lib = controller.tree.idOf('/repo/lib')!;
      await tester.tap(find.text('lib'));
      await tester.pump(kDoubleTapTimeout);
      expect(controller.isSelected(lib), isTrue);
      expect(controller.isExpanded(lib), isTrue);
      expect(activated, isEmpty);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.isExpanded(lib), isFalse);
      expect(activated, ['lib']);
    });

    testWidgets('the context menu gets the selection on a selected row, and '
        'with selectOnTap: false it opens without selecting', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      final menus = <List<String>>[];
      Future<void> pump({required bool selectOnTap}) => tester.pumpWidget(
        _app(
          DirectoryTreeView(
            controller: controller,
            selectOnTap: selectOnTap,
            contextMenuBuilder: (context, details) {
              menus.add([for (final node in details.nodes) node.name]);
              return const [];
            },
          ),
        ),
      );
      final test = controller.tree.idOf('/repo/test')!;
      final readme = controller.tree.idOf('/repo/README.md')!;

      await pump(selectOnTap: true);
      controller
        ..select(test)
        ..toggleSelected(readme);
      await tester.pump();
      await tester.tap(find.text('README.md'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(menus.last, ['test', 'README.md']);

      controller.clearSelection();
      await pump(selectOnTap: false);
      await tester.tap(find.text('test'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(menus.last, ['test']);
      expect(controller.selection.isEmpty, isTrue);
      expect(controller.focusedId, test);
    });

    testWidgets('each row reports its level in the semantics hint', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(DirectoryTreeView(controller: controller, semanticLabel: 'Files')),
      );
      expect(find.bySemanticsLabel('Files'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('repo')).hint,
        'Level 1',
      );
      expect(tester.getSemantics(find.bySemanticsLabel('lib')).hint, 'Level 2');
      handle.dispose();
    });

    testWidgets('FilesPane: the panel, persistence, new data, and Delete', (
      tester,
    ) async {
      const paths = [
        '/repo/lib/main.dart',
        '/repo/lib/src/tree.dart',
        '/repo/README.md',
      ];
      await tester.pumpWidget(
        _app(const FilesPane(paths: paths), scaffold: true),
      );
      expect(find.text('Files'), findsOneWidget);
      expect(find.text('lib'), findsOneWidget);
      final state = tester.state<_FilesPaneState>(find.byType(FilesPane));
      final saved = state.saveExpansion();

      await tester.enterText(find.byType(TextField), 'tree');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('tree.dart', findRichText: true), findsOneWidget);
      expect(state.saveExpansion(), saved);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 200));

      await tester.tap(find.text('lib'));
      await tester.pump(kDoubleTapTimeout);
      expect(find.text('main.dart'), findsOneWidget);
      final opened = state.saveExpansion();
      expect(opened, isNot(saved));

      await tester.pumpWidget(
        _app(const FilesPane(paths: [...paths, '/repo/lib/b.dart'])),
      );
      expect(find.text('b.dart'), findsOneWidget);
      expect(find.text('main.dart'), findsOneWidget);

      await tester.tap(find.text('README.md'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 1'));
      await tester.pumpAndSettle();
      expect(find.text('README.md'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _app(FilesPane(paths: paths, savedExpansion: opened)),
      );
      expect(find.text('main.dart'), findsOneWidget);
    });

    test('controllerBasics expands, selects, and checks lib', () async {
      final controller = _sample();
      addTearDown(controller.dispose);
      final log = await _debugLog(() async => controllerBasics(controller));
      final lib = controller.tree.idOf('/repo/lib')!;
      expect(controller.isExpanded(lib), isTrue);
      expect(controller.selection.selected, {lib});
      expect(controller.checkStateOf(lib), CheckState.checked);
      expect(log, [
        '[/repo/lib/src/tree.dart, /repo/lib/main.dart], focused: lib',
      ]);

      final empty = DirectoryTreeController<Object?>();
      addTearDown(empty.dispose);
      expect(await _debugLog(() async => controllerBasics(empty)), isEmpty);
    });

    test('watchRows logs splices and resets', () async {
      final controller = _sample();
      addTearDown(controller.dispose);
      final log = await _debugLog(() async {
        watchRows(controller);
        controller
          ..expand(controller.tree.idOf('/repo/lib')!)
          ..tree = DirectoryTree.fromPaths(['/repo/a.txt']);
      });
      expect(log, ['at 2: -0 +2', 'all 2 rows replaced']);
    });

    test(
      'openLocalFolder reads a folder and loads subfolders lazily',
      () async {
        final temp = await Directory.systemTemp.createTemp('skill_claims');
        addTearDown(() => temp.delete(recursive: true));
        await Directory('${temp.path}/lib').create();
        await File('${temp.path}/lib/main.dart').writeAsString('');
        await File('${temp.path}/.hidden').writeAsString('');

        final controller = await openLocalFolder(temp.path);
        addTearDown(controller.dispose);
        final name = temp.uri.pathSegments.where((s) => s.isNotEmpty).last;
        expect(controller.rows.map((row) => row.label), [name, 'lib']);
        expect(controller.rows.first.node.data, isA<Directory>());

        final lib = controller.rows[1].id;
        controller.expand(lib);
        await controller.loadChildren(lib);
        expect(controller.rows.map((row) => row.label), [
          name,
          'lib',
          'main.dart',
        ]);
        expect(controller.rows.last.node.data, isA<File>());
      },
    );

    testWidgets('treeWithBackspace moves to the parent row', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      controller.expand(controller.tree.idOf('/repo/lib')!);
      await tester.pumpWidget(
        _app(
          Builder(builder: (context) => treeWithBackspace(context, controller)),
        ),
      );
      await tester.tap(find.text('main.dart'));
      await tester.pump(kDoubleTapTimeout);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.focusedRow!.label, 'lib');
    });

    testWidgets('pickFolders returns the picked folders, or null on cancel', (
      tester,
    ) async {
      final tree = DirectoryTree.fromPaths([
        '/repo/lib/main.dart',
        '/repo/docs/',
        '/repo/README.md',
      ]);
      final results = <List<NodeId>?>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await pickFolders(context, tree)),
              child: const Text('Pick'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      expect(find.text('Choose folders'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [null]);

      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).first); // repo
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(results.last, [tree.roots.single]);
    });
  });

  group('migrate-flutter-directory-tree-v1-to-v2', () {
    test('dart fix ships the seven renames the skill lists', () {
      final fixes = File('lib/fix_data.yaml').readAsStringSync();
      expect(
        RegExp(r'^  - title:', multiLine: true).allMatches(fixes),
        hasLength(7),
      );
      for (final name in [
        'indent',
        'indentWidth',
        'rowHeight',
        'rowExtent',
        'removeIndicesDesc',
        'removedIndices',
        'insertIndicesAsc',
        'insertedIndices',
        'fullPath',
      ]) {
        expect(fixes, contains("'$name'"), reason: name);
      }
    });

    testWidgets('a migrated title that repeats the label is read twice '
        'unless it is excluded from semantics', (tester) async {
      for (final file in [
        '$_migrateSkill/SKILL.md',
        '$_migrateSkill/references/v1-to-v2-api-mapping.md',
      ]) {
        final text = _normalize(File(file).readAsStringSync());
        expect(text, contains('ExcludeSemantics'), reason: file);
      }
      final handle = tester.ensureSemantics();
      final controller = _sample();
      addTearDown(controller.dispose);
      Future<int> readmeLabels(
        DirectoryTreeRowBuilder<Object?> rowBuilder,
      ) async {
        await tester.pumpWidget(
          _app(
            DirectoryTreeView(controller: controller, rowBuilder: rowBuilder),
          ),
        );
        var root = tester.getSemantics(find.text('repo'));
        while (root.parent != null) {
          root = root.parent!;
        }
        var count = 0;
        void visit(SemanticsNode node) {
          count += 'README.md'.allMatches(node.label).length;
          node.visitChildren((SemanticsNode child) {
            visit(child);
            return true;
          });
        }

        visit(root);
        return count;
      }

      expect(
        await readmeLabels(
          (context, details) => DirectoryTreeRow(details: details),
        ),
        1,
      );
      expect(
        await readmeLabels(
          (context, details) => DirectoryTreeRow(
            details: details,
            title: Text(details.row.label),
          ),
        ),
        2,
      );
      expect(
        await readmeLabels(
          (context, details) => DirectoryTreeRow(
            details: details,
            title: ExcludeSemantics(child: Text(details.row.label)),
          ),
        ),
        1,
      );
      handle.dispose();
    });

    test('a 1.x string id compiles and matches nothing', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);
      const old = NodeId('main');
      controller.select(old);
      expect(controller.tree.contains(old), isFalse);
      expect(notifications, 0);
      expect(controller.tree.idOf('/repo/lib/main.dart')!.value, isNot('main'));
    });

    test(
      'a new controller starts collapsed with an empty multiple selection',
      () {
        final controller = DirectoryTreeController<Object?>(
          tree: DirectoryTree.fromPaths(['/repo/lib/main.dart', '/repo/a.md']),
        );
        addTearDown(controller.dispose);
        expect(controller.rows.map((row) => row.label), ['repo']);
        expect(controller.selection.isEmpty, isTrue);
        expect(controller.selectionMode, SelectionMode.multiple);
      },
    );

    test('paths are case-sensitive unless the tree says otherwise', () {
      expect(DirectoryTree.fromPaths(['/r/A.txt', '/r/a.txt']).fileCount, 2);
      expect(
        DirectoryTree.fromPaths(
          ['/r/A.txt', '/r/a.txt'],
          options: const TreeOptions(paths: PathPolicy.caseInsensitive),
        ).fileCount,
        1,
      );
    });

    test('in single mode, toggleSelected on the selected row clears it', () {
      final controller = _sample()..selectionMode = SelectionMode.single;
      addTearDown(controller.dispose);
      final readme = controller.tree.idOf('/repo/README.md')!;
      controller.select(readme);
      controller.toggleSelected(readme);
      expect(controller.selection.isEmpty, isTrue);
    });

    test('reveal focuses and scrolls unless told not to', () {
      final controller = _sample();
      addTearDown(controller.dispose);
      final main = controller.tree.idOf('/repo/lib/main.dart')!;
      expect(controller.reveal(main, focus: false, scroll: false), isTrue);
      expect(controller.focusedId, isNull);
      expect(controller.revealPath('/repo/lib/main.dart', select: true), main);
      expect(controller.focusedId, main);
      expect(controller.isSelected(main), isTrue);
    });

    test('ListDiff index lists are unmodifiable', () {
      final diff = ListDiff.compute([1, 2, 3], [3], keyOf: (value) => value);
      expect(diff.removedIndices, isNotEmpty);
      expect(() => diff.removedIndices.sort(), throwsUnsupportedError);
      expect(List.of(diff.removedIndices)..sort(), [0, 1]);
    });

    testWidgets('DirectoryTreeToolbar has no search field', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(DirectoryTreeToolbar(controller: controller)),
      );
      expect(find.byType(TextField), findsNothing);
      await tester.pumpWidget(_app(DirectoryTreePanel(controller: controller)));
      expect(find.byType(DirectoryTreeSearchField), findsOneWidget);
    });

    testWidgets('migratedView activates rows without a row builder', (
      tester,
    ) async {
      final controller = DirectoryTreeController<Object?>(
        tree: DirectoryTree.fromPaths([
          '/repo/lib/main.dart',
          '/repo/README.md',
        ]),
      );
      addTearDown(controller.dispose);
      final log = await _debugLog(() async {
        await tester.pumpWidget(_app(migratedView(controller)));
        await tester.tap(find.text('repo'));
        await tester.pump(kDoubleTapTimeout);
        await tester.tap(find.text('README.md'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('README.md'));
        await tester.pump(kDoubleTapTimeout);
      });
      expect(log, ['open /repo/README.md']);
    });

    testWidgets('pickFolderIds returns an empty set on cancel', (tester) async {
      final controller = _sample();
      addTearDown(controller.dispose);
      final results = <Set<NodeId>>[];
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await pickFolderIds(context, controller)),
              child: const Text('Pick'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(results, [<NodeId>{}]);
    });
  });
}

// ---------------------------------------------------------------------------
// The skills' Dart blocks, verbatim.

class FilesPane extends StatefulWidget {
  const FilesPane({super.key, required this.paths, this.savedExpansion});

  final List<String> paths;
  final Map<String, Object?>? savedExpansion;

  @override
  State<FilesPane> createState() => _FilesPaneState();
}

class _FilesPaneState extends State<FilesPane> {
  late final DirectoryTreeController<Object?> _controller;

  @override
  void initState() {
    super.initState();
    final tree = DirectoryTree.fromPaths(widget.paths);
    final saved = widget.savedExpansion;
    _controller = DirectoryTreeController(
      tree: tree,
      expansion: saved == null
          ? ExpansionState.withExpanded(tree.roots)
          : ExpansionState.fromJson(saved),
    );
  }

  @override
  void didUpdateWidget(FilesPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.paths, widget.paths)) {
      _controller.tree = DirectoryTree.fromPaths(widget.paths); // keeps state
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The value to persist: the requested expansion, not `rows.expansion`.
  Map<String, Object?> saveExpansion() => _controller.expansion.toJson();

  @override
  Widget build(BuildContext context) {
    return DirectoryTreePanel(
      controller: _controller,
      title: const Text('Files'),
      onActivate: (row) {
        if (row.node.isFile) debugPrint('open ${row.node.path}');
      },
      contextMenuBuilder: (context, details) => [
        MenuItemButton(
          onPressed: () => _controller.updateTree((builder) {
            for (final node in details.nodes) {
              builder.remove(node.path.toString());
            }
          }),
          child: Text('Delete ${details.nodes.length}'),
        ),
      ],
    );
  }
}

void controllerBasics(DirectoryTreeController<Object?> controller) {
  final lib = controller.tree.nodeAt('/repo/lib')?.id;
  if (lib == null) return; // not in the tree (idOf would still return an id)
  controller.expand(lib);
  controller.select(lib); // a click: selects, focuses, and scrolls to it
  controller.setChecked(lib, checked: true); // checks every leaf below lib
  final files = controller.checkedLeaves.map((node) => node.path).toList();
  debugPrint('$files, focused: ${controller.focusedRow?.label}');
}

void watchRows(DirectoryTreeController<Object?> controller) {
  controller.addListener(() {
    final change = controller.lastRowsChange; // read it here, not later
    if (change.isReset) {
      debugPrint('all ${controller.rows.length} rows replaced');
    } else {
      debugPrint('at ${change.index}: -${change.removed} +${change.inserted}');
    }
  });
}

Future<DirectoryTreeController<FileSystemEntity>> openLocalFolder(
  String path,
) async {
  const loader = FileSystemTreeLoader(); // includeHidden: false by default
  final tree = await loader.loadTree(path); // the folder and its children
  return DirectoryTreeController(
    tree: tree,
    expansion: ExpansionState.withExpanded(tree.roots),
    loadChildren: loader.loadChildren,
    onLoadError: (directory, error, stackTrace) =>
        debugPrint('Cannot open $directory: $error'),
  );
}

Widget treeWithBackspace(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) {
  return DirectoryTreeView(
    controller: controller,
    shortcuts: {
      ...DirectoryTreeShortcuts.defaults(
        platform: defaultTargetPlatform,
        textDirection: Directionality.of(context),
      ),
      const SingleActivator(LogicalKeyboardKey.backspace):
          const MoveTreeFocusIntent(TreeFocusMove.parent),
    },
  );
}

Future<List<NodeId>?> pickFolders(
  BuildContext context,
  DirectoryTree<Object?> tree,
) async {
  final picked = await showDirectoryTreePicker(
    context: context,
    tree: tree,
    mode: DirectoryTreePickerMode.directories,
    multiple: true,
    title: 'Choose folders',
  );
  return picked?.map((node) => node.id).toList(); // null: cancelled
}

Widget migratedView(DirectoryTreeController<Object?> controller) {
  return DirectoryTreeView(
    controller: controller, // tree: DirectoryTree.fromPaths([...])
    onActivate: (row) => debugPrint('open ${row.node.path}'),
  );
}

Future<Set<NodeId>> pickFolderIds(
  BuildContext context,
  DirectoryTreeController<Object?> controller,
) async {
  final nodes = await showDirectoryTreePicker(
    context: context,
    tree: controller.tree,
    mode: DirectoryTreePickerMode.directories, // was foldersOnly: true
    multiple: true, // was allowMultiple: true
    initialSelection: controller.selection.selected,
    initialExpansion: controller.expansion,
  );
  return nodes?.map((node) => node.id).toSet() ?? const <NodeId>{};
}

Widget composedExplorer(DirectoryTreeController<Object?> controller) {
  return DirectoryTreeContextMenu<Object?>(
    controller: controller, // above the keyboard: Shift+F10 reaches it
    builder: (context, details) => [
      MenuItemButton(
        onPressed: () => controller.expandSubtree(details.row.id),
        child: const Text('Expand all below'),
      ),
    ],
    child: Builder(
      builder: (context) => DirectoryTreeKeyboard(
        controller: controller,
        onActivate: (row) => debugPrint('open ${row.node.path}'),
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: Text('Open editors')),
            SliverDirectoryTree(
              controller: controller,
              onActivate: (row) => debugPrint('open ${row.node.path}'),
              onRowSecondaryTap: (row, globalPosition) =>
                  DirectoryTreeContextMenu.maybeOf<Object?>(
                    context, // the Builder's context, below the menu host
                  )?.open(row: row, globalPosition: globalPosition),
            ),
          ],
        ),
      ),
    ),
  );
}

class DraggableExplorer extends StatefulWidget {
  const DraggableExplorer({super.key, required this.controller});

  final DirectoryTreeController<Object?> controller;

  @override
  State<DraggableExplorer> createState() => _DraggableExplorerState();
}

class _DraggableExplorerState extends State<DraggableExplorer> {
  // The scope is above the menu host, so it reaches the host by this key.
  final _menuKey = GlobalKey<DirectoryTreeContextMenuState<Object?>>();

  void _openMenu(TreeRow<Object?> row, Offset globalPosition) =>
      _menuKey.currentState?.open(row: row, globalPosition: globalPosition);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return DirectoryTreeDragAndDropScope<Object?>(
      controller: controller,
      dragAndDrop: DirectoryTreeDragAndDrop(
        onDrop: (details) => debugPrint(
          'move ${details.nodes.length} into ${details.target.path}',
        ),
      ),
      onLongPressWithoutDrag: _openMenu, // a touch long press that did not drag
      child: DirectoryTreeContextMenu<Object?>(
        key: _menuKey,
        controller: controller,
        builder: (context, details) => [
          MenuItemButton(
            onPressed: () => controller.expandSubtree(details.row.id),
            child: const Text('Expand all below'),
          ),
        ],
        child: DirectoryTreeKeyboard(
          controller: controller,
          child: CustomScrollView(
            slivers: [
              SliverDirectoryTree(
                controller: controller,
                rowDecorator:
                    DirectoryTreeDragAndDropScope.decorateRow<Object?>,
                secondaryTapOnLongPress: false, // the scope owns long presses
                onRowSecondaryTap: _openMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers.

/// The normalized dartdoc right above [declaration] in [source].
String _docOf(String source, String declaration) {
  final lines = source.split('\n');
  final at = lines.indexWhere((line) => line.trim().startsWith(declaration));
  expect(at, isNot(-1), reason: 'no declaration "$declaration"');
  var end = at;
  while (end > 0 && lines[end - 1].trim().startsWith('@')) {
    end--; // annotations between the dartdoc and the declaration
  }
  var start = end;
  while (start > 0 && lines[start - 1].trim().startsWith('///')) {
    start--;
  }
  return _normalize(
    lines
        .sublist(start, end)
        .map((line) => line.trim().replaceFirst('///', ''))
        .join(' '),
  );
}

DirectoryTreeController<Object?> _sample() {
  final tree = DirectoryTree.fromPaths([
    '/repo/lib/main.dart',
    '/repo/lib/src/tree.dart',
    '/repo/test/tree_test.dart',
    '/repo/README.md',
  ]);
  return DirectoryTreeController<Object?>(
    tree: tree,
    expansion: ExpansionState.withExpanded(tree.roots),
  );
}

Widget _app(Widget child, {bool scaffold = true}) =>
    MaterialApp(home: scaffold ? Scaffold(body: child) : child);

Future<List<String>> _debugLog(Future<void> Function() body) async {
  final log = <String>[];
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) => log.add(message ?? '');
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return log;
}

/// [text] with every run of whitespace collapsed to one space.
String _normalize(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// [source] without `//` comments (including doc comments).
String _stripComments(String source) =>
    source.replaceAll(RegExp(r'//.*$', multiLine: true), '');

bool _isCamelCase(String name) =>
    RegExp('^[A-Z]').hasMatch(name) || RegExp('[a-z][A-Z]').hasMatch(name);

/// The root directory of the resolved package [name].
Directory _packageRoot(String name) {
  final config = jsonDecode(
    File('.dart_tool/package_config.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final packages = (config['packages']! as List<Object?>)
      .cast<Map<String, Object?>>();
  final entry = packages.singleWhere((package) => package['name'] == name);
  final configUri = Uri.file(
    File('.dart_tool/package_config.json').absolute.path,
  );
  final root = configUri.resolve('${entry['rootUri']}/');
  return Directory.fromUri(root.resolve(entry['packageUri']! as String));
}

/// The API names a skill file mentions, each with the line it is on:
/// CamelCase names in its description; in inline code, every CamelCase
/// name, every name after a `.` or before a `(` or `:`, and every span that
/// is a single name; and the same names, line by line, in every fenced
/// block except the 2.x `dart` blocks, which this file compiles instead.
/// String literals and `//` comments are dropped first, and spans or lines
/// that are paths or shell commands are skipped.
List<({String name, String line})> _mentionedNames(String text) {
  final names = <({String name, String line})>[];
  final identifier = RegExp('[A-Za-z_][A-Za-z0-9_]*');
  const commands = ['flutter ', 'dart ', 'grep ', 'claude ', 'codex ', 'agy '];

  void scan(String raw, String line) {
    final code = raw
        .replaceAll('\n', ' ')
        .replaceAll(
          RegExp(
            r"'[^']*'|"
            r'"[^"]*"',
          ),
          "''",
        )
        .replaceAll(RegExp(r'//.*$'), '')
        .trim();
    if (code.isEmpty ||
        code.startsWith('#') ||
        code.contains('/') ||
        commands.any(code.startsWith)) {
      return;
    }
    for (final match in identifier.allMatches(code)) {
      final name = match.group(0)!;
      final before = match.start == 0 ? '' : code[match.start - 1];
      final after = match.end == code.length ? '' : code[match.end];
      if (_isCamelCase(name) ||
          before == '.' ||
          after == '(' ||
          after == ':' ||
          (match.start == 0 && match.end == code.length)) {
        names.add((name: name, line: line));
      }
    }
  }

  var body = text;
  final frontmatter = RegExp(r'^---\n([\s\S]*?)\n---\n').firstMatch(text);
  if (frontmatter != null) {
    final description = RegExp(
      r'^description:(.*)$',
      multiLine: true,
    ).firstMatch(frontmatter.group(1)!)!.group(1)!;
    for (final match in identifier.allMatches(description)) {
      final name = match.group(0)!;
      if (RegExp('[a-z0-9][A-Z]').hasMatch(name)) {
        names.add((name: name, line: 'description:${match.group(0)}'));
      }
    }
    body = text.substring(frontmatter.end);
  }
  final fence = RegExp(r'```(\w*)\n([\s\S]*?)```');
  for (final match in fence.allMatches(body)) {
    final content = match.group(2)!;
    if (match.group(1) == 'dart' && !content.startsWith(_v1Marker)) continue;
    for (final line in content.split('\n')) {
      scan(line, line.trim());
    }
  }
  final prose = body.replaceAll(fence, '');
  final lines = prose.split('\n');
  var offset = 0;
  final lineStarts = <int>[
    for (final line in lines) (offset += line.length + 1) - line.length - 1,
  ];
  for (final span in RegExp('`([^`]+)`').allMatches(prose)) {
    final index = lineStarts.lastIndexWhere((start) => start <= span.start);
    scan(span.group(1)!, lines[index].trim());
  }
  return names;
}

/// Whether [line] of the use skill names the removed 1.x [name] as such: in
/// the "Wrong guess" column of a table row, or on a line about 1.x.
bool _namesOldApi(String line, String name) {
  if (line.contains('1.x')) return true;
  final cells = line.split('|');
  return line.startsWith('|') && cells.length > 3 && cells[2].contains(name);
}

/// Whether the brackets of [code] balance once strings and comments are
/// dropped, so a block was not cut short.
bool _isBalanced(String code) {
  final stripped = code
      .replaceAll(
        RegExp(
          r"'[^'\n]*'|"
          r'"[^"\n]*"',
        ),
        "''",
      )
      .replaceAll(RegExp(r'//.*$', multiLine: true), '');
  final stack = <String>[];
  const pairs = {')': '(', ']': '[', '}': '{'};
  for (final char in stripped.split('')) {
    if ('([{'.contains(char)) {
      stack.add(char);
    } else if (pairs.containsKey(char)) {
      if (stack.isEmpty || stack.removeLast() != pairs[char]) return false;
    }
  }
  return stack.isEmpty;
}

// ---------------------------------------------------------------------------
// The names the skills may mention.

// Never initialized: the closures in _names are compiled, never called.
late final DirectoryTreeController<Object?> _c;
late final DirectoryTree<Object?> _tree;
late final TreeRow<Object?> _row;
late final TreeNode<Object?> _node;
late final DirectoryNode<Object?> _dir;
late final DirectoryTreeRowDetails<Object?> _details;
late final DirectoryTreeMenuDetails<Object?> _menu;
late final DirectoryTreeDropDetails<Object?> _drop;
late final TreeRowsChange _change;
late final DirectoryTreeBuilder<Object?> _builder;
late final BuildContext _context;
late final NodeId _id;
late final DirectoryTreeThemeData _theme;
late final DirectoryTreeContextMenuState<Object?> _menuState;
late final ExpansionState _expansion;
late final SelectionState _selection;
late final ListDiff _diff;
late final TreePath _path;
late final DirectoryTreeIconSet _icons;

/// Every 2.x and Flutter name the skills mention, each with code that uses
/// it, so a renamed or removed name fails to compile.
final Map<String, void Function()> _names = {
  'Actions': () => Actions,
  'ActivateTreeNodeIntent': () => ActivateTreeNodeIntent,
  'BorderRadius': () => BorderRadius,
  'BrowserContextMenu': () => BrowserContextMenu,
  'CheckState': () => CheckState,
  'ClearTreeSelectionIntent': () => ClearTreeSelectionIntent,
  'CollapseTreeNodeIntent': () => CollapseTreeNodeIntent,
  'Directory': () => Directory,
  'DirectoryChildrenLoader': () => DirectoryChildrenLoader,
  'DirectoryLoadStatus': () => DirectoryLoadStatus,
  'DirectoryNode': () => DirectoryNode,
  'DirectoryScanner': () => DirectoryScanner,
  'DirectoryTree': () => DirectoryTree,
  'DirectoryTreeBuilder': () => DirectoryTreeBuilder,
  'DirectoryTreeCheckbox': () => DirectoryTreeCheckbox,
  'DirectoryTreeCheckboxMode': () => DirectoryTreeCheckboxMode,
  'DirectoryTreeContextMenu': () => DirectoryTreeContextMenu,
  'DirectoryTreeController': () => DirectoryTreeController,
  'DirectoryTreeDragAndDrop': () => DirectoryTreeDragAndDrop,
  'DirectoryTreeDragAndDropScope': () => DirectoryTreeDragAndDropScope,
  'DirectoryTreeDropDetails': () => DirectoryTreeDropDetails,
  'DirectoryTreeExpander': () => DirectoryTreeExpander,
  'DirectoryTreeGuideStyle': () => DirectoryTreeGuideStyle,
  'DirectoryTreeIconSet': () => DirectoryTreeIconSet,
  'DirectoryTreeIndentGuides': () => DirectoryTreeIndentGuides,
  'DirectoryTreeKeyboard': () => DirectoryTreeKeyboard,
  'DirectoryTreeLabel': () => DirectoryTreeLabel,
  'DirectoryTreeMenuDetails': () => DirectoryTreeMenuDetails,
  'DirectoryTreeMenuBuilder': () => DirectoryTreeMenuBuilder,
  'DirectoryTreePanel': () => DirectoryTreePanel,
  'DirectoryTreePicker': () => DirectoryTreePicker,
  'DirectoryTreePickerMode': () => DirectoryTreePickerMode,
  'DirectoryTreeRow': () => DirectoryTreeRow,
  'DirectoryTreeRowBuilder': () => DirectoryTreeRowBuilder,
  'DirectoryTreeRowDecorator': () => DirectoryTreeRowDecorator,
  'DirectoryTreeRowDetails': () => DirectoryTreeRowDetails,
  'DirectoryTreeSearchField': () => DirectoryTreeSearchField,
  'DirectoryTreeShortcuts': () => DirectoryTreeShortcuts,
  'DirectoryTreeTheme': () => DirectoryTreeTheme,
  'DirectoryTreeThemeData': () => DirectoryTreeThemeData,
  'DirectoryTreeToolbar': () => DirectoryTreeToolbar,
  'DirectoryTreeView': () => DirectoryTreeView,
  'DirectoryTreeViewport': () => DirectoryTreeViewport,
  'Duration': () => Duration,
  'ExcludeSemantics': () => ExcludeSemantics,
  'ExpandTreeNodeIntent': () => ExpandTreeNodeIntent,
  'ExpandTreeSubtreeIntent': () => ExpandTreeSubtreeIntent,
  'Expanded': () => Expanded,
  'ExpansionState': () => ExpansionState,
  'File': () => File,
  'FileNode': () => FileNode,
  'FileSystemEntity': () => FileSystemEntity,
  'FileSystemTreeLoader': () => FileSystemTreeLoader,
  'Function': () => Function,
  'Future': () => Future,
  'GestureDetector': () => GestureDetector,
  'Link': () => Link,
  'List': () => List,
  'ListDiff': () => ListDiff,
  'ListenableBuilder': () => ListenableBuilder,
  'MenuItemButton': () => MenuItemButton,
  'MoveTreeFocusIntent': () => MoveTreeFocusIntent,
  'NodeId': () => NodeId,
  'OpenTreeContextMenuIntent': () => OpenTreeContextMenuIntent,
  'PathPolicy': () => PathPolicy,
  'Scaffold': () => Scaffold,
  'SelectAllTreeNodesIntent': () => SelectAllTreeNodesIntent,
  'SelectionMode': () => SelectionMode,
  'SelectionState': () => SelectionState,
  'Set': () => Set,
  'SizedBox': () => SizedBox,
  'SliverDirectoryTree': () => SliverDirectoryTree,
  'String': () => String,
  'TextOverflow': () => TextOverflow,
  'ThemeData': () => ThemeData,
  'ThemeExtension': () => ThemeExtension,
  'ToggleTreeSelectionIntent': () => ToggleTreeSelectionIntent,
  'TreeEntry': () => TreeEntry,
  'TreeFilter': () => TreeFilter,
  'TreeFocusMove': () => TreeFocusMove,
  'TreeNode': () => TreeNode,
  'TreeNodeKind': () => TreeNodeKind,
  'TreeOptions': () => TreeOptions,
  'TreeOrder': () => TreeOrder,
  'TreePath': () => TreePath,
  'TreeQuery': () => TreeQuery,
  'TreeRoots': () => TreeRoots,
  'TreeRow': () => TreeRow,
  'TreeRows': () => TreeRows,
  'TreeRowsChange': () => TreeRowsChange,
  'TreeSelectionUpdate': () => TreeSelectionUpdate,
  'ValueChanged': () => ValueChanged,
  'VisualDensity': () => VisualDensity,
  'Widget': () => Widget,
  // Controller members and constructor parameters.
  'tree': () => DirectoryTreeController<Object?>(tree: _c.tree),
  'expansion': () => DirectoryTreeController<Object?>(expansion: _c.expansion),
  'selection': () => DirectoryTreeController<Object?>(selection: _c.selection),
  'checks': () => DirectoryTreeController<Object?>(checks: _c.checks),
  'selectable': () =>
      DirectoryTreeController<Object?>(selectable: (node) => true),
  'query': () => DirectoryTreeController<Object?>(query: _c.query),
  'caseSensitiveQuery': () => DirectoryTreeController<Object?>(
    caseSensitiveQuery: _c.caseSensitiveQuery,
  ),
  'filter': () => DirectoryTreeController<Object?>(filter: _c.filter),
  'revealMatches': () =>
      DirectoryTreeController<Object?>(revealMatches: _c.revealMatches),
  'compactFolders': () =>
      DirectoryTreeController<Object?>(compactFolders: _c.compactFolders),
  'showRoots': () => DirectoryTreeController<Object?>(showRoots: _c.showRoots),
  'loadChildren': () =>
      DirectoryTreeController<Object?>(loadChildren: (d) async => []),
  'onLoadError': () =>
      DirectoryTreeController<Object?>(onLoadError: (d, e, s) {}),
  'updateTree': () => _c.updateTree,
  'rows': () => _c.rows,
  'lastRowsChange': () => _c.lastRowsChange,
  'isExpandable': () => _c.isExpandable,
  'isExpanded': () => _c.isExpanded,
  'expand': () => _c.expand,
  'collapse': () => _c.collapse,
  'toggleExpansion': () => _c.toggleExpansion,
  'expandAll': () => _c.expandAll,
  'collapseAll': () => _c.collapseAll,
  'expandSubtree': () => _c.expandSubtree,
  'collapseSubtree': () => _c.collapseSubtree,
  'reveal': () => _c.reveal,
  'revealPath': () => _c.revealPath,
  'focus': () => _c.reveal(_id, focus: true),
  'scroll': () => _c.reveal(_id, scroll: true),
  'alignment': () => _c.reveal(_id, alignment: 0),
  'duration': () => _c.reveal(_id, duration: Duration.zero),
  'curve': () => _c.reveal(_id, curve: Curves.linear),
  'select': () => _c.select,
  'selectionMode': () => _c.selectionMode,
  'isSelected': () => _c.isSelected,
  'isSelectable': () => _c.isSelectable,
  'selectedNodes': () => _c.selectedNodes,
  'toggleSelected': () => _c.toggleSelected,
  'extendSelection': () => _c.extendSelection,
  'selectAll': () => _c.selectAll,
  'clearSelection': () => _c.clearSelection,
  'checkStateOf': () => _c.checkStateOf,
  'toggleChecked': () => _c.toggleChecked,
  'setChecked': () => _c.setChecked,
  'checked': () => _c.setChecked(_id, checked: true),
  'checkAll': () => _c.checkAll,
  'uncheckAll': () => _c.uncheckAll,
  'checkedLeaves': () => _c.checkedLeaves,
  'checkedRoots': () => _c.checkedRoots,
  'focusedId': () => _c.focusedId,
  'focusedRow': () => _c.focusedRow,
  'focusedIndex': () => _c.focusedIndex,
  'moveFocus': () => _c.moveFocus,
  'pageSize': () => _c.moveFocus(TreeFocusMove.next, pageSize: 1),
  'parsedQuery': () => _c.parsedQuery,
  'isFiltering': () => _c.isFiltering,
  'matchRangesOf': () => _c.matchRangesOf,
  'loadStatusOf': () => _c.loadStatusOf,
  'loadErrorOf': () => _c.loadErrorOf,
  'reloadChildren': () => _c.reloadChildren,
  'ensureVisible': () => _c.ensureVisible,
  'globalRowRect': () => _c.globalRowRect,
  'attachViewport': () => _c.attachViewport,
  'detachViewport': () => _c.detachViewport,
  'dispose': () => _c.dispose,
  'addListener': () => _c.addListener,
  // Enum values.
  'next': () => TreeFocusMove.next,
  'previous': () => TreeFocusMove.previous,
  'first': () => TreeFocusMove.first,
  'last': () => TreeFocusMove.last,
  'parent': () => TreeFocusMove.parent,
  'firstChild': () => TreeFocusMove.firstChild,
  'pageDown': () => TreeFocusMove.pageDown,
  'pageUp': () => TreeFocusMove.pageUp,
  'replace': () => TreeSelectionUpdate.replace,
  'extend': () => TreeSelectionUpdate.extend,
  'keep': () => TreeSelectionUpdate.keep,
  'notLoaded': () => DirectoryLoadStatus.notLoaded,
  'loading': () => DirectoryLoadStatus.loading,
  'loaded': () => DirectoryLoadStatus.loaded,
  'failed': () => DirectoryLoadStatus.failed,
  'unchecked': () => CheckState.unchecked,
  'partial': () => CheckState.partial,
  'single': () => SelectionMode.single,
  'multiple': () => SelectionMode.multiple,
  'none': () => DirectoryTreeCheckboxMode.none,
  'files': () => DirectoryTreePickerMode.files,
  'directories': () => DirectoryTreePickerMode.directories,
  'any': () => DirectoryTreePickerMode.any,
  'indent': () => DirectoryTreeGuideStyle.indent,
  'connectors': () => DirectoryTreeGuideStyle.connectors,
  'compact': () => VisualDensity.compact,
  'zero': () => Duration.zero,
  'material': () => DirectoryTreeIconSet.material,
  'caseInsensitive': () => PathPolicy.caseInsensitive,
  'alphabetical': () => TreeOrder.alphabetical,
  'directoriesFirst': () => TreeOrder.directoriesFirst,
  'by': () => TreeOrder.by<Object?>((a, b) => 0),
  // Core types.
  'fromPaths': () => DirectoryTree.fromPaths,
  'build': () => DirectoryTree<Object?>.build,
  'empty': () => DirectoryTree<Object?>.empty,
  'roots': () => _tree.roots,
  'rootNodes': () => _tree.rootNodes,
  'nodes': () => _tree.nodes,
  'entries': () => _tree.entries,
  'options': () => _tree.options,
  'contains': () => _tree.contains,
  'idOf': () => _tree.idOf,
  'nodeAt': () => _tree.nodeAt,
  'childrenOf': () => _tree.childrenOf,
  'parentOf': () => _tree.parentOf,
  'ancestorsOf': () => _tree.ancestorsOf,
  'descendantsOf': () => _tree.descendantsOf,
  'rebuild': () => _tree.rebuild,
  'file': () => TreeEntry<Object?>.file,
  'directory': () => TreeEntry<Object?>.directory,
  'data': () => TreeEntry<Object?>.file('/a', data: _node.data),
  'add': () => _builder.add,
  'addFile': () => _builder.addFile,
  'addDirectory': () => _builder.addDirectory,
  'remove': () => _builder.remove,
  'removeWhere': () => _builder.removeWhere,
  'id': () => _node.id,
  'path': () => _node.path,
  'name': () => _node.name,
  'depth': () => _node.depth,
  'kind': () => _node.kind,
  'isFile': () => _node.isFile,
  'isDirectory': () => _node.isDirectory,
  'isRoot': () => _node.isRoot,
  'children': () => _dir.children,
  'extension': () => _path.extension,
  'toString': () => _path.toString,
  'node': () => _row.node,
  'label': () => _row.label,
  'hasChildren': () => _row.hasChildren,
  'isLast': () => _row.isLast,
  'isMatch': () => _row.isMatch,
  'guides': () => _row.guides,
  'chain': () => _row.chain,
  'indexOfNode': () => _c.rows.indexOfNode,
  'rowOf': () => _c.rows.rowOf,
  'isReset': () => _change.isReset,
  'index': () => _change.index,
  'removed': () => _change.removed,
  'inserted': () => _change.inserted,
  'paths': () => const TreeOptions(paths: PathPolicy.caseInsensitive),
  'order': () => const TreeOptions(order: TreeOrder.alphabetical),
  'copyWith': () => const TreeOptions().copyWith,
  'fixed': () => const TreeRoots.fixed(['/a']),
  'minimal': () => const TreeRoots.minimal(),
  'commonAncestor': () => const TreeRoots.commonAncestor(),
  'filesystem': () => const TreeRoots.filesystem(),
  'collapsed': () => const ExpansionState.collapsed(),
  'expanded': () => const ExpansionState.expanded(),
  'withExpanded': () => ExpansionState.withExpanded,
  'withCollapsed': () => ExpansionState.withCollapsed,
  'fromJson': () => ExpansionState.fromJson,
  'toJson': () => _expansion.toJson,
  'exceptions': () => _expansion.exceptions,
  'setExpanded': () => _expansion.setExpanded,
  'toggle': () => _expansion.toggle,
  'prune': () => _expansion.prune,
  'mode': () => _selection.mode,
  'selected': () => _selection.selected,
  'anchor': () => _selection.anchor,
  'addAll': () => _selection.addAll,
  'removeAll': () => _selection.removeAll,
  'clear': () => _selection.clear,
  'isEmpty': () => _selection.isEmpty,
  'parse': () => TreeQuery.parse,
  'caseSensitive': () => TreeQuery.parse('', caseSensitive: true),
  'where': () => TreeFilter.where<Object?>,
  'and': () => TreeFilter.all.and,
  'or': () => TreeFilter.all.or,
  'negate': () => TreeFilter.all.negate,
  'value': () => _id.value,
  'compute': () => ListDiff.compute<int, int>,
  'keyOf': () => ListDiff.compute<int, int>([], [], keyOf: (v) => v),
  'removedIndices': () => _diff.removedIndices,
  'insertedIndices': () => _diff.insertedIndices,
  'sort': () => _diff.removedIndices.sort,
  // Widgets and their parameters.
  'controller': () => DirectoryTreeView(controller: _c),
  'rowBuilder': () => DirectoryTreeView(controller: _c, rowBuilder: null),
  'checkboxMode': () => DirectoryTreeView(
    controller: _c,
    checkboxMode: DirectoryTreeCheckboxMode.checks,
  ),
  'expandOnTap': () => DirectoryTreeView(controller: _c, expandOnTap: false),
  'selectOnTap': () => DirectoryTreeView(controller: _c, selectOnTap: false),
  'onRowTap': () => DirectoryTreeView(controller: _c, onRowTap: (row) {}),
  'onActivate': () => DirectoryTreeView(controller: _c, onActivate: (row) {}),
  'onRowSecondaryTap': () =>
      DirectoryTreeView(controller: _c, onRowSecondaryTap: (row, p) {}),
  'contextMenuBuilder': () =>
      DirectoryTreeView(controller: _c, contextMenuBuilder: (c, d) => []),
  'dragAndDrop': () => DirectoryTreeView(controller: _c, dragAndDrop: null),
  'autofocus': () => DirectoryTreeView(controller: _c, autofocus: true),
  'shortcuts': () => DirectoryTreeView(controller: _c, shortcuts: const {}),
  'scrollController': () =>
      DirectoryTreeView(controller: _c, scrollController: null),
  'selectionFollowsFocus': () =>
      DirectoryTreeView(controller: _c, selectionFollowsFocus: false),
  'semanticLabel': () => DirectoryTreeView(controller: _c, semanticLabel: ''),
  'levelSemanticsHint': () =>
      DirectoryTreeView(controller: _c, levelSemanticsHint: (level) => ''),
  'activateSemanticsLabel': () =>
      DirectoryTreeView(controller: _c, activateSemanticsLabel: ''),
  'loadingSemanticsLabel': () =>
      DirectoryTreeView(controller: _c, loadingSemanticsLabel: ''),
  'loadFailedSemanticsLabel': () =>
      DirectoryTreeView(controller: _c, loadFailedSemanticsLabel: ''),
  'emptyBuilder': () => DirectoryTreeView(controller: _c, emptyBuilder: null),
  'title': () => DirectoryTreePanel(controller: _c, title: null),
  'actions': () => DirectoryTreePanel(controller: _c, actions: const []),
  'toolbar': () => DirectoryTreePanel(controller: _c, toolbar: null),
  'showToolbar': () => DirectoryTreePanel(controller: _c, showToolbar: false),
  'showSearch': () => DirectoryTreePanel(controller: _c, showSearch: false),
  'searchHintText': () =>
      DirectoryTreePanel(controller: _c, searchHintText: ''),
  'expandAllTooltip': () =>
      DirectoryTreePanel(controller: _c, expandAllTooltip: ''),
  'showExpandAll': () =>
      DirectoryTreeToolbar(controller: _c, showExpandAll: false),
  'showCollapseAll': () =>
      DirectoryTreeToolbar(controller: _c, showCollapseAll: false),
  'hintText': () => DirectoryTreeSearchField(controller: _c, hintText: ''),
  'rowDecorator': () => SliverDirectoryTree(
    controller: _c,
    rowDecorator: DirectoryTreeDragAndDropScope.decorateRow<Object?>,
  ),
  'decorateRow': () => DirectoryTreeDragAndDropScope.decorateRow<Object?>,
  'secondaryTapOnLongPress': () =>
      SliverDirectoryTree(controller: _c, secondaryTapOnLongPress: false),
  'child': () => DirectoryTreeKeyboard(controller: _c, child: const Text('')),
  'maybeOf': () => DirectoryTreeContextMenu.maybeOf<Object?>,
  'open': () => _menuState.open,
  'globalPosition': () =>
      _menuState.open(row: _row, globalPosition: _menu.globalPosition),
  'row': () => _menuState.open(row: _details.row, globalPosition: Offset.zero),
  'details': () => DirectoryTreeRow(details: _details),
  'expander': () => DirectoryTreeRow(details: _details, expander: null),
  'leading': () => DirectoryTreeRow(details: _details, leading: null),
  'trailing': () => DirectoryTreeRow(details: _details, trailing: null),
  'text': () => DirectoryTreeLabel(text: ''),
  'isFocused': () => _details.isFocused,
  'hasFocus': () => _details.hasFocus,
  'isHovered': () => _details.isHovered,
  'checkState': () => _details.checkState,
  'loadStatus': () => _details.loadStatus,
  'matchRanges': () => _details.matchRanges,
  'onDrop': () => DirectoryTreeDragAndDrop<Object?>(onDrop: (d) {}),
  'canDrag': () =>
      DirectoryTreeDragAndDrop<Object?>(onDrop: (d) {}, canDrag: (n) => true),
  'canDrop': () =>
      DirectoryTreeDragAndDrop<Object?>(onDrop: (d) {}, canDrop: (d) => true),
  'autoExpandDelay': () =>
      DirectoryTreeDragAndDrop<Object?>(onDrop: (d) {}, autoExpandDelay: null),
  'feedbackBuilder': () => DirectoryTreeDragAndDrop<Object?>(
    onDrop: (d) {},
    feedbackBuilder: (c, n) => const SizedBox(),
  ),
  'target': () => _drop.target,
  'showDirectoryTreePicker': () => showDirectoryTreePicker<Object?>,
  'context': () => showDirectoryTreePicker(context: _context, tree: _tree),
  'initialSelection': () =>
      DirectoryTreePicker(tree: _tree, initialSelection: const []),
  'initialExpansion': () =>
      DirectoryTreePicker(tree: _tree, initialExpansion: null),
  'onChanged': () => DirectoryTreePicker(tree: _tree, onChanged: (n) {}),
  'onConfirm': () => DirectoryTreePicker(tree: _tree, onConfirm: (n) {}),
  'defaults': () => DirectoryTreeShortcuts.defaults,
  'platform': () => DirectoryTreeShortcuts.defaults(
    platform: TargetPlatform.macOS,
    textDirection: TextDirection.ltr,
  ),
  'textDirection': () => DirectoryTreeShortcuts.defaults(
    platform: TargetPlatform.macOS,
    textDirection: TextDirection.ltr,
  ),
  // Theme.
  'of': () => DirectoryTreeTheme.of,
  'fallback': () => DirectoryTreeThemeData.fallback,
  'merge': () => _theme.merge,
  'lerp': () => _theme.lerp,
  'rowExtent': () => _theme.rowExtent,
  'indentWidth': () => _theme.indentWidth,
  'rowPadding': () => _theme.rowPadding,
  'rowBorderRadius': () => _theme.rowBorderRadius,
  'expanderSize': () => _theme.expanderSize,
  'iconSize': () => _theme.iconSize,
  'iconSpacing': () => _theme.iconSpacing,
  'guideStyle': () => _theme.guideStyle,
  'guideColor': () => _theme.guideColor,
  'guideWidth': () => _theme.guideWidth,
  'hoverColor': () => _theme.hoverColor,
  'selectedColor': () => _theme.selectedColor,
  'inactiveSelectedColor': () => _theme.inactiveSelectedColor,
  'focusedBorderColor': () => _theme.focusedBorderColor,
  'focusedBorderWidth': () => _theme.focusedBorderWidth,
  'dropTargetColor': () => _theme.dropTargetColor,
  'labelStyle': () => _theme.labelStyle,
  'selectedLabelStyle': () => _theme.selectedLabelStyle,
  'dimmedLabelStyle': () => _theme.dimmedLabelStyle,
  'matchHighlightStyle': () => _theme.matchHighlightStyle,
  'iconColor': () => _theme.iconColor,
  'folderIconColor': () => _theme.folderIconColor,
  'iconSet': () => _theme.iconSet,
  'animationDuration': () => _theme.animationDuration,
  'animationCurve': () => _theme.animationCurve,
  'extensions': () => _icons.copyWith(extensions: _icons.extensions),
  'iconFor': () => _icons.iconFor,
  'folder': () => _icons.folder,
  // File system.
  'loadTree': () => const FileSystemTreeLoader().loadTree,
  'includeHidden': () => const FileSystemTreeLoader(includeHidden: true),
  'followLinks': () => const FileSystemTreeLoader(followLinks: true),
  'skip': () => FileSystemTreeLoader(skip: (entity) => false),
  // Flutter and Dart.
  'identical': () => identical,
  'onPressed': () => MenuItemButton(onPressed: () {}, child: null),
  'leadingIcon': () => MenuItemButton(leadingIcon: null, child: null),
  'onTertiaryTapUp': () => GestureDetector(onTertiaryTapUp: (details) {}),
  'disableContextMenu': () => BrowserContextMenu.disableContextMenu,
  'enableContextMenu': () => BrowserContextMenu.enableContextMenu,
  // Signatures in the API reference.
  'DirectoryLoadErrorCallback': () => DirectoryLoadErrorCallback,
  'Iterable': () => Iterable,
  'Object': () => Object,
  'Offset': () => Offset,
  'StackTrace': () => StackTrace,
  'stackTrace': () =>
      DirectoryTreeController<Object?>(onLoadError: (d, e, stackTrace) {}),
  'milliseconds': () => const Duration(milliseconds: 1),
  'seconds': () => const Duration(seconds: 1),
  'ellipsis': () => TextOverflow.ellipsis,
  'move': () => const MoveTreeFocusIntent(TreeFocusMove.next).move,
  'close': () => _menuState.close,
  'isOpen': () => _menuState.isOpen,
  'selectOnOpen': () => DirectoryTreeContextMenu<Object?>(
    controller: _c,
    builder: (context, details) => [],
    selectOnOpen: false,
    child: const SizedBox(),
  ),
  'onLongPressWithoutDrag': () => DirectoryTreeDragAndDropScope<Object?>(
    controller: _c,
    dragAndDrop: DirectoryTreeDragAndDrop(onDrop: (d) {}),
    onLongPressWithoutDrag: (row, position) {},
    child: const SizedBox(),
  ),
  'focusNode': () => DirectoryTreeView(controller: _c, focusNode: null),
  'typeAhead': () => DirectoryTreeView(controller: _c, typeAhead: false),
  'showScrollbar': () =>
      DirectoryTreeView(controller: _c, showScrollbar: false),
  'typeAheadTimeout': () => DirectoryTreeKeyboard(
    controller: _c,
    typeAheadTimeout: Duration.zero,
    child: const SizedBox(),
  ),
  'collapseAllTooltip': () =>
      DirectoryTreePanel(controller: _c, collapseAllTooltip: ''),
  'showCompactFolders': () =>
      DirectoryTreeToolbar(controller: _c, showCompactFolders: true),
  'compactFoldersTooltip': () =>
      DirectoryTreeToolbar(controller: _c, compactFoldersTooltip: ''),
  'treeFocusNode': () =>
      DirectoryTreeSearchField(controller: _c, treeFocusNode: null),
  'highlightStyle': () => DirectoryTreeLabel(text: '', highlightStyle: null),
  'maxLines': () => DirectoryTreeLabel(text: '', maxLines: 1),
  'confirmLabel': () =>
      showDirectoryTreePicker(context: _context, tree: _tree, confirmLabel: ''),
  'folderOpen': () => _icons.folderOpen,
  'BuildContext': () => BuildContext,
  'Builder': () => Builder,
  // The skills' own examples, compiled in this file.
  'watchRows': () => watchRows,
  'composedExplorer': () => composedExplorer,
  'DraggableExplorer': () => DraggableExplorer,
  'GlobalKey': () => GlobalKey,
  'State': () => State,
  'currentState': () => GlobalKey<State<StatefulWidget>>().currentState,
  'DirectoryTreeContextMenuState': () => DirectoryTreeContextMenuState,
  'Text': () => Text,
  'debugPrint': () => debugPrint,
  'CustomScrollView': () => CustomScrollView,
  'slivers': () => CustomScrollView(slivers: const []),
};

/// Removed 1.x names that the skills mention as what not to write.
const Set<String> _v1Names = {
  'AlphaSortDelegate',
  'ClearSelectionIntent',
  'CollapseNodeIntent',
  'ContextMenuDelegate',
  'DirectoryTreeAction',
  'DirectoryTreeDefaults',
  'ExpandNodeIntent',
  'ExpanderBuilder',
  'ExpansionController',
  'ExpansionSet',
  'FolderSelection',
  'IconProvider',
  'MaterialContextMenuDelegate',
  'MaterialIconProvider',
  'NodeAction',
  'NodeBuilder',
  'NodeType',
  'NodeVisualState',
  'RevealNodeIntent',
  'SelectOnlyIntent',
  'SelectionController',
  'SelectionSet',
  'SelectionShortcuts',
  'SortDelegate',
  'ToggleNodeIntent',
  'TreeBuilder',
  'TreeData',
  'TreeNodeTile',
  'VisibleNode',
  'addAutomaticKeepAlives',
  'allowMultiple',
  'ancestorChain',
  'anchorId',
  'autoExpandVisibleRoot',
  'childIds',
  'compileFilter',
  'contextMenuDelegate',
  'deselectSubtree',
  'diffVisibleNodes',
  'entryId',
  'expandedIds',
  'expanderBuilder',
  'expanderGap',
  'expansions',
  'filterQuery',
  'findByVirtualPath',
  'flattenStrategy',
  'focusColor',
  'folderSelection',
  'foldersOnly',
  'fullPath',
  'icon',
  'indentGuides',
  'initiallyExpanded',
  'insertIndicesAsc',
  'metadata',
  'multi',
  'nodeBuilder',
  'nodeId',
  'nodeIdForEntryId',
  'onDoubleTap',
  'onInvoke',
  'onTap',
  'onTertiaryTap',
  'pageJumpSize',
  'parentId',
  'performBatch',
  'preserveScrollOnChanges',
  'recursive',
  'removeIndicesDesc',
  'reseedFromCore',
  'retainWhere',
  'revealAndScroll',
  'revealAndSelect',
  'revealByEntryId',
  'rootId',
  'roundedCorners',
  'rowHeight',
  'schedulePreserveScrollOffset',
  'seedSelectionFromCore',
  'selectOnly',
  'selectRange',
  'selectSubtree',
  'selectedIds',
  'selectionColor',
  'shortcutsAutofocus',
  'showExpandCollapse',
  'sourcePath',
  'state',
  'subtitle',
  'themed',
  'toId',
  'toggleSelection',
  'tryPreserveState',
  'virtualPath',
  'visibleNodes',
  'visibleRootId',
  'wrapWithMenu',
};

/// Words in inline code that are not API names: literals, generic type
/// parameters, package and file names, lint names, the search syntax
/// keywords and terms the skills quote, and the semantics hint text.
const Set<String> _notApi = {
  'T',
  'true',
  'false',
  'null',
  'dart',
  'io',
  'lock',
  'design',
  'directory_tree',
  'flutter_directory_tree',
  'unused_result',
  'type',
  'ext',
  'dir',
  'main',
  'md',
  'test',
  'lib',
  'Level',
  // The pubspec key (`flutter:`), the package URI scheme, and folder names
  // the examples use.
  'flutter',
  'package',
  'repo',
  'docs',
  // A State lifecycle method, protected outside State subclasses.
  'initState',
};
