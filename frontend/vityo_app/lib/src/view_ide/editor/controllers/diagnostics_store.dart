import '../../language/language_contract.dart';
import 'editor_owned_controller.dart';

class DiagnosticsStore extends EditorOwnedController {
  DiagnosticsStore({required int documentLength})
    : _documentLength = documentLength;

  int _documentLength;
  List<Diagnostic> _externalDiagnostics = const <Diagnostic>[];

  List<Diagnostic> get externalDiagnostics => _externalDiagnostics;

  void resetForDocumentLength(int documentLength) {
    ensureNotDisposed();
    _documentLength = documentLength;
    _externalDiagnostics = const <Diagnostic>[];
    notifyControllerListeners();
  }

  StyioDocumentAnalysis? applyExternalDiagnostics({
    required StyioDocumentAnalysis baseAnalysis,
    required Iterable<Diagnostic> diagnostics,
  }) {
    ensureNotDisposed();
    final externalDiagnostics = diagnostics
        .where(_isValidForDocument)
        .toList(growable: false);
    if (externalDiagnostics.isEmpty) {
      return null;
    }

    _externalDiagnostics = dedupeDiagnostics(<Diagnostic>[
      ..._externalDiagnostics,
      ...externalDiagnostics,
    ]);
    notifyControllerListeners();

    return StyioDocumentAnalysis(
      tokenSpans: baseAnalysis.tokenSpans,
      semanticSpans: baseAnalysis.semanticSpans,
      diagnostics: dedupeDiagnostics(<Diagnostic>[
        ...baseAnalysis.diagnostics,
        ..._externalDiagnostics,
      ]),
      formattingEdits: baseAnalysis.formattingEdits,
      semanticBlocks: baseAnalysis.semanticBlocks,
      inlayHints: baseAnalysis.inlayHints,
      documentSymbols: baseAnalysis.documentSymbols,
      referenceSpans: baseAnalysis.referenceSpans,
    );
  }

  List<Diagnostic> dedupeDiagnostics(Iterable<Diagnostic> diagnostics) {
    final deduped = <Diagnostic>[];
    final seen = <String>{};
    for (final diagnostic in diagnostics) {
      final key =
          '${diagnostic.code}:'
          '${diagnostic.range.start}:'
          '${diagnostic.range.end}:'
          '${diagnostic.message}';
      if (seen.add(key)) {
        deduped.add(diagnostic);
      }
    }
    return deduped;
  }

  bool _isValidForDocument(Diagnostic diagnostic) {
    return diagnostic.range.start >= 0 &&
        diagnostic.range.end >= diagnostic.range.start &&
        diagnostic.range.end <= _documentLength;
  }
}
