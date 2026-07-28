// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'resource_adapter.dart';
import 'resource_facts.dart';
import 'resource_manager.dart';
import 'resource_prober.dart';
import 'resource_prober_stub.dart';

Future<ResourceManager> createPlatformResourceManager({
  ResourceProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedResourceManager(facts: platformContext.resource);
  }
  final facts = await (prober ?? const UnsupportedResourceProber()).probe();
  return UnsupportedResourceManager(facts: facts);
}

class LocalResourceManager extends UnsupportedResourceManager {
  LocalResourceManager({required ResourceFacts facts, ResourceAdapter? adapter})
    : super(facts: facts);

  factory LocalResourceManager.linuxDebianArmForTest({
    String systemTempPath = '/tmp',
  }) {
    return LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(systemTempPath: systemTempPath),
    );
  }
}
