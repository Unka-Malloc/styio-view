library;

import 'dart:async';

import '../cancellation.dart';
import 'model_provider.dart';
import 'provider_stream_reducer.dart';
import 'usage_budget.dart';

abstract interface class ProviderClock {
  DateTime now();
}

final class SystemProviderClock implements ProviderClock {
  const SystemProviderClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

final class ProviderRoute {
  const ProviderRoute({required this.providerId, required this.capabilities});

  final String providerId;
  final ModelProviderCapabilities capabilities;
}

final class ProviderRouter {
  ProviderRouter({
    required List<ModelProvider> providers,
    required this.budget,
    ProviderClock clock = const SystemProviderClock(),
  }) : _providers = List<ModelProvider>.unmodifiable(providers),
       _clock = clock {
    if (_providers.isEmpty) {
      throw ArgumentError.value(providers, 'providers', 'must not be empty');
    }
    final ids = _providers.map((provider) => provider.id).toSet();
    if (ids.length != _providers.length || ids.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(
        providers,
        'providers',
        'provider ids must be unique and non-empty',
      );
    }
  }

  final List<ModelProvider> _providers;
  final ProviderClock _clock;
  final UsageBudget budget;
  final Map<String, int> _active = <String, int>{};
  final Map<String, DateTime> _unavailableUntil = <String, DateTime>{};

  Future<ProviderRoute> select(ProviderRequirements requirements) async {
    final now = _clock.now();
    for (final provider in _providers) {
      final unavailableUntil = _unavailableUntil[provider.id];
      if (unavailableUntil != null && now.isBefore(unavailableUntil)) {
        continue;
      }
      final capabilities = await provider.capabilities();
      if (!requirements.accepts(capabilities) ||
          (_active[provider.id] ?? 0) >= capabilities.maxConcurrency) {
        continue;
      }
      return ProviderRoute(providerId: provider.id, capabilities: capabilities);
    }
    throw const ProviderFailure(
      kind: ProviderFailureKind.capabilityUnavailable,
      message: 'no healthy provider satisfies the request capabilities',
      retryable: false,
      effectState: ModelEffectState.none,
    );
  }

  Future<ModelExecutionReceipt> generate(
    ModelRequest request, {
    required ProviderRequirements requirements,
    required AgentCancellationToken cancellation,
  }) async {
    final normalizedRequest = ModelRequest(
      requestId: request.requestId,
      messages: List<ModelMessage>.unmodifiable(request.messages),
      tools: List<ModelToolDefinition>.unmodifiable(
        request.tools.map(
          (tool) => ModelToolDefinition(
            name: tool.name,
            description: tool.description,
            inputSchema: Map<String, Object?>.unmodifiable(tool.inputSchema),
            schemaVersion: tool.schemaVersion,
          ),
        ),
      ),
      estimatedContextTokens: request.estimatedContextTokens,
      outputTokenLimit: request.outputTokenLimit,
      retrySafety: request.retrySafety,
      idempotencyKey: request.idempotencyKey,
      deadline: request.deadline,
    );
    budget.validateRequest(normalizedRequest);
    if (requirements.requiresTools && normalizedRequest.tools.isEmpty) {
      throw const ProviderFailure(
        kind: ProviderFailureKind.invalidRequest,
        message: 'a tool-capable request must include selected tool schemas',
        retryable: false,
        effectState: ModelEffectState.none,
      );
    }
    final effectiveRequirements = ProviderRequirements(
      requiresTools:
          requirements.requiresTools || normalizedRequest.tools.isNotEmpty,
      minimumContextTokens: requirements.minimumContextTokens,
      minimumOutputTokens: requirements.minimumOutputTokens,
    );
    _throwIfCancelledOrExpired(normalizedRequest, cancellation);

    ProviderFailure? lastFailure;
    var accruedUsage = ModelUsage.zero;
    final attempted = <String>{};
    while (attempted.length < _providers.length) {
      _throwIfCancelledOrExpired(normalizedRequest, cancellation);
      final ProviderRoute route;
      try {
        route = await _selectUnattempted(
          effectiveRequirements,
          attempted,
          normalizedRequest,
          cancellation,
        );
      } on ProviderFailure {
        if (lastFailure != null) {
          throw lastFailure;
        }
        rethrow;
      }
      final provider = _providers.firstWhere(
        (candidate) => candidate.id == route.providerId,
      );
      attempted.add(provider.id);
      _active[provider.id] = (_active[provider.id] ?? 0) + 1;
      try {
        final receipt = await _consume(
          provider,
          normalizedRequest,
          cancellation,
        );
        accruedUsage = _addUsage(accruedUsage, receipt.usage);
        budget.validateUsage(accruedUsage);
        return ModelExecutionReceipt(
          requestId: receipt.requestId,
          providerId: receipt.providerId,
          text: receipt.text,
          toolCalls: receipt.toolCalls,
          usage: accruedUsage,
          finishReason: receipt.finishReason,
        );
      } on ProviderFailure catch (failure) {
        lastFailure = failure;
        final failedUsage = failure.usage;
        if (failedUsage != null) {
          accruedUsage = _addUsage(accruedUsage, failedUsage);
          budget.validateUsage(accruedUsage);
        }
        _recordHealth(provider.id, failure);
        if (!_mayFallback(normalizedRequest, failure)) {
          rethrow;
        }
      } finally {
        final active = (_active[provider.id] ?? 1) - 1;
        if (active == 0) {
          _active.remove(provider.id);
        } else {
          _active[provider.id] = active;
        }
      }
    }
    throw lastFailure ??
        const ProviderFailure(
          kind: ProviderFailureKind.capabilityUnavailable,
          message: 'no provider route is available',
          retryable: false,
          effectState: ModelEffectState.none,
        );
  }

