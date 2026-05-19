import 'dart:async';

import 'debug_adapter_protocol.dart';
import 'debug_adapter_session.dart';
import 'debug_adapter_transport.dart';
import 'debug_launch_contract.dart';

typedef DapByteTransportFactory =
    Future<DapByteTransport> Function(DebugLaunchConfiguration launch);

class DapDebugSessionHandle {
  const DapDebugSessionHandle({
    required this.launchConfiguration,
    required this.launchPlan,
    required this.bridge,
  });

  final DebugLaunchConfiguration launchConfiguration;
  final DapLaunchRequestPlan launchPlan;
  final DapSessionTransportBridge bridge;

  DapSessionSnapshot get snapshot => bridge.snapshot;
  Stream<DapSessionSnapshot> get snapshotEvents => bridge.snapshotEvents;

  Future<void> sendRequest(DapRequest request) {
    return bridge.sendRequest(request);
  }

  Future<void> close() {
    return bridge.close();
  }
}

class DapDebugAdapterLauncher {
  const DapDebugAdapterLauncher({required this.transportFactory});

  final DapByteTransportFactory transportFactory;

  Future<DapDebugSessionHandle> launch(
    DebugLaunchConfiguration launchConfiguration,
  ) async {
    if (!launchConfiguration.ready) {
      throw StateError(launchConfiguration.reason);
    }
    final transport = await transportFactory(launchConfiguration);
    final bridge = DapSessionTransportBridge(transport: transport);
    final launchPlan = DapLaunchRequestPlan.fromLaunchConfiguration(
      launch: launchConfiguration,
    );
    bridge.attach();
    await bridge.sendLaunchPlan(launchPlan);
    return DapDebugSessionHandle(
      launchConfiguration: launchConfiguration,
      launchPlan: launchPlan,
      bridge: bridge,
    );
  }
}
