import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../features/styio_completion_feature.dart';
import '../features/styio_formatting_feature.dart';
import '../features/styio_hover_feature.dart';
import '../features/styio_inlay_hint_feature.dart';
import '../features/styio_navigation_feature.dart';
import '../features/styio_parameter_info_feature.dart';
import '../features/styio_refactor_feature.dart';
import '../features/styio_semantic_token_feature.dart';
import '../features/styio_syntax_diagnostic_feature.dart';
import 'language_service_foundation.dart';
import 'styio_language_service.dart';

class LocalStyioLanguageService implements StyioLanguageService {
  const LocalStyioLanguageService({
    this.snapshotBuilder = const SemanticSnapshotBuilder(),
    this.completionFeature = const StyioCompletionFeature(),
    this.formattingFeature = const StyioFormattingFeature(),
    this.hoverFeature = const StyioHoverFeature(),
    this.inlayHintFeature = const StyioInlayHintFeature(),
    this.navigationFeature = const StyioNavigationFeature(),
    this.parameterInfoFeature = const StyioParameterInfoFeature(),
    this.refactorFeature = const StyioRefactorFeature(),
    this.semanticTokenFeature = const StyioSemanticTokenFeature(),
    this.syntaxDiagnosticFeature = const StyioSyntaxDiagnosticFeature(),
  });

