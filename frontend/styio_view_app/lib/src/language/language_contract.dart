enum TokenKind {
  keyword,
  identifier,
  number,
  string,
  comment,
  operator,
  punctuation,
  whitespace,
  unknown,
}

enum SemanticKind {
  function,
  pipeline,
  state,
  resource,
  variable,
  parameter,
  typeName,
}

enum DiagnosticSeverity {
  error,
  warning,
  hint,
}

enum CompletionItemKind {
  keyword,
  function,
  variable,
  snippet,
}

class SourceRange {
  const SourceRange({
    required this.start,
    required this.end,
  });

  final int start;
  final int end;

  bool get isCollapsed => start == end;

  bool contains(int offset) {
    return offset >= start && offset < end;
  }

  bool intersects(SourceRange other) {
    return start < other.end && other.start < end;
  }

  int clampStart(int min, int max) {
    return start.clamp(min, max);
  }

  int clampEnd(int min, int max) {
    return end.clamp(min, max);
  }
}

class TokenSpan {
  const TokenSpan({
    required this.range,
    required this.kind,
    required this.lexeme,
  });

  final SourceRange range;
  final TokenKind kind;
  final String lexeme;
}

class SemanticSpan {
  const SemanticSpan({
    required this.range,
    required this.kind,
    this.modifiers = const <String>[],
  });

  final SourceRange range;
  final SemanticKind kind;
  final List<String> modifiers;
}

class Diagnostic {
  const Diagnostic({
    required this.severity,
    required this.code,
    required this.message,
    required this.range,
  });

  final DiagnosticSeverity severity;
  final String code;
  final String message;
  final SourceRange range;
}

class FormattingEdit {
  const FormattingEdit({
    required this.range,
    required this.newText,
  });

  final SourceRange range;
  final String newText;
}

class DiagnosticQuickFix {
  const DiagnosticQuickFix({
    required this.label,
    required this.edits,
    this.detail = '',
  });

  final String label;
  final List<FormattingEdit> edits;
  final String detail;
}

class CompletionItem {
  const CompletionItem({
    required this.label,
    required this.kind,
    required this.insertText,
    this.detail = '',
  });

  final String label;
  final CompletionItemKind kind;
  final String insertText;
  final String detail;
}

class HoverPayload {
  const HoverPayload({
    required this.range,
    required this.markdown,
  });

  final SourceRange range;
  final String markdown;
}

class SemanticBlockRange {
  const SemanticBlockRange({
    required this.range,
    required this.label,
  });

  final SourceRange range;
  final String label;
}

class StyioDocumentAnalysis {
  const StyioDocumentAnalysis({
    required this.tokenSpans,
    required this.semanticSpans,
    required this.diagnostics,
    required this.formattingEdits,
    required this.semanticBlocks,
  });

  final List<TokenSpan> tokenSpans;
  final List<SemanticSpan> semanticSpans;
  final List<Diagnostic> diagnostics;
  final List<FormattingEdit> formattingEdits;
  final List<SemanticBlockRange> semanticBlocks;

  int get tokenCount => tokenSpans.length;
  int get semanticCount => semanticSpans.length;
  int get diagnosticCount => diagnostics.length;
}
