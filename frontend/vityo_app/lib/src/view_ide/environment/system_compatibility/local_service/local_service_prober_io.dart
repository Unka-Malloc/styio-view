import 'dart:async';
import 'dart:io';

import 'local_service_facts.dart';
import 'local_service_prober.dart';

class LocalLoopbackServiceProber implements LocalServiceProber {
  const LocalLoopbackServiceProber({this.targetId = 'local', this.architectureReader, this.osReleaseReader, this.clock});
  final String targetId;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;
  @override
  Future<LocalServiceFacts> probe() async {
    final release = await _readOsRelease();
    return LocalServiceFacts(targetId: targetId, operatingSystem: Platform.operatingSystem.toLowerCase(), distributionId: release['ID']?.toLowerCase() ?? 'unknown', architecture: (await _readArchitecture()) ?? 'unknown', providerKind: LocalServiceProviderKind.loopback, supportsLoopbackHttpServer: true, supportsEphemeralPort: true, detectedAt: (clock ?? DateTime.now)().toUtc());
  }
  Future<String?> _readArchitecture() async { final reader = architectureReader; if (reader != null) return reader(); try { final result = await Process.run('uname', const <String>['-m']).timeout(const Duration(milliseconds: 500)); if (result.exitCode == 0) return result.stdout.toString().trim().toLowerCase(); } on Object { return null; } return null; }
  Future<Map<String, String>> _readOsRelease() async { final reader = osReleaseReader; if (reader != null) return reader(); final file = File('/etc/os-release'); if (!await file.exists()) return const <String, String>{}; final result = <String, String>{}; for (final rawLine in (await file.readAsString()).split('\n')) { final line = rawLine.trim(); if (line.isEmpty || line.startsWith('#') || !line.contains('=')) continue; final separator = line.indexOf('='); var value = line.substring(separator + 1).trim(); if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1); result[line.substring(0, separator).trim()] = value; } return result; }
}
