# flutter_directory_tree 1.x to 2.0 API mapping

Every 1.x method that took a `String` id takes a `NodeId` in 2.0: get one
from `tree.idOf(path)`, `node.id`, or `row.id`. "Removed" names the
alternative.

## DirectoryTreeController

| 1.x | 2.0 | Notes |
|---|---|---|
| `DirectoryTreeController` | `DirectoryTreeController<T>` | `T` is the type of the entries' `data` |
| `data:` | `tree:` | Optional; empty tree by default |
| `expansions:` | `expansion:` (`ExpansionState`) | `ExpansionController(initiallyExpanded: ids)` becomes `ExpansionState.withExpanded(ids)` |
| `selection:` | `selection:` (`SelectionState`) | Default multiple mode; 1.x defaulted to single |
| `flattenStrategy:` | Removed | `TreeOptions(order: ...)` on the tree; filters go to `query` and `filter` |
| `seedSelectionFromCore:`, `autoExpandVisibleRoot` | Removed | Pass `selection:`, `checks:`, or `expansion: ExpansionState.withExpanded(tree.roots)` |
| `data` | `tree` | Settable; `data.nodes[id]` becomes `tree[id]` |
| `expansions` | `expansion` plus controller commands | |
| `selection` | `selection` (`SelectionState`) plus commands | Same name, different type |
| `filterQuery` | `query` | Richer syntax; clearing restores the earlier expansion |
| `visibleNodes` | `rows` (`TreeRows<T>`) | |
| `rebuild(next)` | `tree = next`, `updateTree((builder) => ...)` | State always kept by id |
| `rebuild(next, reseedFromCore: true)` | Removed | Compute the states and assign them |
| `reveal(nodeId:, virtualPath:, select:)` | `reveal(id, select: ...)`, `revealPath(path, ...)` | Focuses and scrolls by default |
| `revealAndScroll(...)` | `reveal(id, alignment: 0, duration: ...)` | No scroll controller or row extent |
| `expand(id)`, `collapse(id)` | same | `expand` starts a lazy load |
| `expand(id, recursive: true)`, `collapse(id, recursive: true)` | `expandSubtree(id)`, `collapseSubtree(id)` | |
| `toggle(id)` | `toggleExpansion(id)` | |
| `selectOnly(id)` | `select(id, {focus})` | |
| `toggleSelection(id)` | `toggleSelected(id, {focus})` | Single mode: toggling the selected id clears it |
| `selectRange(anchorId:, toId:)` | `extendSelection(id, {focus})` | Uses the anchor of `select` |
| `clearSelection()` | `clearSelection()` | Also clears the anchor |
| `selectSubtree(id)`, `deselectSubtree(id)` | `setChecked(id, checked: true/false)` | Checks live in `checks` |
| `nodeIdForEntryId(entryId)` | `tree.idOf(path)` | Ids come from paths |
| `revealByEntryId(entryId, select:)` | `revealPath(path, select:)` | |
| `indexOfNode(id)` | `rows.indexOfNode(id)` | |
| `dispose()` | `dispose()` | Also drops running loads |

## ExpansionController and SelectionController (removed)

| 1.x | 2.0 |
|---|---|
| `ExpansionController(state: set)` | `ExpansionState.withExpanded(ids)` |
| `expansions.performBatch(updates)` | compute one state and assign it once |
| `expansions.isExpanded(id)` | `controller.isExpanded(id)` (effective) or `controller.expansion.isExpanded(id)` (requested) |
| `expansions.setExpanded(id, true)` | `controller.expand(id)` |
| `expansions.expandAll(ids)` | `controller.expansion = controller.expansion.expandAll(ids)` |
| `expansions.collapseAll()` | `controller.collapseAll()` |
| `expansions.expandedIds` | `controller.expansion.exceptions`, `toJson()` |
| `expansions.retainWhere(test)` | automatic on a new tree; `ExpansionState.prune(tree)` |
| `SelectionController(mode:, state:)` | `SelectionState.empty(mode: ...)`, `SelectionState(mode:, selected:, anchor:)` |
| `selection.mode` | `controller.selectionMode` |
| `selection.isSelected(id)` | `controller.isSelected(id)` |
| `selection.selectedIds` | `controller.selection.selected`, `controller.selectedNodes` |
| `selection.selectOnly(id)`, `toggle(id)`, `clear()` | `controller.select(id)`, `toggleSelected(id)`, `clearSelection()` |
| `selection.addAll(ids)`, `removeAll(ids)` | `controller.selection = controller.selection.addAll(ids)` |

