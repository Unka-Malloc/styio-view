import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../service/language_service_foundation.dart';

class StyioInlayHintFeature {
  const StyioInlayHintFeature();

  List<InlayHint> inlayHints({
    required DocumentState document,
    required SemanticSnapshot snapshot,
  }) {
    final hints = <InlayHint>[];

    for (final element in snapshot.elements) {
      if (element.kind != ResolvedElementKind.variable) {
        continue;
      }
      final initializer = _initializerText(document.text, element);
      final inferredType = _inferLiteralType(initializer);
      if (inferredType == null) {
        continue;
      }
      hints.add(
        InlayHint(
          label: ': $inferredType',
          kind: InlayHintKind.type,
          position: element.nameRange.end,
          range: element.nameRange,
        ),
      );
    }

    return hints;
  }

  String? _initializerText(String source, ResolvedElement element) {
    final range = _initializerRange(source, element);
    if (range == null) {
      return null;
    }
    return source.substring(range.start, range.end);
  }

  SourceRange? _initializerRange(String source, ResolvedElement element) {
    final declaration = source.substring(
      element.declarationRange.start,
      element.declarationRange.end,
    );
    final operatorIndex = declaration.indexOf(':=');
    final fallbackIndex = declaration.indexOf('=');
    final index = operatorIndex >= 0 ? operatorIndex + 2 : fallbackIndex + 1;
    if (index <= 0 || index >= declaration.length) {
      return null;
    }

    final rawStart = element.declarationRange.start + index;
    final rawEnd = element.declarationRange.end;
    return _trimmedRange(source, SourceRange(start: rawStart, end: rawEnd));
  }

  String? _inferLiteralType(String? text) {
    if (text == null) {
      return null;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed == 'true' || trimmed == 'false') {
      return 'bool';
    }
    if (RegExp(r'^-?[0-9]+$').hasMatch(trimmed)) {
      return 'i64';
    }
    if (RegExp(r'^-?[0-9]+\.[0-9]+$').hasMatch(trimmed)) {
      return 'f64';
    }
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return 'string';
    }
    return null;
  }

  SourceRange _trimmedRange(String source, SourceRange range) {
    var start = range.start.clamp(0, source.length);
    var end = range.end.clamp(start, source.length);

    while (start < end && source[start].trim().isEmpty) {
      start += 1;
    }
    while (end > start && source[end - 1].trim().isEmpty) {
      end -= 1;
    }

    return SourceRange(start: start, end: end);
  }
}
