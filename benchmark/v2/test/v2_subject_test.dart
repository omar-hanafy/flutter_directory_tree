import 'package:fdt_bench_harness/jit.dart';
import 'package:fdt_bench_v2/v2_subject.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs every operation once on [shape] 10k through the harness, as the JIT
/// benchmark does, and returns the records.
Future<List<Map<String, Object?>>> _runAll(
  WidgetTester tester,
  WorkloadShape shape,
) async {
  final slot = ValueNotifier<Widget?>(null);
  addTearDown(slot.dispose);
  await tester.pumpWidget(BenchHost(slot: slot));
  final records = await runBenchmark(
    BenchConfig(implementation: 'v2', shape: shape, runs: 1, warmup: 0),
    createV2Subject,
    frames: TesterFrameDriver(tester, slot),
    emit: (_) {},
  );
  await tester.pumpWidget(const SizedBox.shrink());
  return records;
}

final List<String> _frameOperations = [
  for (final operation in benchOperations)
    if (operation.kind == OperationKind.frame) operation.name,
];

void main() {
  for (final shape in WorkloadShape.values) {
    testWidgets(
      '${shape.name} 10k: every operation reports the expected counts',
      (tester) async {
        final workload = Workload.generate(shape, 10000);
        final expected = WorkloadExpectations(workload);
        final records = await _runAll(tester, shape);

        expect(records.map((r) => r['operation']), standardOperations);
        final byOperation = {for (final r in records) r['operation']: r};
        for (final record in records) {
          final operation = record['operation']! as String;
          expect(record['error'], isNull, reason: operation);
          expect(record['fingerprint'], workload.fingerprint);
          expect(expected.check(operation, record), isEmpty, reason: operation);
        }
        // 2.0.0 stores exactly the files and the folders.
        expect(
          byOperation['build']!['nodes'],
          workload.size + workload.folderCount,
        );
        // The views build only the rows on screen, not the 10k+ rows: a
        // 600 px viewport of 28 px rows shows 22 rows, and the default cache
        // extent adds about 9 on each side.
        for (final operation in _frameOperations) {
          final record = byOperation[operation]!;
          expect(record, isNot(contains('unavailable')), reason: operation);
          expect(
            record['built_rows'],
            inInclusiveRange(22, 42),
            reason: operation,
          );
        }
        expect(tester.takeException(), isNull);
      },
      semanticsEnabled: false,
    );

    test('${shape.name} 10k: toggle collapses incrementally, one splice', () {
      final workload = Workload.generate(shape, 10000);
      final expected = WorkloadExpectations(workload);
      final subject = V2Subject(workload);
      addTearDown(subject.dispose);
      final controller = subject.controller;
      final target = controller.tree.idOf(workload.toggleTarget)!;

      subject.setUp('toggle');
      for (var run = 0; run < 2; run++) {
        subject.beforeRun('toggle');
        final before = controller.rows;
        final targetIndex = before.indexOfNode(target);
        subject.run('toggle');

        // The rows after the target's block are the identical row objects,
        // moved up: only the target's row was replaced and its descendants
        // removed, without flattening the tree again.
        final change = controller.lastRowsChange;
        expect(change.isReset, isFalse, reason: 'run $run');
        expect(change.previous, same(before));
        expect(change.index, targetIndex + 1);
        expect(change.removed, expected.toggleHiddenRows);
        expect(change.inserted, 0);
        final after = controller.rows;
        expect(after[targetIndex].isExpanded, isFalse);
        expect(after[targetIndex - 1], same(before[targetIndex - 1]));
        if (targetIndex + 1 < after.length) {
          expect(
            after[targetIndex + 1],
            same(before[targetIndex + 1 + change.removed]),
          );
        }
        expect(subject.counts('toggle'), {
          'rows': expected.toggleRows,
          'hidden_rows': expected.toggleHiddenRows,
        });
      }
    });
  }
}
