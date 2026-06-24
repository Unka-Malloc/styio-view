import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  const document = DocumentState(
    documentId: 'fixture://capability-router',
    text: '#main := () => {}',
    revision: 1,
  );

  test('routes language service calls by requested capability', () {
    final registry = LanguageProviderRegistry<StyioLanguageService>()
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: const LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'completion-provider',
            displayName: 'Completion provider',
            priority: 10,
            capabilities: <String>{'completion'},
          ),
          provider: _CompletionService(),
        ),
      )
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: const LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'hover-provider',
            displayName: 'Hover provider',
            priority: 5,
            capabilities: <String>{'hover'},
          ),
          provider: _HoverService(),
        ),
      )
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'definition-provider',
            displayName: 'Definition provider',
            priority: 7,
            capabilities: <String>{StyioServiceCapability.definition.wireValue},
          ),
          provider: _DefinitionService(),
        ),
      );
    final service = CapabilityRoutedStyioLanguageService(
      registry: registry,
      fallback: const _FallbackService(),
    );

    expect(service.completeAt(document, 0).single.label, 'from-completion');
    expect(service.hoverAt(document, 0)?.markdown, 'from-hover');
    expect(service.definitionAt(document, 0)?.symbol.name, 'from-definition');
    expect(service.referencesAt(document, 0).single.name, 'fallback');
  });

  test('normalizes provider capability strings during routing', () {
    final registry = LanguageProviderRegistry<StyioLanguageService>()
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: const LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'completion-provider',
            displayName: 'Completion provider',
            priority: 10,
            capabilities: <String>{' Completion '},
          ),
          provider: _CompletionService(),
        ),
      );
    final service = CapabilityRoutedStyioLanguageService(
      registry: registry,
      fallback: const _FallbackService(),
    );

    expect(service.completeAt(document, 0).single.label, 'from-completion');
    expect(
      registry.providersFor('styio', capability: 'COMPLETION'),
      hasLength(1),
    );
  });

  test('normalizes provider capability separators during lookup', () {
    final registry = LanguageProviderRegistry<StyioLanguageService>()
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: const LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'semantic-provider',
            displayName: 'Semantic provider',
            priority: 10,
            capabilities: <String>{' semantic_tokens '},
          ),
          provider: _SemanticService(),
        ),
      );

    expect(
      registry.providersFor(
        'styio',
        capability: StyioServiceCapability.semanticTokens.wireValue,
      ),
      hasLength(1),
    );
    expect(
      registry.providersFor('styio', capability: 'semanticTokens'),
      hasLength(1),
    );
  });

  test('merges document analysis by capability', () {
    final registry = LanguageProviderRegistry<StyioLanguageService>()
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: const LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'diagnostic-provider',
            displayName: 'Diagnostic provider',
            priority: 10,
            capabilities: <String>{'diagnostics'},
          ),
          provider: _DiagnosticService(),
        ),
      )
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: const LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'semantic-provider',
            displayName: 'Semantic provider',
            priority: 10,
            capabilities: <String>{'semantic-tokens'},
          ),
          provider: _SemanticService(),
        ),
      );
    final service = CapabilityRoutedStyioLanguageService(
      registry: registry,
      fallback: const _FallbackService(),
    );

    final analysis = service.analyzeDocument(document);

    expect(analysis.diagnostics.single.code, 'routed.diagnostic');
    expect(analysis.semanticSpans.single.kind, SemanticKind.variable);
    expect(analysis.referenceSpans.single.name, 'fallback');
  });

  test('reuses provider analysis within a routed document analysis', () {
    final provider = _CountingAnalysisService();
    final registry = LanguageProviderRegistry<StyioLanguageService>()
      ..register(
        LanguageProviderRegistration<StyioLanguageService>(
          descriptor: LanguageProviderDescriptor(
            languageId: 'styio',
            providerId: 'multi-capability-provider',
            displayName: 'Multi capability provider',
            priority: 10,
            capabilities: <String>{
              StyioServiceCapability.analysis.wireValue,
              StyioServiceCapability.syntax.wireValue,
              'diagnostics',
              'semantic-tokens',
              'references',
            },
          ),
          provider: provider,
        ),
      );
    final service = CapabilityRoutedStyioLanguageService(
      registry: registry,
      fallback: const _FallbackService(),
    );

    final analysis = service.analyzeDocument(document);

    expect(provider.analysisCount, 1);
    expect(analysis.diagnostics.single.code, 'counted.diagnostic');
    expect(analysis.semanticSpans.single.kind, SemanticKind.variable);
    expect(analysis.referenceSpans.single.name, 'counted');
  });

  test('default routed service uses cached StyioService capabilities', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://capability-router',
        revision: 1,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.warning,
            code: 'styio.cached',
            message: 'Cached diagnostic',
            range: SourceRange(start: 0, end: 0),
          ),
        ],
        completions: <CompletionItem>[
          CompletionItem(
            label: 'cached-completion',
            kind: CompletionItemKind.variable,
            insertText: 'cachedCompletion',
          ),
        ],
        documentSymbols: <DocumentSymbol>[
          DocumentSymbol(
            name: 'cachedSymbol',
            kind: SymbolKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 10),
          ),
        ],
        referenceSpans: <ReferenceSpan>[
          ReferenceSpan(
            name: 'cachedSymbol',
            kind: SymbolKind.variable,
            range: SourceRange(start: 12, end: 17),
            targetRange: SourceRange(start: 0, end: 10),
          ),
        ],
      ),
    );
    final service = createRoutedStyioLanguageService(resultCache: cache);

    final analysis = service.analyzeDocument(document);

    expect(analysis.diagnostics.single.code, 'styio.cached');
    expect(service.completeAt(document, 0).single.label, 'cached-completion');
    expect(service.definitionAt(document, 12)?.symbol.name, 'cachedSymbol');
  });

  test('default routed project service uses cached document service facts', () {
    final cache = StyioServiceResultCache();
    cache.store(
      const StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://capability-router',
        revision: 1,
        diagnostics: <StyioServiceDiagnosticDto>[
          StyioServiceDiagnosticDto(
            severity: DiagnosticSeverity.warning,
            code: 'styio.project.cached',
            message: 'Cached project diagnostic',
            range: SourceRange(start: 0, end: 0),
          ),
        ],
      ),
    );
    final service = createRoutedProjectStyioLanguageService(resultCache: cache);

    final analysis = service.analyzeProject(<DocumentState>[document]);

    expect(
      analysis.documentAnalyses[document.documentId]!.diagnostics.map(
        (diagnostic) => diagnostic.code,
      ),
      contains('styio.project.cached'),
    );
  });

  test(
    'routes refactoring and surround capabilities through capability enum',
    () {
      final routes = <_RouteCase>[
        _RouteCase(
          capability: StyioServiceCapability.inlineVariable,
          invoke: (service) => service.inlineVariableAt(document, 0),
        ),
        _RouteCase(
          capability: StyioServiceCapability.introduceVariable,
          invoke: (service) => service.introduceVariable(
            document,
            const SourceRange(start: 0, end: 1),
            'nextValue',
          ),
        ),
        _RouteCase(
          capability: StyioServiceCapability.extractFunction,
          invoke: (service) => service.extractFunction(
            document,
            const SourceRange(start: 0, end: 1),
            'readValue',
          ),
        ),
        _RouteCase(
          capability: StyioServiceCapability.formatting,
          invoke: (service) => service.formatDocument(document),
        ),
        _RouteCase(
          capability: StyioServiceCapability.changeSignature,
          invoke: (service) => service.changeSignatureAt(
            document,
            0,
            newName: 'nextValue',
            parameters: const <ChangeSignatureParameterUpdate>[],
          ),
        ),
        _RouteCase(
          capability: StyioServiceCapability.inlayHints,
          invoke: (service) => service.inlayHints(document),
        ),
        _RouteCase(
          capability: StyioServiceCapability.codeActions,
          invoke: (service) => service.intentionsAt(document, 0),
        ),
        _RouteCase(
          capability: StyioServiceCapability.parameterInfo,
          invoke: (service) => service.parameterInfoAt(document, 0),
        ),
        _RouteCase(
          capability: StyioServiceCapability.codeActions,
          invoke: (service) => service.quickFixesForDiagnostic(
            document,
            const Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'route.diagnostic',
              message: 'Route diagnostic',
              range: SourceRange(start: 0, end: 1),
            ),
          ),
        ),
        _RouteCase(
          capability: StyioServiceCapability.rename,
          invoke: (service) => service.renameAt(document, 0, 'renamedValue'),
        ),
        _RouteCase(
          capability: StyioServiceCapability.safeDelete,
          invoke: (service) => service.safeDeleteAt(document, 0),
        ),
        _RouteCase(
          capability: StyioServiceCapability.surround,
          invoke: (service) => service.surroundTemplatesAt(
            document,
            const SourceRange(start: 0, end: 1),
          ),
        ),
      ];

      for (final route in routes) {
        final provider = _CapabilityTraceService();
        final fallback = _CapabilityTraceService();
        final registry = LanguageProviderRegistry<StyioLanguageService>()
          ..register(
            LanguageProviderRegistration<StyioLanguageService>(
              descriptor: LanguageProviderDescriptor(
                languageId: 'styio',
                providerId: '${route.capability.wireValue}-provider',
                displayName: '${route.capability.wireValue} provider',
                priority: 10,
                capabilities: <String>{route.capability.wireValue},
              ),
              provider: provider,
            ),
          );
        final service = CapabilityRoutedStyioLanguageService(
          registry: registry,
          fallback: fallback,
        );

        route.invoke(service);

        expect(provider.calls, contains(route.capability.wireValue));
        expect(fallback.calls, isEmpty);
      }
    },
  );
}

