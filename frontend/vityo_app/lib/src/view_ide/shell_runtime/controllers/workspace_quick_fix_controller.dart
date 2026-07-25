import 'package:flutter/foundation.dart';

import '../../editor/editor.dart' hide WorkspaceEditSource;
import '../../language/language_contract.dart';
import '../../language/service/service.dart';
import '../../workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';

/// Owns deterministic project quick-fix preview, review, and application.
final class WorkspaceQuickFixController extends ChangeNotifier {
  WorkspaceQuickFixController({
    required this.languageService,
    required this.loadDocuments,
    required this.documentSamples,
    required this.documentStore,
    required this.editorController,
    required this.editorWorkspaceState,
    required this.cacheDocument,
    required this.log,
  });

  final ProjectStyioLanguageService languageService;
  final Future<List<DocumentState>> Function() loadDocuments;
  final List<DocumentState> Function() documentSamples;
  final WorkspaceDocumentStore documentStore;
  final EditorSessionController editorController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final void Function(String message) log;

  WorkspaceEditPreview? _lastPreview;
  WorkspaceEditApplyResultViewModel? _lastApplyResult;

  WorkspaceEditPreview? get lastPreview => _lastPreview;
  WorkspaceEditApplyResultViewModel? get lastApplyResult => _lastApplyResult;

  Future<List<StyioProjectWorkspaceFix>> collect() async {
    final documents = await loadDocuments();
    for (final document in documents) {
      if (document.documentId != editorController.document.documentId) {
        cacheDocument(document.documentId, document);
      }
    }
    final analysis = languageService.analyzeProject(documents);
    final fixes = languageService.workspaceQuickFixesForProjectDiagnostics(
      documents: documents,
      diagnostics: analysis.diagnostics,
      analysis: analysis,
    );
    log(
      'Project workspace quick fixes collected: ${fixes.length} candidate(s).',
    );
    notifyListeners();
    return fixes;
  }

  Future<WorkspaceEditPreview?> previewFirst() async {
    final documents = await loadDocuments();
    final analysis = languageService.analyzeProject(documents);
    final fixes = languageService.workspaceQuickFixesForProjectDiagnostics(
      documents: documents,
      diagnostics: analysis.diagnostics,
      analysis: analysis,
    );
    if (fixes.isEmpty) {
      _lastPreview = null;
      _lastApplyResult = null;
      log('Project workspace quick fix preview skipped: no deterministic fix.');
      notifyListeners();
      return null;
    }
    final preview = _planFor(fixes.first).preview(documents);
    _lastPreview = preview;
    _lastApplyResult = null;
    log(
      'Project workspace quick fix previewed: ${preview.summary} '
      '(${preview.editCount} edit(s)).',
    );
    notifyListeners();
    return preview;
  }

  Future<bool> applyFirst({String? expectedPreviewPlanId}) async {
    final fixes = await collect();
    if (fixes.isEmpty) {
      _lastApplyResult = null;
      log('Project workspace quick fix skipped: no deterministic fix.');
      notifyListeners();
      return false;
    }
    final fix = fixes.first;
    final plan = _planFor(fix);
    if (expectedPreviewPlanId != null && plan.id != expectedPreviewPlanId) {
      final preview = plan.preview(documentSamples());
      final confirmationPlan = WorkspaceEditConfirmationPlan.fromPreview(
        preview,
      );
      const result = WorkspaceEditApplicationResult(
        applied: false,
        message:
            'Project workspace quick fix skipped: preview is stale. Run previewQuickFix again before applying.',
      );
      _lastPreview = preview;
      _recordApplyResult(
        confirmationPlan: confirmationPlan,
        preview: preview,
        result: result,
      );
      log(result.message);
      notifyListeners();
      return false;
    }
    return _apply(fix, plan: plan);
  }

