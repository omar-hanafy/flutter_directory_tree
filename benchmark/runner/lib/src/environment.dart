import 'dart:convert';
import 'dart:io';

/// The machine, OS, and Flutter SDK the benchmarks run on.
class BenchEnvironment {
  /// Creates an environment description.
  const BenchEnvironment({
    required this.machine,
    required this.os,
    required this.flutter,
  });

  /// CPU model, architecture, cores, and memory, for example
  /// `Apple M2 Pro (arm64), 12 logical cores, 16 GB`.
  final String machine;

  /// Operating system name and version.
  final String os;

  /// The Flutter SDK that ran the benchmarks, for example
  /// `Flutter 3.47.7 (stable, framework abaf9c5237, engine deb287481e)`.
  final String flutter;

  /// Detects the environment, using [flutterExecutable] for
  /// `flutter --version --machine`.
  static Future<BenchEnvironment> detect(String flutterExecutable) async {
    Future<String?> run(String exe, List<String> args) async {
      try {
        final r = await Process.run(exe, args);
        if (r.exitCode != 0) return null;
        final out = '${r.stdout}'.trim();
        return out.isEmpty ? null : out;
      } on ProcessException {
        return null;
      }
    }

    String? cpu;
    int? memoryBytes;
    if (Platform.isMacOS) {
      cpu = await run('sysctl', ['-n', 'machdep.cpu.brand_string']);
      memoryBytes = int.tryParse(
        await run('sysctl', ['-n', 'hw.memsize']) ?? '',
      );
    } else if (Platform.isLinux) {
      final info = File('/proc/cpuinfo');
      if (info.existsSync()) {
        final line = info
            .readAsLinesSync()
            .where((l) => l.startsWith('model name'))
            .firstOrNull;
        cpu = line?.split(':').skip(1).join(':').trim();
      }
    }
    final arch = await run('uname', ['-m']);
    final machine = [
      '${cpu ?? 'unknown CPU'}${arch == null ? '' : ' ($arch)'}',
      '${Platform.numberOfProcessors} logical cores',
      if (memoryBytes != null) '${(memoryBytes / (1 << 30)).round()} GB',
    ].join(', ');

    var os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    if (Platform.isMacOS) {
      final version = await run('sw_vers', ['-productVersion']);
      final build = await run('sw_vers', ['-buildVersion']);
      if (version != null) {
        os = 'macOS $version${build == null ? '' : ' ($build)'}';
      }
    }

    return BenchEnvironment(
      machine: machine,
      os: os,
      flutter: describeFlutterVersion(
        await run(flutterExecutable, ['--version', '--machine']),
      ),
    );
  }

  /// The fields added to every stored record.
  Map<String, String> toJson() => {
    'machine': machine,
    'os': os,
    'flutter': flutter,
  };
}

/// Turns the output of `flutter --version --machine` into one line, or
/// `unknown Flutter SDK` when [machineJson] is null or not that output.
String describeFlutterVersion(String? machineJson) {
  if (machineJson == null) return 'unknown Flutter SDK';
  try {
    final start = machineJson.indexOf('{');
    final info = (jsonDecode(machineJson.substring(start)) as Map)
        .cast<String, Object?>();
    String short(Object? revision) {
      final s = '${revision ?? '?'}';
      return s.length > 10 ? s.substring(0, 10) : s;
    }

    final version = info['flutterVersion'] ?? info['frameworkVersion'] ?? '?';
    return 'Flutter $version (${info['channel'] ?? '?'}, framework '
        '${short(info['frameworkRevision'])}, engine '
        '${short(info['engineRevision'])})';
  } on Object {
    return 'unknown Flutter SDK';
  }
}
