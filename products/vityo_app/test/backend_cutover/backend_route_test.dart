import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/local_service/platform/client_factory.dart';
import 'package:vityo_app/src/ide/local_service/platform/platform_policy.dart';
import 'package:vityo_app/src/ide/local_service/vityod_client.dart';

void main() {
  test('desktop targets compose exactly one local daemon gateway', () {
    var transportsCreated = 0;
    final factory = VityodClientFactory(
      transportFactory: () {
        transportsCreated += 1;
        return MemoryVityodTransport();
      },
    );

    for (final platform in const <TargetPlatform>[
      TargetPlatform.linux,
      TargetPlatform.macOS,
      TargetPlatform.windows,
    ]) {
      final client = factory.create(
        isWeb: false,
        platform: platform,
        clientInstanceId: 'desktop-${platform.name}',
      );
      expect(client, isNotNull);
    }
    expect(transportsCreated, 3);
  });

  test('web and mobile preserve hosted or explicitly blocked routing', () {
    var transportsCreated = 0;
    final factory = VityodClientFactory(
      transportFactory: () {
        transportsCreated += 1;
        return MemoryVityodTransport();
      },
    );

    for (final route in <({bool isWeb, TargetPlatform platform})>[
      (isWeb: true, platform: TargetPlatform.linux),
      (isWeb: false, platform: TargetPlatform.android),
      (isWeb: false, platform: TargetPlatform.iOS),
      (isWeb: false, platform: TargetPlatform.fuchsia),
    ]) {
      expect(
        factory.create(
          isWeb: route.isWeb,
          platform: route.platform,
          clientInstanceId: 'hosted-${route.platform.name}',
        ),
        isNull,
      );
      expect(
        VityodPlatformPolicy.routeFor(
          isWeb: route.isWeb,
          platform: route.platform,
        ),
        VityodBackendRoute.hostedOrBlocked,
      );
    }
    expect(transportsCreated, 0);
  });
}
