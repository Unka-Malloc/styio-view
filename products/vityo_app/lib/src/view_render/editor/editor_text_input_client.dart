import 'package:flutter/services.dart';

import '../../ide/editor/controllers/editor_session_facade.dart';
import '../../ide/editor/input/editor_composition.dart';
import '../../ide/editor/input/unicode_boundary_index.dart';
import '../../ide/editor/selection/selection_state.dart';

/// Flutter's transport adapter for the revisioned editor input boundary.
///
/// This object deliberately owns no source, selection, composition, history,
/// or painting policy. Those decisions remain in the editor domain and the
/// laid-out source surface; this class only correlates Flutter callbacks with
/// that state.
final class EditorTextInputClient with TextInputClient {
  EditorTextInputClient({
    required EditorSessionFacade controller,
    required VoidCallback onChanged,
  }) : _controller = controller,
       _onChanged = onChanged;

  final EditorSessionFacade _controller;
  final VoidCallback _onChanged;

  TextInputConnection? _connection;
  EditorCompositionState _composition = const EditorCompositionState.idle();
  TextEditingValue _editingValue = TextEditingValue.empty;
  EditorCompositionWindow _window = EditorCompositionWindow.empty;
  int _generation = 0;
  int _sequence = 0;
  int _publishedRevision = -1;
  bool _disposed = false;
  bool _awaitingExplicitReconnect = false;
  String _status = 'input disconnected';
  int _acceptedCommitSerial = 0;
  String? _lastAcceptedCommitText;

  bool get isAttached => _connection?.attached ?? false;
  bool get isComposing =>
      _composition.phase == EditorCompositionPhase.composing;
  EditorCompositionState get composition => _composition;
  EditorCompositionWindow get window => _window;
  String get status => _status;
  int get acceptedCommitSerial => _acceptedCommitSerial;
  String? get lastAcceptedCommitText => _lastAcceptedCommitText;
  String get provisionalText => isComposing ? _composition.provisionalText : '';

  TextRange get provisionalComposingRange => isComposing
      ? TextRange(
          start: _composition.composingRange.start,
          end: _composition.composingRange.end,
        )
      : TextRange.empty;

  void attach({bool explicit = false}) {
    if (_disposed || isAttached) return;
    if (_awaitingExplicitReconnect && !explicit) return;
    _awaitingExplicitReconnect = false;
    _generation += 1;
    _sequence = 0;
    _composition = const EditorCompositionState.idle();
    _refreshWindowFromCommittedSource();
    try {
      final connection = TextInput.attach(
        this,
        const TextInputConfiguration(
          inputType: TextInputType.multiline,
          inputAction: TextInputAction.newline,
          autocorrect: true,
          enableSuggestions: true,
          enableIMEPersonalizedLearning: false,
        ),
      );
      _connection = connection;
      connection.setEditingState(_editingValue);
      connection.show();
      _status = 'input connected';
    } catch (_) {
      _connection = null;
      _status = 'input unavailable';
    }
    _notifyChanged();
  }

  /// Finalizes a valid active composition and closes the Flutter transport.
  void detach({
    EditorCompositionTransitionReason reason =
        EditorCompositionTransitionReason.focusLoss,
  }) {
    if (_disposed) return;
    _finalizeActive(reason);
    final connection = _connection;
    _connection = null;
    if (connection?.attached ?? false) connection!.close();
    _status = 'input disconnected';
    _notifyChanged();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _composition = const EditorCompositionState.idle();
    final connection = _connection;
    _connection = null;
    if (connection?.attached ?? false) connection!.close();
    _status = 'input disconnected';
  }

  /// Synchronizes platform state after an external committed edit (undo,
  /// command, pointer selection). Active stale composition is rejected by the
  /// reducer before a fresh committed window is published.
  void synchronizeCommittedState() {
    if (_disposed) return;
    final document = _controller.document;
    if (document.revision == _publishedRevision &&
        !isComposing &&
        _selectionMatchesWindow()) {
      return;
    }
    if (isComposing &&
        (document.revision != _composition.expectedRevision ||
            _controller.selectionSet != _composition.selectionSet)) {
      final transition = _composition.cancel(
        documentId: document.documentId,
        revision: document.revision,
        selectionSet: _controller.selectionSet,
        connectionGeneration: _generation,
        sequence: ++_sequence,
        reason: EditorCompositionTransitionReason.selectionChanged,
      );
      _composition = transition.nextState;
      _status = 'composition canceled after source change';
    }
    if (!isComposing) {
      if (document.revision == _publishedRevision) {
        _syncEditingSelectionToPrimary();
      } else {
        _refreshWindowFromCommittedSource();
        _publishEditingState();
      }
    }
  }

