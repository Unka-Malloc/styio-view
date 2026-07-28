import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/cache/language_cache.dart';

void main() {
  group('LanguageCache', () {
    const testDocumentId = 'doc://test';
    const testRevision = 5;
    const testWorkspaceGraphHash = 'wshash001';
    const testToolchainId = 'styio-1.2.0';
    const testProviderId = 'styio-native';
    const testProtocolVersion = '1.0';
    const testSemanticPayloadVersion = '1.0';

    LanguageCacheEntry<String> createEntry({
      String documentId = testDocumentId,
      int revision = testRevision,
      String workspaceGraphHash = testWorkspaceGraphHash,
      String toolchainId = testToolchainId,
      String providerId = testProviderId,
      String protocolVersion = testProtocolVersion,
      String semanticPayloadVersion = testSemanticPayloadVersion,
      String value = 'cached-result',
      Duration? ttl,
      int? ttlMinutes,
    }) {
      final effectiveTtl = ttl ??
          (ttlMinutes != null ? Duration(minutes: ttlMinutes) : null);
      return LanguageCacheEntry<String>(
        value: value,
        documentId: documentId,
        revision: revision,
        workspaceGraphHash: workspaceGraphHash,
        toolchainId: toolchainId,
        providerId: providerId,
        protocolVersion: protocolVersion,
        semanticPayloadVersion: semanticPayloadVersion,
        cachedAt: DateTime.now(),
        ttl: effectiveTtl,
      );
    }

    // ── Test 1: Basic put/get freshness ──────────────────────────────────
    test('put and get returns fresh entry', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry());

      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 'cached-result');
      expect(result.documentId, testDocumentId);
      expect(result.revision, testRevision);
    });

    test('get returns null for missing key', () {
      final cache = LanguageCache(capacity: 10);

      final result = cache.get<String>(
        'nonexistent',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNull);
    });

    // ── Test 2: Stale entry rejection (wrong revision) ───────────────────
    test('rejects stale entry when revision differs', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(revision: 5));

      // Request with a different revision
      final result = cache.get<String>(
        key,
        revision: 6,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNull);
      // Entry should have been removed from cache
      expect(cache.get<String>(
        key,
        revision: 5,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      ), isNull);
    });

    // ── Test 3: Stale entry rejection (wrong workspaceGraphHash) ─────────
    test('rejects stale entry when workspaceGraphHash differs', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(workspaceGraphHash: 'hash-a'));

      // Request with a different workspace hash
      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: 'hash-b',
        toolchainId: testToolchainId,
      );

      expect(result, isNull);
    });

    test('allows entry when workspaceGraphHash is empty (wildcard)', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(workspaceGraphHash: ''));

      // Request with non-empty hash should still match (stored hash is empty)
      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 'cached-result');
    });

    test('allows entry when requested workspaceGraphHash is empty (wildcard)',
        () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(workspaceGraphHash: 'hash-a'));

      // Request with empty hash should skip hash comparison
      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: '',
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 'cached-result');
    });

    // ── Test 4: Stale entry rejection (wrong toolchainId) ────────────────
    test('rejects stale entry when toolchainId differs', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(toolchainId: 'toolchain-old'));

      // Request with a different toolchain
      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: 'toolchain-new',
      );

      expect(result, isNull);
    });

    test('allows entry when stored toolchainId is empty (wildcard)', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(toolchainId: ''));

      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 'cached-result');
    });

    // ── Test 5: LRU eviction when capacity exceeded ──────────────────────
    test('evicts least recently used entry when capacity exceeded', () {
      final cache = LanguageCache(capacity: 3);

      // Fill cache to capacity
      cache.put('key1', createEntry(value: 'one', documentId: 'doc1'));
      cache.put('key2', createEntry(value: 'two', documentId: 'doc2'));
      cache.put('key3', createEntry(value: 'three', documentId: 'doc3'));

      expect(cache.size, 3);

      // Access key1 to make it most recently used
      cache.get<String>(
        'key1',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      // Add fourth entry - should evict key2 (LRU)
      cache.put('key4', createEntry(value: 'four', documentId: 'doc4'));

      expect(cache.size, 3);

      // key2 should have been evicted
      expect(
        cache.get<String>(
          'key2',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNull,
      );

      // key1, key3, key4 should still be present
      expect(
        cache.get<String>(
          'key1',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNotNull,
      );
      expect(
        cache.get<String>(
          'key3',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNotNull,
      );
      expect(
        cache.get<String>(
          'key4',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNotNull,
      );
    });

    test('evicts oldest entry when put exceeds capacity', () {
      final cache = LanguageCache(capacity: 2);

      cache.put('a', createEntry(value: 'alpha', documentId: 'docA'));
      cache.put('b', createEntry(value: 'bravo', documentId: 'docB'));

      // This should evict 'a'
      cache.put('c', createEntry(value: 'charlie', documentId: 'docC'));

      expect(
        cache.get<String>(
          'a',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNull,
      );
      expect(cache.size, 2);
      expect(
        cache.get<String>(
          'b',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNotNull,
      );
      expect(
        cache.get<String>(
          'c',
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
        ),
        isNotNull,
      );
    });

    // ── Test 6: Invalidation triggers ────────────────────────────────────
    test('invalidates entries by workspace graph change', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry(value: 'one', workspaceGraphHash: 'hash-a'));
      cache.put('key2', createEntry(value: 'two', workspaceGraphHash: 'hash-b'));
      cache.put('key3', createEntry(value: 'three', workspaceGraphHash: ''));

      final count = cache.invalidateByReason(
        CacheInvalidationReason.workspaceGraphChange,
      );

      // key1 and key2 should be removed (have non-empty hashes)
      // key3 should stay (empty hash)
      expect(count, 2);
      expect(cache.size, 1);
      expect(cache.keys, ['key3']);
    });

    test('invalidates entries by toolchain change', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry(value: 'one', toolchainId: 'tc-a'));
      cache.put('key2', createEntry(value: 'two', toolchainId: 'tc-b'));
      cache.put(
        'key3',
        createEntry(value: 'three', toolchainId: ''),
      );

      final count = cache.invalidateByReason(
        CacheInvalidationReason.toolchainChange,
      );

      expect(count, 2);
      expect(cache.size, 1);
      expect(cache.keys, ['key3']);
    });

    test('clears entire cache on protocol version change', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry());
      cache.put('key2', createEntry(value: 'other', documentId: 'doc2'));

      final count = cache.invalidateByReason(
        CacheInvalidationReason.protocolVersionChange,
      );

      expect(count, greaterThanOrEqualTo(0));
      expect(cache.size, 0);
    });

    test('clears entire cache on manual invalidation', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry());
      cache.put('key2', createEntry(value: 'other', documentId: 'doc2'));

      cache.invalidateByReason(CacheInvalidationReason.manual);

      expect(cache.size, 0);
    });

    test('document edit invalidation returns 0 (caller provides documentId)',
        () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry());
      cache.put('key2', createEntry(value: 'other', documentId: 'doc2'));

      // documentEdit does not auto-invalidate (caller must specify documentId)
      final count = cache.invalidateByReason(
        CacheInvalidationReason.documentEdit,
      );

      expect(count, 0);
      expect(cache.size, 2);
    });

    test('invalidateWhere with custom predicate', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry(value: 'keep', documentId: 'doc/keep'));
      cache.put(
        'key2',
        createEntry(value: 'remove', documentId: 'doc/remove'),
      );

      final count = cache.invalidateWhere(
        (key, entry) => entry.documentId == 'doc/remove',
      );

      expect(count, 1);
      expect(cache.size, 1);
      expect(cache.keys, ['key1']);
    });

    // ── Test 7: Metrics tracking ─────────────────────────────────────────
    test('tracks hit metrics', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry());

      // Miss
      cache.get<String>(
        'unknown',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      // Hit
      cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(cache.metrics.hits, 1);
      expect(cache.metrics.misses, 1);
    });

    test('tracks stale hit metrics', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry(revision: 5));

      // Request with different revision — should be stale
      cache.get<String>(
        key,
        revision: 6,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(cache.metrics.staleHits, 1);
    });

    test('tracks eviction metrics', () {
      final cache = LanguageCache(capacity: 2);

      cache.put('a', createEntry(documentId: 'docA'));
      cache.put('b', createEntry(documentId: 'docB'));

      // This put triggers eviction of 'a'
      cache.put('c', createEntry(documentId: 'docC'));

      expect(cache.metrics.evictions, 1);
    });

    test('tracks invalidation metrics', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('key1', createEntry());
      cache.put('key2', createEntry(value: 'other', documentId: 'doc2'));

      cache.invalidateByReason(CacheInvalidationReason.manual);

      expect(cache.metrics.invalidations, greaterThanOrEqualTo(0));
    });

    test('metrics toJson produces expected structure', () {
      final metrics = LanguageCacheMetrics();
      metrics.hits = 10;
      metrics.misses = 5;

      final json = metrics.toJson();

      expect(json['hits'], 10);
      expect(json['misses'], 5);
      expect(json['hitRate'], 10 / 15);
    });

    test('metrics reset clears all counts', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry());
      cache.put('other', createEntry(value: 'x', documentId: 'doc2'));

      cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );
      cache.get<String>(
        'unknown',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      cache.metrics.reset();

      expect(cache.metrics.hits, 0);
      expect(cache.metrics.misses, 0);
      expect(cache.metrics.staleHits, 0);
      expect(cache.metrics.evictions, 0);
      expect(cache.metrics.invalidations, 0);
      expect(cache.metrics.size, 0);
    });

    // ── Test 8: Expired TTL rejection ────────────────────────────────────
    test('rejects entry with expired TTL', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(
        key,
        LanguageCacheEntry<String>(
          value: 'cached-result',
          documentId: testDocumentId,
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
          providerId: testProviderId,
          protocolVersion: testProtocolVersion,
          semanticPayloadVersion: testSemanticPayloadVersion,
          cachedAt: DateTime.now().subtract(const Duration(minutes: 30)),
          ttl: const Duration(minutes: 10),
        ),
      );

      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNull);
      // Entry should have been removed
      expect(cache.size, 0);
    });

    test('returns fresh entry when TTL has not expired', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(
        key,
        LanguageCacheEntry<String>(
          value: 'fresh-value',
          documentId: testDocumentId,
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
          providerId: testProviderId,
          protocolVersion: testProtocolVersion,
          semanticPayloadVersion: testSemanticPayloadVersion,
          cachedAt: DateTime.now(),
          ttl: const Duration(minutes: 10),
        ),
      );

      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 'fresh-value');
    });

    test('entry without TTL never expires', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(
        key,
        LanguageCacheEntry<String>(
          value: 'persistent',
          documentId: testDocumentId,
          revision: testRevision,
          workspaceGraphHash: testWorkspaceGraphHash,
          toolchainId: testToolchainId,
          providerId: testProviderId,
          protocolVersion: testProtocolVersion,
          semanticPayloadVersion: testSemanticPayloadVersion,
          cachedAt: DateTime.now().subtract(const Duration(days: 365)),
        ),
      );

      final result = cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 'persistent');
    });

    // ── Additional tests ─────────────────────────────────────────────────
    test('compositeKey formats correctly', () {
      final entry = createEntry();

      expect(
        entry.compositeKey,
        '$testDocumentId:$testRevision:$testWorkspaceGraphHash:$testToolchainId:$testProviderId:$testProtocolVersion:$testSemanticPayloadVersion',
      );
    });

    test('clear wipes all entries and resets metrics', () {
      final cache = LanguageCache(capacity: 10);
      const key = 'doc://test:5';

      cache.put(key, createEntry());
      cache.put('another', createEntry(value: 'other', documentId: 'doc2'));

      // Get some metrics
      cache.get<String>(
        key,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );
      cache.get<String>(
        'missing',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      cache.clear();

      expect(cache.size, 0);
      expect(cache.metrics.hits, 0);
      expect(cache.metrics.misses, 0);
      expect(cache.metrics.staleHits, 0);
      expect(cache.metrics.evictions, 0);
      expect(cache.metrics.invalidations, 0);
      expect(cache.metrics.size, 0);
    });

    test('keys returns a copy of cached keys', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('a', createEntry(documentId: 'docA'));
      cache.put('b', createEntry(documentId: 'docB'));

      final keys = cache.keys;
      expect(keys, ['a', 'b']);

      // Modifying the returned list should not affect cache
      keys.clear();
      expect(cache.size, 2);
    });

    test('LRU order is maintained on access', () {
      final cache = LanguageCache(capacity: 5);

      cache.put('a', createEntry(documentId: 'docA'));
      cache.put('b', createEntry(documentId: 'docB'));
      cache.put('c', createEntry(documentId: 'docC'));

      // Access 'a' to make it MRU
      cache.get<String>(
        'a',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      // Cache keys should be: b, c, a (a moved to back = MRU)
      expect(cache.keys, ['b', 'c', 'a']);
    });

    test('put with existing key updates value and moves to MRU', () {
      final cache = LanguageCache(capacity: 5);

      cache.put('a', createEntry(value: 'old', documentId: 'docA'));
      cache.put('b', createEntry(value: 'beta', documentId: 'docB'));

      // Re-put 'a' with new value (re-insert, moves to MRU position)
      cache.put('a', createEntry(value: 'new', documentId: 'docA'));

      // Keys order should be: b, a (a at end = MRU)
      expect(cache.keys, ['b', 'a']);

      final result = cache.get<String>(
        'a',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );
      expect(result!.value, 'new');
    });

    test('get returns entry with correct generic type', () {
      final cache = LanguageCache(capacity: 10);

      cache.put('intKey', LanguageCacheEntry<int>(
        value: 42,
        documentId: testDocumentId,
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
        providerId: testProviderId,
        protocolVersion: testProtocolVersion,
        semanticPayloadVersion: testSemanticPayloadVersion,
        cachedAt: DateTime.now(),
      ));

      final result = cache.get<int>(
        'intKey',
        revision: testRevision,
        workspaceGraphHash: testWorkspaceGraphHash,
        toolchainId: testToolchainId,
      );

      expect(result, isNotNull);
      expect(result!.value, 42);
    });

    test('Capacity of 1 works correctly', () {
      final cache = LanguageCache(capacity: 1);

      cache.put('a', createEntry(documentId: 'docA'));
      expect(cache.size, 1);

      cache.put('b', createEntry(documentId: 'docB'));
      expect(cache.size, 1);

      // 'a' should be evicted
      expect(cache.keys, ['b']);
    });

    test('invalidateWhere with reason parameter passes through correctly', () {
      final cache = LanguageCache(capacity: 10);
      cache.put('k1', createEntry());
      cache.put('k2', createEntry(documentId: 'docB'));

      final count = cache.invalidateWhere(
        (key, entry) => key == 'k1',
        reason: CacheInvalidationReason.ttlExpired,
      );

      expect(count, 1);
      expect(cache.size, 1);
      expect(cache.keys, ['k2']);
    });
  });
}
