import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/editor_controller.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_capability_detector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_runtime.dart';

void main() {
  test('routed Styio language service exposes cached core facts to editor', () {
    const document = DocumentState(
      documentId: 'fixture://core-language-capabilities',
      text: '#main := (): string => {\n  main\n}\n',
      revision: 1,
    );
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://core-language-capabilities',
        revision: 1,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.warning,
            code: 'styio.demo',
            message: 'demo diagnostic',
            range: SourceRange(start: 1, end: 5),
          ),
        ],
        completions: <CompletionItem>[
          CompletionItem(
            label: 'main',
            kind: CompletionItemKind.function,
            insertText: 'main',
            detail: 'Styio function',
          ),
        ],
        hovers: <HoverPayload>[
          HoverPayload(
            range: SourceRange(start: 1, end: 5),
            markdown: '**main**',
          ),
        ],
        semanticSpans: <SemanticSpan>[
          SemanticSpan(
            range: SourceRange(start: 1, end: 5),
            kind: SemanticKind.function,
          ),
        ],
      ),
    );
    final controller = EditorSessionController(
      initialDocument: document,
      languageService: createRoutedStyioLanguageService(resultCache: cache),
    );

    controller.selectCollapsed(2);

    expect(controller.analysis.diagnostics.single.code, 'styio.demo');
    expect(controller.completionsAtSelection.single.label, 'main');
    expect(controller.hoverAtSelection!.markdown, '**main**');
    expect(controller.semanticKindAtSelection, SemanticKind.function);
  });

  test(
    'routed Styio language service derives semantic tokens from Styio symbols',
    () {
      const document = DocumentState(
        documentId: 'fixture://derived-semantic-tokens',
        text: '#main := (): string => {\n  main\n}\n',
        revision: 2,
      );
      final cache = StyioServiceResultCache();
      cache.store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://derived-semantic-tokens',
          revision: 2,
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'main',
              kind: SymbolKind.function,
              nameRange: SourceRange(start: 1, end: 5),
              declarationRange: SourceRange(start: 0, end: 24),
              detail: 'Styio function',
            ),
          ],
        ),
      );
      final service = createRoutedStyioLanguageService(resultCache: cache);

      final analysis = service.analyzeDocument(document);

      expect(
        analysis.semanticSpans
            .where(
              (span) =>
                  span.kind == SemanticKind.function &&
                  span.range.start == 1 &&
                  span.range.end == 5,
            )
            .length,
        1,
      );
    },
  );

  test(
    'capability detector treats successful empty diagnostics as syntax result',
    () {
      final snapshot = const StyioServiceCapabilityDetector().detect(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://syntax-clean',
          revision: 1,
        ),
        expectedCapabilities: const <StyioServiceCapability>[
          StyioServiceCapability.diagnostics,
          StyioServiceCapability.completion,
          StyioServiceCapability.hover,
          StyioServiceCapability.semanticTokens,
        ],
      );

      expect(
        snapshot.stateOf(StyioServiceCapability.diagnostics),
        StyioServiceCapabilityState.available,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.completion),
        StyioServiceCapabilityState.empty,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.hover),
        StyioServiceCapabilityState.empty,
      );
      expect(
        snapshot.stateOf(StyioServiceCapability.semanticTokens),
        StyioServiceCapabilityState.empty,
      );
      expect(
        snapshot.healthSummary.health,
        StyioServiceCapabilityHealth.degraded,
      );
      expect(snapshot.healthSummary.usableCount, 1);
      expect(
        snapshot.healthSummary.missingCapabilities,
        contains(StyioServiceCapability.completion),
      );
      expect(
        (snapshot.toJson()['healthSummary']! as Map<String, Object?>)['health'],
        'degraded',
      );
    },
  );
}
