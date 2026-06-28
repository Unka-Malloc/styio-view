import 'package:flutter/foundation.dart';

import '../../language/language_contract.dart';
import '../../language/service/language_service_foundation.dart';
import '../../language/service/semantic_snapshot_provider.dart';
import '../../language/styio_language_service.dart';
import '../document/document_state.dart';
import '../document/range_index.dart';
import '../render_plan/editor_render_layers.dart';
import '../selection/selection_state.dart';
import '../session/editor_session_data_store.dart';
import '../transactions/transactions.dart';
import 'diagnostics_store.dart';
import 'document_controller.dart';
import 'history_controller.dart';
import 'language_feature_controller.dart';
import 'render_plan_controller.dart';
import 'selection_controller.dart';
import 'semantic_token_store.dart';
import 'transaction_controller.dart';

class EditorSearchMatch {
  const EditorSearchMatch({
    required this.index,
    required this.range,
    required this.text,
  });

  final int index;
  final SourceRange range;
  final String text;
}

class EditorSessionFacade extends ChangeNotifier {
  EditorSessionFacade({
    required DocumentState initialDocument,
    required StyioLanguageService languageService,
    SelectionState? initialSelection,
    EditorRenderPlan? renderPlan,
    EditorTransactionService transactionService =
        const EditorTransactionService(),
    int historyLimit = HistoryController.defaultMaxEntries,
  }) : documentController = DocumentController(initialDocument),
       selectionController = SelectionController(
         initialSelection ?? SelectionState.collapsed(initialDocument.length),
         documentLength: initialDocument.length,
       ),
       transactionController = TransactionController(
         service: transactionService,
       ),
       historyController = HistoryController(maxEntries: historyLimit),
       languageFeatureController = LanguageFeatureController(
         languageService: languageService,
         initialDocument: initialDocument,
       ),
       diagnosticsStore = DiagnosticsStore(
         documentLength: initialDocument.length,
       ),
       semanticTokenStore = SemanticTokenStore(),
       renderPlanController = RenderPlanController(
         renderPlan ?? EditorRenderPlan.foundation(),
       ) {
    semanticTokenStore.updateFromAnalysis(languageFeatureController.analysis);
    _rebuildAnalysisIndexes();
  }

  final DocumentController documentController;
  final SelectionController selectionController;
  final TransactionController transactionController;
  final HistoryController historyController;
  final LanguageFeatureController languageFeatureController;
  final DiagnosticsStore diagnosticsStore;
  final SemanticTokenStore semanticTokenStore;
  final RenderPlanController renderPlanController;

  bool _isDisposed = false;
  late RangeIndex<Diagnostic> _diagnosticIndex;
  late RangeIndex<SemanticSpan> _semanticSpanIndex;

  DocumentState get _document => documentController.document;
  set _document(DocumentState document) {
    documentController.replaceDocument(document);
  }

  StyioLanguageService get _languageService =>
      languageFeatureController.languageService;
  SelectionState get _selection => selectionController.selection;
  set _selection(SelectionState selection) {
    selectionController.select(selection, documentLength: _document.length);
  }

  EditorRenderPlan get _renderPlan => renderPlanController.renderPlan;

  StyioDocumentAnalysis get _analysis => languageFeatureController.analysis;
  set _analysis(StyioDocumentAnalysis analysis) {
    languageFeatureController.setAnalysis(analysis);
    semanticTokenStore.updateFromAnalysis(analysis);
    _rebuildAnalysisIndexes();
  }

  List<SelectionState> get _structuredSelectionStack {
    _ensureNotDisposed();
    return selectionController.structuredSelectionStack;
  }

