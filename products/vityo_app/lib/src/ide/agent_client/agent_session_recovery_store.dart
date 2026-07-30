import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'agent_client_models.dart';

final class AgentSessionRecoveryFailure implements Exception {
  const AgentSessionRecoveryFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AgentSessionRecoveryFailure($code, $message)';
}

abstract interface class AgentSessionRecoveryStorage {
  Future<String?> read();

  Future<void> write(String encoded);
}

final class MemoryAgentSessionRecoveryStorage
    implements AgentSessionRecoveryStorage {
  String? _encoded;

  @override
  Future<String?> read() async => _encoded;

  @override
  Future<void> write(String encoded) async {
    _encoded = encoded;
  }
}

final class AgentRecoveryCheckpoint {
  AgentRecoveryCheckpoint({
    required this.sessionId,
    required this.agentId,
    required this.processGeneration,
    required this.protocolVersion,
    required this.workspaceRevision,
    required this.status,
    required this.droppedUpdateCount,
    required List<AgentSessionUpdate> timeline,
  }) : timeline = List<AgentSessionUpdate>.unmodifiable(timeline) {
    if (sessionId.trim().isEmpty || agentId.trim().isEmpty) {
      throw ArgumentError('recovery identifiers must not be empty');
    }
    if (processGeneration < 0 ||
        protocolVersion < 0 ||
        workspaceRevision < 0 ||
        droppedUpdateCount < 0) {
      throw ArgumentError('recovery revisions and counts must not be negative');
    }
  }

  final String sessionId;
  final String agentId;
  final int processGeneration;
  final int protocolVersion;
  final int workspaceRevision;
  final String status;
  final int droppedUpdateCount;
  final List<AgentSessionUpdate> timeline;
}

final class AgentSessionRecoveryStore {
  AgentSessionRecoveryStore({
    required AgentSessionRecoveryStorage storage,
    required this.maxSessions,
    required this.maxTimelineEntriesPerSession,
    required this.maxEncodedBytes,
  }) : _storage = storage {
    if (maxSessions <= 0 ||
        maxTimelineEntriesPerSession <= 0 ||
        maxEncodedBytes <= 0) {
      throw ArgumentError('recovery budgets must be positive');
    }
  }

  static const _schemaVersion = 1;
  static const _sensitiveKeys = <String>{
    'authorization',
    'cookie',
    'token',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'password',
    'secret',
    'credential',
  };
  static final _bearerPattern = RegExp(
    r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
    caseSensitive: false,
  );

  final AgentSessionRecoveryStorage _storage;
  final int maxSessions;
  final int maxTimelineEntriesPerSession;
  final int maxEncodedBytes;
  Future<void> _lane = Future<void>.value();

  Future<void> save(AgentRecoveryCheckpoint checkpoint) => _serialize(() async {
    final existing = await _loadMap();
    existing.remove(checkpoint.sessionId);
    existing[checkpoint.sessionId] = _bounded(checkpoint);
    while (existing.length > maxSessions) {
      existing.remove(existing.keys.first);
    }
    final payload = <String, Object?>{
      'schemaVersion': _schemaVersion,
      'sessions': existing.values
          .map(_checkpointToJson)
          .toList(growable: false),
    };
    final canonicalPayload = jsonEncode(payload);
    final envelope = jsonEncode(<String, Object?>{
      'schemaVersion': _schemaVersion,
      'checksum': sha256.convert(utf8.encode(canonicalPayload)).toString(),
      'payload': payload,
    });
    if (utf8.encode(envelope).length > maxEncodedBytes) {
      throw const AgentSessionRecoveryFailure(
        'projection_limit_exceeded',
        'Recovery projection exceeds its encoded byte budget',
      );
    }
    await _storage.write(envelope);
  });

  Future<List<AgentRecoveryCheckpoint>> loadAll() async {
    final checkpoints = await _loadMap();
    return List<AgentRecoveryCheckpoint>.unmodifiable(checkpoints.values);
  }

  AgentRecoveryCheckpoint _bounded(AgentRecoveryCheckpoint checkpoint) {
    final omitted = checkpoint.timeline.length > maxTimelineEntriesPerSession
        ? checkpoint.timeline.length - maxTimelineEntriesPerSession
        : 0;
    final timeline = omitted == 0
        ? checkpoint.timeline
        : checkpoint.timeline.sublist(omitted);
    return AgentRecoveryCheckpoint(
      sessionId: checkpoint.sessionId,
      agentId: checkpoint.agentId,
      processGeneration: checkpoint.processGeneration,
      protocolVersion: checkpoint.protocolVersion,
      workspaceRevision: checkpoint.workspaceRevision,
      status: checkpoint.status,
      droppedUpdateCount: checkpoint.droppedUpdateCount + omitted,
      timeline: <AgentSessionUpdate>[
        for (final update in timeline)
          AgentSessionUpdate(
            sessionId: update.sessionId,
            kind: update.kind,
            text: _sanitize(update.text) as String?,
            payload: _sanitize(update.payload) as Map<String, Object?>,
          ),
      ],
    );
  }

