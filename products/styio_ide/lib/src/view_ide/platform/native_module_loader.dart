import 'platform_target.dart';

enum NativeBridgeState {
  unavailable,
  deferred,
  ready,
}

class NativeBridgeDescriptor {
  const NativeBridgeDescriptor({
    required this.moduleId,
    required this.state,
    required this.detail,
  });

  final String moduleId;
  final NativeBridgeState state;
  final String detail;
}

abstract class NativeModuleLoader {
  Future<NativeBridgeDescriptor> describe(String moduleId);
}

class NoopNativeModuleLoader implements NativeModuleLoader {
  const NoopNativeModuleLoader({
    required this.platformTarget,
  });

  final PlatformTarget platformTarget;

  @override
  Future<NativeBridgeDescriptor> describe(String moduleId) async {
    if (moduleId == 'local.runtime.desktop') {
      if (platformTarget == PlatformTarget.ios ||
          platformTarget == PlatformTarget.web) {
        return const NativeBridgeDescriptor(
          moduleId: 'local.runtime.desktop',
          state: NativeBridgeState.unavailable,
          detail: 'Local runtime is hidden on this platform.',
        );
      }

      return const NativeBridgeDescriptor(
        moduleId: 'local.runtime.desktop',
        state: NativeBridgeState.deferred,
        detail: 'FFI bridge slot is reserved for M3/M4 native integration.',
      );
    }

    return NativeBridgeDescriptor(
      moduleId: moduleId,
      state: NativeBridgeState.deferred,
      detail: 'Module bridge is reserved for ${platformTarget.label}.',
    );
  }
}
