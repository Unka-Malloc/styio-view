import 'agent_provider_adapter.dart';

typedef AgentProviderRetryOperation<T> = Future<T> Function(int attempt);
typedef AgentProviderRetryDelay = Future<void> Function(Duration delay);
typedef AgentProviderRetryClock = DateTime Function();
typedef HostedControlPlaneRetryTransport =
    Future<HostedBackendRetryActionResult> Function(
      HostedBackendRetryEndpointPlan plan,
    );
typedef AgentProviderResponseRetryTelemetrySink =
    void Function(
      AgentProviderRequest request,
      AgentProviderRetryExecution<AgentProviderResponseEnvelope> execution,
    );

DateTime _retryNow() => DateTime.now().toUtc();

enum AgentProviderRetryAttemptStatus { succeeded, failed }

extension AgentProviderRetryAttemptStatusX on AgentProviderRetryAttemptStatus {
  String get wireValue {
    return switch (this) {
      AgentProviderRetryAttemptStatus.succeeded => 'succeeded',
      AgentProviderRetryAttemptStatus.failed => 'failed',
    };
  }
}

class AgentProviderRetryPolicy {
  const AgentProviderRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 250),
    this.backoffMultiplier = 2,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final int backoffMultiplier;

  bool shouldRetry({required int attempt, required Object error}) {
    if (attempt >= maxAttempts) {
      return false;
    }
    if (error is! AgentProviderTransportException) {
      return false;
    }
    return switch (error.kind) {
      AgentProviderTransportFailureKind.timeout => true,
      AgentProviderTransportFailureKind.hostUnreachable => true,
      AgentProviderTransportFailureKind.unknown => true,
      AgentProviderTransportFailureKind.httpStatus => _retryableStatusCode(
        error.statusCode,
      ),
      AgentProviderTransportFailureKind.cancelled => false,
      AgentProviderTransportFailureKind.invalidResponse => false,
      AgentProviderTransportFailureKind.tlsFailure => false,
      AgentProviderTransportFailureKind.unsupported => false,
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

  bool _retryableStatusCode(int? statusCode) {
    if (statusCode == null) {
      return true;
    }
    return statusCode == 408 || statusCode == 429 || statusCode >= 500;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxAttempts': maxAttempts,
      'initialDelayMs': initialDelay.inMilliseconds,
      'backoffMultiplier': backoffMultiplier,
    };
  }
}

class AgentProviderRetryAttempt {
  const AgentProviderRetryAttempt({
    required this.attempt,
    required this.status,
    required this.startedAt,
    this.finishedAt,
    this.failureKind,
    this.statusCode,
    this.message,
    this.retryScheduled = false,
    this.delayBeforeNextAttempt = Duration.zero,
  });

  final int attempt;
  final AgentProviderRetryAttemptStatus status;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final AgentProviderTransportFailureKind? failureKind;
  final int? statusCode;
  final String? message;
  final bool retryScheduled;
  final Duration delayBeforeNextAttempt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'attempt': attempt,
      'status': status.wireValue,
      'startedAt': startedAt.toIso8601String(),
      if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      if (failureKind != null) 'failureKind': failureKind!.name,
      if (statusCode != null) 'statusCode': statusCode,
      if (message != null) 'message': message,
      'retryScheduled': retryScheduled,
      if (delayBeforeNextAttempt != Duration.zero)
        'delayBeforeNextAttemptMs': delayBeforeNextAttempt.inMilliseconds,
    };
  }
}

class AgentProviderRetryExecution<T> {
  const AgentProviderRetryExecution({
    required this.attempts,
    this.value,
    this.error,
  });

  final T? value;
  final Object? error;
  final List<AgentProviderRetryAttempt> attempts;

  bool get succeeded => error == null;
  int get attemptCount => attempts.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'succeeded': succeeded,
      'attemptCount': attemptCount,
      if (error != null) 'error': error.toString(),
      'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
    };
  }
}

class AgentProviderRetryExecutor {
  const AgentProviderRetryExecutor({
    this.policy = const AgentProviderRetryPolicy(),
    this.delay = _noDelay,
    this.clock = _retryNow,
  });

