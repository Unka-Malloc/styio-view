import 'dart:async';

import '../host_platform_io.dart';
import 'file_system_facts.dart';
import 'file_system_prober.dart';

class LocalFileSystemProber implements FileSystemProber {
  const LocalFileSystemProber({
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
  Future<FileSystemFacts> probe() async {
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
    final pathStyle = os == 'windows'
        ? FileSystemPathStyle.windows
        : FileSystemPathStyle.posix;
    final pathSeparator = os == 'windows' ? r'\' : '/';
    final watchSupport = os == 'windows'
        ? FileSystemWatchSupport.recursive
        : os == 'linux'
        ? FileSystemWatchSupport.directory
        : FileSystemWatchSupport.unknown;
    final caseSensitive = os == 'linux' || os == 'android';
    final supportsSymbolicLinks = os == 'linux' || os == 'macos';
    final supportsAtomicWrite = os == 'linux' || os == 'macos' || os == 'windows';

    return FileSystemFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      pathStyle: pathStyle,
      pathSeparator: pathSeparator,
      providerKind: FileSystemProviderKind.local,
      watchSupport: watchSupport,
      caseSensitive: caseSensitive,
      supportsFileUri: true,
      supportsSymbolicLinks: supportsSymbolicLinks,
      supportsAtomicWrite: supportsAtomicWrite,
      detectedAt: detectedAt,
      entries: FileSystemFacts.buildEntries(
        targetId: targetId,
        operatingSystem: os,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        pathStyle: pathStyle,
        pathSeparator: pathSeparator,
        providerKind: FileSystemProviderKind.local,
        watchSupport: watchSupport,
        caseSensitive: caseSensitive,
        supportsFileUri: true,
        supportsSymbolicLinks: supportsSymbolicLinks,
        supportsAtomicWrite: supportsAtomicWrite,
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
  }

}
