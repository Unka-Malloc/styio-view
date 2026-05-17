import 'dart:async';
import 'dart:io';

import 'resource_facts.dart';
import 'resource_prober.dart';

class LocalResourceProber implements ResourceProber {
  const LocalResourceProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.environment,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final Map<String, String>? environment;
  final DateTime Function()? clock;

  @override
  Future<ResourceFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final env = environment ?? Platform.environment;
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final release = await _readOsRelease();
    return ResourceFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: (await _readArchitecture()) ?? 'unknown',
      providerKind: ResourceProviderKind.local,
      processorCount: Platform.numberOfProcessors,
      systemTempPath: Directory.systemTemp.path,
      homePath: env['HOME'] ?? env['USERPROFILE'],
      supportsTempDirectory: true,
      supportsHomeDirectory: (env['HOME'] ?? env['USERPROFILE']) != null,
      supportsStorageProbe: true,
      detectedAt: detectedAt,
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
    final result = <String, String>{};
    for (final rawLine in (await file.readAsString()).split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue;
      final separator = line.indexOf('=');
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
      result[line.substring(0, separator).trim()] = value;
    }
    return result;
  }
}
