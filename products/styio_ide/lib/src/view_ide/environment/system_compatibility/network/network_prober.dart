import 'network_facts.dart';

abstract class NetworkProber {
  Future<NetworkFacts> probe();
}

class StaticNetworkProber implements NetworkProber {
  const StaticNetworkProber(this.facts);
  final NetworkFacts facts;
  @override
  Future<NetworkFacts> probe() async => facts;
}
