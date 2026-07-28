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

String _cancellationHandleKey(
  String extensionId,
  String contributionId,
  String taskId,
) {
  return '$extensionId::$contributionId::$taskId';
}

enum ExtensionRuntimeTaskTelemetryKind { dispatch, retry, cancellation }

enum ExtensionRuntimeTaskRetryFailureKind {
  transient,
  timeout,
  unavailable,
  invalidConfiguration,
  cancelled,
  unknown,
}

class ExtensionRuntimeTaskRetryPolicy {
  const ExtensionRuntimeTaskRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 250),
    this.backoffMultiplier = 2,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final int backoffMultiplier;

  bool shouldRetry({
    required int failedAttempt,
    required ExtensionRuntimeTaskRetryFailureKind failureKind,
  }) {
    if (failedAttempt >= maxAttempts) {
      return false;
    }
    return switch (failureKind) {
      ExtensionRuntimeTaskRetryFailureKind.transient => true,
      ExtensionRuntimeTaskRetryFailureKind.timeout => true,
      ExtensionRuntimeTaskRetryFailureKind.unavailable => true,
      ExtensionRuntimeTaskRetryFailureKind.unknown => true,
      ExtensionRuntimeTaskRetryFailureKind.invalidConfiguration => false,
      ExtensionRuntimeTaskRetryFailureKind.cancelled => false,
    };
  }

  Duration delayForNextAttempt(int failedAttempt) {
    if (failedAttempt <= 0) {
      return Duration.zero;
    }
    var multiplier = 1;
    for (var index = 1; index < failedAttempt; index += 1) {
      multiplier *= backoffMultiplier;
    }
    return initialDelay * multiplier;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxAttempts': maxAttempts,
      'initialDelayMs': initialDelay.inMilliseconds,
      'backoffMultiplier': backoffMultiplier,
    };
  }
}

class ExtensionRuntimeTaskRetryPlan {
  const ExtensionRuntimeTaskRetryPlan({
    required this.extensionId,
    required this.contributionId,
    required this.taskId,
    required this.attempt,
    required this.nextAttempt,
    required this.retryable,
    required this.failureKind,
    required this.delayBeforeNextAttempt,
    required this.message,
    required this.policy,
  });

  factory ExtensionRuntimeTaskRetryPlan.fromFailure({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required int failedAttempt,
    required ExtensionRuntimeTaskRetryFailureKind failureKind,
    String reason = '',
    ExtensionRuntimeTaskRetryPolicy policy =
        const ExtensionRuntimeTaskRetryPolicy(),
  }) {
    final retryable = policy.shouldRetry(
      failedAttempt: failedAttempt,
      failureKind: failureKind,
    );
    final delay = retryable
        ? policy.delayForNextAttempt(failedAttempt)
        : Duration.zero;
    final nextAttempt = retryable ? failedAttempt + 1 : failedAttempt;
    final taskId = plan.executionPlan.definition.id;
    final reasonSuffix = reason.trim().isEmpty ? '' : ': ${reason.trim()}';
    return ExtensionRuntimeTaskRetryPlan(
      extensionId: plan.contribution.extensionId,
      contributionId: plan.contribution.contributionId,
      taskId: taskId,
      attempt: failedAttempt,
      nextAttempt: nextAttempt,
      retryable: retryable,
      failureKind: failureKind,
      delayBeforeNextAttempt: delay,
      message: retryable
          ? 'Extension runtime task $taskId can retry attempt $nextAttempt after ${delay.inMilliseconds}ms$reasonSuffix.'
          : 'Extension runtime task $taskId cannot retry after attempt $failedAttempt$reasonSuffix.',
      policy: policy,
    );
  }

