import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/view_render/shell/hosted_workspace_lifecycle_banner.dart';

void main() {
  testWidgets('hosted lifecycle banner shows export and retention state', (
    tester,
  ) async {
    final plan = HostedWorkspaceClosePlan(
      workspaceId: 'hosted-demo',
      status: HostedWorkspaceStatus.pendingDeletion,
      exportState: HostedWorkspaceExportState.ready,
      coreFilePaths: const <String>['/workspace/demo/src/main.styio'],
      requiresClearConfirmation: true,
      exportUrl: 'https://hosted.example/export/demo.zip',
      exportExpiresAt: DateTime.utc(2026, 5, 4),
      pendingDeletionPlan: HostedWorkspacePendingDeletionPlan(
        workspaceId: 'hosted-demo',
        retentionDays: 7,
        closedAt: DateTime.utc(2026, 5, 1),
        deadline: DateTime.utc(2026, 5, 8),
        remaining: const Duration(days: 4),
        expired: false,
      ),
    );

    const report = HostedBackendConnectorParityReport(
      workspaceId: 'hosted-demo',
      status: HostedBackendConnectorStatus.retryableFailure,
      message: 'Hosted backend connector is retryable.',
      checks: <HostedBackendConnectorCheck>[
        HostedBackendConnectorCheck(
          id: 'control-plane',
          label: 'Hosted control plane',
          available: false,
          required: true,
        ),
      ],
      actions: <HostedBackendRetryAction>[
        HostedBackendRetryAction(
          id: 'retry-connect',
          label: 'Retry connection',
          kind: HostedBackendRetryActionKind.retryConnect,
        ),
      ],
    );
    final tappedActions = <HostedBackendRetryAction>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HostedWorkspaceLifecycleBanner(
            plan: plan,
            connectorReport: report,
            onRetryAction: tappedActions.add,
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('hosted-workspace-lifecycle-banner')),
      findsOneWidget,
    );
    expect(find.text('Hosted workspace close guard'), findsOneWidget);
    expect(find.text('pending-deletion'), findsOneWidget);
    expect(find.text('retention 7 days'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hosted-workspace-export-entry')),
      findsOneWidget,
    );
    expect(
      find.textContaining('https://hosted.example/export/demo.zip'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hosted-workspace-retention-message')),
      findsOneWidget,
    );
    expect(find.textContaining('2026-05-08T00:00:00'), findsOneWidget);
    expect(find.text('Hosted backend connector'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hosted-backend-connector-message')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hosted-backend-action-retry-connect')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('hosted-backend-action-retry-connect')),
    );

    expect(
      tappedActions.single.kind,
      HostedBackendRetryActionKind.retryConnect,
    );
  });
}
