import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// The size of the box the tree view under test gets, in logical pixels.
///
/// Fixed so the JIT runs (800 x 600 test surface) and the AOT runs (800 x 600
/// macOS window) show the same number of rows.
const Size benchViewSize = Size(400, 600);

/// The app that hosts the view under test: a [MaterialApp] whose only content
/// is [slot], top-left aligned in a [benchViewSize] box.
///
/// Mounted once before any measurement, so a measured frame contains only the
/// work of the view in [slot].
class BenchHost extends StatelessWidget {
  /// Creates the host.
  const BenchHost({super.key, required this.slot});

  /// The widget under test; null shows nothing.
  final ValueListenable<Widget?> slot;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox.fromSize(
            size: benchViewSize,
            child: ValueListenableBuilder<Widget?>(
              valueListenable: slot,
              builder: (context, child, _) => child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Produces frames for the harness: the test binding in JIT runs, the real
/// binding in AOT runs.
abstract class FrameDriver {
  /// The content of the mounted [BenchHost].
  ValueNotifier<Widget?> get slot;

  /// Completes after the next frame has run.
  Future<void> pump();
}

/// A [FrameDriver] for an app running on the real binding.
class LiveFrameDriver implements FrameDriver {
  /// Creates a driver for a [BenchHost] showing [slot].
  LiveFrameDriver(this.slot);

  @override
  final ValueNotifier<Widget?> slot;

  @override
  Future<void> pump() {
    SchedulerBinding.instance.scheduleFrame();
    return SchedulerBinding.instance.endOfFrame;
  }
}

/// Applies [change], lets [driver] run the next frame, and returns that
/// frame's UI-thread time in milliseconds.
///
/// The time runs from the frame's first transient callback (registered here,
/// before any other callback of that frame) to its first post-frame callback,
/// so it covers animations, build, layout, paint, and compositing but not the
/// wait for vsync. Throws a [StateError] when the frame did not run.
Future<double> measureFrame(FrameDriver driver, VoidCallback change) async {
  final binding = SchedulerBinding.instance;
  final watch = Stopwatch();
  var finished = false;
  binding
    ..scheduleFrameCallback((_) => watch.start())
    ..addPostFrameCallback((_) {
      watch.stop();
      finished = true;
    });
  change();
  await driver.pump();
  if (!finished) throw StateError('The measured frame did not run.');
  return watch.elapsedMicroseconds / 1000;
}

/// Reports [index] through [onBuilt] every time it builds, then shows
/// [child].
///
/// Wrap a view's rows in it when the view may reuse row widgets (2.0.0's
/// sliver caches them per id): a reused widget skips the row builder, but a
/// probe still builds whenever its element is mounted or rebuilt, so
/// `built_rows` counts the rows a frame really built.
class RowBuildProbe extends StatelessWidget {
  /// Creates a probe for the row at [index].
  const RowBuildProbe({
    super.key,
    required this.index,
    required this.onBuilt,
    required this.child,
  });

  /// The row's index in the view's list.
  final int index;

  /// Called with [index] on every build.
  final ValueChanged<int> onBuilt;

  /// The row.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    onBuilt(index);
    return child;
  }
}

/// Counts the rows a view builds and the range of their indices.
class RowProbe {
  int _count = 0;
  int? _first;
  int? _last;

  /// Records that the row at [index] was built.
  void add(int index) {
    _count++;
    final first = _first;
    final last = _last;
    if (first == null || index < first) _first = index;
    if (last == null || index > last) _last = index;
  }

  /// Forgets every recorded row.
  void reset() {
    _count = 0;
    _first = null;
    _last = null;
  }

  /// `built_rows`, `first_index`, and `last_index` (-1 when nothing was
  /// built).
  Map<String, Object> toCounts() => {
    'built_rows': _count,
    'first_index': _first ?? -1,
    'last_index': _last ?? -1,
  };
}
