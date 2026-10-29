import 'package:fdt_bench_harness/harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the deep 10k workload with every operation', () {
    final config = BenchConfig.parse(const [], implementation: 'v1');
    expect(config.implementation, 'v1');
    expect(config.shape, WorkloadShape.deep);
    expect(config.size, 10000);
    expect(config.seed, Workload.defaultSeed);
    expect(config.runs, 5);
    expect(config.warmup, 1);
    expect(config.effectiveOperations, standardOperations);
  });

  test('reads values and keeps the operations in catalog order', () {
    final config = BenchConfig.parse([
      '--shape',
      'wide',
      '--size=100k',
      '--runs',
      '3',
      '--warmup',
      '0',
      '--seed',
      '7',
      '--operations',
      'jump_end, build,filter',
    ], implementation: 'v2');
    expect(config.shape, WorkloadShape.wide);
    expect(config.size, 100000);
    expect(config.runs, 3);
    expect(config.warmup, 0);
    expect(config.seed, 7);
    expect(config.effectiveOperations, ['build', 'filter', 'jump_end']);
    expect(config.toJson(), {
      'implementation': 'v2',
      'shape': 'wide',
      'size': 100000,
      'seed': 7,
      'runs': 3,
      'warmup': 0,
    });
  });

  test('rejects invalid arguments', () {
    for (final bad in [
      ['deep'],
      ['--shape'],
      ['--shape', 'tall'],
      ['--size', '1x'],
      ['--size', '10'],
      ['--runs', '0'],
      ['--operations', 'sort'],
      ['--operations', ','],
      ['--nope', '1'],
    ]) {
      expect(
        () => BenchConfig.parse(bad, implementation: 'v1'),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('resolve prefers command-line arguments', () {
    final config = BenchConfig.resolve(['--size', '1m'], implementation: 'v1');
    expect(config.size, 1000000);
  });

  test('parseCount accepts k and m suffixes', () {
    expect(parseCount('10000'), 10000);
    expect(parseCount('10K'), 10000);
    expect(parseCount(' 1m '), 1000000);
    expect(() => parseCount('ten'), throwsFormatException);
  });

  test('the debug test binding reports JIT', () {
    expect(benchMode, 'jit');
    expect(benchBuildMode, 'debug');
  });
}
