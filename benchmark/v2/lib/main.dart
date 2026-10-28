import 'package:fdt_bench_harness/harness.dart';
import 'package:fdt_bench_v2/v2_subject.dart';

/// Runs the v2 benchmark as an app and exits; see `benchmark/README.md`.
///
/// AOT: `flutter build macos --profile`, then launch
/// `build/macos/Build/Products/Profile/fdt_bench_v2.app/Contents/MacOS/fdt_bench_v2`
/// with the benchmark arguments, or `flutter run --profile -d macos`.
Future<void> main(List<String> args) =>
    runAotBenchmark(args, implementation: 'v2', createSubject: createV2Subject);
