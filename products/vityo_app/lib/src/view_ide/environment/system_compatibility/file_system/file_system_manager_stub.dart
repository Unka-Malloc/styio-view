// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'file_system_adapter.dart';
import 'file_system_facts.dart';
import 'file_system_manager.dart';
import 'file_system_prober.dart';

Future<FileSystemManager> createPlatformFileSystemManager({
  FileSystemProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedFileSystemManager(facts: platformContext.fileSystem);
  }
  final facts = prober == null
      ? FileSystemFacts(
          targetId: 'unsupported',
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
        )
      : await prober.probe();
  return UnsupportedFileSystemManager(facts: facts);
}

class LocalFileSystemManager extends UnsupportedFileSystemManager {
  LocalFileSystemManager({
    required FileSystemFacts facts,
    FileSystemAdapter? adapter,
  }) : super(facts: facts);

  factory LocalFileSystemManager.linuxDebianArmForTest() {
    return LocalFileSystemManager(facts: FileSystemFacts.linuxDebianArm());
  }
}
