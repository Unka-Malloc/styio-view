@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
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
}
