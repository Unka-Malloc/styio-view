import 'dart:async';
import 'dart:io';

import 'pty_facts.dart';
import 'pty_prober.dart';

class LocalPtyProber implements PtyProber {
  const LocalPtyProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.scriptPathReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final Future<String?> Function()? scriptPathReader;
  final DateTime Function()? clock;

  @override
  Future<PtyFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final os = (operatingSystem ?? Platform.operatingSystem).toLowerCase();
    final osRelease = await _readOsRelease();
    final architecture = (await _readArchitecture()) ?? 'unknown';
    final distributionId = osRelease['ID']?.toLowerCase() ?? 'unknown';
    final distributionName = osRelease['PRETTY_NAME'] ?? distributionId;
    final scriptPath = os == 'linux' ? await _readScriptPath() : null;
    final supportsScriptUtility = scriptPath != null;
    final providerKind = supportsScriptUtility
        ? PtyProviderKind.scriptUtility
        : PtyProviderKind.unsupported;

    return PtyFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: providerKind,
      supportsPty: supportsScriptUtility,
      supportsResize: false,
      supportsRawMode: supportsScriptUtility,
      supportsSignals: supportsScriptUtility,
      supportsProcessGroup: false,
      supportsConPty: false,
      supportsForkPty: false,
      supportsScriptUtility: supportsScriptUtility,
      scriptUtilityPath: scriptPath,
      detectedAt: detectedAt,
      entries: PtyFacts.buildEntries(
        targetId: targetId,
        operatingSystem: os,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: providerKind,
        supportsPty: supportsScriptUtility,
        supportsResize: false,
        supportsRawMode: supportsScriptUtility,
        supportsSignals: supportsScriptUtility,
        supportsProcessGroup: false,
        supportsConPty: false,
        supportsForkPty: false,
        supportsScriptUtility: supportsScriptUtility,
        scriptUtilityPath: scriptPath,
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
  }

  Future<String?> _readScriptPath() async {
    final reader = scriptPathReader;
    if (reader != null) {
      return reader();
    }
    try {
      final result = await Process.run(
        'which',
        const <String>['script'],
      ).timeout(const Duration(milliseconds: 500));
      if (result.exitCode == 0) {
        final value = result.stdout.toString().trim();
        return value.isEmpty ? null : value;
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<String?> _readArchitecture() async {
    final reader = architectureReader;
    if (reader != null) {
      return reader();
    }
    try {
      final result = await Process.run(
        'uname',
        const <String>['-m'],
      ).timeout(const Duration(milliseconds: 500));
      if (result.exitCode == 0) {
        return result.stdout.toString().trim().toLowerCase();
      }
    } on Object {
      return null;
    }
    return null;
  }

  Future<Map<String, String>> _readOsRelease() async {
    final reader = osReleaseReader;
    if (reader != null) {
      return reader();
    }
    final file = File('/etc/os-release');
    if (!await file.exists()) {
      return const <String, String>{};
    }
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
      if (line.isEmpty || line.startsWith('#') || !line.contains('=')) {
        continue;
      }
      final separator = line.indexOf('=');
      final key = line.substring(0, separator).trim();
      var value = line.substring(separator + 1).trim();
      if (value.length >= 2 &&
          ((value[0] == '"' && value[value.length - 1] == '"') ||
              (value[0] == "'" && value[value.length - 1] == "'"))) {
        value = value.substring(1, value.length - 1);
      }
      result[key] = value;
    }
    return result;
  }
}
