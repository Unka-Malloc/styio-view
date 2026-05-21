import '../foundation/foundation.dart';
import '../runtime/runtime.dart';
import 'debug_adapter_launcher.dart';
import 'debug_adapter_session.dart';
import 'debug_launch_contract.dart';

enum DebugLaunchTelemetryStatus {
  planned,
  launched,
  blocked,
  failed,
  closed,
  cancelled,
}

extension DebugLaunchTelemetryStatusX on DebugLaunchTelemetryStatus {
  String get wireValue => switch (this) {
    DebugLaunchTelemetryStatus.planned => 'planned',
    DebugLaunchTelemetryStatus.launched => 'launched',
    DebugLaunchTelemetryStatus.blocked => 'blocked',
    DebugLaunchTelemetryStatus.failed => 'failed',
    DebugLaunchTelemetryStatus.closed => 'closed',
    DebugLaunchTelemetryStatus.cancelled => 'cancelled',
  };
}

class DebugLaunchTelemetryRecord {
  const DebugLaunchTelemetryRecord({
    required this.workspaceId,
    required this.profileId,
    required this.debuggerId,
    required this.status,
    required this.message,
    required this.timestamp,
    this.planStatus = '',
    this.ready = false,
    this.sessionStatus,
    this.metadata = const <String, Object?>{},
  });

