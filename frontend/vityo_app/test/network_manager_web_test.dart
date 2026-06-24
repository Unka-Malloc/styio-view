@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_provider_network_transport.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/network/network.dart';

void main() {
  test('web network manager uses browser fetch for text requests', () async {
    final manager = await createPlatformNetworkManager();

    final response = await manager.getText(
      Uri.parse('data:text/plain,vityo-web-network-ok'),
    );

    expect(manager.compatibility.compatibilityTarget, 'web-hosted');
    expect(manager.compatibility.supportsHttpClient, isTrue);
    expect(response.succeeded, isTrue);
    expect(response.body, 'vityo-web-network-ok');
  });

  test('web network manager supports agent provider JSON transport', () async {
    final manager = await createPlatformNetworkManager();
    final transport = NetworkAgentProviderTransport(networkManager: manager);

    final response = await transport.postJson(
      endpoint: Uri.parse(
        'data:application/json,%7B%22ok%22%3Atrue%7D',
      ),
      headers: const <String, String>{},
      body: const <String, Object?>{'prompt': 'hello'},
    );

    expect(response['ok'], isTrue);
  });
}
