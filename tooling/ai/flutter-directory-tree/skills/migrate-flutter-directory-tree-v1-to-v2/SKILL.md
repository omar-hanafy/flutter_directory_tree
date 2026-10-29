---
name: migrate-flutter-directory-tree-v1-to-v2
description: Use when upgrading a Flutter project from flutter_directory_tree 1.x to 2.0, or fixing analyzer errors after that bump - TreeBuilder and TreeData replaced by DirectoryTree, string ids replaced by NodeId paths, the removed ExpansionController, SelectionController, SelectionShortcuts, TreeNodeTile, ContextMenuDelegate, and IconProvider, nodeBuilder to rowBuilder, rebuild and revealAndScroll replacements, the picker's allowMultiple and foldersOnly, the dart fix theme renames (rowHeight, indent), SelectionMode.multi, and behavior changes that compile but do nothing, such as dropped immutable state values.
---

# Migrate flutter_directory_tree 1.x to 2.0

2.0 is a rewrite on directory_tree 2.0. Only seven pure renames are
automated by `dart fix`; everything else is a manual change, because 1.x
used string ids and mutable sub-controllers and 2.0 uses `NodeId` paths
and immutable state values. Several 1.x calls still compile in 2.0 and
silently do nothing: hunt for them explicitly (see the behavior
checklist).

## Preconditions

1. Clean git working tree; migrate on a branch. Never reset user work
   without explicit confirmation.
2. Run the tests before migrating and record the baseline.
3. Versions: `flutter --version` must show Flutter 3.47.7 or later
   (Dart 3.13.5 or later). 2.0 depends on `directory_tree` 2.x; a project
   that also depends on directory_tree 1.x directly must move it too
   (its own migration guide covers the core types).
4. Find every use: `grep -rnE "flutter_directory_tree|directory_tree" lib/ test/`.

## Ordered steps

1. Set `flutter_directory_tree: ^2.0.0` and run `flutter pub get`.
2. Run `dart fix --dry-run`, then `dart fix --apply`. It rewrites:

   | 1.x | 2.0 |
   |---|---|
   | `DirectoryTreeThemeData(indent: ...)`, `copyWith(indent: ...)` | `indentWidth:` |
   | `DirectoryTreeThemeData(rowHeight: ...)`, `copyWith(rowHeight: ...)` | `rowExtent:` |
   | `ListDiff.removeIndicesDesc` | `ListDiff.removedIndices` |
   | `ListDiff.insertIndicesAsc` | `ListDiff.insertedIndices` |
   | `TreeEntry.fullPath` | `TreeEntry.path` |

   It does not rename reads of the theme fields (`theme.indent`,
   `theme.rowHeight`: use `DirectoryTreeTheme.of(context).indentWidth!`
   and `.rowExtent!`), `super.indent` and `super.rowHeight` in a theme
   subclass, `SelectionMode.multi` (becomes `SelectionMode.multiple`), or
   calls whose receiver no longer exists (replace `diffVisibleNodes` first,
   then run `dart fix --apply` again).
3. Trees: replace `TreeBuilder().build(entries: ...)` with
   `DirectoryTree.fromPaths(paths)` or `DirectoryTree<T>.build(entries)`
   with `TreeEntry.file(path, data: ...)` and
   `TreeEntry.directory(path)`. The path is the identity; 1.x `id`,
   `name`, and `metadata` become the path and typed `data`. 1.x was
   case-insensitive; to keep that pass
   `options: const TreeOptions(paths: PathPolicy.caseInsensitive)`.
4. Controller: `DirectoryTreeController(data: ...)` becomes `tree:`;
   `expansions:` becomes `expansion:` (`ExpansionState`); the `selection:`
   argument is a `SelectionState`. String ids become `NodeId`s from
   `tree.idOf(path)`, `node.id`, or `row.id`. Replace sub-controller calls
   with controller commands (table below).
5. View: remove `SelectionShortcuts` (the view has the keyboard built in).
   Move click handling out of `nodeBuilder` into the view (`onActivate`,
   `onRowTap`, `selectOnTap`, `expandOnTap`). Turn `nodeBuilder` into a
   `rowBuilder` that returns `DirectoryTreeRow(details: details, ...)`, or
   drop it.
6. Menus and icons: `ContextMenuDelegate` becomes `contextMenuBuilder:
   (context, details) => [MenuItemButton(...)]`; `IconProvider` becomes the
   theme's `iconSet` or the row's `leading` slot.
