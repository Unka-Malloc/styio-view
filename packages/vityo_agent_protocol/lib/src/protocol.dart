import 'dart:convert';

const acpProtocolVersion = 1;
const vityoAgentProtocolVersion = '$acpProtocolVersion';
const vityoAgentProtocolMaxMessageBytes = 1024 * 1024;
const vityoAcpExtensionPrefix = '_vityo.dev/';
const vityoAcpMetadataKey = 'vityo.dev';

abstract final class AcpMethod {
  static const initialize = 'initialize';
  static const sessionNew = 'session/new';
  static const sessionLoad = 'session/load';
  static const sessionPrompt = 'session/prompt';
  static const sessionCancel = 'session/cancel';
  static const sessionUpdate = 'session/update';
  static const sessionRequestPermission = 'session/request_permission';
  static const capabilitiesChanged =
      '${vityoAcpExtensionPrefix}capabilities_changed';
}

abstract final class AcpCapability {
  static const loadSession = 'loadSession';
}

abstract final class VityoCapability {
  static const workspaceChangeProposal =
      '${vityoAcpExtensionPrefix}workspace-change-proposal';
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
    Map<String, Object?> params = const <String, Object?>{},
  }) : params = _freezeJsonObject(params, 'request params') {
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
    Map<String, Object?> params = const <String, Object?>{},
  }) : params = _freezeJsonObject(params, 'notification params') {
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
  JsonRpcSuccessResponse({required this.id, required Object? result})
    : result = _freezeJsonValue(result, 'response result');

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
    int maxMessageBytes = vityoAgentProtocolMaxMessageBytes,
  }) {
    _validateOutgoingMessage(message);
    final encoded = jsonEncode(message.toJson());
    _enforceByteLimit(encoded, maxMessageBytes);
    return encoded;
  }

  static JsonRpcMessage decode(
    String source, {
    int maxMessageBytes = vityoAgentProtocolMaxMessageBytes,
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
    return AcpPromptResult(
      stopReason: _requiredBoundedString(json, 'stopReason', 256),
    );
  }

  final String stopReason;
}

final class VityoTextChange {
  VityoTextChange({
    required this.start,
    required this.end,
    required this.replacement,
  }) {
    if (start < 0 || end < start) {
      throw ArgumentError('Text change range is invalid.');
    }
  }

  factory VityoTextChange.fromJson(Object? value) {
    final json = _requiredObjectValue(value, 'text change');
    final start = _requiredNonNegativeInt(json, 'start');
    final end = _requiredNonNegativeInt(json, 'end');
    final replacement = _requiredStringValue(json, 'replacement');
    if (end < start) {
      throw const AgentProtocolException(
        'malformed_message',
        'text change end must not precede start',
      );
    }
    return VityoTextChange(start: start, end: end, replacement: replacement);
  }

  final int start;
  final int end;
  final String replacement;

  Map<String, Object?> toJson() => <String, Object?>{
    'start': start,
    'end': end,
    'replacement': replacement,
  };
}

final class VityoResourceChange {
  VityoResourceChange({
    required this.resourceId,
    required this.baseDocumentRevision,
    required Iterable<VityoTextChange> edits,
  }) : edits = List<VityoTextChange>.unmodifiable(edits) {
    if (resourceId.isEmpty ||
        resourceId.length > 4096 ||
        baseDocumentRevision < 0 ||
        this.edits.isEmpty) {
      throw ArgumentError('Resource change is invalid.');
    }
  }

  factory VityoResourceChange.fromJson(Object? value) {
    final json = _requiredObjectValue(value, 'resource change');
    final resourceId = _requiredBoundedString(json, 'resourceId', 4096);
    final baseDocumentRevision = _requiredNonNegativeInt(
      json,
      'baseDocumentRevision',
    );
    final rawEdits = _requiredList(json, 'edits');
    if (rawEdits.isEmpty || rawEdits.length > 500) {
      throw const AgentProtocolException(
        'message_too_large',
        'resource change edits must be non-empty and bounded',
      );
    }
    return VityoResourceChange(
      resourceId: resourceId,
      baseDocumentRevision: baseDocumentRevision,
      edits: rawEdits.map(VityoTextChange.fromJson),
    );
  }

  final String resourceId;
  final int baseDocumentRevision;
  final List<VityoTextChange> edits;

  Map<String, Object?> toJson() => <String, Object?>{
    'resourceId': resourceId,
    'baseDocumentRevision': baseDocumentRevision,
    'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
  };
}

/// A protocol-owned, revision-bound proposal. The IDE remains the sole owner
/// of preview, commit, rejection, and rollback.
final class VityoWorkspaceChangeProposal {
  VityoWorkspaceChangeProposal({
    required this.id,
    required this.baseWorkspaceRevision,
    required Iterable<VityoResourceChange> resources,
  }) : resources = List<VityoResourceChange>.unmodifiable(resources) {
    _validate();
  }

