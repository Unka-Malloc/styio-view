import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../service/language_service_foundation.dart';
import '../syntax/styio_syntax_highlighter.dart';

class StyioCompletionFeature {
  const StyioCompletionFeature();

  List<CompletionItem> completeAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
  }) {
    final replacementRange = _replacementRange(snapshot.tokens, offset);
    final prefix = _completionPrefix(document.text, replacementRange, offset);
    final seenLabels = <String>{};
    final items = <CompletionItem>[];

    void addItem(CompletionItem item) {
      if (!_matchesPrefix(item.label, prefix) || !seenLabels.add(item.label)) {
        return;
      }
      items.add(item);
    }

    for (final keyword in const <String>['import', 'schema', 'true', 'false']) {
      addItem(
        CompletionItem(
          label: keyword,
          kind: CompletionItemKind.keyword,
          insertText: keyword,
          detail: 'Styio keyword',
          replacementRange: replacementRange,
        ),
      );
    }

    for (final typeName in StyioSyntaxHighlighter.typeNames) {
      addItem(
        CompletionItem(
          label: typeName,
          kind: CompletionItemKind.keyword,
          insertText: typeName,
          detail: 'Styio type',
          replacementRange: replacementRange,
        ),
      );
    }

    final candidates = snapshot.completionCandidatesAt(offset).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    for (final element in candidates) {
      addItem(
        CompletionItem(
          label: element.name,
          kind: _completionKind(element.kind),
          insertText: element.name,
          detail: element.detail ?? '',
          documentation: element.documentation ?? '',
          replacementRange: replacementRange,
        ),
      );
    }

    return items;
  }

  CompletionItemKind _completionKind(ResolvedElementKind kind) {
    switch (kind) {
      case ResolvedElementKind.function:
        return CompletionItemKind.function;
      case ResolvedElementKind.variable:
      case ResolvedElementKind.type:
      case ResolvedElementKind.resource:
      case ResolvedElementKind.parameter:
      case ResolvedElementKind.unknown:
        return CompletionItemKind.variable;
    }
  }

  SourceRange _replacementRange(List<TokenSpan> tokens, int offset) {
    final token = _tokenAtOffset(tokens, offset);
    if (token != null && _isValidIdentifier(token.lexeme)) {
      return token.range;
    }
    return SourceRange(start: offset, end: offset);
  }

  String _completionPrefix(String source, SourceRange range, int offset) {
    if (range.isCollapsed) {
      return '';
    }
    final start = range.clampStart(0, source.length);
    final end = offset.clamp(start, range.clampEnd(0, source.length));
    return source.substring(start, end);
  }

  bool _matchesPrefix(String label, String prefix) {
    return prefix.isEmpty || label.startsWith(prefix);
  }

  TokenSpan? _tokenAtOffset(List<TokenSpan> tokens, int offset) {
    for (final token in tokens) {
      if (_contains(token.range, offset) && token.lexeme.trim().isNotEmpty) {
        return token;
      }
    }
    return null;
  }

  bool _isValidIdentifier(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }

  bool _contains(SourceRange range, int offset) {
    return range.contains(offset);
  }
}
