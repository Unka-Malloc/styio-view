import '../controller/editor_controller.dart';
import 'editor_render_layers.dart';

class EditorRenderSnapshot {
  const EditorRenderSnapshot({
    required this.documentId,
    required this.revision,
    required this.lineCount,
    required this.characterCount,
    required this.selectionStart,
    required this.selectionEnd,
    required this.renderPlan,
    required this.tokenCount,
    required this.semanticCount,
    required this.diagnosticCount,
    required this.virtualizedRowWindow,
    this.hoverAvailable = false,
    this.completionCount = 0,
    this.contextActionCount = 0,
    this.activeTokenText = '',
    this.activeSemanticKind = '',
    this.todo = '',
  });

  factory EditorRenderSnapshot.fromController(
    EditorSessionController controller,
  ) {
    final activeToken = controller.tokenAtSelection;
    final activeSemanticKind = controller.semanticKindAtSelection;
    return EditorRenderSnapshot(
      documentId: controller.document.documentId,
      revision: controller.document.revision,
      lineCount: controller.document.lines.length,
      characterCount: controller.document.length,
      selectionStart: controller.selection.start,
      selectionEnd: controller.selection.end,
      renderPlan: controller.renderPlan,
      tokenCount: controller.analysis.tokenCount,
      semanticCount: controller.analysis.semanticCount,
      diagnosticCount: controller.analysis.diagnosticCount,
      virtualizedRowWindow: EditorVirtualizedRowWindow.fromViewport(
        totalLineCount: controller.document.lines.length,
        firstVisibleLine: _editorLineIndexForOffset(
          controller.document.text,
          controller.selection.end,
        ),
        viewportLineCapacity: 80,
      ),
      hoverAvailable: controller.hoverAtSelection != null,
      completionCount: controller.completionsAtSelection.length,
      contextActionCount: controller.contextActionsAtSelection.length,
      activeTokenText: activeToken?.lexeme ?? '',
      activeSemanticKind: activeSemanticKind?.name ?? '',
      todo:
          'TODO: bind this snapshot to virtualized row rendering, hover widgets, completion widgets, and code action widgets.',
    );
  }

