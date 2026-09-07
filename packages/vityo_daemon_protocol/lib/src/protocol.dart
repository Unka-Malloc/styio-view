import 'dart:convert';
import 'dart:typed_data';

const vityodProtocolVersion = 1;
const vityodFrameHeaderBytes = 24;
const vityodMaxControlPayloadBytes = 1024 * 1024;
const vityodMaxBinaryPayloadBytes = 4 * 1024 * 1024;
const vityodCoreCapabilities = <String>[
  'handshake.negotiate',
  'health.get',
  'event.resume',
  'workspace.snapshot',
  'workspace.open',
  'workspace.files.list',
  'workspace.watch',
  'snapshot.get',
  'buffer.delta',
  'fs.scope.open',
  'fs.scope.close',
  'fs.stat',
  'fs.read',
  'fs.write',
  'fs.createDirectory',
  'fs.delete',
  'fs.copy',
  'fs.move',
  'fs.list',
  'fs.isExecutable',
  'fs.setExecutable',
  'fs.watch.start',
  'fs.watch.poll',
  'fs.watch.stop',
  'cancellation.cancel',
  'pty.start',
  'pty.resize',
  'pty.close',
  'task.start',
  'task.cancel',
  'task.output',
  'task.close',
  'git.start',
  'git.output',
  'git.close',
  'styio.request',
  'pafio.request',
  'dap.start',
  'dap.request',
  'dap.stop',
  'lsp.start',
  'lsp.request',
  'lsp.stop',
  'agent.connection.open',
  'agent.connection.close',
  'agent.session.new',
  'agent.session.load',
  'agent.session.prompt',
  'agent.session.poll',
  'agent.acp.session.cancel',
  'agent.acp.permission.decide',
  'agent.extension.invoke',
  'workspace.read',
  'workspace.search',
  'workspace.transaction.commit',
  'workspace.delete',
  'agent.session.start',
  'agent.session.resume',
  'agent.session.cancel',
  'agent.permission.request',
  'agent.permission.decide',
  'agent.mcp.invoke',
];

const vityodMethodCatalog = <String>{
  'handshake.negotiate',
  'health.get',
  'event.resume',
  'event.ack',
  'snapshot.get',
  'workspace.open',
  'workspace.read',
  'workspace.search',
  'workspace.transaction.commit',
  'workspace.delete',
  'workspace.watch',
  'workspace.files.list',
  'fs.scope.open',
  'fs.scope.close',
  'fs.stat',
  'fs.read',
  'fs.write',
  'fs.createDirectory',
  'fs.delete',
  'fs.copy',
  'fs.move',
  'fs.list',
  'fs.isExecutable',
  'fs.setExecutable',
  'fs.watch.start',
  'fs.watch.poll',
  'fs.watch.stop',
  'buffer.delta',
  'buffer.ack',
  'git.start',
  'git.output',
  'git.close',
  'styio.request',
  'pafio.request',
  'lsp.start',
  'lsp.request',
  'lsp.stop',
  'dap.start',
  'dap.request',
  'dap.stop',
  'task.start',
  'task.cancel',
  'task.output',
  'task.close',
  'pty.start',
  'pty.write',
  'pty.resize',
  'pty.close',
  'agent.session.start',
  'agent.session.resume',
  'agent.session.cancel',
  'agent.permission.decide',
  'agent.permission.request',
  'agent.mcp.invoke',
  'agent.connection.open',
  'agent.connection.close',
  'agent.session.new',
  'agent.session.load',
  'agent.session.prompt',
  'agent.session.poll',
  'agent.acp.session.cancel',
  'agent.acp.permission.decide',
  'agent.extension.invoke',
  'cancellation.cancel',
  'credit.grant',
  'upgrade.prepare',
};

final class VityodProtocolException implements Exception {
  const VityodProtocolException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'VityodProtocolException($code, $message)';
}

enum VityodFrameKind {
  control(1),
  pty(2),
  credit(3);

  const VityodFrameKind(this.wireValue);

  final int wireValue;

