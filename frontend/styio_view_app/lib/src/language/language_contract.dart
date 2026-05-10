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

enum DiagnosticSeverity { error, warning, hint }

enum CompletionItemKind { keyword, function, variable, snippet }

enum SymbolKind {
  function,
  pipeline,
  state,
  resource,
  variable,
  parameter,
  task,
}

enum ReferenceAccess { declaration, read, write }

class SourceRange {
  const SourceRange({required this.start, required this.end});

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
  const FormattingEdit({required this.range, required this.newText});

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

class SurroundTemplate {
  const SurroundTemplate({
    required this.id,
    required this.label,
    required this.openingLine,
    required this.closingLine,
    this.bodyIndent = '  ',
    this.detail = '',
  });

  final String id;
  final String label;
  final String openingLine;
  final String closingLine;
  final String bodyIndent;
  final String detail;
}

class HoverPayload {
  const HoverPayload({required this.range, required this.markdown});

  final SourceRange range;
  final String markdown;
}

class SemanticBlockRange {
  const SemanticBlockRange({required this.range, required this.label});

  final SourceRange range;
  final String label;
}

class DocumentSymbol {
  const DocumentSymbol({
    required this.name,
    required this.kind,
    required this.nameRange,
    required this.declarationRange,
    this.detail = '',
  });

  final String name;
  final SymbolKind kind;
  final SourceRange nameRange;
  final SourceRange declarationRange;
  final String detail;
}

class ReferenceSpan {
  const ReferenceSpan({
    required this.name,
    required this.kind,
    required this.range,
    required this.targetRange,
    this.isDeclaration = false,
    this.access = ReferenceAccess.read,
  });

  final String name;
  final SymbolKind kind;
  final SourceRange range;
  final SourceRange targetRange;
  final bool isDeclaration;
  final ReferenceAccess access;
}

class DefinitionTarget {
  const DefinitionTarget({required this.symbol, required this.originRange});

  final DocumentSymbol symbol;
  final SourceRange originRange;
}

class RenameConflict {
  const RenameConflict({required this.message, required this.range});

  final String message;
  final SourceRange range;
}

class RenamePlan {
  const RenamePlan({
    required this.target,
    required this.newName,
    required this.references,
    required this.edits,
    this.conflicts = const <RenameConflict>[],
  });

  final DocumentSymbol target;
  final String newName;
  final List<ReferenceSpan> references;
  final List<FormattingEdit> edits;
  final List<RenameConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class SafeDeleteConflict {
  const SafeDeleteConflict({required this.message, required this.range});

  final String message;
  final SourceRange range;
}

class SafeDeletePlan {
  const SafeDeletePlan({
    required this.target,
    required this.references,
    required this.edits,
    this.conflicts = const <SafeDeleteConflict>[],
  });

  final DocumentSymbol target;
  final List<ReferenceSpan> references;
  final List<FormattingEdit> edits;
  final List<SafeDeleteConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class InlineVariableConflict {
  const InlineVariableConflict({required this.message, required this.range});

  final String message;
  final SourceRange range;
}

class InlineVariablePlan {
  const InlineVariablePlan({
    required this.target,
    required this.initializerRange,
    required this.initializerText,
    required this.references,
    required this.edits,
    this.conflicts = const <InlineVariableConflict>[],
  });

  final DocumentSymbol target;
  final SourceRange initializerRange;
  final String initializerText;
  final List<ReferenceSpan> references;
  final List<FormattingEdit> edits;
  final List<InlineVariableConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class IntroduceVariableConflict {
  const IntroduceVariableConflict({required this.message, required this.range});

  final String message;
  final SourceRange range;
}

class IntroduceVariablePlan {
  const IntroduceVariablePlan({
    required this.variableName,
    required this.expressionRange,
    required this.expressionText,
    required this.edits,
    this.conflicts = const <IntroduceVariableConflict>[],
  });

  final String variableName;
  final SourceRange expressionRange;
  final String expressionText;
  final List<FormattingEdit> edits;
  final List<IntroduceVariableConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class ExtractFunctionConflict {
  const ExtractFunctionConflict({required this.message, required this.range});

  final String message;
  final SourceRange range;
}

class ExtractFunctionPlan {
  const ExtractFunctionPlan({
    required this.functionName,
    required this.selectionRange,
    required this.selectedText,
    required this.parameters,
    required this.callText,
    required this.functionText,
    required this.edits,
    this.conflicts = const <ExtractFunctionConflict>[],
  });

  final String functionName;
  final SourceRange selectionRange;
  final String selectedText;
  final List<String> parameters;
  final String callText;
  final String functionText;
  final List<FormattingEdit> edits;
  final List<ExtractFunctionConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

class ParameterInfoParameter {
  const ParameterInfoParameter({
    required this.name,
    required this.range,
    this.type = '',
  });

  final String name;
  final SourceRange range;
  final String type;

  String get displayText => type.isEmpty ? name : '$name: $type';
}

class ParameterInfoPayload {
  const ParameterInfoPayload({
    required this.callableName,
    required this.signature,
    required this.parameters,
    required this.activeParameterIndex,
    required this.invocationRange,
    required this.callableRange,
  });

  final String callableName;
  final String signature;
  final List<ParameterInfoParameter> parameters;
  final int activeParameterIndex;
  final SourceRange invocationRange;
  final SourceRange callableRange;

  ParameterInfoParameter? get activeParameter {
    if (activeParameterIndex < 0 || activeParameterIndex >= parameters.length) {
      return null;
    }
    return parameters[activeParameterIndex];
  }
}

class StyioDocumentAnalysis {
  const StyioDocumentAnalysis({
    required this.tokenSpans,
    required this.semanticSpans,
    required this.diagnostics,
    required this.formattingEdits,
    required this.semanticBlocks,
    required this.documentSymbols,
    required this.referenceSpans,
  });

  final List<TokenSpan> tokenSpans;
  final List<SemanticSpan> semanticSpans;
  final List<Diagnostic> diagnostics;
  final List<FormattingEdit> formattingEdits;
  final List<SemanticBlockRange> semanticBlocks;
  final List<DocumentSymbol> documentSymbols;
  final List<ReferenceSpan> referenceSpans;

  int get tokenCount => tokenSpans.length;
  int get semanticCount => semanticSpans.length;
  int get diagnosticCount => diagnostics.length;
  int get symbolCount => documentSymbols.length;
  int get referenceCount => referenceSpans.length;
}
