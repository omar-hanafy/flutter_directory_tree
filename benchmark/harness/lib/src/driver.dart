import 'dart:io' show Platform;

import 'package:fdt_bench_workloads/protocol.dart';
import 'package:fdt_bench_workloads/workloads.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'config.dart';
import 'frames.dart';
import 'subject.dart';

/// Writes one benchmark line to standard output.
///
/// `print` reaches the runner in both modes: flutter test forwards it to the
/// reporter output, and a macOS app writes it to stdout (prefixed with
/// `flutter: `).
void emitBenchLine(String line) {
  // ignore: avoid_print, the runner reads benchmark lines from stdout.
  print(line);
}

/// Runs every operation of [config] on a subject from [createSubject] and
/// returns one record per operation.
///
/// Prints (through [emit]) a `start` event, a `workload` event, a `phase`
/// event before every step, a `record` event per operation, and a `done`
/// event; see [BenchEvent]. An operation that throws gets a record with an
/// `error`, and operations whose prerequisites failed get an `error` with
/// `blocked_by` instead of running. Frame operations render through
/// [frames], which must show a mounted [BenchHost].
Future<List<Map<String, Object?>>> runBenchmark(
  BenchConfig config,
  SubjectFactory createSubject, {
  required FrameDriver frames,
  void Function(String line) emit = emitBenchLine,
}) async {
  void send(Map<String, Object?> event) => emit(encodeBenchLine(event));
  void phase(String? operation, String phase, [int completedRuns = 0]) => send({
    'event': BenchEvent.phase,
    'operation': operation,
    'phase': phase,
    'completed_runs': completedRuns,
  });

  final dart = Platform.version;
  send({
    'event': BenchEvent.start,
    ...config.toJson(),
    'mode': benchMode,
    'build_mode': benchBuildMode,
    'dart': dart,
    'operations': config.effectiveOperations,
  });

  phase(null, 'workload');
  final workload = Workload.generate(
    config.shape,
    config.size,
    seed: config.seed,
  );
  send({'event': BenchEvent.workload, 'description': workload.describe()});

  Map<String, Object?> recordOf(String operation, Map<String, Object?> data) =>
      {
        'implementation': config.implementation,
        'mode': benchMode,
        'build_mode': benchBuildMode,
        'shape': config.shape.name,
        'size': config.size,
        'operation': operation,
        'runs': config.runs,
        'warmup': config.warmup,
        'seed': config.seed,
        'fingerprint': workload.fingerprint,
        ...data,
        'dart': dart,
      };

  final records = <Map<String, Object?>>[];
  final failed = <String>{};
  final subject = createSubject(workload);
  final view = _ViewSlot(frames, subject);
  final errors = _FrameErrors()..install();
  try {
    for (final operation in config.effectiveOperations) {
      final blocker = operationNamed(operation).prerequisites
          .where(failed.contains)
          .firstOrNull;
      Map<String, Object?> data;
      if (blocker != null) {
        data = {'error': 'blocked: $blocker failed', 'blocked_by': blocker};
        failed.add(operation);
      } else {
        try {
          data = await _measure(
            operation,
            config: config,
            subject: subject,
            view: view,
            errors: errors,
            phase: phase,
          );
        } on Object catch (error, stack) {
          data = {'error': _describeError(error, stack)};
          failed.add(operation);
          try {
            await view.unmount();
          } on Object {
            // Best effort: the error above is the one worth reporting.
          }
        }
      }
      final record = recordOf(operation, data);
      records.add(record);
      send({'event': BenchEvent.record, 'record': record});
    }
  } finally {
    try {
      await view.unmount();
    } finally {
      errors.uninstall();
      subject.dispose();
    }
  }
  send({'event': BenchEvent.done});
  return records;
}

