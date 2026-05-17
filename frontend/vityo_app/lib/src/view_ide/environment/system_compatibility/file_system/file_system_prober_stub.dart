// ignore_for_file: use_super_parameters

import 'dart:async';

import 'file_system_facts.dart';
import 'file_system_prober.dart';

class UnsupportedFileSystemProber implements FileSystemProber {
  const UnsupportedFileSystemProber({this.targetId = 'unsupported'});

  final String targetId;

  @override
  Future<FileSystemFacts> probe() async {
    return FileSystemFacts(
      targetId: targetId,
      operatingSystem: 'unknown',
      distributionId: 'unknown',
      distributionName: 'Unknown',
      architecture: 'unknown',
      pathStyle: FileSystemPathStyle.unknown,
      pathSeparator: '/',
      providerKind: FileSystemProviderKind.unknown,
      watchSupport: FileSystemWatchSupport.none,
      caseSensitive: true,
      supportsFileUri: false,
      supportsSymbolicLinks: false,
      supportsAtomicWrite: false,
      detectedAt: DateTime.now().toUtc(),
      entries: const <String, PlatformContextFact>{},
    );
  }
}

class LocalFileSystemProber extends UnsupportedFileSystemProber {
  const LocalFileSystemProber({
    String targetId = 'local',
    String? operatingSystem,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  }) : super(targetId: targetId);
}
