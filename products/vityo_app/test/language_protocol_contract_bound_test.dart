import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/cache/cache.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';

void main() {
  group('StyioServiceResultCacheKey revision binding', () {
    test('cache key binds documentId, revision, and protocolVersion', () {
      const key = StyioServiceResultCacheKey(
        documentId: 'doc://test.sty', revision: 5,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      expect(key.documentId, 'doc://test.sty');
      expect(key.revision, 5);
      expect(key.protocolVersion, 'styio-cli-jsonl-v1');
    });

    test('different revision yields unequal cache key', () {
      const keyV3 = StyioServiceResultCacheKey(
        documentId: 'doc://test.sty', revision: 3,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      const keyV5 = StyioServiceResultCacheKey(
        documentId: 'doc://test.sty', revision: 5,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      expect(keyV3 == keyV5, isFalse);
    });

    test('different protocol version yields unequal cache key', () {
      const keyV1 = StyioServiceResultCacheKey(
        documentId: 'doc://test.sty', revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      const keyV2 = StyioServiceResultCacheKey(
        documentId: 'doc://test.sty', revision: 1,
        protocolVersion: 'styio-cli-jsonl-v2',
      );
      expect(keyV1 == keyV2, isFalse);
    });

    test('cache lookup misses on stale revision', () {
      final cache = StyioServiceResultCache();
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'doc://test.sty', revision: 5,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      cache.store(response, toolchainId: 'styio-nightly');
      final miss = cache.lookupDocument(
        documentId: 'doc://test.sty', revision: 3,
        protocolVersion: 'styio-cli-jsonl-v1',
        toolchainId: 'styio-nightly',
      );
      expect(miss, isNull);
      final hit = cache.lookupDocument(
        documentId: 'doc://test.sty', revision: 5,
        protocolVersion: 'styio-cli-jsonl-v1',
        toolchainId: 'styio-nightly',
      );
      expect(hit, isNotNull);
      expect(hit!.revision, 5);
    });

    test('cache lookup misses on protocol version mismatch', () {
      final cache = StyioServiceResultCache();
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'doc://test.sty', revision: 1,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      cache.store(response);
      final miss = cache.lookupDocument(
        documentId: 'doc://test.sty', revision: 1,
        protocolVersion: 'styio-service-v2',
      );
      expect(miss, isNull);
    });

    test('cache lookup matches with identical protocol version', () {
      final cache = StyioServiceResultCache();
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'doc://match.sty', revision: 2,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      cache.store(response);
      final hit = cache.lookupDocument(
        documentId: 'doc://match.sty', revision: 2,
        protocolVersion: 'styio-cli-jsonl-v1',
      );
      expect(hit, isNotNull);
    });
  });

  group('SemanticSnapshot cache key', () {
    test('cacheKey includes revision-bound fields', () {
      const snapshot = SemanticSnapshot(
        documentId: 'doc://test.sty', revision: 7,
        tokens: <TokenSpan>[], elements: <ResolvedElement>[],
        references: <ResolvedReference>[],
        workspaceGraphHash: 'abc', toolchainId: 'styio-0.9.0',
        providerId: 'styio-service', protocolVersion: '1.0',
        semanticPayloadVersion: '2.0',
      );
      expect(snapshot.cacheKey,
        'doc://test.sty:7:abc:styio-0.9.0:styio-service:1.0:2.0');
    });
  });

  group('LanguageCacheEntry composite key', () {
    test('key includes revision-bound fields', () {
      final entry = LanguageCacheEntry<String>(
        value: 'test', documentId: 'doc://t.sty', revision: 3,
        workspaceGraphHash: 'abc', toolchainId: 'styio-nightly',
        providerId: 'styio-service',
        protocolVersion: 'styio-facts-v1',
        semanticPayloadVersion: 'payload-v1',
        cachedAt: DateTime(2026),
      );
      expect(entry.compositeKey,
        'doc://t.sty:3:abc:styio-nightly:styio-service:styio-facts-v1:payload-v1');
    });
  });

  group('Unknown-field tolerant decode', () {
    const protocol = StyioCliJsonlProtocol();
    test('ignores unknown fields in JSONL records', () {
      const doc = StyioServiceDocument(
        documentId: 'doc://t', text: '', revision: 1);
      final r = protocol.decode(document: doc,
        stdout: jsonEncode(<String, Object?>{
          'record': 'diagnostic',
          'severity': 'error', 'code': 't.code',
          'message': 't', 'range': {'start': 0, 'end': 5},
          'unknownX': 'ignore', 'extraY': 42,
        }), stderr: '', exitCode: 0,
        toolchainSucceeded: true);
      expect(r.diagnostics, hasLength(1));
      expect(r.diagnostics.first.code, 't.code');
    });

    test('skips malformed records with missing range', () {
      const doc = StyioServiceDocument(
        documentId: 'doc://t', text: '', revision: 1);
      final r = protocol.decode(document: doc,
        stdout: jsonEncode(<String, Object?>{
          'record': 'diagnostic', 'severity': 'error',
          'code': 'no.range', 'message': 'miss'}),
        stderr: '', exitCode: 0,
        toolchainSucceeded: true);
      expect(r.diagnostics, isEmpty);
    });

    test('tolerates non-JSON lines', () {
      final r = protocol.decode(
        document: const StyioServiceDocument(
          documentId: 'doc://t', text: '', revision: 1),
        stdout: 'bad\n{"record":"diagnostic","severity":"error","code":"r","message":"m","range":{"start":0,"end":1}}\nbad2',
        stderr: '', exitCode: 0, toolchainSucceeded: true);
      expect(r.diagnostics, hasLength(1));
      expect(r.diagnostics.first.code, 'r');
    });
  });

  group('StyioServiceResultCacheEntry fromJson tolerance', () {
    test('extra unknown fields are ignored', () {
      final e = StyioServiceResultCacheEntry.fromJson(<String, Object?>{
        'documentId': 'x', 'revision': 1, 'protocolVersion': 'v1',
        'toolchainId': 't', 'status': 'succeeded',
        'diagnosticCount': 0, 'completionCount': 0, 'hoverCount': 0,
        'semanticSpanCount': 0, 'formattingEditCount': 0,
        'semanticBlockCount': 0, 'inlayHintCount': 0,
        'documentSymbolCount': 0, 'referenceSpanCount': 0,
        'definitionTargetCount': 0, 'codeActionCount': 0,
        'renamePlanCount': 0, 'safeDeletePlanCount': 0,
        'inlineVariablePlanCount': 0, 'introduceVariablePlanCount': 0,
        'extractFunctionPlanCount': 0, 'changeSignaturePlanCount': 0,
        'parameterInfoCount': 0, 'surroundTemplateCount': 0,
        'unknownExtra': 'ok', 'another': 99,
      });
      expect(e.documentId, 'x');
      expect(e.protocolVersion, 'v1');
    });
  });

  group('StyioDocumentAnalysis capability gaps', () {
    test('analysis carries capability gaps', () {
      const a = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
        capabilityGaps: <AnalysisCapabilityGap>[
          AnalysisCapabilityGap(
            capabilityId: 'language.completion',
            reason: 'provider blocked',
            detail: 'Styio service unavailable',
            resolution: 'Install styio CLI',
          ),
        ],
      );
      expect(a.capabilityGaps, hasLength(1));
      expect(a.capabilityGaps.first.capabilityId, 'language.completion');
      expect(a.capabilityGaps.first.reason, 'provider blocked');
    });

    test('analysis defaults to empty gaps', () {
      const a = StyioDocumentAnalysis(
        tokenSpans: <TokenSpan>[],
        semanticSpans: <SemanticSpan>[],
        diagnostics: <Diagnostic>[],
        formattingEdits: <FormattingEdit>[],
        semanticBlocks: <SemanticBlockRange>[],
        inlayHints: <InlayHint>[],
        documentSymbols: <DocumentSymbol>[],
        referenceSpans: <ReferenceSpan>[],
      );
      expect(a.capabilityGaps, isEmpty);
    });
  });
}