  final String extensionId;
  final String contributionId;
  final String taskId;
  final int attempt;
  final int nextAttempt;
  final bool retryable;
  final ExtensionRuntimeTaskRetryFailureKind failureKind;
  final Duration delayBeforeNextAttempt;
  final String message;
  final ExtensionRuntimeTaskRetryPolicy policy;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'taskId': taskId,
      'attempt': attempt,
      'nextAttempt': nextAttempt,
      'retryable': retryable,
      'failureKind': failureKind.name,
      'delayBeforeNextAttemptMs': delayBeforeNextAttempt.inMilliseconds,
      'message': message,
      'policy': policy.toJson(),
    };
  }
}

enum ExtensionRuntimeTaskCancellationState {
  registered,
  requested,
  completed,
  unavailable,
}

enum ExtensionRuntimeTaskCancellationDispatchStatus {
  dispatched,
  blocked,
  missingManager,
  missingAdapter,
  rejected,
}

extension ExtensionRuntimeTaskCancellationDispatchStatusX
    on ExtensionRuntimeTaskCancellationDispatchStatus {
  String get wireValue {
    return switch (this) {
      ExtensionRuntimeTaskCancellationDispatchStatus.dispatched => 'dispatched',
      ExtensionRuntimeTaskCancellationDispatchStatus.blocked => 'blocked',
      ExtensionRuntimeTaskCancellationDispatchStatus.missingManager =>
        'missing-manager',
      ExtensionRuntimeTaskCancellationDispatchStatus.missingAdapter =>
        'missing-adapter',
      ExtensionRuntimeTaskCancellationDispatchStatus.rejected => 'rejected',
    };
  }
}

