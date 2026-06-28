import 'dart:async';

import 'network_facts.dart';
import 'network_prober.dart';

class WebNetworkProber implements NetworkProber {
  const WebNetworkProber();

  @override
  Future<NetworkFacts> probe() async {
    return NetworkFacts.webHosted(detectedAt: DateTime.now().toUtc());
  }
}

class LocalNetworkProber extends WebNetworkProber {
  const LocalNetworkProber({
    String targetId = 'web',
    String? operatingSystem,
    Map<String, String>? environment,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  });
}
