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
    ExtensionHostSandboxLauncherRegistry? sandboxLaunchers,
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers(),
       _sandboxLaunchers =
           sandboxLaunchers ?? ExtensionHostSandboxLauncherRegistry();

  final RuntimeExecutionManagerRegistry _registry;
  final ExtensionHostSandboxLauncherRegistry _sandboxLaunchers;

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

  Future<ExtensionHostSandboxLaunchResult> launchSandboxForPlan({
    required ExtensionHostSupervisorExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final dispatch = dispatchPlan(
      plan: plan,
      buffer: buffer,
      timestamp: timestamp,
      metadata: metadata,
    );
    return _sandboxLaunchers.launch(
      ExtensionHostSandboxLaunchRequest(
        plan: plan,
        dispatchResult: dispatch,
        timestamp: timestamp,
        metadata: metadata,
      ),
    );
  }

  Future<List<ExtensionHostSandboxLaunchResult>> launchSnapshotSandboxes({
    required ExtensionHostSupervisorSnapshot snapshot,
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    ExtensionManifestRegistry? manifestRegistry,
  }) async {
    final results = <ExtensionHostSandboxLaunchResult>[];
    for (final record in snapshot.records.where((record) => record.active)) {
      results.add(
        await launchSandboxForPlan(
          plan: ExtensionHostSupervisorExecutionPlan.fromRecord(
            record,
            manifest: manifestRegistry?.lookup(record.extensionId),
          ),
          buffer: buffer,
          timestamp: timestamp,
        ),
      );
    }
    return results;
  }
}

enum ExtensionHostSandboxLaunchStatus { launched, blocked, missingLauncher }

extension ExtensionHostSandboxLaunchStatusX
    on ExtensionHostSandboxLaunchStatus {
  String get wireValue => switch (this) {
    ExtensionHostSandboxLaunchStatus.launched => 'launched',
    ExtensionHostSandboxLaunchStatus.blocked => 'blocked',
    ExtensionHostSandboxLaunchStatus.missingLauncher => 'missing-launcher',
  };
}

typedef ExtensionHostSandboxLauncher =
    Future<ExtensionHostSandboxLaunchResult> Function(
      ExtensionHostSandboxLaunchRequest request,
    );

