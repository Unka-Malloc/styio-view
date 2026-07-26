import 'dart:convert';

const acpProtocolVersion = 1;
const styioAgentProtocolVersion = '$acpProtocolVersion';
const styioAgentProtocolMaxMessageBytes = 1024 * 1024;

abstract final class AcpMethod {
  static const initialize = 'initialize';
  static const sessionNew = 'session/new';
  static const sessionLoad = 'session/load';
  static const sessionPrompt = 'session/prompt';
  static const sessionCancel = 'session/cancel';
  static const sessionUpdate = 'session/update';
  static const sessionRequestPermission = 'session/request_permission';
  static const capabilitiesChanged = 'styio/capabilities_changed';
}

abstract final class AcpCapability {
  static const loadSession = 'loadSession';
}

abstract final class AcpStopReason {
  static const endTurn = 'end_turn';
  static const cancelled = 'cancelled';
  static const refusal = 'refusal';
}

final class AgentProtocolException implements Exception {
  const AgentProtocolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AgentProtocolException($code, $message)';
}

final class JsonRpcId {
  const JsonRpcId.string(String value) : this._(value);

  const JsonRpcId.integer(int value) : this._(value);

  const JsonRpcId._(this.value);

  factory JsonRpcId.fromJson(Object? value) {
    if (value is String) {
      _requireIdentifier(value, 'id');
      return JsonRpcId.string(value);
    }
    if (value is int) {
      return JsonRpcId.integer(value);
    }
    throw const AgentProtocolException(
      'malformed_message',
      'JSON-RPC id must be a non-empty string or integer',
    );
  }

  final Object value;

  Object toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonRpcId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value.toString();
}

sealed class JsonRpcMessage {
  const JsonRpcMessage();

  Map<String, Object?> toJson();
}

final class JsonRpcRequest extends JsonRpcMessage {
  JsonRpcRequest({
    required this.id,
    required this.method,
    this.params = const <String, Object?>{},
  }) {
    _requireIdentifier(method, 'method');
  }

  final JsonRpcId id;
  final String method;
  final Map<String, Object?> params;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id.toJson(),
    'method': method,
    if (params.isNotEmpty) 'params': params,
  };
}

final class JsonRpcNotification extends JsonRpcMessage {
  JsonRpcNotification({
    required this.method,
    this.params = const <String, Object?>{},
  }) {
    _requireIdentifier(method, 'method');
  }

  final String method;
  final Map<String, Object?> params;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': '2.0',
    'method': method,
    if (params.isNotEmpty) 'params': params,
  };
}

final class JsonRpcSuccessResponse extends JsonRpcMessage {
  const JsonRpcSuccessResponse({required this.id, required this.result});

  final JsonRpcId id;
  final Object? result;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id.toJson(),
    'result': result,
  };
}

final class JsonRpcError {
  const JsonRpcError({required this.code, required this.message, this.data});

  final int code;
  final String message;
  final Object? data;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };
}

final class JsonRpcErrorResponse extends JsonRpcMessage {
  const JsonRpcErrorResponse({required this.id, required this.error});

  final JsonRpcId id;
  final JsonRpcError error;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'jsonrpc': '2.0',
    'id': id.toJson(),
    'error': error.toJson(),
  };
}

abstract final class JsonRpcCodec {
  static String encode(
    JsonRpcMessage message, {
    int maxMessageBytes = styioAgentProtocolMaxMessageBytes,
  }) {
    final encoded = jsonEncode(message.toJson());
    _enforceByteLimit(encoded, maxMessageBytes);
    return encoded;
  }

  static JsonRpcMessage decode(
    String source, {
    int maxMessageBytes = styioAgentProtocolMaxMessageBytes,
  }) {
    _enforceByteLimit(source, maxMessageBytes);
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const AgentProtocolException(
        'malformed_message',
        'protocol message is not valid JSON',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const AgentProtocolException(
        'malformed_message',
        'protocol message must be a JSON object',
      );
    }
    if (decoded['jsonrpc'] != '2.0') {
      throw const AgentProtocolException(
        'malformed_message',
        'jsonrpc must equal 2.0',
      );
    }
    final hasId = decoded.containsKey('id');
    final hasMethod = decoded.containsKey('method');
    if (hasMethod) {
      final method = _requiredString(decoded, 'method');
      final params = _optionalObject(decoded, 'params');
      if (hasId) {
        return JsonRpcRequest(
          id: JsonRpcId.fromJson(decoded['id']),
          method: method,
          params: params,
        );
      }
      return JsonRpcNotification(method: method, params: params);
    }
    if (!hasId) {
      throw const AgentProtocolException(
        'malformed_message',
        'response must contain an id',
      );
    }
    final id = JsonRpcId.fromJson(decoded['id']);
    final hasResult = decoded.containsKey('result');
    final hasError = decoded.containsKey('error');
    if (hasResult == hasError) {
      throw const AgentProtocolException(
        'malformed_message',
        'response must contain exactly one of result or error',
      );
    }
    if (hasResult) {
      return JsonRpcSuccessResponse(id: id, result: decoded['result']);
    }
    final error = decoded['error'];
    if (error is! Map<String, Object?> ||
        error['code'] is! int ||
        error['message'] is! String ||
        (error['message'] as String).isEmpty ||
        (error['message'] as String).length > 1024) {
      throw const AgentProtocolException(
        'malformed_message',
        'error must contain a bounded integer code and message',
      );
    }
    return JsonRpcErrorResponse(
      id: id,
      error: JsonRpcError(
        code: error['code'] as int,
        message: error['message'] as String,
        data: error['data'],
      ),
    );
  }
}

final class AcpPromptResult {
  const AcpPromptResult({required this.stopReason});

  factory AcpPromptResult.fromJson(Object? value) {
    final json = _requiredObjectValue(value, 'prompt result');
    return AcpPromptResult(stopReason: _requiredString(json, 'stopReason'));
  }

  final String stopReason;
}

void validateStyioExtensionMethod(
  String method,
  Set<String> negotiatedExtensions,
) {
  if (!method.startsWith('styio/')) {
    throw const AgentProtocolException(
      'invalid_extension_namespace',
      'Styio extension methods must use the styio/ namespace',
    );
  }
  if (!negotiatedExtensions.contains(method)) {
    throw AgentProtocolException(
      'capability_revoked',
      'extension capability is not currently negotiated: $method',
    );
  }
}

Map<String, Object?> requireJsonObject(Object? value, String name) =>
    _requiredObjectValue(value, name);

String requireJsonString(Map<String, Object?> json, String key) =>
    _requiredString(json, key);

Map<String, Object?> _requiredObjectValue(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw AgentProtocolException(
      'malformed_message',
      '$name must be a JSON object',
    );
  }
  return value;
}

Map<String, Object?> _optionalObject(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    _requiredObjectValue(json[key], key),
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw AgentProtocolException(
      'malformed_message',
      '$key must be a non-empty string',
    );
  }
  return value;
}

void _requireIdentifier(String value, String name) {
  if (value.isEmpty || value.length > 256) {
    throw AgentProtocolException(
      'invalid_identifier',
      '$name must contain between 1 and 256 characters',
    );
  }
}

void _enforceByteLimit(String source, int maxMessageBytes) {
  if (maxMessageBytes <= 0 || utf8.encode(source).length > maxMessageBytes) {
    throw const AgentProtocolException(
      'message_too_large',
      'protocol message exceeds the configured byte limit',
    );
  }
}
