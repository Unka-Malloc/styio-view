import 'dart:async';

import '../foundation/foundation.dart';
import '../module_host/module_host.dart';
import 'runtime_execution_plan.dart';
import 'runtime_output_channels.dart';
import 'runtime_task_lifecycle.dart';

enum ExtensionRuntimeTaskContributionStatus {
  ready,
  invalidRoute,
  missingCommand,
}

class ExtensionRuntimeTaskContribution {
  const ExtensionRuntimeTaskContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.definition,
  });

  factory ExtensionRuntimeTaskContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.runtimeTaskRegistry) {
      return ExtensionRuntimeTaskContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionRuntimeTaskContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready runtime task route.',
      );
    }
    final command = _metadataString(route.contribution.metadata, 'command');
    if (command == null) {
      return ExtensionRuntimeTaskContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionRuntimeTaskContributionStatus.missingCommand,
        message:
            'Runtime task contribution ${route.contribution.id} does not declare metadata.command.',
      );
    }
    final definition = RuntimeTaskDefinition(
      id:
          _metadataString(route.contribution.metadata, 'taskId') ??
          route.contribution.id,
      label:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          route.contribution.id,
      kind: _runtimeTaskKindFromMetadata(route.contribution.metadata),
      command: command,
      arguments: _metadataStringList(route.contribution.metadata, 'arguments'),
      workingDirectory: _metadataString(
        route.contribution.metadata,
        'workingDirectory',
      ),
      environment: _metadataStringMap(
        route.contribution.metadata,
        'environment',
      ),
      dependsOn: _metadataStringList(route.contribution.metadata, 'dependsOn'),
      group: _metadataString(route.contribution.metadata, 'group'),
      terminalProfileId: _metadataString(
        route.contribution.metadata,
        'terminalProfileId',
      ),
      background: route.contribution.metadata['background'] as bool? ?? false,
      metadata: <String, Object?>{
        ...route.contribution.metadata,
        'extensionId': route.extensionId,
        'contributionId': route.contribution.id,
        'source': 'extension-runtime-task-contribution',
      },
    );
    return ExtensionRuntimeTaskContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionRuntimeTaskContributionStatus.ready,
      message: 'Runtime task contribution ${route.contribution.id} is ready.',
      definition: definition,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionRuntimeTaskContributionStatus status;
  final String message;
  final RuntimeTaskDefinition? definition;

  bool get ready => status == ExtensionRuntimeTaskContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (definition != null) 'definition': definition!.toJson(),
    };
  }
}

class ExtensionRuntimeTaskContributionCatalog {
  const ExtensionRuntimeTaskContributionCatalog({required this.contributions});

  factory ExtensionRuntimeTaskContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionRuntimeTaskContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.runtimeTaskRegistry)
          .map(ExtensionRuntimeTaskContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionRuntimeTaskContribution> contributions;

  List<RuntimeTaskDefinition> get readyDefinitions {
    return contributions
        .map((contribution) => contribution.definition)
        .whereType<RuntimeTaskDefinition>()
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-runtime-task-contributions.v1',
      'contributionCount': contributions.length,
      'readyDefinitionCount': readyDefinitions.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionRuntimeTaskExecutionPlan {
  const ExtensionRuntimeTaskExecutionPlan({
    required this.contribution,
    required this.executionPlan,
    required this.handoff,
    required this.binding,
  });

  factory ExtensionRuntimeTaskExecutionPlan.fromContribution(
    ExtensionRuntimeTaskContribution contribution, {
    String outputChannelId = '',
  }) {
    final definition = contribution.definition;
    final executionPlan = definition == null
        ? RuntimeExecutionPlan(
            definition: RuntimeTaskDefinition(
              id: contribution.contributionId,
              label: contribution.contributionId,
              kind: RuntimeTaskKind.run,
              command: '',
              metadata: <String, Object?>{
                'extensionId': contribution.extensionId,
                'contributionId': contribution.contributionId,
              },
            ),
            status: RuntimeExecutionPlanStatus.blockedUnrunnable,
            message: contribution.message,
          )
        : const RuntimeExecutionPlanner().plan(definition: definition);
    final target = definition == null
        ? RuntimeExecutionHandoffTarget.terminalRuntime
        : _runtimeTaskHandoffTargetFromMetadata(definition);
    final channelId = outputChannelId.trim().isEmpty
        ? 'extension.task.${contribution.extensionId}.${contribution.contributionId}'
        : outputChannelId.trim();
    final handoff = executionPlan.createHandoff(
      target: target,
      outputChannelId: channelId,
      metadata: <String, Object?>{
        'extensionId': contribution.extensionId,
        'contributionId': contribution.contributionId,
        'extensionRuntimeTask': true,
      },
    );
    final binding = handoff.bind(
      outputKind: _runtimeOutputKindForTarget(target),
      metadata: <String, Object?>{
        'extensionId': contribution.extensionId,
        'contributionId': contribution.contributionId,
        'extensionRuntimeTask': true,
      },
    );
    return ExtensionRuntimeTaskExecutionPlan(
      contribution: contribution,
      executionPlan: executionPlan,
      handoff: handoff,
      binding: binding,
    );
  }

  final ExtensionRuntimeTaskContribution contribution;
  final RuntimeExecutionPlan executionPlan;
  final RuntimeExecutionHandoff handoff;
  final RuntimeExecutionHandoffBinding binding;

  bool get ready => contribution.ready && executionPlan.ready && binding.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'contribution': contribution.toJson(),
      'executionPlan': executionPlan.toJson(),
      'handoff': handoff.toJson(),
      'binding': binding.toJson(),
    };
  }
}

