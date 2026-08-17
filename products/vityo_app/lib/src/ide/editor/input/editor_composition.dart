import '../selection/selection_state.dart';
import 'unicode_boundary_index.dart';

enum EditorCompositionPhase { idle, composing, finalizing }

enum EditorCompositionTransitionKind {
  started,
  provisional,
  commit,
  canceled,
  rejected,
  ignored,
}

enum EditorCompositionTransitionReason {
  compositionStarted,
  platformUpdate,
  platformCommit,
  directCommit,
  explicitCancel,
  platformReversion,
  focusLoss,
  connectionClosed,
  staleDocument,
  staleRevision,
  selectionChanged,
  staleGeneration,
  connectionChanged,
  staleSequence,
  invalidPlatformRange,
  noActiveComposition,
  commitAccepted,
  commitRejected,
}

final class EditorInputRange {
  const EditorInputRange({required this.start, required this.end})
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;

  @override
  bool operator ==(Object other) =>
      other is EditorInputRange && start == other.start && end == other.end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// The only source text retained for the platform connection.
final class EditorCompositionWindow {
  const EditorCompositionWindow({
    required this.documentStart,
    required this.text,
    required this.primaryReplacement,
    required this.completePrimaryRange,
  });

  static const empty = EditorCompositionWindow(
    documentStart: 0,
    text: '',
    primaryReplacement: EditorInputRange(start: 0, end: 0),
    completePrimaryRange: EditorInputRange(start: 0, end: 0),
  );

  final int documentStart;
  final String text;
  final EditorInputRange primaryReplacement;
  final EditorInputRange completePrimaryRange;

  int get documentEnd => documentStart + text.length;
  int get codeUnitLength => text.length;
  String get selectedText =>
      text.substring(primaryReplacement.start, primaryReplacement.end);
}

final class EditorCompositionCommitIntent {
  const EditorCompositionCommitIntent({
    required this.documentId,
    required this.expectedRevision,
    required this.selectionSet,
    required this.text,
    required this.connectionGeneration,
    required this.sequence,
    required this.reason,
  });

  final String documentId;
  final int expectedRevision;
  final EditorSelectionSet selectionSet;
  final String text;
  final int connectionGeneration;
  final int sequence;
  final EditorCompositionTransitionReason reason;
}

final class EditorCompositionTransition {
  const EditorCompositionTransition({
    required this.kind,
    required this.reason,
    required this.nextState,
    this.commitIntent,
  });

  final EditorCompositionTransitionKind kind;
  final EditorCompositionTransitionReason reason;
  final EditorCompositionState nextState;
  final EditorCompositionCommitIntent? commitIntent;
}

/// Immutable, Flutter-independent composition reducer.
///
/// Provisional values have no Source Buffer or history mutation capability.
/// The only outward editing value is an idempotently correlated commit intent.
final class EditorCompositionState {
  const EditorCompositionState._({
    required this.phase,
    required this.documentId,
    required this.expectedRevision,
    required this.selectionSet,
    required this.connectionGeneration,
    required this.sequence,
    required this.window,
    required this.provisionalText,
    required this.provisionalSelection,
    required this.composingRange,
  });

  const EditorCompositionState.idle()
    : phase = EditorCompositionPhase.idle,
      documentId = null,
      expectedRevision = -1,
      selectionSet = null,
      connectionGeneration = -1,
      sequence = -1,
      window = EditorCompositionWindow.empty,
      provisionalText = '',
      provisionalSelection = const EditorInputRange(start: 0, end: 0),
      composingRange = const EditorInputRange(start: 0, end: 0);

  static const int maximumTransportCodeUnits = 8192;

  final EditorCompositionPhase phase;
  final String? documentId;
  final int expectedRevision;
  final EditorSelectionSet? selectionSet;
  final int connectionGeneration;
  final int sequence;
  final EditorCompositionWindow window;
  final String provisionalText;
  final EditorInputRange provisionalSelection;
  final EditorInputRange composingRange;

