library;

import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

enum SessionEventKind {
  goalRecorded,
  turnRecorded,
  planRecorded,
  stepRecorded,
  toolCallRecorded,
  permissionRecorded,
  changeCommitted,
  validationRecorded,
  budgetRecorded,
  terminalRecorded,
}

final class SessionCorrelation {
  const SessionCorrelation({
    required this.taskId,
    required this.sessionId,
    this.turnId,
    this.planId,
    this.stepId,
    this.operationId,
  });

  final String taskId;
  final String sessionId;
  final String? turnId;
  final String? planId;
  final String? stepId;
  final String? operationId;

  factory SessionCorrelation.fromJson(Map<String, Object?> json) =>
      SessionCorrelation(
        taskId: json['taskId']! as String,
        sessionId: json['sessionId']! as String,
        turnId: json['turnId'] as String?,
        planId: json['planId'] as String?,
        stepId: json['stepId'] as String?,
        operationId: json['operationId'] as String?,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'taskId': taskId,
    'sessionId': sessionId,
    if (turnId != null) 'turnId': turnId,
    if (planId != null) 'planId': planId,
    if (stepId != null) 'stepId': stepId,
    if (operationId != null) 'operationId': operationId,
  };

  bool get isValid => taskId.trim().isNotEmpty && sessionId.trim().isNotEmpty;
}

final class SessionEventDraft {
  SessionEventDraft({
    required this.kind,
    required this.correlation,
    required this.occurredAt,
    required Map<String, Object?> payload,
  }) : payload = freezeStringMap(payload) {
    if (!correlation.isValid) {
      throw ArgumentError('Session event correlation is invalid.');
    }
  }

  final SessionEventKind kind;
  final SessionCorrelation correlation;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
}

final class SessionEvent {
  SessionEvent({
    required this.sessionId,
    required this.sequence,
    required this.kind,
    required this.correlation,
    required this.occurredAt,
    required Map<String, Object?> payload,
    required this.previousDigest,
    required this.digest,
  }) : payload = freezeStringMap(payload);

  factory SessionEvent.commit({
    required int sequence,
    required SessionEventDraft draft,
    required String previousDigest,
    required SessionRedactor redactor,
  }) {
    final payload = redactor.redact(draft.payload);
    final digest = computeSessionEventDigest(
      sessionId: draft.correlation.sessionId,
      sequence: sequence,
      kind: draft.kind,
      correlation: draft.correlation,
      occurredAt: draft.occurredAt,
      payload: payload,
      previousDigest: previousDigest,
    );
    return SessionEvent(
      sessionId: draft.correlation.sessionId,
      sequence: sequence,
      kind: draft.kind,
      correlation: draft.correlation,
      occurredAt: draft.occurredAt,
      payload: payload,
      previousDigest: previousDigest,
      digest: digest,
    );
  }

  factory SessionEvent.fromJson(Map<String, Object?> json) => SessionEvent(
    sessionId: json['sessionId']! as String,
    sequence: json['sequence']! as int,
    kind: SessionEventKind.values.byName(json['kind']! as String),
    correlation: SessionCorrelation.fromJson(
      Map<String, Object?>.from(json['correlation']! as Map),
    ),
    occurredAt: DateTime.parse(json['occurredAt']! as String).toUtc(),
    payload: Map<String, Object?>.from(json['payload']! as Map),
    previousDigest: json['previousDigest']! as String,
    digest: json['digest']! as String,
  );

  final String sessionId;
  final int sequence;
  final SessionEventKind kind;
  final SessionCorrelation correlation;
  final DateTime occurredAt;
  final Map<String, Object?> payload;
  final String previousDigest;
  final String digest;

  bool get hasValidDigest =>
      digest ==
      computeSessionEventDigest(
        sessionId: sessionId,
        sequence: sequence,
        kind: kind,
        correlation: correlation,
        occurredAt: occurredAt,
        payload: payload,
        previousDigest: previousDigest,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'sequence': sequence,
    'kind': kind.name,
    'correlation': correlation.toJson(),
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'payload': payload,
    'previousDigest': previousDigest,
    'digest': digest,
  };
}

final class SessionRedactor {
  const SessionRedactor({
    this.sensitiveKeys = const <String>{
      'authorization',
      'password',
      'token',
      'secret',
      'credential',
      'api_key',
    },
  });

  static const String replacement = '<redacted>';

  final Set<String> sensitiveKeys;

  Map<String, Object?> redact(Map<String, Object?> input) =>
      freezeStringMap(_redactMap(input));

  Map<String, Object?> _redactMap(Map<String, Object?> input) =>
      <String, Object?>{
        for (final entry in input.entries)
          entry.key: _isSensitive(entry.key)
              ? replacement
              : _redactValue(entry.value),
      };

  Object? _redactValue(Object? value) => switch (value) {
    Map<String, Object?> map => _redactMap(map),
    Map<Object?, Object?> map => <String, Object?>{
      for (final entry in map.entries)
        entry.key.toString(): _isSensitive(entry.key.toString())
            ? replacement
            : _redactValue(entry.value),
    },
    List<Object?> list => <Object?>[
      for (final item in list) _redactValue(item),
    ],
    Set<Object?> set => <Object?>[for (final item in set) _redactValue(item)],
    _ => value,
  };

  bool _isSensitive(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
    return sensitiveKeys.any((candidate) {
      final normalizedCandidate = candidate.toLowerCase().replaceAll(
        RegExp(r'[-_\s]'),
        '',
      );
      return normalized == normalizedCandidate ||
          normalized.endsWith(normalizedCandidate);
    });
  }
}

String computeSessionEventDigest({
  required String sessionId,
  required int sequence,
  required SessionEventKind kind,
  required SessionCorrelation correlation,
  required DateTime occurredAt,
  required Map<String, Object?> payload,
  required String previousDigest,
}) => sha256
    .convert(
      utf8.encode(
        canonicalJson(<String, Object?>{
          'sessionId': sessionId,
          'sequence': sequence,
          'kind': kind.name,
          'correlation': correlation.toJson(),
          'occurredAt': occurredAt.toUtc().toIso8601String(),
          'payload': payload,
          'previousDigest': previousDigest,
        }),
      ),
    )
    .toString();

String canonicalJson(Object? value) => jsonEncode(_canonicalValue(value));

int canonicalUtf8Length(Object? value) =>
    utf8.encode(canonicalJson(value)).length;

Object? _canonicalValue(Object? value) => switch (value) {
  Map<Object?, Object?> map =>
    SplayTreeMap<String, Object?>.of(<String, Object?>{
      for (final entry in map.entries)
        entry.key.toString(): _canonicalValue(entry.value),
    }),
  Iterable<Object?> iterable => <Object?>[
    for (final item in iterable) _canonicalValue(item),
  ],
  DateTime timestamp => timestamp.toUtc().toIso8601String(),
  _ => value,
};

Map<String, Object?> freezeStringMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(
      source.map((key, value) => MapEntry(key, _freezeValue(value))),
    );

Object? _freezeValue(Object? value) => switch (value) {
  Map<Object?, Object?> map => Map<Object?, Object?>.unmodifiable(
    map.map((key, item) => MapEntry(key, _freezeValue(item))),
  ),
  List<Object?> list => List<Object?>.unmodifiable(list.map(_freezeValue)),
  Set<Object?> set => Set<Object?>.unmodifiable(set.map(_freezeValue)),
  _ => value,
};
