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
      requiresClearConfirmation:
          workspace.status != HostedWorkspaceStatus.deleted,
      pendingDeletionPlan:
          workspace.status == HostedWorkspaceStatus.pendingDeletion
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

  HostedBackendConnectorParityReport connectorParityReportFor(
    ProjectGraphSnapshot project, {
    bool controlPlaneAvailable = true,
    bool documentStoreAvailable = true,
    bool backendReachable = true,
    String? failureMessage,
    DateTime? now,
  }) {
    final workspace = project.hostedWorkspace;
    if (workspace == null) {
      return HostedBackendConnectorParityReport(
        workspaceId: project.id,
        status: HostedBackendConnectorStatus.unavailable,
        message: 'No hosted workspace record is available for this project.',
        checks: const <HostedBackendConnectorCheck>[
          HostedBackendConnectorCheck(
            id: 'hosted-workspace-record',
            label: 'Hosted workspace record',
            available: false,
            required: true,
            message: 'Project graph has no hosted workspace snapshot.',
          ),
        ],
        actions: const <HostedBackendRetryAction>[
          HostedBackendRetryAction(
            id: 'open-settings',
            label: 'Open hosted settings',
            kind: HostedBackendRetryActionKind.openSettings,
          ),
        ],
      );
    }

    final closePlan = closePlanFor(project, now: now);
    final checks = <HostedBackendConnectorCheck>[
      HostedBackendConnectorCheck(
        id: 'control-plane',
        label: 'Hosted control plane',
        available: controlPlaneAvailable,
        required: true,
        message: controlPlaneAvailable
            ? 'Control plane connector is available.'
            : 'Control plane connector is unavailable.',
      ),
      HostedBackendConnectorCheck(
        id: 'document-store',
        label: 'Hosted document store',
        available: documentStoreAvailable,
        required: true,
        message: documentStoreAvailable
            ? 'Document store connector is available.'
            : 'Document store connector is unavailable.',
      ),
      HostedBackendConnectorCheck(
        id: 'backend-reachability',
        label: 'Hosted backend reachability',
        available: backendReachable,
        required: true,
        message: backendReachable
            ? 'Hosted backend route is reachable.'
            : failureMessage ?? 'Hosted backend route is unreachable.',
      ),
      HostedBackendConnectorCheck(
        id: 'entry-url',
        label: 'Workspace entry URL',
        available: workspace.entryUrl.trim().isNotEmpty,
        required: true,
        message: workspace.entryUrl.trim().isNotEmpty
            ? 'Workspace entry URL is available.'
            : 'Workspace entry URL is missing.',
      ),
    ];
    final missingRequired = checks.any(
      (check) => check.required && !check.available,
    );
    final status = _connectorStatusFor(
      workspace,
      missingRequired: missingRequired,
    );
    return HostedBackendConnectorParityReport(
      workspaceId: workspace.workspaceId,
      status: status,
      message: _connectorMessage(
        workspace,
        status: status,
        failureMessage: failureMessage,
      ),
      checks: List.unmodifiable(checks),
      actions: _retryActionsFor(
        workspace,
        status: status,
        closePlan: closePlan,
      ),
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

  HostedBackendConnectorStatus _connectorStatusFor(
    HostedWorkspaceRecordSnapshot workspace, {
    required bool missingRequired,
  }) {
    if (workspace.status == HostedWorkspaceStatus.deleted ||
        workspace.status == HostedWorkspaceStatus.pendingDeletion) {
      return HostedBackendConnectorStatus.blocked;
    }
    if (missingRequired) {
      return HostedBackendConnectorStatus.retryableFailure;
    }
    if (workspace.status == HostedWorkspaceStatus.active) {
      return HostedBackendConnectorStatus.ready;
    }
    return HostedBackendConnectorStatus.retryableFailure;
  }

  String _connectorMessage(
    HostedWorkspaceRecordSnapshot workspace, {
    required HostedBackendConnectorStatus status,
    String? failureMessage,
  }) {
    return switch (status) {
      HostedBackendConnectorStatus.ready =>
        'Hosted backend connectors are ready for workspace ${workspace.workspaceId}.',
      HostedBackendConnectorStatus.retryableFailure =>
        failureMessage?.trim().isNotEmpty == true
            ? 'Hosted backend connector is retryable: ${failureMessage!.trim()}'
            : 'Hosted backend connector is not ready yet; retry or refresh the workspace.',
      HostedBackendConnectorStatus.blocked =>
        'Hosted workspace ${workspace.workspaceId} is ${workspace.status.label}; reopen or export core files before continuing.',
      HostedBackendConnectorStatus.unavailable =>
        'Hosted backend connector state is unavailable.',
    };
  }

  List<HostedBackendRetryAction> _retryActionsFor(
    HostedWorkspaceRecordSnapshot workspace, {
    required HostedBackendConnectorStatus status,
    HostedWorkspaceClosePlan? closePlan,
  }) {
    final actions = <HostedBackendRetryAction>[
      HostedBackendRetryAction(
        id: 'retry-connect',
        label: 'Retry connection',
        kind: HostedBackendRetryActionKind.retryConnect,
        enabled: status == HostedBackendConnectorStatus.retryableFailure,
        message: status == HostedBackendConnectorStatus.retryableFailure
            ? 'Retry the hosted backend connector route.'
            : 'Retry is only available for retryable connector failures.',
        endpointPlan: HostedBackendRetryEndpointPlan.forAction(
          actionId: 'retry-connect',
          kind: HostedBackendRetryActionKind.retryConnect,
          workspaceId: workspace.workspaceId,
        ),
      ),
      HostedBackendRetryAction(
        id: 'refresh-workspace',
        label: 'Refresh workspace',
        kind: HostedBackendRetryActionKind.refreshWorkspace,
        enabled: workspace.status != HostedWorkspaceStatus.deleted,
        message: 'Refresh hosted workspace state from the control plane.',
        endpointPlan: HostedBackendRetryEndpointPlan.forAction(
          actionId: 'refresh-workspace',
          kind: HostedBackendRetryActionKind.refreshWorkspace,
          workspaceId: workspace.workspaceId,
        ),
      ),
      HostedBackendRetryAction(
        id: 'reopen-workspace',
        label: 'Reopen workspace',
        kind: HostedBackendRetryActionKind.reopenWorkspace,
        enabled: workspace.status == HostedWorkspaceStatus.pendingDeletion,
        message: workspace.status == HostedWorkspaceStatus.pendingDeletion
            ? 'Reopen this pending-deletion hosted workspace.'
            : 'Reopen is only available for pending-deletion workspaces.',
        endpointPlan: HostedBackendRetryEndpointPlan.forAction(
          actionId: 'reopen-workspace',
          kind: HostedBackendRetryActionKind.reopenWorkspace,
          workspaceId: workspace.workspaceId,
        ),
      ),
      HostedBackendRetryAction(
        id: 'export-core-files',
        label: 'Export core files',
        kind: HostedBackendRetryActionKind.exportCoreFiles,
        enabled: closePlan?.exportReady ?? false,
        message: closePlan?.exportReady == true
            ? 'Download core files before clearing or reconnecting.'
            : 'Core file export is not ready yet.',
        endpointPlan: HostedBackendRetryEndpointPlan.forAction(
          actionId: 'export-core-files',
          kind: HostedBackendRetryActionKind.exportCoreFiles,
          workspaceId: workspace.workspaceId,
        ),
      ),
      HostedBackendRetryAction(
        id: 'open-settings',
        label: 'Open hosted settings',
        kind: HostedBackendRetryActionKind.openSettings,
        message: 'Open hosted backend configuration and credential settings.',
        endpointPlan: HostedBackendRetryEndpointPlan.forAction(
          actionId: 'open-settings',
          kind: HostedBackendRetryActionKind.openSettings,
          workspaceId: workspace.workspaceId,
        ),
      ),
    ];
    return List.unmodifiable(actions);
  }
}

enum HostedBackendConnectorStatus {
  ready,
  retryableFailure,
  blocked,
  unavailable,
}

extension HostedBackendConnectorStatusX on HostedBackendConnectorStatus {
  String get label {
    return switch (this) {
      HostedBackendConnectorStatus.ready => 'ready',
      HostedBackendConnectorStatus.retryableFailure => 'retryable-failure',
      HostedBackendConnectorStatus.blocked => 'blocked',
      HostedBackendConnectorStatus.unavailable => 'unavailable',
    };
  }
}

enum HostedBackendRetryActionKind {
  retryConnect,
  refreshWorkspace,
  reopenWorkspace,
  exportCoreFiles,
  openSettings,
}

extension HostedBackendRetryActionKindX on HostedBackendRetryActionKind {
  String get label {
    return switch (this) {
      HostedBackendRetryActionKind.retryConnect => 'retry-connect',
      HostedBackendRetryActionKind.refreshWorkspace => 'refresh-workspace',
      HostedBackendRetryActionKind.reopenWorkspace => 'reopen-workspace',
      HostedBackendRetryActionKind.exportCoreFiles => 'export-core-files',
      HostedBackendRetryActionKind.openSettings => 'open-settings',
    };
  }
}

class HostedBackendConnectorCheck {
  const HostedBackendConnectorCheck({
    required this.id,
    required this.label,
    required this.available,
    required this.required,
    this.message,
  });

  final String id;
  final String label;
  final bool available;
  final bool required;
  final String? message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'available': available,
      'required': required,
      if (message != null) 'message': message,
    };
  }
}