class _RouteCase {
  const _RouteCase({required this.capability, required this.invoke});

  final StyioServiceCapability capability;
  final void Function(StyioLanguageService service) invoke;
}

class _FallbackService implements StyioLanguageService {
  const _FallbackService();

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'fallback',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 0),
          targetRange: SourceRange(start: 0, end: 0),
        ),
      ],
    );
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    return const <CompletionItem>[
      CompletionItem(
        label: 'fallback',
        kind: CompletionItemKind.keyword,
        insertText: 'fallback',
      ),
    ];
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) => null;

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) => null;

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    return const <FormattingEdit>[];
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) => null;

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) => null;

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    return const <InlayHint>[];
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    return null;
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    return const <DiagnosticQuickFix>[];
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) => null;

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    return null;
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return const <DiagnosticQuickFix>[];
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    return const <ReferenceSpan>[
      ReferenceSpan(
        name: 'fallback',
        kind: SymbolKind.variable,
        range: SourceRange(start: 0, end: 0),
        targetRange: SourceRange(start: 0, end: 0),
      ),
    ];
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    return null;
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) => null;

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    return const <SurroundTemplate>[];
  }
}

class _CompletionService extends _FallbackService {
  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    return const <CompletionItem>[
      CompletionItem(
        label: 'from-completion',
        kind: CompletionItemKind.variable,
        insertText: 'fromCompletion',
      ),
    ];
  }
}

