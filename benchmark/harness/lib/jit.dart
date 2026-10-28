/// The JIT entry point: the benchmark as one widget test, run by
/// `flutter test` (debug mode, JIT compiler).
///
/// Import it only from a benchmark test file (for example
/// `bench/jit_bench_test.dart`); it depends on `flutter_test`.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

export 'harness.dart';

/// Defines the benchmark for [implementation] as one widget test.
///
/// The configuration comes from the `FDT_BENCH_ARGS` environment variable
/// (see [BenchConfig.resolve]); without it the deep 10k workload runs.
/// Semantics are off, as in an app without assistive technology. The test
/// fails when an operation failed, after every record was printed.
void defineJitBenchmark({
  required String implementation,
  required SubjectFactory createSubject,
}) {
  testWidgets(
    '$implementation benchmark (JIT)',
    (tester) async {
      final config = BenchConfig.resolve(
        const [],
        implementation: implementation,
      );
      final slot = ValueNotifier<Widget?>(null);
      addTearDown(slot.dispose);
      await tester.pumpWidget(BenchHost(slot: slot));
      final records = await runBenchmark(
        config,
        createSubject,
        frames: TesterFrameDriver(tester, slot),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      // Lets timers the views started (scrollbar fades, tooltips) finish.
      await tester.pump(const Duration(seconds: 5));
      final failures = [
        for (final record in records)
          if (record['error'] != null)
            '${record['operation']}: ${record['error']}',
      ];
      expect(failures, isEmpty);
    },
    semanticsEnabled: false,
    timeout: Timeout.none,
  );
}

/// A [FrameDriver] that runs frames with [WidgetTester.pump].
class TesterFrameDriver implements FrameDriver {
  /// Creates a driver for a [BenchHost] showing [slot].
  TesterFrameDriver(this.tester, this.slot);

  /// The tester whose binding produces the frames.
  final WidgetTester tester;

  @override
  final ValueNotifier<Widget?> slot;

  @override
  Future<void> pump() => tester.pump();
}
