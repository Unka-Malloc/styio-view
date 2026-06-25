import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
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
    final os = localOperatingSystem(operatingSystem);
    final osRelease = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
        )) ??
        'unknown';
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

}
