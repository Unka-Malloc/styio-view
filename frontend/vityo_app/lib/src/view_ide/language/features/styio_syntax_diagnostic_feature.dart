import '../../editor/document_state.dart';
import '../contract/language_contract.dart';

class StyioSyntaxDiagnosticFeature {
  const StyioSyntaxDiagnosticFeature();

  List<Diagnostic> diagnosticsFor({
    required DocumentState document,
    required List<TokenSpan> tokens,
  }) {
    final stack = <_OpenDelimiter>[];
    final diagnostics = <Diagnostic>[];

    for (final token in tokens) {
      final opening = _openingDelimiter(token.lexeme);
      if (opening != null) {
        stack.add(_OpenDelimiter(opening, token.range));
        continue;
      }

      final expectedOpening = _expectedOpening(token.lexeme);
      if (expectedOpening == null) {
        continue;
      }

      if (stack.isEmpty || stack.last.lexeme != expectedOpening) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'local.unmatched-delimiter',
            message: 'Unmatched delimiter `${token.lexeme}`.',
            range: token.range,
          ),
        );
        continue;
      }

      stack.removeLast();
    }

    for (final open in stack.reversed) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'local.unclosed-delimiter',
          message: 'Unclosed delimiter `${open.lexeme}`.',
          range: open.range,
        ),
      );
    }

    return diagnostics;
  }

  List<DiagnosticQuickFix> quickFixesForDiagnostic({
    required DocumentState document,
    required Diagnostic diagnostic,
  }) {
    switch (diagnostic.code) {
      case 'local.unclosed-delimiter':
        final opening = _lexemeAt(document.text, diagnostic.range);
        final closing = _closingDelimiter(opening);
        if (closing == null) {
          return const <DiagnosticQuickFix>[];
        }
        return <DiagnosticQuickFix>[
          DiagnosticQuickFix(
            label: 'Insert matching `$closing`',
            detail: 'Local fallback fix for an unclosed delimiter.',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(
                  start: document.length,
                  end: document.length,
                ),
                newText: closing,
              ),
            ],
          ),
        ];
      case 'local.unmatched-delimiter':
        return <DiagnosticQuickFix>[
          DiagnosticQuickFix(
            label: 'Remove unmatched delimiter',
            detail: 'Local fallback fix for an unmatched closing delimiter.',
            edits: <FormattingEdit>[
              FormattingEdit(range: diagnostic.range, newText: ''),
            ],
          ),
        ];
    }
    return const <DiagnosticQuickFix>[];
  }

  String? _openingDelimiter(String lexeme) {
    switch (lexeme) {
      case '(':
      case '{':
      case '[':
        return lexeme;
    }
    return null;
  }

  String? _closingDelimiter(String? lexeme) {
    switch (lexeme) {
      case '(':
        return ')';
      case '{':
        return '}';
      case '[':
        return ']';
    }
    return null;
  }

  String? _expectedOpening(String lexeme) {
    switch (lexeme) {
      case ')':
        return '(';
      case '}':
        return '{';
      case ']':
        return '[';
    }
    return null;
  }

  String? _lexemeAt(String source, SourceRange range) {
    if (range.start < 0 ||
        range.end > source.length ||
        range.start >= range.end) {
      return null;
    }
    return source.substring(range.start, range.end);
  }
}

class _OpenDelimiter {
  const _OpenDelimiter(this.lexeme, this.range);

  final String lexeme;
  final SourceRange range;
}
