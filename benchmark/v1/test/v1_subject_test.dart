import 'package:fdt_bench_harness/jit.dart';
import 'package:fdt_bench_v1/v1_subject.dart';
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
    BenchConfig(implementation: 'v1', shape: shape, runs: 1, warmup: 0),
    createV1Subject,
    frames: TesterFrameDriver(tester, slot),
    emit: (_) {},
  );
  await tester.pumpWidget(const SizedBox.shrink());
  return records;
}

void main() {
  for (final shape in WorkloadShape.values) {
    testWidgets(
      '${shape.name} 10k: every operation reports the expected counts',
      (tester) async {
        final workload = Workload.generate(shape, 10000);
        final expected = WorkloadExpectations(workload);
        final records = await _runAll(tester, shape);

        expect(records.map((r) => r['operation']), standardOperations);
        for (final record in records) {
          final operation = record['operation']! as String;
          expect(record['error'], isNull, reason: operation);
          expect(record['fingerprint'], workload.fingerprint);
          expect(expected.check(operation, record), isEmpty, reason: operation);
        }
        final byOperation = {for (final r in records) r['operation']: r};
        // 1.0.0 stores two extra nodes: its hidden root and the container.
        expect(
          byOperation['build']!['nodes'],
          workload.size + workload.folderCount + 2,
        );
        // The views build only the rows on screen, not the 10k+ rows: a
        // 600 px viewport of 28 px rows shows 22 rows, and the default cache
        // extent adds about 9 on each side.
        for (final operation in ['first_frame', 'jump_middle', 'jump_end']) {
          expect(
            byOperation[operation]!['built_rows'],
            inInclusiveRange(22, 42),
            reason: operation,
          );
        }
        expect(tester.takeException(), isNull);
      },
      semanticsEnabled: false,
    );
  }
}
