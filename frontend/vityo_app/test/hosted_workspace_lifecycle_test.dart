import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('builds close plan with clear confirmation and core export files', () {
    final project = _project(
      workspace: _workspace(
        status: HostedWorkspaceStatus.active,
        exportState: HostedWorkspaceExportState.ready,
        coreFileExportUrl: 'https://hosted.example/export/demo.zip',
      ),
    );

    final plan = const HostedWorkspaceLifecycle().closePlanFor(project);

    expect(plan, isNotNull);
    expect(plan!.workspaceId, 'hosted-demo');
    expect(plan.requiresClearConfirmation, isTrue);
    expect(plan.exportReady, isTrue);
    expect(plan.coreFilePaths, <String>[
      '/workspace/demo/spio.toml',
      '/workspace/demo/styio.toml',
      '/workspace/demo/spio-toolchain.toml',
      '/workspace/demo/spio.lock',
      '/workspace/demo/src/main.styio',
      '/workspace/demo/src/lib.styio',
    ]);
  });

  test('uses a seven day retention default for pending deletion', () {
    final closedAt = DateTime.utc(2026, 5, 1, 12);
    final now = DateTime.utc(2026, 5, 3, 12);
    final workspace = _workspace(
      status: HostedWorkspaceStatus.pendingDeletion,
      retentionDays: 0,
      closedAt: closedAt,
    );

    final pending = const HostedWorkspaceLifecycle().pendingDeletionPlanFor(
      workspace,
      now: now,
    );

    expect(pending.retentionDays, 7);
    expect(pending.deadline, DateTime.utc(2026, 5, 8, 12));
    expect(pending.remaining, const Duration(days: 5));
    expect(pending.expired, isFalse);
  });

  test('reports hosted backend connector parity and retry actions', () {
    final project = _project(
      workspace: _workspace(
        status: HostedWorkspaceStatus.active,
        exportState: HostedWorkspaceExportState.ready,
        coreFileExportUrl: 'https://hosted.example/export/demo.zip',
      ),
    );

    final report = const HostedWorkspaceLifecycle().connectorParityReportFor(
      project,
      controlPlaneAvailable: false,
      backendReachable: false,
      failureMessage: '503 from hosted backend',
    );
    final json = report.toJson();

    expect(report.status, HostedBackendConnectorStatus.retryableFailure);
    expect(report.ready, isFalse);
    expect(report.message, contains('503 from hosted backend'));
    expect(
      report.checks
          .singleWhere((check) => check.id == 'control-plane')
          .available,
      isFalse,
    );
    expect(
      report.actionFor(HostedBackendRetryActionKind.retryConnect)?.enabled,
      isTrue,
    );
    expect(
      report.actionFor(HostedBackendRetryActionKind.exportCoreFiles)?.enabled,
      isTrue,
    );
    expect(json['status'], 'retryable-failure');
    expect(json['actions'], isA<List<Object?>>());
  });

  test('blocks pending-deletion workspace but offers reopen action', () {
    final project = _project(
      workspace: _workspace(status: HostedWorkspaceStatus.pendingDeletion),
    );

    final report = const HostedWorkspaceLifecycle().connectorParityReportFor(
      project,
    );

    expect(report.status, HostedBackendConnectorStatus.blocked);
    expect(
      report.actionFor(HostedBackendRetryActionKind.reopenWorkspace)?.enabled,
      isTrue,
    );
    expect(
      report.actionFor(HostedBackendRetryActionKind.retryConnect)?.enabled,
      isFalse,
    );
  });
}

ProjectGraphSnapshot _project({
  required HostedWorkspaceRecordSnapshot workspace,
}) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.hosted,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/spio.toml',
    lockfilePath: '/workspace/demo/spio.lock',
    toolchainPinPath: '/workspace/demo/spio-toolchain.toml',
    styioConfigPath: '/workspace/demo/styio.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>[
      '/workspace/demo/src/main.styio',
      '/workspace/demo/src/lib.styio',
    ],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'Hosted lifecycle fixture.',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.unknown,
    hostedWorkspace: workspace,
    notes: const <String>[],
  );
}

HostedWorkspaceRecordSnapshot _workspace({
  required HostedWorkspaceStatus status,
  HostedWorkspaceExportState exportState =
      HostedWorkspaceExportState.notRequested,
  int retentionDays = 7,
  DateTime? closedAt,
  String? coreFileExportUrl,
}) {
  return HostedWorkspaceRecordSnapshot(
    workspaceId: 'hosted-demo',
    schemaVersion: '1',
    ownerRef: 'user:test',
    status: status,
    entryUrl: 'https://hosted.example/workspaces/hosted-demo',
    createdAt: DateTime.utc(2026, 5),
    lastActiveAt: DateTime.utc(2026, 5, 1, 11),
    retentionDays: retentionDays,
    exportState: exportState,
    closedAt: closedAt,
    coreFileExportUrl: coreFileExportUrl,
  );
}
