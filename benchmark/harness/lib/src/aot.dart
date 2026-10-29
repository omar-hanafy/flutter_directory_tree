import 'dart:io' show exit;

import 'package:fdt_bench_workloads/protocol.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'driver.dart';
import 'frames.dart';
import 'subject.dart';

/// Runs the benchmark in a real app and exits the process when it is done.
///
/// Use it as the `main` of an implementation package's `lib/main.dart`, built
/// with `flutter build macos --profile` (AOT) and launched directly, or with
/// `flutter run --profile -d macos`. The configuration comes from [args],
/// else the `FDT_BENCH_ARGS` environment variable (see [BenchConfig.resolve]).
///
/// Exit codes: 0 when every operation produced numbers, 1 when one failed,
/// 64 for invalid arguments.
Future<Never> runAotBenchmark(
  List<String> args, {
  required String implementation,
  required SubjectFactory createSubject,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final BenchConfig config;
  try {
    config = BenchConfig.resolve(args, implementation: implementation);
  } on FormatException catch (error) {
    emitBenchLine('error: ${error.message}\n$benchUsage');
    exit(64);
  }

  final slot = ValueNotifier<Widget?>(null);
  runApp(BenchHost(slot: slot));
  await SchedulerBinding.instance.endOfFrame;

  var code = 0;
  try {
    final records = await runBenchmark(
      config,
      createSubject,
      frames: LiveFrameDriver(slot),
    );
    if (records.any((record) => record.containsKey('error'))) code = 1;
  } on Object catch (error, stack) {
    emitBenchLine(
      encodeBenchLine({
        'event': 'fatal',
        'error': '$error',
        'stack': stack.toString().split('\n').take(8).join(' | '),
      }),
    );
    code = 1;
  }
  exit(code);
}
