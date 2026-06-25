/// Editor transaction boundary.
///
/// Undo/redo snapshots and language-action edits still live inside the editor
/// controller. New mutation semantics should be extracted here before they are
/// exposed to render widgets.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../language/language_contract.dart';
import '../document/document_state.dart';
import '../document/text_buffer/text_buffer.dart';
import '../selection/selection_state.dart';

enum WorkspaceEditSource {
  userInput,
  formatting,
  codeAction,
  rename,
  refactor,
  searchReplace,
  agentPatch,
  unknown,
}

extension WorkspaceEditSourceX on WorkspaceEditSource {
  String get wireValue {
    switch (this) {
      case WorkspaceEditSource.userInput:
        return 'user-input';
      case WorkspaceEditSource.formatting:
        return 'formatting';
      case WorkspaceEditSource.codeAction:
        return 'code-action';
      case WorkspaceEditSource.rename:
        return 'rename';
      case WorkspaceEditSource.refactor:
        return 'refactor';
      case WorkspaceEditSource.searchReplace:
        return 'search-replace';
      case WorkspaceEditSource.agentPatch:
        return 'agent-patch';
      case WorkspaceEditSource.unknown:
        return 'unknown';
    }
  }
}

enum WorkspaceEditValidationCode {
  ok,
  empty,
  documentMismatch,
  staleRevision,
  staleContentHash,
  invalidRange,
  overlappingRanges,
}

class DocumentContentHash {
  const DocumentContentHash._();

  static String compute(String text) {
    return sha256.convert(utf8.encode(text)).toString();
  }
}

class WorkspaceEditPrecondition {
  const WorkspaceEditPrecondition({
    required this.documentId,
    this.expectedRevision,
    this.expectedContentHash,
  });

  final String documentId;
  final int? expectedRevision;
  final String? expectedContentHash;

  factory WorkspaceEditPrecondition.forDocument(DocumentState document) {
    return WorkspaceEditPrecondition(
      documentId: document.documentId,
      expectedRevision: document.revision,
      expectedContentHash: DocumentContentHash.compute(document.text),
    );
  }
}

class WorkspaceTextEdit {
  const WorkspaceTextEdit({
    required this.documentId,
    required this.range,
    required this.newText,
  });

  final String documentId;
  final SourceRange range;
  final String newText;

  FormattingEdit toFormattingEdit() {
    return FormattingEdit(range: range, newText: newText);
  }
}

class WorkspaceEdit {
  const WorkspaceEdit({
    required this.source,
    required this.edits,
    this.precondition,
    this.undoGroupId,
    this.label,
  });

  final WorkspaceEditSource source;
  final List<WorkspaceTextEdit> edits;
  final WorkspaceEditPrecondition? precondition;
  final String? undoGroupId;
  final String? label;

  factory WorkspaceEdit.singleDocument({
    required DocumentState document,
    required WorkspaceEditSource source,
    required Iterable<WorkspaceTextEdit> edits,
    String? undoGroupId,
    String? label,
  }) {
    return WorkspaceEdit(
      source: source,
      edits: List<WorkspaceTextEdit>.unmodifiable(edits),
      precondition: WorkspaceEditPrecondition.forDocument(document),
      undoGroupId: undoGroupId,
      label: label,
    );
  }

  factory WorkspaceEdit.fromFormattingEdits({
    required DocumentState document,
    required WorkspaceEditSource source,
    required Iterable<FormattingEdit> edits,
    String? undoGroupId,
    String? label,
  }) {
    return WorkspaceEdit.singleDocument(
      document: document,
      source: source,
      undoGroupId: undoGroupId,
      label: label,
      edits: edits.map(
        (edit) => WorkspaceTextEdit(
          documentId: document.documentId,
          range: edit.range,
          newText: edit.newText,
        ),
      ),
    );
  }
}

class WorkspaceEditValidation {
  const WorkspaceEditValidation({
    required this.code,
    required this.message,
  });

  final WorkspaceEditValidationCode code;
  final String message;

  bool get isValid => code == WorkspaceEditValidationCode.ok;

  static const WorkspaceEditValidation ok = WorkspaceEditValidation(
    code: WorkspaceEditValidationCode.ok,
    message: 'Workspace edit is valid.',
  );
}

class EditorTransaction {
  const EditorTransaction({
    required this.id,
    required this.edit,
  });

  final String id;
  final WorkspaceEdit edit;
}

class EditorCommandTransaction {
  const EditorCommandTransaction({
    required this.id,
    required this.commandId,
    required this.edit,
    this.selectionAfter,
    this.label,
  });

  final String id;
  final String commandId;
  final WorkspaceEdit edit;
  final SelectionState? selectionAfter;
  final String? label;
}

class EditorTransactionResult {
  const EditorTransactionResult({
    required this.document,
    required this.validation,
    required this.appliedEditCount,
    required this.contentHash,
  });

