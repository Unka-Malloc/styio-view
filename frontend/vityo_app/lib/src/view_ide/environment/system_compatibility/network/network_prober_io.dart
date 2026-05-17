import 'dart:async';
import 'dart:io';

import 'network_facts.dart';
import 'network_prober.dart';

class LocalNetworkProber implements NetworkProber {
  const LocalNetworkProber({this.targetId = 'local', this.environment, this.architectureReader, this.osReleaseReader, this.clock});
  final String targetId;
  final Map<String, String>? environment;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;
  @override
  Future<NetworkFacts> probe() async {
    final env = environment ?? Platform.environment;
    final release = await _readOsRelease();
    final proxy = <String, String>{};
    for (final key in const <String>['HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'no_proxy']) {
      final value = env[key];
      if (value != null && value.isNotEmpty) proxy[key] = value;
    }
    return NetworkFacts(
      targetId: targetId,
      operatingSystem: Platform.operatingSystem.toLowerCase(),
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: (await _readArchitecture()) ?? 'unknown',
      providerKind: NetworkProviderKind.local,
      supportsHttpClient: true,
      supportsLoopback: true,
      proxyEnvironment: proxy,
      detectedAt: (clock ?? DateTime.now)().toUtc(),
    );
  }
  Future<String?> _readArchitecture() async {
    final reader = architectureReader;
    if (reader != null) return reader();
    try {
      final result = await Process.run('uname', const <String>['-m']).timeout(const Duration(milliseconds: 500));
      if (result.exitCode == 0) return result.stdout.toString().trim().toLowerCase();
    } on Object { return null; }
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
