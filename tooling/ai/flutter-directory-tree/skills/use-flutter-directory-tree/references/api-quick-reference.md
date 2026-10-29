# flutter_directory_tree 2.x API quick reference

Signatures as shipped in 2.0.0. `T` is the type of each entry's `data`.
Everything comes from
`import 'package:flutter_directory_tree/flutter_directory_tree.dart';`
except `FileSystemTreeLoader` and `DirectoryScanner`, which come from
`package:flutter_directory_tree/io.dart` (not available on the web).

## DirectoryTreeController<T> (a ChangeNotifier)

```text
DirectoryTreeController({
  DirectoryTree<T>? tree,                       // empty tree when null
  ExpansionState expansion = const ExpansionState.collapsed(),
  SelectionState selection = const SelectionState.empty(mode: SelectionMode.multiple),
  SelectionState checks = const SelectionState.empty(mode: SelectionMode.multiple),
  bool Function(TreeNode<T> node)? selectable,
  String query = '',
  bool caseSensitiveQuery = false,
  TreeFilter? filter,
  bool revealMatches = true,
  bool compactFolders = false,
  bool showRoots = true,
  DirectoryChildrenLoader<T>? loadChildren,
  DirectoryLoadErrorCallback? onLoadError,
})
```

| Member | Kind | Notes |
|---|---|---|
| `tree` | get/set | Setting keeps state by id; `updateTree(void Function(DirectoryTreeBuilder<T>))` edits it |
| `rows` | get | `TreeRows<T>`, a `List<TreeRow<T>>` of the visible rows |
| `lastRowsChange` | get | `TreeRowsChange`; read it in a listener |
| `expansion` | get/set | The requested `ExpansionState`; persist `toJson()` |
| `isExpanded(id)` | query | The effective state on screen |
| `isExpandable(id)` | query | Whether the row should draw an arrow |
| `expand(id)`, `collapse(id)`, `toggleExpansion(id)` | command | `expand` on a lazy folder starts its load |
| `expandAll()`, `collapseAll()` | command | O(rows); start no loads |
| `expandSubtree(id)`, `collapseSubtree(id)` | command | |
| `reveal(id, {focus = true, select = false, scroll = true, alignment, duration, curve})` | command | Returns whether the node has a row |
| `revealPath(path, ...)` | command | Returns the `NodeId` or `null` |
| `selection` | get/set | `SelectionState` |
| `selectionMode` | get/set | `SelectionMode.single` or `SelectionMode.multiple` |
| `isSelected(id)`, `isSelectable(id)`, `selectedNodes` | query | `selectedNodes` is in display order |
| `select(id, {focus = true})` | command | A plain click; sets the anchor |
| `toggleSelected(id, {focus = true})` | command | Ctrl or Cmd click |
| `extendSelection(id, {focus = true})` | command | Shift click, from the anchor |
| `selectAll()`, `clearSelection()` | command | `selectAll` only in multiple mode |
| `checks` | get/set | `SelectionState` with tri-state folder semantics |
| `checkStateOf(id)` | query | `CheckState.unchecked`, `partial`, `checked`; O(1) after one O(n) count |
| `toggleChecked(id)`, `setChecked(id, checked: bool)` | command | Checks or unchecks every leaf below |
| `checkAll()`, `uncheckAll()` | command | `checkAll` only in multiple mode |
| `checkedLeaves`, `checkedRoots` | query | Files and empty folders; outermost fully checked nodes |
| `focusedId`, `focusedRow`, `focusedIndex` | query | The keyboard cursor row |
| `focus(id, {scroll = true})` | command | Returns false when the node has no row |
| `moveFocus(TreeFocusMove move, {TreeSelectionUpdate selection = TreeSelectionUpdate.replace, int? pageSize})` | command | Returns whether the focus moved |
| `query`, `caseSensitiveQuery`, `filter`, `revealMatches` | get/set | A new query or filter runs the filter once over the tree |
| `parsedQuery`, `isFiltering`, `matchRangesOf(row)` | query | |
| `compactFolders`, `showRoots` | get/set | Display options |
| `loadStatusOf(id)`, `loadErrorOf(id)` | query | `DirectoryLoadStatus` |
| `loadChildren(id)`, `reloadChildren(id)` | command | Futures that never complete with an error |
| `ensureVisible(id, {duration, curve, alignment})`, `globalRowRect(index)` | view | Work through the attached views |
| `attachViewport`, `detachViewport` | view | For custom views implementing `DirectoryTreeViewport` |

