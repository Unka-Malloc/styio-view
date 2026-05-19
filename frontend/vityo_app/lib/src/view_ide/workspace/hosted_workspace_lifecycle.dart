import '../backend_toolchain/project_graph_contract.dart';

class HostedWorkspaceLifecycle {
  const HostedWorkspaceLifecycle({this.defaultRetentionDays = 7});

  final int defaultRetentionDays;

  HostedWorkspaceClosePlan? closePlanFor(
    ProjectGraphSnapshot project, {
    DateTime? now,
  }) {
    final workspace = project.hostedWorkspace;
    if (workspace == null) {
      return null;
    }
    return HostedWorkspaceClosePlan(
      workspaceId: workspace.workspaceId,
      status: workspace.status,
      exportState: workspace.exportState,
      coreFilePaths: _coreFilePaths(project),
      exportUrl: workspace.coreFileExportUrl,
      exportExpiresAt: workspace.coreFileExportExpiresAt,
      requiresClearConfirmation: workspace.status != HostedWorkspaceStatus.deleted,
      pendingDeletionPlan: workspace.status == HostedWorkspaceStatus.pendingDeletion
          ? pendingDeletionPlanFor(workspace, now: now)
          : null,
    );
  }

  HostedWorkspacePendingDeletionPlan pendingDeletionPlanFor(
    HostedWorkspaceRecordSnapshot workspace, {
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now().toUtc();
    final retentionDays = workspace.retentionDays > 0
        ? workspace.retentionDays
        : defaultRetentionDays;
    final closedAt = workspace.closedAt ?? effectiveNow;
    final deadline =
        workspace.retentionDeadline ??
        closedAt.add(Duration(days: retentionDays));
    final remaining = deadline.difference(effectiveNow);
    return HostedWorkspacePendingDeletionPlan(
      workspaceId: workspace.workspaceId,
      retentionDays: retentionDays,
      closedAt: closedAt,
      deadline: deadline,
      remaining: remaining.isNegative ? Duration.zero : remaining,
      expired: !effectiveNow.isBefore(deadline),
    );
  }

  List<String> _coreFilePaths(ProjectGraphSnapshot project) {
    final paths = <String>[];

    void add(String? path) {
      final trimmed = path?.trim();
      if (trimmed == null || trimmed.isEmpty || paths.contains(trimmed)) {
        return;
      }
      paths.add(trimmed);
    }

    add(project.manifestPath);
    add(project.styioConfigPath);
    add(project.toolchainPinPath);
    add(project.lockfilePath);
    for (final file in project.editorFiles) {
      add(file);
    }
    return List.unmodifiable(paths);
  }
}

class HostedWorkspaceClosePlan {
  const HostedWorkspaceClosePlan({
    required this.workspaceId,
    required this.status,
    required this.exportState,
    required this.coreFilePaths,
    required this.requiresClearConfirmation,
    this.exportUrl,
    this.exportExpiresAt,
    this.pendingDeletionPlan,
  });

  final String workspaceId;
  final HostedWorkspaceStatus status;
  final HostedWorkspaceExportState exportState;
  final List<String> coreFilePaths;
  final bool requiresClearConfirmation;
  final String? exportUrl;
  final DateTime? exportExpiresAt;
  final HostedWorkspacePendingDeletionPlan? pendingDeletionPlan;

  bool get hasCoreFileExportEntry => coreFilePaths.isNotEmpty;

  bool get exportReady =>
      exportState == HostedWorkspaceExportState.ready &&
      exportUrl != null &&
      exportUrl!.trim().isNotEmpty;

  String get exportStateLabel => exportState.label;
}

class HostedWorkspacePendingDeletionPlan {
  const HostedWorkspacePendingDeletionPlan({
    required this.workspaceId,
    required this.retentionDays,
    required this.closedAt,
    required this.deadline,
    required this.remaining,
    required this.expired,
  });

  final String workspaceId;
  final int retentionDays;
  final DateTime closedAt;
  final DateTime deadline;
  final Duration remaining;
  final bool expired;
}
