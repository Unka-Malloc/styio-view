import 'resource_facts.dart';

class ResourceAdapter {
  const ResourceAdapter(this.facts);
  final ResourceFacts facts;
  ResourceCompatibility adapt() => ResourceCompatibility(
    targetId: facts.targetId,
    compatibilityTarget: facts.compatibilityTarget,
    processorCount: facts.processorCount,
    systemTempPath: facts.systemTempPath,
    homePath: facts.homePath,
    supportsTempDirectory: facts.supportsTempDirectory,
    supportsStorageProbe: facts.supportsStorageProbe,
  );
}

class ResourceCompatibility {
  const ResourceCompatibility({
    required this.targetId,
    required this.compatibilityTarget,
    required this.processorCount,
    required this.systemTempPath,
    required this.homePath,
    required this.supportsTempDirectory,
    required this.supportsStorageProbe,
  });

  final String targetId;
  final String compatibilityTarget;
  final int processorCount;
  final String systemTempPath;
  final String? homePath;
  final bool supportsTempDirectory;
  final bool supportsStorageProbe;
  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}
