import 'package:flutter/material.dart';

import '../../view_ide/backend_toolchain/project_graph_contract.dart';
import '../../view_ide/workspace/workspace.dart';

class HostedWorkspaceLifecycleBanner extends StatelessWidget {
  const HostedWorkspaceLifecycleBanner({
    super.key,
    required this.plan,
    this.connectorReport,
    this.onRetryAction,
  });

  final HostedWorkspaceClosePlan plan;
  final HostedBackendConnectorParityReport? connectorReport;
  final ValueChanged<HostedBackendRetryAction>? onRetryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pendingDeletion = plan.pendingDeletionPlan;

    return Card(
      key: const ValueKey('hosted-workspace-lifecycle-banner'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_done_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hosted workspace close guard',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Chip(label: Text(plan.status.label)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              plan.requiresClearConfirmation
                  ? 'Close requires explicit clear confirmation before browser-local hosted workspace state is discarded.'
                  : 'Hosted workspace is already deleted; local close can proceed without clear confirmation.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('core files ${plan.coreFilePaths.length}')),
                Chip(label: Text('export ${plan.exportStateLabel}')),
                if (pendingDeletion != null)
                  Chip(
                    label: Text(
                      'retention ${pendingDeletion.retentionDays} days',
                    ),
                  ),
              ],
            ),
            if (plan.exportReady) ...[
              const SizedBox(height: 10),
              SelectableText(
                'Download core files: ${plan.exportUrl}',
                key: const ValueKey('hosted-workspace-export-entry'),
                style: theme.textTheme.bodySmall,
              ),
              if (plan.exportExpiresAt != null)
                Text(
                  'Export expires at ${_dateLabel(plan.exportExpiresAt!)}.',
                  style: theme.textTheme.bodySmall,
                ),
            ] else if (plan.hasCoreFileExportEntry) ...[
              const SizedBox(height: 10),
              Text(
                'Core file export entry is available before clearing the hosted workspace.',
                key: const ValueKey('hosted-workspace-export-entry'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (pendingDeletion != null) ...[
              const SizedBox(height: 10),
              Text(
                pendingDeletion.expired
                    ? 'Pending-deletion retention has expired.'
                    : 'Pending-deletion workspace is retained until ${_dateLabel(pendingDeletion.deadline)}.',
                key: const ValueKey('hosted-workspace-retention-message'),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (connectorReport != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.sync_problem_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Hosted backend connector',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Chip(label: Text(connectorReport!.status.label)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                connectorReport!.message,
                key: const ValueKey('hosted-backend-connector-message'),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final check in connectorReport!.checks)
                    Chip(
                      key: ValueKey('hosted-backend-check-${check.id}'),
                      avatar: Icon(
                        check.available
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                      ),
                      label: Text(check.label),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in connectorReport!.actions)
                    OutlinedButton(
                      key: ValueKey('hosted-backend-action-${action.id}'),
                      onPressed: action.enabled && onRetryAction != null
                          ? () => onRetryAction!(action)
                          : null,
                      child: Text(action.label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  return value.toUtc().toIso8601String().split('.').first;
}
