import 'dart:convert';
import 'dart:io';

import 'package:fdt_bench_runner/runner.dart';
import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';

final _usage =
    '''
Usage: dart run bin/run.dart [options]   (from benchmark/runner)

Runs each implementation in benchmark/<impl>/ in each mode, for every shape
and size, merges the records into benchmark/results.jsonl, and rewrites
benchmark/RESULTS.md.

  --impls <a,b>        Implementations (default v1,v2; missing ones are
                       skipped).
  --modes <a,b>        jit (flutter test, debug) and/or aot (macOS profile
                       app) (default jit,aot).
  --shapes <a,b>       Shapes (default deep,wide).
  --sizes <a,b>        Sizes (default 10k,100k,1m).
  --operations <a,b>   Operations (default all): ${standardOperations.join(',')}.
  --runs <n>           Timed runs per operation (default 5).
  --warmup <n>         Warm-up runs per operation (default 1).
  --budget-ms <ms>     Longest a single step may take (default 60000).
  --startup-ms <ms>    Longest a process may take to start (default 300000).
  --no-build           Reuse the existing AOT app builds.
  --fresh              Drop previously stored records instead of merging.
  --report-only        Only rewrite RESULTS.md from results.jsonl.
  --flutter <path>     The flutter executable (default: the SDK that runs
                       this script, else flutter on PATH).
  --benchmark-dir <d>  The benchmark/ directory (default: found from cwd).
  -h, --help           Show this help.''';

Future<void> main(List<String> args) async {
  final _Options options;
  try {
    options = _Options.parse(args);
  } on FormatException catch (e) {
    stderr
      ..writeln('error: ${e.message}')
      ..writeln(_usage);
    exitCode = 64;
    return;
  }
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  final benchDir = options.benchmarkDir ?? _findBenchmarkDir();
  if (benchDir == null) {
    stderr.writeln('error: cannot find benchmark/; pass --benchmark-dir');
    exitCode = 64;
    return;
  }
  final resultsFile = File('${benchDir.path}/results.jsonl');
  final markdownFile = File('${benchDir.path}/RESULTS.md');
  final flutter = options.flutter ?? _flutterExecutable();

  final existing = options.fresh || !resultsFile.existsSync()
      ? <BenchRecord>[]
      : [
          for (final line in resultsFile.readAsLinesSync())
            if (line.trim().isNotEmpty)
              (jsonDecode(line) as Map).cast<String, Object?>(),
        ];

  final fresh = <BenchRecord>[];
  var failed = false;
  if (!options.reportOnly) {
    _keepAwake();
    final env = await BenchEnvironment.detect(flutter);
    _log('Machine: ${env.machine}');
    _log('OS: ${env.os}');
    _log(env.flutter);

    for (final mode in options.modes) {
      final launchers = <String, BenchLauncher>{};
      for (final impl in options.impls) {
        final dir = Directory('${benchDir.path}/$impl');
        if (!File('${dir.path}/pubspec.yaml').existsSync()) {
          _log('Skipping $impl: ${dir.path}/pubspec.yaml does not exist.');
          continue;
        }
        final launcher = mode == 'aot'
            ? AotMacOSLauncher(dir, flutter: flutter, build: options.build)
            : JitLauncher(dir, flutter: flutter);
        _log('Preparing $impl ($mode)');
        if (await launcher.prepare(_log)) {
          launchers[impl] = launcher;
        } else {
          _log('Skipping $impl ($mode): preparation failed.');
          failed = true;
        }
      }

      for (final shape in options.shapes) {
        for (final size in options.sizes) {
          for (final MapEntry(key: impl, value: launcher)
              in launchers.entries) {
            final run = WorkloadRun(
              implementation: impl,
              mode: mode,
              shape: shape,
              size: size,
              runs: options.runs,
              warmup: options.warmup,
              budget: Duration(milliseconds: options.budgetMs),
              startupBudget: Duration(milliseconds: options.startupMs),
              operations: options.operations,
            );
            _log('== $impl $mode $shape $size');
            final records = await runWorkload(
              run,
              (operations) => launcher.start(run, operations),
              onRecord: (r) => _log('  ${_summary(r)}'),
              log: _log,
            );
            for (final r in records) {
              if (r['error'] != null) failed = true;
              fresh.add({...r, ...env.toJson()});
            }
            // Persist after every workload so an interrupted session keeps
            // what it measured.
            _write(resultsFile, mergeRecords(existing, fresh));
          }
        }
      }
    }
  }

  final merged = mergeRecords(existing, fresh);
  _write(resultsFile, merged);
  final workloads = <Workload>[];
  final expectations = <String, WorkloadExpectations>{};
  for (final r in merged) {
    final key = '${r['shape']}|${r['size']}|${r['seed']}';
    if (expectations.containsKey(key)) continue;
    final workload = Workload.generate(
      WorkloadShape.parse(r['shape']! as String),
      r['size']! as int,
      seed: r['seed'] as int? ?? Workload.defaultSeed,
    );
    workloads.add(workload);
    expectations[key] = WorkloadExpectations(workload);
  }
  markdownFile.writeAsStringSync(
    renderMarkdown(
      merged,
      workloads: workloads,
      expectations: expectations,
      generatedAt: DateTime.now(),
    ),
  );
  final problems = countProblems(merged, expectations);
  for (final problem in problems) {
    _log('count check: $problem');
  }
  _log('Wrote ${markdownFile.path} (${merged.length} records).');
  if (failed || problems.isNotEmpty) exitCode = 1;
}

