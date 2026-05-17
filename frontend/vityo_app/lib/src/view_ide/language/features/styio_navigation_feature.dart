import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../service/language_service_foundation.dart';

class StyioNavigationFeature {
  const StyioNavigationFeature();

  DefinitionTarget? definitionAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
  }) {
    final reference = snapshot.referenceAt(offset);
    final target = reference?.target ?? snapshot.elementAt(offset);
    if (target == null) {
      return null;
    }
    return DefinitionTarget(
      symbol: _documentSymbol(target),
      originRange: reference?.range ?? target.nameRange,
    );
  }

  List<ReferenceSpan> referencesAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
  }) {
    final reference = snapshot.referenceAt(offset);
    final target = reference?.target ?? snapshot.elementAt(offset);
    if (target == null) {
      return const <ReferenceSpan>[];
    }
    return snapshot
        .referencesFor(target)
        .map(_referenceSpan)
        .toList(growable: false);
  }

  RenamePlan? renameAt({
    required DocumentState document,
    required SemanticSnapshot snapshot,
    required int offset,
    required String newName,
  }) {
    if (!_isValidIdentifier(newName)) {
      return null;
    }

    final reference = snapshot.referenceAt(offset);
    final target = reference?.target ?? snapshot.elementAt(offset);
    if (target == null) {
      return null;
    }

    final references = snapshot
        .referencesFor(target)
        .map(_referenceSpan)
        .toList(growable: false);
    if (newName == target.name) {
      return RenamePlan(
        target: _documentSymbol(target),
        newName: newName,
        references: references,
        edits: const <FormattingEdit>[],
      );
    }

    final conflicts = snapshot.elements
        .where(
          (element) =>
              element.name == newName &&
              !_sameRange(element.nameRange, target.nameRange),
        )
        .map(
          (element) => RenameConflict(
            message: 'A symbol named $newName already exists.',
            range: element.nameRange,
          ),
        )
        .toList(growable: false);

    return RenamePlan(
      target: _documentSymbol(target),
      newName: newName,
      references: references,
      edits: conflicts.isEmpty
          ? [
              for (final span in snapshot.referencesFor(target))
                FormattingEdit(range: span.range, newText: newName),
            ]
          : const <FormattingEdit>[],
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

  bool _isValidIdentifier(String value) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }

  bool _sameRange(SourceRange left, SourceRange right) {
    return left.start == right.start && left.end == right.end;
  }
}