  void _syncEditingSelectionToPrimary() {
    final primary = _controller.selectionSet.primarySelection;
    final completeStart = primary.start;
    final completeEnd = primary.end;
    if (completeStart < _window.documentStart ||
        completeEnd > _window.documentEnd) {
      _refreshWindowFromCommittedSource();
      _publishEditingState();
      return;
    }
    final relativeStart = completeStart - _window.documentStart;
    final relativeEnd = completeEnd - _window.documentStart;
    _editingValue = TextEditingValue(
      text: _window.text,
      selection: TextSelection(
        baseOffset: relativeStart,
        extentOffset: relativeEnd,
        affinity: _flutterAffinity(primary.extentAffinity),
      ),
    );
    _publishEditingState();
  }

  bool cancelComposition() {
    if (!isComposing) return false;
    final transition = _composition.cancel(
      documentId: _controller.document.documentId,
      revision: _controller.document.revision,
      selectionSet: _controller.selectionSet,
      connectionGeneration: _generation,
      sequence: ++_sequence,
      reason: EditorCompositionTransitionReason.explicitCancel,
    );
    _composition = transition.nextState;
    _status = transition.kind == EditorCompositionTransitionKind.canceled
        ? 'composition canceled'
        : 'composition rejected';
    _refreshWindowFromCommittedSource();
    _publishEditingState();
    _notifyChanged();
    return transition.kind == EditorCompositionTransitionKind.canceled;
  }

  /// Deletes one extended grapheme (or the active ranges) across every
  /// selection through [EditorSessionFacade.commitEditorInput].
  bool deleteBackward() => _commitStructuralDeletion(forward: false);

  /// Deletes one extended grapheme forward (or the active ranges) across every
  /// selection through [EditorSessionFacade.commitEditorInput].
  bool deleteForward() => _commitStructuralDeletion(forward: true);

  /// Inserts a newline at every selection through the shared commit seam.
  bool insertNewline() => insertPlainText('\n');

  /// Inserts [text] at every selection through the shared commit seam.
  bool insertPlainText(String text) {
    if (_disposed || isComposing) return false;
    final document = _controller.document;
    return _commitStructuralText(
      text: text,
      selectionSet: _controller.selectionSet,
      expectedRevision: document.revision,
      documentId: document.documentId,
    );
  }

