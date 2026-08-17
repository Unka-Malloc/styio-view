import 'package:flutter/foundation.dart';

import '../vityod_client.dart';
import 'platform_policy.dart';

typedef VityodTransportFactory = VityodTransport Function();

/// Creates the native gateway only for desktop targets.
///
/// Hosted and blocked platforms deliberately receive no client, keeping the
/// native daemon implementation out of their composition root.
final class VityodClientFactory {
  const VityodClientFactory({required this.transportFactory});

  final VityodTransportFactory transportFactory;

  VityodClient? create({
    required bool isWeb,
    required TargetPlatform platform,
    required String clientInstanceId,
  }) {
    final route = VityodPlatformPolicy.routeFor(
      isWeb: isWeb,
      platform: platform,
    );
    if (route != VityodBackendRoute.localDaemon) return null;
    return VityodClient(
      transport: transportFactory(),
      clientInstanceId: clientInstanceId,
    );
  }
}