  EditorCompositionTransition start({
    required String documentId,
    required String documentText,
    required int revision,
    required EditorSelectionSet selectionSet,
    required int connectionGeneration,
    required int sequence,
  }) {
    if (phase != EditorCompositionPhase.idle) {
      return _ignored(EditorCompositionTransitionReason.staleSequence);
    }
    final gate = _idleEventGate(connectionGeneration, sequence);
    if (gate != null) return gate;
    if (documentId.isEmpty) {
      throw ArgumentError.value(documentId, 'documentId', 'must not be empty');
    }
    if (revision < 0 || connectionGeneration < 0 || sequence < 0) {
      throw ArgumentError(
        'Revision, generation, and sequence must be non-negative.',
      );
    }
    final primary = selectionSet.primarySelection;
    RangeError.checkValidRange(primary.start, primary.end, documentText.length);
    final transport = _makeWindow(
      documentId: documentId,
      documentText: documentText,
      revision: revision,
      primary: primary,
    );
    final next = EditorCompositionState._(
      phase: EditorCompositionPhase.composing,
      documentId: documentId,
      expectedRevision: revision,
      selectionSet: selectionSet,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      window: transport,
      provisionalText: transport.selectedText,
      provisionalSelection: EditorInputRange(
        start: 0,
        end: transport.selectedText.length,
      ),
      composingRange: const EditorInputRange(start: 0, end: 0),
    );
    return EditorCompositionTransition(
      kind: EditorCompositionTransitionKind.started,
      reason: EditorCompositionTransitionReason.compositionStarted,
      nextState: next,
    );
  }

  EditorCompositionTransition update({
    String? documentId,
    required int revision,
    required EditorSelectionSet selectionSet,
    required int connectionGeneration,
    required int sequence,
    required String provisionalText,
    required EditorInputRange provisionalSelection,
    required EditorInputRange composingRange,
  }) {
    final gate = _activeEventGate(
      eventDocumentId: documentId,
      revision: revision,
      eventSelections: selectionSet,
      generation: connectionGeneration,
      eventSequence: sequence,
    );
    if (gate != null) return gate;
    if (!_validPlatformRange(provisionalText, provisionalSelection) ||
        !_validPlatformRange(provisionalText, composingRange)) {
      return _reject(
        EditorCompositionTransitionReason.invalidPlatformRange,
        generation: connectionGeneration,
        eventSequence: sequence,
      );
    }
    if (provisionalText == window.selectedText && composingRange.isCollapsed) {
      return _toIdle(
        kind: EditorCompositionTransitionKind.canceled,
        reason: EditorCompositionTransitionReason.platformReversion,
        generation: connectionGeneration,
        eventSequence: sequence,
      );
    }
    final next = EditorCompositionState._(
      phase: EditorCompositionPhase.composing,
      documentId: this.documentId,
      expectedRevision: expectedRevision,
      selectionSet: this.selectionSet,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      window: window,
      provisionalText: provisionalText,
      provisionalSelection: provisionalSelection,
      composingRange: composingRange,
    );
    return EditorCompositionTransition(
      kind: EditorCompositionTransitionKind.provisional,
      reason: EditorCompositionTransitionReason.platformUpdate,
      nextState: next,
    );
  }

  EditorCompositionTransition cancel({
    String? documentId,
    required int revision,
    required EditorSelectionSet selectionSet,
    required int connectionGeneration,
    required int sequence,
    required EditorCompositionTransitionReason reason,
  }) {
    final gate = _activeEventGate(
      eventDocumentId: documentId,
      revision: revision,
      eventSelections: selectionSet,
      generation: connectionGeneration,
      eventSequence: sequence,
    );
    if (gate != null) return gate;
    return _toIdle(
      kind: EditorCompositionTransitionKind.canceled,
      reason: reason,
      generation: connectionGeneration,
      eventSequence: sequence,
    );
  }

  /// Emits a correlated commit and clears provisional state atomically.
  EditorCompositionTransition finalize({
    String? documentId,
    required int revision,
    required EditorSelectionSet selectionSet,
    required int connectionGeneration,
    required int sequence,
    required EditorCompositionTransitionReason reason,
  }) {
    final begun = beginFinalize(
      documentId: documentId,
      revision: revision,
      selectionSet: selectionSet,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      reason: reason,
    );
    if (begun.kind != EditorCompositionTransitionKind.commit) return begun;
    return EditorCompositionTransition(
      kind: begun.kind,
      reason: begun.reason,
      nextState: begun.nextState._idleHighWater(),
      commitIntent: begun.commitIntent,
    );
  }

