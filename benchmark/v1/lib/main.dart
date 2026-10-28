import 'package:fdt_bench_harness/harness.dart';
import 'package:fdt_bench_v1/v1_subject.dart';

/// Runs the v1 benchmark as an app and exits; see `benchmark/README.md`.
///
/// AOT: `flutter build macos --profile`, then launch
/// `build/macos/Build/Products/Profile/fdt_bench_v1.app/Contents/MacOS/fdt_bench_v1`
/// with the benchmark arguments, or `flutter run --profile -d macos`.
Future<void> main(List<String> args) =>
    runAotBenchmark(args, implementation: 'v1', createSubject: createV1Subject);