  final SemanticSnapshotBuilder snapshotBuilder;
  final StyioCompletionFeature completionFeature;
  final StyioFormattingFeature formattingFeature;
  final StyioHoverFeature hoverFeature;
  final StyioInlayHintFeature inlayHintFeature;
  final StyioNavigationFeature navigationFeature;
  final StyioParameterInfoFeature parameterInfoFeature;
  final StyioRefactorFeature refactorFeature;
  final StyioSemanticTokenFeature semanticTokenFeature;
  final StyioSyntaxDiagnosticFeature syntaxDiagnosticFeature;

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final snapshot = _safeSnapshot(document);
    final tokens = snapshot?.tokens ?? _safeTokenize(document);
    return StyioDocumentAnalysis(
      tokenSpans: tokens,
      semanticSpans: snapshot == null
          ? const <SemanticSpan>[]
          : _safeList(
              () => semanticTokenFeature.semanticSpans(snapshot: snapshot),
            ),
      diagnostics: _safeList(() => _diagnostics(document, tokens)),
      formattingEdits: _safeList(() => formattingFeature.formatDocument(document)),
      semanticBlocks: snapshot == null
          ? const <SemanticBlockRange>[]
          : _semanticBlocks(snapshot),
      inlayHints: snapshot == null
          ? const <InlayHint>[]
          : _safeList(
              () => inlayHintFeature.inlayHints(
                document: document,
                snapshot: snapshot,
              ),
            ),
      documentSymbols: snapshot == null
          ? const <DocumentSymbol>[]
          : snapshot.elements.map(_documentSymbol).toList(growable: false),
      referenceSpans: snapshot == null
          ? const <ReferenceSpan>[]
          : snapshot.references.map(_referenceSpan).toList(growable: false),
    );
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    return formattingFeature.formatDocument(document);
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    final snapshot = snapshotBuilder.build(document);
    return inlayHintFeature.inlayHints(document: document, snapshot: snapshot);
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    final snapshot = snapshotBuilder.build(document);
    return completionFeature.completeAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    return const <SurroundTemplate>[
      SurroundTemplate(
        id: 'styio.block',
        label: 'Block',
        openingLine: '{',
        closingLine: '}',
        detail: 'Wrap selection in a Styio block.',
      ),
      SurroundTemplate(
        id: 'styio.group',
        label: 'Group',
        openingLine: '(',
        closingLine: ')',
        detail: 'Wrap selection in a grouped expression.',
      ),
    ];
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    final snapshot = snapshotBuilder.build(document);
    return hoverFeature.hoverAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    final snapshot = snapshotBuilder.build(document);
    return navigationFeature.definitionAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    final snapshot = snapshotBuilder.build(document);
    return navigationFeature.referencesAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    final snapshot = snapshotBuilder.build(document);
    return navigationFeature.renameAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
      newName: newName,
    );
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    final snapshot = snapshotBuilder.build(document);
    return refactorFeature.safeDeleteAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    final snapshot = snapshotBuilder.build(document);
    return refactorFeature.inlineVariableAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
    );
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return refactorFeature.introduceVariable(
      document: document,
      range: range,
      name: name,
    );
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return refactorFeature.extractFunction(
      document: document,
      range: range,
      name: name,
    );
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    final snapshot = snapshotBuilder.build(document);
    return refactorFeature.changeSignatureAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
      newName: newName,
      parameters: parameters,
    );
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    return parameterInfoFeature.parameterInfoAt(
      document: document,
      offset: offset,
    );
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    final intentions = <DiagnosticQuickFix>[];
    for (final diagnostic in _diagnostics(document)) {
      if (_contains(diagnostic.range, offset)) {
        intentions.addAll(quickFixesForDiagnostic(document, diagnostic));
      }
    }

    final formatAction = formattingFeature.formatDocumentAction(document);
    if (formatAction != null) {
      intentions.add(formatAction);
    }
    return intentions;
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return syntaxDiagnosticFeature.quickFixesForDiagnostic(
      document: document,
      diagnostic: diagnostic,
    );
  }

  SemanticSnapshot? _safeSnapshot(DocumentState document) {
    try {
      return snapshotBuilder.build(document);
    } on Object {
      return null;
    }
  }

  List<TokenSpan> _safeTokenize(DocumentState document) {
    try {
      return snapshotBuilder.syntaxHighlighter.tokenize(document.text);
    } on Object {
      return const <TokenSpan>[];
    }
  }

  List<T> _safeList<T>(List<T> Function() create) {
    try {
      return create();
    } on Object {
      return <T>[];
    }
  }

  List<Diagnostic> _diagnostics(
    DocumentState document, [
    List<TokenSpan>? tokens,
  ]) {
    final tokenSpans =
        tokens ?? snapshotBuilder.syntaxHighlighter.tokenize(document.text);
    return syntaxDiagnosticFeature.diagnosticsFor(
      document: document,
      tokens: tokenSpans,
    );
  }

  List<SemanticBlockRange> _semanticBlocks(SemanticSnapshot snapshot) {
    return snapshot.elements
        .where((element) => element.kind == ResolvedElementKind.function)
        .map(
          (element) => SemanticBlockRange(
            range: _semanticBlockRangeForElement(snapshot, element),
            label: element.name,
          ),
        )
        .toList(growable: false);
  }

  SourceRange _semanticBlockRangeForElement(
    SemanticSnapshot snapshot,
    ResolvedElement element,
  ) {
    final openingBraceIndex = _matchingTokenIndex(
      snapshot.tokens,
      startOffset: element.declarationRange.start,
      lexeme: '{',
    );
    if (openingBraceIndex == null) {
      return element.declarationRange;
    }

    var depth = 0;
    for (var index = openingBraceIndex; index < snapshot.tokens.length; index += 1) {
      final token = snapshot.tokens[index];
      if (token.lexeme == '{') {
        depth += 1;
        continue;
      }
      if (token.lexeme != '}') {
        continue;
      }
      depth -= 1;
      if (depth == 0) {
        return SourceRange(
          start: element.declarationRange.start,
          end: token.range.end,
        );
      }
    }

    return element.declarationRange;
  }

  int? _matchingTokenIndex(
    List<TokenSpan> tokens, {
    required int startOffset,
    required String lexeme,
  }) {
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.range.start < startOffset) {
        continue;
      }
      if (token.lexeme == lexeme) {
        return index;
      }
      if (token.lexeme == '\n' || token.range.start > startOffset + 4096) {
        return null;
      }
    }
    return null;
  }

  DocumentSymbol _documentSymbol(ResolvedElement element) {
    return DocumentSymbol(
      name: element.name,
      kind: symbolKindFromResolvedElementKind(element.kind),
      nameRange: element.nameRange,
      declarationRange: element.declarationRange,
      detail: element.detail ?? '',
      documentation: element.documentation ?? '',
    );
  }

  ReferenceSpan _referenceSpan(ResolvedReference reference) {
    return ReferenceSpan(
      name: reference.name,
      kind: symbolKindFromResolvedElementKind(reference.target.kind),
      range: reference.range,
      targetRange: reference.target.nameRange,
      isDeclaration: reference.isDeclaration,
      access: referenceAccessFromResolvedReferenceAccess(reference.access),
    );
  }

  bool _contains(SourceRange range, int offset) {
    return range.contains(offset);
  }
}
