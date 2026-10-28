import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_directory_tree/flutter_directory_tree.dart';
import 'package:flutter_directory_tree/src/search/directory_tree_toolbar.dart';
import 'package:flutter_test/flutter_test.dart';

import 'search_test_utils.dart';

Widget toolbarHost(
  Widget toolbar, {
  ThemeData? theme,
  TextDirection textDirection = TextDirection.ltr,
}) {
  return MaterialApp(
    theme: theme,
    home: Directionality(
      textDirection: textDirection,
      child: Scaffold(body: Column(children: <Widget>[toolbar])),
    ),
  );
}

final Finder expandAll = find.byIcon(Icons.unfold_more);
final Finder collapseAll = find.byIcon(Icons.unfold_less);
final Finder compactFolders = find.byIcon(Icons.merge_type);

IconButton buttonOf(WidgetTester tester, Finder icon) =>
    tester.widget(find.ancestor(of: icon, matching: find.byType(IconButton)));

/// The color the icon is painted with.
Color? iconColorOf(WidgetTester tester, Finder icon) => tester
    .widget<RichText>(
      find.descendant(of: icon, matching: find.byType(RichText)),
    )
    .text
    .style
    ?.color;

void main() {
  late DirectoryTreeController<String> controller;

  setUp(() {
    controller = DirectoryTreeController<String>(tree: sampleTree());
  });

  tearDown(() => controller.dispose());

  testWidgets('shows expand all and collapse all by default', (tester) async {
    await tester.pumpWidget(
      toolbarHost(DirectoryTreeToolbar(controller: controller)),
    );

    expect(find.byTooltip('Expand all'), findsOneWidget);
    expect(find.byTooltip('Collapse all'), findsOneWidget);
    expect(find.byTooltip('Compact folders'), findsNothing);
    expect(compactFolders, findsNothing);
  });

  testWidgets('expand all and collapse all act on the controller', (
    tester,
  ) async {
    await tester.pumpWidget(
      toolbarHost(DirectoryTreeToolbar(controller: controller)),
    );

    await tester.tap(expandAll);
    await tester.pump();
    expect(controller.expansion, const ExpansionState.expanded());
    expect(labelsOf(controller.rows), <String>[
      'repo',
      'lib',
      'src',
      'a.dart',
      'b.dart',
      'main.dart',
      'test',
      'main_test.dart',
      'README.md',
    ]);

    await tester.tap(collapseAll);
    await tester.pump();
    expect(controller.expansion, const ExpansionState.collapsed());
    expect(labelsOf(controller.rows), <String>['repo']);
  });

  testWidgets('the compact folders button switches the setting and shows '
      'it', (tester) async {
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: controller, showCompactFolders: true),
      ),
    );
    final scheme = Theme.of(tester.element(compactFolders)).colorScheme;
    expect(buttonOf(tester, compactFolders).isSelected, isFalse);
    expect(iconColorOf(tester, compactFolders), scheme.onSurfaceVariant);

    await tester.tap(compactFolders);
    await tester.pumpAndSettle();
    expect(controller.compactFolders, isTrue);
    expect(buttonOf(tester, compactFolders).isSelected, isTrue);
    expect(iconColorOf(tester, compactFolders), scheme.primary);

    await tester.tap(compactFolders);
    await tester.pumpAndSettle();
    expect(controller.compactFolders, isFalse);
    expect(buttonOf(tester, compactFolders).isSelected, isFalse);
  });

  testWidgets('the compact folders button follows changes made elsewhere', (
    tester,
  ) async {
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: controller, showCompactFolders: true),
      ),
    );

    controller.compactFolders = true;
    await tester.pump();
    expect(buttonOf(tester, compactFolders).isSelected, isTrue);

    controller.compactFolders = false;
    await tester.pump();
    expect(buttonOf(tester, compactFolders).isSelected, isFalse);
  });

  testWidgets('names every button for assistive technologies', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(
          controller: controller,
          title: const Text('Explorer'),
          showCompactFolders: true,
        ),
      ),
    );

    // The tooltip text is the label and is not announced a second time.
    expect(
      tester.getSemantics(expandAll),
      isSemantics(
        label: 'Expand all',
        tooltip: '',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getSemantics(collapseAll),
      isSemantics(
        label: 'Collapse all',
        tooltip: '',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
      ),
    );
    expect(
      tester.getSemantics(compactFolders),
      isSemantics(
        label: 'Compact folders',
        tooltip: '',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    expect(
      tester.getSemantics(find.text('Explorer')),
      isSemantics(label: 'Explorer', isHeader: true),
    );
    // No node anywhere carries the tooltips, so each name is read once.
    expect(
      find.semantics.byPredicate((node) => node.tooltip.isNotEmpty),
      findsNothing,
    );

    await tester.tap(compactFolders);
    await tester.pump();
    expect(
      tester.getSemantics(compactFolders),
      isSemantics(label: 'Compact folders', isSelected: true),
    );
    semantics.dispose();
  });

  testWidgets('the tooltip strings name the buttons', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(
          controller: controller,
          showCompactFolders: true,
          expandAllTooltip: 'Alle ausklappen',
          collapseAllTooltip: 'Alle einklappen',
          compactFoldersTooltip: 'Ordner zusammenfassen',
        ),
      ),
    );

    for (final name in <String>[
      'Alle ausklappen',
      'Alle einklappen',
      'Ordner zusammenfassen',
    ]) {
      expect(find.byTooltip(name), findsOneWidget);
      expect(find.bySemanticsLabel(name), findsOneWidget);
    }
    expect(find.byTooltip('Expand all'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a hovering mouse shows the tooltip', (tester) async {
    await tester.pumpWidget(
      toolbarHost(DirectoryTreeToolbar(controller: controller)),
    );
    expect(find.text('Collapse all'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(collapseAll));
    await tester.pumpAndSettle();

    expect(find.text('Collapse all'), findsOneWidget);
  });

  testWidgets('hides the buttons it is told to hide', (tester) async {
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(
          controller: controller,
          showExpandAll: false,
          showCompactFolders: true,
        ),
      ),
    );
    expect(expandAll, findsNothing);
    expect(collapseAll, findsOneWidget);
    expect(compactFolders, findsOneWidget);

    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(
          controller: controller,
          showExpandAll: false,
          showCollapseAll: false,
        ),
      ),
    );
    expect(find.byType(IconButton), findsNothing);
  });

  testWidgets('lays out the title, then the actions, then the buttons, '
      'mirrored right to left', (tester) async {
    for (final direction in TextDirection.values) {
      await tester.pumpWidget(
        toolbarHost(
          DirectoryTreeToolbar(
            controller: controller,
            title: const Text('Explorer'),
            actions: <Widget>[
              IconButton(onPressed: () {}, icon: const Icon(Icons.refresh)),
            ],
            showCompactFolders: true,
          ),
          textDirection: direction,
        ),
      );

      final starts = <double>[
        for (final finder in <Finder>[
          find.text('Explorer'),
          find.byIcon(Icons.refresh),
          expandAll,
          collapseAll,
          compactFolders,
        ])
          tester.getCenter(finder).dx,
      ];
      final ordered = <double>[...starts]..sort();
      expect(
        starts,
        direction == TextDirection.ltr ? ordered : ordered.reversed.toList(),
        reason: '$direction',
      );
      final edge = direction == TextDirection.ltr
          ? tester.getTopLeft(find.text('Explorer')).dx
          : 800 - tester.getTopRight(find.text('Explorer')).dx;
      expect(edge, 16, reason: '$direction');
    }
  });

  testWidgets('the title is one line of titleSmall', (tester) async {
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(
          controller: controller,
          title: Text('A rather long explorer title ' * 20),
        ),
      ),
    );
    final theme = Theme.of(tester.element(find.byType(DirectoryTreeToolbar)));
    final title = tester.widget<RichText>(
      find.descendant(
        of: find.textContaining('A rather long'),
        matching: find.byType(RichText),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(title.maxLines, 1);
    expect(title.softWrap, isFalse);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.text.style?.fontSize, theme.textTheme.titleSmall?.fontSize);
    expect(
      title.text.style?.fontWeight,
      theme.textTheme.titleSmall?.fontWeight,
    );
  });

  testWidgets('keeps an icon button height without buttons', (tester) async {
    for (final (density, height) in <(VisualDensity, double)>[
      (VisualDensity.standard, 48),
      (VisualDensity.compact, 40),
    ]) {
      await tester.pumpWidget(
        toolbarHost(
          DirectoryTreeToolbar(
            controller: controller,
            showExpandAll: false,
            showCollapseAll: false,
          ),
          theme: ThemeData(visualDensity: density),
        ),
      );
      // MaterialApp animates from the previous theme.
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(DirectoryTreeToolbar)).height,
        height,
        reason: '$density',
      );
    }
  });

  testWidgets('rebuilds only when compact folders change', (tester) async {
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: controller, showCompactFolders: true),
      ),
    );
    await tester.pumpAndSettle();
    final rebuilds = RebuildCounter.install();
    addTearDown(rebuilds.uninstall);

    controller
      ..expandAll()
      ..focus(lib)
      ..select(mainDart)
      ..selectAll()
      ..query = 'main';
    await tester.pump();
    expect(rebuilds.count, 0);

    controller.compactFolders = true;
    await tester.pump();
    expect(rebuilds.count, greaterThan(0));
  });

  testWidgets('follows a new controller', (tester) async {
    final other = DirectoryTreeController<String>(
      tree: sampleTree(),
      compactFolders: true,
    );
    addTearDown(other.dispose);
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: controller, showCompactFolders: true),
      ),
    );
    expect(buttonOf(tester, compactFolders).isSelected, isFalse);

    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: other, showCompactFolders: true),
      ),
    );
    expect(buttonOf(tester, compactFolders).isSelected, isTrue);

    // The old controller is no longer followed.
    controller.compactFolders = true;
    other.compactFolders = false;
    await tester.pump();
    expect(buttonOf(tester, compactFolders).isSelected, isFalse);
    controller.compactFolders = false;
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(expandAll);
    await tester.tap(compactFolders);
    await tester.pump();
    expect(other.expansion, const ExpansionState.expanded());
    expect(other.compactFolders, isTrue);
    expect(controller.expansion, const ExpansionState.collapsed());
    expect(controller.compactFolders, isFalse);
  });

  testWidgets('stops listening when removed', (tester) async {
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: controller, showCompactFolders: true),
      ),
    );
    await tester.pumpWidget(const SizedBox());

    // A listener left behind would call setState on a disposed state.
    controller.compactFolders = true;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final useMaterial3 in <bool>[true, false]) {
    testWidgets('works without a Material ancestor '
        '(useMaterial3: $useMaterial3)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: useMaterial3),
          home: Center(
            child: SizedBox(
              width: 400,
              child: DirectoryTreeToolbar(
                controller: controller,
                showCompactFolders: true,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      await tester.tap(expandAll);
      await tester.pump();
      expect(controller.expansion, const ExpansionState.expanded());
    });
  }

  testWidgets('Material 2: the compact folders button shows and announces '
      'its state', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      toolbarHost(
        DirectoryTreeToolbar(controller: controller, showCompactFolders: true),
        theme: ThemeData(useMaterial3: false),
      ),
    );
    final scheme = Theme.of(tester.element(compactFolders)).colorScheme;
    expect(
      tester.getSemantics(compactFolders),
      isSemantics(
        label: 'Compact folders',
        isButton: true,
        hasSelectedState: true,
        isSelected: false,
      ),
    );
    expect(iconColorOf(tester, compactFolders), isNot(scheme.primary));

    await tester.tap(compactFolders);
    await tester.pump();
    expect(
      tester.getSemantics(compactFolders),
      isSemantics(label: 'Compact folders', isSelected: true),
    );
    expect(iconColorOf(tester, compactFolders), scheme.primary);
    semantics.dispose();
  });

  test('describes its properties', () {
    final names = <String?>[
      for (final property in DirectoryTreeToolbar(
        controller: controller,
        showCompactFolders: true,
        expandAllTooltip: 'Expand',
      ).toDiagnosticsNode().getProperties())
        property.name,
    ];

    expect(
      names,
      containsAll(<String>[
        'controller',
        'showExpandAll',
        'showCollapseAll',
        'showCompactFolders',
        'expandAllTooltip',
        'collapseAllTooltip',
        'compactFoldersTooltip',
      ]),
    );
  });
}