  factory EditorRenderSnapshot.fromJson(Map<String, Object?> json) {
    final plan = json['renderPlan'];
    return EditorRenderSnapshot(
      documentId: json['documentId'] as String? ?? '',
      revision: json['revision'] as int? ?? 0,
      lineCount: json['lineCount'] as int? ?? 0,
      characterCount: json['characterCount'] as int? ?? 0,
      selectionStart: json['selectionStart'] as int? ?? 0,
      selectionEnd: json['selectionEnd'] as int? ?? 0,
      renderPlan: plan is Map<String, Object?>
          ? EditorRenderPlan.fromJson(plan)
          : plan is Map
          ? EditorRenderPlan.fromJson(
              plan.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : EditorRenderPlan.foundation(),
      tokenCount: json['tokenCount'] as int? ?? 0,
      semanticCount: json['semanticCount'] as int? ?? 0,
      diagnosticCount: json['diagnosticCount'] as int? ?? 0,
      virtualizedRowWindow: _editorVirtualizedRowWindowFromJson(
        json['virtualizedRowWindow'],
      ),
      hoverAvailable: json['hoverAvailable'] as bool? ?? false,
      completionCount: json['completionCount'] as int? ?? 0,
      contextActionCount: json['contextActionCount'] as int? ?? 0,
      activeTokenText: json['activeTokenText'] as String? ?? '',
      activeSemanticKind: json['activeSemanticKind'] as String? ?? '',
      todo: json['todo'] as String? ?? '',
    );
  }

  final String documentId;
  final int revision;
  final int lineCount;
  final int characterCount;
  final int selectionStart;
  final int selectionEnd;
  final EditorRenderPlan renderPlan;
  final int tokenCount;
  final int semanticCount;
  final int diagnosticCount;
  final EditorVirtualizedRowWindow virtualizedRowWindow;
  final bool hoverAvailable;
  final int completionCount;
  final int contextActionCount;
  final String activeTokenText;
  final String activeSemanticKind;
  final String todo;

  bool get hasSelection => selectionStart != selectionEnd;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'lineCount': lineCount,
      'characterCount': characterCount,
      'selectionStart': selectionStart,
      'selectionEnd': selectionEnd,
      'hasSelection': hasSelection,
      'renderPlan': renderPlan.toJson(),
      'tokenCount': tokenCount,
      'semanticCount': semanticCount,
      'diagnosticCount': diagnosticCount,
      'virtualizedRowWindow': virtualizedRowWindow.toJson(),
      'hoverAvailable': hoverAvailable,
      'completionCount': completionCount,
      'contextActionCount': contextActionCount,
      if (activeTokenText.isNotEmpty) 'activeTokenText': activeTokenText,
      if (activeSemanticKind.isNotEmpty)
        'activeSemanticKind': activeSemanticKind,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class EditorVirtualizedRowWindow {
  const EditorVirtualizedRowWindow({
    required this.totalLineCount,
    required this.startLine,
    required this.endLineExclusive,
    required this.viewportFirstLine,
    required this.viewportLineCapacity,
    required this.overscanLineCount,
  });

  factory EditorVirtualizedRowWindow.fromViewport({
    required int totalLineCount,
    required int firstVisibleLine,
    required int viewportLineCapacity,
    int overscanLineCount = 8,
  }) {
    final safeTotal = totalLineCount < 0 ? 0 : totalLineCount;
    final safeCapacity = viewportLineCapacity <= 0 ? 1 : viewportLineCapacity;
    final safeOverscan = overscanLineCount < 0 ? 0 : overscanLineCount;
    final safeFirstVisible = safeTotal == 0
        ? 0
        : firstVisibleLine.clamp(0, safeTotal - 1);
    final startLine = (safeFirstVisible - safeOverscan).clamp(0, safeTotal);
    final endLine = (safeFirstVisible + safeCapacity + safeOverscan).clamp(
      startLine,
      safeTotal,
    );
    return EditorVirtualizedRowWindow(
      totalLineCount: safeTotal,
      startLine: startLine,
      endLineExclusive: endLine,
      viewportFirstLine: safeFirstVisible,
      viewportLineCapacity: safeCapacity,
      overscanLineCount: safeOverscan,
    );
  }

  factory EditorVirtualizedRowWindow.fromJson(Map<String, Object?> json) {
    return EditorVirtualizedRowWindow(
      totalLineCount: json['totalLineCount'] as int? ?? 0,
      startLine: json['startLine'] as int? ?? 0,
      endLineExclusive: json['endLineExclusive'] as int? ?? 0,
      viewportFirstLine: json['viewportFirstLine'] as int? ?? 0,
      viewportLineCapacity: json['viewportLineCapacity'] as int? ?? 1,
      overscanLineCount: json['overscanLineCount'] as int? ?? 0,
    );
  }

  final int totalLineCount;
  final int startLine;
  final int endLineExclusive;
  final int viewportFirstLine;
  final int viewportLineCapacity;
  final int overscanLineCount;

  int get renderLineCount => endLineExclusive - startLine;

  bool get coversFullDocument {
    return startLine == 0 && endLineExclusive >= totalLineCount;
  }

  bool containsLine(int lineIndex) {
    return lineIndex >= startLine && lineIndex < endLineExclusive;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'totalLineCount': totalLineCount,
      'startLine': startLine,
      'endLineExclusive': endLineExclusive,
      'viewportFirstLine': viewportFirstLine,
      'viewportLineCapacity': viewportLineCapacity,
      'overscanLineCount': overscanLineCount,
      'renderLineCount': renderLineCount,
      'coversFullDocument': coversFullDocument,
    };
  }
}

EditorVirtualizedRowWindow _editorVirtualizedRowWindowFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return EditorVirtualizedRowWindow.fromJson(value);
  }
  if (value is Map) {
    return EditorVirtualizedRowWindow.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return const EditorVirtualizedRowWindow(
    totalLineCount: 0,
    startLine: 0,
    endLineExclusive: 0,
    viewportFirstLine: 0,
    viewportLineCapacity: 1,
    overscanLineCount: 0,
  );
}

int _editorLineIndexForOffset(String source, int offset) {
  final safeOffset = offset.clamp(0, source.length);
  var line = 0;
  for (var index = 0; index < safeOffset; index += 1) {
    if (source.codeUnitAt(index) == 10) {
      line += 1;
    }
  }
  return line;
}
