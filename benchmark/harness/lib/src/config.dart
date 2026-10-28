import 'dart:io';

import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';
import 'package:flutter/foundation.dart';

/// The environment variable (or `--dart-define`) that carries the benchmark
/// arguments when the process has no command line of its own, such as
/// `flutter test` or an app launched by the runner.
const String benchArgsVariable = 'FDT_BENCH_ARGS';

/// The usage text for the benchmark arguments.
const String benchUsage =
    '''
Arguments (command line, or the $benchArgsVariable environment variable):

  --shape <deep|wide>     Workload shape (default deep).
  --size <n>              File count, for example 10000, 100k, or 1m
                          (default 10k).
  --runs <n>              Timed runs per operation (default 5).
  --warmup <n>            Untimed warm-up runs per operation (default 1).
  --seed <n>              Workload seed (default ${Workload.defaultSeed}).
  --operations <a,b,...>  Subset of the operations, run in catalog order.''';

/// `jit` in debug builds (flutter test, `flutter run` without flags), `aot`
/// in profile and release builds.
String get benchMode => kDebugMode ? 'jit' : 'aot';

/// The Flutter build mode: `debug`, `profile`, or `release`.
String get benchBuildMode => kReleaseMode
    ? 'release'
    : kProfileMode
    ? 'profile'
    : 'debug';

/// What one benchmark process measures: one implementation and workload.
@immutable
class BenchConfig {
  /// Creates a configuration.
  const BenchConfig({
    required this.implementation,
    this.shape = WorkloadShape.deep,
    this.size = 10000,
    this.seed = Workload.defaultSeed,
    this.runs = 5,
    this.warmup = 1,
    this.operations,
  });

  /// Parses CLI-style [args] such as `['--shape', 'wide', '--size', '100k']`.
  ///
  /// Missing arguments keep their defaults, so empty [args] measure the deep
  /// 10k workload. Throws a [FormatException] for invalid arguments.
  factory BenchConfig.parse(
    List<String> args, {
    required String implementation,
  }) {
    final values = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) throw FormatException('Unexpected "$arg"');
      final eq = arg.indexOf('=');
      if (eq != -1) {
        values[arg.substring(2, eq)] = arg.substring(eq + 1);
      } else {
        if (i + 1 >= args.length) throw FormatException('Missing value: $arg');
        values[arg.substring(2)] = args[++i];
      }
    }

    int count(String name, int fallback, {int min = 0}) {
      final raw = values.remove(name);
      if (raw == null) return fallback;
      final value = parseCount(raw);
      if (value < min) throw FormatException('--$name must be >= $min');
      return value;
    }

    final shapeName = values.remove('shape');
    final operationsRaw = values.remove('operations');
    List<String>? operations;
    if (operationsRaw != null) {
      final names = {
        for (final name in operationsRaw.split(','))
          if (name.trim().isNotEmpty) operationNamed(name.trim()).name,
      };
      if (names.isEmpty) throw const FormatException('--operations is empty');
      operations = [
        for (final name in standardOperations)
          if (names.contains(name)) name,
      ];
    }
    final config = BenchConfig(
      implementation: implementation,
      shape: shapeName == null
          ? WorkloadShape.deep
          : WorkloadShape.parse(shapeName),
      size: count('size', 10000, min: 100),
      seed: count('seed', Workload.defaultSeed),
      runs: count('runs', 5, min: 1),
      warmup: count('warmup', 1),
      operations: operations,
    );
    if (values.isNotEmpty) {
      throw FormatException('Unknown option --${values.keys.first}');
    }
    return config;
  }

  /// Parses [args] when there are any, otherwise the [benchArgsVariable]
  /// environment variable, otherwise the `--dart-define` of the same name.
  ///
  /// Throws a [FormatException] for invalid arguments.
  factory BenchConfig.resolve(
    List<String> args, {
    required String implementation,
  }) {
    var source = args;
    if (source.isEmpty) {
      final raw =
          Platform.environment[benchArgsVariable] ??
          const String.fromEnvironment(benchArgsVariable);
      source = raw.trim().isEmpty ? const [] : raw.trim().split(RegExp(r'\s+'));
    }
    return BenchConfig.parse(source, implementation: implementation);
  }

  /// The implementation label, such as `v1` or `v2`.
  final String implementation;

  /// The workload shape.
  final WorkloadShape shape;

  /// The workload size (file count).
  final int size;

  /// The workload seed.
  final int seed;

  /// Timed runs per operation.
  final int runs;

  /// Untimed warm-up runs per operation.
  final int warmup;

  /// The operations to run; null means all of them.
  final List<String>? operations;

  /// The operations this configuration runs, in catalog order (the order of
  /// [operations] does not matter).
  ///
  /// Throws a [FormatException] when [operations] names an unknown one.
  List<String> get effectiveOperations {
    final requested = operations;
    if (requested == null) return standardOperations;
    requested.forEach(operationNamed);
    return [
      for (final name in standardOperations)
        if (requested.contains(name)) name,
    ];
  }

  /// The fields every record and the start event carry.
  Map<String, Object?> toJson() => {
    'implementation': implementation,
    'shape': shape.name,
    'size': size,
    'seed': seed,
    'runs': runs,
    'warmup': warmup,
  };
}

/// Parses `10000`, `100k`, or `1m` (case-insensitive).
///
/// Throws a [FormatException] when [raw] is not a count.
int parseCount(String raw) {
  final s = raw.trim().toLowerCase();
  final multiplier = s.endsWith('k')
      ? 1000
      : s.endsWith('m')
      ? 1000000
      : 1;
  final digits = multiplier == 1 ? s : s.substring(0, s.length - 1);
  final value = int.tryParse(digits);
  if (value == null) throw FormatException('Not a number: "$raw"');
  return value * multiplier;
}
