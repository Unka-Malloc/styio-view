import 'agent_provider_adapter.dart';

typedef AgentProviderRetryOperation<T> = Future<T> Function(int attempt);
typedef AgentProviderRetryDelay = Future<void> Function(Duration delay);
typedef AgentProviderRetryClock = DateTime Function();
typedef AgentProviderResponseRetryTelemetrySink =
    void Function(
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
    implements AgentProviderAdapter, CancellableAgentProviderAdapter {
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
    telemetrySink?.call(execution);
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
  void cancelRequest(String requestId) {
    final cancellable = inner is CancellableAgentProviderAdapter
        ? inner as CancellableAgentProviderAdapter
        : null;
    cancellable?.cancelRequest(requestId);
  }
}

Future<void> _noDelay(Duration delay) async {}