  bool _commitStructuralDeletion({required bool forward}) {
    if (_disposed || isComposing) return false;
    final document = _controller.document;
    final current = _controller.selectionSet;
    final nextSelections = <SelectionState>[];
    var mutates = false;
    for (final selection in current.selections) {
      if (!selection.isCollapsed) {
        nextSelections.add(selection);
        mutates = true;
        continue;
      }
      if ((!forward && selection.end == 0) ||
          (forward && selection.end >= document.length)) {
        nextSelections.add(selection);
        continue;
      }
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: document.documentId,
        revision: document.revision,
        text: document.text,
        anchorOffset: selection.end,
      );
      final range = index.deletionRange(
        selection.end,
        forward: forward,
        documentRevision: document.revision,
      );
      if (range.isCollapsed) {
        nextSelections.add(selection);
        continue;
      }
      mutates = true;
      nextSelections.add(
        SelectionState(
          baseOffset: range.start,
          extentOffset: range.end,
          baseAffinity: selection.extentAffinity,
          extentAffinity: selection.extentAffinity,
        ),
      );
    }
    if (!mutates) return false;
    final deletionSet = EditorSelectionSet.normalized(
      selections: nextSelections,
      primaryIndex: current.primaryIndex,
      documentLength: document.length,
    );
    if (deletionSet != current) {
      _controller.selectionController.selectSelectionSet(deletionSet);
    }
    return _commitStructuralText(
      text: '',
      selectionSet: _controller.selectionSet,
      expectedRevision: document.revision,
      documentId: document.documentId,
    );
  }

  bool _commitStructuralText({
    required String text,
    required EditorSelectionSet selectionSet,
    required int expectedRevision,
    required String documentId,
  }) {
    final transition = _composition.commitDirect(
      documentId: documentId,
      revision: expectedRevision,
      selectionSet: selectionSet,
      connectionGeneration: _generation,
      sequence: ++_sequence,
      text: text,
    );
    if (transition.commitIntent == null) {
      _status = 'input rejected';
      _notifyChanged();
      return false;
    }
    _composition = transition.nextState;
    _applyCommit(transition);
    return _status == 'input committed';
  }

  void updateGeometry({
    required Size editableSize,
    required Matrix4 transform,
    required Rect caretRect,
    required List<SelectionRect> selectionRects,
    Rect? composingRect,
  }) {
    final connection = _connection;
    if (connection == null || !connection.attached) return;
    connection.setEditableSizeAndTransform(editableSize, transform);
    connection.setCaretRect(caretRect);
    connection.setSelectionRects(selectionRects);
    if (composingRect != null) connection.setComposingRect(composingRect);
  }

  @override
  TextEditingValue? get currentTextEditingValue => _editingValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (_disposed || !isAttached) return;
    final document = _controller.document;
    final delta = _replacementDelta(_editingValue, value);
    final provisionalSelection = _relativeRange(
      value.selection,
      delta.newStart,
      delta.text.length,
    );
    final composing = value.composing.isValid && !value.composing.isCollapsed;
    final composingRange = composing
        ? _relativeRange(value.composing, delta.newStart, delta.text.length)
        : const EditorInputRange(start: 0, end: 0);

    if (_composition.phase == EditorCompositionPhase.idle && composing) {
      final started = _composition.start(
        documentId: document.documentId,
        documentText: document.text,
        revision: document.revision,
        selectionSet: _controller.selectionSet,
        connectionGeneration: _generation,
        sequence: ++_sequence,
      );
      _composition = started.nextState;
    }

    if (isComposing) {
      if (!composing) {
        _finalizeActive(EditorCompositionTransitionReason.platformCommit);
        _notifyChanged();
        return;
      }
      final updated = _composition.update(
        documentId: document.documentId,
        revision: document.revision,
        selectionSet: _controller.selectionSet,
        connectionGeneration: _generation,
        sequence: ++_sequence,
        provisionalText: delta.text,
        provisionalSelection: provisionalSelection,
        composingRange: composingRange,
      );
      _composition = updated.nextState;
      if (updated.kind == EditorCompositionTransitionKind.rejected) {
        _status = 'composition rejected';
        _refreshWindowFromCommittedSource();
        _publishEditingState();
      } else if (composing) {
        _editingValue = value;
        _status = 'composition active';
      }
      _notifyChanged();
      return;
    }

    if (!composing && delta.changed) {
      final transition = _composition.commitDirect(
        documentId: document.documentId,
        revision: document.revision,
        selectionSet: _controller.selectionSet,
        connectionGeneration: _generation,
        sequence: ++_sequence,
        text: delta.text,
      );
      _composition = transition.nextState;
      _applyCommit(transition);
      return;
    }

    // A platform-only selection movement is kept inside the bounded window.
    _editingValue = value;
    _notifyChanged();
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.done) detach();
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void connectionClosed() {
    if (_disposed || _connection == null) return;
    _finalizeActive(EditorCompositionTransitionReason.connectionClosed);
    final connection = _connection!;
    _connection = null;
    _awaitingExplicitReconnect = true;
    if (connection.attached) {
      connection.close();
    }
    _status = 'input disconnected';
    _notifyChanged();
  }

  void _finalizeActive(EditorCompositionTransitionReason reason) {
    if (!isComposing) return;
    final document = _controller.document;
    final transition = _composition.finalize(
      documentId: document.documentId,
      revision: document.revision,
      selectionSet: _controller.selectionSet,
      connectionGeneration: _generation,
      sequence: ++_sequence,
      reason: reason,
    );
    _composition = transition.nextState;
    _applyCommit(transition, publish: false);
  }

  void _applyCommit(
    EditorCompositionTransition transition, {
    bool publish = true,
  }) {
    final intent = transition.commitIntent;
    final accepted = intent != null && _controller.commitEditorInput(intent);
    _status = accepted ? 'input committed' : 'input rejected';
    if (accepted) {
      _acceptedCommitSerial += 1;
      _lastAcceptedCommitText = intent.text;
    }
    _refreshWindowFromCommittedSource();
    if (publish) _publishEditingState();
    _notifyChanged();
  }

  void _refreshWindowFromCommittedSource() {
    final document = _controller.document;
    final primary = _controller.selectionSet.primarySelection;
    if (document.lineCount >= 10000) {
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: document.documentId,
        revision: document.revision,
        text: document.text,
        anchorOffset: primary.extentOffset,
      );
      final relativeStart = primary.start - index.windowStart;
      final relativeEnd = primary.end - index.windowStart;
      final windowText = index.windowText;
      _window = EditorCompositionWindow(
        documentStart: index.windowStart,
        text: windowText,
        primaryReplacement: EditorInputRange(
          start: relativeStart.clamp(0, windowText.length),
          end: relativeEnd.clamp(0, windowText.length),
        ),
        completePrimaryRange: EditorInputRange(
          start: primary.start,
          end: primary.end,
        ),
      );
      _editingValue = TextEditingValue(
        text: windowText,
        selection: TextSelection(
          baseOffset: relativeStart.clamp(0, windowText.length),
          extentOffset: relativeEnd.clamp(0, windowText.length),
          affinity: _flutterAffinity(primary.extentAffinity),
        ),
      );
      _publishedRevision = document.revision;
      return;
    }
    final transient = const EditorCompositionState.idle().start(
      documentId: document.documentId,
      documentText: document.text,
      revision: document.revision,
      selectionSet: _controller.selectionSet,
      connectionGeneration: _generation,
      sequence: 0,
    );
    _window = transient.nextState.window;
    final replacement = _window.primaryReplacement;
    _editingValue = TextEditingValue(
      text: _window.text,
      selection: TextSelection(
        baseOffset: replacement.start,
        extentOffset: replacement.end,
        affinity: _flutterAffinity(
          _controller.selectionSet.primarySelection.extentAffinity,
        ),
      ),
    );
    _publishedRevision = document.revision;
  }

  void _publishEditingState() {
    final connection = _connection;
    if (connection != null && connection.attached) {
      connection.setEditingState(_editingValue);
    }
  }

  bool _selectionMatchesWindow() {
    final primary = _controller.selectionSet.primarySelection;
    return primary.start == _window.completePrimaryRange.start &&
        primary.end == _window.completePrimaryRange.end;
  }

  void _notifyChanged() {
    if (!_disposed) _onChanged();
  }

  static TextAffinity _flutterAffinity(Object affinity) =>
      affinity.toString().endsWith('upstream')
      ? TextAffinity.upstream
      : TextAffinity.downstream;

  static EditorInputRange _relativeRange(
    TextRange range,
    int origin,
    int maximum,
  ) {
    final start = (range.start - origin).clamp(0, maximum);
    final end = (range.end - origin).clamp(start, maximum);
    return EditorInputRange(start: start, end: end);
  }

  static _EditingReplacement _replacementDelta(
    TextEditingValue before,
    TextEditingValue after,
  ) {
    var prefix = 0;
    final sharedLength = before.text.length < after.text.length
        ? before.text.length
        : after.text.length;
    while (prefix < sharedLength &&
        before.text.codeUnitAt(prefix) == after.text.codeUnitAt(prefix)) {
      prefix += 1;
    }
    var suffix = 0;
    while (suffix < before.text.length - prefix &&
        suffix < after.text.length - prefix &&
        before.text.codeUnitAt(before.text.length - suffix - 1) ==
            after.text.codeUnitAt(after.text.length - suffix - 1)) {
      suffix += 1;
    }
    final newEnd = after.text.length - suffix;
    return _EditingReplacement(
      text: after.text.substring(prefix, newEnd),
      newStart: prefix,
      changed: before.text != after.text,
    );
  }
}

final class _EditingReplacement {
  const _EditingReplacement({
    required this.text,
    required this.newStart,
    required this.changed,
  });

  final String text;
  final int newStart;
  final bool changed;
}
