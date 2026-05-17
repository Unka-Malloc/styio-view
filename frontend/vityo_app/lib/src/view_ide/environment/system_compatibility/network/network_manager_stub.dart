// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'network_adapter.dart';
import 'network_facts.dart';
import 'network_manager.dart';
import 'network_prober.dart';
import 'network_prober_stub.dart';

Future<NetworkManager> createPlatformNetworkManager({
  NetworkProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedNetworkManager(facts: platformContext.network);
  }
  final facts = await (prober ?? const UnsupportedNetworkProber()).probe();
  return UnsupportedNetworkManager(facts: facts);
}

class LocalNetworkManager extends UnsupportedNetworkManager {
  LocalNetworkManager({required NetworkFacts facts, NetworkAdapter? adapter})
    : super(facts: facts);

  factory LocalNetworkManager.linuxDebianArmForTest() {
    return LocalNetworkManager(facts: NetworkFacts.linuxDebianArm());
  }
}
