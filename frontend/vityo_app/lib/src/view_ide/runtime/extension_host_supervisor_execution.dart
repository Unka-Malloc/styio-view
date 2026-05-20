import '../module_host/module_host.dart';
import 'runtime_execution_plan.dart';
import 'runtime_output_channels.dart';
import 'runtime_task_lifecycle.dart';

class ExtensionHostSupervisorExecutionPlan {
  const ExtensionHostSupervisorExecutionPlan({
    required this.record,
    required this.definition,
    required this.executionPlan,
    required this.handoff,
    required this.binding,
  });

  factory ExtensionHostSupervisorExecutionPlan.fromRecord(
    ExtensionHostSupervisorRecord record, {
    ExtensionManifest? manifest,
    String outputChannelId = '',
  }) {
    final command = _commandForSupervisorRecord(record, manifest);
    final definition = RuntimeTaskDefinition(
      id: 'extension.host.${record.extensionId}',
      label: 'Start extension host ${record.extensionId}',
      kind: RuntimeTaskKind.agent,
      command: record.active ? command : '',
      arguments: const <String>[],
      metadata: <String, Object?>{
        'extensionHostSupervisor': true,
        'extensionId': record.extensionId,
        'isolationMode': record.plan.mode.wireValue,
        'supervisorStatus': record.status.wireValue,
        'supervisorAction': record.action.wireValue,
        if (manifest != null) 'entrypoint': manifest.entrypoint,
        if (record.action == ExtensionHostSupervisorAction.runInProcess)
          'TODO':
              'Run in-process extension hosts through an isolated service container.',
        if (record.action == ExtensionHostSupervisorAction.spawnLocalProcess)
          'TODO':
              'Spawn local extension hosts through a concrete process sandbox.',
        if (record.action == ExtensionHostSupervisorAction.connectRemoteService)
          'TODO':
              'Connect remote extension hosts through a concrete service client.',
      },
    );
    final executionPlan = const RuntimeExecutionPlanner().plan(
      definition: definition,
    );
    final target = _targetForSupervisorAction(record.action);
    final handoff = executionPlan.createHandoff(
      target: target,
      outputChannelId: outputChannelId.trim().isEmpty
          ? 'extension.host.${record.extensionId}'
          : outputChannelId.trim(),
      metadata: <String, Object?>{
        'extensionHostSupervisor': true,
        'extensionId': record.extensionId,
      },
    );
    final binding = handoff.bind(
      outputKind: _outputKindForSupervisorTarget(target),
      metadata: <String, Object?>{
        'extensionHostSupervisor': true,
        'extensionId': record.extensionId,
        'supervisorAction': record.action.wireValue,
      },
    );
    return ExtensionHostSupervisorExecutionPlan(
      record: record,
      definition: definition,
      executionPlan: executionPlan,
      handoff: handoff,
      binding: binding,
    );
  }

  final ExtensionHostSupervisorRecord record;
  final RuntimeTaskDefinition definition;
  final RuntimeExecutionPlan executionPlan;
  final RuntimeExecutionHandoff handoff;
  final RuntimeExecutionHandoffBinding binding;

  bool get ready => record.active && executionPlan.ready && binding.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'record': record.toJson(),
      'definition': definition.toJson(),
      'executionPlan': executionPlan.toJson(),
      'handoff': handoff.toJson(),
      'binding': binding.toJson(),
    };
  }
}

class ExtensionHostSupervisorExecutionBridge {
  ExtensionHostSupervisorExecutionBridge({
    RuntimeExecutionManagerRegistry? registry,
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers();

  final RuntimeExecutionManagerRegistry _registry;

  RuntimeExecutionDispatchResult dispatchPlan({
    required ExtensionHostSupervisorExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _registry.dispatchToLiveBuffer(
      plan.binding,
      buffer: buffer,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'extensionHostSupervisor': true,
        'extensionId': plan.record.extensionId,
        'supervisorAction': plan.record.action.wireValue,
        ...metadata,
      },
    );
  }

  List<RuntimeExecutionDispatchResult> dispatchSnapshot({
    required ExtensionHostSupervisorSnapshot snapshot,
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    ExtensionManifestRegistry? manifestRegistry,
  }) {
    return snapshot.records
        .where((record) => record.active)
        .map(
          (record) => dispatchPlan(
            plan: ExtensionHostSupervisorExecutionPlan.fromRecord(
              record,
              manifest: manifestRegistry?.lookup(record.extensionId),
            ),
            buffer: buffer,
            timestamp: timestamp,
          ),
        )
        .toList(growable: false);
  }
}

String _commandForSupervisorRecord(
  ExtensionHostSupervisorRecord record,
  ExtensionManifest? manifest,
) {
  final entrypoint = manifest?.entrypoint.trim();
  if (entrypoint != null && entrypoint.isNotEmpty) {
    return entrypoint;
  }
  return 'extension-host:${record.action.wireValue}';
}

RuntimeExecutionHandoffTarget _targetForSupervisorAction(
  ExtensionHostSupervisorAction action,
) {
  return switch (action) {
    ExtensionHostSupervisorAction.spawnLocalProcess =>
      RuntimeExecutionHandoffTarget.shellManager,
    ExtensionHostSupervisorAction.connectRemoteService =>
      RuntimeExecutionHandoffTarget.hostedExecutor,
    ExtensionHostSupervisorAction.runInProcess ||
    ExtensionHostSupervisorAction.spawnWebWorker =>
      RuntimeExecutionHandoffTarget.terminalRuntime,
    ExtensionHostSupervisorAction.none =>
      RuntimeExecutionHandoffTarget.terminalRuntime,
  };
}

RuntimeOutputChannelKind _outputKindForSupervisorTarget(
  RuntimeExecutionHandoffTarget target,
) {
  return switch (target) {
    RuntimeExecutionHandoffTarget.shellManager =>
      RuntimeOutputChannelKind.stdout,
    RuntimeExecutionHandoffTarget.terminalRuntime =>
      RuntimeOutputChannelKind.runtimeEvents,
    RuntimeExecutionHandoffTarget.toolchainManager =>
      RuntimeOutputChannelKind.nativeTools,
    RuntimeExecutionHandoffTarget.hostedExecutor =>
      RuntimeOutputChannelKind.runtimeEvents,
  };
}
