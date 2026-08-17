import '../file_system/file_system_manager.dart';
import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'resource_adapter.dart';
import 'resource_facts.dart';
import 'resource_manager.dart';
import 'resource_prober.dart';
import 'resource_prober_io.dart';

Future<ResourceManager> createPlatformResourceManager({
  ResourceProber? prober,
  PlatformContextSnapshot? platformContext,
  FileSystemManager? fileSystemManager,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.resource ??
      await (prober ?? const LocalResourceProber()).probe();
  return LocalResourceManager(
    facts: facts,
    adapter: adapter?.resourceAdapter,
    fileSystemManager: fileSystemManager,
  );
}

class LocalResourceManager implements ResourceManager {
  LocalResourceManager({
    required this.facts,
    ResourceAdapter? adapter,
    FileSystemManager? fileSystemManager,
  }) : _fileSystemManager = fileSystemManager,
       compatibility = (adapter ?? ResourceAdapter(facts)).adapt();
  factory LocalResourceManager.linuxDebianArmForTest({
    String systemTempPath = '/tmp',
  }) => LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(systemTempPath: systemTempPath),
  );
  @override
  final ResourceFacts facts;
  final FileSystemManager? _fileSystemManager;
  var _temporarySequence = 0;
  @override
  final ResourceCompatibility compatibility;
  @override
  ResourceSnapshot snapshot() => ResourceSnapshot(
    processorCount: compatibility.processorCount,
    systemTempPath: compatibility.systemTempPath,
    homePath: compatibility.homePath,
  );
  @override
  ResourceOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return const ResourceFailureClassifier(
      sourceManager: 'VityodResourceManager',
    ).classify(
      error,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<String> createTempDirectory(String prefix) async {
    if (!compatibility.supportsTempDirectory) {
      throw UnsupportedError('Temporary directories are not available.');
    }
    final fileSystem = _fileSystemManager;
    if (fileSystem == null) {
      throw UnsupportedError(
        'Temporary directories require the local service file gateway.',
      );
    }
    final safePrefix = prefix.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final candidate = fileSystem.joinPath(<String>[
        compatibility.systemTempPath,
        '$safePrefix${DateTime.now().microsecondsSinceEpoch}-${++_temporarySequence}',
      ]);
      if (await fileSystem.exists(candidate)) continue;
      await fileSystem.createDirectory(candidate);
      return candidate;
    }
    throw StateError('Temporary directory allocation was exhausted.');
  }
}
