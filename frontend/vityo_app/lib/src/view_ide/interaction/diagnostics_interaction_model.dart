import '../language/language_contract.dart';
import '../workspace/workspace.dart';

enum DiagnosticsInteractionActionKind {
  openDocument,
  filterBySource,
  previewQuickFix,
  applyQuickFix,
}

extension DiagnosticsInteractionActionKindX
    on DiagnosticsInteractionActionKind {
  String get wireValue {
    return switch (this) {
      DiagnosticsInteractionActionKind.openDocument => 'open-document',
      DiagnosticsInteractionActionKind.filterBySource => 'filter-by-source',
      DiagnosticsInteractionActionKind.previewQuickFix => 'preview-quick-fix',
      DiagnosticsInteractionActionKind.applyQuickFix => 'apply-quick-fix',
    };
  }
}

class DiagnosticsInteractionAction {
  const DiagnosticsInteractionAction({
    required this.actionId,
    required this.kind,
    required this.label,
    this.enabled = true,
    this.targetId = '',
    this.commandId = '',
    this.metadata = const <String, Object?>{},
  });

  final String actionId;
  final DiagnosticsInteractionActionKind kind;
  final String label;
  final bool enabled;
  final String targetId;
  final String commandId;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'actionId': actionId,
      'kind': kind.wireValue,
      'label': label,
      'enabled': enabled,
      if (targetId.isNotEmpty) 'targetId': targetId,
      if (commandId.isNotEmpty) 'commandId': commandId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class DiagnosticsQuickFixCommandRoute {
  const DiagnosticsQuickFixCommandRoute({
    required this.commandId,
    required this.diagnostic,
    required this.quickFixIndex,
    required this.label,
    this.enabled = true,
    this.reason = '',
  });

  factory DiagnosticsQuickFixCommandRoute.preview({
    required WorkspaceDiagnostic diagnostic,
    required int quickFixIndex,
  }) {
    final quickFix = _quickFixAt(diagnostic, quickFixIndex);
    return DiagnosticsQuickFixCommandRoute(
      commandId: 'previewQuickFix',
      diagnostic: diagnostic,
      quickFixIndex: quickFixIndex,
      label: 'Preview ${quickFix?.label ?? 'quick fix'}',
      enabled: quickFix != null,
      reason: quickFix == null
          ? 'Quick fix index $quickFixIndex is not available.'
          : '',
    );
  }

  factory DiagnosticsQuickFixCommandRoute.apply({
    required WorkspaceDiagnostic diagnostic,
    required int quickFixIndex,
  }) {
    final quickFix = _quickFixAt(diagnostic, quickFixIndex);
    return DiagnosticsQuickFixCommandRoute(
      commandId: 'applyQuickFix',
      diagnostic: diagnostic,
      quickFixIndex: quickFixIndex,
      label: 'Apply ${quickFix?.label ?? 'quick fix'}',
      enabled: quickFix != null,
      reason: quickFix == null
          ? 'Quick fix index $quickFixIndex is not available.'
          : '',
    );
  }

  final String commandId;
  final WorkspaceDiagnostic diagnostic;
  final int quickFixIndex;
  final String label;
  final bool enabled;
  final String reason;

  DiagnosticQuickFix? get quickFix {
    return _quickFixAt(diagnostic, quickFixIndex);
  }

  String get routeId {
    return <String>[
      commandId,
      diagnostic.documentId,
      diagnostic.diagnostic.code,
      quickFixIndex.toString(),
    ].join(':');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'routeId': routeId,
      'commandId': commandId,
      'documentId': diagnostic.documentId,
      'diagnosticCode': diagnostic.diagnostic.code,
      'quickFixIndex': quickFixIndex,
      'label': label,
      'enabled': enabled,
      if (reason.isNotEmpty) 'reason': reason,
      if (quickFix != null) 'quickFixLabel': quickFix!.label,
    };
  }
}

class DiagnosticsInteractionModel {
  const DiagnosticsInteractionModel({
    required this.view,
    this.quickFixConfirmationPlans =
        const <WorkspaceQuickFixConfirmationPlan>[],
  });

  final WorkspaceDiagnosticsView view;
  final List<WorkspaceQuickFixConfirmationPlan> quickFixConfirmationPlans;

