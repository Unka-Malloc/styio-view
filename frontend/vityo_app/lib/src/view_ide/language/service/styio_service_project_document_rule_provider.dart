import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import 'project_document_rule_provider.dart';
import 'styio_service_connector.dart';

class StyioServiceProjectDocumentRuleProvider
    implements ProjectDocumentRuleProvider {
  const StyioServiceProjectDocumentRuleProvider({
    required StyioServiceResultCache cache,
    this.protocolVersion = 'styio-cli-jsonl-v1',
    this.toolchainId = '',
    this.configPath,
    this.workingDirectory,
  }) : _cache = cache;

  final StyioServiceResultCache _cache;
  final String protocolVersion;
  final String toolchainId;
  final String? configPath;
  final String? workingDirectory;

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    final response = _cachedResponse(document);
    if (response == null || !response.succeeded || response.isStaleFor(document)) {
      return _emptyAnalysis;
    }
    return StyioDocumentAnalysis(
      tokenSpans: const <TokenSpan>[],
      semanticSpans: response.semanticSpans,
      diagnostics: _diagnosticsFromResponse(response),
      formattingEdits: response.formattingEdits,
      semanticBlocks: response.semanticBlocks,
      inlayHints: response.inlayHints,
      documentSymbols: response.documentSymbols,
      referenceSpans: response.referenceSpans,
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    final response = _cachedResponse(document);
    if (response == null || !response.succeeded || response.isStaleFor(document)) {
      return const <Diagnostic>[];
    }
    return _diagnosticsFromResponse(response);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final response = _cachedResponse(document);
    if (response == null || !response.succeeded || response.isStaleFor(document)) {
      return const <DiagnosticQuickFix>[];
    }
    return response.codeActions
        .where(
          (action) =>
              action.edits.isEmpty ||
              action.edits.any(
                (edit) => edit.range.intersects(diagnostic.range),
              ),
        )
        .toList(growable: false);
  }

  StyioServiceResponse? _cachedResponse(DocumentState document) {
    return _cache.lookupDocument(
      documentId: document.documentId,
      revision: document.revision,
      protocolVersion: protocolVersion,
      toolchainId: toolchainId,
      configPath: configPath,
      workingDirectory: workingDirectory,
    );
  }

  List<Diagnostic> _diagnosticsFromResponse(StyioServiceResponse response) {
    return [
      for (final diagnostic in response.diagnostics)
        Diagnostic(
          severity: diagnostic.severity,
          code: diagnostic.code,
          message: diagnostic.message,
          range: diagnostic.range,
        ),
    ];
  }
}

const _emptyAnalysis = StyioDocumentAnalysis(
  tokenSpans: <TokenSpan>[],
  semanticSpans: <SemanticSpan>[],
  diagnostics: <Diagnostic>[],
  formattingEdits: <FormattingEdit>[],
  semanticBlocks: <SemanticBlockRange>[],
  inlayHints: <InlayHint>[],
  documentSymbols: <DocumentSymbol>[],
  referenceSpans: <ReferenceSpan>[],
);