void _log(String message) => stderr.writeln(message);

void _write(File file, List<BenchRecord> records) {
  file.writeAsStringSync(records.map((r) => '${jsonEncode(r)}\n').join());
}

/// Keeps the Mac awake (and its display on, so AOT frames keep coming) for
/// as long as this process runs.
///
/// Detached: caffeinate waits for this process to exit, so an attached child
/// (whose exit this process would wait for) would keep both alive forever.
void _keepAwake() {
  if (!Platform.isMacOS) return;
  Process.start('caffeinate', [
    '-d',
    '-i',
    '-m',
    '-w',
    '$pid',
  ], mode: ProcessStartMode.detached).then((_) {}, onError: (Object _) {});
}

String _flutterExecutable() {
  final root = Platform.environment['FLUTTER_ROOT'];
  final name = Platform.isWindows ? 'flutter.bat' : 'flutter';
  if (root != null && root.isNotEmpty) {
    final candidate = File('$root/bin/$name');
    if (candidate.existsSync()) return candidate.path;
  }
  // The Flutter SDK's dart: <root>/bin/cache/dart-sdk/bin/dart.
  final dart = File(Platform.resolvedExecutable);
  final sdkBin = dart.parent.parent.parent.parent;
  final candidate = File('${sdkBin.path}/$name');
  if (candidate.existsSync()) return candidate.path;
  return name;
}

Directory? _findBenchmarkDir() {
  bool isBench(Directory d) =>
      File('${d.path}/workloads/pubspec.yaml').existsSync() &&
      File('${d.path}/harness/pubspec.yaml').existsSync();
  var dir = Directory.current.absolute;
  while (true) {
    for (final candidate in [dir, Directory('${dir.path}/benchmark')]) {
      if (isBench(candidate)) return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

String _summary(BenchRecord r) {
  final head = '${r['operation']}:';
  if (r['median_ms'] is num) {
    return '$head median ${formatMs(r['median_ms']! as num)} ms, '
        'min ${formatMs(r['min_ms']! as num)} ms';
  }
  final error = r['error'] != null && r['blocked_by'] == null
      ? ': ${r['error']}'
      : '';
  return '$head ${medianCell(r)}$error';
}

class _Options {
  _Options({
    required this.help,
    required this.impls,
    required this.modes,
    required this.shapes,
    required this.sizes,
    required this.operations,
    required this.runs,
    required this.warmup,
    required this.budgetMs,
    required this.startupMs,
    required this.build,
    required this.fresh,
    required this.reportOnly,
    required this.flutter,
    required this.benchmarkDir,
  });

  factory _Options.parse(List<String> args) {
    final values = <String, String>{};
    final flags = <String>{};
    const flagNames = {'no-build', 'fresh', 'report-only'};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-h' || arg == '--help') {
        flags.add('help');
        continue;
      }
      if (!arg.startsWith('--')) throw FormatException('Unexpected "$arg"');
      final name = arg.substring(2);
      if (flagNames.contains(name)) {
        flags.add(name);
        continue;
      }
      final eq = name.indexOf('=');
      if (eq != -1) {
        values[name.substring(0, eq)] = name.substring(eq + 1);
      } else if (i + 1 < args.length) {
        values[name] = args[++i];
      } else {
        throw FormatException('Missing value: $arg');
      }
    }
    List<String> list(String name, List<String> fallback) =>
        values
            .remove(name)
            ?.split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList() ??
        fallback;
    int count(String name, int fallback, {int min = 0}) {
      final raw = values.remove(name);
      final value = raw == null ? fallback : _parseCount(raw);
      if (value < min) throw FormatException('--$name must be >= $min');
      return value;
    }

    final modes = list('modes', ['jit', 'aot']);
    for (final mode in modes) {
      if (!knownModes.containsKey(mode)) {
        throw FormatException('Unknown mode "$mode"');
      }
    }
    final shapes = list('shapes', [
      for (final s in WorkloadShape.values) s.name,
    ]);
    shapes.forEach(WorkloadShape.parse);
    final sizes = list('sizes', [
      for (final s in standardSizes) '$s',
    ]).map(_parseCount).toList();
    final requested = list('operations', standardOperations).toSet();
    requested.forEach(operationNamed);
    final benchDir = values.remove('benchmark-dir');
    final options = _Options(
      help: flags.contains('help'),
      impls: list('impls', knownImplementations),
      modes: modes,
      shapes: shapes,
      sizes: sizes,
      operations: [
        for (final name in standardOperations)
          if (requested.contains(name)) name,
      ],
      runs: count('runs', 5, min: 1),
      warmup: count('warmup', 1),
      budgetMs: count('budget-ms', 60000, min: 1),
      startupMs: count('startup-ms', 300000, min: 1),
      build: !flags.contains('no-build'),
      fresh: flags.contains('fresh'),
      reportOnly: flags.contains('report-only'),
      flutter: values.remove('flutter'),
      benchmarkDir: benchDir == null ? null : Directory(benchDir).absolute,
    );
    if (values.isNotEmpty) {
      throw FormatException('Unknown option --${values.keys.first}');
    }
    return options;
  }

  final bool help;
  final List<String> impls;
  final List<String> modes;
  final List<String> shapes;
  final List<int> sizes;
  final List<String> operations;
  final int runs;
  final int warmup;
  final int budgetMs;
  final int startupMs;
  final bool build;
  final bool fresh;
  final bool reportOnly;
  final String? flutter;
  final Directory? benchmarkDir;
}

int _parseCount(String raw) {
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
