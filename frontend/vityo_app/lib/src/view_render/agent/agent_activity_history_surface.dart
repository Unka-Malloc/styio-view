import 'package:flutter/material.dart';

import '../../view_ide/agent/agent.dart';

class AgentActivityHistorySurface extends StatelessWidget {
  const AgentActivityHistorySurface({
    super.key,
    required this.history,
    this.maxVisibleRecords = 8,
  });

  final AgentCodingSessionHistory history;
  final int maxVisibleRecords;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final records = history.records
        .take(maxVisibleRecords)
        .toList(growable: false);
    return Card(
      key: const ValueKey('agent-activity-history-surface'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Agent Activity', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              records.isEmpty
                  ? 'No persisted agent coding sessions yet.'
                  : '${history.records.length} persisted coding session(s).',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              const _AgentActivityEmptyState()
            else
              for (final record in records) _AgentActivityRecordTile(record),
          ],
        ),
      ),
    );
  }
}

class _AgentActivityEmptyState extends StatelessWidget {
  const _AgentActivityEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'Run an agent prompt to create an auditable activity record.',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _AgentActivityRecordTile extends StatelessWidget {
  const _AgentActivityRecordTile(this.record);

  final AgentCodingSessionHistoryRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorMessage = record.errorMessage?.trim();
    final validationSummary = _activityValidationSummary(record.metadata);
    final statusColor = record.succeeded
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: statusColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              Text(
                record.outcome.wireValue,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${record.providerKind} / ${record.profileId} / ${record.requestId}',
            style: theme.textTheme.bodySmall,
          ),
          if (errorMessage != null && errorMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Error: $errorMessage',
              key: const ValueKey('agent-activity-record-error'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (record.responseTextSample.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              record.responseTextSample,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (validationSummary != null) ...[
            const SizedBox(height: 6),
            Text(
              validationSummary,
              key: const ValueKey('agent-activity-validation-summary'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ActivityChip(label: 'parts ${record.contentPartCount}'),
              _ActivityChip(label: 'patches ${record.patchCount}'),
              _ActivityChip(label: 'commands ${record.ideCommandCount}'),
              _ActivityChip(label: 'plans ${record.planCount}'),
              _ActivityChip(
                label: 'diagnostics ${record.diagnosticSummaryCount}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String? _activityValidationSummary(Map<String, Object?> metadata) {
  final validationResult = _metadataObject(metadata['validationResult']);
  final validationPipeline = _metadataObject(metadata['validationPipeline']);
  if (validationResult.isEmpty && validationPipeline.isEmpty) {
    return null;
  }
  final resultStatus = validationResult['status'] as String? ?? 'unknown';
  final pipelineStatus = validationPipeline['status'] as String? ?? 'unknown';
  final progressNumerator = validationPipeline['progressNumerator'] as int?;
  final progressDenominator =
      validationPipeline['progressDenominator'] as int?;
  final nextCommandId = validationPipeline['nextCommandId'] as String?;
  final progress = progressNumerator == null || progressDenominator == null
      ? ''
      : ' $progressNumerator/$progressDenominator';
  final next = nextCommandId == null ? '' : ' · next $nextCommandId';
  return 'Validation: $resultStatus · pipeline $pipelineStatus$progress$next';
}

Map<String, Object?> _metadataObject(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is String) {
        result[key] = entry.value;
      }
    }
    return result;
  }
  return const <String, Object?>{};
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(label, style: theme.textTheme.labelSmall),
      ),
    );
  }
}