  Future<ProviderRoute> _selectUnattempted(
    ProviderRequirements requirements,
    Set<String> attempted,
    ModelRequest request,
    AgentCancellationToken cancellation,
  ) async {
    final now = _clock.now();
    for (final provider in _providers) {
      if (attempted.contains(provider.id)) {
        continue;
      }
      final unavailableUntil = _unavailableUntil[provider.id];
      if (unavailableUntil != null && now.isBefore(unavailableUntil)) {
        continue;
      }
      final capabilities = await _awaitCapabilities(
        provider,
        request,
        cancellation,
      );
      final requestFits =
          capabilities.contextTokens >= request.estimatedContextTokens &&
          capabilities.outputTokens >= request.outputTokenLimit;
      if (requestFits &&
          requirements.accepts(capabilities) &&
          (_active[provider.id] ?? 0) < capabilities.maxConcurrency) {
        return ProviderRoute(
          providerId: provider.id,
          capabilities: capabilities,
        );
      }
    }
    throw lastFailureForRoute(attempted);
  }

  ProviderFailure lastFailureForRoute(Set<String> attempted) => ProviderFailure(
    kind: ProviderFailureKind.capabilityUnavailable,
    message: attempted.isEmpty
        ? 'no healthy provider satisfies the request capabilities'
        : 'no compatible fallback provider is available',
    retryable: false,
    effectState: ModelEffectState.none,
  );

  Future<ModelExecutionReceipt> _consume(
    ModelProvider provider,
    ModelRequest request,
    AgentCancellationToken cancellation,
  ) async {
    final reducer = ProviderStreamReducer(
      maxBufferedOutputBytes: budget.maxBufferedOutputBytes,
      maxToolArgumentBytes: budget.maxToolArgumentBytes,
      maxBufferedToolBytes: budget.maxBufferedToolBytes,
      maxPendingToolCalls: budget.maxPendingToolCalls,
      maxToolCalls: budget.maxToolCalls,
    );
    final completer = Completer<ModelExecutionReceipt>();
    StreamSubscription<ModelEvent>? subscription;
    Timer? deadlineTimer;

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (completer.isCompleted) {
        return;
      }
      var failure = _normalizeFailure(
        error,
        fallbackEffectState: ModelEffectState.uncertain,
      );
      final observedUsage = reducer.observedUsage;
      if (failure.usage == null && observedUsage != null) {
        failure = ProviderFailure(
          kind: failure.kind,
          message: failure.message,
          retryable: failure.retryable,
          effectState: failure.effectState,
          retryAfter: failure.retryAfter,
          usage: observedUsage,
        );
      }
      completer.completeError(failure, stackTrace);
    }

    try {
      subscription = provider
          .stream(request, cancellation)
          .listen(
            (event) {
              if (completer.isCompleted) {
                return;
              }
              try {
                reducer.add(event);
              } on Object catch (error, stackTrace) {
                completeError(error, stackTrace);
              }
            },
            onError: completeError,
            onDone: () {
              if (completer.isCompleted) {
                return;
              }
              try {
                completer.complete(
                  reducer.finish(
                    requestId: request.requestId,
                    providerId: provider.id,
                  ),
                );
              } on Object catch (error, stackTrace) {
                completeError(error, stackTrace);
              }
            },
            cancelOnError: false,
          );
    } on Object catch (error, stackTrace) {
      completeError(error, stackTrace);
    }

