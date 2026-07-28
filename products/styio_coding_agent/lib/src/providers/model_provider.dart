library;

import '../cancellation.dart';

enum ModelMessageRole { system, user, assistant, tool }

final class ModelMessage {
  const ModelMessage({required this.role, required this.text});

  const ModelMessage.user(String text)
    : this(role: ModelMessageRole.user, text: text);

  final ModelMessageRole role;
  final String text;
}

enum ModelRetrySafety { readOnly, idempotentMutation, unsafeMutation }

enum ModelEffectState { none, uncertain, committed }

enum ProviderFailureKind {
  authentication,
  rateLimited,
  transientUnavailable,
  invalidRequest,
  capabilityUnavailable,
  budgetExceeded,
  cancelled,
  timeout,
  protocol,
}

final class ProviderFailure implements Exception {
  const ProviderFailure({
    required this.kind,
    required this.message,
    required this.retryable,
    required this.effectState,
    this.retryAfter,
    this.usage,
  }) : assert(message.length <= 1024);

  final ProviderFailureKind kind;
  final String message;
  final bool retryable;
  final ModelEffectState effectState;
  final Duration? retryAfter;
  final ModelUsage? usage;

  @override
  String toString() => 'ProviderFailure(${kind.name}, $message)';
}

final class ModelProviderCapabilities {
  const ModelProviderCapabilities({
    required this.contextTokens,
    required this.outputTokens,
    required this.supportsTools,
    required this.maxConcurrency,
  }) : assert(contextTokens > 0),
       assert(outputTokens > 0),
       assert(maxConcurrency > 0);

  final int contextTokens;
  final int outputTokens;
  final bool supportsTools;
  final int maxConcurrency;
}

final class ProviderRequirements {
  const ProviderRequirements({
    this.requiresTools = false,
    this.minimumContextTokens = 0,
    this.minimumOutputTokens = 0,
  });

  final bool requiresTools;
  final int minimumContextTokens;
  final int minimumOutputTokens;

  bool accepts(ModelProviderCapabilities capabilities) =>
      (!requiresTools || capabilities.supportsTools) &&
      capabilities.contextTokens >= minimumContextTokens &&
      capabilities.outputTokens >= minimumOutputTokens;
}

final class ModelToolDefinition {
  const ModelToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.schemaVersion = 1,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final int schemaVersion;
}

final class ModelRequest {
  const ModelRequest({
    required this.requestId,
    required this.messages,
    this.tools = const <ModelToolDefinition>[],
    required this.estimatedContextTokens,
    required this.outputTokenLimit,
    required this.retrySafety,
    this.idempotencyKey,
    this.deadline,
  });

  final String requestId;
  final List<ModelMessage> messages;
  final List<ModelToolDefinition> tools;
  final int estimatedContextTokens;
  final int outputTokenLimit;
  final ModelRetrySafety retrySafety;
  final String? idempotencyKey;
  final DateTime? deadline;

  bool get permitsReplay =>
      retrySafety == ModelRetrySafety.readOnly ||
      (retrySafety == ModelRetrySafety.idempotentMutation &&
          idempotencyKey != null &&
          idempotencyKey!.trim().isNotEmpty);
}

enum ModelFinishReason { completed, toolCalls, length, cancelled }

sealed class ModelEvent {
  const ModelEvent();
}

final class ModelTextDelta extends ModelEvent {
  const ModelTextDelta(this.text);

  final String text;
}

final class ModelToolCallDelta extends ModelEvent {
  const ModelToolCallDelta({
    required this.id,
    this.name,
    this.argumentsFragment = '',
    this.done = false,
  });

  final String id;
  final String? name;
  final String argumentsFragment;
  final bool done;
}

final class ModelUsage {
  const ModelUsage({
    required this.inputTokens,
    required this.outputTokens,
    this.costMicros = 0,
  });

  static const zero = ModelUsage(inputTokens: 0, outputTokens: 0);

  final int inputTokens;
  final int outputTokens;
  final int costMicros;
}

final class ModelUsageEvent extends ModelEvent {
  const ModelUsageEvent(this.usage);

  final ModelUsage usage;
}

final class ModelCompleted extends ModelEvent {
  const ModelCompleted({this.finishReason = ModelFinishReason.completed});

  final ModelFinishReason finishReason;
}

final class ModelToolCall {
  ModelToolCall({
    required this.id,
    required this.name,
    required Map<String, Object?> arguments,
  }) : arguments = Map<String, Object?>.unmodifiable(arguments);

  final String id;
  final String name;
  final Map<String, Object?> arguments;
}

final class ModelExecutionReceipt {
  ModelExecutionReceipt({
    required this.requestId,
    required this.providerId,
    required this.text,
    required List<ModelToolCall> toolCalls,
    required this.usage,
    required this.finishReason,
  }) : toolCalls = List<ModelToolCall>.unmodifiable(toolCalls);

  final String requestId;
  final String providerId;
  final String text;
  final List<ModelToolCall> toolCalls;
  final ModelUsage usage;
  final ModelFinishReason finishReason;
}

abstract interface class ModelProvider {
  String get id;

  Future<ModelProviderCapabilities> capabilities();

  Stream<ModelEvent> stream(
    ModelRequest request,
    AgentCancellationToken cancellation,
  );
}