  static VityodFrameKind fromWire(int value) {
    for (final kind in values) {
      if (kind.wireValue == value) return kind;
    }
    throw VityodProtocolException(
      'unknown_frame_kind',
      'Unknown frame kind $value',
    );
  }
}

final class VityodFrameHeader {
  const VityodFrameHeader({
    required this.kind,
    required this.streamId,
    required this.sequence,
    required this.payloadLength,
    this.flags = 0,
    this.version = vityodProtocolVersion,
  });

  final int version;
  final VityodFrameKind kind;
  final int flags;
  final int streamId;
  final int sequence;
  final int payloadLength;

  Uint8List encode() {
    _validate();
    final bytes = Uint8List(vityodFrameHeaderBytes);
    final data = ByteData.sublistView(bytes);
    data.setUint16(0, version, Endian.big);
    data.setUint8(2, kind.wireValue);
    data.setUint8(3, flags);
    data.setUint32(4, streamId, Endian.big);
    data.setUint64(8, sequence, Endian.big);
    data.setUint32(16, payloadLength, Endian.big);
    data.setUint32(20, 0, Endian.big);
    return bytes;
  }

  static VityodFrameHeader decode(List<int> encoded) {
    if (encoded.length != vityodFrameHeaderBytes) {
      throw const VityodProtocolException(
        'invalid_frame_header',
        'Frame header must be exactly 24 bytes',
      );
    }
    final data = ByteData.sublistView(Uint8List.fromList(encoded));
    final header = VityodFrameHeader(
      version: data.getUint16(0, Endian.big),
      kind: VityodFrameKind.fromWire(data.getUint8(2)),
      flags: data.getUint8(3),
      streamId: data.getUint32(4, Endian.big),
      sequence: data.getUint64(8, Endian.big),
      payloadLength: data.getUint32(16, Endian.big),
    );
    header._validate();
    return header;
  }

  void _validate() {
    if (version != vityodProtocolVersion) {
      throw VityodProtocolException(
        'unsupported_protocol_version',
        'Unsupported protocol version $version',
      );
    }
    if (streamId < 0 || sequence < 0 || payloadLength < 0) {
      throw const VityodProtocolException(
        'invalid_frame_header',
        'Frame identifiers and lengths must be non-negative',
      );
    }
    final maximum = kind == VityodFrameKind.control
        ? vityodMaxControlPayloadBytes
        : vityodMaxBinaryPayloadBytes;
    if (payloadLength > maximum) {
      throw VityodProtocolException(
        'frame_too_large',
        'Payload length $payloadLength exceeds $maximum',
      );
    }
  }
}

final class VityodBinaryFrame {
  VityodBinaryFrame({
    required this.kind,
    required this.streamId,
    required this.sequence,
    required List<int> payload,
    this.flags = 0,
  }) : payload = Uint8List.fromList(payload) {
    if (kind == VityodFrameKind.control) {
      throw ArgumentError.value(
        kind,
        'kind',
        'binary frames cannot use the control kind',
      );
    }
    VityodFrameHeader(
      kind: kind,
      streamId: streamId,
      sequence: sequence,
      payloadLength: this.payload.length,
      flags: flags,
    ).encode();
  }

  final VityodFrameKind kind;
  final int flags;
  final int streamId;
  final int sequence;
  final Uint8List payload;
}

final class VityodControlEnvelope {
  VityodControlEnvelope({
    required this.method,
    required this.clientInstanceId,
    required this.idempotencyKey,
    required this.deadlineUnixMillis,
    this.requestId,
    this.workspaceId,
    this.workspaceRevision,
    this.cancellationId,
    this.params = const <String, Object?>{},
    this.capabilities = const <String>[],
    this.unknownFields = const <String, Object?>{},
    this.protocolVersion = vityodProtocolVersion,
  });

  final int protocolVersion;
  final String method;
  final String? requestId;
  final String clientInstanceId;
  final String idempotencyKey;
  final String? workspaceId;
  final int? workspaceRevision;
  final int deadlineUnixMillis;
  final String? cancellationId;
  final Map<String, Object?> params;
  final List<String> capabilities;
  final Map<String, Object?> unknownFields;