class _HoverService extends _FallbackService {
  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    return const HoverPayload(
      range: SourceRange(start: 0, end: 0),
      markdown: 'from-hover',
    );
  }
}

class _DefinitionService extends _FallbackService {
  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    return const DefinitionTarget(
      symbol: DocumentSymbol(
        name: 'from-definition',
        kind: SymbolKind.variable,
        nameRange: SourceRange(start: 0, end: 0),
        declarationRange: SourceRange(start: 0, end: 0),
      ),
      originRange: SourceRange(start: 0, end: 0),
    );
  }
}

class _DiagnosticService extends _FallbackService {
  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final base = super.analyzeDocument(document);
    return StyioDocumentAnalysis(
      tokenSpans: base.tokenSpans,
      semanticSpans: base.semanticSpans,
      diagnostics: const <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'routed.diagnostic',
          message: 'Routed diagnostic',
          range: SourceRange(start: 0, end: 0),
        ),
      ],
      formattingEdits: base.formattingEdits,
      semanticBlocks: base.semanticBlocks,
      inlayHints: base.inlayHints,
      documentSymbols: base.documentSymbols,
      referenceSpans: base.referenceSpans,
    );
  }
}

class _SemanticService extends _FallbackService {
  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final base = super.analyzeDocument(document);
    return StyioDocumentAnalysis(
      tokenSpans: base.tokenSpans,
      semanticSpans: const <SemanticSpan>[
        SemanticSpan(
          range: SourceRange(start: 0, end: 1),
          kind: SemanticKind.variable,
        ),
      ],
      diagnostics: base.diagnostics,
      formattingEdits: base.formattingEdits,
      semanticBlocks: base.semanticBlocks,
      inlayHints: base.inlayHints,
      documentSymbols: base.documentSymbols,
      referenceSpans: base.referenceSpans,
    );
  }
}

class _CountingAnalysisService extends _FallbackService {
  int analysisCount = 0;

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    analysisCount += 1;
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[
        SemanticSpan(
          range: SourceRange(start: 0, end: 1),
          kind: SemanticKind.variable,
        ),
      ],
      diagnostics: <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'counted.diagnostic',
          message: 'Counted diagnostic',
          range: SourceRange(start: 0, end: 0),
        ),
      ],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'counted',
          kind: SymbolKind.variable,
          range: SourceRange(start: 0, end: 0),
          targetRange: SourceRange(start: 0, end: 0),
        ),
      ],
    );
  }
}

class _CapabilityTraceService extends _FallbackService {
  final calls = <String>[];

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    calls.add(StyioServiceCapability.inlineVariable.wireValue);
    return super.inlineVariableAt(document, offset);
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    calls.add(StyioServiceCapability.introduceVariable.wireValue);
    return super.introduceVariable(document, range, name);
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    calls.add(StyioServiceCapability.extractFunction.wireValue);
    return super.extractFunction(document, range, name);
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    calls.add(StyioServiceCapability.formatting.wireValue);
    return super.formatDocument(document);
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    calls.add(StyioServiceCapability.changeSignature.wireValue);
    return super.changeSignatureAt(
      document,
      offset,
      newName: newName,
      parameters: parameters,
    );
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    calls.add(StyioServiceCapability.inlayHints.wireValue);
    return super.inlayHints(document);
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    calls.add(StyioServiceCapability.codeActions.wireValue);
    return super.intentionsAt(document, offset);
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    calls.add(StyioServiceCapability.parameterInfo.wireValue);
    return super.parameterInfoAt(document, offset);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    calls.add(StyioServiceCapability.codeActions.wireValue);
    return super.quickFixesForDiagnostic(document, diagnostic);
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    calls.add(StyioServiceCapability.rename.wireValue);
    return super.renameAt(document, offset, newName);
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    calls.add(StyioServiceCapability.safeDelete.wireValue);
    return super.safeDeleteAt(document, offset);
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    calls.add(StyioServiceCapability.surround.wireValue);
    return super.surroundTemplatesAt(document, range);
  }
}
