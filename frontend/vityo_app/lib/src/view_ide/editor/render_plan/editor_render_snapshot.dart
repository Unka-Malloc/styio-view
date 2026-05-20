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