  factory DiagnosticsInteractionModel.fromWorkspaceView(
    WorkspaceDiagnosticsView view, {
    List<WorkspaceQuickFixConfirmationPlan> quickFixConfirmationPlans =
        const <WorkspaceQuickFixConfirmationPlan>[],
  }) {
    return DiagnosticsInteractionModel(
      view: view,
      quickFixConfirmationPlans:
          List<WorkspaceQuickFixConfirmationPlan>.unmodifiable(
            quickFixConfirmationPlans,
          ),
    );
  }

  int get totalCount => view.totalCount;
  int get visibleCount => view.visibleCount;
  bool get hasVisibleErrors {
    return view.visibleDiagnostics.any((diagnostic) {
      return diagnostic.diagnostic.severity.name == 'error';
    });
  }

  int get readyQuickFixCount {
    return quickFixConfirmationPlans.where((plan) => plan.ready).length;
  }

  int get previewableQuickFixCount {
    return quickFixConfirmationPlans
        .where(
          (plan) =>
              plan.status !=
              WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
        )
        .length;
  }

  List<DiagnosticsInteractionAction> get actions {
    return <DiagnosticsInteractionAction>[
      for (final group in view.documentGroups)
        DiagnosticsInteractionAction(
          actionId: 'diagnostics.open.${group.documentId}',
          kind: DiagnosticsInteractionActionKind.openDocument,
          label: 'Open ${group.documentId}',
          targetId: group.documentId,
          metadata: <String, Object?>{
            'totalCount': group.totalCount,
            'hasErrors': group.hasErrors,
          },
        ),
      for (final group in view.sourceGroups)
        DiagnosticsInteractionAction(
          actionId: 'diagnostics.filter-source.${group.source}',
          kind: DiagnosticsInteractionActionKind.filterBySource,
          label: 'Filter ${group.source}',
          targetId: group.source,
          metadata: <String, Object?>{
            'totalCount': group.totalCount,
            'hasErrors': group.hasErrors,
          },
        ),
      for (final plan in quickFixConfirmationPlans)
        DiagnosticsInteractionAction(
          actionId: 'diagnostics.preview-fix.${plan.planId}',
          kind: DiagnosticsInteractionActionKind.previewQuickFix,
          commandId: 'previewQuickFix',
          label:
              plan.status ==
                  WorkspaceQuickFixConfirmationStatus.blockedNoPreview
              ? plan.message
              : 'Preview ${plan.summary}',
          enabled:
              plan.status !=
              WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
          targetId: plan.planId,
          metadata: <String, Object?>{
            'status': plan.status.wireValue,
            'affectedDocumentIds': plan.affectedDocumentIds,
            'missingDocumentIds': plan.missingDocumentIds,
          },
        ),
      for (final plan in quickFixConfirmationPlans)
        DiagnosticsInteractionAction(
          actionId: 'diagnostics.apply-fix.${plan.planId}',
          kind: DiagnosticsInteractionActionKind.applyQuickFix,
          commandId: 'applyQuickFix',
          label: plan.ready ? 'Apply ${plan.summary}' : plan.message,
          enabled: plan.ready,
          targetId: plan.planId,
          metadata: <String, Object?>{
            'status': plan.status.wireValue,
            'affectedDocumentIds': plan.affectedDocumentIds,
            'missingDocumentIds': plan.missingDocumentIds,
          },
        ),
    ];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': view.providerId,
      'totalCount': totalCount,
      'visibleCount': visibleCount,
      'hasVisibleErrors': hasVisibleErrors,
      'readyQuickFixCount': readyQuickFixCount,
      'previewableQuickFixCount': previewableQuickFixCount,
      'sourceGroups': view.sourceGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'documentGroups': view.documentGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'quickFixConfirmationPlans': quickFixConfirmationPlans
          .map((plan) => plan.toJson())
          .toList(growable: false),
      'actions': actions
          .map((action) => action.toJson())
          .toList(growable: false),
    };
  }
}

DiagnosticQuickFix? _quickFixAt(
  WorkspaceDiagnostic diagnostic,
  int quickFixIndex,
) {
  if (quickFixIndex < 0 || quickFixIndex >= diagnostic.quickFixes.length) {
    return null;
  }
  return diagnostic.quickFixes[quickFixIndex];
}
