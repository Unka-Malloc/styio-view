/// Bounded revision-aware materialization cache.
library;

import 'dart:collection';
import 'dart:convert';

final class ContextCacheKey {
  const ContextCacheKey({
    required this.evidenceId,
    required this.resource,
    required this.revision,
  });

  final String evidenceId;
  final String resource;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ContextCacheKey &&
      evidenceId == other.evidenceId &&
      resource == other.resource &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(evidenceId, resource, revision);
}

final class ContextCacheMetrics {
  const ContextCacheMetrics({
    required this.hits,
    required this.misses,
    required this.evictions,
  });

  final int hits;
  final int misses;
  final int evictions;
}

final class ContextCache {
  ContextCache({required this.maxEntries, required this.maxBytes}) {
    if (maxEntries < 0 || maxBytes < 0) {
      throw ArgumentError('Cache bounds cannot be negative.');
    }
  }

  final int maxEntries;
  final int maxBytes;
  final LinkedHashMap<ContextCacheKey, _CacheEntry> _entries =
      LinkedHashMap<ContextCacheKey, _CacheEntry>();
  int _byteCount = 0;
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;

  int get entryCount => _entries.length;
  int get byteCount => _byteCount;
  ContextCacheMetrics get metrics =>
      ContextCacheMetrics(hits: _hits, misses: _misses, evictions: _evictions);

  String? get(ContextCacheKey key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      _misses += 1;
      return null;
    }
    _entries[key] = entry;
    _hits += 1;
    return entry.value;
  }

  void put(ContextCacheKey key, String value) {
    final size = utf8.encode(value).length;
    final previous = _entries.remove(key);
    if (previous != null) {
      _byteCount -= previous.byteCount;
    }
    if (size > maxBytes || maxEntries == 0) {
      return;
    }
    _entries[key] = _CacheEntry(value, size);
    _byteCount += size;
    while (_entries.length > maxEntries || _byteCount > maxBytes) {
      final oldest = _entries.keys.first;
      final removed = _entries.remove(oldest)!;
      _byteCount -= removed.byteCount;
      _evictions += 1;
    }
  }

  void invalidateResource(String resource, {required int currentRevision}) {
    final staleKeys = _entries.keys
        .where(
          (key) => key.resource == resource && key.revision != currentRevision,
        )
        .toList(growable: false);
    for (final key in staleKeys) {
      _byteCount -= _entries.remove(key)!.byteCount;
    }
  }
}

final class _CacheEntry {
  const _CacheEntry(this.value, this.byteCount);

  final String value;
  final int byteCount;
}
