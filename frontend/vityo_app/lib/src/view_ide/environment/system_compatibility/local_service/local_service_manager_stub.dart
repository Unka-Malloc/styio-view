// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'local_service_adapter.dart';
import 'local_service_facts.dart';
import 'local_service_manager.dart';
import 'local_service_prober.dart';
import 'local_service_prober_stub.dart';

Future<LocalServiceManager> createPlatformLocalServiceManager({
  LocalServiceProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedLocalServiceManager(facts: platformContext.localService);
  }
  final facts = await (prober ?? const UnsupportedLocalServiceProber()).probe();
  return UnsupportedLocalServiceManager(facts: facts);
}

class LoopbackLocalServiceManager extends UnsupportedLocalServiceManager {
  LoopbackLocalServiceManager({
    required LocalServiceFacts facts,
    LocalServiceAdapter? adapter,
  }) : super(facts: facts);

  factory LoopbackLocalServiceManager.linuxDebianArmForTest() {
    return LoopbackLocalServiceManager(
      facts: LocalServiceFacts.linuxDebianArm(),
    );
  }
}
