import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'coordinator.dart';

/// The environment variable the benchmark processes read their arguments
/// from (see the harness's `BenchConfig.resolve`).
const String benchArgsVariable = 'FDT_BENCH_ARGS';

/// The arguments for one benchmark process.
String benchArguments(WorkloadRun run, List<String> operations) => [
  '--shape ${run.shape}',
  '--size ${run.size}',
  '--seed ${run.seed}',
  '--runs ${run.runs}',
  '--warmup ${run.warmup}',
  '--operations ${operations.join(',')}',
].join(' ');

/// A [BenchProcess] backed by a local OS process.
class LocalBenchProcess implements BenchProcess {
  LocalBenchProcess._(this._process) {
    var open = 2;
    void closeOne() {
      if (--open == 0) unawaited(_lines.close());
    }

    for (final stream in [_process.stdout, _process.stderr]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(_lines.add, onDone: closeOne, onError: (Object _) {});
    }
  }

  /// Starts [executable] with [arguments].
  static Future<LocalBenchProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async => LocalBenchProcess._(
    await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    ),
  );

  final Process _process;
  final StreamController<String> _lines = StreamController<String>();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> kill() => killProcessTree(_process.pid);
}

/// Kills the process [pid] and all its descendants (SIGKILL; `taskkill /T`
/// on Windows).
///
/// `flutter test` runs the test in a `flutter_tester` child and compiles it
/// in a frontend-server child, so killing only the tool would leave them
/// running (and skew every later measurement).
Future<void> killProcessTree(int pid) async {
  if (Platform.isWindows) {
    await Process.run('taskkill', ['/T', '/F', '/PID', '$pid']);
    return;
  }
  final tree = <int>[];
  Future<void> collect(int parent) async {
    tree.add(parent);
    try {
      final result = await Process.run('pgrep', ['-P', '$parent']);
      for (final line in '${result.stdout}'.split('\n')) {
        final child = int.tryParse(line.trim());
        if (child != null) await collect(child);
      }
    } on ProcessException {
      // No pgrep: only the parent is killed.
    }
  }

  await collect(pid);
  for (final process in tree.reversed) {
    Process.killPid(process, ProcessSignal.sigkill);
  }
}

/// Runs [executable] with [arguments] in [workingDirectory] and returns
/// whether it succeeded, logging the command and, on failure, its output.
Future<bool> runStep(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required void Function(String message) log,
}) async {
  log(
    '  \$ ${[executable.split(Platform.pathSeparator).last, ...arguments].join(' ')}',
  );
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
  );
  if (result.exitCode == 0) return true;
  log(
    '  failed (exit code ${result.exitCode}):\n${result.stdout}${result.stderr}',
  );
  return false;
}

/// How to run one implementation package in one mode.
abstract class BenchLauncher {
  /// The implementation package directory, for example `benchmark/v1`.
  Directory get directory;

  /// `jit` or `aot`.
  String get mode;

  /// Gets the package ready (pub get, builds). Returns false on failure.
  Future<bool> prepare(void Function(String message) log);

  /// Starts a process that runs [operations] of [run].
  Future<BenchProcess> start(WorkloadRun run, List<String> operations);
}

/// Runs `flutter test bench/jit_bench_test.dart` (debug mode, JIT).
class JitLauncher implements BenchLauncher {
  /// Creates a launcher for the package in [directory].
  JitLauncher(this.directory, {required this.flutter});

  @override
  final Directory directory;

  /// The `flutter` executable.
  final String flutter;

  /// The benchmark test, relative to [directory].
  static const String entryPoint = 'bench/jit_bench_test.dart';

  @override
  String get mode => 'jit';

  @override
  Future<bool> prepare(void Function(String message) log) => runStep(
    flutter,
    ['pub', 'get'],
    workingDirectory: directory.path,
    log: log,
  );

  @override
  Future<BenchProcess> start(WorkloadRun run, List<String> operations) =>
      LocalBenchProcess.start(
        flutter,
        ['test', '--no-pub', '-r', 'expanded', entryPoint],
        workingDirectory: directory.path,
        environment: {benchArgsVariable: benchArguments(run, operations)},
      );
}

/// Builds the package as a macOS app in profile mode (AOT) and launches its
/// executable directly.
class AotMacOSLauncher implements BenchLauncher {
  /// Creates a launcher for the package in [directory].
  AotMacOSLauncher(this.directory, {required this.flutter, this.build = true});

  @override
  final Directory directory;

  /// The `flutter` executable.
  final String flutter;

  /// Whether [prepare] runs `flutter build macos --profile`; when false it
  /// reuses the existing build.
  final bool build;

  String? _executable;

  @override
  String get mode => 'aot';

  /// The built app's executable, or null when there is no build.
  String? findExecutable() {
    final products = Directory(
      '${directory.path}/build/macos/Build/Products/Profile',
    );
    if (!products.existsSync()) return null;
    for (final app in products.listSync().whereType<Directory>()) {
      if (!app.path.endsWith('.app')) continue;
      final binaries = Directory('${app.path}/Contents/MacOS');
      if (!binaries.existsSync()) continue;
      final files = binaries.listSync().whereType<File>().toList();
      if (files.length == 1) return files.single.path;
    }
    return null;
  }

  @override
  Future<bool> prepare(void Function(String message) log) async {
    if (!Platform.isMacOS) {
      log('  AOT runs need macOS (they build a macOS profile app).');
      return false;
    }
    if (!Directory('${directory.path}/macos').existsSync()) {
      log('  ${directory.path} has no macos/ runner.');
      return false;
    }
    if (build) {
      final ok =
          await runStep(
            flutter,
            ['pub', 'get'],
            workingDirectory: directory.path,
            log: log,
          ) &&
          await runStep(
            flutter,
            ['build', 'macos', '--profile'],
            workingDirectory: directory.path,
            log: log,
          );
      if (!ok) return false;
    }
    _executable = findExecutable();
    if (_executable == null) log('  No profile build in ${directory.path}.');
    return _executable != null;
  }

  @override
  Future<BenchProcess> start(WorkloadRun run, List<String> operations) =>
      LocalBenchProcess.start(
        _executable!,
        const [],
        workingDirectory: directory.path,
        environment: {benchArgsVariable: benchArguments(run, operations)},
      );
}
