import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
import 'clipboard_facts.dart';
import 'clipboard_prober.dart';

class LocalClipboardProber implements ClipboardProber {
  const LocalClipboardProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.environment,
    this.architectureReader,
    this.osReleaseReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Map<String, String>? environment;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;

  @override
  Future<ClipboardFacts> probe() async {
    final env = environment ?? Platform.environment;
    final os = localOperatingSystem(operatingSystem);
    final release = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final hasDisplay = os == 'windows' ||
        (env['DISPLAY']?.isNotEmpty ?? false) ||
        (env['WAYLAND_DISPLAY']?.isNotEmpty ?? false);
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
          environment: env,
        )) ??
        'unknown';
    return ClipboardFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: architecture,
      providerKind: hasDisplay
          ? ClipboardProviderKind.system
          : ClipboardProviderKind.memoryFallback,
      supportsText: true,
      supportsSystemClipboard: hasDisplay,
      supportsMemoryFallback: true,
      detectedAt: (clock ?? DateTime.now)().toUtc(),
    );
  }
}
