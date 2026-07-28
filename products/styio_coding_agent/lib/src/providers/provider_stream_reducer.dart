library;

import 'dart:convert';

import 'model_provider.dart';

final class ProviderStreamReducer {
  ProviderStreamReducer({
    required this.maxBufferedOutputBytes,
    required this.maxToolArgumentBytes,
    this.maxBufferedToolBytes = 256 * 1024,
    this.maxPendingToolCalls = 16,
    this.maxToolCalls = 64,
  });

  final int maxBufferedOutputBytes;
  final int maxToolArgumentBytes;
  final int maxBufferedToolBytes;
  final int maxPendingToolCalls;
  final int maxToolCalls;
  final StringBuffer _text = StringBuffer();
  final Map<String, _ToolCallBuilder> _pending = <String, _ToolCallBuilder>{};
  final List<ModelToolCall> _completedTools = <ModelToolCall>[];
  var _textBytes = 0;
  var _toolBytes = 0;
  ModelUsage _usage = ModelUsage.zero;
  var _usageSeen = false;
  ModelFinishReason? _finishReason;

  ModelUsage? get observedUsage => _usageSeen ? _usage : null;

  void add(ModelEvent event) {
    if (_finishReason != null) {
      throw _protocol('provider emitted an event after completion');
    }
    switch (event) {
      case ModelTextDelta():
        final bytes = utf8.encode(event.text).length;
        if (_textBytes + bytes > maxBufferedOutputBytes) {
          throw _budget('provider text exceeds the bounded output buffer');
        }
        _textBytes += bytes;
        _text.write(event.text);
      case ModelToolCallDelta():
        _reduceToolCall(event);
      case ModelUsageEvent():
        if (_usageSeen) {
          throw _protocol('provider emitted more than one usage receipt');
        }
        _usageSeen = true;
        _usage = event.usage;
      case ModelCompleted():
        if (_pending.isNotEmpty) {
          throw _protocol('provider completed with a fragmented tool call');
        }
        if (!_usageSeen) {
          throw _protocol('provider completed without a usage receipt');
        }
        _finishReason = event.finishReason;
    }
  }

  ModelExecutionReceipt finish({
    required String requestId,
    required String providerId,
  }) {
    final finishReason = _finishReason;
    if (finishReason == null) {
      throw _protocol('provider stream ended without a completion event');
    }
    return ModelExecutionReceipt(
      requestId: requestId,
      providerId: providerId,
      text: _text.toString(),
      toolCalls: _completedTools,
      usage: _usage,
      finishReason: finishReason,
    );
  }

  void _reduceToolCall(ModelToolCallDelta event) {
    if (event.id.trim().isEmpty) {
      throw _protocol('tool call id must not be empty');
    }
    var builder = _pending[event.id];
    if (builder == null) {
      if (_pending.length + _completedTools.length >= maxToolCalls) {
        throw _budget('provider emitted too many tool calls');
      }
      if (_pending.length >= maxPendingToolCalls) {
        throw _budget('provider has too many fragmented tool calls');
      }
      builder = _ToolCallBuilder(event.id);
      _pending[event.id] = builder;
    }
    if (event.name case final name?) {
      if (builder.name != null && builder.name != name) {
        throw _protocol('tool call name changed during streaming');
      }
      builder.name = name;
    }
    final fragmentBytes = utf8.encode(event.argumentsFragment).length;
    if (builder.argumentBytes + fragmentBytes > maxToolArgumentBytes ||
        _toolBytes + fragmentBytes > maxBufferedToolBytes) {
      throw _budget('tool arguments exceed the bounded fragment buffer');
    }
    builder.argumentBytes += fragmentBytes;
    _toolBytes += fragmentBytes;
    builder.arguments.write(event.argumentsFragment);
    if (!event.done) {
      return;
    }
    final name = builder.name;
    if (name == null || name.trim().isEmpty) {
      throw _protocol('completed tool call has no name');
    }
    try {
      final decoded = jsonDecode(builder.arguments.toString());
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('arguments are not an object');
      }
      _completedTools.add(
        ModelToolCall(id: event.id, name: name, arguments: decoded),
      );
      _pending.remove(event.id);
    } on FormatException {
      throw _protocol('tool arguments are not valid JSON object data');
    }
  }

  ProviderFailure _budget(String message) => ProviderFailure(
    kind: ProviderFailureKind.budgetExceeded,
    message: message,
    retryable: false,
    effectState: ModelEffectState.none,
  );

  ProviderFailure _protocol(String message) => ProviderFailure(
    kind: ProviderFailureKind.protocol,
    message: message,
    retryable: false,
    effectState: ModelEffectState.none,
  );
}

final class _ToolCallBuilder {
  _ToolCallBuilder(this.id);

  final String id;
  String? name;
  final StringBuffer arguments = StringBuffer();
  int argumentBytes = 0;
}
