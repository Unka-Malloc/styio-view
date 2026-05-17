import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/language_service_configuration.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_runtime.dart';

void main() {
  test('cached Styio language service resolves exact project context', () {
    const document = DocumentState(
      documentId: 'fixture://context-bound-cache',
      text: 'value = 1\nvalue\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://context-bound-cache',
        revision: 1,
        configPath: '/workspace/a/styio.toml',
        workingDirectory: '/workspace/a',
        completions: <CompletionItem>[
          CompletionItem(
            label: 'fromA',
            kind: CompletionItemKind.variable,
            insertText: 'fromA',
          ),
        ],
      ),
    );
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://context-bound-cache',
        revision: 1,
        configPath: '/workspace/b/styio.toml',
        workingDirectory: '/workspace/b',
        completions: <CompletionItem>[
          CompletionItem(
            label: 'fromB',
            kind: CompletionItemKind.variable,
            insertText: 'fromB',
          ),
        ],
      ),
    );
    final service = CachedStyioLanguageService(
      cache: cache,
      configPath: '/workspace/a/styio.toml',
      workingDirectory: '/workspace/a',
    );

    final completions = service.completeAt(document, document.length);

    expect(completions.single.label, 'fromA');
  });

  test(
    'routed Styio language service passes project context to cache lookup',
    () {
      const document = DocumentState(
        documentId: 'fixture://routed-context-bound-cache',
        text: 'value = 1\nvalue\n',
        revision: 1,
      );
      final cache = StyioServiceResultCache();
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://routed-context-bound-cache',
          revision: 1,
          configPath: '/workspace/styio.toml',
          workingDirectory: '/workspace',
          hovers: <HoverPayload>[
            HoverPayload(
              range: SourceRange(start: 0, end: 5),
              markdown: '**workspace value**',
            ),
          ],
        ),
      );

      final service = createRoutedStyioLanguageService(
        resultCache: cache,
        configPath: '/workspace/styio.toml',
        workingDirectory: '/workspace',
      );

      expect(service.hoverAt(document, 1)!.markdown, '**workspace value**');
    },
  );

  test('routed Styio language service can disable local fallback', () {
    const document = DocumentState(
      documentId: 'fixture://routed-strict-service',
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
    final service = createRoutedStyioLanguageService(
      resultCache: StyioServiceResultCache(),
      allowLocalFallback: false,
    );

    expect(service.completeAt(document, document.length), isEmpty);
    expect(service.hoverAt(document, 1), isNull);
    expect(service.referencesAt(document, 1), isEmpty);
  });

  test(
    'routed Styio language service reads fallback mode from configuration',
    () {
      const document = DocumentState(
        documentId: 'fixture://routed-configured-strict-service',
        text: 'value := 1\nvalue\n',
        revision: 1,
      );
      final service = createRoutedStyioLanguageService(
        resultCache: StyioServiceResultCache(),
        languageServiceConfiguration: const LanguageServiceConfiguration(
          allowLocalFallback: false,
        ),
      );

      expect(service.completeAt(document, document.length), isEmpty);
      expect(service.hoverAt(document, 1), isNull);
    },
  );

  test('routed project Styio language service can disable local fallback', () {
    const document = DocumentState(
      documentId: 'fixture://routed-project-strict-service',
      text: 'value := 1\nvalue\n',
      revision: 1,
    );
    final service = createRoutedProjectStyioLanguageService(
      resultCache: StyioServiceResultCache(),
      allowLocalFallback: false,
    );

    final analysis = service.analyzeProject(const <DocumentState>[document]);
    final documentAnalysis = analysis.documentAnalyses[document.documentId]!;

    expect(documentAnalysis.documentSymbols, isEmpty);
    expect(documentAnalysis.referenceSpans, isEmpty);
  });

  test(
    'routed project Styio language service reads fallback mode from configuration',
    () {
      const document = DocumentState(
        documentId: 'fixture://routed-project-configured-strict-service',
        text: 'value := 1\nvalue\n',
        revision: 1,
      );
      final service = createRoutedProjectStyioLanguageService(
        resultCache: StyioServiceResultCache(),
        languageServiceConfiguration: const LanguageServiceConfiguration(
          allowLocalFallback: false,
        ),
      );

      final analysis = service.analyzeProject(const <DocumentState>[document]);
      final documentAnalysis = analysis.documentAnalyses[document.documentId]!;

      expect(documentAnalysis.documentSymbols, isEmpty);
      expect(documentAnalysis.referenceSpans, isEmpty);
    },
  );

  test(
    'routed project Styio language service strict mode uses service facts',
    () {
      const document = DocumentState(
        documentId: 'fixture://routed-project-strict-service-facts',
        text: 'value := 1\nvalue\n',
        revision: 1,
      );
      final cache = StyioServiceResultCache();
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://routed-project-strict-service-facts',
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
            ),
          ],
        ),
      );
      final service = createRoutedProjectStyioLanguageService(
        resultCache: cache,
        allowLocalFallback: false,
      );

      final analysis = service.analyzeProject(const <DocumentState>[document]);
      final documentAnalysis = analysis.documentAnalyses[document.documentId]!;

      expect(documentAnalysis.documentSymbols.single.name, 'value');
      expect(documentAnalysis.referenceSpans, hasLength(2));
    },
  );
}