Enums: `TreeFocusMove` (`next`, `previous`, `first`, `last`, `parent`,
`firstChild`, `pageDown`, `pageUp`), `TreeSelectionUpdate` (`replace`,
`extend`, `keep`), `DirectoryLoadStatus` (`notLoaded`, `loading`,
`loaded`, `failed`).

`typedef DirectoryChildrenLoader<T> = Future<Iterable<TreeEntry<T>>>
Function(DirectoryNode<T> directory)`;
`typedef DirectoryLoadErrorCallback = void Function(NodeId directory,
Object error, StackTrace stackTrace)`.

`TreeRowsChange`: `isReset`, `index`, `removed`, `inserted`, `previous`
(the replaced `TreeRows`, or `null`).

Listening to row changes (read `lastRowsChange` in the listener):

```dart
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
```

## Loads and reloads

- `expand(id)` starts a load when the folder has no children and is
  `notLoaded` or `failed`, or when it has children that wait to be listed
  again; it also retries a failed load of an already open folder. In a
  compacted row it loads the outermost folder of the row that needs it, and
  no load starts while the filter hides the row.
- `reloadChildren(id)`: the folder keeps its rows (status `loading`), and
  the loads and statuses below it stay, until its listing arrives. Then
  the loads still running below are discarded, the statuses below start
  over, and the listing replaces the folder's contents in one change:
  expansion, selection, checks, and focus stay with every node that still
  exists, a checked folder stays checked (its new leaves too), and while
  filtering a folder the user collapsed stays collapsed.
- A subfolder that the listing returns without contents but that had
  contents (a loader that lists one level) keeps them and is listed again:
  at once when open, even while the filter hides it (so new matches in it
  show), otherwise on its next expand.
- A failed reload keeps everything (status `failed`); `expand` or
  `loadChildren` retries.
- A new tree (the `tree` setter or `updateTree`) restarts the load
  statuses and discards running loads. A folder whose load was discarded
  loads again on its next expand, at once when open. A folder with contents
  that waits for a new listing (its reload was discarded or failed, or a
  reload above it kept its contents) stays marked and is listed on its next
  expand.
- A compacted row's `loadStatus` is `loading` while any folder above its
  node in the row loads and `failed` when one of those loads failed.

## Core types (re-exported from package:directory_tree)

- `DirectoryTree.fromPaths(paths, {options})` (a trailing `/` makes a
  directory), `DirectoryTree<T>.build(entries, {options})`,
  `DirectoryTree<T>.empty()`. Members: `roots`, `rootNodes`, `nodes`
  (pre-order), `files`, `directories`, `entries`, `options`, `tree[id]`,
  `contains(id)`, `idOf(path)` (the id of any parseable path, contained
  or not), `nodeAt(path)` (`null` when absent), `childrenOf(id)`,
  `parentOf(id)`, `ancestorsOf(id)`, `descendantsOf(id)`,
  `rebuild((builder) => ...)`.
- `TreeEntry.file(path, data: x)`, `TreeEntry.directory(path, data: x)`.
- `DirectoryTreeBuilder<T>`: `addFile(path, data:)`,
  `addDirectory(path, data:)`, `add(entry)`, `remove(path)`,
  `removeWhere(test)`, `contains(path)`.
- `TreeNode<T>` (`FileNode<T>` or `DirectoryNode<T>`): `id`, `path` (a
  `TreePath`; `path.toString()`, `path.name`, `path.extension`), `name`,
  `parent`, `depth`, `data`, `isFile`, `isDirectory`, `isRoot`;
  `DirectoryNode.children`.
- `TreeRow<T>`: `node`, `id`, `depth`, `label`, `isExpanded`,
  `hasChildren`, `isLast`, `isMatch`, `guides`, `chain` (the nodes of a
  compacted row).
- `TreeOptions(paths: PathPolicy.caseInsensitive, order:
  TreeOrder.alphabetical, roots: TreeRoots.fixed([...]))`; `copyWith`.
  Roots: `TreeRoots.minimal()` (default: the outermost folders that hold
  entries), `TreeRoots.commonAncestor()` (one root per path root, the
  deepest folder that holds everything), `TreeRoots.fixed(paths)`,
  `TreeRoots.filesystem()` (each path root, such as / or a drive, and
  every folder below it).
  `TreeOrder.directoriesFirst` is the default; `TreeOrder.by<T>(compare)`
  sorts by your data.
- `ExpansionState.collapsed()`, `.expanded()`, `.withExpanded(ids)`,
  `.withCollapsed(ids)`, `.fromJson(json)`; `toJson()`, `isExpanded(id)`,
  `expandAll(ids)`, `collapseAll(ids)`, `setExpanded(id, expanded:)`.
