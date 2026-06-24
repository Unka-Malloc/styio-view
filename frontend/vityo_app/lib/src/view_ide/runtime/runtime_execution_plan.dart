import 'runtime_output_channels.dart';
import 'runtime_task_lifecycle.dart';

enum RuntimeExecutionPlanStatus {
  ready,
  blockedUnrunnable,
  blockedMissingDependency,
}

enum RuntimeExecutionHandoffStatus { ready, blocked }

enum RuntimeExecutionHandoffBindingStatus { ready, blocked }

enum RuntimeExecutionDispatchStatus { dispatched, blocked, missingManager }

enum RuntimeExecutionHandoffTarget {
  shellManager,
  terminalRuntime,
  toolchainManager,
  hostedExecutor,
}

extension RuntimeExecutionPlanStatusX on RuntimeExecutionPlanStatus {
  String get wireValue => switch (this) {
    RuntimeExecutionPlanStatus.ready => 'ready',
    RuntimeExecutionPlanStatus.blockedUnrunnable => 'blocked-unrunnable',
    RuntimeExecutionPlanStatus.blockedMissingDependency =>
      'blocked-missing-dependency',
  };
}

extension RuntimeExecutionHandoffStatusX on RuntimeExecutionHandoffStatus {
  String get wireValue => switch (this) {
    RuntimeExecutionHandoffStatus.ready => 'ready',
    RuntimeExecutionHandoffStatus.blocked => 'blocked',
  };
}

extension RuntimeExecutionHandoffTargetX on RuntimeExecutionHandoffTarget {
  String get wireValue => switch (this) {
    RuntimeExecutionHandoffTarget.shellManager => 'shell-manager',
    RuntimeExecutionHandoffTarget.terminalRuntime => 'terminal-runtime',
    RuntimeExecutionHandoffTarget.toolchainManager => 'toolchain-manager',
    RuntimeExecutionHandoffTarget.hostedExecutor => 'hosted-executor',
  };
}

extension RuntimeExecutionHandoffBindingStatusX
    on RuntimeExecutionHandoffBindingStatus {
  String get wireValue => switch (this) {
    RuntimeExecutionHandoffBindingStatus.ready => 'ready',
    RuntimeExecutionHandoffBindingStatus.blocked => 'blocked',
  };
}

extension RuntimeExecutionDispatchStatusX on RuntimeExecutionDispatchStatus {
  String get wireValue => switch (this) {
    RuntimeExecutionDispatchStatus.dispatched => 'dispatched',
    RuntimeExecutionDispatchStatus.blocked => 'blocked',
    RuntimeExecutionDispatchStatus.missingManager => 'missing-manager',
  };
}

class RuntimeProcessHandleIdentity {
  const RuntimeProcessHandleIdentity({
    required this.managerId,
    this.processHandleId = '',
    this.pid,
    this.source = '',
    this.metadata = const <String, Object?>{},
  });

  static RuntimeProcessHandleIdentity? tryFromMetadata(
    Map<String, Object?> metadata, {
    required String managerId,
  }) {
    final processHandleId = _stringMetadata(metadata, const <String>[
      'processHandleId',
      'process_handle_id',
      'handleId',
    ]);
    final pid = _intMetadata(metadata, const <String>['pid', 'processId']);
    if (processHandleId.isEmpty && pid == null) {
      return null;
    }
    return RuntimeProcessHandleIdentity(
      managerId: managerId,
      processHandleId: processHandleId,
      pid: pid,
      source: _stringMetadata(metadata, const <String>[
        'processHandleSource',
        'processSource',
        'source',
      ]),
      metadata: <String, Object?>{
        if (metadata.containsKey('processGroupId'))
          'processGroupId': metadata['processGroupId'],
        if (metadata.containsKey('runtimeSessionId'))
          'runtimeSessionId': metadata['runtimeSessionId'],
      },
    );
  }

  final String managerId;
  final String processHandleId;
  final int? pid;
  final String source;
  final Map<String, Object?> metadata;