    final cancellationSubscription = cancellation.cancellations.listen(
      (_) => completeError(
        const ProviderFailure(
          kind: ProviderFailureKind.cancelled,
          message: 'provider request was cancelled',
          retryable: false,
          effectState: ModelEffectState.uncertain,
        ),
      ),
    );
    if (cancellation.isCancelled) {
      completeError(
        const ProviderFailure(
          kind: ProviderFailureKind.cancelled,
          message: 'provider request was cancelled',
          retryable: false,
          effectState: ModelEffectState.uncertain,
        ),
      );
    }
    final deadline = request.deadline;
    if (deadline != null) {
      final remaining = deadline.difference(_clock.now());
      if (remaining <= Duration.zero) {
        completeError(_timeoutFailure());
      } else {
        deadlineTimer = Timer(
          remaining,
          () => completeError(_timeoutFailure()),
        );
      }
    }

    try {
      return await completer.future;
    } finally {
      deadlineTimer?.cancel();
      await cancellationSubscription.cancel();
      await subscription?.cancel();
    }
  }

  Future<ModelProviderCapabilities> _awaitCapabilities(
    ModelProvider provider,
    ModelRequest request,
    AgentCancellationToken cancellation,
  ) {
    final completer = Completer<ModelProviderCapabilities>();
    Timer? deadlineTimer;

    void completeError(Object error, [StackTrace? stackTrace]) {
      if (!completer.isCompleted) {
        completer.completeError(
          _normalizeFailure(error, fallbackEffectState: ModelEffectState.none),
          stackTrace,
        );
      }
    }

    Future<ModelProviderCapabilities>.sync(provider.capabilities).then((
      capabilities,
    ) {
      if (!completer.isCompleted) {
        completer.complete(capabilities);
      }
    }, onError: completeError);
    final cancellationSubscription = cancellation.cancellations.listen(
      (_) => completeError(
        const ProviderFailure(
          kind: ProviderFailureKind.cancelled,
          message: 'provider capability discovery was cancelled',
          retryable: false,
          effectState: ModelEffectState.none,
        ),
      ),
    );
    if (cancellation.isCancelled) {
      completeError(
        const ProviderFailure(
          kind: ProviderFailureKind.cancelled,
          message: 'provider capability discovery was cancelled',
          retryable: false,
          effectState: ModelEffectState.none,
        ),
      );
    }
    final deadline = request.deadline;
    if (deadline != null) {
      final remaining = deadline.difference(_clock.now());
      if (remaining <= Duration.zero) {
        completeError(_timeoutFailure());
      } else {
        deadlineTimer = Timer(
          remaining,
          () => completeError(_timeoutFailure()),
        );
      }
    }
    return completer.future.whenComplete(() async {
      deadlineTimer?.cancel();
      await cancellationSubscription.cancel();
    });
  }

  void _throwIfCancelledOrExpired(
    ModelRequest request,
    AgentCancellationToken cancellation,
  ) {
    if (cancellation.isCancelled) {
      throw const ProviderFailure(
        kind: ProviderFailureKind.cancelled,
        message: 'provider request was cancelled before start',
        retryable: false,
        effectState: ModelEffectState.none,
      );
    }
    final deadline = request.deadline;
    if (deadline != null && !deadline.isAfter(_clock.now())) {
      throw _timeoutFailure();
    }
  }

  bool _mayFallback(ModelRequest request, ProviderFailure failure) =>
      request.permitsReplay &&
      failure.retryable &&
      failure.effectState == ModelEffectState.none &&
      (failure.kind == ProviderFailureKind.rateLimited ||
          failure.kind == ProviderFailureKind.transientUnavailable);

  void _recordHealth(String providerId, ProviderFailure failure) {
    if (failure.kind == ProviderFailureKind.rateLimited ||
        failure.kind == ProviderFailureKind.transientUnavailable) {
      _unavailableUntil[providerId] = _clock.now().add(
        failure.retryAfter ?? const Duration(seconds: 1),
      );
    }
  }

  ProviderFailure _timeoutFailure() => const ProviderFailure(
    kind: ProviderFailureKind.timeout,
    message: 'provider request deadline expired',
    retryable: true,
    effectState: ModelEffectState.none,
  );

  ProviderFailure _normalizeFailure(
    Object error, {
    required ModelEffectState fallbackEffectState,
  }) {
    if (error is ProviderFailure) {
      final message = error.message.length <= 1024
          ? error.message
          : error.message.substring(0, 1024);
      return ProviderFailure(
        kind: error.kind,
        message: message,
        retryable: error.retryable,
        effectState: error.effectState,
        retryAfter: error.retryAfter,
        usage: error.usage,
      );
    }
    return ProviderFailure(
      kind: ProviderFailureKind.protocol,
      message: 'provider boundary returned an untyped failure',
      retryable: false,
      effectState: fallbackEffectState,
    );
  }

  ModelUsage _addUsage(ModelUsage left, ModelUsage right) => ModelUsage(
    inputTokens: left.inputTokens + right.inputTokens,
    outputTokens: left.outputTokens + right.outputTokens,
    costMicros: left.costMicros + right.costMicros,
  );
}