enum ExtensionRuntimeTaskTelemetryKind { dispatch, retry, cancellation }

class ExtensionRuntimeTaskTelemetryRecord {
  const ExtensionRuntimeTaskTelemetryRecord({
    required this.kind,
    required this.extensionId,
    required this.contributionId,
    required this.taskId,
    required this.timestamp,
    this.dispatchStatus = '',
    this.message = '',
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionRuntimeTaskTelemetryRecord.fromJson(
    Map<String, Object?> json,
  ) {
    return ExtensionRuntimeTaskTelemetryRecord(
      kind: _extensionRuntimeTaskTelemetryKindFromWire(json['kind']),
      extensionId: json['extensionId'] as String? ?? '',
      contributionId: json['contributionId'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      dispatchStatus: json['dispatchStatus'] as String? ?? '',
      message: json['message'] as String? ?? '',
      metadata: json['metadata'] is Map
          ? (json['metadata']! as Map).map(
              (key, value) => MapEntry<String, Object?>(
                key.toString(),
                value,
              ),
            )
          : const <String, Object?>{},
    );
  }

  factory ExtensionRuntimeTaskTelemetryRecord.dispatch({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required RuntimeExecutionDispatchResult result,
    required DateTime timestamp,
  }) {
    return ExtensionRuntimeTaskTelemetryRecord(
      kind: ExtensionRuntimeTaskTelemetryKind.dispatch,
      extensionId: plan.contribution.extensionId,
      contributionId: plan.contribution.contributionId,
      taskId: plan.executionPlan.definition.id,
      timestamp: timestamp,
      dispatchStatus: result.status.name,
      message: result.message,
      metadata: <String, Object?>{'dispatch': result.toJson()},
    );
  }

  factory ExtensionRuntimeTaskTelemetryRecord.retry({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionRuntimeTaskTelemetryRecord(
      kind: ExtensionRuntimeTaskTelemetryKind.retry,
      extensionId: plan.contribution.extensionId,
      contributionId: plan.contribution.contributionId,
      taskId: plan.executionPlan.definition.id,
      timestamp: timestamp,
      message: reason,
      metadata: metadata,
    );
  }

  factory ExtensionRuntimeTaskTelemetryRecord.cancellation({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionRuntimeTaskTelemetryRecord(
      kind: ExtensionRuntimeTaskTelemetryKind.cancellation,
      extensionId: plan.contribution.extensionId,
      contributionId: plan.contribution.contributionId,
      taskId: plan.executionPlan.definition.id,
      timestamp: timestamp,
      message: reason,
      metadata: metadata,
    );
  }

  final ExtensionRuntimeTaskTelemetryKind kind;
  final String extensionId;
  final String contributionId;
  final String taskId;
  final DateTime timestamp;
  final String dispatchStatus;
  final String message;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'extensionId': extensionId,
      'contributionId': contributionId,
      'taskId': taskId,
      'timestamp': timestamp.toIso8601String(),
      if (dispatchStatus.isNotEmpty) 'dispatchStatus': dispatchStatus,
      if (message.isNotEmpty) 'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

abstract class ExtensionRuntimeTaskTelemetrySink {
  const ExtensionRuntimeTaskTelemetrySink();

  void record(ExtensionRuntimeTaskTelemetryRecord record);
}

class ExtensionRuntimeTaskTelemetrySnapshot {
  const ExtensionRuntimeTaskTelemetrySnapshot({
    required this.workspaceId,
    this.records = const <ExtensionRuntimeTaskTelemetryRecord>[],
    this.updatedAt,
  });

  factory ExtensionRuntimeTaskTelemetrySnapshot.fromJson(
    Map<String, Object?> json,
  ) {
    return ExtensionRuntimeTaskTelemetrySnapshot(
      workspaceId: json['workspaceId'] as String? ?? '',
      records: _extensionRuntimeTaskTelemetryRecords(json['records']),
      updatedAt: DateTime.tryParse(
        json['updatedAt'] as String? ?? '',
      )?.toUtc(),
    );
  }

  final String workspaceId;
  final List<ExtensionRuntimeTaskTelemetryRecord> records;
  final DateTime? updatedAt;

  ExtensionRuntimeTaskTelemetrySnapshot append(
    ExtensionRuntimeTaskTelemetryRecord record, {
    int maxRecords = 50,
    DateTime? updatedAt,
  }) {
    return ExtensionRuntimeTaskTelemetrySnapshot(
      workspaceId: workspaceId,
      records: <ExtensionRuntimeTaskTelemetryRecord>[
        record,
        ...records,
      ].take(maxRecords).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  ExtensionRuntimeTaskTelemetrySnapshot copyWith({
    String? workspaceId,
    List<ExtensionRuntimeTaskTelemetryRecord>? records,
    DateTime? updatedAt,
  }) {
    return ExtensionRuntimeTaskTelemetrySnapshot(
      workspaceId: workspaceId ?? this.workspaceId,
      records: records ?? this.records,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'recordCount': records.length,
      'records': records.map((record) => record.toJson()).toList(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class ExtensionRuntimeTaskInMemoryTelemetrySink
    extends ExtensionRuntimeTaskTelemetrySink {
  ExtensionRuntimeTaskInMemoryTelemetrySink();

  final List<ExtensionRuntimeTaskTelemetryRecord> _records =
      <ExtensionRuntimeTaskTelemetryRecord>[];

  List<ExtensionRuntimeTaskTelemetryRecord> get records =>
      List<ExtensionRuntimeTaskTelemetryRecord>.unmodifiable(_records);

  @override
  void record(ExtensionRuntimeTaskTelemetryRecord record) {
    _records.add(record);
  }
}

class ExtensionRuntimeTaskDataStoreTelemetrySink
    extends ExtensionRuntimeTaskTelemetrySink {
  ExtensionRuntimeTaskDataStoreTelemetrySink.fromDataStore({
    required FoundationDataStore dataStore,
    required this.workspaceId,
    this.maxRecords = 50,
  }) : _owner = FoundationDataStoreOwner(
         descriptor: const FoundationDataStoreOwnerDescriptor(
           ownerId: 'runtime.extension-task-telemetry',
           layer: 'runtime',
           stateFamily: 'extension-task-telemetry',
           allowedNamespaces: <String>{_namespaceName},
         ),
         dataStore: dataStore,
       );

  ExtensionRuntimeTaskDataStoreTelemetrySink({
    required FoundationDataStoreOwner owner,
    required this.workspaceId,
    this.maxRecords = 50,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'runtime.extension-task-telemetry';
  static const String _key = 'records';

  final FoundationDataStoreOwner _owner;
  final String workspaceId;
  final int maxRecords;
  Future<void> _appendQueue = Future<void>.value();

  @override
  void record(ExtensionRuntimeTaskTelemetryRecord record) {
    _appendQueue = _appendQueue.then((_) => _append(record));
    unawaited(_appendQueue);
  }

  Future<void> flush() => _appendQueue;

  Future<ExtensionRuntimeTaskTelemetrySnapshot> readTelemetry() async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return ExtensionRuntimeTaskTelemetrySnapshot(workspaceId: workspaceId);
    }
    final snapshot = ExtensionRuntimeTaskTelemetrySnapshot.fromJson(value);
    return snapshot.workspaceId.isEmpty
        ? snapshot.copyWith(workspaceId: workspaceId)
        : snapshot;
  }

  Future<void> saveTelemetry(
    ExtensionRuntimeTaskTelemetrySnapshot snapshot,
  ) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: snapshot.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<void> _append(ExtensionRuntimeTaskTelemetryRecord record) async {
    final current = await readTelemetry();
    await saveTelemetry(current.append(record, maxRecords: maxRecords));
  }
}

class ExtensionRuntimeTaskExecutionBridge {
  ExtensionRuntimeTaskExecutionBridge({
    RuntimeExecutionManagerRegistry? registry,
    ExtensionRuntimeTaskTelemetrySink? telemetrySink,
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers(),
       _telemetrySink = telemetrySink;

  final RuntimeExecutionManagerRegistry _registry;
  final ExtensionRuntimeTaskTelemetrySink? _telemetrySink;

  RuntimeExecutionDispatchResult dispatchToLiveBuffer({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final result = _registry.dispatchToLiveBuffer(
      plan.binding,
      buffer: buffer,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'extensionId': plan.contribution.extensionId,
        'contributionId': plan.contribution.contributionId,
        'extensionRuntimeTask': true,
        ...metadata,
      },
    );
    _telemetrySink?.record(
      ExtensionRuntimeTaskTelemetryRecord.dispatch(
        plan: plan,
        result: result,
        timestamp: timestamp,
      ),
    );
    return result;
  }

  ExtensionRuntimeTaskTelemetryRecord recordRetry({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final record = ExtensionRuntimeTaskTelemetryRecord.retry(
      plan: plan,
      timestamp: timestamp,
      reason: reason,
      metadata: metadata,
    );
    _telemetrySink?.record(record);
    return record;
  }

  ExtensionRuntimeTaskTelemetryRecord recordCancellation({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final record = ExtensionRuntimeTaskTelemetryRecord.cancellation(
      plan: plan,
      timestamp: timestamp,
      reason: reason,
      metadata: metadata,
    );
    _telemetrySink?.record(record);
    return record;
  }
}

ExtensionRuntimeTaskTelemetryKind _extensionRuntimeTaskTelemetryKindFromWire(
  Object? value,
) {
  return switch (value) {
    'retry' => ExtensionRuntimeTaskTelemetryKind.retry,
    'cancellation' => ExtensionRuntimeTaskTelemetryKind.cancellation,
    _ => ExtensionRuntimeTaskTelemetryKind.dispatch,
  };
}

List<ExtensionRuntimeTaskTelemetryRecord>
_extensionRuntimeTaskTelemetryRecords(Object? value) {
  if (value is! List) {
    return const <ExtensionRuntimeTaskTelemetryRecord>[];
  }
  return value
      .whereType<Map>()
      .map(
        (record) => ExtensionRuntimeTaskTelemetryRecord.fromJson(
          record.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

RuntimeTaskKind _runtimeTaskKindFromMetadata(Map<String, Object?> metadata) {
  final value = _metadataString(metadata, 'kind');
  return switch (value) {
    'shell' => RuntimeTaskKind.shell,
    'build' => RuntimeTaskKind.build,
    'test' => RuntimeTaskKind.test,
    'debug' => RuntimeTaskKind.debug,
    'agent' => RuntimeTaskKind.agent,
    'toolchain' => RuntimeTaskKind.toolchain,
    _ => RuntimeTaskKind.run,
  };
}

RuntimeExecutionHandoffTarget _runtimeTaskHandoffTargetFromMetadata(
  RuntimeTaskDefinition definition,
) {
  final explicitTarget = _metadataString(definition.metadata, 'handoffTarget');
  return switch (explicitTarget) {
    'shell-manager' => RuntimeExecutionHandoffTarget.shellManager,
    'terminal-runtime' => RuntimeExecutionHandoffTarget.terminalRuntime,
    'toolchain-manager' => RuntimeExecutionHandoffTarget.toolchainManager,
    'hosted-executor' => RuntimeExecutionHandoffTarget.hostedExecutor,
    _ => switch (definition.kind) {
      RuntimeTaskKind.shell => RuntimeExecutionHandoffTarget.shellManager,
      RuntimeTaskKind.build ||
      RuntimeTaskKind.test ||
      RuntimeTaskKind.debug ||
      RuntimeTaskKind.toolchain =>
        RuntimeExecutionHandoffTarget.toolchainManager,
      RuntimeTaskKind.run ||
      RuntimeTaskKind.agent => RuntimeExecutionHandoffTarget.terminalRuntime,
    },
  };
}

RuntimeOutputChannelKind _runtimeOutputKindForTarget(
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

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

List<String> _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .map((item) => item.trim())
      .toList(growable: false);
}

Map<String, String> _metadataStringMap(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! Map) {
    return const <String, String>{};
  }
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}