  Future<Map<String, AgentRecoveryCheckpoint>> _loadMap() async {
    final encoded = await _storage.read();
    if (encoded == null || encoded.isEmpty) {
      return <String, AgentRecoveryCheckpoint>{};
    }
    if (utf8.encode(encoded).length > maxEncodedBytes) {
      throw const AgentSessionRecoveryFailure(
        'projection_limit_exceeded',
        'Recovery projection exceeds its encoded byte budget',
      );
    }
    try {
      final envelope = jsonDecode(encoded) as Map<String, Object?>;
      if (envelope['schemaVersion'] != _schemaVersion) {
        throw const FormatException('unsupported recovery schema');
      }
      final payload = envelope['payload'] as Map<String, Object?>;
      final canonicalPayload = jsonEncode(payload);
      final expected = sha256.convert(utf8.encode(canonicalPayload)).toString();
      if (envelope['checksum'] != expected) {
        throw const FormatException('recovery checksum mismatch');
      }
      if (payload['schemaVersion'] != _schemaVersion) {
        throw const FormatException('unsupported payload schema');
      }
      final sessions = payload['sessions'] as List<Object?>;
      final result = <String, AgentRecoveryCheckpoint>{};
      for (final raw in sessions) {
        final checkpoint = _checkpointFromJson(raw as Map<String, Object?>);
        if (result.containsKey(checkpoint.sessionId)) {
          throw const FormatException('duplicate recovery session');
        }
        result[checkpoint.sessionId] = checkpoint;
      }
      if (result.length > maxSessions) {
        throw const FormatException('recovery session budget exceeded');
      }
      return result;
    } on AgentSessionRecoveryFailure {
      rethrow;
    } on Object {
      throw const AgentSessionRecoveryFailure(
        'corrupted_projection',
        'Recovery projection is corrupted',
      );
    }
  }

  Map<String, Object?> _checkpointToJson(AgentRecoveryCheckpoint checkpoint) =>
      <String, Object?>{
        'sessionId': checkpoint.sessionId,
        'agentId': checkpoint.agentId,
        'processGeneration': checkpoint.processGeneration,
        'protocolVersion': checkpoint.protocolVersion,
        'workspaceRevision': checkpoint.workspaceRevision,
        'status': checkpoint.status,
        'droppedUpdateCount': checkpoint.droppedUpdateCount,
        'timeline': <Map<String, Object?>>[
          for (final update in checkpoint.timeline)
            <String, Object?>{
              'sessionId': update.sessionId,
              'kind': update.kind,
              if (update.text != null) 'text': update.text,
              'payload': update.payload,
            },
        ],
      };

  AgentRecoveryCheckpoint _checkpointFromJson(Map<String, Object?> json) {
    final timeline = json['timeline'] as List<Object?>;
    if (timeline.length > maxTimelineEntriesPerSession) {
      throw const FormatException('timeline budget exceeded');
    }
    return AgentRecoveryCheckpoint(
      sessionId: json['sessionId'] as String,
      agentId: json['agentId'] as String,
      processGeneration: json['processGeneration'] as int,
      protocolVersion: json['protocolVersion'] as int,
      workspaceRevision: json['workspaceRevision'] as int,
      status: json['status'] as String,
      droppedUpdateCount: json['droppedUpdateCount'] as int,
      timeline: <AgentSessionUpdate>[
        for (final raw in timeline)
          _updateFromJson(raw as Map<String, Object?>),
      ],
    );
  }

  AgentSessionUpdate _updateFromJson(Map<String, Object?> json) =>
      AgentSessionUpdate(
        sessionId: json['sessionId'] as String,
        kind: json['kind'] as String,
        text: json['text'] as String?,
        payload: Map<String, Object?>.of(
          json['payload'] as Map<String, Object?>,
        ),
      );

  Object? _sanitize(Object? value) {
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString():
              _sensitiveKeys.contains(entry.key.toString().toLowerCase())
              ? '[REDACTED]'
              : _sanitize(entry.value),
      };
    }
    if (value is Iterable<Object?>) {
      return value.map(_sanitize).toList(growable: false);
    }
    if (value is String) {
      return value.replaceAll(_bearerPattern, '[REDACTED]');
    }
    return value;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _lane = _lane.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