  final AgentProviderRetryPolicy policy;
  final AgentProviderRetryDelay delay;
  final AgentProviderRetryClock clock;

  Future<AgentProviderRetryExecution<T>> execute<T>({
    required AgentProviderRetryOperation<T> operation,
  }) async {
    final attempts = <AgentProviderRetryAttempt>[];
    for (var attempt = 1; attempt <= policy.maxAttempts; attempt += 1) {
      final startedAt = clock();
      try {
        final value = await operation(attempt);
        attempts.add(
          AgentProviderRetryAttempt(
            attempt: attempt,
            status: AgentProviderRetryAttemptStatus.succeeded,
            startedAt: startedAt,
            finishedAt: clock(),
          ),
        );
        return AgentProviderRetryExecution<T>(
          attempts: List<AgentProviderRetryAttempt>.unmodifiable(attempts),
          value: value,
        );
      } on Object catch (error) {
        final retry = policy.shouldRetry(attempt: attempt, error: error);
        final retryDelay = retry
            ? policy.delayForNextAttempt(attempt)
            : Duration.zero;
        attempts.add(
          AgentProviderRetryAttempt(
            attempt: attempt,
            status: AgentProviderRetryAttemptStatus.failed,
            startedAt: startedAt,
            finishedAt: clock(),
            failureKind: _failureKind(error),
            statusCode: _statusCode(error),
            message: _message(error),
            retryScheduled: retry,
            delayBeforeNextAttempt: retryDelay,
          ),
        );
        if (!retry) {
          return AgentProviderRetryExecution<T>(
            attempts: List<AgentProviderRetryAttempt>.unmodifiable(attempts),
            error: error,
          );
        }
        await delay(retryDelay);
      }
    }
    return AgentProviderRetryExecution<T>(
      attempts: List<AgentProviderRetryAttempt>.unmodifiable(attempts),
      error: StateError('Agent provider retry policy exhausted.'),
    );
  }

  AgentProviderTransportFailureKind? _failureKind(Object error) {
    return error is AgentProviderTransportException ? error.kind : null;
  }

  int? _statusCode(Object error) {
    return error is AgentProviderTransportException ? error.statusCode : null;
  }

  String _message(Object error) {
    return error is AgentProviderTransportException
        ? error.message
        : error.toString();
  }
}

