import '../workspace/workspace.dart';

enum DiagnosticsInteractionActionKind {
  openDocument,
  filterBySource,
  applyQuickFix,
}

extension DiagnosticsInteractionActionKindX
    on DiagnosticsInteractionActionKind {
  String get wireValue {
    return switch (this) {
      DiagnosticsInteractionActionKind.openDocument => 'open-document',
      DiagnosticsInteractionActionKind.filterBySource => 'filter-by-source',
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
    this.metadata = const <String, Object?>{},
  });

  final String actionId;
  final DiagnosticsInteractionActionKind kind;
  final String label;
  final bool enabled;
  final String targetId;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'actionId': actionId,
      'kind': kind.wireValue,
      'label': label,
      'enabled': enabled,
      if (targetId.isNotEmpty) 'targetId': targetId,
      if (metadata.isNotEmpty) 'metadata': metadata,
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
          actionId: 'diagnostics.apply-fix.${plan.planId}',
          kind: DiagnosticsInteractionActionKind.applyQuickFix,
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
