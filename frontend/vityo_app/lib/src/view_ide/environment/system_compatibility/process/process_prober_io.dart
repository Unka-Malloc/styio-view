import 'dart:async';
import 'dart:io';

import 'process_facts.dart';
import 'process_prober.dart';

class LocalProcessProber implements ProcessProber {
  const LocalProcessProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;

  @override
  Future<ProcessFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final release = await _readOsRelease();
    final architecture = (await _readArchitecture()) ?? 'unknown';
    final distributionId = release['ID']?.toLowerCase() ?? 'unknown';
    final distributionName = release['PRETTY_NAME'] ?? distributionId;
    final supportsSpawn = os == 'linux' || os == 'macos' || os == 'windows';
    return ProcessFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: ProcessProviderKind.local,
      supportsSpawn: supportsSpawn,
      supportsSignals: os == 'linux' || os == 'macos',
      supportsProcessGroups: os == 'linux' || os == 'macos',
      supportsEnvironmentOverlay: supportsSpawn,
      supportsWorkingDirectory: supportsSpawn,
      detectedAt: detectedAt,
      entries: ProcessFacts.buildEntries(
        targetId: targetId,
        operatingSystem: os,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: ProcessProviderKind.local,
        supportsSpawn: supportsSpawn,
        supportsSignals: os == 'linux' || os == 'macos',
        supportsProcessGroups: os == 'linux' || os == 'macos',
        supportsEnvironmentOverlay: supportsSpawn,
        supportsWorkingDirectory: supportsSpawn,
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
  }

  Future<String?> _readArchitecture() async {
    final reader = architectureReader;
    if (reader != null) return reader();
    try {
      final result = await Process.run('uname', const <String>['-m']).timeout(const Duration(milliseconds: 500));
      if (result.exitCode == 0) return result.stdout.toString().trim().toLowerCase();
    } on Object {
      return null;
    }
    return null;
  }

  Future<Map<String, String>> _readOsRelease() async {
    final reader = osReleaseReader;
    if (reader != null) return reader();
    final file = File('/etc/os-release');
    if (!await file.exists()) return const <String, String>{};
    try {
      return _parseOsRelease(await file.readAsString());
    } on Object {
      return const <String, String>{};
    }
  }

  Map<String, String> _parseOsRelease(String text) {
    final result = <String, String>{};
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
      final separator = line.indexOf('=');
      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 && ((value[0] == '"' && value[value.length - 1] == '"') || (value[0] == "'" && value[value.length - 1] == "'"))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }
}
