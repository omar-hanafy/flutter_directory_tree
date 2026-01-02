import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_directory_tree_example/main.dart';

void main() {
  testWidgets('Example app shows setup hint', (tester) async {
    await tester.pumpWidget(const DirectoryTreeExamplesApp());
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Implement buildDemoTreeData()'),
      findsOneWidget,
    );
  });
}
