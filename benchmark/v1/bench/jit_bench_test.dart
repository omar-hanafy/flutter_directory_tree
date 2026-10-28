// The JIT benchmark: `flutter test bench/jit_bench_test.dart -r expanded`,
// configured through FDT_BENCH_ARGS (see benchmark/README.md). It lives
// outside test/ so `flutter test` (CI) runs only the cheap correctness tests.
import 'package:fdt_bench_harness/jit.dart';
import 'package:fdt_bench_v1/v1_subject.dart';

void main() =>
    defineJitBenchmark(implementation: 'v1', createSubject: createV1Subject);
