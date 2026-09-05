import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'observable_delta_model.dart';
import 'observable_snapshot_decoder.dart';
import 'observable_snapshot_model.dart';

String observableSnapshotId(List<int> bytes) {
  final digest = sha256.convert(bytes).toString();
  return '$kObservableSnapshotIdPrefix${digest.substring(0, 32)}';
}

class ObservableSnapshotCache {
  ObservableSnapshotCache({
    this.maxEntries = kObservableSnapshotCacheDefaultMaxEntries,
  }) : assert(maxEntries > 0, 'maxEntries must be positive');

  final int maxEntries;
  final LinkedHashMap<SnapshotIdentity, ObservableSnapshot> _entries =
      LinkedHashMap<SnapshotIdentity, ObservableSnapshot>();
  ObservableCacheMetrics _metrics = const ObservableCacheMetrics();

  ObservableCacheMetrics get metrics => _metrics;

  int get length => _entries.length;

  ObservableSnapshot? get(SnapshotIdentity identity) {
    final snapshot = _entries.remove(identity);
    if (snapshot == null) {
      _metrics = _metrics.copyWith(misses: _metrics.misses + 1);
      return null;
    }
    _entries[identity] = snapshot;
    _metrics = _metrics.copyWith(hits: _metrics.hits + 1);
    return snapshot;
  }

  ObservableSnapshot put(SnapshotIdentity identity, ObservableSnapshot snapshot) {
    final existing = _entries.remove(identity);
    if (existing != null) {
      _entries[identity] = existing;
      _metrics = _metrics.copyWith(hits: _metrics.hits + 1);
      return existing;
    }
    _entries[identity] = snapshot;
    _metrics = _metrics.copyWith(misses: _metrics.misses + 1);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
      _metrics = _metrics.copyWith(evictions: _metrics.evictions + 1);
    }
    return snapshot;
  }

  ObservableCacheIntakeResult intake(
    List<int> bytes, {
    ObservableSnapshot Function(List<int> bytes)? decode,
  }) {
    final snapshotId = observableSnapshotId(bytes);
    final hit = _hitForSnapshotId(snapshotId);
    if (hit != null) {
      return hit;
    }
    final decoded = decode != null
        ? _decodeWith(decode, bytes)
        : decodeObservableSnapshotBytes(bytes);
    return _intakeDecoded(snapshotId, decoded);
  }

  /// Production intake path: the fail-closed decode runs in a background
  /// isolate so multi-megabyte snapshots never block the UI thread. Cache
  /// mutation still happens on the caller's thread after the decode returns.
  Future<ObservableCacheIntakeResult> intakeAsync(List<int> bytes) async {
    final snapshotId = observableSnapshotId(bytes);
    final hit = _hitForSnapshotId(snapshotId);
    if (hit != null) {
      return hit;
    }
    final decoded = await compute(
      decodeObservableSnapshotBytes,
      bytes,
    );
    return _intakeDecoded(snapshotId, decoded);
  }

  ObservableCacheIntakeResult? _hitForSnapshotId(String snapshotId) {
    final probe = SnapshotIdentity(
      snapshotId: snapshotId,
      compilationUnitKey: '',
    );
    final cached = get(probe);
    if (cached == null) {
      return null;
    }
    return ObservableCacheIntakeResult.hit(
      identity: SnapshotIdentity(
        snapshotId: snapshotId,
        compilationUnitKey: cached.compilationUnit.identityKey,
      ),
      snapshot: cached,
      metrics: metrics,
    );
  }

  ObservableCacheIntakeResult _intakeDecoded(
    String snapshotId,
    ObservableDecodeResult decoded,
  ) {
    if (!decoded.isOk) {
      return ObservableCacheIntakeResult.invalid(decoded.failure!);
    }
    final identity = SnapshotIdentity.fromSnapshot(
      snapshot: decoded.snapshot!,
      snapshotId: snapshotId,
    );
    final stored = put(identity, decoded.snapshot!);
    return ObservableCacheIntakeResult.miss(
      identity: identity,
      snapshot: stored,
      metrics: metrics,
    );
  }

  ObservableDecodeResult _decodeWith(
    ObservableSnapshot Function(List<int> bytes) decode,
    List<int> bytes,
  ) {
    return ObservableDecodeResult.ok(decode(bytes));
  }
}

class ObservableCacheIntakeResult {
  const ObservableCacheIntakeResult._({
    required this.hit,
    this.identity,
    this.snapshot,
    this.failure,
    this.metrics = const ObservableCacheMetrics(),
  });

  factory ObservableCacheIntakeResult.hit({
    required SnapshotIdentity identity,
    required ObservableSnapshot snapshot,
    required ObservableCacheMetrics metrics,
  }) {
    return ObservableCacheIntakeResult._(
      hit: true,
      identity: identity,
      snapshot: snapshot,
      metrics: metrics,
    );
  }

  factory ObservableCacheIntakeResult.miss({
    required SnapshotIdentity identity,
    required ObservableSnapshot snapshot,
    required ObservableCacheMetrics metrics,
  }) {
    return ObservableCacheIntakeResult._(
      hit: false,
      identity: identity,
      snapshot: snapshot,
      metrics: metrics,
    );
  }

  factory ObservableCacheIntakeResult.invalid(ObservableDecodeFailure failure) {
    return ObservableCacheIntakeResult._(hit: false, failure: failure);
  }

  final bool hit;
  final SnapshotIdentity? identity;
  final ObservableSnapshot? snapshot;
  final ObservableDecodeFailure? failure;
  final ObservableCacheMetrics metrics;
}

List<int> observableSnapshotUtf8(String json) => utf8.encode(json);