  factory VityoWorkspaceChangeProposal.fromJson(Object? value) {
    final json = _requiredObjectValue(value, 'workspace change proposal');
    final rawResources = _requiredList(json, 'resources');
    if (rawResources.isEmpty || rawResources.length > 64) {
      throw const AgentProtocolException(
        'message_too_large',
        'workspace change proposal resources must be non-empty and bounded',
      );
    }
    final resources = rawResources
        .map(VityoResourceChange.fromJson)
        .toList(growable: false);
    final editCount = resources.fold<int>(
      0,
      (total, resource) => total + resource.edits.length,
    );
    final replacementCharacterCount = resources.fold<int>(
      0,
      (total, resource) =>
          total +
          resource.edits.fold<int>(
            0,
            (subtotal, edit) => subtotal + edit.replacement.length,
          ),
    );
    if (resources.isEmpty ||
        resources.map((resource) => resource.resourceId).toSet().length !=
            resources.length) {
      throw const AgentProtocolException(
        'malformed_message',
        'workspace change proposal resources are invalid',
      );
    }
    if (resources.length > 64 ||
        editCount > 500 ||
        replacementCharacterCount > 200000) {
      throw const AgentProtocolException(
        'message_too_large',
        'workspace change proposal exceeds its bounded limits',
      );
    }
    final proposal = VityoWorkspaceChangeProposal(
      id: _requiredBoundedString(json, 'id', 256),
      baseWorkspaceRevision: _requiredNonNegativeInt(
        json,
        'baseWorkspaceRevision',
      ),
      resources: resources,
    );
    return proposal;
  }

  factory VityoWorkspaceChangeProposal.fromNotificationParams(
    Map<String, Object?> params,
  ) => VityoWorkspaceChangeProposal.fromJson(params['proposal']);

  final String id;
  final int baseWorkspaceRevision;
  final List<VityoResourceChange> resources;

  int get editCount => resources.fold<int>(
    0,
    (total, resource) => total + resource.edits.length,
  );

  int get replacementCharacterCount => resources.fold<int>(
    0,
    (total, resource) =>
        total +
        resource.edits.fold<int>(
          0,
          (subtotal, edit) => subtotal + edit.replacement.length,
        ),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'baseWorkspaceRevision': baseWorkspaceRevision,
    'resources': resources
        .map((resource) => resource.toJson())
        .toList(growable: false),
  };

  Map<String, Object?> toNotificationParamsJson(String sessionId) =>
      <String, Object?>{'sessionId': sessionId, 'proposal': toJson()};

  void _validate() {
    if (id.isEmpty ||
        id.length > 256 ||
        baseWorkspaceRevision < 0 ||
        resources.isEmpty ||
        resources.length > 64 ||
        editCount > 500 ||
        replacementCharacterCount > 200000 ||
        resources.map((resource) => resource.resourceId).toSet().length !=
            resources.length) {
      throw ArgumentError('Workspace change proposal is invalid.');
    }
  }
}

void validateVityoExtensionMethod(
  String method,
  Set<String> negotiatedExtensions,
) {
  if (!method.startsWith(vityoAcpExtensionPrefix) ||
      method.length <= vityoAcpExtensionPrefix.length ||
      method.length > 256) {
    throw const AgentProtocolException(
      'invalid_extension_namespace',
      'Vityo extension methods must use the reserved _vityo.dev/ namespace',
    );
  }
  if (!negotiatedExtensions.contains(method)) {
    throw AgentProtocolException(
      'capability_revoked',
      'extension capability is not currently negotiated: $method',
    );
  }
}

Map<String, Object?> _freezeJsonObject(
  Map<String, Object?> value,
  String label,
) {
  final frozen = _freezeJsonValue(value, label);
  if (frozen is! Map<String, Object?>) {
    throw AgentProtocolException(
      'malformed_message',
      '$label must be an object',
    );
  }
  return frozen;
}

Object? _freezeJsonValue(Object? value, String label, [int depth = 0]) {
  if (depth > 64) {
    throw AgentProtocolException(
      'message_too_large',
      '$label exceeds the maximum nesting depth',
    );
  }
  if (value == null || value is bool || value is num || value is String) {
    return value;
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(
      value.map((item) => _freezeJsonValue(item, label, depth + 1)),
    );
  }
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries)
        entry.key: _freezeJsonValue(entry.value, label, depth + 1),
    });
  }
  throw AgentProtocolException(
    'malformed_message',
    '$label contains a non-JSON value',
  );
}

void _validateOutgoingMessage(JsonRpcMessage message) {
  switch (message) {
    case JsonRpcRequest():
      _validateJsonRpcId(message.id);
    case JsonRpcNotification():
      break;
    case JsonRpcSuccessResponse():
      _validateJsonRpcId(message.id);
    case JsonRpcErrorResponse():
      _validateJsonRpcId(message.id);
      if (message.error.message.isEmpty ||
          message.error.message.length > 1024) {
        throw const AgentProtocolException(
          'malformed_message',
          'error message must be non-empty and bounded',
        );
      }
  }
}

void _validateJsonRpcId(JsonRpcId id) {
  final value = id.value;
  if (value is String) {
    _requireIdentifier(value, 'id');
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

String _requiredStringValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw AgentProtocolException('malformed_message', '$key must be a string');
  }
  return value;
}

String _requiredBoundedString(
  Map<String, Object?> json,
  String key,
  int maxLength,
) {
  final value = _requiredString(json, key);
  if (value.length > maxLength) {
    throw AgentProtocolException(
      'malformed_message',
      '$key exceeds its character limit',
    );
  }
  return value;
}

int _requiredNonNegativeInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw AgentProtocolException(
      'malformed_message',
      '$key must be a non-negative integer',
    );
  }
  return value;
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw AgentProtocolException('malformed_message', '$key must be an array');
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