  bool get isDisposed => _isDisposed;

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('EditorSessionFacade has been disposed.');
    }
  }

  @override
  void notifyListeners() {
    _ensureNotDisposed();
    super.notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    documentController.dispose();
    selectionController.dispose();
    transactionController.dispose();
    historyController.dispose();
    languageFeatureController.dispose();
    diagnosticsStore.dispose();
    semanticTokenStore.dispose();
    renderPlanController.dispose();
    super.dispose();
  }

  DocumentState get document => _document;
  SelectionState get selection => _selection;
  EditorRenderPlan get renderPlan => _renderPlan;
  bool get glyphSubstitutionEnabled => _renderPlan.glyphSubstitutionEnabled;
  String? get selectedSourceText {
    if (_selection.isCollapsed) {
      return null;
    }
    return _document.text.substring(_selection.start, _selection.end);
  }

  void setGlyphSubstitutionEnabled(bool enabled) {
    if (glyphSubstitutionEnabled == enabled) {
      return;
    }
    renderPlanController.setGlyphSubstitutionEnabled(enabled);
    notifyListeners();
  }

  void toggleGlyphSubstitution() {
    setGlyphSubstitutionEnabled(!_renderPlan.glyphSubstitutionEnabled);
  }

  StyioDocumentAnalysis get analysis => _analysis;
  int get inspectionOffset =>
      selection.isCollapsed ? selection.end : selection.start;
  HoverPayload? get hoverAtSelection =>
      _languageService.hoverAt(_document, inspectionOffset);
  List<CompletionItem> get completionsAtSelection =>
      _languageService.completeAt(_document, inspectionOffset);
  List<SurroundTemplate> get surroundTemplatesAtSelection {
    final range = _surroundRangeForSelection();
    if (range == null) {
      return const <SurroundTemplate>[];
    }
    return _languageService.surroundTemplatesAt(_document, range);
  }

  DefinitionTarget? get definitionAtSelection =>
      _languageService.definitionAt(_document, inspectionOffset);
  List<ReferenceSpan> get referencesAtSelection =>
      _languageService.referencesAt(_document, inspectionOffset);
  ResolvedElement? get resolvedElementAtSelection =>
      _languageService.resolvedElementAt(_document, inspectionOffset);
  ResolvedReference? get resolvedReferenceAtSelection =>
      _languageService.resolvedReferenceAt(_document, inspectionOffset);
  RenamePlan? renamePlanAtSelection(String newName) =>
      _languageService.renameAt(_document, inspectionOffset, newName);
  SafeDeletePlan? get safeDeletePlanAtSelection =>
      _languageService.safeDeleteAt(_document, inspectionOffset);
  InlineVariablePlan? get inlineVariablePlanAtSelection =>
      _languageService.inlineVariableAt(_document, inspectionOffset);
  IntroduceVariablePlan? introduceVariablePlanAtSelection(String name) {
    if (_selection.isCollapsed) {
      return null;
    }
    return _languageService.introduceVariable(
      _document,
      SourceRange(start: _selection.start, end: _selection.end),
      name,
    );
  }

  ExtractFunctionPlan? extractFunctionPlanAtSelection(String name) {
    if (_selection.isCollapsed) {
      return null;
    }
    return _languageService.extractFunction(
      _document,
      SourceRange(start: _selection.start, end: _selection.end),
      name,
    );
  }

  ChangeSignaturePlan? changeSignaturePlanAtSelection({
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) => _languageService.changeSignatureAt(
    _document,
    inspectionOffset,
    newName: newName,
    parameters: parameters,
  );

  ParameterInfoPayload? get parameterInfoAtSelection =>
      _languageService.parameterInfoAt(_document, inspectionOffset);
  List<Diagnostic> get diagnostics => _analysis.diagnostics;
  TokenSpan? get tokenAtSelection => _tokenAroundOffset(inspectionOffset);
  SemanticKind? get semanticKindAtSelection {
    final token = tokenAtSelection;
    if (token == null) {
      return null;
    }
    final spans = _semanticSpanIndex.overlapQuery(
      start: token.range.start,
      end: token.range.end,
    );
    return spans.isEmpty ? null : spans.first.kind;
  }

  List<Diagnostic> get diagnosticsAtSelectionToken {
    final token = tokenAtSelection;
    if (token == null) {
      return const <Diagnostic>[];
    }
    return _diagnosticIndex.overlapQuery(
      start: token.range.start,
      end: token.range.end,
    );
  }

  List<Diagnostic> get diagnosticsAtSelection {
    final selectionRange = SourceRange(
      start: selection.start,
      end: selection.end,
    );
    final token = tokenAtSelection;
    final focusRange = selection.isCollapsed
        ? token?.range ??
              SourceRange(start: inspectionOffset, end: inspectionOffset)
        : selectionRange;
    return diagnosticsStore.dedupeDiagnostics(<Diagnostic>[
      ..._diagnosticIndex.pointQuery(inspectionOffset),
      ..._diagnosticIndex.overlapQuery(
        start: focusRange.start,
        end: focusRange.end,
      ),
    ]);
  }

  List<DiagnosticQuickFix> quickFixesForDiagnostics(
    Iterable<Diagnostic> diagnostics,
  ) {
    final fixes = <DiagnosticQuickFix>[];
    final seenSignatures = <String>{};

    for (final diagnostic in diagnostics) {
      final diagnosticFixes = _languageService.quickFixesForDiagnostic(
        _document,
        diagnostic,
      );
      for (final fix in diagnosticFixes) {
        final signature = [
          fix.label,
          for (final edit in fix.edits)
            '${edit.range.start}:${edit.range.end}:${edit.newText}',
        ].join('|');
        if (seenSignatures.add(signature)) {
          fixes.add(fix);
        }
      }
    }

    return fixes;
  }

  List<SemanticSnapshotCodeActionFact> codeActionFactsForDiagnostics(
    Iterable<Diagnostic> diagnostics,
  ) {
    final provider = SemanticSnapshotProvider(
      languageService: _languageService,
    );
    final facts = <SemanticSnapshotCodeActionFact>[];
    final seenSignatures = <String>{};

    for (final diagnostic in diagnostics) {
      final result = provider.codeActionsForDiagnostic(
        document: _document,
        diagnostic: diagnostic,
      );
      for (final action in result.actions) {
        final signature = [
          action.label,
          for (final edit in action.edits)
            '${edit.range.start}:${edit.range.end}:${edit.newText}',
        ].join('|');
        if (seenSignatures.add(signature)) {
          facts.add(action);
        }
      }
    }

    return facts;
  }

  List<SemanticSnapshotCodeActionFact> get codeActionFactsAtSelection {
    return codeActionFactsForDiagnostics(diagnosticsAtSelection);
  }

  SemanticSnapshotFeatureMatrix get semanticFeatureMatrix {
    return SemanticSnapshotProvider(
      languageService: _languageService,
    ).snapshotFor(_document).featureMatrix;
  }

  List<DiagnosticQuickFix> get contextActionsAtSelection {
    final actions = <DiagnosticQuickFix>[];
    final seenSignatures = <String>{};

    void addAction(DiagnosticQuickFix action) {
      final signature = [
        action.label,
        for (final edit in action.edits)
          '${edit.range.start}:${edit.range.end}:${edit.newText}',
      ].join('|');
      if (seenSignatures.add(signature)) {
        actions.add(action);
      }
    }

    for (final fix in quickFixesForDiagnostics(diagnosticsAtSelection)) {
      addAction(fix);
    }
    for (final intention in _languageService.intentionsAt(
      _document,
      _selection.extentOffset,
    )) {
      addAction(intention);
    }

    return actions;
  }

  List<EditorSearchMatch> searchDocument(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
  }) {
    if (query.isEmpty) {
      return const <EditorSearchMatch>[];
    }
    if (useRegex) {
      return _regexSearchDocument(
        query,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
      );
    }
    final source = _document.text;
    final haystack = caseSensitive ? source : source.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    final matches = <EditorSearchMatch>[];
    var offset = 0;
    while (offset <= haystack.length - needle.length) {
      final index = haystack.indexOf(needle, offset);
      if (index < 0) {
        break;
      }
      final end = index + needle.length;
      if (!wholeWord || _isWholeWordSearchMatch(source, index, end)) {
        matches.add(
          EditorSearchMatch(
            index: matches.length,
            range: SourceRange(start: index, end: end),
            text: source.substring(index, end),
          ),
        );
      }
      offset = end;
    }
    return List.unmodifiable(matches);
  }

  bool selectNextSearchMatch(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
  }) {
    final matches = searchDocument(
      query,
      caseSensitive: caseSensitive,
      wholeWord: wholeWord,
      useRegex: useRegex,
    );
    if (matches.isEmpty) {
      return false;
    }
    final startOffset = selection.end;
    final match = matches.firstWhere(
      (candidate) => candidate.range.start >= startOffset,
      orElse: () => matches.first,
    );
    selectRange(baseOffset: match.range.start, extentOffset: match.range.end);
    return true;
  }

  bool selectPreviousSearchMatch(
    String query, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
  }) {
    final matches = searchDocument(
      query,
      caseSensitive: caseSensitive,
      wholeWord: wholeWord,
      useRegex: useRegex,
    );
    if (matches.isEmpty) {
      return false;
    }
    final startOffset = selection.start;
    EditorSearchMatch? match;
    for (final candidate in matches.reversed) {
      if (candidate.range.end <= startOffset) {
        match = candidate;
        break;
      }
    }
    match ??= matches.last;
    selectRange(baseOffset: match.range.start, extentOffset: match.range.end);
    return true;
  }

  bool replaceSelectedSearchMatch(
    String query,
    String replacement, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
  }) {
    if (query.isEmpty || selection.isCollapsed) {
      return false;
    }
    if (useRegex) {
      final selectionMatches =
          searchDocument(
            query,
            caseSensitive: caseSensitive,
            wholeWord: wholeWord,
            useRegex: true,
          ).any(
            (match) =>
                match.range.start == selection.start &&
                match.range.end == selection.end,
          );
      if (!selectionMatches) {
        return false;
      }
      insertText(replacement);
      return true;
    }
    final selectedText = _document.text.substring(
      selection.start,
      selection.end,
    );
    final matches = caseSensitive
        ? selectedText == query
        : selectedText.toLowerCase() == query.toLowerCase();
    if (!matches ||
        (wholeWord &&
            !_isWholeWordSearchMatch(
              _document.text,
              selection.start,
              selection.end,
            )) ||
        selectedText == replacement) {
      return false;
    }
    insertText(replacement);
    return true;
  }

  int replaceAllSearchMatches(
    String query,
    String replacement, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool useRegex = false,
  }) {
    final matches = searchDocument(
      query,
      caseSensitive: caseSensitive,
      wholeWord: wholeWord,
      useRegex: useRegex,
    );
    final edits = <FormattingEdit>[
      for (final match in matches)
        if (match.text != replacement)
          FormattingEdit(range: match.range, newText: replacement),
    ];
    if (edits.isEmpty) {
      return 0;
    }
    applyFormattingEdits(edits);
    return edits.length;
  }

  List<EditorSearchMatch> _regexSearchDocument(
    String pattern, {
    required bool caseSensitive,
    required bool wholeWord,
  }) {
    late final RegExp expression;
    try {
      expression = RegExp(pattern, caseSensitive: caseSensitive);
    } on FormatException {
      return const <EditorSearchMatch>[];
    }
    final source = _document.text;
    final matches = <EditorSearchMatch>[];
    for (final match in expression.allMatches(source)) {
      if (match.start == match.end) {
        continue;
      }
      if (wholeWord &&
          !_isWholeWordSearchMatch(source, match.start, match.end)) {
        continue;
      }
      matches.add(
        EditorSearchMatch(
          index: matches.length,
          range: SourceRange(start: match.start, end: match.end),
          text: match.group(0) ?? source.substring(match.start, match.end),
        ),
      );
    }
    return List.unmodifiable(matches);
  }

  bool get canUndo => historyController.canUndo;
  bool get canRedo => historyController.canRedo;
  bool get shouldIndentLineAtSelection =>
      !_selection.isCollapsed || _isCaretWithinLeadingIndent();

  EditorSessionSnapshot toSessionSnapshot({
    List<String>? openDocumentIds,
    List<String>? dirtyDocumentIds,
    Map<String, int>? cursorOffsets,
    Map<String, int>? selectionAnchors,
  }) {
    return EditorSessionSnapshot(
      activeDocumentId: _document.documentId,
      openDocumentIds: openDocumentIds ?? <String>[_document.documentId],
      dirtyDocumentIds: dirtyDocumentIds ?? const <String>[],
      cursorOffsets: <String, int>{
        ...?cursorOffsets,
        _document.documentId: _selection.extentOffset,
      },
      selectionAnchors: <String, int>{
        ...?selectionAnchors,
        _document.documentId: _selection.baseOffset,
      },
    );
  }

  void loadDocument(DocumentState document) {
    _document = document;
    _selection = SelectionState.collapsed(document.length);
    _refreshAnalysis();
    historyController.clear();
    _structuredSelectionStack.clear();
    notifyListeners();
  }

  void refreshAnalysis() {
    _refreshAnalysis();
    notifyListeners();
  }

  void applyExternalDiagnostics(Iterable<Diagnostic> diagnostics) {
    final analysis = diagnosticsStore.applyExternalDiagnostics(
      baseAnalysis: _analysis,
      diagnostics: diagnostics,
    );
    if (analysis == null) {
      return;
    }
    _analysis = analysis;
    notifyListeners();
  }

  void selectCollapsed(int offset) {
    _structuredSelectionStack.clear();
    final clamped = offset.clamp(0, _document.length);
    _selection = SelectionState.collapsed(clamped);
    _refreshAnalysis();
    notifyListeners();
  }

  void selectRange({required int baseOffset, required int extentOffset}) {
    _structuredSelectionStack.clear();
    _selection = SelectionState(
      baseOffset: baseOffset.clamp(0, _document.length),
      extentOffset: extentOffset.clamp(0, _document.length),
    );
    _refreshAnalysis();
    notifyListeners();
  }

  void selectLineColumn({required int line, required int column}) {
    selectCollapsed(_document.offsetForLineColumn(line: line, column: column));
  }

  void insertText(String value) {
    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _replaceSelection(value);
    _clearRedoStack();
    notifyListeners();
  }

  void insertTypedCharacter(String value) {
    if (value.length == 1 && _insertSmartPairCharacter(value)) {
      return;
    }
    insertText(value);
  }

  void insertNewline() {
    _structuredSelectionStack.clear();
    final insertion = _newlineInsertion();
    final replacementStart = _selection.start;
    _pushUndoSnapshot();
    _replaceRange(
      start: replacementStart,
      end: _selection.end,
      replacement: insertion.text,
      selectionOffset: replacementStart + insertion.caretDelta,
    );
    _clearRedoStack();
    notifyListeners();
  }

  void backspace() {
    if (_selection.isCollapsed && _selection.end == 0) {
      return;
    }
    if (_deleteEmptyPairBeforeCaret()) {
      return;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();

    if (_selection.isCollapsed) {
      final deleteStart = _selection.end - 1;
      _replaceRange(
        start: deleteStart,
        end: _selection.end,
        replacement: '',
        selectionOffset: deleteStart,
      );
    } else {
      _replaceSelection('');
    }

    _clearRedoStack();
    notifyListeners();
  }

  void deleteForward() {
    if (_selection.isCollapsed && _selection.end >= _document.length) {
      return;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();

    if (_selection.isCollapsed) {
      _replaceRange(
        start: _selection.start,
        end: _selection.end + 1,
        replacement: '',
        selectionOffset: _selection.start,
      );
    } else {
      _replaceSelection('');
    }

    _clearRedoStack();
    notifyListeners();
  }

  bool deleteToWordBoundary({required bool forward}) {
    if (_selection.isCollapsed) {
      final boundary = forward
          ? _nextCaretStopOffset(_selection.end)
          : _previousCaretStopOffset(_selection.end);
      if (boundary == _selection.end) {
        return false;
      }

      _structuredSelectionStack.clear();
      _pushUndoSnapshot();
      _replaceRange(
        start: forward ? _selection.end : boundary,
        end: forward ? boundary : _selection.end,
        replacement: '',
        selectionOffset: forward ? _selection.end : boundary,
      );
      _clearRedoStack();
      notifyListeners();
      return true;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _replaceSelection('');
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  bool indentLineOrSelection() {
    return _shiftIndentLineOrSelection(indent: true);
  }

  bool outdentLineOrSelection() {
    return _shiftIndentLineOrSelection(indent: false);
  }

  bool deleteLineAtSelection() {
    final logicalLines = _logicalLinesForDocument(_document);
    if (logicalLines.isEmpty) {
      return false;
    }

    final lineRange = _lineRangeForSelectionAction(logicalLines.length);
    final startOffset = _offsetForLogicalLineStart(
      _document,
      lineRange.startLine,
    );
    final endOffset = _offsetAfterLogicalLine(
      _document,
      lineRange.endLine,
      logicalLines.length,
    );
    if (startOffset == endOffset) {
      return false;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _replaceDocumentRange(start: startOffset, end: endOffset, replacement: '');
    _selection = SelectionState.collapsed(
      startOffset.clamp(0, _document.length).toInt(),
    );
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  bool duplicateLineOrSelection() {
    _structuredSelectionStack.clear();

    if (!_selection.isCollapsed) {
      final selectedText = _document.text.substring(
        _selection.start,
        _selection.end,
      );
      if (selectedText.isEmpty) {
        return false;
      }

      _pushUndoSnapshot();
      final insertOffset = _selection.end;
      _replaceDocumentRange(
        start: insertOffset,
        end: insertOffset,
        replacement: selectedText,
      );
      _selection = SelectionState(
        baseOffset: insertOffset,
        extentOffset: insertOffset + selectedText.length,
      );
      _refreshAnalysis();
      _clearRedoStack();
      notifyListeners();
      return true;
    }

    final lines = _document.lines;
    if (lines.isEmpty) {
      return false;
    }

    final position = _document.positionForOffset(_selection.end);
    final lineIndex = position.line.clamp(0, lines.length - 1).toInt();
    final lineText = lines[lineIndex];
    final lineStart = _document.lineStarts[lineIndex];
    final lineEnd = lineStart + lineText.length;
    final hasTrailingNewline =
        lineEnd < _document.length && _document.text[lineEnd] == '\n';
    final insertOffset = hasTrailingNewline ? lineEnd + 1 : lineEnd;
    final duplicateText = hasTrailingNewline
        ? _document.text.substring(lineStart, lineEnd + 1)
        : '\n$lineText';
    final duplicateStart = hasTrailingNewline ? insertOffset : insertOffset + 1;
    final duplicateColumn = position.column.clamp(0, lineText.length).toInt();

    _pushUndoSnapshot();
    _replaceDocumentRange(
      start: insertOffset,
      end: insertOffset,
      replacement: duplicateText,
    );
    _selection = SelectionState.collapsed(
      (duplicateStart + duplicateColumn).clamp(0, _document.length).toInt(),
    );
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  bool moveLineOrSelection({required bool down}) {
    final logicalLines = _logicalLinesForDocument(_document);
    if (logicalLines.length <= 1) {
      return false;
    }

    final lineRange = _lineRangeForSelectionAction(logicalLines.length);
    final canMove = down
        ? lineRange.endLine < logicalLines.length - 1
        : lineRange.startLine > 0;
    if (!canMove) {
      return false;
    }

    final nextLines = <String>[];
    if (down) {
      nextLines
        ..addAll(logicalLines.take(lineRange.startLine))
        ..add(logicalLines[lineRange.endLine + 1])
        ..addAll(
          logicalLines.sublist(lineRange.startLine, lineRange.endLine + 1),
        )
        ..addAll(logicalLines.skip(lineRange.endLine + 2));
    } else {
      nextLines
        ..addAll(logicalLines.take(lineRange.startLine - 1))
        ..addAll(
          logicalLines.sublist(lineRange.startLine, lineRange.endLine + 1),
        )
        ..add(logicalLines[lineRange.startLine - 1])
        ..addAll(logicalLines.skip(lineRange.endLine + 1));
    }

    final nextText =
        nextLines.join('\n') + (_document.text.endsWith('\n') ? '\n' : '');
    if (nextText == _document.text) {
      return false;
    }

    final oldDocument = _document;
    final oldBlockStart = _offsetForLogicalLineStart(
      oldDocument,
      lineRange.startLine,
    );
    final oldBlockEnd = _offsetAfterLogicalLine(
      oldDocument,
      lineRange.endLine,
      logicalLines.length,
    );

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _replaceDocumentRange(
      start: 0,
      end: _document.length,
      replacement: nextText,
    );

    final nextLogicalLineCount = _logicalLinesForDocument(_document).length;
    _selection = SelectionState(
      baseOffset: _transformLineMoveOffset(
        _selection.baseOffset,
        oldDocument: oldDocument,
        nextDocument: _document,
        lineRange: lineRange,
        oldLogicalLineCount: logicalLines.length,
        nextLogicalLineCount: nextLogicalLineCount,
        oldBlockStart: oldBlockStart,
        oldBlockEnd: oldBlockEnd,
        down: down,
      ),
      extentOffset: _transformLineMoveOffset(
        _selection.extentOffset,
        oldDocument: oldDocument,
        nextDocument: _document,
        lineRange: lineRange,
        oldLogicalLineCount: logicalLines.length,
        nextLogicalLineCount: nextLogicalLineCount,
        oldBlockStart: oldBlockStart,
        oldBlockEnd: oldBlockEnd,
        down: down,
      ),
    );
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  bool joinLinesAtSelection() {
    final logicalLines = _logicalLinesForDocument(_document);
    if (logicalLines.length <= 1) {
      return false;
    }

    final lineRange = _lineRangeForSelectionAction(logicalLines.length);
    final startLine = lineRange.startLine;
    final endLine = lineRange.startLine == lineRange.endLine
        ? lineRange.endLine + 1
        : lineRange.endLine;
    if (endLine >= logicalLines.length) {
      return false;
    }

    final joinedText = _joinLineFragments(
      logicalLines.sublist(startLine, endLine + 1),
    );
    final replacementKeepsNewline =
        endLine < logicalLines.length - 1 || _document.text.endsWith('\n');
    final replacement = joinedText + (replacementKeepsNewline ? '\n' : '');
    final startOffset = _offsetForLogicalLineStart(_document, startLine);
    final endOffset = _offsetAfterLogicalLine(
      _document,
      endLine,
      logicalLines.length,
    );
    if (replacement == _document.text.substring(startOffset, endOffset)) {
      return false;
    }

    final caretOffset = _selection.isCollapsed
        ? startOffset +
              _firstJoinCaretOffset(logicalLines[startLine], joinedText)
        : null;

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _replaceDocumentRange(
      start: startOffset,
      end: endOffset,
      replacement: replacement,
    );
    _selection = caretOffset == null
        ? SelectionState(
            baseOffset: startOffset,
            extentOffset: startOffset + joinedText.length,
          )
        : SelectionState.collapsed(caretOffset);
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  void moveCaretHorizontally(int delta, {bool expandSelection = false}) {
    if (delta == 0) {
      return;
    }
    _structuredSelectionStack.clear();
    final nextOffset = (_selection.extentOffset + delta).clamp(
      0,
      _document.length,
    );
    if (expandSelection) {
      selectRange(baseOffset: _selection.baseOffset, extentOffset: nextOffset);
      return;
    }
    selectCollapsed(nextOffset);
  }

  void moveCaretByWord({required bool forward, bool expandSelection = false}) {
    final nextOffset = forward
        ? _nextCaretStopOffset(_selection.extentOffset)
        : _previousCaretStopOffset(_selection.extentOffset);
    if (nextOffset == _selection.extentOffset) {
      return;
    }

    _structuredSelectionStack.clear();
    if (expandSelection) {
      selectRange(baseOffset: _selection.baseOffset, extentOffset: nextOffset);
      return;
    }
    selectCollapsed(nextOffset);
  }

  void moveCaretVertically(int deltaLines, {bool expandSelection = false}) {
    if (deltaLines == 0) {
      return;
    }

    _structuredSelectionStack.clear();
    final position = _document.positionForOffset(_selection.extentOffset);
    final nextOffset = _document.offsetForLineColumn(
      line: position.line + deltaLines,
      column: position.column,
    );
    if (expandSelection) {
      selectRange(baseOffset: _selection.baseOffset, extentOffset: nextOffset);
      return;
    }
    selectCollapsed(nextOffset);
  }

  void moveCaretToLineBoundary({
    required bool end,
    bool expandSelection = false,
  }) {
    _structuredSelectionStack.clear();
    final position = _document.positionForOffset(_selection.extentOffset);
    final nextOffset = _document.offsetForLineColumn(
      line: position.line,
      column: end ? _document.lines[position.line].length : 0,
    );
    if (expandSelection) {
      selectRange(baseOffset: _selection.baseOffset, extentOffset: nextOffset);
      return;
    }
    selectCollapsed(nextOffset);
  }

  void moveCaretToSmartLineStart({bool expandSelection = false}) {
    _structuredSelectionStack.clear();
    final position = _document.positionForOffset(_selection.extentOffset);
    final lineText = _document.lines[position.line];
    final lineStart = _document.lineStarts[position.line];
    final indentLength = _leadingHorizontalWhitespaceLength(lineText);
    final firstCodeOffset = indentLength >= lineText.length
        ? lineStart
        : lineStart + indentLength;
    final lineStartOffset = lineStart;
    final currentOffset = _selection.extentOffset;
    var nextOffset = lineStartOffset;
    if (currentOffset == lineStartOffset || firstCodeOffset < currentOffset) {
      nextOffset = firstCodeOffset;
    }

    if (expandSelection) {
      selectRange(baseOffset: _selection.baseOffset, extentOffset: nextOffset);
      return;
    }
    selectCollapsed(nextOffset);
  }

  void applyCompletionItem(CompletionItem item) {
    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    final replacementRange =
        item.replacementRange ?? _completionReplacementRange();
    final replacementStart = replacementRange.start.clamp(0, _document.length);
    final replacementEnd = replacementRange.end.clamp(
      replacementStart,
      _document.length,
    );
    _replaceRange(
      start: replacementStart,
      end: replacementEnd,
      replacement: item.insertText,
      selectionOffset: replacementStart + item.insertText.length,
    );
    _clearRedoStack();
    notifyListeners();
  }

  bool applyBestCompletionAtSelection() {
    final completions = completionsAtSelection;
    if (completions.isEmpty) {
      return false;
    }
    applyCompletionItem(completions.first);
    return true;
  }

  bool applyTokenCompletionAtSelection() {
    if (!_selection.isCollapsed) {
      return false;
    }
    final token = tokenAtSelection;
    if (token == null || token.kind != TokenKind.identifier) {
      return false;
    }
    final completions = completionsAtSelection;
    if (completions.isEmpty) {
      return false;
    }
    applyCompletionItem(completions.first);
    return true;
  }

  bool applySurroundTemplateAtSelection(SurroundTemplate template) {
    final range = _surroundRangeForSelection();
    if (range == null) {
      return false;
    }
    final selectedText = _document.text.substring(range.start, range.end);
    if (selectedText.trim().isEmpty) {
      return false;
    }

    final replacement = _surroundReplacement(
      template: template,
      selectedText: selectedText,
    );
    if (replacement.text == selectedText) {
      return false;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _replaceDocumentRange(
      start: range.start,
      end: range.end,
      replacement: replacement.text,
    );
    _selection = SelectionState(
      baseOffset: range.start + replacement.bodyStart,
      extentOffset: range.start + replacement.bodyEnd,
    );
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  bool moveCaretToMatchingBrace() {
    final targetOffset = _matchingBraceTargetOffset();
    if (targetOffset == null) {
      return false;
    }
    selectCollapsed(targetOffset);
    return true;
  }

  void applyFormattingEdits(
    Iterable<FormattingEdit> edits, {
    WorkspaceEditSource source = WorkspaceEditSource.formatting,
    String? label,
  }) {
    final normalizedEdits = normalizeFormattingEditsForDocument(
      documentLength: _document.length,
      edits: edits,
    );
    if (normalizedEdits.isEmpty) {
      return;
    }

    _structuredSelectionStack.clear();
    final editsAscending = normalizedEdits.toList(growable: false)
      ..sort((left, right) => left.range.start.compareTo(right.range.start));
    final nextBaseOffset = _transformOffsetWithEdits(
      _selection.baseOffset,
      editsAscending,
    );
    final nextExtentOffset = _transformOffsetWithEdits(
      _selection.extentOffset,
      editsAscending,
    );
    final workspaceEdit = WorkspaceEdit.fromFormattingEdits(
      document: _document,
      source: source,
      edits: editsAscending,
      label: label,
    );
    final validation = transactionController.validateForDocument(
      document: _document,
      edit: workspaceEdit,
    );
    if (!validation.isValid) {
      return;
    }

    _pushUndoSnapshot();

    final result = transactionController.applyToDocument(
      document: _document,
      edit: workspaceEdit,
    );
    if (!result.isApplied) {
      return;
    }

    _document = result.document;
    _selection = SelectionState(
      baseOffset: nextBaseOffset.clamp(0, _document.length),
      extentOffset: nextExtentOffset.clamp(0, _document.length),
    );
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
  }

  EditorCommandTransaction createCommandTransaction({
    required String commandId,
    required WorkspaceEdit edit,
    SelectionState? selectionAfter,
    String? label,
  }) {
    return transactionController.createCommandTransaction(
      commandId: commandId,
      edit: edit,
      selectionAfter: selectionAfter,
      label: label,
    );
  }

  EditorCommandTransactionResult applyCommandTransaction(
    EditorCommandTransaction transaction,
  ) {
    final result = transactionController.applyCommandTransaction(
      document: _document,
      selectionBefore: _selection,
      transaction: transaction,
    );
    if (!result.isApplied) {
      return result;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    _document = result.result.document;
    _selection = result.selectionAfter;
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return result;
  }

  EditorCommandTransactionResult executeCommandTransaction(
    EditorCommandTransaction transaction,
  ) {
    return applyCommandTransaction(transaction);
  }

  void applyDiagnosticQuickFix(DiagnosticQuickFix fix) {
    applyFormattingEdits(
      fix.edits,
      source: WorkspaceEditSource.codeAction,
      label: fix.label,
    );
  }

  DiagnosticQuickFix? quickFixAtSelectionForInput(String? input) {
    final fixes = contextActionsAtSelection;
    if (fixes.isEmpty) {
      return null;
    }

    final normalizedInput = input?.trim();
    if (normalizedInput == null || normalizedInput.isEmpty) {
      return fixes.first;
    }

    final requestedIndex = int.tryParse(normalizedInput);
    if (requestedIndex != null) {
      if (requestedIndex == 0) {
        return fixes.first;
      }
      if (requestedIndex > 0 && requestedIndex <= fixes.length) {
        return fixes[requestedIndex - 1];
      }
      return null;
    }

    final requestedLabel = normalizedInput.toLowerCase();
    for (final fix in fixes) {
      if (fix.label.trim().toLowerCase() == requestedLabel) {
        return fix;
      }
    }

    for (final fix in fixes) {
      if (fix.label.trim().toLowerCase().contains(requestedLabel)) {
        return fix;
      }
    }

    return null;
  }

  bool applyQuickFixAtSelection({String? input}) {
    final fix = quickFixAtSelectionForInput(input);
    if (fix == null) {
      return false;
    }
    applyDiagnosticQuickFix(fix);
    return true;
  }

  bool applyFirstQuickFixAtSelection() => applyQuickFixAtSelection();

  bool applyRename(String newName) {
    final plan = renamePlanAtSelection(newName);
    if (plan == null || plan.hasConflicts) {
      return false;
    }
    applyFormattingEdits(
      plan.edits,
      source: WorkspaceEditSource.rename,
      label: 'Rename symbol',
    );
    return true;
  }

  bool applySafeDeleteAtSelection() {
    final plan = safeDeletePlanAtSelection;
    if (plan == null || plan.hasConflicts || plan.edits.isEmpty) {
      return false;
    }
    applyFormattingEdits(
      plan.edits,
      source: WorkspaceEditSource.refactor,
      label: 'Safe delete',
    );
    return true;
  }

  bool applyInlineVariableAtSelection() {
    final plan = inlineVariablePlanAtSelection;
    if (plan == null || plan.hasConflicts || plan.edits.isEmpty) {
      return false;
    }
    applyFormattingEdits(
      plan.edits,
      source: WorkspaceEditSource.refactor,
      label: 'Inline variable',
    );
    return true;
  }

  bool applyIntroduceVariableAtSelection(String name) {
    final plan = introduceVariablePlanAtSelection(name);
    if (plan == null || plan.hasConflicts || plan.edits.isEmpty) {
      return false;
    }
    applyFormattingEdits(
      plan.edits,
      source: WorkspaceEditSource.refactor,
      label: 'Introduce variable',
    );
    return true;
  }

  bool applyExtractFunctionAtSelection(String name) {
    final plan = extractFunctionPlanAtSelection(name);
    if (plan == null || plan.hasConflicts || plan.edits.isEmpty) {
      return false;
    }
    applyFormattingEdits(
      plan.edits,
      source: WorkspaceEditSource.refactor,
      label: 'Extract function',
    );
    return true;
  }

  bool applyChangeSignatureAtSelection({
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    final plan = changeSignaturePlanAtSelection(
      newName: newName,
      parameters: parameters,
    );
    if (plan == null || plan.hasConflicts || plan.edits.isEmpty) {
      return false;
    }
    applyFormattingEdits(
      plan.edits,
      source: WorkspaceEditSource.refactor,
      label: 'Change signature',
    );
    return true;
  }

  bool toggleLineComment() {
    final lineRange = _lineRangeForCommentToggle();
    final lines = _document.lines;
    final lineStarts = _document.lineStarts;
    final singleLine = lineRange.startLine == lineRange.endLine;
    final targetLines = <int>[];

    for (
      var lineIndex = lineRange.startLine;
      lineIndex <= lineRange.endLine;
      lineIndex += 1
    ) {
      final lineText = lines[lineIndex];
      if (!singleLine && lineText.trim().isEmpty) {
        continue;
      }
      targetLines.add(lineIndex);
    }

    if (targetLines.isEmpty) {
      return false;
    }

    final shouldUncomment = targetLines.every(
      (lineIndex) =>
          _lineCommentPrefixOffset(
            lineText: lines[lineIndex],
            lineStart: lineStarts[lineIndex],
          ) !=
          null,
    );
    final edits = <FormattingEdit>[];

    for (final lineIndex in targetLines) {
      final lineText = lines[lineIndex];
      final lineStart = lineStarts[lineIndex];
      if (shouldUncomment) {
        final prefixOffset = _lineCommentPrefixOffset(
          lineText: lineText,
          lineStart: lineStart,
        );
        if (prefixOffset == null) {
          continue;
        }
        final localPrefixOffset = prefixOffset - lineStart;
        var removeEnd = prefixOffset + 2;
        if (localPrefixOffset + 2 < lineText.length &&
            lineText[localPrefixOffset + 2] == ' ') {
          removeEnd += 1;
        }
        edits.add(
          FormattingEdit(
            range: SourceRange(start: prefixOffset, end: removeEnd),
            newText: '',
          ),
        );
      } else {
        final insertOffset =
            lineStart + _leadingHorizontalWhitespaceLength(lineText);
        edits.add(
          FormattingEdit(
            range: SourceRange(start: insertOffset, end: insertOffset),
            newText: '// ',
          ),
        );
      }
    }

    if (edits.isEmpty) {
      return false;
    }

    applyFormattingEdits(edits);
    return true;
  }

  bool extendSelectionStructurally() {
    final current = SourceRange(start: _selection.start, end: _selection.end);
    final candidates = _structuredSelectionCandidates(current);
    if (candidates.isEmpty) {
      return false;
    }

    _structuredSelectionStack.add(_selection);
    final next = candidates.first;
    _selection = SelectionState(baseOffset: next.start, extentOffset: next.end);
    _refreshAnalysis();
    notifyListeners();
    return true;
  }

  bool shrinkSelectionStructurally() {
    if (_structuredSelectionStack.isEmpty) {
      return false;
    }

    _selection = _structuredSelectionStack.removeLast();
    _refreshAnalysis();
    notifyListeners();
    return true;
  }

  bool selectDefinitionAtSelection() {
    _structuredSelectionStack.clear();
    final definition = definitionAtSelection;
    if (definition == null) {
      return false;
    }
    return selectDocumentSymbol(definition.symbol);
  }

  bool selectDocumentSymbol(DocumentSymbol symbol) {
    _structuredSelectionStack.clear();
    final range = symbol.nameRange;
    if (range.start < 0 ||
        range.end < range.start ||
        range.end > _document.length) {
      return false;
    }
    _selection = SelectionState(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    notifyListeners();
    return true;
  }

  bool selectDiagnostic(Diagnostic diagnostic) {
    _structuredSelectionStack.clear();
    final range = diagnostic.range;
    if (range.start < 0 ||
        range.end < range.start ||
        range.end > _document.length) {
      return false;
    }
    _selection = SelectionState(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    notifyListeners();
    return true;
  }

  bool selectReference(ReferenceSpan reference) {
    _structuredSelectionStack.clear();
    final range = reference.range;
    if (range.start < 0 ||
        range.end < range.start ||
        range.end > _document.length) {
      return false;
    }
    _selection = SelectionState(
      baseOffset: range.start,
      extentOffset: range.end,
    );
    _refreshAnalysis();
    notifyListeners();
    return true;
  }

  bool selectNextReferenceAtSelection() {
    return _selectReferenceAtSelection(forward: true);
  }

  bool selectPreviousReferenceAtSelection() {
    return _selectReferenceAtSelection(forward: false);
  }

  bool selectNextDiagnosticAtSelection() {
    return _selectDiagnostic(forward: true);
  }

  bool selectPreviousDiagnosticAtSelection() {
    return _selectDiagnostic(forward: false);
  }

  void _replaceSelection(String replacement) {
    final start = _selection.start;
    _replaceRange(
      start: start,
      end: _selection.end,
      replacement: replacement,
      selectionOffset: start + replacement.length,
    );
  }

  void _replaceRange({
    required int start,
    required int end,
    required String replacement,
    required int selectionOffset,
  }) {
    _replaceDocumentRange(start: start, end: end, replacement: replacement);
    _selection = SelectionState.collapsed(selectionOffset);
  }

  bool _replaceDocumentRange({
    required int start,
    required int end,
    required String replacement,
    WorkspaceEditSource source = WorkspaceEditSource.userInput,
    String? label,
  }) {
    final workspaceEdit = WorkspaceEdit.singleDocument(
      document: _document,
      source: source,
      label: label,
      edits: <WorkspaceTextEdit>[
        WorkspaceTextEdit(
          documentId: _document.documentId,
          range: SourceRange(start: start, end: end),
          newText: replacement,
        ),
      ],
    );
    final result = transactionController.applyToDocument(
      document: _document,
      edit: workspaceEdit,
    );
    if (!result.isApplied) {
      return false;
    }
    _document = result.document;
    _refreshAnalysis();
    return true;
  }

  bool _insertSmartPairCharacter(String character) {
    final close = _pairedCloseForOpening(character);
    if (close != null) {
      _structuredSelectionStack.clear();
      _pushUndoSnapshot();
      final selectedText = _document.text.substring(
        _selection.start,
        _selection.end,
      );
      final replacement = '$character$selectedText$close';
      final selectionOffset = _selection.isCollapsed
          ? _selection.start + 1
          : _selection.start + replacement.length;
      _replaceDocumentRange(
        start: _selection.start,
        end: _selection.end,
        replacement: replacement,
      );
      _selection = SelectionState.collapsed(
        selectionOffset.clamp(0, _document.length).toInt(),
      );
      _refreshAnalysis();
      _clearRedoStack();
      notifyListeners();
      return true;
    }

    if (_selection.isCollapsed &&
        _isPairedClosing(character) &&
        _selection.end < _document.length &&
        _document.text[_selection.end] == character) {
      _structuredSelectionStack.clear();
      _selection = SelectionState.collapsed(_selection.end + 1);
      _refreshAnalysis();
      notifyListeners();
      return true;
    }

    return false;
  }

  bool _deleteEmptyPairBeforeCaret() {
    if (!_selection.isCollapsed ||
        _selection.end == 0 ||
        _selection.end >= _document.length) {
      return false;
    }

    final opening = _document.text[_selection.end - 1];
    final closing = _document.text[_selection.end];
    if (_pairedCloseForOpening(opening) != closing) {
      return false;
    }

    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    final selectionOffset = _selection.end - 1;
    _replaceDocumentRange(
      start: selectionOffset,
      end: _selection.end + 1,
      replacement: '',
    );
    _selection = SelectionState.collapsed(selectionOffset);
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
    return true;
  }

  _NewlineInsertion _newlineInsertion() {
    final offset = (_selection.isCollapsed ? _selection.end : _selection.start)
        .clamp(0, _document.length)
        .toInt();
    final position = _document.positionForOffset(offset);
    final lineText = _document.lines[position.line];
    final baseIndentLength = _leadingHorizontalWhitespaceLength(lineText);
    final baseIndent = lineText.substring(0, baseIndentLength);

    if (_selection.isCollapsed && _hasImmediatePairAroundOffset(offset)) {
      final innerIndent = '$baseIndent  ';
      return _NewlineInsertion(
        text: '\n$innerIndent\n$baseIndent',
        caretDelta: 1 + innerIndent.length,
      );
    }

    final indent = _selection.isCollapsed && _hasOpeningPairBeforeOffset(offset)
        ? '$baseIndent  '
        : baseIndent;
    return _NewlineInsertion(text: '\n$indent', caretDelta: 1 + indent.length);
  }

  bool _hasImmediatePairAroundOffset(int offset) {
    if (offset <= 0 || offset >= _document.length) {
      return false;
    }

    final opening = _document.text[offset - 1];
    final closing = _document.text[offset];
    return _isBlockOpeningPair(opening) &&
        _pairedCloseForOpening(opening) == closing;
  }

  bool _hasOpeningPairBeforeOffset(int offset) {
    for (var index = offset - 1; index >= 0; index -= 1) {
      final codeUnit = _document.text.codeUnitAt(index);
      if (_isHorizontalWhitespace(codeUnit)) {
        continue;
      }
      return _isBlockOpeningPair(_document.text[index]);
    }
    return false;
  }

  bool _isCaretWithinLeadingIndent() {
    if (!_selection.isCollapsed) {
      return false;
    }

    final position = _document.positionForOffset(_selection.end);
    final lineText = _document.lines[position.line];
    return position.column <= _leadingHorizontalWhitespaceLength(lineText);
  }

  bool _shiftIndentLineOrSelection({required bool indent}) {
    final logicalLines = _logicalLinesForDocument(_document);
    if (logicalLines.isEmpty) {
      return false;
    }

    final lineRange = _lineRangeForSelectionAction(logicalLines.length);
    final edits = <FormattingEdit>[];
    for (
      var lineIndex = lineRange.startLine;
      lineIndex <= lineRange.endLine;
      lineIndex += 1
    ) {
      final lineStart = _offsetForLogicalLineStart(_document, lineIndex);
      if (indent) {
        edits.add(
          FormattingEdit(
            range: SourceRange(start: lineStart, end: lineStart),
            newText: '  ',
          ),
        );
        continue;
      }

      final removeLength = _lineOutdentLength(_document.lines[lineIndex]);
      if (removeLength > 0) {
        edits.add(
          FormattingEdit(
            range: SourceRange(start: lineStart, end: lineStart + removeLength),
            newText: '',
          ),
        );
      }
    }

    if (edits.isEmpty) {
      return false;
    }

    _applyLineIndentEdits(edits);
    return true;
  }

  void _applyLineIndentEdits(List<FormattingEdit> edits) {
    final editsAscending = edits.toList(growable: false)
      ..sort((left, right) => left.range.start.compareTo(right.range.start));
    final moveAtInsertion = _selection.isCollapsed;
    final nextBaseOffset = _transformLineIndentOffset(
      _selection.baseOffset,
      editsAscending,
      moveAtInsertion: moveAtInsertion,
    );
    final nextExtentOffset = _transformLineIndentOffset(
      _selection.extentOffset,
      editsAscending,
      moveAtInsertion: moveAtInsertion,
    );

    _structuredSelectionStack.clear();
    final workspaceEdit = WorkspaceEdit.fromFormattingEdits(
      document: _document,
      source: WorkspaceEditSource.userInput,
      edits: editsAscending,
      label: 'Indent lines',
    );
    final validation = transactionController.validateForDocument(
      document: _document,
      edit: workspaceEdit,
    );
    if (!validation.isValid) {
      return;
    }

    _pushUndoSnapshot();

    final result = transactionController.applyToDocument(
      document: _document,
      edit: workspaceEdit,
    );
    if (!result.isApplied) {
      return;
    }

    _document = result.document;
    _selection = SelectionState(
      baseOffset: nextBaseOffset.clamp(0, _document.length),
      extentOffset: nextExtentOffset.clamp(0, _document.length),
    );
    _refreshAnalysis();
    _clearRedoStack();
    notifyListeners();
  }

  int _transformLineIndentOffset(
    int offset,
    List<FormattingEdit> editsAscending, {
    required bool moveAtInsertion,
  }) {
    var delta = 0;
    for (final edit in editsAscending) {
      final start = edit.range.start;
      final end = edit.range.end;
      final replacementLength = edit.newText.length;
      final originalLength = end - start;

      if (offset < start) {
        break;
      }

      if (originalLength == 0) {
        if (offset == start) {
          if (moveAtInsertion) {
            delta += replacementLength;
          }
          continue;
        }
        delta += replacementLength;
        continue;
      }

      if (offset <= end) {
        final relativeOffset = offset - start;
        final clampedRelativeOffset = relativeOffset.clamp(
          0,
          replacementLength,
        );
        return start + delta + clampedRelativeOffset;
      }

      delta += replacementLength - originalLength;
    }

    return offset + delta;
  }

  int _lineOutdentLength(String lineText) {
    if (lineText.isEmpty) {
      return 0;
    }
    if (lineText.codeUnitAt(0) == 0x09) {
      return 1;
    }

    var spaces = 0;
    while (spaces < lineText.length &&
        spaces < 2 &&
        lineText.codeUnitAt(spaces) == 0x20) {
      spaces += 1;
    }
    return spaces;
  }

  void undo() {
    if (!canUndo) {
      return;
    }
    _structuredSelectionStack.clear();
    historyController.pushRedo(_captureSnapshot());
    final snapshot = historyController.popUndo();
    if (snapshot == null) {
      return;
    }
    _document = snapshot.document;
    _selection = snapshot.selection;
    _refreshAnalysis();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) {
      return;
    }
    _structuredSelectionStack.clear();
    historyController.pushUndo(_captureSnapshot());
    final snapshot = historyController.popRedo();
    if (snapshot == null) {
      return;
    }
    _document = snapshot.document;
    _selection = snapshot.selection;
    _refreshAnalysis();
    notifyListeners();
  }

  EditorHistorySnapshot _captureSnapshot() {
    return EditorHistorySnapshot(document: _document, selection: _selection);
  }

  void _pushUndoSnapshot() {
    historyController.pushUndo(_captureSnapshot());
  }

  void _clearRedoStack() {
    historyController.clearRedo();
  }

  void _refreshAnalysis() {
    languageFeatureController.refresh(_document);
    diagnosticsStore.resetForDocumentLength(_document.length);
    semanticTokenStore.updateFromAnalysis(_analysis);
    _rebuildAnalysisIndexes();
  }

  void _rebuildAnalysisIndexes() {
    _diagnosticIndex = RangeIndex<Diagnostic>.fromValues(
      _analysis.diagnostics,
      startOf: (diagnostic) => diagnostic.range.start,
      endOf: (diagnostic) => diagnostic.range.end,
      revision: _document.revision,
      priorityOf: (diagnostic) => switch (diagnostic.severity) {
        DiagnosticSeverity.error => 30,
        DiagnosticSeverity.warning => 20,
        DiagnosticSeverity.hint => 10,
      },
      layerOf: (_) => 'diagnostics',
    );
    _semanticSpanIndex = RangeIndex<SemanticSpan>.fromValues(
      _analysis.semanticSpans,
      startOf: (span) => span.range.start,
      endOf: (span) => span.range.end,
      revision: _document.revision,
      layerOf: (_) => 'semantic',
    );
  }

  SourceRange _completionReplacementRange() {
    if (!_selection.isCollapsed) {
      return SourceRange(start: _selection.start, end: _selection.end);
    }

    for (final token in _analysis.tokenSpans) {
      final touchesCaret =
          token.range.contains(_selection.end) ||
          token.range.end == _selection.end;
      if (!touchesCaret) {
        continue;
      }

      switch (token.kind) {
        case TokenKind.identifier:
        case TokenKind.keyword:
        case TokenKind.unknown:
          return token.range;
        case TokenKind.number:
        case TokenKind.string:
        case TokenKind.comment:
        case TokenKind.operator:
        case TokenKind.punctuation:
        case TokenKind.whitespace:
          break;
      }
    }

    return SourceRange(start: _selection.end, end: _selection.end);
  }

  int _nextCaretStopOffset(int offset) {
    final safeOffset = offset.clamp(0, _document.length).toInt();
    if (safeOffset >= _document.length) {
      return _document.length;
    }

    for (final stop in _caretStopOffsets()) {
      if (stop > safeOffset) {
        return stop;
      }
    }
    return _document.length;
  }

  int _previousCaretStopOffset(int offset) {
    final safeOffset = offset.clamp(0, _document.length).toInt();
    if (safeOffset <= 0) {
      return 0;
    }

    var previous = 0;
    for (final stop in _caretStopOffsets()) {
      if (stop >= safeOffset) {
        return previous;
      }
      previous = stop;
    }
    return previous;
  }

  List<int> _caretStopOffsets() {
    final stops = <int>{0, _document.length};

    final lines = _document.lines;
    final lineStarts = _document.lineStarts;
    for (var index = 0; index < lines.length; index += 1) {
      final lineStart = lineStarts[index];
      stops
        ..add(lineStart)
        ..add(lineStart + lines[index].length);
    }

    for (final token in _analysis.tokenSpans) {
      if (token.kind == TokenKind.whitespace) {
        continue;
      }
      stops
        ..add(token.range.start)
        ..add(token.range.end);
      if (token.kind == TokenKind.identifier ||
          token.kind == TokenKind.keyword) {
        for (final offset in _identifierCaretStops(token)) {
          stops.add(offset);
        }
      }
    }

    return stops.where((stop) => stop >= 0 && stop <= _document.length).toList()
      ..sort();
  }

  Iterable<int> _identifierCaretStops(TokenSpan token) sync* {
    final lexeme = token.lexeme;
    for (var index = 1; index < lexeme.length; index += 1) {
      final previous = lexeme.codeUnitAt(index - 1);
      final current = lexeme.codeUnitAt(index);
      if (previous == 0x5F ||
          current == 0x5F ||
          (_isLowerAscii(previous) && _isUpperAscii(current))) {
        yield token.range.start + index;
      }
    }
  }

  int _transformOffsetWithEdits(
    int offset,
    List<FormattingEdit> editsAscending,
  ) {
    var delta = 0;
    for (final edit in editsAscending) {
      final start = edit.range.start;
      final end = edit.range.end;
      final replacementLength = edit.newText.length;
      final originalLength = end - start;

      if (offset < start) {
        break;
      }

      if (offset <= end) {
        final relativeOffset = offset - start;
        final clampedRelativeOffset = relativeOffset.clamp(
          0,
          replacementLength,
        );
        return start + delta + clampedRelativeOffset;
      }

      delta += replacementLength - originalLength;
    }

    return offset + delta;
  }

  TokenSpan? _tokenAroundOffset(int offset) {
    return semanticTokenStore.tokenAroundOffset(
      document: _document,
      offset: offset,
    );
  }

  List<SourceRange> _structuredSelectionCandidates(SourceRange current) {
    final candidates = <SourceRange>[];
    final token = tokenAtSelection;
    if (token != null) {
      candidates.add(token.range);
    }

    candidates.add(_lineRangeForSelection(current));

    for (final symbol in _analysis.documentSymbols) {
      candidates
        ..add(symbol.nameRange)
        ..add(symbol.declarationRange);
    }
    for (final block in _analysis.semanticBlocks) {
      candidates.add(block.range);
    }

    candidates.add(SourceRange(start: 0, end: _document.length));

    final seen = <String>{};
    final normalized = <SourceRange>[];
    for (final candidate in candidates) {
      final start = candidate.clampStart(0, _document.length);
      final end = candidate.clampEnd(start, _document.length);
      if (start == end) {
        continue;
      }
      final normalizedCandidate = SourceRange(start: start, end: end);
      if (!_strictlyContainsSelection(normalizedCandidate, current)) {
        continue;
      }
      final key = '$start:$end';
      if (seen.add(key)) {
        normalized.add(normalizedCandidate);
      }
    }

    normalized.sort((left, right) {
      final leftLength = left.end - left.start;
      final rightLength = right.end - right.start;
      final byLength = leftLength.compareTo(rightLength);
      if (byLength != 0) {
        return byLength;
      }
      return left.start.compareTo(right.start);
    });
    return normalized;
  }

  SourceRange _lineRangeForSelection(SourceRange current) {
    final startPosition = _document.positionForOffset(current.start);
    final endPosition = _document.positionForOffset(current.end);
    final start = _document.offsetForLineColumn(
      line: startPosition.line,
      column: 0,
    );
    final endLine = endPosition.line.clamp(0, _document.lines.length - 1);
    final end = _document.offsetForLineColumn(
      line: endLine,
      column: _document.lines[endLine].length,
    );
    return SourceRange(start: start, end: end);
  }

  SourceRange? _surroundRangeForSelection() {
    final logicalLines = _logicalLinesForDocument(_document);
    if (logicalLines.isEmpty) {
      return null;
    }

    final lineRange = _lineRangeForSelectionAction(logicalLines.length);
    final lines = _document.lines;
    if (lines.isEmpty) {
      return null;
    }
    final startLine = lineRange.startLine.clamp(0, lines.length - 1).toInt();
    final endLine = lineRange.endLine
        .clamp(startLine, lines.length - 1)
        .toInt();
    final start = _document.offsetForLineColumn(line: startLine, column: 0);
    final end = _document.offsetForLineColumn(
      line: endLine,
      column: lines[endLine].length,
    );
    if (start > end) {
      return null;
    }
    return SourceRange(start: start, end: end);
  }

  _SurroundReplacement _surroundReplacement({
    required SurroundTemplate template,
    required String selectedText,
  }) {
    final baseIndent = _baseIndentForSurround(selectedText);
    final bodyLines = selectedText.split('\n');
    final bodyText = bodyLines
        .map((line) {
          if (line.isEmpty) {
            return '';
          }
          final unindented = line.startsWith(baseIndent)
              ? line.substring(baseIndent.length)
              : line.substring(_leadingHorizontalWhitespaceLength(line));
          return '$baseIndent${template.bodyIndent}$unindented';
        })
        .join('\n');

    final openingText = '$baseIndent${template.openingLine}\n';
    final closingText = '\n$baseIndent${template.closingLine}';
    return _SurroundReplacement(
      text: '$openingText$bodyText$closingText',
      bodyStart: openingText.length,
      bodyEnd: openingText.length + bodyText.length,
    );
  }

  String _baseIndentForSurround(String selectedText) {
    for (final line in selectedText.split('\n')) {
      if (line.trim().isEmpty) {
        continue;
      }
      return line.substring(0, _leadingHorizontalWhitespaceLength(line));
    }
    return '';
  }

  int? _matchingBraceTargetOffset() {
    final token = _braceTokenAroundOffset(_selection.extentOffset);
    if (token != null) {
      return _matchingBraceOffsetForToken(token);
    }
    return _previousUnclosedOpeningBraceOffset(_selection.extentOffset);
  }

  TokenSpan? _braceTokenAroundOffset(int offset) {
    final safeOffset = offset.clamp(0, _document.length);
    TokenSpan? trailingBrace;
    TokenSpan? leadingBrace;

    for (final token in _analysis.tokenSpans) {
      if (!_isBraceToken(token)) {
        continue;
      }
      if (token.range.contains(safeOffset)) {
        return token;
      }
      if (token.range.end == safeOffset) {
        trailingBrace = token;
      }
      if (leadingBrace == null && token.range.start == safeOffset) {
        leadingBrace = token;
      }
    }

    return trailingBrace ?? leadingBrace;
  }

  int? _matchingBraceOffsetForToken(TokenSpan token) {
    final lexeme = token.lexeme;
    if (_isOpeningBrace(lexeme)) {
      final closeLexeme = _matchingCloseBrace(lexeme);
      var depth = 0;
      for (final candidate in _analysis.tokenSpans) {
        if (candidate.range.start < token.range.start ||
            !_isBraceToken(candidate)) {
          continue;
        }
        if (candidate.lexeme == lexeme) {
          depth += 1;
        } else if (candidate.lexeme == closeLexeme) {
          depth -= 1;
          if (depth == 0) {
            return candidate.range.end;
          }
        }
      }
      return null;
    }

    if (_isClosingBrace(lexeme)) {
      final openLexeme = _matchingOpenBrace(lexeme);
      var depth = 0;
      for (final candidate in _analysis.tokenSpans.reversed) {
        if (candidate.range.end > token.range.end ||
            !_isBraceToken(candidate)) {
          continue;
        }
        if (candidate.lexeme == lexeme) {
          depth += 1;
        } else if (candidate.lexeme == openLexeme) {
          depth -= 1;
          if (depth == 0) {
            return candidate.range.start;
          }
        }
      }
    }

    return null;
  }

  int? _previousUnclosedOpeningBraceOffset(int offset) {
    final safeOffset = offset.clamp(0, _document.length);
    final stack = <TokenSpan>[];

    for (final token in _analysis.tokenSpans) {
      if (token.range.start >= safeOffset) {
        break;
      }
      if (!_isBraceToken(token)) {
        continue;
      }
      if (_isOpeningBrace(token.lexeme)) {
        stack.add(token);
        continue;
      }
      if (stack.isEmpty) {
        continue;
      }
      final last = stack.last;
      if (_matchingCloseBrace(last.lexeme) == token.lexeme) {
        stack.removeLast();
      }
    }

    return stack.isEmpty ? null : stack.last.range.start;
  }

  bool _isBraceToken(TokenSpan token) {
    return token.kind == TokenKind.punctuation &&
        (token.lexeme == '{' ||
            token.lexeme == '}' ||
            token.lexeme == '(' ||
            token.lexeme == ')' ||
            token.lexeme == '[' ||
            token.lexeme == ']');
  }

  bool _isOpeningBrace(String lexeme) {
    return lexeme == '{' || lexeme == '(' || lexeme == '[';
  }

  bool _isClosingBrace(String lexeme) {
    return lexeme == '}' || lexeme == ')' || lexeme == ']';
  }

  String? _matchingCloseBrace(String lexeme) {
    return switch (lexeme) {
      '{' => '}',
      '(' => ')',
      '[' => ']',
      _ => null,
    };
  }

  String? _matchingOpenBrace(String lexeme) {
    return switch (lexeme) {
      '}' => '{',
      ')' => '(',
      ']' => '[',
      _ => null,
    };
  }

  String? _pairedCloseForOpening(String lexeme) {
    return switch (lexeme) {
      '{' => '}',
      '(' => ')',
      '[' => ']',
      '"' => '"',
      _ => null,
    };
  }

  bool _isPairedClosing(String lexeme) {
    return lexeme == '}' || lexeme == ')' || lexeme == ']' || lexeme == '"';
  }

  bool _isBlockOpeningPair(String lexeme) {
    return lexeme == '{' || lexeme == '(' || lexeme == '[';
  }

  _CommentLineRange _lineRangeForCommentToggle() {
    final lineCount = _document.lines.length;
    final startPosition = _document.positionForOffset(_selection.start);
    var endOffset = _selection.end;
    if (!_selection.isCollapsed && endOffset > _selection.start) {
      final endPosition = _document.positionForOffset(endOffset);
      if (endPosition.column == 0 && endPosition.line > startPosition.line) {
        endOffset -= 1;
      }
    }

    final endPosition = _document.positionForOffset(endOffset);
    return _CommentLineRange(
      startLine: startPosition.line.clamp(0, lineCount - 1),
      endLine: endPosition.line.clamp(0, lineCount - 1),
    );
  }

  _LineMoveRange _lineRangeForSelectionAction(int logicalLineCount) {
    final startPosition = _document.positionForOffset(_selection.start);
    var endOffset = _selection.end;
    if (!_selection.isCollapsed && endOffset > _selection.start) {
      final endPosition = _document.positionForOffset(endOffset);
      if (endPosition.column == 0 && endPosition.line > startPosition.line) {
        endOffset -= 1;
      }
    }

    final endPosition = _document.positionForOffset(endOffset);
    return _LineMoveRange(
      startLine: startPosition.line.clamp(0, logicalLineCount - 1).toInt(),
      endLine: endPosition.line.clamp(0, logicalLineCount - 1).toInt(),
    );
  }

  String _joinLineFragments(List<String> lines) {
    if (lines.isEmpty) {
      return '';
    }

    var joined = _trimTrailingHorizontalWhitespace(lines.first);
    for (final rawLine in lines.skip(1)) {
      final next = rawLine.substring(
        _leadingHorizontalWhitespaceLength(rawLine),
      );
      final separator = _joinSeparator(joined, next);
      joined = _trimTrailingHorizontalWhitespace('$joined$separator$next');
    }
    return joined;
  }

  int _firstJoinCaretOffset(String firstLine, String joinedText) {
    final trimmedFirst = _trimTrailingHorizontalWhitespace(firstLine);
    final offset = trimmedFirst.length;
    if (offset >= joinedText.length) {
      return offset;
    }
    if (_isHorizontalWhitespace(joinedText.codeUnitAt(offset))) {
      return offset + 1;
    }
    return offset;
  }

  String _joinSeparator(String left, String right) {
    if (left.isEmpty || right.isEmpty) {
      return '';
    }
    final leftUnit = left.codeUnitAt(left.length - 1);
    final rightUnit = right.codeUnitAt(0);
    if (_isHorizontalWhitespace(leftUnit) ||
        _isHorizontalWhitespace(rightUnit)) {
      return '';
    }
    if ('([{'.contains(left[left.length - 1]) ||
        ')]},.;:'.contains(right[0]) ||
        left[left.length - 1] == '.' ||
        right[0] == '.') {
      return '';
    }
    return ' ';
  }

  List<String> _logicalLinesForDocument(DocumentState document) {
    final lines = document.lines;
    if (document.text.endsWith('\n') && lines.length > 1) {
      return lines.sublist(0, lines.length - 1);
    }
    return lines;
  }

  int _offsetForLogicalLineStart(DocumentState document, int line) {
    return document.lineStarts[line.clamp(0, document.lineStarts.length - 1)];
  }

  int _offsetAfterLogicalLine(
    DocumentState document,
    int line,
    int logicalLineCount,
  ) {
    if (line < logicalLineCount - 1) {
      return _offsetForLogicalLineStart(document, line + 1);
    }
    return document.length;
  }

  int _transformLineMoveOffset(
    int offset, {
    required DocumentState oldDocument,
    required DocumentState nextDocument,
    required _LineMoveRange lineRange,
    required int oldLogicalLineCount,
    required int nextLogicalLineCount,
    required int oldBlockStart,
    required int oldBlockEnd,
    required bool down,
  }) {
    final safeOffset = offset.clamp(0, oldDocument.length).toInt();
    final newBlockStartLine = lineRange.startLine + (down ? 1 : -1);
    final newBlockEndLine = lineRange.endLine + (down ? 1 : -1);
    final newBlockStart = _offsetForLogicalLineStart(
      nextDocument,
      newBlockStartLine,
    );
    final newBlockEnd = _offsetAfterLogicalLine(
      nextDocument,
      newBlockEndLine,
      nextLogicalLineCount,
    );

    if (safeOffset >= oldBlockStart && safeOffset <= oldBlockEnd) {
      return (newBlockStart + safeOffset - oldBlockStart)
          .clamp(newBlockStart, newBlockEnd)
          .toInt();
    }

    final oldPosition = oldDocument.positionForOffset(safeOffset);
    final oldLine = oldPosition.line.clamp(0, oldLogicalLineCount - 1).toInt();
    var newLine = oldLine;
    if (down) {
      if (oldLine == lineRange.endLine + 1) {
        newLine = lineRange.startLine;
      } else if (oldLine >= lineRange.startLine &&
          oldLine <= lineRange.endLine) {
        newLine = oldLine + 1;
      }
    } else {
      if (oldLine == lineRange.startLine - 1) {
        newLine = lineRange.endLine;
      } else if (oldLine >= lineRange.startLine &&
          oldLine <= lineRange.endLine) {
        newLine = oldLine - 1;
      }
    }

    return nextDocument
        .offsetForLineColumn(line: newLine, column: oldPosition.column)
        .clamp(0, nextDocument.length)
        .toInt();
  }

  int? _lineCommentPrefixOffset({
    required String lineText,
    required int lineStart,
  }) {
    final indentLength = _leadingHorizontalWhitespaceLength(lineText);
    if (indentLength + 1 >= lineText.length) {
      return null;
    }
    if (lineText[indentLength] != '/' || lineText[indentLength + 1] != '/') {
      return null;
    }
    return lineStart + indentLength;
  }

  int _leadingHorizontalWhitespaceLength(String lineText) {
    var index = 0;
    while (index < lineText.length) {
      final codeUnit = lineText.codeUnitAt(index);
      if (!_isHorizontalWhitespace(codeUnit)) {
        break;
      }
      index += 1;
    }
    return index;
  }

  int _trailingHorizontalWhitespaceLength(String lineText) {
    var index = lineText.length;
    while (index > 0) {
      final codeUnit = lineText.codeUnitAt(index - 1);
      if (!_isHorizontalWhitespace(codeUnit)) {
        break;
      }
      index -= 1;
    }
    return lineText.length - index;
  }

  String _trimTrailingHorizontalWhitespace(String lineText) {
    final trailingLength = _trailingHorizontalWhitespaceLength(lineText);
    if (trailingLength == 0) {
      return lineText;
    }
    return lineText.substring(0, lineText.length - trailingLength);
  }

  bool _isHorizontalWhitespace(int codeUnit) {
    return codeUnit == 0x20 || codeUnit == 0x09;
  }

  bool _isLowerAscii(int codeUnit) {
    return codeUnit >= 0x61 && codeUnit <= 0x7A;
  }

  bool _isUpperAscii(int codeUnit) {
    return codeUnit >= 0x41 && codeUnit <= 0x5A;
  }

  bool _strictlyContainsSelection(SourceRange candidate, SourceRange current) {
    return candidate.start <= current.start &&
        candidate.end >= current.end &&
        (candidate.start < current.start || candidate.end > current.end);
  }

  bool _selectReferenceAtSelection({required bool forward}) {
    final references = referencesAtSelection.toList(growable: false)
      ..sort((left, right) => left.range.start.compareTo(right.range.start));
    if (references.isEmpty) {
      return false;
    }

    final anchor = forward ? _selection.end : _selection.start;
    ReferenceSpan target;
    if (forward) {
      target = references.firstWhere(
        (reference) => reference.range.start > anchor,
        orElse: () => references.first,
      );
    } else {
      target = references.lastWhere(
        (reference) => reference.range.end < anchor,
        orElse: () => references.last,
      );
    }

    _structuredSelectionStack.clear();
    _selection = SelectionState(
      baseOffset: target.range.start,
      extentOffset: target.range.end,
    );
    _refreshAnalysis();
    notifyListeners();
    return true;
  }

  bool _selectDiagnostic({required bool forward}) {
    final diagnostics = _analysis.diagnostics.toList(growable: false)
      ..sort((left, right) => left.range.start.compareTo(right.range.start));
    if (diagnostics.isEmpty) {
      return false;
    }

    Diagnostic target;
    if (forward) {
      final anchor = _selection.end;
      target = diagnostics.firstWhere(
        (diagnostic) => diagnostic.range.end > anchor,
        orElse: () => diagnostics.first,
      );
    } else {
      final anchor = _selection.start;
      target = diagnostics.lastWhere(
        (diagnostic) => diagnostic.range.start < anchor,
        orElse: () => diagnostics.last,
      );
    }

    return selectDiagnostic(target);
  }

  static DocumentState seedDocumentForPath(String path) {
    return DocumentController.seedDocumentForPath(path);
  }
}

bool _isWholeWordSearchMatch(String source, int start, int end) {
  final before = start <= 0 ? null : source.codeUnitAt(start - 1);
  final after = end >= source.length ? null : source.codeUnitAt(end);
  return !_isSearchWordCharacter(before) && !_isSearchWordCharacter(after);
}

bool _isSearchWordCharacter(int? codeUnit) {
  if (codeUnit == null) {
    return false;
  }
  return (codeUnit >= 48 && codeUnit <= 57) ||
      (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122) ||
      codeUnit == 95;
}

class _NewlineInsertion {
  const _NewlineInsertion({required this.text, required this.caretDelta});

  final String text;
  final int caretDelta;
}

class _CommentLineRange {
  const _CommentLineRange({required this.startLine, required this.endLine});

  final int startLine;
  final int endLine;
}

class _LineMoveRange {
  const _LineMoveRange({required this.startLine, required this.endLine});

  final int startLine;
  final int endLine;
}

class _SurroundReplacement {
  const _SurroundReplacement({
    required this.text,
    required this.bodyStart,
    required this.bodyEnd,
  });

  final String text;
  final int bodyStart;
  final int bodyEnd;
}
