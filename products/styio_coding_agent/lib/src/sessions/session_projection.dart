library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'effect_receipt.dart';
import 'session_event.dart';

final class SessionProjection {
  SessionProjection({
    required this.sessionId,
    required this.appliedSequence,
    required this.lastEventDigest,
    required Map<SessionEventKind, SessionEvent> latestByKind,
    required List<SessionEvent> hotEvents,
    required Map<String, EffectReceipt> effectReceipts,
  }) : latestByKind = Map<SessionEventKind, SessionEvent>.unmodifiable(
         latestByKind,
       ),
       hotEvents = List<SessionEvent>.unmodifiable(hotEvents),
       effectReceipts = Map<String, EffectReceipt>.unmodifiable(effectReceipts);

  factory SessionProjection.empty(String sessionId) => SessionProjection(
    sessionId: sessionId,
    appliedSequence: 0,
    lastEventDigest: '',
    latestByKind: const <SessionEventKind, SessionEvent>{},
    hotEvents: const <SessionEvent>[],
    effectReceipts: const <String, EffectReceipt>{},
  );

  factory SessionProjection.fromJson(Map<String, Object?> json) {
    final latest = Map<String, Object?>.from(json['latestByKind']! as Map);
    final effects = Map<String, Object?>.from(json['effectReceipts']! as Map);
    return SessionProjection(
      sessionId: json['sessionId']! as String,
      appliedSequence: json['appliedSequence']! as int,
      lastEventDigest: json['lastEventDigest']! as String,
      latestByKind: <SessionEventKind, SessionEvent>{
        for (final entry in latest.entries)
          SessionEventKind.values.byName(entry.key): SessionEvent.fromJson(
            Map<String, Object?>.from(entry.value! as Map),
          ),
      },
      hotEvents: <SessionEvent>[
        for (final raw in json['hotEvents']! as List)
          SessionEvent.fromJson(Map<String, Object?>.from(raw as Map)),
      ],
      effectReceipts: <String, EffectReceipt>{
        for (final entry in effects.entries)
          entry.key: EffectReceipt.fromJson(
            Map<String, Object?>.from(entry.value! as Map),
          ),
      },
    );
  }

  final String sessionId;
  final int appliedSequence;
  final String lastEventDigest;
  final Map<SessionEventKind, SessionEvent> latestByKind;
  final List<SessionEvent> hotEvents;
  final Map<String, EffectReceipt> effectReceipts;

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'appliedSequence': appliedSequence,
    'lastEventDigest': lastEventDigest,
    'latestByKind': <String, Object?>{
      for (final entry in latestByKind.entries)
        entry.key.name: entry.value.toJson(),
    },
    'hotEvents': <Map<String, Object?>>[
      for (final event in hotEvents) event.toJson(),
    ],
    'effectReceipts': <String, Object?>{
      for (final entry in effectReceipts.entries)
        entry.key: entry.value.toJson(),
    },
  };
}

final class SessionProjector {
  const SessionProjector({required this.maxHotEvents})
    : assert(maxHotEvents > 0);

  final int maxHotEvents;

  SessionProjection project({
    required String sessionId,
    required Iterable<SessionEvent> events,
    SessionProjection? base,
    Iterable<EffectReceipt> effectReceipts = const <EffectReceipt>[],
  }) {
    final initial = base ?? SessionProjection.empty(sessionId);
    if (initial.sessionId != sessionId) {
      throw ArgumentError('Projection session does not match.');
    }
    final latest = Map<SessionEventKind, SessionEvent>.of(initial.latestByKind);
    final hot = List<SessionEvent>.of(initial.hotEvents);
    var sequence = initial.appliedSequence;
    var digest = initial.lastEventDigest;
    for (final event in events) {
      if (event.sessionId != sessionId ||
          event.sequence != sequence + 1 ||
          event.previousDigest != digest ||
          !event.hasValidDigest) {
        throw ArgumentError('Projection event chain is invalid.');
      }
      latest[event.kind] = event;
      hot.add(event);
      if (hot.length > maxHotEvents) {
        hot.removeRange(0, hot.length - maxHotEvents);
      }
      sequence = event.sequence;
      digest = event.digest;
    }
    final effects = Map<String, EffectReceipt>.of(initial.effectReceipts);
    for (final receipt in effectReceipts) {
      if (receipt.sessionId == sessionId && receipt.eventSequence <= sequence) {
        effects[receipt.idempotencyKey] = receipt;
      }
    }
    return SessionProjection(
      sessionId: sessionId,
      appliedSequence: sequence,
      lastEventDigest: digest,
      latestByKind: latest,
      hotEvents: hot,
      effectReceipts: effects,
    );
  }
}

final class SessionCheckpoint {
  const SessionCheckpoint({
    required this.sessionId,
    required this.appliedSequence,
    required this.lastEventDigest,
    required this.projection,
    required this.projectionDigest,
  });

  factory SessionCheckpoint.fromProjection(SessionProjection projection) =>
      SessionCheckpoint(
        sessionId: projection.sessionId,
        appliedSequence: projection.appliedSequence,
        lastEventDigest: projection.lastEventDigest,
        projection: projection,
        projectionDigest: computeProjectionDigest(projection),
      );

  factory SessionCheckpoint.fromJson(Map<String, Object?> json) =>
      SessionCheckpoint(
        sessionId: json['sessionId']! as String,
        appliedSequence: json['appliedSequence']! as int,
        lastEventDigest: json['lastEventDigest']! as String,
        projection: SessionProjection.fromJson(
          Map<String, Object?>.from(json['projection']! as Map),
        ),
        projectionDigest: json['projectionDigest']! as String,
      );

  final String sessionId;
  final int appliedSequence;
  final String lastEventDigest;
  final SessionProjection projection;
  final String projectionDigest;

  bool get isValid =>
      sessionId == projection.sessionId &&
      appliedSequence == projection.appliedSequence &&
      lastEventDigest == projection.lastEventDigest &&
      projectionDigest == computeProjectionDigest(projection);

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'appliedSequence': appliedSequence,
    'lastEventDigest': lastEventDigest,
    'projection': projection.toJson(),
    'projectionDigest': projectionDigest,
  };
}

String computeProjectionDigest(SessionProjection projection) => sha256
    .convert(
      utf8.encode(
        canonicalJson(<String, Object?>{
          'sessionId': projection.sessionId,
          'appliedSequence': projection.appliedSequence,
          'lastEventDigest': projection.lastEventDigest,
          'latestByKind': <String, Object?>{
            for (final entry in projection.latestByKind.entries)
              entry.key.name: entry.value.digest,
          },
          'hotEvents': <String>[
            for (final event in projection.hotEvents) event.digest,
          ],
          'effectReceipts': <String, Object?>{
            for (final entry in projection.effectReceipts.entries)
              entry.key: <String, Object?>{
                'effectId': entry.value.effectId,
                'eventSequence': entry.value.eventSequence,
                'outcome': entry.value.outcome.name,
              },
          },
        }),
      ),
    )
    .toString();