  Map<String, Object?> toJson() => <String, Object?>{
    ...unknownFields,
    'protocolVersion': protocolVersion,
    'method': method,
    if (requestId != null) 'requestId': requestId,
    'clientInstanceId': clientInstanceId,
    'idempotencyKey': idempotencyKey,
    if (workspaceId != null) 'workspaceId': workspaceId,
    if (workspaceRevision != null) 'workspaceRevision': workspaceRevision,
    'deadlineUnixMillis': deadlineUnixMillis,
    if (cancellationId != null) 'cancellationId': cancellationId,
    'params': params,
    'capabilities': capabilities,
  };

  static VityodControlEnvelope fromJson(Map<String, Object?> json) {
    const known = <String>{
      'protocolVersion',
      'method',
      'requestId',
      'clientInstanceId',
      'idempotencyKey',
      'workspaceId',
      'workspaceRevision',
      'deadlineUnixMillis',
      'cancellationId',
      'params',
      'capabilities',
    };
    final version = _requiredInt(json, 'protocolVersion');
    if (version != vityodProtocolVersion) {
      throw VityodProtocolException(
        'unsupported_protocol_version',
        'Unsupported protocol version $version',
      );
    }
    final params = json['params'];
    final capabilities = json['capabilities'];
    if (params is! Map<String, Object?>) {
      throw const VityodProtocolException(
        'invalid_envelope',
        'params must be an object',
      );
    }
    if (capabilities is! List ||
        capabilities.any((value) => value is! String)) {
      throw const VityodProtocolException(
        'invalid_envelope',
        'capabilities must contain only strings',
      );
    }
    return VityodControlEnvelope(
      protocolVersion: version,
      method: _requiredString(json, 'method'),
      requestId: _optionalString(json, 'requestId'),
      clientInstanceId: _requiredString(json, 'clientInstanceId'),
      idempotencyKey: _requiredString(json, 'idempotencyKey'),
      workspaceId: _optionalString(json, 'workspaceId'),
      workspaceRevision: _optionalInt(json, 'workspaceRevision'),
      deadlineUnixMillis: _requiredInt(json, 'deadlineUnixMillis'),
      cancellationId: _optionalString(json, 'cancellationId'),
      params: Map<String, Object?>.unmodifiable(params),
      capabilities: List<String>.unmodifiable(capabilities.cast<String>()),
      unknownFields: Map<String, Object?>.unmodifiable(
        Map<String, Object?>.fromEntries(
          json.entries.where((entry) => !known.contains(entry.key)),
        ),
      ),
    );
  }
}

abstract final class VityodControlCodec {
  static Uint8List encode(VityodControlEnvelope envelope) {
    final bytes = utf8.encode(jsonEncode(envelope.toJson()));
    if (bytes.length > vityodMaxControlPayloadBytes) {
      throw const VityodProtocolException(
        'frame_too_large',
        'Control payload exceeds limit',
      );
    }
    return Uint8List.fromList(bytes);
  }

  static VityodControlEnvelope decode(List<int> bytes) {
    if (bytes.length > vityodMaxControlPayloadBytes) {
      throw const VityodProtocolException(
        'frame_too_large',
        'Control payload exceeds limit',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    } on FormatException catch (error) {
      throw VityodProtocolException('invalid_json', error.message);
    }
    if (decoded is! Map<String, Object?>) {
      throw const VityodProtocolException(
        'invalid_envelope',
        'Control payload must be an object',
      );
    }
    return VityodControlEnvelope.fromJson(decoded);
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw VityodProtocolException(
    'invalid_envelope',
    '$key must be a non-empty string',
  );
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw VityodProtocolException('invalid_envelope', '$key must be a string');
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw VityodProtocolException('invalid_envelope', '$key must be an integer');
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw VityodProtocolException('invalid_envelope', '$key must be an integer');
}
