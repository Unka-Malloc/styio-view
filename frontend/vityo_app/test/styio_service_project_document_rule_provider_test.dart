import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  test('serves project rule facts from fresh StyioService cache response', () {
    const document = DocumentState(
      documentId: 'fixture://styio-service-project-rules',
      text: 'value = 1\nvalue\n',
      revision: 2,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://styio-service-project-rules',
          revision: 2,
          toolchainId: 'styio-nightly',
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'styio.service.project',
              message: 'Project fact from StyioService',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
          documentSymbols: <DocumentSymbol>[
            DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 9),
            ),
          ],
          referenceSpans: <ReferenceSpan>[
            ReferenceSpan(
              name: 'value',
              kind: SymbolKind.variable,
              range: SourceRange(start: 10, end: 15),
              targetRange: SourceRange(start: 0, end: 5),
            ),
          ],
          codeActions: <DiagnosticQuickFix>[
            DiagnosticQuickFix(
              label: 'Apply StyioService fix',
              edits: <FormattingEdit>[
                FormattingEdit(
                  range: SourceRange(start: 0, end: 5),
                  newText: 'nextValue',
                ),
              ],
            ),
          ],
        ),
      );
    final provider = StyioServiceProjectDocumentRuleProvider(cache: cache);

    final analysis = provider.analysisFactsFor(document);
    final fixes = provider.quickFixesForDiagnostic(
      document,
      analysis.diagnostics.single,
    );

    expect(analysis.diagnostics.single.code, 'styio.service.project');
    expect(analysis.documentSymbols.single.name, 'value');
    expect(analysis.referenceSpans.single.name, 'value');
    expect(fixes.single.label, 'Apply StyioService fix');
  });

  test('ignores stale StyioService project rule responses', () {
    const document = DocumentState(
      documentId: 'fixture://stale',
      text: 'value = 1\n',
      revision: 2,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://stale',
          revision: 1,
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'stale',
              message: 'Stale response',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
        ),
      );
    final provider = StyioServiceProjectDocumentRuleProvider(cache: cache);

    final analysis = provider.analysisFactsFor(document);

    expect(analysis.diagnostics, isEmpty);
  });

  test('resolves project rule facts from exact configuration context', () {
    const document = DocumentState(
      documentId: 'fixture://contextual-project-rules',
      text: 'value = 1\nvalue\n',
      revision: 3,
    );
    final cache = StyioServiceResultCache()
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://contextual-project-rules',
          revision: 3,
          configPath: '/workspace/a/styio.toml',
          workingDirectory: '/workspace/a',
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'styio.context.a',
              message: 'Context A',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
        ),
      )
      ..store(
        const StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: 'fixture://contextual-project-rules',
          revision: 3,
          configPath: '/workspace/b/styio.toml',
          workingDirectory: '/workspace/b',
          diagnostics: <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'styio.context.b',
              message: 'Context B',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
        ),
      );
    final provider = StyioServiceProjectDocumentRuleProvider(
      cache: cache,
      configPath: '/workspace/b/styio.toml',
      workingDirectory: '/workspace/b',
    );

    final diagnostics = provider.diagnosticsFor(document);

    expect(diagnostics.single.code, 'styio.context.b');
  });
}
