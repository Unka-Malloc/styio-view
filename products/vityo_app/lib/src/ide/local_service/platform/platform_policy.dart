import 'package:flutter/foundation.dart';

enum VityodBackendRoute { localDaemon, hostedOrBlocked }

abstract final class VityodPlatformPolicy {
  static bool get supportsLocalDaemon {
    return routeFor(isWeb: kIsWeb, platform: defaultTargetPlatform) ==
        VityodBackendRoute.localDaemon;
  }

  static VityodBackendRoute routeFor({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) return VityodBackendRoute.hostedOrBlocked;
    return switch (platform) {
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => VityodBackendRoute.localDaemon,
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => VityodBackendRoute.hostedOrBlocked,
    };
  }
}