## Rows, menus, icons, intents

| 1.x | 2.0 |
|---|---|
| `NodeBuilder` `(context, node, state)` | `DirectoryTreeRowBuilder<T>` `(context, details)` |
| `NodeVisualState` | `DirectoryTreeRowDetails<T>` (`details.row.isExpanded`, `details.isSelected`, `details.row.depth`, `details.isHovered`; 1.x `isFocused` is `details.isSelected && details.hasFocus`) |
| `TreeNodeTile(node:, state:, leading:, title:, trailing:)` | `DirectoryTreeRow(details:, leading:, title:, trailing:)`; the row's semantics node already carries the label, so a `title` that only repeats it goes in `ExcludeSemantics` (or is dropped for the default label) |
| `TreeNodeTile(onTap:, onDoubleTap:)` | the view's `onRowTap` and `onActivate` |
| `TreeNodeTile(subtitle:)`, `onTertiaryTap` | Removed (recipes in the skill) |
| `ExpanderBuilder`, `expanderBuilder:` | `DirectoryTreeRow(expander: ...)` |
| `NodeAction` | a `MenuItemButton` from `contextMenuBuilder` (`label` to `child`, `icon` to `leadingIcon`, `onInvoke` to `onPressed`) |
| `ContextMenuDelegate`, `MaterialContextMenuDelegate` | `contextMenuBuilder:`, or `onRowSecondaryTap:` |
| `IconProvider`, `MaterialIconProvider` | `DirectoryTreeThemeData(iconSet: ...)`, `DirectoryTreeIconSet.material`, or `DirectoryTreeRow(leading: ...)` |
| `ExpandNodeIntent(id)` | `ExpandTreeNodeIntent()` (acts on the focused row) or `controller.expand(id)` |
| `ExpandNodeIntent(id, recursive: true)` | `ExpandTreeSubtreeIntent()` or `controller.expandSubtree(id)` |
| `CollapseNodeIntent(id)` | `CollapseTreeNodeIntent()` or `controller.collapse(id)` |
| `ToggleNodeIntent(id)` | `controller.toggleExpansion(id)` |
| `RevealNodeIntent(...)` | `controller.reveal(id)`, `controller.revealPath(path)` |
| `SelectOnlyIntent(id)` | `controller.select(id)` |
| `ClearSelectionIntent()` | `ClearTreeSelectionIntent()` (handled by the view: Escape) |
| `DirectoryTreeAction<T>` | Removed; map the intent type in an `Actions` widget |
| `schedulePreserveScrollOffset(...)` | Removed; the sliver keeps the first visible row in place |

## Keyboard

| 1.x | 2.0 |
|---|---|
| `SelectionShortcuts(controller:, child:)` | `DirectoryTreeView(controller: ...)` |
| `SelectionShortcuts(onActivate:)` | `DirectoryTreeView(onActivate:)` (a `TreeRow<T>`; runs for folders too) |
| `SelectionShortcuts(autofocus:)` | `autofocus:` (default false; 1.x true) |
| `SelectionShortcuts(pageJumpSize:)` | Removed; pages are one viewport |

New keys: Ctrl+arrows move without selecting (not on macOS), Escape clears
the selection, `*` opens the subtree, Shift+F10 and the menu key open the
context menu, Cmd+Up and Cmd+Down on macOS, type-ahead find. Ctrl+A
works off Apple platforms and Cmd+A on them.

