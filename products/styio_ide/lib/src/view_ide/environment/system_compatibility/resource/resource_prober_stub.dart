import 'dart:async';

import 'resource_facts.dart';
import 'resource_prober.dart';

class UnsupportedResourceProber implements ResourceProber {
  const UnsupportedResourceProber();
  @override
  Future<ResourceFacts> probe() async => ResourceFacts(
    targetId: 'unsupported',
    operatingSystem: 'unknown',
    distributionId: 'unknown',
    architecture: 'unknown',
    providerKind: ResourceProviderKind.unknown,
    processorCount: 1,
    systemTempPath: '/tmp',
    supportsTempDirectory: false,
    supportsHomeDirectory: false,
    supportsStorageProbe: false,
    detectedAt: DateTime.now().toUtc(),
  );
}

class LocalResourceProber extends UnsupportedResourceProber {
  const LocalResourceProber({
    String targetId = 'local',
    String? operatingSystem,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    Map<String, String>? environment,
    DateTime Function()? clock,
  });
}