  /// Two-step variant for adapters which wait for an asynchronous transaction.
  EditorCompositionTransition beginFinalize({
    String? documentId,
    required int revision,
    required EditorSelectionSet selectionSet,
    required int connectionGeneration,
    required int sequence,
    required EditorCompositionTransitionReason reason,
  }) {
    final gate = _activeEventGate(
      eventDocumentId: documentId,
      revision: revision,
      eventSelections: selectionSet,
      generation: connectionGeneration,
      eventSequence: sequence,
    );
    if (gate != null) return gate;
    final intent = EditorCompositionCommitIntent(
      documentId: this.documentId!,
      expectedRevision: expectedRevision,
      selectionSet: this.selectionSet!,
      text: provisionalText,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      reason: reason,
    );
    final next = EditorCompositionState._(
      phase: EditorCompositionPhase.finalizing,
      documentId: this.documentId,
      expectedRevision: expectedRevision,
      selectionSet: this.selectionSet,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      window: window,
      provisionalText: provisionalText,
      provisionalSelection: provisionalSelection,
      composingRange: composingRange,
    );
    return EditorCompositionTransition(
      kind: EditorCompositionTransitionKind.commit,
      reason: reason,
      nextState: next,
      commitIntent: intent,
    );
  }

  EditorCompositionTransition resolveFinalization({
    required int connectionGeneration,
    required int sequence,
    required bool accepted,
  }) {
    if (phase != EditorCompositionPhase.finalizing) {
      return _ignored(EditorCompositionTransitionReason.noActiveComposition);
    }
    if (connectionGeneration != this.connectionGeneration) {
      return _ignored(EditorCompositionTransitionReason.staleGeneration);
    }
    if (sequence != this.sequence) {
      return _ignored(EditorCompositionTransitionReason.staleSequence);
    }
    return EditorCompositionTransition(
      kind: accepted
          ? EditorCompositionTransitionKind.commit
          : EditorCompositionTransitionKind.rejected,
      reason: accepted
          ? EditorCompositionTransitionReason.commitAccepted
          : EditorCompositionTransitionReason.commitRejected,
      nextState: _idleHighWater(),
    );
  }

  /// Handles an idle non-composing delta/dead-key result without capturing
  /// provisional state.
  EditorCompositionTransition commitDirect({
    required String documentId,
    required int revision,
    required EditorSelectionSet selectionSet,
    required int connectionGeneration,
    required int sequence,
    required String text,
  }) {
    if (phase != EditorCompositionPhase.idle) {
      return _ignored(EditorCompositionTransitionReason.staleSequence);
    }
    final gate = _idleEventGate(connectionGeneration, sequence);
    if (gate != null) return gate;
    if (documentId.isEmpty) {
      throw ArgumentError.value(documentId, 'documentId', 'must not be empty');
    }
    if (revision < 0 || connectionGeneration < 0 || sequence < 0) {
      throw ArgumentError(
        'Revision, generation, and sequence must be non-negative.',
      );
    }
    final intent = EditorCompositionCommitIntent(
      documentId: documentId,
      expectedRevision: revision,
      selectionSet: selectionSet,
      text: text,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      reason: EditorCompositionTransitionReason.directCommit,
    );
    final next = EditorCompositionState._(
      phase: EditorCompositionPhase.idle,
      documentId: documentId,
      expectedRevision: revision,
      selectionSet: selectionSet,
      connectionGeneration: connectionGeneration,
      sequence: sequence,
      window: EditorCompositionWindow.empty,
      provisionalText: '',
      provisionalSelection: const EditorInputRange(start: 0, end: 0),
      composingRange: const EditorInputRange(start: 0, end: 0),
    );
    return EditorCompositionTransition(
      kind: EditorCompositionTransitionKind.commit,
      reason: EditorCompositionTransitionReason.directCommit,
      nextState: next,
      commitIntent: intent,
    );
  }

  EditorCompositionTransition? _idleEventGate(
    int generation,
    int nextSequence,
  ) {
    if (generation < connectionGeneration) {
      return _ignored(EditorCompositionTransitionReason.staleGeneration);
    }
    if (generation == connectionGeneration && nextSequence <= sequence) {
      return _ignored(EditorCompositionTransitionReason.staleSequence);
    }
    return null;
  }

