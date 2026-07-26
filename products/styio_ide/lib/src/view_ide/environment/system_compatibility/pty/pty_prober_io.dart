import 'dart:ffi';

import '../host_platform_io.dart';
import 'pty_facts.dart';
import 'pty_prober.dart';

class LocalPtyProber implements PtyProber {
  const LocalPtyProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.conPtyAvailabilityReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final Future<bool> Function()? conPtyAvailabilityReader;
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
    final isWindows = os == 'windows';
    final available = isWindows
        ? await _supportsConPty()
        : os == 'linux' || os == 'macos';
    return PtyFacts.native(
      targetId: targetId,
      operatingSystem: os,
      distributionId: osRelease['ID']?.toLowerCase() ?? os,
      distributionName: osRelease['PRETTY_NAME'] ?? os,
      architecture: architecture,
      available: available,
      detectedAt: detectedAt,
    );
  }

  Future<bool> _supportsConPty() async {
    final reader = conPtyAvailabilityReader;
    if (reader != null) return reader();
    try {
      return DynamicLibrary.open(
        'kernel32.dll',
      ).providesSymbol('CreatePseudoConsole');
    } on Object {
      return false;
    }
  }
}