7. Theme: rename what `dart fix` left, then check the new defaults (rows
   are 36 at standard density, 28 compact, at least 48 on touch; indent
   guides are drawn).
8. Picker: `showDirectoryTreePicker(context:, tree:, mode:, multiple:)`
   returns `null` on cancel and a list of nodes otherwise.
9. Walk the behavior checklist, run `flutter analyze` and the tests, and
   compare with the baseline.

```dart
// flutter_directory_tree 1.x
final controller = DirectoryTreeController(
  data: TreeBuilder().build(entries: const [
    TreeEntry(id: 'main', name: 'main.dart', fullPath: '/repo/lib/main.dart'),
  ]),
  selection: SelectionController(mode: SelectionMode.multi),
);
final view = SelectionShortcuts(
  controller: controller,
  onActivate: (node) => debugPrint('open ${node.sourcePath}'),
  child: DirectoryTreeView(
    controller: controller,
    nodeBuilder: (context, node, state) => TreeNodeTile(
      node: node,
      state: state,
      title: Text(node.name),
      onTap: () => controller.selectOnly(node.id),
    ),
  ),
);
```

```dart
Widget migratedView(DirectoryTreeController<Object?> controller) {
  return DirectoryTreeView(
    controller: controller, // tree: DirectoryTree.fromPaths([...])
    onActivate: (row) => debugPrint('open ${row.node.path}'),
  );
}
```

## Controller calls

| 1.x | 2.0 |
|---|---|
| `controller.rebuild(next)` | `controller.tree = next` (state kept by id) |
| `rebuild(next, tryPreserveState: false)` | `tree = next`, then `expansion = const ExpansionState.collapsed()` and `clearSelection()` |
| `expand(id, recursive: true)` | `expandSubtree(id)` |
| `toggle(id)` | `toggleExpansion(id)` |
| `selectOnly(id)` | `select(id)` (also focuses and scrolls; `focus: false` to not) |
| `toggleSelection(id)` | `toggleSelected(id)` |
| `selectRange(anchorId: a, toId: b)` | `select(a, focus: false)`, then `extendSelection(b)` |
| `selectSubtree(id)`, `deselectSubtree(id)` | `setChecked(id, checked: true)`, `setChecked(id, checked: false)` (checks, not the selection) |
| `folderSelection(controller, id)` | `controller.checkStateOf(id)` |
| `expansions.isExpanded(id)` | `controller.isExpanded(id)` |
| `expansions.expandAll(ids)` | `controller.expansion = controller.expansion.expandAll(ids)` |
| `selection.selectedIds` | `controller.selection.selected`, or `controller.selectedNodes` |
| `selection.clear()` | `controller.clearSelection()` |
| `filterQuery` | `query` |
| `visibleNodes` | `rows` (`row.label`, `row.depth`, `row.node.path`) |
| `revealAndScroll(nodeId:, scrollController:, rowExtent:)` | `reveal(id, select: true, alignment: 0)` |
| `nodeIdForEntryId(entryId)`, `revealByEntryId(...)` | `tree.idOf(path)`, `revealPath(path, select: true)` |

The full table, including intents, the picker, every theme field, and
the re-exported core types, is in
[references/v1-to-v2-api-mapping.md](references/v1-to-v2-api-mapping.md).

## Behavior checklist

Search first; most projects hit only some of these.

```bash
grep -rnE "\.(selection|expansion)\.(clear|select|toggle|expand|collapse|setExpanded|addAll|removeAll)\(" lib/ test/
grep -rnE "NodeId\(|expandAll\(|collapseAll\(|showDirectoryTreePicker|SelectionShortcuts|DirectoryTreeToolbar|onActivate|autofocus" lib/ test/
grep -rnE "rowHeight|indent\b|guideColor|hoverColor|animationDuration|removedIndices|insertedIndices" lib/ test/
```

