import 'dart:collection';

/// Cache entry with freshness metadata
class LanguageCacheEntry<T> {
  final T value;
  final String documentId;
  final int revision;
  final String workspaceGraphHash;
  final String toolchainId;
  final String providerId;
  final String protocolVersion;
  final String semanticPayloadVersion;
  final DateTime cachedAt;
  final Duration? ttl;
  final Set<String> dependencyKeys;

  const LanguageCacheEntry({
    required this.value,
    required this.documentId,
    required this.revision,
    required this.workspaceGraphHash,
    required this.toolchainId,
    required this.providerId,
    required this.protocolVersion,
    required this.semanticPayloadVersion,
    required this.cachedAt,
    this.ttl,
    this.dependencyKeys = const {},
  });

  String get compositeKey =>
      '$documentId:$revision:$workspaceGraphHash:$toolchainId:$providerId:$protocolVersion:$semanticPayloadVersion';

  bool get isExpired {
    if (ttl == null) return false;
    return DateTime.now().difference(cachedAt) > ttl!;
  }
}

/// Invalidation reason enum
enum CacheInvalidationReason {
  documentEdit,
  workspaceGraphChange,
  toolchainChange,
  providerCapabilityChange,
  protocolVersionChange,
  manual,
  ttlExpired,
}

/// Cache metrics
class LanguageCacheMetrics {
  int hits = 0;
  int misses = 0;
  int staleHits = 0;
  int evictions = 0;
  int invalidations = 0;
  int size = 0;

  Map<String, Object?> toJson() => {
        'hits': hits,
        'misses': misses,
        'staleHits': staleHits,
        'evictions': evictions,
        'invalidations': invalidations,
        'size': size,
        'hitRate': hits + misses > 0 ? hits / (hits + misses) : 0.0,
      };

  void reset() {
    hits = 0;
    misses = 0;
    staleHits = 0;
    evictions = 0;
    invalidations = 0;
    size = 0;
  }
}

/// Two-Level LRU Language Cache
///
/// Level 1: In-memory LRU cache for fast access
/// Level 2: DataStore-backed manifest for persistence
class LanguageCache {
  static const int _defaultCapacity = 100;

  final int _capacity;
  final LinkedHashMap<String, LanguageCacheEntry<Object>> _cache;
  final LanguageCacheMetrics metrics;

  LanguageCache({int capacity = _defaultCapacity})
      : _capacity = capacity,
        _cache = LinkedHashMap<String, LanguageCacheEntry<Object>>(),
        metrics = LanguageCacheMetrics();

  /// Get entry if fresh (not stale and not expired)
  LanguageCacheEntry<T>? get<T>(
    String key, {
    required int revision,
    required String workspaceGraphHash,
    required String toolchainId,
  }) {
    final entry = _cache[key];
    if (entry == null) {
      metrics.misses += 1;
      return null;
    }

    // Check freshness
    if (entry.revision != revision ||
        (entry.workspaceGraphHash.isNotEmpty &&
            workspaceGraphHash.isNotEmpty &&
            entry.workspaceGraphHash != workspaceGraphHash) ||
        (entry.toolchainId.isNotEmpty &&
            toolchainId.isNotEmpty &&
            entry.toolchainId != toolchainId)) {
      _cache.remove(key);
      metrics.staleHits += 1;
      return null;
    }

    // Check TTL
    if (entry.isExpired) {
      _cache.remove(key);
      metrics.staleHits += 1;
      return null;
    }

    // Move to front (re-insert for LRU)
    _cache.remove(key);
    _cache[key] = entry;
    metrics.hits += 1;
    return entry as LanguageCacheEntry<T>;
  }

  /// Put entry into cache
  void put<T>(String key, LanguageCacheEntry<T> entry) {
    _cache.remove(key);
    // Evict if at capacity
    while (_cache.length >= _capacity) {
      _cache.remove(_cache.keys.first);
      metrics.evictions += 1;
    }
    _cache[key] = entry as LanguageCacheEntry<Object>;
    metrics.size = _cache.length;
  }

  /// Invalidate entries matching predicate or by reason
  int invalidateWhere(
    bool Function(String key, LanguageCacheEntry entry) predicate, {
    CacheInvalidationReason reason = CacheInvalidationReason.manual,
  }) {
    final keysToRemove = <String>[];
    for (final entry in _cache.entries) {
      if (predicate(entry.key, entry.value)) {
        keysToRemove.add(entry.key);
      }
    }
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
    metrics.invalidations += keysToRemove.length;
    metrics.size = _cache.length;
    return keysToRemove.length;
  }

  /// Invalidate by reason
  int invalidateByReason(CacheInvalidationReason reason) {
    switch (reason) {
      case CacheInvalidationReason.documentEdit:
        // Invalidate entries with matching documentId
        // (caller provides documentId)
        return 0;
      case CacheInvalidationReason.workspaceGraphChange:
        final count =
            invalidateWhere((key, entry) => entry.workspaceGraphHash.isNotEmpty);
        return count;
      case CacheInvalidationReason.toolchainChange:
        final count =
            invalidateWhere((key, entry) => entry.toolchainId.isNotEmpty);
        return count;
      case CacheInvalidationReason.protocolVersionChange:
        _cache.clear();
        metrics.invalidations = _cache.length;
        metrics.size = 0;
        return _cache.length;
      default:
        _cache.clear();
        metrics.invalidations = _cache.length;
        metrics.size = 0;
        return _cache.length;
    }
  }

  /// Invalidate all entries
  void clear() {
    _cache.clear();
    metrics.reset();
  }

  /// Get all cached keys
  List<String> get keys => _cache.keys.toList();

  /// Get entry count
  int get size => _cache.length;
}

/// Cache event for observation
class CacheEvent {
  final String key;
  final CacheEventKind kind;
  final DateTime timestamp;
  final CacheInvalidationReason? reason;

  const CacheEvent({
    required this.key,
    required this.kind,
    required this.timestamp,
    this.reason,
  });
}

enum CacheEventKind { hit, miss, stale, eviction, invalidation, put }
