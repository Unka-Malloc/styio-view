import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_provider.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';

void main() {
  test('semantic snapshot provider prefers StyioService analysis facts', () {
    const document = DocumentState(
      documentId: 'fixture://semantic-provider-service',
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://semantic-provider-service',
        revision: 1,
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'value',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 10),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'value',
            kind: SymbolKind.variable,
            range: SourceRange(start: 11, end: 16),
            targetRange: SourceRange(start: 0, end: 5),
            access: ReferenceAccess.read,
          ),
        ],
      ),
    );
    final provider = SemanticSnapshotProvider(
      languageService: CachedStyioLanguageService(
        cache: cache,
        allowLocalFallback: false,
      ),
    );

    final result = provider.snapshotFor(document);

    expect(result.source, SemanticSnapshotProviderSource.serviceAnalysis);
    expect(result.usedFallback, isFalse);
    expect(result.snapshot.elements.single.name, 'value');
    expect(result.snapshot.references, hasLength(2));
    expect(result.snapshot.referenceAt(11)?.target.name, 'value');
    expect(result.toJson()['source'], 'service-analysis');
  });

  test(
    'semantic snapshot provider falls back when service has no semantic facts',
    () {
      const document = DocumentState(
        documentId: 'fixture://semantic-provider-fallback',
        text: 'value := 1\nvalue\n',
        revision: 1,
      );
      final provider = SemanticSnapshotProvider(
        languageService: CachedStyioLanguageService(
          cache: StyioServiceResultCache(),
          allowLocalFallback: false,
        ),
      );

      final result = provider.snapshotFor(document);

      expect(
        result.source,
        SemanticSnapshotProviderSource.localBuilderFallback,
      );
      expect(result.usedFallback, isTrue);
      expect(result.message, startsWith('TODO:'));
      expect(result.snapshot.elements.map((element) => element.name), [
        'value',
      ]);
      expect(result.snapshot.references, hasLength(2));
      expect(result.toJson()['usedFallback'], isTrue);
    },
  );
}
