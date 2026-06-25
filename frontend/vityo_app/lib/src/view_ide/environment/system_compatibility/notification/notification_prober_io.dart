import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
import 'notification_facts.dart';
import 'notification_prober.dart';

class LocalNotificationProber implements NotificationProber {
  const LocalNotificationProber({
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
  Future<NotificationFacts> probe() async {
    final env = environment ?? Platform.environment;
    final os = localOperatingSystem(operatingSystem);
    final release = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final desktop =
        os == 'windows' || os == 'macos' || await _hasNotifySend();
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
          environment: env,
        )) ??
        'unknown';
    return NotificationFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: architecture,
      providerKind: desktop
          ? NotificationProviderKind.desktop
          : NotificationProviderKind.inAppFallback,
      supportsDesktopNotifications: desktop,
      supportsInAppFallback: true,
      detectedAt: (clock ?? DateTime.now)().toUtc(),
    );
  }

  Future<bool> _hasNotifySend() async {
    try {
      final result = await Process.run(
        'which',
        const <String>['notify-send'],
      ).timeout(const Duration(milliseconds: 500));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }
}