| Compiles in 2.0, but | Fix |
|---|---|
| `controller.selection.clear()`, `controller.expansion.expand(id)` return a new value and change nothing (only an `unused_result` warning) | Call `clearSelection()`, `expand(id)`, or assign the computed value |
| `NodeId('main')` from a stored 1.x id matches no node, and unknown ids are ignored silently | Drop stored 1.x ids or map them to paths with `tree.idOf(path)` |
| `controller.expandAll()` opens every folder | For a list of ids: `controller.expansion = controller.expansion.expandAll(ids)` |
| The picker's default `mode` is `DirectoryTreePickerMode.files`, which rejects folders | Pass `mode: DirectoryTreePickerMode.any` where 1.x had no `foldersOnly` |
| A new controller starts collapsed with an empty selection in multiple mode (1.x builder defaults opened every folder and selected every file; 1.x selection defaulted to single mode) | Pass `expansion:` and `selection:` explicitly |
| Paths are case-sensitive: names that differ only in case become separate nodes | `TreeOptions(paths: PathPolicy.caseInsensitive)` |
| `select`, `toggleSelected`, `extendSelection`, and `reveal` move the keyboard focus and scroll | Pass `focus: false` (and `scroll: false` for `reveal`) |
| A click selects and toggles folders; double-click activates | `selectOnTap: false`, `expandOnTap: false`, handle `onRowTap` |
| In single mode, `toggleSelected` on the selected row clears it | Use `select(id)` to keep it |
| `autofocus` defaults to false (1.x `SelectionShortcuts` and the panel defaulted to true) | Pass `autofocus: true` |
| `onActivate` receives a `TreeRow` and runs for folders too, after the toggle; Enter on a file without `onActivate` does nothing (1.x toggled its selection) | Branch on `row.node.isFile` |
| Wrapping a 2.0 view in `DirectoryTreeKeyboard` adds a second keyboard layer | Remove the wrapper |
| `DirectoryTreeToolbar(controller: c)` shows no search field | Add a `DirectoryTreeSearchField`, or use `DirectoryTreePanel` |
| `collapseAll()` keeps the top-level rows visible | Nothing, unless a test expected one row |
| Guides are drawn by default; `rowExtent` is 36 at standard density, not 28 | `guideStyle: DirectoryTreeGuideStyle.none`, an explicit `rowExtent` |
| `ListDiff` index lists are unmodifiable, so `removedIndices.sort()` throws | Copy the list first |
| The picker returns `null` on cancel (1.x returned an empty set) and never changes your controller | Handle `null`; pass `initialSelection` and `initialExpansion` to carry state in |

```dart
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
```

## Recipes for removed features

- Initial state from 1.x node flags (every folder open, every file
  selected): pass `expansion: const ExpansionState.expanded()` and
  `selection:` or `checks:` built with
  `const SelectionState.empty(mode: SelectionMode.multiple).addAll(ids)`.
- Lookup by your own key (`nodeIdForEntryId`): keep the key in the
  entry's `data` and build `{for (final node in tree.nodes) ?node.data:
  node.id}` once per tree.
- Custom expander (`expanderBuilder`): the `expander` slot of
  `DirectoryTreeRow`, or `DirectoryTreeExpander(details: details)`.
- Middle-click (`onTertiaryTap`): wrap `DirectoryTreeRow` in a
  `GestureDetector(onTertiaryTapUp: ...)` in the `rowBuilder`.
- Subtitles: rows are one line; use the `trailing` slot.
- Fixed page size (`pageJumpSize`): map `MoveTreeFocusIntent` in an
  `Actions` widget to `controller.moveFocus(intent.move, selection:
  intent.selection, pageSize: 10)`.
- Listening to one kind of change (1.x sub-controllers): listen to the
  controller and compare with `identical(controller.selection, last)`.
- Sorting (`flattenStrategy`): rebuild the tree with
  `options: controller.tree.options.copyWith(order: TreeOrder.alphabetical)`.
- Menus from another design system (`ContextMenuDelegate.wrapWithMenu`):
  `onRowSecondaryTap: (row, globalPosition) => ...` without
  `contextMenuBuilder`.

## Verification

1. `flutter analyze` reports no errors, and no `unused_result` warning on
   an `ExpansionState` or `SelectionState` (each one is a state change
   that never happened).
2. Run the full test suite and compare with the baseline; check each new
   failure against the behavior checklist before changing a test.
3. Run the app: click, Shift-click, keyboard arrows, Enter, the context
   menu, and the picker, since most of those moved into the view.

## Failure handling

- `dart fix --apply` changes nothing: the project still resolves 1.x;
  check `pubspec.lock` and re-run `flutter pub get`.
- Version solving fails: the Flutter SDK is older than 3.47.7, or another
  dependency pins `directory_tree` 1.x.
- "The named parameter 'data' isn't defined": the controller takes
  `tree:` now.
- Undefined `TreeBuilder`, `ExpansionController`, `SelectionController`,
  `SelectionShortcuts`, `TreeNodeTile`, `NodeVisualState`: removed; see the
  mapping reference.
- For everything not covered here, the package ships MIGRATION.md in its
  root (find it through the `flutter_directory_tree` entry of
  `.dart_tool/package_config.json`), with compiled examples for every
  recipe.
