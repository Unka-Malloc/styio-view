import 'dart:async';

import 'local_service_facts.dart';
import 'local_service_prober.dart';

class UnsupportedLocalServiceProber implements LocalServiceProber {
  const UnsupportedLocalServiceProber();
  @override
  Future<LocalServiceFacts> probe() async => LocalServiceFacts(
    targetId: 'unsupported',
    operatingSystem: 'unknown',
    distributionId: 'unknown',
    architecture: 'unknown',
    providerKind: LocalServiceProviderKind.unsupported,
    supportsLoopbackHttpServer: false,
    supportsEphemeralPort: false,
    detectedAt: DateTime.now().toUtc(),
  );
}

class LocalLoopbackServiceProber extends UnsupportedLocalServiceProber {
  const LocalLoopbackServiceProber({
    String targetId = 'local',
    String? operatingSystem,
    Map<String, String>? environment,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  });
}