class ExtensionHostSandboxLaunchRequest {
  const ExtensionHostSandboxLaunchRequest({
    required this.plan,
    required this.dispatchResult,
    required this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  final ExtensionHostSupervisorExecutionPlan plan;
  final RuntimeExecutionDispatchResult dispatchResult;
  final DateTime timestamp;
  final Map<String, Object?> metadata;

  String get extensionId => plan.record.extensionId;
  ExtensionHostSupervisorAction get action => plan.record.action;
  String get managerId => dispatchResult.binding.managerId;
  bool get dispatchReady => dispatchResult.dispatched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'action': action.wireValue,
      'managerId': managerId,
      'dispatchReady': dispatchReady,
      'timestamp': timestamp.toIso8601String(),
      'plan': plan.toJson(),
      'dispatchResult': dispatchResult.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionHostSandboxLauncherRegistration {
  const ExtensionHostSandboxLauncherRegistration({
    required this.launcherId,
    required this.label,
    required this.action,
    required this.launcher,
    this.available = true,
    this.metadata = const <String, Object?>{},
  });

  final String launcherId;
  final String label;
  final ExtensionHostSupervisorAction action;
  final ExtensionHostSandboxLauncher launcher;
  final bool available;
  final Map<String, Object?> metadata;

  bool accepts(ExtensionHostSandboxLaunchRequest request) {
    return available && action == request.action;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'launcherId': launcherId,
      'label': label,
      'action': action.wireValue,
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionHostSandboxLaunchResult {
  const ExtensionHostSandboxLaunchResult({
    required this.request,
    required this.status,
    required this.message,
    this.launcher,
    this.processHandleId = '',
    this.pid,
    this.activationTelemetryId = '',
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionHostSandboxLaunchResult.launched({
    required ExtensionHostSandboxLaunchRequest request,
    required ExtensionHostSandboxLauncherRegistration launcher,
    String message = 'Extension host sandbox launch accepted.',
    String processHandleId = '',
    int? pid,
    String activationTelemetryId = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionHostSandboxLaunchResult(
      request: request,
      status: ExtensionHostSandboxLaunchStatus.launched,
      launcher: launcher,
      message: message,
      processHandleId: processHandleId,
      pid: pid,
      activationTelemetryId: activationTelemetryId,
      metadata: metadata,
    );
  }

  factory ExtensionHostSandboxLaunchResult.blocked({
    required ExtensionHostSandboxLaunchRequest request,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionHostSandboxLaunchResult(
      request: request,
      status: ExtensionHostSandboxLaunchStatus.blocked,
      message: message,
      metadata: metadata,
    );
  }

  factory ExtensionHostSandboxLaunchResult.missingLauncher({
    required ExtensionHostSandboxLaunchRequest request,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionHostSandboxLaunchResult(
      request: request,
      status: ExtensionHostSandboxLaunchStatus.missingLauncher,
      message:
          'Extension host sandbox launcher is missing for action '
          '${request.action.wireValue}.',
      metadata: metadata,
    );
  }

  final ExtensionHostSandboxLaunchRequest request;
  final ExtensionHostSandboxLaunchStatus status;
  final String message;
  final ExtensionHostSandboxLauncherRegistration? launcher;
  final String processHandleId;
  final int? pid;
  final String activationTelemetryId;
  final Map<String, Object?> metadata;

  bool get launched => status == ExtensionHostSandboxLaunchStatus.launched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'launched': launched,
      'message': message,
      'extensionId': request.extensionId,
      'action': request.action.wireValue,
      'managerId': request.managerId,
      if (launcher != null) 'launcher': launcher!.toJson(),
      if (processHandleId.isNotEmpty) 'processHandleId': processHandleId,
      if (pid != null) 'pid': pid,
      if (activationTelemetryId.isNotEmpty)
        'activationTelemetryId': activationTelemetryId,
      'request': request.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionHostSandboxLauncherRegistry {
  ExtensionHostSandboxLauncherRegistry({
    Iterable<ExtensionHostSandboxLauncherRegistration> launchers =
        const <ExtensionHostSandboxLauncherRegistration>[],
  }) {
    for (final launcher in launchers) {
      register(launcher);
    }
  }

  final List<ExtensionHostSandboxLauncherRegistration> _launchers =
      <ExtensionHostSandboxLauncherRegistration>[];

  List<ExtensionHostSandboxLauncherRegistration> get launchers {
    return List<ExtensionHostSandboxLauncherRegistration>.unmodifiable(
      _launchers,
    );
  }

  void register(ExtensionHostSandboxLauncherRegistration launcher) {
    _launchers.removeWhere(
      (candidate) => candidate.launcherId == launcher.launcherId,
    );
    _launchers.add(launcher);
  }

  ExtensionHostSandboxLauncherRegistration? resolve(
    ExtensionHostSandboxLaunchRequest request,
  ) {
    for (final launcher in _launchers) {
      if (launcher.accepts(request)) {
        return launcher;
      }
    }
    return null;
  }

  Future<ExtensionHostSandboxLaunchResult> launch(
    ExtensionHostSandboxLaunchRequest request,
  ) async {
    if (!request.plan.ready || !request.dispatchReady) {
      return ExtensionHostSandboxLaunchResult.blocked(
        request: request,
        message:
            'Extension host sandbox launch blocked because runtime dispatch '
            'is not ready.',
        metadata: <String, Object?>{
          'dispatchStatus': request.dispatchResult.status.wireValue,
        },
      );
    }
    final launcher = resolve(request);
    if (launcher == null) {
      return ExtensionHostSandboxLaunchResult.missingLauncher(request: request);
    }
    final result = await launcher.launcher(request);
    return ExtensionHostSandboxLaunchResult(
      request: result.request,
      status: result.status,
      launcher: result.launcher ?? launcher,
      message: result.message,
      processHandleId: result.processHandleId,
      pid: result.pid,
      activationTelemetryId: result.activationTelemetryId,
      metadata: <String, Object?>{...launcher.metadata, ...result.metadata},
    );
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
