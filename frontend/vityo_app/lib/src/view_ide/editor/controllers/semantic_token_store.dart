import '../../language/language_contract.dart';
import '../document/document_state.dart';
import '../document/range_index.dart';
import 'editor_owned_controller.dart';

class SemanticTokenStore extends EditorOwnedController {
  List<TokenSpan> _tokenSpans = const <TokenSpan>[];
  List<SemanticSpan> _semanticSpans = const <SemanticSpan>[];
  RangeIndex<SemanticSpan> _semanticSpanIndex =
      RangeIndex<SemanticSpan>.empty();

  List<TokenSpan> get tokenSpans => _tokenSpans;
  List<SemanticSpan> get semanticSpans => _semanticSpans;

  void updateFromAnalysis(StyioDocumentAnalysis analysis) {
    ensureNotDisposed();
    _tokenSpans = analysis.tokenSpans;
    _semanticSpans = analysis.semanticSpans;
    _semanticSpanIndex = RangeIndex<SemanticSpan>.fromValues(
      _semanticSpans,
      startOf: (span) => span.range.start,
      endOf: (span) => span.range.end,
      layerOf: (_) => 'semantic',
    );
    notifyControllerListeners();
  }

  TokenSpan? tokenAroundOffset({
    required DocumentState document,
    required int offset,
  }) {
    ensureNotDisposed();
    final safeOffset = offset.clamp(0, document.length);
    TokenSpan? trailingToken;
    TokenSpan? leadingToken;

    for (final token in _tokenSpans) {
      if (token.kind == TokenKind.whitespace) {
        continue;
      }

      if (token.range.contains(safeOffset)) {
        return token;
      }
      if (token.range.end == safeOffset) {
        trailingToken = token;
      }
      if (leadingToken == null && token.range.start == safeOffset) {
        leadingToken = token;
      }
    }

    return trailingToken ?? leadingToken;
  }

  SemanticKind? semanticKindForToken(TokenSpan? token) {
    ensureNotDisposed();
    if (token == null) {
      return null;
    }

    final spans = _semanticSpanIndex.overlapQuery(
      start: token.range.start,
      end: token.range.end,
    );
    if (spans.isNotEmpty) {
      return spans.first.kind;
    }
    return null;
  }
}