- `SelectionState.empty({mode = SelectionMode.single})`,
  `SelectionState(mode:, selected:, anchor:)`; `selected`, `anchor`,
  `addAll(ids)`, `removeAll(ids)`, `toJson()`, `SelectionState.fromJson`.
- `TreeQuery.parse(text, caseSensitive: false)`,
  `TreeFilter.where<T>((node) => ...)`, `and`, `or`, `negate`.
- `NodeId(value)` wraps a stored `NodeId.value`; derive ids from paths
  with `tree.idOf(path)` instead.

## Widgets

`DirectoryTreeView<T>({required controller, rowBuilder, checkboxMode =
DirectoryTreeCheckboxMode.none, expandOnTap = true, selectOnTap = true,
onRowTap, onActivate, onRowSecondaryTap, contextMenuBuilder, dragAndDrop,
focusNode, autofocus = false, shortcuts, typeAhead = true,
scrollController, padding, physics, showScrollbar = true, semanticLabel,
levelSemanticsHint, activateSemanticsLabel = 'Open',
loadingSemanticsLabel = 'Loading', loadFailedSemanticsLabel = 'Failed to
load', emptyBuilder, selectionFollowsFocus = true})`

- `onRowTap`, `onActivate`: `ValueChanged<TreeRow<T>>`.
- `onRowSecondaryTap`: `void Function(TreeRow<T> row, Offset
  globalPosition)`.
- `shortcuts` replaces the defaults entirely (spread
  `DirectoryTreeShortcuts.defaults(platform:, textDirection:)` to extend).
- `emptyBuilder`: shown when there are no rows.

`DirectoryTreePanel<T>`: every `DirectoryTreeView` parameter plus `title`
(`Widget?`), `actions` (`List<Widget>`), `toolbar` (replaces the toolbar),
`showToolbar = true`, `showSearch = true`, `searchHintText`,
`expandAllTooltip = 'Expand all'`, `collapseAllTooltip = 'Collapse
all'`.

`SliverDirectoryTree<T>({required controller, rowBuilder, rowDecorator,
checkboxMode, expandOnTap = true, selectOnTap = true, onRowTap,
onActivate, onRowSecondaryTap, secondaryTapOnLongPress = true,
levelSemanticsHint, activateSemanticsLabel, loadingSemanticsLabel,
loadFailedSemanticsLabel})`

`DirectoryTreeKeyboard<T>({required controller, required child,
focusNode, autofocus = false, shortcuts, onActivate, checkboxMode,
typeAhead = true, typeAheadTimeout = const Duration(seconds: 1),
selectionFollowsFocus = true})`

`DirectoryTreeContextMenu<T>({required controller, required builder,
required child, selectOnOpen = true})`; open it from below with
`DirectoryTreeContextMenu.maybeOf<T>(context)?.open(row: row,
globalPosition: position)`; `close()`, `isOpen`.

`DirectoryTreeDragAndDropScope<T>({required controller, required
dragAndDrop, required child, onLongPressWithoutDrag})`; the sliver needs
`rowDecorator: DirectoryTreeDragAndDropScope.decorateRow`.

`DirectoryTreeSearchField({required controller, focusNode,
treeFocusNode, autofocus = false, hintText, decoration, debounce = const
Duration(milliseconds: 120)})`

`DirectoryTreeToolbar({required controller, title, actions, showExpandAll
= true, showCollapseAll = true, showCompactFolders = false,
expandAllTooltip, collapseAllTooltip, compactFoldersTooltip})`; it has no
search field.

`DirectoryTreeRow<T>({required details, expander, leading, title,
trailing})`, `DirectoryTreeExpander<T>({required details})`,
`DirectoryTreeCheckbox<T>({required details})`,
`DirectoryTreeLabel({required text, matchRanges, style, highlightStyle,
maxLines = 1, overflow = TextOverflow.ellipsis})`,
`DirectoryTreeIndentGuides({required depth, required guides, required
isLast, style, indentWidth, color, width})`.

The sliver stack with a context menu, outermost first (the menu host
above the keyboard widget, so Shift+F10 and the menu key reach it):

```dart
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
```

With drag and drop, the scope sits above the menu host, so its
`onLongPressWithoutDrag` reaches the host through a `GlobalKey` kept in a
`State` (`maybeOf` from there finds nothing), as `DirectoryTreeView` does:

```dart
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
                rowDecorator: DirectoryTreeDragAndDropScope.decorateRow<Object?>,
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
```

## Callback types and details

