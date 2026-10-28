/// Shared measurement harness for the flutter_directory_tree benchmarks.
///
/// An implementation package provides a [BenchSubject] and two entry points:
/// `lib/main.dart` calls [runAotBenchmark] (AOT, macOS profile app) and
/// `bench/jit_bench_test.dart` calls `defineJitBenchmark` from
/// `package:fdt_bench_harness/jit.dart` (JIT, flutter test).
library;

export 'package:fdt_bench_workloads/protocol.dart';
export 'package:fdt_bench_workloads/workloads.dart';

export 'src/aot.dart';
export 'src/config.dart';
export 'src/driver.dart';
export 'src/frames.dart';
export 'src/subject.dart';