class RetryingAgentProviderAdapter
    implements StreamingAgentProviderAdapter, CancellableAgentProviderAdapter {
  const RetryingAgentProviderAdapter({
    required this.inner,
    this.retryExecutor = const AgentProviderRetryExecutor(),
    this.telemetrySink,
  });

  final AgentProviderAdapter inner;
  final AgentProviderRetryExecutor retryExecutor;
  final AgentProviderResponseRetryTelemetrySink? telemetrySink;

  @override
  AgentProviderKind get kind => inner.kind;

  @override
  String get adapterId => '${inner.adapterId}:retrying';

  @override
  bool get supportsCodePatch => inner.supportsCodePatch;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    final execution = await retryExecutor
        .execute<AgentProviderResponseEnvelope>(
          operation: (_) => inner.send(request),
        );
    telemetrySink?.call(request, execution);
    if (execution.succeeded && execution.value != null) {
      return execution.value!;
    }
    final error = execution.error;
    if (error != null) {
      throw error;
    }
    throw StateError('Agent provider retry execution failed without an error.');
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    final streaming = inner is StreamingAgentProviderAdapter
        ? inner as StreamingAgentProviderAdapter
        : null;
    if (streaming == null) {
      yield* _streamFromSend(request);
      return;
    }

    final lastAttemptEvents = <AgentProviderStreamEvent>[];
    final successfulEvents = <AgentProviderStreamEvent>[];
    final execution = await retryExecutor.execute<AgentProviderResponseEnvelope>(
      operation: (_) async {
        final attemptEvents = <AgentProviderStreamEvent>[];
        try {
          final response = await const AgentProviderStreamingResponseCollector()
              .collect(
                requestId: request.requestId,
                events: streaming.stream(request).map((event) {
                  attemptEvents.add(event);
                  return event;
                }),
              );
          successfulEvents
            ..clear()
            ..addAll(attemptEvents);
          return response;
        } finally {
          lastAttemptEvents
            ..clear()
            ..addAll(attemptEvents);
        }
      },
    );
    telemetrySink?.call(request, execution);
    if (execution.succeeded && execution.value != null) {
      if (successfulEvents.isNotEmpty) {
        yield* Stream<AgentProviderStreamEvent>.fromIterable(
          successfulEvents,
        );
        return;
      }
      yield AgentProviderStreamEvent.completed(
        requestId: request.requestId,
        response: execution.value,
        metadata: const <String, Object?>{'synthetic': true},
      );
      return;
    }
    if (lastAttemptEvents.isNotEmpty && lastAttemptEvents.last.terminal) {
      yield* Stream<AgentProviderStreamEvent>.fromIterable(lastAttemptEvents);
      return;
    }
    yield AgentProviderStreamEvent.failed(
      requestId: request.requestId,
      message: execution.error?.toString() ??
          'Agent provider retry execution failed without an error.',
      metadata: const <String, Object?>{'synthetic': true},
    );
  }

  Stream<AgentProviderStreamEvent> _streamFromSend(
    AgentProviderRequest request,
  ) async* {
    yield AgentProviderStreamEvent.started(
      request.requestId,
      metadata: const <String, Object?>{'synthetic': true},
    );
    try {
      final response = await send(request);
      for (final part in response.contentParts) {
        yield AgentProviderStreamEvent.part(
          requestId: request.requestId,
          contentPart: part,
          metadata: const <String, Object?>{'synthetic': true},
        );
      }
      yield AgentProviderStreamEvent.completed(
        requestId: request.requestId,
        response: response,
        metadata: const <String, Object?>{'synthetic': true},
      );
    } on Object catch (error) {
      yield AgentProviderStreamEvent.failed(
        requestId: request.requestId,
        message: error is AgentProviderTransportException
            ? error.message
            : error.toString(),
        metadata: const <String, Object?>{'synthetic': true},
      );
    }
  }

  @override
  void cancelRequest(String requestId) {
    final cancellable = inner is CancellableAgentProviderAdapter
        ? inner as CancellableAgentProviderAdapter
        : null;
    cancellable?.cancelRequest(requestId);
  }
}

Future<void> _noDelay(Duration delay) async {}

enum HostedBackendRetryEndpointKind {
  retryAgentProvider,
  reopenWorkspace,
  exportWorkspace,
  openSettings,
}

extension HostedBackendRetryEndpointKindX on HostedBackendRetryEndpointKind {
  String get wireValue {
    return switch (this) {
      HostedBackendRetryEndpointKind.retryAgentProvider =>
        'retry-agent-provider',
      HostedBackendRetryEndpointKind.reopenWorkspace => 'reopen-workspace',
      HostedBackendRetryEndpointKind.exportWorkspace => 'export-workspace',
      HostedBackendRetryEndpointKind.openSettings => 'open-settings',
    };
  }
}

class HostedBackendRetryEndpointPlan {
  const HostedBackendRetryEndpointPlan({
    required this.kind,
    required this.method,
    required this.path,
    required this.label,
    required this.message,
    this.settingsSectionId = '',
    this.requiresConfirmation = false,
    this.metadata = const <String, Object?>{},
  });

