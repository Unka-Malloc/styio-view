import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/semantic/styio_semantic_core.dart';

void main() {
  group('SemanticIndexStatus', () {
    test('ready is usable', () {
      expect(SemanticIndexStatus.ready.isUsable, isTrue);
    });

    test('degraded is usable', () {
      expect(SemanticIndexStatus.degraded.isUsable, isTrue);
    });

    test('blocked is not usable', () {
      expect(SemanticIndexStatus.blocked.isUsable, isFalse);
    });

    test('stale is not usable', () {
      expect(SemanticIndexStatus.stale.isUsable, isFalse);
    });

    test('wireValue returns expected strings', () {
      expect(SemanticIndexStatus.ready.wireValue, 'ready');
      expect(SemanticIndexStatus.degraded.wireValue, 'degraded');
      expect(SemanticIndexStatus.blocked.wireValue, 'blocked');
      expect(SemanticIndexStatus.stale.wireValue, 'stale');
    });
  });

  group('SemanticIndexInvalidationKeys', () {
    const baseKeys = SemanticIndexInvalidationKeys(
      documentId: 'doc://test.sty',
      revision: 3,
      workspaceGraphHash: 'abc123',
      toolchainId: 'styio-0.9.0',
      providerId: 'styio-service',
      protocolVersion: '1.0',
      semanticPayloadVersion: '2.0',
    );

    test('compositeKey includes all fields', () {
      expect(
        baseKeys.compositeKey,
        'doc://test.sty:3:abc123:styio-0.9.0:styio-service:1.0:2.0',
      );
    });

    test('matches returns true for identical keys', () {
      const same = SemanticIndexInvalidationKeys(
        documentId: 'doc://test.sty',
        revision: 3,
        workspaceGraphHash: 'abc123',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
        protocolVersion: '1.0',
        semanticPayloadVersion: '2.0',
      );
      expect(baseKeys.matches(same), isTrue);
    });

    test('matches returns false when any field differs', () {
      const diff = SemanticIndexInvalidationKeys(
        documentId: 'doc://test.sty',
        revision: 4, // different revision
        workspaceGraphHash: 'abc123',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
        protocolVersion: '1.0',
        semanticPayloadVersion: '2.0',
      );
      expect(baseKeys.matches(diff), isFalse);
    });

    test('equality operator works', () {
      const same = SemanticIndexInvalidationKeys(
        documentId: 'doc://test.sty',
        revision: 3,
        workspaceGraphHash: 'abc123',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
        protocolVersion: '1.0',
        semanticPayloadVersion: '2.0',
      );
      expect(baseKeys == same, isTrue);
      expect(baseKeys.hashCode == same.hashCode, isTrue);
    });
  });

  group('StyioSemanticCore - ready', () {
    const keys = SemanticIndexInvalidationKeys(
      documentId: 'doc://test.sty',
      revision: 1,
      workspaceGraphHash: 'abc',
      toolchainId: 'styio-0.9.0',
      providerId: 'styio-service',
      protocolVersion: '1.0',
      semanticPayloadVersion: '2.0',
    );

    test('ready core allows refactor and cross-file navigation', () {
      final core = StyioSemanticCore.ready(keys: keys);

      expect(core.status, SemanticIndexStatus.ready);
      expect(core.isRefactorReady, isTrue);
      expect(core.isCrossFileNavigationReady, isTrue);
      expect(core.refactorGate(), isNull);
      expect(core.crossFileNavigationGate(), isNull);
      expect(core.lastReadyKeys, isNotNull);
      expect(core.readyAt, isNotNull);
    });
  });

  group('StyioSemanticCore - degraded', () {
    const keys = SemanticIndexInvalidationKeys(
      documentId: 'doc://test.sty',
      revision: 1,
      workspaceGraphHash: 'abc',
      toolchainId: 'styio-0.9.0',
      providerId: 'styio-service',
      protocolVersion: '1.0',
      semanticPayloadVersion: '2.0',
    );

    test('degraded core allows refactor with reason but blocks cross-file', () {
      final core = StyioSemanticCore.evaluate(
        latestKeys: keys,
        lastReadyCore: null,
        upstreamDegradedReason: 'local fallback only',
      );

      expect(core.status, SemanticIndexStatus.degraded);
      expect(core.isRefactorReady, isTrue);

      final refactorGate = core.refactorGate();
      expect(refactorGate, isNotNull);
      expect(refactorGate!.status, SemanticIndexStatus.degraded);
      expect(refactorGate.message, contains('degraded'));
      expect(refactorGate.detail, isNotEmpty);

      expect(core.isCrossFileNavigationReady, isFalse);
      final navGate = core.crossFileNavigationGate();
      expect(navGate, isNotNull);
      expect(navGate!.status, SemanticIndexStatus.degraded);
      expect(navGate.message, contains('degraded'));
    });
  });

  group('StyioSemanticCore - blocked', () {
    const keys = SemanticIndexInvalidationKeys(
      documentId: 'doc://test.sty',
      revision: 1,
      workspaceGraphHash: 'abc',
      toolchainId: '',
      providerId: '',
      protocolVersion: '',
      semanticPayloadVersion: '',
    );

    test('blocked core denies all operations', () {
      final core = StyioSemanticCore.evaluate(
        latestKeys: keys,
        lastReadyCore: null,
        upstreamBlockedReason: 'toolchain not found',
      );

      expect(core.status, SemanticIndexStatus.blocked);
      expect(core.isRefactorReady, isFalse);
      expect(core.isCrossFileNavigationReady, isFalse);

      final refactorGate = core.refactorGate();
      expect(refactorGate, isNotNull);
      expect(refactorGate!.status, SemanticIndexStatus.blocked);
      expect(refactorGate.message, contains('blocked'));

      final navGate = core.crossFileNavigationGate();
      expect(navGate, isNotNull);
      expect(navGate!.status, SemanticIndexStatus.blocked);
      expect(navGate.message, contains('blocked'));
    });
  });

  group('StyioSemanticCore - stale', () {
    const oldKeys = SemanticIndexInvalidationKeys(
      documentId: 'doc://test.sty',
      revision: 1,
      workspaceGraphHash: 'abc',
      toolchainId: 'styio-0.9.0',
      providerId: 'styio-service',
      protocolVersion: '1.0',
      semanticPayloadVersion: '2.0',
    );

    const newKeys = SemanticIndexInvalidationKeys(
      documentId: 'doc://test.sty',
      revision: 2,
      workspaceGraphHash: 'abc',
      toolchainId: 'styio-0.9.0',
      providerId: 'styio-service',
      protocolVersion: '1.0',
      semanticPayloadVersion: '2.0',
    );

    test('stale core denies operations and preserves lastReadyKeys', () {
      final readyCore = StyioSemanticCore.ready(keys: oldKeys);

      final staleCore = StyioSemanticCore.evaluate(
        latestKeys: newKeys,
        lastReadyCore: readyCore,
      );

      expect(staleCore.status, SemanticIndexStatus.stale);
      expect(staleCore.isRefactorReady, isFalse);
      expect(staleCore.isCrossFileNavigationReady, isFalse);
      expect(staleCore.lastReadyKeys, isNotNull);
      expect(staleCore.lastReadyKeys!.revision, oldKeys.revision);

      final refactorGate = staleCore.refactorGate();
      expect(refactorGate, isNotNull);
      expect(refactorGate!.status, SemanticIndexStatus.stale);
      expect(refactorGate.message, contains('stale'));

      final navGate = staleCore.crossFileNavigationGate();
      expect(navGate, isNotNull);
      expect(navGate!.status, SemanticIndexStatus.stale);
      expect(navGate.message, contains('stale'));
    });

    test('evaluate returns ready when keys match lastReadyCore', () {
      final readyCore = StyioSemanticCore.ready(keys: oldKeys);

      // Same keys -> should stay ready
      const sameKeys = SemanticIndexInvalidationKeys(
        documentId: 'doc://test.sty',
        revision: 1,
        workspaceGraphHash: 'abc',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
        protocolVersion: '1.0',
        semanticPayloadVersion: '2.0',
      );

      final reReady = StyioSemanticCore.evaluate(
        latestKeys: sameKeys,
        lastReadyCore: readyCore,
      );

      expect(reReady.status, SemanticIndexStatus.ready);
    });
  });
}