class HostedBackendRetryAction {
  const HostedBackendRetryAction({
    required this.id,
    required this.label,
    required this.kind,
    this.enabled = true,
    this.message,
    this.endpointPlan,
  });

  final String id;
  final String label;
  final HostedBackendRetryActionKind kind;
  final bool enabled;
  final String? message;
  final HostedBackendRetryEndpointPlan? endpointPlan;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'kind': kind.label,
      'enabled': enabled,
      if (message != null) 'message': message,
      if (endpointPlan != null) 'endpointPlan': endpointPlan!.toJson(),
    };
  }
}

class HostedBackendRetryEndpointPlan {
  const HostedBackendRetryEndpointPlan({
    required this.actionId,
    required this.kind,
    required this.workspaceId,
    required this.method,
    required this.route,
    required this.published,
    this.settingsRoute = '',
  });

  factory HostedBackendRetryEndpointPlan.forAction({
    required String actionId,
    required HostedBackendRetryActionKind kind,
    required String workspaceId,
  }) {
    final encodedWorkspaceId = Uri.encodeComponent(workspaceId);
    return switch (kind) {
      HostedBackendRetryActionKind.retryConnect =>
        HostedBackendRetryEndpointPlan(
          actionId: actionId,
          kind: kind,
          workspaceId: workspaceId,
          method: 'GET',
          route:
              '/hosted/workspaces/$encodedWorkspaceId/project-graph',
          published: true,
        ),
      HostedBackendRetryActionKind.refreshWorkspace =>
        HostedBackendRetryEndpointPlan(
          actionId: actionId,
          kind: kind,
          workspaceId: workspaceId,
          method: 'GET',
          route:
              '/hosted/workspaces/$encodedWorkspaceId/project-graph',
          published: true,
        ),
      HostedBackendRetryActionKind.reopenWorkspace =>
        HostedBackendRetryEndpointPlan(
          actionId: actionId,
          kind: kind,
          workspaceId: workspaceId,
          method: 'POST',
          route: '/hosted/workspaces/$encodedWorkspaceId/reopen',
          published: false,
        ),
      HostedBackendRetryActionKind.exportCoreFiles =>
        HostedBackendRetryEndpointPlan(
          actionId: actionId,
          kind: kind,
          workspaceId: workspaceId,
          method: 'POST',
          route:
              '/hosted/workspaces/$encodedWorkspaceId/core-files/export',
          published: false,
        ),
      HostedBackendRetryActionKind.openSettings =>
        HostedBackendRetryEndpointPlan(
          actionId: actionId,
          kind: kind,
          workspaceId: workspaceId,
          method: 'OPEN',
          route: 'settings://hosted-backend?workspaceId=$encodedWorkspaceId',
          published: true,
          settingsRoute:
              'settings://hosted-backend?workspaceId=$encodedWorkspaceId',
        ),
    };
  }

  final String actionId;
  final HostedBackendRetryActionKind kind;
  final String workspaceId;
  final String method;
  final String route;
  final bool published;
  final String settingsRoute;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'actionId': actionId,
      'kind': kind.label,
      'workspaceId': workspaceId,
      'method': method,
      'route': route,
      'published': published,
      if (settingsRoute.isNotEmpty) 'settingsRoute': settingsRoute,
    };
  }
}

class HostedBackendConnectorParityReport {
  const HostedBackendConnectorParityReport({
    required this.workspaceId,
    required this.status,
    required this.message,
    required this.checks,
    required this.actions,
  });

  final String workspaceId;
  final HostedBackendConnectorStatus status;
  final String message;
  final List<HostedBackendConnectorCheck> checks;
  final List<HostedBackendRetryAction> actions;

  bool get ready => status == HostedBackendConnectorStatus.ready;

  HostedBackendRetryAction? actionFor(HostedBackendRetryActionKind kind) {
    for (final action in actions) {
      if (action.kind == kind) {
        return action;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'status': status.label,
      'ready': ready,
      'message': message,
      'checks': checks.map((check) => check.toJson()).toList(growable: false),
      'actions': actions
          .map((action) => action.toJson())
          .toList(growable: false),
    };
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
