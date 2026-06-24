import '../controller/editor_controller.dart';
import '../../language/language_contract.dart';
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
    this.viewportBinding = const EditorRenderViewportBinding.unbound(),
    this.renderPipelinePlan = const EditorRenderPipelinePlan.unbound(),
    this.hoverAvailable = false,
    this.completionCount = 0,
    this.contextActionCount = 0,
    this.codeActionWidget = const EditorCodeActionWidgetState.hidden(),
    this.activeTokenText = '',
    this.activeSemanticKind = '',
    this.todo = '',
  });

  factory EditorRenderSnapshot.fromController(
    EditorSessionController controller,
  ) {
    final activeToken = controller.tokenAtSelection;
    final activeSemanticKind = controller.semanticKindAtSelection;
    final rowWindow = EditorVirtualizedRowWindow.fromViewport(
      totalLineCount: controller.document.lines.length,
      firstVisibleLine: _editorLineIndexForOffset(
        controller.document.text,
        controller.selection.end,
      ),
      viewportLineCapacity: 80,
    );
    final viewportBinding = EditorRenderViewportBinding.fromWindow(
      rowWindow,
      boundToScrollController: false,
      todo:
          'TODO: bind viewport facts to the concrete Flutter ScrollController.',
    );
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
      virtualizedRowWindow: rowWindow,
      viewportBinding: viewportBinding,
      renderPipelinePlan: EditorRenderPipelinePlan.fromRenderFacts(
        renderPlan: controller.renderPlan,
        lineCount: controller.document.lines.length,
        viewportBinding: viewportBinding,
      ),
      hoverAvailable: controller.hoverAtSelection != null,
      completionCount: controller.completionsAtSelection.length,
      contextActionCount: controller.contextActionsAtSelection.length,
      codeActionWidget: EditorCodeActionWidgetState.fromController(controller),
      activeTokenText: activeToken?.lexeme ?? '',
      activeSemanticKind: activeSemanticKind?.name ?? '',
      todo:
          'TODO: bind this snapshot to the concrete scroll controller viewport state.',
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
      viewportBinding: _editorRenderViewportBindingFromJson(
        json['viewportBinding'],
      ),
      renderPipelinePlan: _editorRenderPipelinePlanFromJson(
        json['renderPipelinePlan'],
      ),
      hoverAvailable: json['hoverAvailable'] as bool? ?? false,
      completionCount: json['completionCount'] as int? ?? 0,
      contextActionCount: json['contextActionCount'] as int? ?? 0,
      codeActionWidget: _editorCodeActionWidgetStateFromJson(
        json['codeActionWidget'],
      ),
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
  final EditorRenderViewportBinding viewportBinding;
  final EditorRenderPipelinePlan renderPipelinePlan;
  final bool hoverAvailable;
  final int completionCount;
  final int contextActionCount;
  final EditorCodeActionWidgetState codeActionWidget;
  final String activeTokenText;
  final String activeSemanticKind;
  final String todo;

  bool get hasSelection => selectionStart != selectionEnd;
  bool get hasCodeActionWidget => contextActionCount > 0;

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
      'viewportBinding': viewportBinding.toJson(),
      'renderPipelinePlan': renderPipelinePlan.toJson(),
      'hoverAvailable': hoverAvailable,
      'completionCount': completionCount,
      'contextActionCount': contextActionCount,
      'hasCodeActionWidget': hasCodeActionWidget,
      'codeActionWidget': codeActionWidget.toJson(),
      if (activeTokenText.isNotEmpty) 'activeTokenText': activeTokenText,
      if (activeSemanticKind.isNotEmpty)
        'activeSemanticKind': activeSemanticKind,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class EditorCodeActionWidgetState {
  const EditorCodeActionWidgetState({
    required this.visible,
    required this.diagnosticCount,
    required this.actionCount,
    required this.serviceFactCount,
    required this.primaryLabel,
    required this.actions,
    this.todo = '',
  });

  const EditorCodeActionWidgetState.hidden()
    : visible = false,
      diagnosticCount = 0,
      actionCount = 0,
      serviceFactCount = 0,
      primaryLabel = '',
      actions = const <EditorCodeActionWidgetAction>[],
      todo = '';

  factory EditorCodeActionWidgetState.fromController(
    EditorSessionController controller,
  ) {
    final diagnostics = controller.diagnosticsAtSelection;
    final actions = controller.contextActionsAtSelection;
    final serviceFacts = controller.codeActionFactsAtSelection;
    return EditorCodeActionWidgetState(
      visible: actions.isNotEmpty,
      diagnosticCount: diagnostics.length,
      actionCount: actions.length,
      serviceFactCount: serviceFacts.length,
      primaryLabel: actions.isEmpty ? '' : actions.first.label,
      actions: actions
          .map(EditorCodeActionWidgetAction.fromQuickFix)
          .toList(growable: false),
      todo:
          'TODO: bind this widget state to the editor lightbulb popup and explicit apply command routing.',
    );
  }

  factory EditorCodeActionWidgetState.fromJson(Map<String, Object?> json) {
    final actions = json['actions'];
    return EditorCodeActionWidgetState(
      visible: json['visible'] as bool? ?? false,
      diagnosticCount: json['diagnosticCount'] as int? ?? 0,
      actionCount: json['actionCount'] as int? ?? 0,
      serviceFactCount: json['serviceFactCount'] as int? ?? 0,
      primaryLabel: json['primaryLabel'] as String? ?? '',
      actions: actions is List
          ? actions
                .whereType<Map>()
                .map(
                  (action) => EditorCodeActionWidgetAction.fromJson(
                    action.map(
                      (key, value) =>
                          MapEntry<String, Object?>(key.toString(), value),
                    ),
                  ),
                )
                .toList(growable: false)
          : const <EditorCodeActionWidgetAction>[],
      todo: json['todo'] as String? ?? '',
    );
  }

  final bool visible;
  final int diagnosticCount;
  final int actionCount;
  final int serviceFactCount;
  final String primaryLabel;
  final List<EditorCodeActionWidgetAction> actions;
  final String todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'visible': visible,
      'diagnosticCount': diagnosticCount,
      'actionCount': actionCount,
      'serviceFactCount': serviceFactCount,
      if (primaryLabel.isNotEmpty) 'primaryLabel': primaryLabel,
      'actions': actions
          .map((action) => action.toJson())
          .toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class EditorCodeActionWidgetAction {
  const EditorCodeActionWidgetAction({
    required this.label,
    required this.editCount,
    this.detail = '',
  });

  factory EditorCodeActionWidgetAction.fromQuickFix(DiagnosticQuickFix fix) {
    return EditorCodeActionWidgetAction(
      label: fix.label,
      detail: fix.detail,
      editCount: fix.edits.length,
    );
  }

  factory EditorCodeActionWidgetAction.fromJson(Map<String, Object?> json) {
    return EditorCodeActionWidgetAction(
      label: json['label'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      editCount: json['editCount'] as int? ?? 0,
    );
  }

  final String label;
  final String detail;
  final int editCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      if (detail.isNotEmpty) 'detail': detail,
      'editCount': editCount,
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

class EditorRenderViewportBinding {
  const EditorRenderViewportBinding({
    required this.viewportFirstLine,
    required this.viewportLineCapacity,
    required this.overscanLineCount,
    this.scrollOffsetPixels = 0,
    this.lineHeightPixels = 20,
    this.boundToScrollController = false,
    this.todo = '',
  });

  const EditorRenderViewportBinding.unbound()
    : viewportFirstLine = 0,
      viewportLineCapacity = 1,
      overscanLineCount = 0,
      scrollOffsetPixels = 0,
      lineHeightPixels = 20,
      boundToScrollController = false,
      todo = 'TODO: bind editor viewport to concrete scroll controller facts.';

  factory EditorRenderViewportBinding.fromWindow(
    EditorVirtualizedRowWindow window, {
    double scrollOffsetPixels = 0,
    double lineHeightPixels = 20,
    bool boundToScrollController = false,
    String todo = '',
  }) {
    return EditorRenderViewportBinding(
      viewportFirstLine: window.viewportFirstLine,
      viewportLineCapacity: window.viewportLineCapacity,
      overscanLineCount: window.overscanLineCount,
      scrollOffsetPixels: scrollOffsetPixels,
      lineHeightPixels: lineHeightPixels,
      boundToScrollController: boundToScrollController,
      todo: todo,
    );
  }

  factory EditorRenderViewportBinding.fromScrollControllerFacts({
    required double scrollOffsetPixels,
    required double viewportHeightPixels,
    double lineHeightPixels = 20,
    int overscanLineCount = 8,
    int? totalLineCount,
  }) {
    final effectiveLineHeight = lineHeightPixels <= 0 ? 20.0 : lineHeightPixels;
    final firstLine = (scrollOffsetPixels / effectiveLineHeight).floor();
    final capacity = (viewportHeightPixels / effectiveLineHeight).ceil();
    final normalizedCapacity = capacity < 1 ? 1 : capacity;
    final normalizedOverscan = overscanLineCount < 0 ? 0 : overscanLineCount;
    final maxFirstLine = totalLineCount == null || totalLineCount <= 0
        ? firstLine
        : totalLineCount - 1;
    final normalizedFirstLine = firstLine < 0
        ? 0
        : firstLine > maxFirstLine
        ? maxFirstLine
        : firstLine;
    return EditorRenderViewportBinding(
      viewportFirstLine: normalizedFirstLine,
      viewportLineCapacity: normalizedCapacity,
      overscanLineCount: normalizedOverscan,
      scrollOffsetPixels: scrollOffsetPixels < 0 ? 0 : scrollOffsetPixels,
      lineHeightPixels: effectiveLineHeight,
      boundToScrollController: true,
    );
  }

  factory EditorRenderViewportBinding.fromJson(Map<String, Object?> json) {
    return EditorRenderViewportBinding(
      viewportFirstLine: json['viewportFirstLine'] as int? ?? 0,
      viewportLineCapacity: json['viewportLineCapacity'] as int? ?? 1,
      overscanLineCount: json['overscanLineCount'] as int? ?? 0,
      scrollOffsetPixels: _doubleFromJson(json['scrollOffsetPixels']),
      lineHeightPixels: _doubleFromJson(json['lineHeightPixels'], fallback: 20),
      boundToScrollController:
          json['boundToScrollController'] as bool? ?? false,
      todo: json['todo'] as String? ?? '',
    );
  }

  final int viewportFirstLine;
  final int viewportLineCapacity;
  final int overscanLineCount;
  final double scrollOffsetPixels;
  final double lineHeightPixels;
  final bool boundToScrollController;
  final String todo;

  EditorVirtualizedRowWindow toWindow({required int totalLineCount}) {
    return EditorVirtualizedRowWindow.fromViewport(
      totalLineCount: totalLineCount,
      firstVisibleLine: viewportFirstLine,
      viewportLineCapacity: viewportLineCapacity,
      overscanLineCount: overscanLineCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'viewportFirstLine': viewportFirstLine,
      'viewportLineCapacity': viewportLineCapacity,
      'overscanLineCount': overscanLineCount,
      'scrollOffsetPixels': scrollOffsetPixels,
      'lineHeightPixels': lineHeightPixels,
      'boundToScrollController': boundToScrollController,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class EditorRenderPipelinePlan {
  const EditorRenderPipelinePlan({
    required this.rendererKind,
    required this.renderPlan,
    required this.renderWindow,
    required this.canRender,
    required this.maxRenderedLines,
    this.fallbackReason = '',
    this.todo = '',
  });

  const EditorRenderPipelinePlan.unbound()
    : rendererKind = 'unbound',
      renderPlan = const EditorRenderPlan(
        activeLayers: <EditorRenderLayer>{EditorRenderLayer.text},
      ),
      renderWindow = const EditorVirtualizedRowWindow(
        totalLineCount: 0,
        startLine: 0,
        endLineExclusive: 0,
        viewportFirstLine: 0,
        viewportLineCapacity: 1,
        overscanLineCount: 0,
      ),
      canRender = false,
      maxRenderedLines = 0,
      fallbackReason = 'Editor render pipeline has not been bound.',
      todo = 'TODO: bind renderer kind to concrete editor rendering backend.';

  factory EditorRenderPipelinePlan.fromRenderFacts({
    required EditorRenderPlan renderPlan,
    required int lineCount,
    required EditorRenderViewportBinding viewportBinding,
    int maxRenderedLines = 400,
  }) {
    final window = viewportBinding.toWindow(totalLineCount: lineCount);
    final canRender = window.renderLineCount <= maxRenderedLines;
    return EditorRenderPipelinePlan(
      rendererKind: canRender
          ? 'virtualized-layer-stack'
          : 'plain-text-fallback',
      renderPlan: renderPlan,
      renderWindow: window,
      canRender: canRender,
      maxRenderedLines: maxRenderedLines,
      fallbackReason: canRender
          ? ''
          : 'Editor render window has ${window.renderLineCount} lines, above limit $maxRenderedLines.',
      todo:
          'TODO: connect this plan to concrete Flutter viewport and layer renderers.',
    );
  }

  factory EditorRenderPipelinePlan.fromJson(Map<String, Object?> json) {
    final renderPlan = json['renderPlan'];
    final renderWindow = json['renderWindow'];
    return EditorRenderPipelinePlan(
      rendererKind: json['rendererKind'] as String? ?? 'unbound',
      renderPlan: renderPlan is Map
          ? EditorRenderPlan.fromJson(
              renderPlan.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : EditorRenderPlan.foundation(),
      renderWindow: renderWindow is Map
          ? EditorVirtualizedRowWindow.fromJson(
              renderWindow.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const EditorVirtualizedRowWindow(
              totalLineCount: 0,
              startLine: 0,
              endLineExclusive: 0,
              viewportFirstLine: 0,
              viewportLineCapacity: 1,
              overscanLineCount: 0,
            ),
      canRender: json['canRender'] as bool? ?? false,
      maxRenderedLines: json['maxRenderedLines'] as int? ?? 0,
      fallbackReason: json['fallbackReason'] as String? ?? '',
      todo: json['todo'] as String? ?? '',
    );
  }

  final String rendererKind;
  final EditorRenderPlan renderPlan;
  final EditorVirtualizedRowWindow renderWindow;
  final bool canRender;
  final int maxRenderedLines;
  final String fallbackReason;
  final String todo;

  bool get usingFallback => fallbackReason.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rendererKind': rendererKind,
      'renderPlan': renderPlan.toJson(),
      'renderWindow': renderWindow.toJson(),
      'canRender': canRender,
      'maxRenderedLines': maxRenderedLines,
      'usingFallback': usingFallback,
      if (fallbackReason.isNotEmpty) 'fallbackReason': fallbackReason,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

EditorCodeActionWidgetState _editorCodeActionWidgetStateFromJson(
  Object? value,
) {
  if (value is Map<String, Object?>) {
    return EditorCodeActionWidgetState.fromJson(value);
  }
  if (value is Map) {
    return EditorCodeActionWidgetState.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return const EditorCodeActionWidgetState.hidden();
}

EditorRenderViewportBinding _editorRenderViewportBindingFromJson(
  Object? value,
) {
  if (value is Map<String, Object?>) {
    return EditorRenderViewportBinding.fromJson(value);
  }
  if (value is Map) {
    return EditorRenderViewportBinding.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return const EditorRenderViewportBinding.unbound();
}

EditorRenderPipelinePlan _editorRenderPipelinePlanFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return EditorRenderPipelinePlan.fromJson(value);
  }
  if (value is Map) {
    return EditorRenderPipelinePlan.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return const EditorRenderPipelinePlan.unbound();
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

double _doubleFromJson(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse('$value') ?? fallback;
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
