import 'dart:io';

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
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.resource ??
      await (prober ?? const LocalResourceProber()).probe();
  return LocalResourceManager(facts: facts, adapter: adapter?.resourceAdapter);
}

class LocalResourceManager implements ResourceManager {
  LocalResourceManager({required this.facts, ResourceAdapter? adapter})
    : compatibility = (adapter ?? ResourceAdapter(facts)).adapt();
  factory LocalResourceManager.linuxDebianArmForTest({
    String systemTempPath = '/tmp',
  }) => LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(systemTempPath: systemTempPath),
  );
  @override
  final ResourceFacts facts;
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
      sourceManager: 'LocalResourceManager',
      platformFailureKindResolver: _localResourceFailureKind,
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
    final dir = await Directory.systemTemp.createTemp(prefix);
    return dir.path;
  }
}

ResourceFailureKind? _localResourceFailureKind(Object error) {
  if (error is! FileSystemException) {
    return null;
  }
  return switch (error.osError?.errorCode) {
    13 => ResourceFailureKind.permissionDenied,
    28 => ResourceFailureKind.resourceLimit,
    _ => ResourceFailureKind.unavailable,
  };
}