  final DocumentState document;
  final WorkspaceEditValidation validation;
  final int appliedEditCount;
  final String contentHash;

  bool get isApplied => validation.isValid;
}

class EditorCommandTransactionResult {
  const EditorCommandTransactionResult({
    required this.transaction,
    required this.result,
    required this.selectionBefore,
    required this.selectionAfter,
  });

  final EditorCommandTransaction transaction;
  final EditorTransactionResult result;
  final SelectionState selectionBefore;
  final SelectionState selectionAfter;

  bool get isApplied => result.isApplied;
}

class EditorTransactionService {
  const EditorTransactionService();

  WorkspaceEditValidation validateForDocument({
    required DocumentState document,
    required WorkspaceEdit edit,
  }) {
    final precondition = edit.precondition;
    if (precondition != null) {
      if (precondition.documentId != document.documentId) {
        return WorkspaceEditValidation(
          code: WorkspaceEditValidationCode.documentMismatch,
          message:
              'Workspace edit targets `${precondition.documentId}`, not `${document.documentId}`.',
        );
      }
      if (precondition.expectedRevision != null &&
          precondition.expectedRevision != document.revision) {
        return WorkspaceEditValidation(
          code: WorkspaceEditValidationCode.staleRevision,
          message: 'Workspace edit expected revision '
              '${precondition.expectedRevision}, found ${document.revision}.',
        );
      }
      if (precondition.expectedContentHash != null &&
          precondition.expectedContentHash !=
              DocumentContentHash.compute(document.text)) {
        return const WorkspaceEditValidation(
          code: WorkspaceEditValidationCode.staleContentHash,
          message: 'Workspace edit expected a different document content hash.',
        );
      }
    }

    if (edit.edits.isEmpty) {
      return const WorkspaceEditValidation(
        code: WorkspaceEditValidationCode.empty,
        message: 'Workspace edit contains no text edits.',
      );
    }

    final sortedEdits = _sortedEdits(edit.edits);
    var previousEnd = -1;
    for (final textEdit in sortedEdits) {
      if (textEdit.documentId != document.documentId) {
        return WorkspaceEditValidation(
          code: WorkspaceEditValidationCode.documentMismatch,
          message:
              'Text edit targets `${textEdit.documentId}`, not `${document.documentId}`.',
        );
      }
      if (!_isRangeValid(document.length, textEdit.range)) {
        return WorkspaceEditValidation(
          code: WorkspaceEditValidationCode.invalidRange,
          message: 'Text edit range '
              '${textEdit.range.start}:${textEdit.range.end} is invalid for '
              '`${document.documentId}`.',
        );
      }
      if (textEdit.range.start < previousEnd) {
        return WorkspaceEditValidation(
          code: WorkspaceEditValidationCode.overlappingRanges,
          message: 'Text edit range '
              '${textEdit.range.start}:${textEdit.range.end} overlaps a '
              'previous edit.',
        );
      }
      previousEnd = textEdit.range.end;
    }

    return WorkspaceEditValidation.ok;
  }

  EditorTransactionResult applyToDocument({
    required DocumentState document,
    required WorkspaceEdit edit,
  }) {
    final validation = validateForDocument(document: document, edit: edit);
    if (!validation.isValid) {
      return EditorTransactionResult(
        document: document,
        validation: validation,
        appliedEditCount: 0,
        contentHash: DocumentContentHash.compute(document.text),
      );
    }

    var nextBuffer = document.textBuffer;
    final descendingEdits = _sortedEdits(edit.edits).reversed;
    for (final textEdit in descendingEdits) {
      nextBuffer = nextBuffer.replace(
        TextRange(start: textEdit.range.start, end: textEdit.range.end),
        textEdit.newText,
      );
    }

    final nextSnapshot = nextBuffer.snapshot();
    final nextDocument = DocumentState.fromTextBuffer(
      documentId: document.documentId,
      textBufferSnapshot: nextSnapshot,
      revision: document.revision + 1,
    );
    return EditorTransactionResult(
      document: nextDocument,
      validation: WorkspaceEditValidation.ok,
      appliedEditCount: edit.edits.length,
      contentHash: DocumentContentHash.compute(nextSnapshot.text),
    );
  }

  List<WorkspaceTextEdit> _sortedEdits(Iterable<WorkspaceTextEdit> edits) {
    return edits.toList(growable: false)
      ..sort((left, right) {
        final startCompare = left.range.start.compareTo(right.range.start);
        if (startCompare != 0) {
          return startCompare;
        }
        return left.range.end.compareTo(right.range.end);
      });
  }

  bool _isRangeValid(int documentLength, SourceRange range) {
    return range.start >= 0 &&
        range.end >= range.start &&
        range.end <= documentLength;
  }
}
