library;

import 'dart:convert';

import 'model_provider.dart';

final class UsageBudget {
  const UsageBudget({
    required this.maxContextTokens,
    required this.maxOutputTokens,
    required this.maxTotalTokens,
    required this.maxCostMicros,
    this.maxBufferedOutputBytes = 256 * 1024,
    this.maxToolArgumentBytes = 64 * 1024,
    this.maxBufferedToolBytes = 256 * 1024,
    this.maxPendingToolCalls = 16,
    this.maxToolCalls = 64,
    this.maxToolSchemaBytes = 256 * 1024,
  }) : assert(maxContextTokens > 0),
       assert(maxOutputTokens > 0),
       assert(maxTotalTokens > 0),
       assert(maxCostMicros >= 0),
       assert(maxBufferedOutputBytes > 0),
       assert(maxToolArgumentBytes > 0),
       assert(maxBufferedToolBytes > 0),
       assert(maxPendingToolCalls > 0),
       assert(maxToolCalls > 0),
       assert(maxToolSchemaBytes > 0);

  final int maxContextTokens;
  final int maxOutputTokens;
  final int maxTotalTokens;
  final int maxCostMicros;
  final int maxBufferedOutputBytes;
  final int maxToolArgumentBytes;
  final int maxBufferedToolBytes;
  final int maxPendingToolCalls;
  final int maxToolCalls;
  final int maxToolSchemaBytes;

  void validateRequest(ModelRequest request) {
    if (request.requestId.trim().isEmpty ||
        request.messages.isEmpty ||
        request.estimatedContextTokens < 0 ||
        request.outputTokenLimit <= 0) {
      throw const ProviderFailure(
        kind: ProviderFailureKind.invalidRequest,
        message: 'request shape or budget is invalid',
        retryable: false,
        effectState: ModelEffectState.none,
      );
    }
    final toolNames = <String>{};
    var toolSchemaBytes = 0;
    for (final tool in request.tools) {
      if (tool.name.trim().isEmpty ||
          tool.description.trim().isEmpty ||
          tool.description.length > 4096 ||
          tool.schemaVersion <= 0 ||
          !toolNames.add(tool.name)) {
        throw const ProviderFailure(
          kind: ProviderFailureKind.invalidRequest,
          message: 'selected tool definitions are invalid or duplicated',
          retryable: false,
          effectState: ModelEffectState.none,
        );
      }
      try {
        toolSchemaBytes += utf8.encode(jsonEncode(tool.inputSchema)).length;
      } on JsonUnsupportedObjectError {
        throw const ProviderFailure(
          kind: ProviderFailureKind.invalidRequest,
          message: 'selected tool schema is not JSON serializable',
          retryable: false,
          effectState: ModelEffectState.none,
        );
      }
    }
    if (request.tools.length > maxToolCalls ||
        toolSchemaBytes > maxToolSchemaBytes) {
      throw const ProviderFailure(
        kind: ProviderFailureKind.budgetExceeded,
        message: 'selected tool schemas exceed the configured budget',
        retryable: false,
        effectState: ModelEffectState.none,
      );
    }
    if (request.estimatedContextTokens > maxContextTokens ||
        request.outputTokenLimit > maxOutputTokens ||
        request.estimatedContextTokens + request.outputTokenLimit >
            maxTotalTokens) {
      throw const ProviderFailure(
        kind: ProviderFailureKind.budgetExceeded,
        message: 'request exceeds the configured token budget',
        retryable: false,
        effectState: ModelEffectState.none,
      );
    }
  }

  void validateUsage(ModelUsage usage) {
    if (usage.inputTokens < 0 ||
        usage.outputTokens < 0 ||
        usage.costMicros < 0 ||
        usage.inputTokens > maxContextTokens ||
        usage.outputTokens > maxOutputTokens ||
        usage.inputTokens + usage.outputTokens > maxTotalTokens ||
        usage.costMicros > maxCostMicros) {
      throw const ProviderFailure(
        kind: ProviderFailureKind.budgetExceeded,
        message: 'provider usage exceeds the configured budget',
        retryable: false,
        effectState: ModelEffectState.none,
      );
    }
  }
}
