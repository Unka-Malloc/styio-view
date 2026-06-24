import 'agent_tool_call_dispatcher.dart';

const int defaultAgentToolResultOutputLimit = 12000;

enum AgentToolCallResultContextStatus { success, failure }

extension AgentToolCallResultContextStatusX
    on AgentToolCallResultContextStatus {
  String get wireValue => switch (this) {
    AgentToolCallResultContextStatus.success => 'success',
    AgentToolCallResultContextStatus.failure => 'failure',
  };
}

class AgentToolCallResultContext {
  const AgentToolCallResultContext({
    required this.callId,
    required this.toolId,
    required this.status,
    required this.message,
    required this.output,
    required this.createdAt,
    this.metadata = const <String, Object?>{},
    this.outputTruncated = false,
    this.outputOriginalLength = 0,
    this.outputLimit = defaultAgentToolResultOutputLimit,
    this.outputOmittedLength = 0,
  });

  factory AgentToolCallResultContext.fromDispatchResult(
    AgentToolCallDispatchResult result, {
    DateTime? createdAt,
    int outputLimit = defaultAgentToolResultOutputLimit,
  }) {
    final output = _truncateToolResultOutput(result.output, outputLimit);
    return AgentToolCallResultContext(
      callId: result.callId,
      toolId: result.toolId,
      status: result.success
          ? AgentToolCallResultContextStatus.success
          : AgentToolCallResultContextStatus.failure,
      message: result.message,
      output: output.text,
      outputTruncated: output.truncated,
      outputOriginalLength: output.originalLength,
      outputLimit: output.limit,
      outputOmittedLength: output.omittedLength,
      createdAt: createdAt ?? DateTime.now().toUtc(),
      metadata: _toolResultMetadataJson(result.metadata),
    );
  }

  final String callId;
  final String toolId;
  final AgentToolCallResultContextStatus status;
  final String message;
  final String output;
  final DateTime createdAt;
  final Map<String, Object?> metadata;
  final bool outputTruncated;
  final int outputOriginalLength;
  final int outputLimit;
  final int outputOmittedLength;

  bool get success => status == AgentToolCallResultContextStatus.success;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      'success': success,
      'message': message,
      'output': output,
      'outputTruncated': outputTruncated,
      if (outputTruncated) 'outputOriginalLength': outputOriginalLength,
      if (outputTruncated) 'outputLimit': outputLimit,
      if (outputTruncated) 'outputOmittedLength': outputOmittedLength,
      'createdAt': createdAt.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class _TruncatedToolResultOutput {
  const _TruncatedToolResultOutput({
    required this.text,
    required this.truncated,
    required this.originalLength,
    required this.limit,
    required this.omittedLength,
  });

  final String text;
  final bool truncated;
  final int originalLength;
  final int limit;
  final int omittedLength;
}

_TruncatedToolResultOutput _truncateToolResultOutput(
  String output,
  int outputLimit,
) {
  if (outputLimit <= 0 || output.length <= outputLimit) {
    return _TruncatedToolResultOutput(
      text: output,
      truncated: false,
      originalLength: output.length,
      limit: outputLimit,
      omittedLength: 0,
    );
  }
  final omittedLength = output.length - outputLimit;
  return _TruncatedToolResultOutput(
    text:
        '${output.substring(0, outputLimit)}\n[tool output truncated: $omittedLength char(s) omitted]',
    truncated: true,
    originalLength: output.length,
    limit: outputLimit,
    omittedLength: omittedLength,
  );
}

Map<String, Object?> _toolResultMetadataJson(Map<String, Object?> metadata) {
  final result = <String, Object?>{};
  for (final entry in metadata.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) {
      continue;
    }
    final value = _toolResultMetadataValueJson(entry.value);
    if (value != _unsupportedToolResultMetadataValue) {
      result[key] = value;
    }
  }
  return result;
}

const Object _unsupportedToolResultMetadataValue = Object();

Object? _toolResultMetadataValueJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    final values = <Object?>[];
    for (final item in value) {
      final itemJson = _toolResultMetadataValueJson(item);
      if (itemJson == _unsupportedToolResultMetadataValue) {
        return _unsupportedToolResultMetadataValue;
      }
      values.add(itemJson);
    }
    return values;
  }
  if (value is Map) {
    final values = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String || key.trim().isEmpty) {
        return _unsupportedToolResultMetadataValue;
      }
      final itemJson = _toolResultMetadataValueJson(entry.value);
      if (itemJson == _unsupportedToolResultMetadataValue) {
        return _unsupportedToolResultMetadataValue;
      }
      values[key.trim()] = itemJson;
    }
    return values;
  }
  return _unsupportedToolResultMetadataValue;
}
