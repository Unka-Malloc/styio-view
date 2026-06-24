# Cache Contract

**Purpose:** Define the shared cache contract for Vityo IDE — owner, key, entry, invalidation, dependency tracking, eviction, freshness, serialization, and observation.

**Last updated:** 2026-06-25

**Status:** Active

## 1. CacheStore<K,V> Interface

All caches in Vityo implement `CacheStore<K, V>`:

```
CacheStore<K, V>:
  - owner: CacheOwner          // which subsystem owns this cache
  - maxEntries: int             // LRU capacity cap
  - metrics: CacheMetrics       // hit, miss, stale, evicted, invalidated

  - get(K key) -> CacheEntry<V>?
  - put(K key, V value, CachePutOptions?) -> CacheEntry<V>
  - invalidate(K key) -> void
  - invalidateByDependency(String depKey) -> void
  - evict(toSize: int) -> void
  - clear() -> void
  - containsKey(K key) -> bool
  - observe(CacheObserver<V>) -> StreamSubscription
```

## 2. CacheEntry<V>

```
CacheEntry<V>:
  - key: K
  - value: V
  - producedAt: DateTime
  - freshness: CacheFreshness    // fresh | stale | unknown
  - dependencies: Set<String>    // dependency keys for invalidation
  - payloadSummary: String?      // optional human-readable summary
  - payloadRef: String?          // optional disk or DataStore ref
```

## 3. CacheFreshness

```
CacheFreshness:
  - fresh       // valid and current
  - stale       // dependency or TTL invalidated
  - unknown     // first load or pending verification
```

Stale entries MUST NOT be returned to UI consumers. They may be retained for metrics or debugging purposes but must be filtered at the `get()` boundary.

## 4. Cache Key Composition

All cache keys MUST include, where applicable:

| Component | Required when |
|-----------|--------------|
| `protocolVersion` | Always |
| `providerId` | Provider-scoped caches |
| `toolchainId` | Toolchain-bound caches |
| `workspaceGraphHash` | Project-scoped caches |
| `documentId` | Document-scoped caches |
| `documentRevision` | Document-scoped caches |
| `semanticPayloadVersion` | Semantic caches |

**Rule:** If a key component changes, the cache entry is stale and must be recomputed.

## 5. Cache Families

| Cache Family | Scope | Invalidation Triggers |
|-------------|-------|----------------------|
| Language Result | Per-document | Document edit, toolchain change, provider version change |
| Semantic Snapshot | Per-document | Document revision change, workspace graph change |
| Project Graph | Per-workspace | Canonical file change, manifest edit |
| File Gist | Per-file | File content change, toolchain change |
| Runtime Event Derived | Per-session | New events appended, session reset |
| AI Context | Per-request | Context candidate list change |

## 6. Invalidation Rules

1. **Document edit**: Invalidates all document-scoped cache entries for that documentId.
2. **Workspace graph change**: Invalidates all project-scoped and document-scoped caches (graphHash mismatch).
3. **Toolchain change**: Invalidates all toolchain-bound caches.
4. **Provider capability change**: Invalidates all provider-scoped caches.
5. **Protocol version change**: Invalidates all caches.

## 7. Eviction Policy

- **LRU** with configurable `maxEntries`.
- Eviction triggers on `put()` when at capacity.
- Evicted entries are removed from memory; disk-backed entries may persist a metadata manifest.
- Manifest MUST NOT contain raw secrets or full language payloads.

## 8. Serialization

- Memory entries: in-memory Dart objects.
- Manifest entries: JSON metadata only (key, producedAt, freshness, dependencies, payloadSummary, payloadRef).
- Payload storage: optional DataStore-backed or file-backed, keyed by payloadRef.

## 9. Observation

```
CacheObserver<V>:
  - onPut(CacheEntry<V> entry) -> void
  - onInvalidate(K key) -> void
  - onEvict(K key) -> void
  - onClear() -> void
```

## 10. Metrics

```
CacheMetrics:
  - hits: int
  - misses: int
  - staleHits: int     // stale entries that were filtered
  - evictions: int
  - invalidations: int
  - hitRate: double    // hits / (hits + misses)
```

All cache implementations MUST expose metrics for observability.