- `typedef DirectoryTreeRowBuilder<T> = Widget Function(BuildContext
  context, DirectoryTreeRowDetails<T> details)`.
- `typedef DirectoryTreeRowDecorator<T> = Widget Function(BuildContext
  context, DirectoryTreeRowDetails<T> details, Widget child)`.
- `DirectoryTreeRowDetails<T>`: `controller`, `row`, `index`,
  `isSelected`, `isFocused` (the keyboard cursor row), `hasFocus` (the
  tree has keyboard focus), `isHovered`, `checkboxMode`, `checkState`
  (`null` without checkboxes), `loadStatus`, `isExpandable`,
  `matchRanges`.
- `typedef DirectoryTreeMenuBuilder<T> = List<Widget> Function(BuildContext
  context, DirectoryTreeMenuDetails<T> details)`;
  `DirectoryTreeMenuDetails<T>`: `controller`, `row`, `nodes`,
  `globalPosition`.
- `DirectoryTreeDragAndDrop<T>({required onDrop, canDrag, canDrop,
  autoExpandDelay = const Duration(milliseconds: 700), feedbackBuilder})`:
  `onDrop` takes a `DirectoryTreeDropDetails<T>` (`nodes`, `target`),
  `canDrag` takes the `List<TreeNode<T>>`, `canDrop` the drop details,
  `feedbackBuilder` the context and nodes.
- `DirectoryTreeCheckboxMode`: `none`, `checks`, `selection`.

## Accessibility

Each row is one semantics node with its label, selected, expanded, and
checked states, a level hint (`Level 1` for a top-level row), and tap,
expand, collapse, and (with `onActivate`) "Open" actions. Translate with
`semanticLabel`, `levelSemanticsHint`, `activateSemanticsLabel`,
`loadingSemanticsLabel`, and `loadFailedSemanticsLabel` on the view or
panel. With the default `rowExtent`, rows on touch platforms are at least
48 pixels tall and grow with the text scale.

## Picker

`showDirectoryTreePicker<T>({required context, required tree, mode =
DirectoryTreePickerMode.files, multiple = false, initialSelection,
initialExpansion, title, confirmLabel, showSearch = true, rowBuilder})`
returns `Future<List<TreeNode<T>>?>`.

`DirectoryTreePicker<T>({required tree, mode, multiple, initialSelection,
initialExpansion, showSearch = true, searchHintText, rowBuilder,
autofocus = false, onChanged, onConfirm})`.

`DirectoryTreePickerMode`: `files`, `directories`, `any`.

## Keyboard intents

All act on the focused row: `MoveTreeFocusIntent(TreeFocusMove move,
{selection})`, `ExpandTreeNodeIntent`, `CollapseTreeNodeIntent`,
`ExpandTreeSubtreeIntent`, `ActivateTreeNodeIntent`,
`ToggleTreeSelectionIntent`, `SelectAllTreeNodesIntent`,
`ClearTreeSelectionIntent`, `OpenTreeContextMenuIntent`.

## Theme

`DirectoryTreeThemeData` (a `ThemeExtension`; every field nullable;
`merge`, `copyWith`, `lerp`, `DirectoryTreeThemeData.fallback(theme)`):
`rowExtent`, `indentWidth` (16), `rowPadding`, `rowBorderRadius` (4),
`expanderSize` (20), `iconSize` (18), `iconSpacing`, `guideStyle`
(`DirectoryTreeGuideStyle.indent`), `guideColor`, `guideWidth`,
`hoverColor`, `selectedColor`, `inactiveSelectedColor`,
`focusedBorderColor`, `focusedBorderWidth`, `dropTargetColor`,
`labelStyle`, `selectedLabelStyle`, `dimmedLabelStyle`,
`matchHighlightStyle`, `iconColor`, `folderIconColor`, `iconSet`,
`animationDuration` (150 ms), `animationCurve`.

`DirectoryTreeTheme({required data, required child})`;
`DirectoryTreeTheme.of(context)` returns a theme with every field set.

`DirectoryTreeIconSet({required file, required folder, required
folderOpen, extensions, names})`; `DirectoryTreeIconSet.material` (the
default), `copyWith`, `iconFor(node, expanded:)`.

## File system (io.dart)

`FileSystemTreeLoader({includeHidden = false, followLinks = false,
skip})`: `loadTree(path, {options, depth = 1})` returns a
`Future<DirectoryTree<FileSystemEntity>>`; `loadChildren` is a
`DirectoryChildrenLoader<FileSystemEntity>` to pass to the controller.
`DirectoryScanner` reads a whole directory at once.