  Future<bool> _apply(
    StyioProjectWorkspaceFix fix, {
    WorkspaceEditPlan? plan,
  }) async {
    final effectivePlan = plan ?? _planFor(fix);
    final preview = effectivePlan.preview(documentSamples());
    final confirmationPlan = WorkspaceEditConfirmationPlan.fromPreview(preview);
    _lastPreview = preview;
    _lastApplyResult = null;
    final activeDocumentId = editorController.document.documentId;
    final activeEdits =
        fix.editsByDocument[activeDocumentId] ?? const <FormattingEdit>[];
    final normalizedActiveEdits = normalizeFormattingEditsForDocument(
      documentLength: editorController.document.length,
      edits: activeEdits,
    );
    if (normalizedActiveEdits.length != activeEdits.length) {
      const result = WorkspaceEditApplicationResult(
        applied: false,
        message:
            'Project workspace quick fix skipped: active document edits are invalid or overlapping.',
      );
      _recordApplyResult(
        confirmationPlan: confirmationPlan,
        preview: preview,
        result: result,
      );
      log(result.message);
      notifyListeners();
      return false;
    }
    final inactiveEditsByDocument = <String, List<FormattingEdit>>{
      for (final entry in fix.editsByDocument.entries)
        if (entry.key != activeDocumentId) entry.key: entry.value,
    };

    var inactiveEditCount = 0;
    var appliedInactiveDocumentIds = const <String>[];
    if (inactiveEditsByDocument.isNotEmpty) {
      final inactiveFix = StyioProjectWorkspaceFix(
        label: fix.label,
        detail: fix.detail,
        editsByDocument: inactiveEditsByDocument,
      );
      final result = await WorkspaceEditApplier(
        workspaceDocumentStore: documentStore,
      ).apply(_planFor(inactiveFix));
      if (!result.applied) {
        _recordApplyResult(
          confirmationPlan: confirmationPlan,
          preview: preview,
          result: result,
        );
        log('Project workspace quick fix skipped: ${result.message}');
        notifyListeners();
        return false;
      }
      inactiveEditCount = result.appliedEditCount;
      appliedInactiveDocumentIds = result.appliedDocumentIds;
      for (final documentId in result.appliedDocumentIds) {
        editorWorkspaceState.removeDocument(documentId);
      }
    }

    if (normalizedActiveEdits.isNotEmpty) {
      editorController.applyFormattingEdits(normalizedActiveEdits);
      cacheDocument(activeDocumentId, editorController.document);
      editorWorkspaceState.markDirty(activeDocumentId);
    }
    final editCount = inactiveEditCount + normalizedActiveEdits.length;
    final appliedDocumentIds = <String>{
      ...appliedInactiveDocumentIds,
      if (normalizedActiveEdits.isNotEmpty) activeDocumentId,
    }.toList(growable: false)..sort();
    final result = WorkspaceEditApplicationResult(
      applied: editCount > 0,
      message:
          'Project workspace quick fix applied: ${fix.label} ($editCount edit(s)).',
      appliedEditCount: editCount,
      appliedDocumentIds: appliedDocumentIds,
    );
    _recordApplyResult(
      confirmationPlan: confirmationPlan,
      preview: preview,
      result: result,
    );
    log(result.message);
    notifyListeners();
    return editCount > 0;
  }

  void _recordApplyResult({
    required WorkspaceEditConfirmationPlan confirmationPlan,
    required WorkspaceEditPreview preview,
    required WorkspaceEditApplicationResult result,
  }) {
    _lastApplyResult = WorkspaceEditApplyResultViewModel.fromTelemetry(
      confirmationPlan: confirmationPlan,
      telemetry: WorkspaceEditReviewResultTelemetry.fromApplicationResult(
        confirmationPlan: confirmationPlan,
        result: result,
      ),
      diffWindow: preview.diffWindow(documentLimit: 3, fileOperationLimit: 3),
    );
  }

  WorkspaceEditPlan _planFor(StyioProjectWorkspaceFix fix) {
    return WorkspaceEditPlan(
      id: 'project-workspace-fix-${_fingerprint(fix)}',
      summary: fix.label,
      source: WorkspaceEditSource.codeAction,
      editsByDocument: fix.editsByDocument,
    );
  }

  String _fingerprint(StyioProjectWorkspaceFix fix) {
    final buffer = StringBuffer(fix.label.trim());
    final entries = fix.editsByDocument.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      buffer.write('|${entry.key}');
      for (final edit in entry.value) {
        buffer.write(
          '@${edit.range.start}-${edit.range.end}:${edit.newText.length}:${edit.newText}',
        );
      }
    }
    var hash = 0x811c9dc5;
    for (final unit in buffer.toString().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
