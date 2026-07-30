/// Fixture Generator
///
/// Generates controlled-size test data for benchmarks and tests.
/// - Large .styio files (1k, 10k, 100k lines)
/// - Multi-package workspaces
/// - Large dependency graphs
/// - Burst event streams
library;

import 'dart:io';
import 'dart:math';

/// Fixture configuration.
class FixtureConfig {
  final int lineCount;
  final int packageCount;
  final int dependencyCount;
  final int eventCount;

  const FixtureConfig({
    this.lineCount = 1000,
    this.packageCount = 10,
    this.dependencyCount = 100,
    this.eventCount = 1000,
  });

  static const small = FixtureConfig(
    lineCount: 1000,
    packageCount: 10,
    dependencyCount: 100,
    eventCount: 1000,
  );

  static const medium = FixtureConfig(
    lineCount: 10000,
    packageCount: 100,
    dependencyCount: 500,
    eventCount: 10000,
  );

  static const large = FixtureConfig(
    lineCount: 100000,
    packageCount: 1000,
    dependencyCount: 2000,
    eventCount: 100000,
  );
}

class FixtureGenerator {
  final FixtureConfig config;
  final Random _rng;

  FixtureGenerator({FixtureConfig? config})
    : config = config ?? FixtureConfig.medium,
      _rng = Random(42);

  /// Generate a large .styio file.
  String generateStyioFile() {
    final buf = StringBuffer();
    buf.writeln('// Auto-generated fixture file');
    buf.writeln('// Lines: ${config.lineCount}');
    buf.writeln('');

    // Header with metadata
    buf.writeln('fn main() {');
    buf.writeln('  let pipeline = source |> transform -> sink');
    buf.writeln('');

    for (var i = 0; i < config.lineCount; i++) {
      final stmtType = _rng.nextInt(5);
      switch (stmtType) {
        case 0:
          buf.writeln('  // Processing stage $i');
          break;
        case 1:
          buf.writeln('  let stream_$i = input_$i |> process_$i -> output_$i;');
          break;
        case 2:
          buf.writeln('  state state_${i % 10}');
          break;
        case 3:
          buf.writeln('  when event_$i -> state active_$i');
          break;
        case 4:
          buf.writeln('  emit result_$i;');
          break;
      }
    }

    buf.writeln('}');
    buf.writeln('');
    return buf.toString();
  }

  /// Generate multi-package workspace structure.
  Map<String, String> generateWorkspace() {
    final files = <String, String>{};
    for (var pkg = 0; pkg < config.packageCount; pkg++) {
      final pkgName = 'pkg_$pkg';
      final pkgFile = StringBuffer();
      pkgFile.writeln('// Package: $pkgName');
      pkgFile.writeln('fn main() {');
      final depCount = 2 + _rng.nextInt(5);
      for (var d = 0; d < depCount; d++) {
        final depIdx = _rng.nextInt(config.packageCount);
        pkgFile.writeln('  dep pkg_$depIdx');
      }
      pkgFile.writeln('  let stream = source |> transform -> sink');
      pkgFile.writeln('}');
      files['$pkgName/main.styio'] = pkgFile.toString();
    }
    return files;
  }

  /// Generate dependency graph specification.
  String generateDependencyGraph() {
    final buf = StringBuffer();
    buf.writeln('// Dependency Graph: ${config.dependencyCount} edges');

    // Generate packages
    final pkgCount = min(config.packageCount, config.dependencyCount);
    final packages = List.generate(pkgCount, (i) => 'pkg_$i');

    for (final pkg in packages) {
      buf.write('$pkg: ');
      final deps = <String>[];
      final depCount = 1 + _rng.nextInt(5);
      for (var d = 0; d < depCount && deps.length < depCount; d++) {
        final dep = packages[_rng.nextInt(packages.length)];
        if (dep != pkg && !deps.contains(dep)) {
          deps.add(dep);
        }
      }
      buf.writeln(deps.join(', '));
    }

    return buf.toString();
  }

  /// Generate burst event stream (as JSON lines).
  String generateEventStream() {
    final buf = StringBuffer();
    final eventTypes = ['file_change', 'diagnostic', 'state_transition', 'metric'];

    for (var i = 0; i < config.eventCount; i++) {
      final eventType = eventTypes[_rng.nextInt(eventTypes.length)];
      final source = ['watcher', 'analyzer', 'compiler', 'runtime'][_rng.nextInt(4)];

      buf.writeln('{"id": $i, "type": "$eventType", "source": "$source", '
          '"timestamp": ${DateTime.now().millisecondsSinceEpoch + i}}');
    }

    return buf.toString();
  }

  /// Write fixtures to [outputDir].
  void writeToDirectory(String outputDir) {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    // Write .styio file
    final styioContent = generateStyioFile();
    File('$outputDir/fixture_${config.lineCount}lines.styio')
        .writeAsStringSync(styioContent);

    // Write workspace files
    final workspace = generateWorkspace();
    final workspaceDir = Directory('$outputDir/workspace');
    if (!workspaceDir.existsSync()) {
      workspaceDir.createSync();
    }
    for (final entry in workspace.entries) {
      final filePath = '$outputDir/workspace/${entry.key}';
      final parentDir = Directory(filePath).parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }
      File(filePath).writeAsStringSync(entry.value);
    }

    // Write dependency graph
    File('$outputDir/dependency_graph_${config.dependencyCount}deps.txt')
        .writeAsStringSync(generateDependencyGraph());

    // Write event stream
    File('$outputDir/event_stream_${config.eventCount}events.jsonl')
        .writeAsStringSync(generateEventStream());

    print('Fixtures written to $outputDir');
    print('  - styio file: ${config.lineCount} lines');
    print('  - workspace: ${config.packageCount} packages');
    print('  - dependency graph: ${config.dependencyCount} edges');
    print('  - event stream: ${config.eventCount} events');
  }
}

void main(List<String> args) {
  final size = args.isNotEmpty ? args[0] : 'medium';
  final outputDir = args.length > 1 ? args[1] : 'test/fixtures/generated';

  final config = switch (size) {
    'small' => FixtureConfig.small,
    'medium' => FixtureConfig.medium,
    'large' => FixtureConfig.large,
    _ => FixtureConfig.medium,
  };

  final generator = FixtureGenerator(config: config);
  generator.writeToDirectory(outputDir);
}
