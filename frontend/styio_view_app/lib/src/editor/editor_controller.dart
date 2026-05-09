import 'package:flutter/foundation.dart';

import 'document_state.dart';
import 'editor_render_layers.dart';
import '../language/language_contract.dart';
import '../language/styio_language_service.dart';
import 'selection_state.dart';

class EditorSessionController extends ChangeNotifier {
  EditorSessionController({
    required DocumentState initialDocument,
    required StyioLanguageService languageService,
    SelectionState? initialSelection,
    EditorRenderPlan? renderPlan,
  }) : _document = initialDocument,
       _languageService = languageService,
       _selection =
           initialSelection ?? SelectionState.collapsed(initialDocument.length),
       _renderPlan = renderPlan ?? EditorRenderPlan.foundation(),
       _analysis = languageService.analyzeDocument(initialDocument);

  final List<_EditorSnapshot> _undoStack = <_EditorSnapshot>[];
  final List<_EditorSnapshot> _redoStack = <_EditorSnapshot>[];
  final List<SelectionState> _structuredSelectionStack = <SelectionState>[];

  DocumentState _document;
  final StyioLanguageService _languageService;
  SelectionState _selection;
  final EditorRenderPlan _renderPlan;
  StyioDocumentAnalysis _analysis;

  DocumentState get document => _document;
  SelectionState get selection => _selection;
  EditorRenderPlan get renderPlan => _renderPlan;
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
  RenamePlan? renamePlanAtSelection(String newName) =>
      _languageService.renameAt(_document, inspectionOffset, newName);
  ParameterInfoPayload? get parameterInfoAtSelection =>
      _languageService.parameterInfoAt(_document, inspectionOffset);
  TokenSpan? get tokenAtSelection => _tokenAroundOffset(inspectionOffset);
  SemanticKind? get semanticKindAtSelection {
    final token = tokenAtSelection;
    if (token == null) {
      return null;
    }

    for (final span in _analysis.semanticSpans) {
      if (span.range.intersects(token.range)) {
        return span.kind;
      }
    }
    return null;
  }

