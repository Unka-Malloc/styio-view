import 'dart:async';

import '../runtime/runtime.dart';
import 'debug_adapter_protocol.dart';
import 'debug_adapter_session.dart';
import 'debug_adapter_transport.dart';
import 'debug_launch_contract.dart';

typedef DapByteTransportFactory =
    Future<DapByteTransport> Function(DebugLaunchConfiguration launch);

enum DapDebugAdapterExecutionPlanStatus {
  ready,
  blockedLaunch,
  blockedProtocol,
}

extension DapDebugAdapterExecutionPlanStatusX
    on DapDebugAdapterExecutionPlanStatus {
  String get wireValue => switch (this) {
    DapDebugAdapterExecutionPlanStatus.ready => 'ready',
    DapDebugAdapterExecutionPlanStatus.blockedLaunch => 'blocked-launch',
    DapDebugAdapterExecutionPlanStatus.blockedProtocol => 'blocked-protocol',
  };
}

class DapDebugAdapterExecutionPlan {
  const DapDebugAdapterExecutionPlan({
    required this.profileId,
    required this.launchConfiguration,
    required this.routePlan,
    required this.outputBinding,
    required this.status,
    required this.message,
    this.todo = '',
  });

  factory DapDebugAdapterExecutionPlan.fromConfiguration({
    required String profileId,
    required DebugLaunchConfiguration launchConfiguration,
  }) {
    final routePlan = launchConfiguration.toRoutePlan(
      profileId: profileId,
      target: RuntimeExecutionHandoffTarget.terminalRuntime,
    );
    final outputBinding = routePlan.handoff.bind(
      outputKind: RuntimeOutputChannelKind.debug,
      metadata: const <String, Object?>{
        'debugAdapterExecution': 'dap-launcher',
      },
    );
    if (!launchConfiguration.ready || !routePlan.ready) {
      return DapDebugAdapterExecutionPlan(
        profileId: profileId,
        launchConfiguration: launchConfiguration,
        routePlan: routePlan,
        outputBinding: outputBinding,
        status: DapDebugAdapterExecutionPlanStatus.blockedLaunch,
        message: launchConfiguration.reason,
      );
    }
    if (launchConfiguration.adapterProtocol.toLowerCase() != 'dap') {
      return DapDebugAdapterExecutionPlan(
        profileId: profileId,
        launchConfiguration: launchConfiguration,
        routePlan: routePlan,
        outputBinding: outputBinding,
        status: DapDebugAdapterExecutionPlanStatus.blockedProtocol,
        message:
            'Debug profile $profileId requires DAP but uses ${launchConfiguration.adapterProtocol}.',
      );
    }
    return DapDebugAdapterExecutionPlan(
      profileId: profileId,
      launchConfiguration: launchConfiguration,
      routePlan: routePlan,
      outputBinding: outputBinding,
      status: DapDebugAdapterExecutionPlanStatus.ready,
      message: 'DAP debug adapter execution plan is ready.',
      todo:
          'TODO: connect this launch plan to a live adapter process and lifecycle telemetry stream.',
    );
  }

  final String profileId;
  final DebugLaunchConfiguration launchConfiguration;
  final DebugLaunchRoutePlan routePlan;
  final RuntimeExecutionHandoffBinding outputBinding;
  final DapDebugAdapterExecutionPlanStatus status;
  final String message;
  final String todo;

  bool get ready => status == DapDebugAdapterExecutionPlanStatus.ready;

  RuntimeOutputStreamSubscriptionPlan outputSubscriptionPlan({
    RuntimeOutputRetentionPolicy retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
  }) {
    return outputBinding.outputSubscriptionPlan(
      retentionPolicy: retentionPolicy,
      metadata: <String, Object?>{
        'debugProfileId': profileId,
        'debugExecutionStatus': status.wireValue,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'status': status.wireValue,
      'ready': ready,
      'message': message,
      'launchConfiguration': launchConfiguration.toJson(),
      'routePlan': routePlan.toJson(),
      'outputBinding': outputBinding.toJson(),
      'outputSubscriptionPlan': outputSubscriptionPlan().toJson(),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

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

  Future<DapDebugSessionHandle> launchExecutionPlan(
    DapDebugAdapterExecutionPlan plan,
  ) {
    if (!plan.ready) {
      throw StateError(plan.message);
    }
    return launch(plan.launchConfiguration);
  }
}
