import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../service/language_service_foundation.dart';
import '../syntax/styio_syntax_highlighter.dart';

class StyioHoverFeature {
  const StyioHoverFeature();

  HoverPayload? hoverAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
  }) {
    final reference = snapshot.referenceAt(offset);
    if (reference != null) {
      return HoverPayload(
        range: reference.range,
        markdown: _elementMarkdown(reference.target),
      );
    }

    final element = snapshot.elementAt(offset);
    if (element != null) {
      return HoverPayload(
        range: element.nameRange,
        markdown: _elementMarkdown(element),
      );
    }

    final token = _tokenAtOffset(snapshot.tokens, offset);
    if (token == null) {
      return null;
    }

    final operatorHover = StyioSyntaxHighlighter.operatorHover[token.lexeme];
    if (operatorHover != null) {
      return HoverPayload(range: token.range, markdown: operatorHover);
    }

    return null;
  }

  TokenSpan? _tokenAtOffset(List<TokenSpan> tokens, int offset) {
    for (final token in tokens) {
      if (_contains(token.range, offset) && token.lexeme.trim().isNotEmpty) {
        return token;
      }
    }
    return null;
  }

  String _elementMarkdown(ResolvedElement element) {
    final detail = element.detail == null ? '' : '\n\n${element.detail}';
    final documentation = element.documentation == null
        ? ''
        : '\n\n${element.documentation}';
    return '**${element.name}**$detail$documentation';
  }

  bool _contains(SourceRange range, int offset) {
    return range.contains(offset);
  }
}
