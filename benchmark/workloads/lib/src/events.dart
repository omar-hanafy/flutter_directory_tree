import 'dart:convert';

/// Prefix of every line a benchmark process prints for the runner.
///
/// The rest of the line is one JSON object with an `event` key. Lines without
/// the marker (test reporter output, engine logs, the `flutter: ` prefix that
/// macOS apps add) are ignored, so the marker may appear anywhere in a line.
const String benchLineMarker = 'FDT_BENCH ';

/// The events a benchmark process prints, in order.
abstract final class BenchEvent {
  /// Once, first: `implementation`, `mode`, `build_mode`, `dart`, and the
  /// configuration (`shape`, `size`, `seed`, `runs`, `warmup`, `operations`).
  static const String start = 'start';

  /// Once, after the workload was generated: `description` (see
  /// `Workload.describe`).
  static const String workload = 'workload';

  /// Before every step: `operation` (null while generating the workload),
  /// `phase` (`workload`, `setup`, `warmup`, or `run`), and
  /// `completed_runs`. The runner restarts its per-step budget on each one.
  static const String phase = 'phase';

  /// One per operation: `record`, the finished measurement (or an `error`).
  static const String record = 'record';

  /// Once, last.
  static const String done = 'done';
}

/// Encodes [event] as one benchmark line.
String encodeBenchLine(Map<String, Object?> event) =>
    '$benchLineMarker${jsonEncode(event)}';

/// Decodes the event in [line], or returns null when [line] carries none.
Map<String, Object?>? decodeBenchLine(String line) {
  final start = line.indexOf(benchLineMarker);
  if (start == -1) return null;
  try {
    final decoded = jsonDecode(line.substring(start + benchLineMarker.length));
    if (decoded is! Map) return null;
    final event = decoded.cast<String, Object?>();
    return event['event'] is String ? event : null;
  } on FormatException {
    return null;
  }
}
