import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../service/language_service_foundation.dart';
import 'styio_navigation_feature.dart';

class StyioRefactorFeature {
  const StyioRefactorFeature({
    this.navigationFeature = const StyioNavigationFeature(),
  });

  final StyioNavigationFeature navigationFeature;

  SafeDeletePlan? safeDeleteAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
  }) {
    final reference = snapshot.referenceAt(offset);
    if (reference == null) {
      return null;
    }

    final references = snapshot.referencesFor(reference.target);
    final nonDeclarationReferences = references
        .where((span) => !span.isDeclaration)
        .toList(growable: false);
    final conflicts = [
      for (final span in nonDeclarationReferences)
        SafeDeleteConflict(
          message: 'Symbol is still referenced.',
          range: span.range,
        ),
    ];

    return SafeDeletePlan(
      target: _documentSymbol(reference.target),
      references: references.map(_referenceSpan).toList(growable: false),
      edits: conflicts.isEmpty
          ? [
              FormattingEdit(
                range: _lineRemovalRange(document.text, reference.target),
                newText: '',
              ),
            ]
          : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  InlineVariablePlan? inlineVariableAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
  }) {
    final reference = snapshot.referenceAt(offset);
    if (reference == null ||
        reference.target.kind != ResolvedElementKind.variable) {
      return null;
    }

    final initializer = _initializerRange(document.text, reference.target);
    if (initializer == null) {
      return null;
    }

    final initializerText = document.text.substring(
      initializer.start,
      initializer.end,
    );
    final references = snapshot.referencesFor(reference.target);
    final referenceUses = references
        .where((span) => !span.isDeclaration)
        .toList(growable: false);
    if (referenceUses.isEmpty) {
      return null;
    }

    return InlineVariablePlan(
      target: _documentSymbol(reference.target),
      initializerRange: initializer,
      initializerText: initializerText,
      references: referenceUses.map(_referenceSpan).toList(growable: false),
      edits: [
        for (final span in referenceUses)
          FormattingEdit(range: span.range, newText: initializerText),
        FormattingEdit(
          range: _lineRemovalRange(document.text, reference.target),
          newText: '',
        ),
      ],
    );
  }

  IntroduceVariablePlan? introduceVariable({
    required DocumentState document,
    required SourceRange range,
    required String name,
  }) {
    if (!_isValidIdentifier(name)) {
      return null;
    }

    final expressionRange = _trimmedRange(document.text, range);
    if (expressionRange.isCollapsed) {
      return null;
    }

    final expression = document.text.substring(
      expressionRange.start,
      expressionRange.end,
    );
    final insertAt = _lineStart(document.text, expressionRange.start);
    return IntroduceVariablePlan(
      variableName: name,
      expressionRange: expressionRange,
      expressionText: expression,
      edits: <FormattingEdit>[
        FormattingEdit(
          range: SourceRange(start: insertAt, end: insertAt),
          newText: '$name := $expression\n',
        ),
        FormattingEdit(range: expressionRange, newText: name),
      ],
    );
  }

  ExtractFunctionPlan? extractFunction({
    required DocumentState document,
    required SourceRange range,
    required String name,
  }) {
    if (!_isValidIdentifier(name)) {
      return null;
    }

    final selectionRange = _trimmedRange(document.text, range);
    if (selectionRange.isCollapsed) {
      return null;
    }

    final selectedText = document.text.substring(
      selectionRange.start,
      selectionRange.end,
    );
    final callText = '$name()';
    final functionText = '#$name := () => {\n${_indent(selectedText)}\n}\n\n';

    return ExtractFunctionPlan(
      functionName: name,
      selectionRange: selectionRange,
      selectedText: selectedText,
      parameters: const <String>[],
      callText: callText,
      functionText: functionText,
      edits: <FormattingEdit>[
        FormattingEdit(
          range: const SourceRange(start: 0, end: 0),
          newText: functionText,
        ),
        FormattingEdit(range: selectionRange, newText: callText),
      ],
    );
  }

  ChangeSignaturePlan? changeSignatureAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    final renamePlan = navigationFeature.renameAt(
      document: document,
      snapshot: snapshot,
      offset: offset,
      newName: newName,
    );
    if (renamePlan == null) {
      return null;
    }

    final conflicts = parameters.isEmpty
        ? const <ChangeSignatureConflict>[]
        : <ChangeSignatureConflict>[
            ChangeSignatureConflict(
              message: 'Parameter rewriting requires StyioService semantics.',
              range: renamePlan.target.nameRange,
            ),
          ];

    return ChangeSignaturePlan(
      target: renamePlan.target,
      originalName: renamePlan.target.name,
      newName: newName,
      originalParameters: const <ParameterInfoParameter>[],
      newParameters: parameters,
      references: renamePlan.references,
      edits: conflicts.isEmpty ? renamePlan.edits : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  DocumentSymbol _documentSymbol(ResolvedElement element) {
    return DocumentSymbol(
      name: element.name,
      kind: symbolKindFromResolvedElementKind(element.kind),
      nameRange: element.nameRange,
      declarationRange: element.declarationRange,
      detail: element.detail ?? '',
      documentation: element.documentation ?? '',
    );
  }

  ReferenceSpan _referenceSpan(ResolvedReference reference) {
    return ReferenceSpan(
      name: reference.name,
      kind: symbolKindFromResolvedElementKind(reference.target.kind),
      range: reference.range,
      targetRange: reference.target.nameRange,
      isDeclaration: reference.isDeclaration,
      access: referenceAccessFromResolvedReferenceAccess(reference.access),
    );
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

  SourceRange _lineRemovalRange(String source, ResolvedElement element) {
    var start = element.declarationRange.start;
    while (start > 0 && source[start - 1] != '\n') {
      start -= 1;
    }

    var end = element.declarationRange.end;
    while (end < source.length && source[end] != '\n') {
      end += 1;
    }
    if (end < source.length && source[end] == '\n') {
      end += 1;
    }

    return SourceRange(start: start, end: end);
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

  int _lineStart(String source, int offset) {
    var cursor = offset.clamp(0, source.length);
    while (cursor > 0 && source[cursor - 1] != '\n') {
      cursor -= 1;
    }
    return cursor;
  }

  String _indent(String text) {
    return text
        .split('\n')
        .map((line) => line.isEmpty ? line : '  $line')
        .join('\n');
  }

  bool _isValidIdentifier(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }
}
