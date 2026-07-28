import 'local_service_facts.dart';

class LocalServiceAdapter {
  const LocalServiceAdapter(this.facts);
  final LocalServiceFacts facts;
  LocalServiceCompatibility adapt() => LocalServiceCompatibility(targetId: facts.targetId, compatibilityTarget: facts.compatibilityTarget, supportsLoopbackHttpServer: facts.supportsLoopbackHttpServer, supportsEphemeralPort: facts.supportsEphemeralPort);
}

class LocalServiceCompatibility {
  const LocalServiceCompatibility({required this.targetId, required this.compatibilityTarget, required this.supportsLoopbackHttpServer, required this.supportsEphemeralPort});
  final String targetId;
  final String compatibilityTarget;
  final bool supportsLoopbackHttpServer;
  final bool supportsEphemeralPort;
  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}
