import '../../editor/document_state.dart';
import '../contract/language_contract.dart';

class StyioFormattingFeature {
  const StyioFormattingFeature();

  List<FormattingEdit> formatDocument(DocumentState document) {
    final edits = <FormattingEdit>[];
    final trailingWhitespace = RegExp(r'[ \t]+(?=\r?\n|$)');

    for (final match in trailingWhitespace.allMatches(document.text)) {
      edits.add(
        FormattingEdit(
          range: SourceRange(start: match.start, end: match.end),
          newText: '',
        ),
      );
    }

    if (document.text.isNotEmpty && !document.text.endsWith('\n')) {
      edits.add(
        FormattingEdit(
          range: SourceRange(start: document.length, end: document.length),
          newText: '\n',
        ),
      );
    }

    return edits;
  }

  DiagnosticQuickFix? formatDocumentAction(DocumentState document) {
    final edits = formatDocument(document);
    if (edits.isEmpty) {
      return null;
    }
    return DiagnosticQuickFix(
      label: 'Format document whitespace',
      detail: 'Remove trailing whitespace and ensure a final newline.',
      edits: edits,
    );
  }
}