Future<Map<String, Object?>> _measure(
  String operation, {
  required BenchConfig config,
  required BenchSubject subject,
  required _ViewSlot view,
  required _FrameErrors errors,
  required void Function(String? operation, String phase, [int runs]) phase,
}) async {
  final kind = operationNamed(operation).kind;
  phase(operation, 'setup');
  subject.setUp(operation);
  errors.clear();

  final times = <double>[];
  Map<String, Object> counts;
  if (kind == OperationKind.controller) {
    for (var i = 0; i < config.warmup + config.runs; i++) {
      final warm = i < config.warmup;
      phase(operation, warm ? 'warmup' : 'run', times.length);
      subject.beforeRun(operation);
      final watch = Stopwatch()..start();
      subject.run(operation);
      watch.stop();
      if (!warm) times.add(watch.elapsedMicroseconds / 1000);
      // Lets pending microtasks run between runs, as an app would.
      await null;
    }
    counts = subject.counts(operation);
  } else {
    final firstFrame = operation == 'first_frame';
    if (firstFrame) {
      await view.unmount();
    } else if (!view.isMounted) {
      await view.mount();
    }
    errors.check();
    for (var i = 0; i < config.warmup + config.runs; i++) {
      final warm = i < config.warmup;
      phase(operation, warm ? 'warmup' : 'run', times.length);
      final double ms;
      if (firstFrame) {
        await view.unmount();
        view.probe.reset();
        ms = await measureFrame(view.frames, view.attach);
      } else {
        await view.jumpTo(0);
        view.probe.reset();
        final scroll = view.scrollController;
        final max = scroll.position.maxScrollExtent;
        final target = operation == 'jump_middle' ? max / 2 : max;
        ms = await measureFrame(view.frames, () => scroll.jumpTo(target));
      }
      errors.check();
      if (!warm) times.add(ms);
    }
    counts = {'rows': subject.viewRowCount, ...view.probe.toCounts()};
  }
  subject.tearDown(operation);

  final sorted = [...times]..sort();
  return {
    'median_ms': _round(_median(sorted)),
    'min_ms': _round(sorted.first),
    'max_ms': _round(sorted.last),
    ...counts,
  };
}

double _median(List<double> sorted) {
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

double _round(double ms) => (ms * 1000).round() / 1000;

String _describeError(Object error, StackTrace stack) {
  final frames = stack.toString().split('\n').take(6).join(' | ');
  return '$error ($frames)';
}

/// The view under test in the host's slot, with the scroll controller and
/// row probe of its current mount.
class _ViewSlot {
  _ViewSlot(this.frames, this.subject);

  final FrameDriver frames;
  final BenchSubject subject;
  final RowProbe probe = RowProbe();
  ScrollController? _scroll;

  bool get isMounted => _scroll != null;

  ScrollController get scrollController =>
      _scroll ?? (throw StateError('The view is not mounted.'));

  /// Puts a new view, with a new scroll controller, in the slot. The next
  /// frame mounts it.
  void attach() {
    final scroll = ScrollController();
    _scroll = scroll;
    frames.slot.value = subject.buildView(
      scrollController: scroll,
      onRowBuilt: probe.add,
    );
  }

  /// [attach] and run the frame that mounts the view.
  Future<void> mount() async {
    attach();
    await frames.pump();
  }

  /// Empties the slot, runs the frame that removes the view, and disposes
  /// its scroll controller.
  Future<void> unmount() async {
    final scroll = _scroll;
    if (scroll == null && frames.slot.value == null) return;
    _scroll = null;
    frames.slot.value = null;
    await frames.pump();
    scroll?.dispose();
  }

  /// Scrolls to [offset] and runs the resulting frame.
  Future<void> jumpTo(double offset) async {
    final scroll = scrollController;
    if (scroll.offset == offset) return;
    scroll.jumpTo(offset);
    await frames.pump();
  }
}

/// Turns errors reported to [FlutterError.onError] during frames into
/// operation failures, while still forwarding them to the previous handler.
class _FrameErrors {
  FlutterExceptionHandler? _previous;
  FlutterErrorDetails? _first;

  void install() {
    _previous = FlutterError.onError;
    FlutterError.onError = (details) {
      _first ??= details;
      _previous?.call(details);
    };
  }

  void uninstall() => FlutterError.onError = _previous;

  void clear() => _first = null;

  /// Throws when an error was reported since the last [clear].
  void check() {
    final first = _first;
    if (first == null) return;
    clear();
    throw StateError('Error during a frame: ${first.exceptionAsString()}');
  }
}