  EditorCompositionTransition? _activeEventGate({
    required String? eventDocumentId,
    required int revision,
    required EditorSelectionSet eventSelections,
    required int generation,
    required int eventSequence,
  }) {
    if (phase == EditorCompositionPhase.idle) {
      return _idleEventGate(generation, eventSequence) ??
          _ignored(EditorCompositionTransitionReason.noActiveComposition);
    }
    if (generation < connectionGeneration) {
      return _ignored(EditorCompositionTransitionReason.staleGeneration);
    }
    if (generation == connectionGeneration && eventSequence <= sequence) {
      return _ignored(EditorCompositionTransitionReason.staleSequence);
    }
    if (generation != connectionGeneration) {
      return _reject(
        EditorCompositionTransitionReason.connectionChanged,
        generation: generation,
        eventSequence: eventSequence,
      );
    }
    if (eventDocumentId != null && eventDocumentId != documentId) {
      return _reject(
        EditorCompositionTransitionReason.staleDocument,
        generation: generation,
        eventSequence: eventSequence,
      );
    }
    if (revision != expectedRevision) {
      return _reject(
        EditorCompositionTransitionReason.staleRevision,
        generation: generation,
        eventSequence: eventSequence,
      );
    }
    if (eventSelections != selectionSet) {
      return _reject(
        EditorCompositionTransitionReason.selectionChanged,
        generation: generation,
        eventSequence: eventSequence,
      );
    }
    if (phase == EditorCompositionPhase.finalizing) {
      return _ignored(EditorCompositionTransitionReason.staleSequence);
    }
    return null;
  }

  EditorCompositionTransition _reject(
    EditorCompositionTransitionReason reason, {
    required int generation,
    required int eventSequence,
  }) => _toIdle(
    kind: EditorCompositionTransitionKind.rejected,
    reason: reason,
    generation: generation,
    eventSequence: eventSequence,
  );

  EditorCompositionTransition _ignored(
    EditorCompositionTransitionReason reason,
  ) => EditorCompositionTransition(
    kind: EditorCompositionTransitionKind.ignored,
    reason: reason,
    nextState: this,
  );

  EditorCompositionTransition _toIdle({
    required EditorCompositionTransitionKind kind,
    required EditorCompositionTransitionReason reason,
    required int generation,
    required int eventSequence,
  }) {
    final next = EditorCompositionState._(
      phase: EditorCompositionPhase.idle,
      documentId: documentId,
      expectedRevision: expectedRevision,
      selectionSet: selectionSet,
      connectionGeneration: generation,
      sequence: eventSequence,
      window: EditorCompositionWindow.empty,
      provisionalText: '',
      provisionalSelection: const EditorInputRange(start: 0, end: 0),
      composingRange: const EditorInputRange(start: 0, end: 0),
    );
    return EditorCompositionTransition(
      kind: kind,
      reason: reason,
      nextState: next,
    );
  }

  EditorCompositionState _idleHighWater() => EditorCompositionState._(
    phase: EditorCompositionPhase.idle,
    documentId: documentId,
    expectedRevision: expectedRevision,
    selectionSet: selectionSet,
    connectionGeneration: connectionGeneration,
    sequence: sequence,
    window: EditorCompositionWindow.empty,
    provisionalText: '',
    provisionalSelection: const EditorInputRange(start: 0, end: 0),
    composingRange: const EditorInputRange(start: 0, end: 0),
  );

  static bool _validPlatformRange(String value, EditorInputRange range) {
    if (range.start < 0 ||
        range.end < range.start ||
        range.end > value.length) {
      return false;
    }
    return _isScalarBoundary(value, range.start) &&
        _isScalarBoundary(value, range.end);
  }

  static bool _isScalarBoundary(String value, int offset) {
    if (offset <= 0 || offset >= value.length) return true;
    final before = value.codeUnitAt(offset - 1);
    final after = value.codeUnitAt(offset);
    return !(before >= 0xD800 &&
        before <= 0xDBFF &&
        after >= 0xDC00 &&
        after <= 0xDFFF);
  }

  static EditorCompositionWindow _makeWindow({
    required String documentId,
    required String documentText,
    required int revision,
    required SelectionState primary,
  }) {
    final complete = EditorInputRange(start: primary.start, end: primary.end);
    if (complete.length > maximumTransportCodeUnits) {
      return EditorCompositionWindow(
        documentStart: complete.start,
        text: '',
        primaryReplacement: const EditorInputRange(start: 0, end: 0),
        completePrimaryRange: complete,
      );
    }
    final index = UnicodeBoundaryIndex.forTextRange(
      documentId: documentId,
      revision: revision,
      text: documentText,
      rangeStart: complete.start,
      rangeEnd: complete.end,
      maxCodeUnits: maximumTransportCodeUnits,
    );
    final relativeStart = complete.start - index.windowStart;
    final relativeEnd = complete.end - index.windowStart;
    return EditorCompositionWindow(
      documentStart: index.windowStart,
      text: index.windowText,
      primaryReplacement: EditorInputRange(
        start: relativeStart.clamp(0, index.windowText.length),
        end: relativeEnd.clamp(0, index.windowText.length),
      ),
      completePrimaryRange: complete,
    );
  }
}