  factory DebugLaunchTelemetryRecord.fromExecutionPlan({
    required String workspaceId,
    required DapDebugAdapterExecutionPlan plan,
    required DebugLaunchTelemetryStatus status,
    String message = '',
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return DebugLaunchTelemetryRecord(
      workspaceId: workspaceId,
      profileId: plan.profileId,
      debuggerId: plan.launchConfiguration.debuggerId,
      status: status,
      planStatus: plan.status.wireValue,
      ready: plan.ready,
      message: message.trim().isEmpty ? plan.message : message.trim(),
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
      metadata: <String, Object?>{
        'routeStatus': plan.routePlan.status.wireValue,
        'outputChannelId': plan.outputBinding.outputChannel.id,
        ...metadata,
      },
    );
  }

  factory DebugLaunchTelemetryRecord.fromSessionSnapshot({
    required String workspaceId,
    required DapDebugAdapterExecutionPlan plan,
    required DapSessionSnapshot snapshot,
    required DebugLaunchTelemetryStatus status,
    String message = '',
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return DebugLaunchTelemetryRecord.fromExecutionPlan(
      workspaceId: workspaceId,
      plan: plan,
      status: status,
      message: message.trim().isEmpty
          ? 'DAP session ${snapshot.status.name}: ${snapshot.events.length} event(s).'
          : message,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'sessionStatus': snapshot.status.name,
        'eventCount': snapshot.events.length,
        'pendingRequestCount': snapshot.pendingRequests.length,
        ...metadata,
      },
    ).copyWith(sessionStatus: snapshot.status.name);
  }

  factory DebugLaunchTelemetryRecord.fromJson(Map<String, Object?> json) {
    return DebugLaunchTelemetryRecord(
      workspaceId: json['workspaceId'] as String? ?? '',
      profileId: json['profileId'] as String? ?? '',
      debuggerId: json['debuggerId'] as String? ?? '',
      status:
          _debugLaunchTelemetryStatusFromWire(json['status']) ??
          DebugLaunchTelemetryStatus.planned,
      message: json['message'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      planStatus: json['planStatus'] as String? ?? '',
      ready: json['ready'] as bool? ?? false,
      sessionStatus: json['sessionStatus'] as String?,
      metadata: json['metadata'] is Map
          ? (json['metadata']! as Map).map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
    );
  }

  final String workspaceId;
  final String profileId;
  final String debuggerId;
  final DebugLaunchTelemetryStatus status;
  final String message;
  final DateTime timestamp;
  final String planStatus;
  final bool ready;
  final String? sessionStatus;
  final Map<String, Object?> metadata;

  bool get successful =>
      status == DebugLaunchTelemetryStatus.launched ||
      status == DebugLaunchTelemetryStatus.closed;

  DebugLaunchTelemetryRecord copyWith({String? sessionStatus}) {
    return DebugLaunchTelemetryRecord(
      workspaceId: workspaceId,
      profileId: profileId,
      debuggerId: debuggerId,
      status: status,
      message: message,
      timestamp: timestamp,
      planStatus: planStatus,
      ready: ready,
      sessionStatus: sessionStatus ?? this.sessionStatus,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'profileId': profileId,
      'debuggerId': debuggerId,
      'status': status.wireValue,
      'successful': successful,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      if (planStatus.isNotEmpty) 'planStatus': planStatus,
      'ready': ready,
      if (sessionStatus != null) 'sessionStatus': sessionStatus,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class DebugLaunchTelemetrySnapshot {
  const DebugLaunchTelemetrySnapshot({
    required this.workspaceId,
    this.records = const <DebugLaunchTelemetryRecord>[],
    this.updatedAt,
  });

  factory DebugLaunchTelemetrySnapshot.fromJson(Map<String, Object?> json) {
    final rawRecords = json['records'];
    final records = <DebugLaunchTelemetryRecord>[];
    if (rawRecords is List) {
      for (final rawRecord in rawRecords) {
        if (rawRecord is Map) {
          records.add(
            DebugLaunchTelemetryRecord.fromJson(
              rawRecord.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            ),
          );
        }
      }
    }
    return DebugLaunchTelemetrySnapshot(
      workspaceId: json['workspaceId'] as String? ?? '',
      records: List.unmodifiable(records),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<DebugLaunchTelemetryRecord> records;
  final DateTime? updatedAt;

  int get successfulCount {
    return records.where((record) => record.successful).length;
  }

  int get blockedCount {
    return records
        .where((record) => record.status == DebugLaunchTelemetryStatus.blocked)
        .length;
  }

  DebugLaunchTelemetrySnapshot record(
    DebugLaunchTelemetryRecord record, {
    int maxRecords = 50,
  }) {
    return DebugLaunchTelemetrySnapshot(
      workspaceId: workspaceId,
      records: <DebugLaunchTelemetryRecord>[
        record,
        ...records,
      ].take(maxRecords).toList(growable: false),
      updatedAt: record.timestamp,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'recordCount': records.length,
      'successfulCount': successfulCount,
      'blockedCount': blockedCount,
      'records': records.map((record) => record.toJson()).toList(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class DebugLaunchRuntimeOutputBinding {
  const DebugLaunchRuntimeOutputBinding({required this.telemetry, this.plan});

  final DebugLaunchTelemetrySnapshot telemetry;
  final DapDebugAdapterExecutionPlan? plan;

  List<RuntimeOutputEvent> runtimeOutputEvents({
    DateTime? timestamp,
    String? channelId,
    String label = 'Debug',
  }) {
    final resolvedTimestamp = timestamp ?? DateTime.now().toUtc();
    final baseChannelId = channelId ?? 'debug.${telemetry.workspaceId}';
    return <RuntimeOutputEvent>[
      if (plan != null)
        RuntimeOutputEvent(
          channelId: baseChannelId,
          label: label,
          kind: RuntimeOutputChannelKind.debug,
          message: plan!.message,
          timestamp: resolvedTimestamp,
          metadata: <String, Object?>{
            'debugProfileId': plan!.profileId,
            'debuggerId': plan!.launchConfiguration.debuggerId,
            'planStatus': plan!.status.wireValue,
            'ready': plan!.ready,
            'routeStatus': plan!.routePlan.status.wireValue,
            'outputChannelId': plan!.outputBinding.outputChannel.id,
          },
        ),
      RuntimeOutputEvent(
        channelId: baseChannelId,
        label: label,
        kind: RuntimeOutputChannelKind.runtimeEvents,
        message:
            '${telemetry.records.length} debug telemetry record(s) for ${telemetry.workspaceId}.',
        timestamp: resolvedTimestamp,
        metadata: <String, Object?>{
          'workspaceId': telemetry.workspaceId,
          'recordCount': telemetry.records.length,
          'successfulCount': telemetry.successfulCount,
          'blockedCount': telemetry.blockedCount,
        },
      ),
      for (final record in telemetry.records)
        RuntimeOutputEvent(
          channelId: '$baseChannelId.${record.profileId}',
          label: '$label ${record.profileId}',
          kind: RuntimeOutputChannelKind.debug,
          message:
              '${record.status.wireValue} ${record.profileId}: ${record.message}',
          timestamp: record.timestamp,
          metadata: <String, Object?>{
            'workspaceId': record.workspaceId,
            'debugProfileId': record.profileId,
            'debuggerId': record.debuggerId,
            'status': record.status.wireValue,
            'successful': record.successful,
            'planStatus': record.planStatus,
            'ready': record.ready,
            if (record.sessionStatus != null)
              'sessionStatus': record.sessionStatus,
            ...record.metadata,
          },
        ),
    ];
  }

  RuntimeOutputPanelSnapshot outputPanelSnapshot({
    DateTime? timestamp,
    String? channelId,
    String label = 'Debug',
    RuntimeOutputChannelFilterState filter =
        const RuntimeOutputChannelFilterState(),
  }) {
    return RuntimeOutputPanelSnapshot(
      events: runtimeOutputEvents(
        timestamp: timestamp,
        channelId: channelId,
        label: label,
      ),
      filter: filter,
    );
  }

  Map<String, Object?> toJson() {
    final snapshot = outputPanelSnapshot();
    return <String, Object?>{
      'workspaceId': telemetry.workspaceId,
      'recordCount': telemetry.records.length,
      'hasPlan': plan != null,
      'outputEventCount': snapshot.events.length,
      'outputSnapshot': snapshot.toJson(),
    };
  }
}

enum DebugRuntimeExecutionStatus {
  launched,
  blocked,
  failed,
  wrongRoute,
  cancelled,
}

extension DebugRuntimeExecutionStatusX on DebugRuntimeExecutionStatus {
  String get wireValue => switch (this) {
    DebugRuntimeExecutionStatus.launched => 'launched',
    DebugRuntimeExecutionStatus.blocked => 'blocked',
    DebugRuntimeExecutionStatus.failed => 'failed',
    DebugRuntimeExecutionStatus.wrongRoute => 'wrong-route',
    DebugRuntimeExecutionStatus.cancelled => 'cancelled',
  };
}

class DebugRuntimeExecutionResult {
  const DebugRuntimeExecutionResult({
    required this.plan,
    required this.status,
    required this.telemetry,
    required this.outputEvents,
    required this.dispatchResult,
    this.handle,
    this.terminationExecution,
  });

  final DapDebugAdapterExecutionPlan plan;
  final DebugRuntimeExecutionStatus status;
  final DebugLaunchTelemetrySnapshot telemetry;
  final List<RuntimeOutputEvent> outputEvents;
  final RuntimeExecutionDispatchResult dispatchResult;
  final DapDebugSessionHandle? handle;
  final DebugSessionTerminationExecutionResult? terminationExecution;

  bool get launched => status == DebugRuntimeExecutionStatus.launched;
  bool get failed => status == DebugRuntimeExecutionStatus.failed;
  bool get blocked =>
      status == DebugRuntimeExecutionStatus.blocked ||
      status == DebugRuntimeExecutionStatus.wrongRoute;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'launched': launched,
      'blocked': blocked,
      'failed': failed,
      'plan': plan.toJson(),
      'telemetry': telemetry.toJson(),
      'dispatch': dispatchResult.toJson(),
      'outputEvents': outputEvents
          .map((event) => event.toJson())
          .toList(growable: false),
      if (handle != null) 'session': handle!.snapshot.toJson(),
      if (terminationExecution != null)
        'terminationExecution': terminationExecution!.toJson(),
    };
  }
}

class DebugRuntimeExecutionAdapter {
  DebugRuntimeExecutionAdapter({
    required this.launcher,
    required this.workspaceId,
    RuntimeExecutionManagerRegistry? registry,
    DebugSessionTerminationExecutor? terminationExecutor,
    RuntimeTaskClock? clock,
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers(),
       _terminationExecutor =
           terminationExecutor ?? const DebugSessionTerminationExecutor(),
       _clock = clock ?? DateTime.now().toUtc;

  final DapDebugAdapterLauncher launcher;
  final String workspaceId;
  final RuntimeExecutionManagerRegistry _registry;
  final DebugSessionTerminationExecutor _terminationExecutor;
  final RuntimeTaskClock _clock;

  Future<DebugRuntimeExecutionResult> executePlan({
    required DapDebugAdapterExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
  }) async {
    final dispatchResult = _registry.dispatchToLiveBuffer(
      plan.outputBinding,
      buffer: buffer,
      timestamp: _clock(),
      metadata: <String, Object?>{
        'debugProfileId': plan.profileId,
        'debugRuntimeExecution': 'dap-launcher',
      },
    );
    if (plan.outputBinding.managerId != 'terminal-runtime') {
      return _controlResult(
        plan: plan,
        buffer: buffer,
        dispatchResult: dispatchResult,
        status: DebugRuntimeExecutionStatus.wrongRoute,
        telemetryStatus: DebugLaunchTelemetryStatus.blocked,
        message:
            'Debug execution ignored non-terminal route ${plan.outputBinding.managerId}.',
      );
    }
    if (!plan.ready ||
        dispatchResult.status != RuntimeExecutionDispatchStatus.dispatched) {
      return _controlResult(
        plan: plan,
        buffer: buffer,
        dispatchResult: dispatchResult,
        status: DebugRuntimeExecutionStatus.blocked,
        telemetryStatus: DebugLaunchTelemetryStatus.blocked,
        message: plan.ready
            ? dispatchResult.message
            : 'Debug execution blocked: ${plan.message}',
      );
    }
    try {
      final handle = await launcher.launchExecutionPlan(plan);
      final record = DebugLaunchTelemetryRecord.fromSessionSnapshot(
        workspaceId: workspaceId,
        plan: plan,
        snapshot: handle.snapshot,
        status: DebugLaunchTelemetryStatus.launched,
        message: 'Debug adapter launched through runtime execution route.',
        timestamp: _clock(),
      );
      final telemetry = DebugLaunchTelemetrySnapshot(
        workspaceId: workspaceId,
        records: <DebugLaunchTelemetryRecord>[record],
        updatedAt: record.timestamp,
      );
      final outputEvents = _emitTelemetry(
        plan: plan,
        telemetry: telemetry,
        buffer: buffer,
      );
      return DebugRuntimeExecutionResult(
        plan: plan,
        status: DebugRuntimeExecutionStatus.launched,
        telemetry: telemetry,
        outputEvents: outputEvents,
        dispatchResult: dispatchResult,
        handle: handle,
      );
    } catch (error) {
      return _controlResult(
        plan: plan,
        buffer: buffer,
        dispatchResult: dispatchResult,
        status: DebugRuntimeExecutionStatus.failed,
        telemetryStatus: DebugLaunchTelemetryStatus.failed,
        message: 'Debug execution failed: $error',
      );
    }
  }

  Future<DebugRuntimeExecutionResult> cancelExecution({
    required DebugRuntimeExecutionResult execution,
    required RuntimeOutputLiveBuffer buffer,
    String reason = 'Debug execution cancelled.',
  }) async {
    final handle = execution.handle;
    if (handle == null) {
      return _controlResult(
        plan: execution.plan,
        buffer: buffer,
        dispatchResult: execution.dispatchResult,
        status: DebugRuntimeExecutionStatus.blocked,
        telemetryStatus: DebugLaunchTelemetryStatus.blocked,
        message: 'Debug execution cancellation skipped: no active session.',
      );
    }
    final terminationExecution = await _terminationExecutor.execute(
      handle: handle,
      plan: handle.terminationPlan(),
      reason: reason,
    );
    if (!terminationExecution.executed) {
      return _controlResult(
        plan: execution.plan,
        buffer: buffer,
        dispatchResult: execution.dispatchResult,
        status: DebugRuntimeExecutionStatus.blocked,
        telemetryStatus: DebugLaunchTelemetryStatus.blocked,
        message: terminationExecution.message,
      );
    }
    final record = DebugLaunchTelemetryRecord.fromSessionSnapshot(
      workspaceId: workspaceId,
      plan: execution.plan,
      snapshot: handle.snapshot,
      status: DebugLaunchTelemetryStatus.cancelled,
      message: reason,
      timestamp: _clock(),
      metadata: <String, Object?>{
        'debugRuntimeExecutionStatus':
            DebugRuntimeExecutionStatus.cancelled.wireValue,
        'cancelledBy': 'DebugRuntimeExecutionAdapter',
        'terminationExecution': terminationExecution.toJson(),
      },
    );
    final telemetry = DebugLaunchTelemetrySnapshot(
      workspaceId: workspaceId,
      records: <DebugLaunchTelemetryRecord>[record],
      updatedAt: record.timestamp,
    );
    final outputEvents = _emitTelemetry(
      plan: execution.plan,
      telemetry: telemetry,
      buffer: buffer,
    );
    return DebugRuntimeExecutionResult(
      plan: execution.plan,
      status: DebugRuntimeExecutionStatus.cancelled,
      telemetry: telemetry,
      outputEvents: outputEvents,
      dispatchResult: execution.dispatchResult,
      handle: handle,
      terminationExecution: terminationExecution,
    );
  }

  DebugRuntimeExecutionResult _controlResult({
    required DapDebugAdapterExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
    required RuntimeExecutionDispatchResult dispatchResult,
    required DebugRuntimeExecutionStatus status,
    required DebugLaunchTelemetryStatus telemetryStatus,
    required String message,
  }) {
    final record = DebugLaunchTelemetryRecord.fromExecutionPlan(
      workspaceId: workspaceId,
      plan: plan,
      status: telemetryStatus,
      message: message,
      timestamp: _clock(),
      metadata: <String, Object?>{
        'debugRuntimeExecutionStatus': status.wireValue,
        'dispatchStatus': dispatchResult.status.wireValue,
      },
    );
    final telemetry = DebugLaunchTelemetrySnapshot(
      workspaceId: workspaceId,
      records: <DebugLaunchTelemetryRecord>[record],
      updatedAt: record.timestamp,
    );
    final outputEvents = _emitTelemetry(
      plan: plan,
      telemetry: telemetry,
      buffer: buffer,
    );
    return DebugRuntimeExecutionResult(
      plan: plan,
      status: status,
      telemetry: telemetry,
      outputEvents: outputEvents,
      dispatchResult: dispatchResult,
    );
  }

  List<RuntimeOutputEvent> _emitTelemetry({
    required DapDebugAdapterExecutionPlan plan,
    required DebugLaunchTelemetrySnapshot telemetry,
    required RuntimeOutputLiveBuffer buffer,
  }) {
    final outputEvents =
        DebugLaunchRuntimeOutputBinding(
          telemetry: telemetry,
          plan: plan,
        ).runtimeOutputEvents(
          timestamp: _clock(),
          channelId: plan.outputBinding.outputChannel.id,
          label: 'Debug',
        );
    for (final event in outputEvents) {
      buffer.addEvent(event, now: event.timestamp);
    }
    return List<RuntimeOutputEvent>.unmodifiable(outputEvents);
  }
}

class DebugLaunchTelemetryStore {
  DebugLaunchTelemetryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'debug.launch.telemetry',
             layer: 'debugger',
             stateFamily: 'debug-launch-telemetry',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const DebugLaunchTelemetryStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'debug.launch.telemetry';
  static const String _key = 'debug-launch-telemetry';

  final FoundationDataStoreOwner _owner;

  Future<DebugLaunchTelemetrySnapshot> readSnapshot({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return DebugLaunchTelemetrySnapshot(workspaceId: workspaceId);
    }
    final snapshot = DebugLaunchTelemetrySnapshot.fromJson(value);
    return snapshot.workspaceId.isEmpty
        ? DebugLaunchTelemetrySnapshot(
            workspaceId: workspaceId,
            records: snapshot.records,
            updatedAt: snapshot.updatedAt,
          )
        : snapshot;
  }

  Future<DebugLaunchTelemetrySnapshot> record({
    required DebugLaunchTelemetryRecord record,
    int maxRecords = 50,
  }) async {
    final next = (await readSnapshot(
      workspaceId: record.workspaceId,
    )).record(record, maxRecords: maxRecords);
    await saveSnapshot(snapshot: next);
    return next;
  }

  Future<DebugLaunchTelemetrySnapshot> saveSnapshot({
    required DebugLaunchTelemetrySnapshot snapshot,
  }) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: snapshot.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: snapshot.workspaceId,
    );
    return snapshot;
  }

  Future<bool> clearSnapshot({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

DebugLaunchTelemetryStatus? _debugLaunchTelemetryStatusFromWire(Object? value) {
  return switch (value) {
    'planned' => DebugLaunchTelemetryStatus.planned,
    'launched' => DebugLaunchTelemetryStatus.launched,
    'blocked' => DebugLaunchTelemetryStatus.blocked,
    'failed' => DebugLaunchTelemetryStatus.failed,
    'closed' => DebugLaunchTelemetryStatus.closed,
    'cancelled' => DebugLaunchTelemetryStatus.cancelled,
    _ => null,
  };
}