  bool get available => processHandleId.isNotEmpty || pid != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'managerId': managerId,
      if (processHandleId.isNotEmpty) 'processHandleId': processHandleId,
      if (pid != null) 'pid': pid,
      if (source.isNotEmpty) 'source': source,
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeExecutionPlan {
  const RuntimeExecutionPlan({
    required this.definition,
    required this.status,
    required this.message,
    this.executionOrder = const <String>[],
    this.missingDependencies = const <String>[],
    this.metadata = const <String, Object?>{},
    this.todo = '',
    this.schemaVersion = 1,
    this.extensions = const {},
  });

  factory RuntimeExecutionPlan.fromJson(Map<String, Object?> json) {
    final definition = json['definition'];
    return RuntimeExecutionPlan(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
      definition: definition is Map<String, Object?>
          ? RuntimeTaskDefinition.fromJson(definition)
          : definition is Map
          ? RuntimeTaskDefinition.fromJson(
              definition.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const RuntimeTaskDefinition(
              id: '',
              label: '',
              kind: RuntimeTaskKind.shell,
              command: '',
            ),
      status: _planStatusFromWire(json['status']),
      message: json['message'] as String? ?? '',
      executionOrder: _jsonStringList(json['executionOrder']),
      missingDependencies: _jsonStringList(json['missingDependencies']),
      metadata: _jsonObjectMap(json['metadata']),
      todo: json['todo'] as String? ?? '',
    );
  }

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'definition',
    'status',
    'message',
    'ready',
    'executionOrder',
    'missingDependencies',
    'metadata',
    'todo',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    final result = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) {
        result[entry.key] = entry.value;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  final RuntimeTaskDefinition definition;
  final RuntimeExecutionPlanStatus status;
  final String message;
  final List<String> executionOrder;
  final List<String> missingDependencies;
  final Map<String, Object?> metadata;
  final String todo;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  bool get ready => status == RuntimeExecutionPlanStatus.ready;

  RuntimeExecutionHandoff createHandoff({
    RuntimeExecutionHandoffTarget target =
        RuntimeExecutionHandoffTarget.terminalRuntime,
    String? outputChannelId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionHandoff.fromPlan(
      plan: this,
      target: target,
      outputChannelId: outputChannelId,
      metadata: metadata,
    );
  }

  RuntimeTaskSnapshot applyTo(RuntimeTaskLifecycleController controller) {
    controller.register(definition);
    if (ready) {
      return controller.queue(definition.id, message: message);
    }
    return controller.block(
      definition.id,
      message: message,
      metadata: <String, Object?>{
        'planStatus': status.wireValue,
        if (missingDependencies.isNotEmpty)
          'missingDependencies': missingDependencies,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'definition': definition.toJson(),
      'status': status.wireValue,
      'message': message,
      'ready': ready,
      'executionOrder': executionOrder,
      'missingDependencies': missingDependencies,
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (todo.isNotEmpty) 'todo': todo,
      ...extensions,
    };
  }
}

class RuntimeExecutionHandoff {
  const RuntimeExecutionHandoff({
    required this.plan,
    required this.status,
    required this.target,
    required this.taskId,
    required this.command,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.outputChannelId,
    this.metadata = const <String, Object?>{},
    this.schemaVersion = 1,
    this.extensions = const {},
  });

  factory RuntimeExecutionHandoff.fromPlan({
    required RuntimeExecutionPlan plan,
    RuntimeExecutionHandoffTarget target =
        RuntimeExecutionHandoffTarget.terminalRuntime,
    String? outputChannelId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionHandoff(
      plan: plan,
      status: plan.ready
          ? RuntimeExecutionHandoffStatus.ready
          : RuntimeExecutionHandoffStatus.blocked,
      target: target,
      taskId: plan.definition.id,
      command: plan.definition.command,
      arguments: plan.definition.arguments,
      workingDirectory: plan.definition.workingDirectory,
      environment: plan.definition.environment,
      outputChannelId: outputChannelId ?? 'runtime.${plan.definition.id}',
      metadata: <String, Object?>{
        'planStatus': plan.status.wireValue,
        'executionOrder': plan.executionOrder,
        if (plan.missingDependencies.isNotEmpty)
          'missingDependencies': plan.missingDependencies,
        ...metadata,
      },
    );
  }

  factory RuntimeExecutionHandoff.fromJson(Map<String, Object?> json) {
    final plan = json['plan'];
    return RuntimeExecutionHandoff(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
      plan: plan is Map<String, Object?>
          ? RuntimeExecutionPlan.fromJson(plan)
          : plan is Map
          ? RuntimeExecutionPlan.fromJson(
              plan.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : RuntimeExecutionPlan(
              definition: RuntimeTaskDefinition(
                id: json['taskId'] as String? ?? '',
                label: json['taskId'] as String? ?? '',
                kind: RuntimeTaskKind.shell,
                command: json['command'] as String? ?? '',
              ),
              status: RuntimeExecutionPlanStatus.blockedUnrunnable,
              message: 'Restored handoff has no execution plan.',
            ),
      status: _handoffStatusFromWire(json['status']),
      target: _handoffTargetFromWire(json['target']),
      taskId: json['taskId'] as String? ?? '',
      command: json['command'] as String? ?? '',
      arguments: _jsonStringList(json['arguments']),
      workingDirectory: json['workingDirectory'] as String?,
      environment: _jsonStringMap(json['environment']),
      outputChannelId: json['outputChannelId'] as String?,
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'plan',
    'status',
    'ready',
    'target',
    'taskId',
    'command',
    'arguments',
    'workingDirectory',
    'environment',
    'outputChannelId',
    'metadata',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    final result = <String, Object?>{};
    for (final entry in json.entries) {
      if (!_knownKeys.contains(entry.key)) {
        result[entry.key] = entry.value;
      }
    }
    return Map<String, Object?>.unmodifiable(result);
  }

  final RuntimeExecutionPlan plan;
  final RuntimeExecutionHandoffStatus status;
  final RuntimeExecutionHandoffTarget target;
  final String taskId;
  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final String? outputChannelId;
  final Map<String, Object?> metadata;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  bool get ready => status == RuntimeExecutionHandoffStatus.ready;

  RuntimeExecutionHandoffBinding bind({
    RuntimeOutputChannelKind? outputKind,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionHandoffBinding.fromHandoff(
      this,
      outputKind: outputKind,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'plan': plan.toJson(),
      'status': status.wireValue,
      'ready': ready,
      'target': target.wireValue,
      'taskId': taskId,
      'command': command,
      'arguments': arguments,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      'environment': environment,
      if (outputChannelId != null) 'outputChannelId': outputChannelId,
      if (metadata.isNotEmpty) 'metadata': metadata,
      ...extensions,
    };
  }
}

class RuntimeExecutionHandoffBinding {
  const RuntimeExecutionHandoffBinding({
    required this.handoff,
    required this.status,
    required this.managerId,
    required this.routeKind,
    required this.outputChannel,
    this.metadata = const <String, Object?>{},
  });

  factory RuntimeExecutionHandoffBinding.fromHandoff(
    RuntimeExecutionHandoff handoff, {
    RuntimeOutputChannelKind? outputKind,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final effectiveOutputKind =
        outputKind ?? _defaultOutputKindForHandoffTarget(handoff.target);
    final normalizedMetadata = <String, Object?>{
      'handoffTarget': handoff.target.wireValue,
      'handoffStatus': handoff.status.wireValue,
      'taskId': handoff.taskId,
      'command': handoff.command,
      'managerId': _managerIdForHandoffTarget(handoff.target),
      'routeKind': _routeKindForHandoffTarget(handoff.target),
      if (handoff.target == RuntimeExecutionHandoffTarget.toolchainManager)
        'toolchainManagerRoute': true,
      if (handoff.target == RuntimeExecutionHandoffTarget.hostedExecutor)
        'hostedExecutorRoute': true,
      ...handoff.metadata,
      ...metadata,
    };
    final outputChannelId =
        handoff.outputChannelId ?? 'runtime.${handoff.taskId}';
    return RuntimeExecutionHandoffBinding(
      handoff: handoff,
      status: handoff.ready
          ? RuntimeExecutionHandoffBindingStatus.ready
          : RuntimeExecutionHandoffBindingStatus.blocked,
      managerId: _managerIdForHandoffTarget(handoff.target),
      routeKind: _routeKindForHandoffTarget(handoff.target),
      outputChannel: RuntimeOutputChannelSummary(
        id: outputChannelId,
        label: '${handoff.plan.definition.label} Output',
        kind: effectiveOutputKind,
        eventCount: 0,
        latestMessage: 'No output has been attached yet.',
      ),
      metadata: Map<String, Object?>.unmodifiable(normalizedMetadata),
    );
  }

  final RuntimeExecutionHandoff handoff;
  final RuntimeExecutionHandoffBindingStatus status;
  final String managerId;
  final String routeKind;
  final RuntimeOutputChannelSummary outputChannel;
  final Map<String, Object?> metadata;

  bool get ready => status == RuntimeExecutionHandoffBindingStatus.ready;

  RuntimeOutputEvent outputEvent({
    required String message,
    required DateTime timestamp,
    RuntimeOutputChannelKind? kind,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeOutputEvent(
      channelId: outputChannel.id,
      label: outputChannel.label,
      kind: kind ?? outputChannel.kind,
      message: message,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'taskId': handoff.taskId,
        'managerId': managerId,
        'routeKind': routeKind,
        ...metadata,
      },
    );
  }

  RuntimeOutputStreamSubscriptionPlan outputSubscriptionPlan({
    RuntimeOutputRetentionPolicy retentionPolicy =
        const RuntimeOutputRetentionPolicy.workspaceHistory(),
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeOutputStreamSubscriptionPlan.forManager(
      taskId: handoff.taskId,
      managerId: managerId,
      routeKind: routeKind,
      channelIds: <String>[outputChannel.id],
      kinds: <RuntimeOutputChannelKind>[outputChannel.kind],
      status: ready
          ? RuntimeOutputSubscriptionStatus.pending
          : RuntimeOutputSubscriptionStatus.blocked,
      retentionPolicy: retentionPolicy,
      metadata: <String, Object?>{
        'handoffTarget': handoff.target.wireValue,
        'handoffStatus': handoff.status.wireValue,
        'bindingStatus': status.wireValue,
        ...metadata,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'managerId': managerId,
      'routeKind': routeKind,
      'handoff': handoff.toJson(),
      'outputChannel': outputChannel.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeExecutionManagerRegistration {
  const RuntimeExecutionManagerRegistration({
    required this.managerId,
    required this.label,
    this.routeKinds = const <String>[],
    this.available = true,
    this.metadata = const <String, Object?>{},
  });

  final String managerId;
  final String label;
  final List<String> routeKinds;
  final bool available;
  final Map<String, Object?> metadata;

  factory RuntimeExecutionManagerRegistration.shellManager({
    bool available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionManagerRegistration(
      managerId: 'shell-manager',
      label: 'Shell Manager',
      routeKinds: const <String>['local-shell'],
      available: available,
      metadata: <String, Object?>{'managerKind': 'platform-shell', ...metadata},
    );
  }

  factory RuntimeExecutionManagerRegistration.terminalRuntime({
    bool available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionManagerRegistration(
      managerId: 'terminal-runtime',
      label: 'Terminal Runtime',
      routeKinds: const <String>['terminal-session'],
      available: available,
      metadata: <String, Object?>{
        'managerKind': 'toolchain-terminal',
        ...metadata,
      },
    );
  }

  factory RuntimeExecutionManagerRegistration.toolchainManager({
    bool available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionManagerRegistration(
      managerId: 'toolchain-manager',
      label: 'Toolchain Manager',
      routeKinds: const <String>['toolchain-task'],
      available: available,
      metadata: <String, Object?>{'managerKind': 'toolchain-task', ...metadata},
    );
  }

  factory RuntimeExecutionManagerRegistration.hostedExecutor({
    bool available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return RuntimeExecutionManagerRegistration(
      managerId: 'hosted-executor',
      label: 'Hosted Executor',
      routeKinds: const <String>['hosted-task'],
      available: available,
      metadata: <String, Object?>{'managerKind': 'hosted-backend', ...metadata},
    );
  }

  bool accepts(RuntimeExecutionHandoffBinding binding) {
    return managerId == binding.managerId &&
        (routeKinds.isEmpty || routeKinds.contains(binding.routeKind));
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'managerId': managerId,
      'label': label,
      'routeKinds': routeKinds,
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeExecutionDispatchResult {
  const RuntimeExecutionDispatchResult({
    required this.binding,
    required this.status,
    required this.message,
    required this.outputSubscription,
    required this.outputEvent,
    this.manager,
    this.metadata = const <String, Object?>{},
  });

  final RuntimeExecutionHandoffBinding binding;
  final RuntimeExecutionDispatchStatus status;
  final String message;
  final RuntimeExecutionManagerRegistration? manager;
  final RuntimeOutputStreamSubscriptionPlan outputSubscription;
  final RuntimeOutputEvent outputEvent;
  final Map<String, Object?> metadata;

  bool get dispatched => status == RuntimeExecutionDispatchStatus.dispatched;

  RuntimeProcessHandleIdentity? get processHandle {
    return RuntimeProcessHandleIdentity.tryFromMetadata(
      metadata,
      managerId: binding.managerId,
    );
  }

  bool get hasProcessHandle => processHandle != null;

  Map<String, Object?> toJson() {
    final handle = processHandle;
    return <String, Object?>{
      'status': status.wireValue,
      'dispatched': dispatched,
      'message': message,
      'managerId': binding.managerId,
      'routeKind': binding.routeKind,
      'binding': binding.toJson(),
      if (manager != null) 'manager': manager!.toJson(),
      'outputSubscription': outputSubscription.toJson(),
      'outputEvent': outputEvent.toJson(),
      if (handle != null) 'processHandle': handle.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeExecutionManagerRegistry {
  RuntimeExecutionManagerRegistry({
    Iterable<RuntimeExecutionManagerRegistration> managers =
        const <RuntimeExecutionManagerRegistration>[],
  }) {
    for (final manager in managers) {
      register(manager);
    }
  }

  final List<RuntimeExecutionManagerRegistration> _managers =
      <RuntimeExecutionManagerRegistration>[];

  factory RuntimeExecutionManagerRegistry.defaultManagers({
    bool shellManagerAvailable = true,
    bool terminalRuntimeAvailable = true,
    bool toolchainManagerAvailable = true,
    bool hostedExecutorAvailable = true,
  }) {
    return RuntimeExecutionManagerRegistry(
      managers: <RuntimeExecutionManagerRegistration>[
        RuntimeExecutionManagerRegistration.shellManager(
          available: shellManagerAvailable,
        ),
        RuntimeExecutionManagerRegistration.terminalRuntime(
          available: terminalRuntimeAvailable,
        ),
        RuntimeExecutionManagerRegistration.toolchainManager(
          available: toolchainManagerAvailable,
        ),
        RuntimeExecutionManagerRegistration.hostedExecutor(
          available: hostedExecutorAvailable,
        ),
      ],
    );
  }

  List<RuntimeExecutionManagerRegistration> get managers {
    return List<RuntimeExecutionManagerRegistration>.unmodifiable(_managers);
  }

  void register(RuntimeExecutionManagerRegistration manager) {
    _managers.removeWhere(
      (candidate) => candidate.managerId == manager.managerId,
    );
    _managers.add(manager);
  }

  RuntimeExecutionManagerRegistration? resolve(
    RuntimeExecutionHandoffBinding binding,
  ) {
    for (final manager in _managers) {
      if (manager.accepts(binding)) {
        return manager;
      }
    }
    return null;
  }

  RuntimeExecutionDispatchResult dispatch(
    RuntimeExecutionHandoffBinding binding, {
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final subscription = binding.outputSubscriptionPlan(metadata: metadata);
    if (!binding.ready) {
      return RuntimeExecutionDispatchResult(
        binding: binding,
        status: RuntimeExecutionDispatchStatus.blocked,
        message:
            'Runtime execution dispatch blocked: handoff ${binding.handoff.taskId} is not ready.',
        outputSubscription: subscription,
        outputEvent: binding.outputEvent(
          message: 'Runtime execution dispatch blocked.',
          timestamp: timestamp,
          metadata: <String, Object?>{
            'dispatchStatus': RuntimeExecutionDispatchStatus.blocked.wireValue,
            ...metadata,
          },
        ),
        metadata: metadata,
      );
    }
    final manager = resolve(binding);
    if (manager == null || !manager.available) {
      return RuntimeExecutionDispatchResult(
        binding: binding,
        status: RuntimeExecutionDispatchStatus.missingManager,
        manager: manager,
        message:
            'Runtime execution dispatch missing available manager ${binding.managerId} for route ${binding.routeKind}.',
        outputSubscription: subscription,
        outputEvent: binding.outputEvent(
          message: 'Runtime execution manager is unavailable.',
          timestamp: timestamp,
          metadata: <String, Object?>{
            'dispatchStatus':
                RuntimeExecutionDispatchStatus.missingManager.wireValue,
            ...metadata,
          },
        ),
        metadata: metadata,
      );
    }
    final activeSubscription = subscription.activate();
    return RuntimeExecutionDispatchResult(
      binding: binding,
      status: RuntimeExecutionDispatchStatus.dispatched,
      manager: manager,
      message:
          'Runtime execution ${binding.handoff.taskId} dispatched to ${manager.managerId}.',
      outputSubscription: activeSubscription,
      outputEvent: binding.outputEvent(
        message:
            'Runtime execution ${binding.handoff.taskId} dispatched to ${manager.label}.',
        timestamp: timestamp,
        metadata: <String, Object?>{
          'dispatchStatus': RuntimeExecutionDispatchStatus.dispatched.wireValue,
          'managerLabel': manager.label,
          ...metadata,
        },
      ),
      metadata: <String, Object?>{...manager.metadata, ...metadata},
    );
  }

  RuntimeExecutionDispatchResult dispatchToLiveBuffer(
    RuntimeExecutionHandoffBinding binding, {
    required RuntimeOutputLiveBuffer buffer,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final result = dispatch(binding, timestamp: timestamp, metadata: metadata);
    buffer.updateSubscriptionPlan(result.outputSubscription, now: timestamp);
    buffer.addEvent(result.outputEvent, now: timestamp);
    return result;
  }
}

class RuntimeExecutionPlanner {
  const RuntimeExecutionPlanner();

  RuntimeExecutionPlan plan({
    required RuntimeTaskDefinition definition,
    Iterable<RuntimeTaskDefinition> availableDefinitions =
        const <RuntimeTaskDefinition>[],
  }) {
    if (!definition.runnable) {
      return RuntimeExecutionPlan(
        definition: definition,
        status: RuntimeExecutionPlanStatus.blockedUnrunnable,
        message: 'Task ${definition.id} is blocked because it has no command.',
      );
    }
    final availableIds = <String>{
      definition.id,
      for (final available in availableDefinitions) available.id,
    };
    final missingDependencies = definition.dependsOn
        .where((dependencyId) => !availableIds.contains(dependencyId))
        .toList(growable: false);
    if (missingDependencies.isNotEmpty) {
      return RuntimeExecutionPlan(
        definition: definition,
        status: RuntimeExecutionPlanStatus.blockedMissingDependency,
        message:
            'Task ${definition.id} is blocked by missing dependencies: ${missingDependencies.join(', ')}.',
        missingDependencies: missingDependencies,
      );
    }
    return RuntimeExecutionPlan(
      definition: definition,
      status: RuntimeExecutionPlanStatus.ready,
      message: 'Task ${definition.id} is ready to run.',
      executionOrder: <String>[...definition.dependsOn, definition.id],
      metadata: const <String, Object?>{'handoff': 'runtime-execution-handoff'},
    );
  }
}

RuntimeExecutionPlanStatus _planStatusFromWire(Object? value) {
  return switch (value) {
    'ready' => RuntimeExecutionPlanStatus.ready,
    'blocked-unrunnable' => RuntimeExecutionPlanStatus.blockedUnrunnable,
    'blocked-missing-dependency' =>
      RuntimeExecutionPlanStatus.blockedMissingDependency,
    _ => RuntimeExecutionPlanStatus.blockedUnrunnable,
  };
}

String _stringMetadata(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    if (value != null && value is! Iterable && value is! Map) {
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
  }
  return '';
}

int? _intMetadata(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is int) {
      return value;
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return null;
}

RuntimeExecutionHandoffStatus _handoffStatusFromWire(Object? value) {
  return switch (value) {
    'ready' => RuntimeExecutionHandoffStatus.ready,
    'blocked' => RuntimeExecutionHandoffStatus.blocked,
    _ => RuntimeExecutionHandoffStatus.blocked,
  };
}

RuntimeExecutionHandoffTarget _handoffTargetFromWire(Object? value) {
  return switch (value) {
    'shell-manager' => RuntimeExecutionHandoffTarget.shellManager,
    'terminal-runtime' => RuntimeExecutionHandoffTarget.terminalRuntime,
    'toolchain-manager' => RuntimeExecutionHandoffTarget.toolchainManager,
    'hosted-executor' => RuntimeExecutionHandoffTarget.hostedExecutor,
    _ => RuntimeExecutionHandoffTarget.terminalRuntime,
  };
}

String _managerIdForHandoffTarget(RuntimeExecutionHandoffTarget target) {
  return switch (target) {
    RuntimeExecutionHandoffTarget.shellManager => 'shell-manager',
    RuntimeExecutionHandoffTarget.terminalRuntime => 'terminal-runtime',
    RuntimeExecutionHandoffTarget.toolchainManager => 'toolchain-manager',
    RuntimeExecutionHandoffTarget.hostedExecutor => 'hosted-executor',
  };
}

String _routeKindForHandoffTarget(RuntimeExecutionHandoffTarget target) {
  return switch (target) {
    RuntimeExecutionHandoffTarget.shellManager => 'local-shell',
    RuntimeExecutionHandoffTarget.terminalRuntime => 'terminal-session',
    RuntimeExecutionHandoffTarget.toolchainManager => 'toolchain-task',
    RuntimeExecutionHandoffTarget.hostedExecutor => 'hosted-task',
  };
}

RuntimeOutputChannelKind _defaultOutputKindForHandoffTarget(
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

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _jsonStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    if (key.isNotEmpty) {
      result[key] = entry.value.toString();
    }
  }
  return Map<String, String>.unmodifiable(result);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}