  static List<HostedBackendRetryEndpointPlan> defaultControlPlaneEndpoints({
    String basePath = '/api/vityo/hosted/v1',
  }) {
    final root = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return <HostedBackendRetryEndpointPlan>[
      HostedBackendRetryEndpointPlan(
        kind: HostedBackendRetryEndpointKind.retryAgentProvider,
        method: 'POST',
        path: '$root/agent/retry',
        label: 'Retry hosted agent provider',
        message:
            'Retry the current hosted agent provider request through the control plane.',
      ),
      HostedBackendRetryEndpointPlan(
        kind: HostedBackendRetryEndpointKind.reopenWorkspace,
        method: 'POST',
        path: '$root/workspaces/reopen',
        label: 'Reopen hosted workspace',
        message:
            'Ask the hosted control plane to reopen the current workspace session.',
        requiresConfirmation: true,
      ),
      HostedBackendRetryEndpointPlan(
        kind: HostedBackendRetryEndpointKind.exportWorkspace,
        method: 'POST',
        path: '$root/workspaces/export',
        label: 'Export hosted workspace',
        message:
            'Export workspace state before changing hosted provider or session settings.',
        requiresConfirmation: true,
      ),
      HostedBackendRetryEndpointPlan(
        kind: HostedBackendRetryEndpointKind.openSettings,
        method: 'GET',
        path: '$root/settings/agent-provider',
        label: 'Open hosted provider settings',
        message:
            'Open the hosted provider settings recovery route for credential or endpoint repair.',
        settingsSectionId: 'agent-provider',
      ),
    ];
  }

  final HostedBackendRetryEndpointKind kind;
  final String method;
  final String path;
  final String label;
  final String message;
  final String settingsSectionId;
  final bool requiresConfirmation;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'method': method,
      'path': path,
      'label': label,
      'message': message,
      'requiresConfirmation': requiresConfirmation,
      if (settingsSectionId.isNotEmpty) 'settingsSectionId': settingsSectionId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class HostedBackendRetryActionResult {
  const HostedBackendRetryActionResult({
    required this.accepted,
    required this.message,
    this.statusCode,
    this.metadata = const <String, Object?>{},
  });

  const HostedBackendRetryActionResult.accepted({
    String message = 'Hosted backend control-plane action accepted.',
    int? statusCode,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: true,
         message: message,
         statusCode: statusCode,
         metadata: metadata,
       );

  const HostedBackendRetryActionResult.rejected({
    String message = 'Hosted backend control-plane action rejected.',
    int? statusCode,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: false,
         message: message,
         statusCode: statusCode,
         metadata: metadata,
       );

  final bool accepted;
  final String message;
  final int? statusCode;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accepted': accepted,
      'message': message,
      if (statusCode != null) 'statusCode': statusCode,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class HostedBackendRetryActionExecutor {
  const HostedBackendRetryActionExecutor({required this.transport});

  final HostedControlPlaneRetryTransport transport;

  Future<HostedBackendRetryActionDispatch> execute(
    HostedBackendRetryEndpointPlan plan,
  ) async {
    try {
      final result = await transport(plan);
      return HostedBackendRetryActionDispatch(
        plan: plan,
        result: result,
        message: result.message,
      );
    } on Object catch (error) {
      return HostedBackendRetryActionDispatch(
        plan: plan,
        result: HostedBackendRetryActionResult.rejected(
          message: 'Hosted backend control-plane action failed: $error',
        ),
        message: 'Hosted backend control-plane action failed: $error',
      );
    }
  }
}

class HostedBackendRetryActionDispatch {
  const HostedBackendRetryActionDispatch({
    required this.plan,
    required this.result,
    required this.message,
  });

  final HostedBackendRetryEndpointPlan plan;
  final HostedBackendRetryActionResult result;
  final String message;

  bool get accepted => result.accepted;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accepted': accepted,
      'message': message,
      'plan': plan.toJson(),
      'result': result.toJson(),
    };
  }
}

class HostedBackendRetryRuntimeOutputBinding {
  const HostedBackendRetryRuntimeOutputBinding();

  Map<String, Object?> metadataFor(HostedBackendRetryActionDispatch dispatch) {
    return <String, Object?>{
      'producerId': 'service.remote-service.hosted-retry',
      'kind': 'hosted-backend-retry',
      'accepted': dispatch.accepted,
      'endpointKind': dispatch.plan.kind.wireValue,
      'method': dispatch.plan.method,
      'path': dispatch.plan.path,
      'requiresConfirmation': dispatch.plan.requiresConfirmation,
      if (dispatch.plan.settingsSectionId.isNotEmpty)
        'settingsSectionId': dispatch.plan.settingsSectionId,
      'result': dispatch.result.toJson(),
    };
  }
}