## Picker, theme, widgets

| 1.x | 2.0 |
|---|---|
| `showDirectoryTreePicker(controller: c)` | `tree: c.tree, initialSelection: c.selection.selected, initialExpansion: c.expansion` |
| `allowMultiple:` | `multiple:` |
| `foldersOnly: true` / `false` | `mode: DirectoryTreePickerMode.directories` / `DirectoryTreePickerMode.any` |
| empty set on cancel | `null` on cancel; a list of nodes otherwise |
| `revealAndSelect(controller, nodeId:)` | `controller.reveal(id, select: true)` |
| `DirectoryTreeDefaults.themed(context)` | `DirectoryTreeTheme.of(context)` |
| `rowHeight:` / `indent:` | `rowExtent:` / `indentWidth:` (`dart fix`) |
| `indentGuides:` | `guideStyle:` (`DirectoryTreeGuideStyle.none` keeps the 1.x look) |
| `selectionColor:` | `selectedColor:` and `inactiveSelectedColor:` |
| `focusColor:` | `focusedBorderColor:` |
| `roundedCorners: false` | `rowBorderRadius: BorderRadius.zero` |
| `DirectoryTreePanel(nodeBuilder:)` | `DirectoryTreePanel<T>(rowBuilder:)` |
| `DirectoryTreePanel(shortcutsAutofocus:)` | `autofocus:` |
| `DirectoryTreeToolbar(hintText:)` | `DirectoryTreeSearchField(hintText:)` |
| `DirectoryTreeToolbar(showExpandCollapse: false)` | `showExpandAll: false, showCollapseAll: false` |
| `DirectoryTreeView(nodeBuilder:)` | `rowBuilder:` |
| `DirectoryTreeView(expanderSize:)` | `DirectoryTreeThemeData(expanderSize:)` |
| `DirectoryTreeView(contextMenuDelegate:)` | `contextMenuBuilder:`, `onRowSecondaryTap:` |
| `expanderGap:`, `addAutomaticKeepAlives:`, `preserveScrollOnChanges:` | Removed |

## Re-exported core types

| 1.x | 2.0 |
|---|---|
| `TreeBuilder().build(entries:)` | `DirectoryTree.build(entries, options: TreeOptions(...))`, `DirectoryTree.fromPaths(paths)` |
| `TreeData` | `DirectoryTree<T>` (immutable) |
| `TreeData.visibleRootId`, `rootId` | `tree.roots`, `tree.rootNodes` |
| `TreeNode.parentId`, `childIds`, `type` | `parent`, `DirectoryNode.children`, `kind` (`isFile`, `isDirectory`) |
| `TreeNode.sourcePath`, `virtualPath` | `path` |
| `NodeType.folder` | `TreeNodeKind.directory` |
| `TreeEntry(id:, name:, fullPath:, metadata:)` | `TreeEntry.file(path, data:)`, `TreeEntry.directory(path, data:)` |
| `VisibleNode` | `TreeRow<T>` (`name` becomes `label`) |
| `SortDelegate`, `AlphaSortDelegate` | `TreeOptions(order: TreeOrder.alphabetical)`, `TreeOrder.by<T>(...)` |
| `compileFilter(query)` | `TreeQuery.parse(query)`, `TreeFilter.where<T>(...)` |
| `ExpansionSet`, `SelectionSet` | `ExpansionState`, `SelectionState` (immutable) |
| `SelectionMode.multi` | `SelectionMode.multiple` |
| `FolderSelection` | `CheckState` (`unchecked`, `partial`, `checked`) |
| `diffVisibleNodes(a, b)` | `ListDiff.compute(a, b, keyOf: (row) => row.id)` |
| `ancestorChain(data, id)` | `tree.ancestorsOf(id)` |
| `findByVirtualPath(data, path)` | `tree.nodeAt(path)`, `tree.idOf(path)` |