  List<Diagnostic> get diagnosticsAtSelectionToken {
    final token = tokenAtSelection;
    if (token == null) {
      return const <Diagnostic>[];
    }
    return _analysis.diagnostics
        .where((diagnostic) => diagnostic.range.intersects(token.range))
        .toList(growable: false);
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
    return _analysis.diagnostics
        .where(
          (diagnostic) =>
              diagnostic.range.contains(inspectionOffset) ||
              diagnostic.range.intersects(focusRange),
        )
        .toList(growable: false);
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

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void loadDocument(DocumentState document) {
    _document = document;
    _selection = SelectionState.collapsed(document.length);
    _refreshAnalysis();
    _undoStack.clear();
    _redoStack.clear();
    _structuredSelectionStack.clear();
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
    _redoStack.clear();
    notifyListeners();
  }

  void insertNewline() {
    insertText('\n');
  }

  void backspace() {
    if (_selection.isCollapsed && _selection.end == 0) {
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

    _redoStack.clear();
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

    _redoStack.clear();
    notifyListeners();
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
    _document = _document.replaceRange(
      start: startOffset,
      end: endOffset,
      replacement: '',
    );
    _selection = SelectionState.collapsed(
      startOffset.clamp(0, _document.length).toInt(),
    );
    _refreshAnalysis();
    _redoStack.clear();
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
      _document = _document.replaceRange(
        start: insertOffset,
        end: insertOffset,
        replacement: selectedText,
      );
      _selection = SelectionState(
        baseOffset: insertOffset,
        extentOffset: insertOffset + selectedText.length,
      );
      _refreshAnalysis();
      _redoStack.clear();
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
    _document = _document.replaceRange(
      start: insertOffset,
      end: insertOffset,
      replacement: duplicateText,
    );
    _selection = SelectionState.collapsed(
      (duplicateStart + duplicateColumn).clamp(0, _document.length).toInt(),
    );
    _refreshAnalysis();
    _redoStack.clear();
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
    _document = _document.replaceRange(
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
    _redoStack.clear();
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
    _document = _document.replaceRange(
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
    _redoStack.clear();
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

  void applyCompletionItem(CompletionItem item) {
    _structuredSelectionStack.clear();
    _pushUndoSnapshot();
    final replacementRange = _completionReplacementRange();
    _replaceRange(
      start: replacementRange.start,
      end: replacementRange.end,
      replacement: item.insertText,
      selectionOffset: replacementRange.start + item.insertText.length,
    );
    _redoStack.clear();
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
    _document = _document.replaceRange(
      start: range.start,
      end: range.end,
      replacement: replacement.text,
    );
    _selection = SelectionState(
      baseOffset: range.start + replacement.bodyStart,
      extentOffset: range.start + replacement.bodyEnd,
    );
    _refreshAnalysis();
    _redoStack.clear();
    notifyListeners();
    return true;
  }

  void applyFormattingEdits(Iterable<FormattingEdit> edits) {
    final normalizedEdits = edits.toList(growable: false);
    if (normalizedEdits.isEmpty) {
      return;
    }

    _structuredSelectionStack.clear();
    final editsAscending = normalizedEdits.toList(growable: false)
      ..sort((left, right) => left.range.start.compareTo(right.range.start));
    final editsDescending = editsAscending.reversed.toList(growable: false);
    final nextBaseOffset = _transformOffsetWithEdits(
      _selection.baseOffset,
      editsAscending,
    );
    final nextExtentOffset = _transformOffsetWithEdits(
      _selection.extentOffset,
      editsAscending,
    );

    _pushUndoSnapshot();

    var nextDocument = _document;
    for (final edit in editsDescending) {
      nextDocument = nextDocument.replaceRange(
        start: edit.range.start,
        end: edit.range.end,
        replacement: edit.newText,
      );
    }

    _document = nextDocument;
    _selection = SelectionState(
      baseOffset: nextBaseOffset.clamp(0, _document.length),
      extentOffset: nextExtentOffset.clamp(0, _document.length),
    );
    _refreshAnalysis();
    _redoStack.clear();
    notifyListeners();
  }

  void applyDiagnosticQuickFix(DiagnosticQuickFix fix) {
    applyFormattingEdits(fix.edits);
  }

  bool applyFirstQuickFixAtSelection() {
    final fixes = quickFixesForDiagnostics(diagnosticsAtSelection);
    if (fixes.isEmpty) {
      return false;
    }
    applyDiagnosticQuickFix(fixes.first);
    return true;
  }

  bool applyRename(String newName) {
    final plan = renamePlanAtSelection(newName);
    if (plan == null) {
      return false;
    }
    applyFormattingEdits(plan.edits);
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
    _refreshAnalysis();
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
    _refreshAnalysis();
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
    _document = _document.replaceRange(
      start: start,
      end: end,
      replacement: replacement,
    );
    _selection = SelectionState.collapsed(selectionOffset);
    _refreshAnalysis();
  }

  void undo() {
    if (!canUndo) {
      return;
    }
    _structuredSelectionStack.clear();
    _redoStack.add(_captureSnapshot());
    final snapshot = _undoStack.removeLast();
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
    _undoStack.add(_captureSnapshot());
    final snapshot = _redoStack.removeLast();
    _document = snapshot.document;
    _selection = snapshot.selection;
    _refreshAnalysis();
    notifyListeners();
  }

  _EditorSnapshot _captureSnapshot() {
    return _EditorSnapshot(document: _document, selection: _selection);
  }

  void _pushUndoSnapshot() {
    _undoStack.add(_captureSnapshot());
    if (_undoStack.length > 128) {
      _undoStack.removeAt(0);
    }
  }

  void _refreshAnalysis() {
    _analysis = _languageService.analyzeDocument(_document);
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
    final safeOffset = offset.clamp(0, _document.length);
    TokenSpan? trailingToken;
    TokenSpan? leadingToken;

    for (final token in _analysis.tokenSpans) {
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
    final samples = <String, String>{
      'main.styio': '''
fn main() {
  let stream = source |> normalize -> sink
  emit stream
}
''',
      'render_flow.styio': '''
pipeline renderFlow

let commitFlow = source |> normalize |> shade -> commit

fn commitFrame(frame) {
  state paint_ready
  when frame.ready -> state submitted
  emit frame.commit
}
''',
      'runtime_graph.styio': '''
fn bootRuntime() {
  spawn worker_a
  spawn worker_b
  sync worker_a -> worker_b
}
''',
      'cloud/main.styio': '''
fn main() {
  let session = remote_source |> hydrate -> cloud_sink
  emit session
}
''',
      'cloud/runtime_surface.styio': '''
fn inspectCloudSession() {
  state awaiting_container
  when container.ready -> state connected
}
''',
    };

    final normalizedPath = path.replaceAll('\\', '/');
    final basename = normalizedPath.split('/').last;
    final cloudPath = normalizedPath.contains('/cloud/');
    final lookupOrder = <String>[
      normalizedPath,
      if (cloudPath) 'cloud/$basename',
      basename,
    ];

    String? sample;
    for (final candidate in lookupOrder) {
      sample = samples[candidate];
      if (sample != null) {
        break;
      }
    }

    return DocumentState(
      documentId: path,
      text: sample ?? '// empty document\n',
      revision: 0,
    );
  }
}

class _EditorSnapshot {
  const _EditorSnapshot({required this.document, required this.selection});

  final DocumentState document;
  final SelectionState selection;
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