class ExtensionRuntimeTaskCancellationHandle {
  const ExtensionRuntimeTaskCancellationHandle({
    required this.extensionId,
    required this.contributionId,
    required this.taskId,
    required this.processHandleId,
    required this.state,
    required this.canCancel,
    required this.message,
    this.requestedAt,
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionRuntimeTaskCancellationHandle.fromPlan({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required String processHandleId,
    String message = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final taskId = plan.executionPlan.definition.id;
    final handleId = processHandleId.trim();
    return ExtensionRuntimeTaskCancellationHandle(
      extensionId: plan.contribution.extensionId,
      contributionId: plan.contribution.contributionId,
      taskId: taskId,
      processHandleId: handleId,
      state: ExtensionRuntimeTaskCancellationState.registered,
      canCancel: handleId.isNotEmpty,
      message: message.trim().isEmpty
          ? 'Cancellation handle is registered for extension runtime task $taskId.'
          : message.trim(),
      metadata: metadata,
    );
  }

  factory ExtensionRuntimeTaskCancellationHandle.unavailable({
    required ExtensionRuntimeTaskExecutionPlan plan,
    String message = '',
  }) {
    final taskId = plan.executionPlan.definition.id;
    return ExtensionRuntimeTaskCancellationHandle(
      extensionId: plan.contribution.extensionId,
      contributionId: plan.contribution.contributionId,
      taskId: taskId,
      processHandleId: '',
      state: ExtensionRuntimeTaskCancellationState.unavailable,
      canCancel: false,
      message: message.trim().isEmpty
          ? 'No cancellation handle is registered for extension runtime task $taskId.'
          : message.trim(),
    );
  }

  final String extensionId;
  final String contributionId;
  final String taskId;
  final String processHandleId;
  final ExtensionRuntimeTaskCancellationState state;
  final bool canCancel;
  final String message;
  final DateTime? requestedAt;
  final Map<String, Object?> metadata;

  ExtensionRuntimeTaskCancellationHandle markRequested({
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final reasonSuffix = reason.trim().isEmpty ? '' : ': ${reason.trim()}';
    if (!canCancel) {
      return ExtensionRuntimeTaskCancellationHandle(
        extensionId: extensionId,
        contributionId: contributionId,
        taskId: taskId,
        processHandleId: processHandleId,
        state: ExtensionRuntimeTaskCancellationState.unavailable,
        canCancel: false,
        requestedAt: timestamp,
        message:
            'Extension runtime task $taskId cannot be cancelled$reasonSuffix.',
        metadata: <String, Object?>{...this.metadata, ...metadata},
      );
    }
    return ExtensionRuntimeTaskCancellationHandle(
      extensionId: extensionId,
      contributionId: contributionId,
      taskId: taskId,
      processHandleId: processHandleId,
      state: ExtensionRuntimeTaskCancellationState.requested,
      canCancel: canCancel,
      requestedAt: timestamp,
      message:
          'Cancellation requested for extension runtime task $taskId$reasonSuffix.',
      metadata: <String, Object?>{...this.metadata, ...metadata},
    );
  }

  ExtensionRuntimeTaskCancellationHandle markCompleted({
    required DateTime timestamp,
    String message = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionRuntimeTaskCancellationHandle(
      extensionId: extensionId,
      contributionId: contributionId,
      taskId: taskId,
      processHandleId: processHandleId,
      state: ExtensionRuntimeTaskCancellationState.completed,
      canCancel: false,
      requestedAt: requestedAt ?? timestamp,
      message: message.trim().isEmpty
          ? 'Cancellation completed for extension runtime task $taskId.'
          : message.trim(),
      metadata: <String, Object?>{...this.metadata, ...metadata},
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'taskId': taskId,
      'processHandleId': processHandleId,
      'state': state.name,
      'canCancel': canCancel,
      'message': message,
      if (requestedAt != null) 'requestedAt': requestedAt!.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionRuntimeTaskCancellationRegistry {
  ExtensionRuntimeTaskCancellationRegistry({
    Iterable<ExtensionRuntimeTaskCancellationHandle> handles = const [],
  }) : _handles = <String, ExtensionRuntimeTaskCancellationHandle>{
         for (final handle in handles)
           _cancellationHandleKey(
             handle.extensionId,
             handle.contributionId,
             handle.taskId,
           ): handle,
       };

  final Map<String, ExtensionRuntimeTaskCancellationHandle> _handles;

  List<ExtensionRuntimeTaskCancellationHandle> get handles {
    return _handles.values.toList(growable: false);
  }

  ExtensionRuntimeTaskCancellationHandle register({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required String processHandleId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final handle = ExtensionRuntimeTaskCancellationHandle.fromPlan(
      plan: plan,
      processHandleId: processHandleId,
      metadata: metadata,
    );
    _handles[_keyForPlan(plan)] = handle;
    return handle;
  }

  ExtensionRuntimeTaskCancellationHandle? lookup(
    ExtensionRuntimeTaskExecutionPlan plan,
  ) {
    return _handles[_keyForPlan(plan)];
  }

  ExtensionRuntimeTaskCancellationHandle requestCancellation({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final handle =
        lookup(plan) ??
        ExtensionRuntimeTaskCancellationHandle.unavailable(plan: plan);
    final requested = handle.markRequested(
      timestamp: timestamp,
      reason: reason,
      metadata: metadata,
    );
    _handles[_keyForPlan(plan)] = requested;
    return requested;
  }

  ExtensionRuntimeTaskCancellationHandle completeCancellation({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String message = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final handle =
        lookup(plan) ??
        ExtensionRuntimeTaskCancellationHandle.unavailable(plan: plan);
    final completed = handle.markCompleted(
      timestamp: timestamp,
      message: message,
      metadata: metadata,
    );
    _handles[_keyForPlan(plan)] = completed;
    return completed;
  }

  String _keyForPlan(ExtensionRuntimeTaskExecutionPlan plan) {
    return _cancellationHandleKey(
      plan.contribution.extensionId,
      plan.contribution.contributionId,
      plan.executionPlan.definition.id,
    );
  }
}

enum ExtensionRuntimeTaskProcessHandleBindingStatus {
  registered,
  missingHandle,
  skipped,
}

class ExtensionRuntimeTaskProcessHandleBindingResult {
  const ExtensionRuntimeTaskProcessHandleBindingResult({
    required this.status,
    required this.message,
    this.handle,
    this.metadata = const <String, Object?>{},
  });

  const ExtensionRuntimeTaskProcessHandleBindingResult.registered({
    required ExtensionRuntimeTaskCancellationHandle handle,
    String message = 'Runtime task process handle registered.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: ExtensionRuntimeTaskProcessHandleBindingStatus.registered,
         message: message,
         handle: handle,
         metadata: metadata,
       );

  const ExtensionRuntimeTaskProcessHandleBindingResult.missingHandle({
    String message = 'Runtime task dispatch did not expose a process handle.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: ExtensionRuntimeTaskProcessHandleBindingStatus.missingHandle,
         message: message,
         metadata: metadata,
       );

  const ExtensionRuntimeTaskProcessHandleBindingResult.skipped({
    String message =
        'Runtime task dispatch was not eligible for handle binding.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: ExtensionRuntimeTaskProcessHandleBindingStatus.skipped,
         message: message,
         metadata: metadata,
       );

  final ExtensionRuntimeTaskProcessHandleBindingStatus status;
  final String message;
  final ExtensionRuntimeTaskCancellationHandle? handle;
  final Map<String, Object?> metadata;

  bool get registered =>
      status == ExtensionRuntimeTaskProcessHandleBindingStatus.registered;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'registered': registered,
      'message': message,
      if (handle != null) 'handle': handle!.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionRuntimeTaskProcessHandleBinder {
  const ExtensionRuntimeTaskProcessHandleBinder({
    this.handleIdKeys = const <String>[
      'processHandleId',
      'processId',
      'pid',
      'taskHandleId',
    ],
  });

  final List<String> handleIdKeys;

  ExtensionRuntimeTaskProcessHandleBindingResult bind({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required RuntimeExecutionDispatchResult result,
    required ExtensionRuntimeTaskCancellationRegistry registry,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!result.dispatched) {
      return ExtensionRuntimeTaskProcessHandleBindingResult.skipped(
        message:
            'Runtime task ${plan.executionPlan.definition.id} was not dispatched; no process handle was bound.',
        metadata: metadata,
      );
    }
    final processHandle = result.processHandle;
    final handleId =
        _handleIdFromProcessHandle(processHandle) ??
        _handleIdFromResult(result);
    if (handleId == null) {
      return ExtensionRuntimeTaskProcessHandleBindingResult.missingHandle(
        message:
            'Runtime task ${plan.executionPlan.definition.id} dispatch did not expose a process handle.',
        metadata: metadata,
      );
    }
    final handle = registry.register(
      plan: plan,
      processHandleId: handleId,
      metadata: <String, Object?>{
        'source': 'runtime-dispatch-result',
        'managerId': result.binding.managerId,
        'routeKind': result.binding.routeKind,
        if (result.manager != null) 'manager': result.manager!.toJson(),
        if (processHandle != null) 'processHandle': processHandle.toJson(),
        ...metadata,
      },
    );
    return ExtensionRuntimeTaskProcessHandleBindingResult.registered(
      handle: handle,
      message:
          'Runtime task ${plan.executionPlan.definition.id} process handle $handleId registered.',
      metadata: metadata,
    );
  }

  String? _handleIdFromProcessHandle(RuntimeProcessHandleIdentity? handle) {
    if (handle == null || !handle.available) {
      return null;
    }
    if (handle.processHandleId.isNotEmpty) {
      return handle.processHandleId;
    }
    final pid = handle.pid;
    return pid == null ? null : '$pid';
  }

  String? _handleIdFromResult(RuntimeExecutionDispatchResult result) {
    for (final source in <Map<String, Object?>>[
      result.metadata,
      result.outputEvent.metadata,
      result.binding.metadata,
      result.binding.handoff.metadata,
      result.binding.handoff.plan.metadata,
    ]) {
      final handleId = _handleIdFromMetadata(source);
      if (handleId != null) {
        return handleId;
      }
    }
    return null;
  }

  String? _handleIdFromMetadata(Map<String, Object?> metadata) {
    for (final key in handleIdKeys) {
      final value = metadata[key];
      if (value == null) {
        continue;
      }
      final handleId = '$value'.trim();
      if (handleId.isNotEmpty) {
        return handleId;
      }
    }
    return null;
  }
}

class ExtensionRuntimeTaskCancellationAdapterResult {
  const ExtensionRuntimeTaskCancellationAdapterResult({
    required this.accepted,
    required this.processTerminated,
    required this.message,
    this.metadata = const <String, Object?>{},
  });

  const ExtensionRuntimeTaskCancellationAdapterResult.accepted({
    bool processTerminated = false,
    String message = 'Extension runtime task cancellation accepted.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: true,
         processTerminated: processTerminated,
         message: message,
         metadata: metadata,
       );

  const ExtensionRuntimeTaskCancellationAdapterResult.rejected({
    String message = 'Extension runtime task cancellation rejected.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: false,
         processTerminated: false,
         message: message,
         metadata: metadata,
       );

  final bool accepted;
  final bool processTerminated;
  final String message;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accepted': accepted,
      'processTerminated': processTerminated,
      'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

typedef ExtensionRuntimeTaskCancellationAdapterHandler =
    Future<ExtensionRuntimeTaskCancellationAdapterResult> Function({
      required ExtensionRuntimeTaskExecutionPlan plan,
      required ExtensionRuntimeTaskCancellationHandle handle,
      required DateTime timestamp,
      required String reason,
    });

enum ExtensionRuntimeTaskTerminationSignal { interrupt, terminate, kill }

extension ExtensionRuntimeTaskTerminationSignalX
    on ExtensionRuntimeTaskTerminationSignal {
  String get wireValue {
    return switch (this) {
      ExtensionRuntimeTaskTerminationSignal.interrupt => 'interrupt',
      ExtensionRuntimeTaskTerminationSignal.terminate => 'terminate',
      ExtensionRuntimeTaskTerminationSignal.kill => 'kill',
    };
  }
}

class ExtensionRuntimeTaskTerminationRequest {
  const ExtensionRuntimeTaskTerminationRequest({
    required this.plan,
    required this.handle,
    required this.timestamp,
    required this.reason,
    required this.managerId,
    required this.backendKind,
    this.signal = ExtensionRuntimeTaskTerminationSignal.terminate,
  });

  final ExtensionRuntimeTaskExecutionPlan plan;
  final ExtensionRuntimeTaskCancellationHandle handle;
  final DateTime timestamp;
  final String reason;
  final String managerId;
  final String backendKind;
  final ExtensionRuntimeTaskTerminationSignal signal;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': plan.contribution.extensionId,
      'contributionId': plan.contribution.contributionId,
      'taskId': plan.executionPlan.definition.id,
      'processHandleId': handle.processHandleId,
      'timestamp': timestamp.toIso8601String(),
      'reason': reason,
      'managerId': managerId,
      'backendKind': backendKind,
      'signal': signal.wireValue,
    };
  }
}

class ExtensionRuntimeTaskTerminationResult {
  const ExtensionRuntimeTaskTerminationResult({
    required this.accepted,
    required this.processTerminated,
    required this.message,
    this.metadata = const <String, Object?>{},
  });

  const ExtensionRuntimeTaskTerminationResult.accepted({
    bool processTerminated = true,
    String message = 'Extension runtime task process termination accepted.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: true,
         processTerminated: processTerminated,
         message: message,
         metadata: metadata,
       );

  const ExtensionRuntimeTaskTerminationResult.rejected({
    String message = 'Extension runtime task process termination rejected.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: false,
         processTerminated: false,
         message: message,
         metadata: metadata,
       );

  final bool accepted;
  final bool processTerminated;
  final String message;
  final Map<String, Object?> metadata;

  ExtensionRuntimeTaskCancellationAdapterResult toAdapterResult() {
    return ExtensionRuntimeTaskCancellationAdapterResult(
      accepted: accepted,
      processTerminated: processTerminated,
      message: message,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accepted': accepted,
      'processTerminated': processTerminated,
      'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

typedef ExtensionRuntimeTaskTerminator =
    Future<ExtensionRuntimeTaskTerminationResult> Function(
      ExtensionRuntimeTaskTerminationRequest request,
    );

class ExtensionRuntimeTaskCancellationAdapter {
  const ExtensionRuntimeTaskCancellationAdapter({
    required this.managerId,
    required ExtensionRuntimeTaskCancellationAdapterHandler cancel,
    this.routeKinds = const <String>[],
  }) : _cancel = cancel;

  factory ExtensionRuntimeTaskCancellationAdapter.processManager({
    required ExtensionRuntimeTaskTerminator terminate,
    String managerId = 'toolchain-manager',
    List<String> routeKinds = const <String>['toolchain-task'],
    ExtensionRuntimeTaskTerminationSignal signal =
        ExtensionRuntimeTaskTerminationSignal.terminate,
  }) {
    return ExtensionRuntimeTaskCancellationAdapter(
      managerId: managerId,
      routeKinds: routeKinds,
      cancel:
          ({
            required plan,
            required handle,
            required timestamp,
            required reason,
          }) async {
            final result = await terminate(
              ExtensionRuntimeTaskTerminationRequest(
                plan: plan,
                handle: handle,
                timestamp: timestamp,
                reason: reason,
                managerId: managerId,
                backendKind: 'process-manager',
                signal: signal,
              ),
            );
            return result.toAdapterResult();
          },
    );
  }

  factory ExtensionRuntimeTaskCancellationAdapter.shellManager({
    required ExtensionRuntimeTaskTerminator terminate,
    String managerId = 'shell-manager',
    List<String> routeKinds = const <String>['shell-command'],
    ExtensionRuntimeTaskTerminationSignal signal =
        ExtensionRuntimeTaskTerminationSignal.terminate,
  }) {
    return ExtensionRuntimeTaskCancellationAdapter(
      managerId: managerId,
      routeKinds: routeKinds,
      cancel:
          ({
            required plan,
            required handle,
            required timestamp,
            required reason,
          }) async {
            final result = await terminate(
              ExtensionRuntimeTaskTerminationRequest(
                plan: plan,
                handle: handle,
                timestamp: timestamp,
                reason: reason,
                managerId: managerId,
                backendKind: 'shell-manager',
                signal: signal,
              ),
            );
            return result.toAdapterResult();
          },
    );
  }

  final String managerId;
  final List<String> routeKinds;
  final ExtensionRuntimeTaskCancellationAdapterHandler _cancel;

  bool accepts(ExtensionRuntimeTaskExecutionPlan plan) {
    return plan.binding.managerId == managerId &&
        (routeKinds.isEmpty || routeKinds.contains(plan.binding.routeKind));
  }

  Future<ExtensionRuntimeTaskCancellationAdapterResult> cancel({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required ExtensionRuntimeTaskCancellationHandle handle,
    required DateTime timestamp,
    required String reason,
  }) {
    return _cancel(
      plan: plan,
      handle: handle,
      timestamp: timestamp,
      reason: reason,
    );
  }
}

class ExtensionRuntimeTaskCancellationDispatchResult {
  const ExtensionRuntimeTaskCancellationDispatchResult({
    required this.plan,
    required this.handle,
    required this.status,
    required this.message,
    this.manager,
    this.adapterResult,
    this.telemetryRecord,
    this.metadata = const <String, Object?>{},
  });

  final ExtensionRuntimeTaskExecutionPlan plan;
  final ExtensionRuntimeTaskCancellationHandle handle;
  final ExtensionRuntimeTaskCancellationDispatchStatus status;
  final String message;
  final RuntimeExecutionManagerRegistration? manager;
  final ExtensionRuntimeTaskCancellationAdapterResult? adapterResult;
  final ExtensionRuntimeTaskTelemetryRecord? telemetryRecord;
  final Map<String, Object?> metadata;

  bool get dispatched =>
      status == ExtensionRuntimeTaskCancellationDispatchStatus.dispatched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'dispatched': dispatched,
      'message': message,
      'managerId': plan.binding.managerId,
      'routeKind': plan.binding.routeKind,
      'handle': handle.toJson(),
      if (manager != null) 'manager': manager!.toJson(),
      if (adapterResult != null) 'adapterResult': adapterResult!.toJson(),
      if (telemetryRecord != null) 'telemetry': telemetryRecord!.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

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
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
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
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
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

  Future<void> saveTelemetry(ExtensionRuntimeTaskTelemetrySnapshot snapshot) {
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
    ExtensionRuntimeTaskCancellationRegistry? cancellationRegistry,
    ExtensionRuntimeTaskProcessHandleBinder processHandleBinder =
        const ExtensionRuntimeTaskProcessHandleBinder(),
    Iterable<ExtensionRuntimeTaskCancellationAdapter> cancellationAdapters =
        const <ExtensionRuntimeTaskCancellationAdapter>[],
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers(),
       _telemetrySink = telemetrySink,
       _cancellationRegistry =
           cancellationRegistry ?? ExtensionRuntimeTaskCancellationRegistry(),
       _processHandleBinder = processHandleBinder,
       _cancellationAdapters = cancellationAdapters.toList(growable: false);

  final RuntimeExecutionManagerRegistry _registry;
  final ExtensionRuntimeTaskTelemetrySink? _telemetrySink;
  final ExtensionRuntimeTaskCancellationRegistry _cancellationRegistry;
  final ExtensionRuntimeTaskProcessHandleBinder _processHandleBinder;
  final List<ExtensionRuntimeTaskCancellationAdapter> _cancellationAdapters;

  ExtensionRuntimeTaskCancellationRegistry get cancellationRegistry =>
      _cancellationRegistry;

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
    _processHandleBinder.bind(
      plan: plan,
      result: result,
      registry: _cancellationRegistry,
      metadata: <String, Object?>{
        'timestamp': timestamp.toIso8601String(),
        ...metadata,
      },
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

  ExtensionRuntimeTaskCancellationHandle registerCancellationHandle({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required String processHandleId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _cancellationRegistry.register(
      plan: plan,
      processHandleId: processHandleId,
      metadata: metadata,
    );
  }

  Future<ExtensionRuntimeTaskCancellationDispatchResult> dispatchCancellation({
    required ExtensionRuntimeTaskExecutionPlan plan,
    required DateTime timestamp,
    String reason = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final requested = _cancellationRegistry.requestCancellation(
      plan: plan,
      timestamp: timestamp,
      reason: reason,
      metadata: metadata,
    );
    if (!requested.canCancel) {
      final record = recordCancellation(
        plan: plan,
        timestamp: timestamp,
        reason: requested.message,
        metadata: <String, Object?>{
          'dispatchStatus':
              ExtensionRuntimeTaskCancellationDispatchStatus.blocked.wireValue,
          'cancellationHandle': requested.toJson(),
          ...metadata,
        },
      );
      return ExtensionRuntimeTaskCancellationDispatchResult(
        plan: plan,
        handle: requested,
        status: ExtensionRuntimeTaskCancellationDispatchStatus.blocked,
        message: requested.message,
        telemetryRecord: record,
        metadata: metadata,
      );
    }
    final manager = _registry.resolve(plan.binding);
    if (manager == null || !manager.available) {
      final record = recordCancellation(
        plan: plan,
        timestamp: timestamp,
        reason:
            'No available runtime execution manager ${plan.binding.managerId} for cancellation.',
        metadata: <String, Object?>{
          'dispatchStatus': ExtensionRuntimeTaskCancellationDispatchStatus
              .missingManager
              .wireValue,
          'cancellationHandle': requested.toJson(),
          ...metadata,
        },
      );
      return ExtensionRuntimeTaskCancellationDispatchResult(
        plan: plan,
        handle: requested,
        status: ExtensionRuntimeTaskCancellationDispatchStatus.missingManager,
        message:
            'Extension runtime task ${plan.executionPlan.definition.id} cancellation missing available manager ${plan.binding.managerId}.',
        telemetryRecord: record,
        metadata: metadata,
      );
    }
    final adapter = _cancellationAdapterFor(plan);
    if (adapter == null) {
      final record = recordCancellation(
        plan: plan,
        timestamp: timestamp,
        reason:
            'No cancellation adapter is registered for ${plan.binding.managerId}/${plan.binding.routeKind}.',
        metadata: <String, Object?>{
          'dispatchStatus': ExtensionRuntimeTaskCancellationDispatchStatus
              .missingAdapter
              .wireValue,
          'cancellationHandle': requested.toJson(),
          'manager': manager.toJson(),
          ...metadata,
        },
      );
      return ExtensionRuntimeTaskCancellationDispatchResult(
        plan: plan,
        handle: requested,
        manager: manager,
        status: ExtensionRuntimeTaskCancellationDispatchStatus.missingAdapter,
        message:
            'Extension runtime task ${plan.executionPlan.definition.id} cancellation missing adapter for ${plan.binding.managerId}/${plan.binding.routeKind}.',
        telemetryRecord: record,
        metadata: metadata,
      );
    }
    late final ExtensionRuntimeTaskCancellationAdapterResult adapterResult;
    try {
      adapterResult = await adapter.cancel(
        plan: plan,
        handle: requested,
        timestamp: timestamp,
        reason: reason,
      );
    } on Object catch (error) {
      adapterResult = ExtensionRuntimeTaskCancellationAdapterResult.rejected(
        message:
            'Extension runtime task ${plan.executionPlan.definition.id} cancellation adapter failed: $error.',
      );
    }
    if (!adapterResult.accepted) {
      final record = recordCancellation(
        plan: plan,
        timestamp: timestamp,
        reason: adapterResult.message,
        metadata: <String, Object?>{
          'dispatchStatus':
              ExtensionRuntimeTaskCancellationDispatchStatus.rejected.wireValue,
          'cancellationHandle': requested.toJson(),
          'manager': manager.toJson(),
          'adapterResult': adapterResult.toJson(),
          ...metadata,
        },
      );
      return ExtensionRuntimeTaskCancellationDispatchResult(
        plan: plan,
        handle: requested,
        manager: manager,
        status: ExtensionRuntimeTaskCancellationDispatchStatus.rejected,
        message: adapterResult.message,
        adapterResult: adapterResult,
        telemetryRecord: record,
        metadata: metadata,
      );
    }
    final completed = _cancellationRegistry.completeCancellation(
      plan: plan,
      timestamp: timestamp,
      message: adapterResult.message,
      metadata: <String, Object?>{
        'adapterResult': adapterResult.toJson(),
        ...metadata,
      },
    );
    final record = recordCancellation(
      plan: plan,
      timestamp: timestamp,
      reason: adapterResult.message,
      metadata: <String, Object?>{
        'dispatchStatus':
            ExtensionRuntimeTaskCancellationDispatchStatus.dispatched.wireValue,
        'cancellationHandle': completed.toJson(),
        'manager': manager.toJson(),
        'adapterResult': adapterResult.toJson(),
        ...metadata,
      },
    );
    return ExtensionRuntimeTaskCancellationDispatchResult(
      plan: plan,
      handle: completed,
      manager: manager,
      status: ExtensionRuntimeTaskCancellationDispatchStatus.dispatched,
      message: adapterResult.message,
      adapterResult: adapterResult,
      telemetryRecord: record,
      metadata: metadata,
    );
  }

  ExtensionRuntimeTaskCancellationAdapter? _cancellationAdapterFor(
    ExtensionRuntimeTaskExecutionPlan plan,
  ) {
    for (final adapter in _cancellationAdapters) {
      if (adapter.accepts(plan)) {
        return adapter;
      }
    }
    return null;
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

List<ExtensionRuntimeTaskTelemetryRecord> _extensionRuntimeTaskTelemetryRecords(
  Object? value,
) {
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
