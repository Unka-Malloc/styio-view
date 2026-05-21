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
    final validationFailureEvidence = _activityValidationFailureEvidence(
      record.metadata,
    );
    final toolCallSummary = _activityToolCallSummary(record.metadata);
    final toolCallFailureEvidence = _activityToolCallFailureEvidence(
      record.metadata,
    );
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
          if (validationFailureEvidence != null) ...[
            const SizedBox(height: 6),
            Text(
              validationFailureEvidence,
              key: const ValueKey('agent-activity-validation-failure-evidence'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (toolCallSummary != null) ...[
            const SizedBox(height: 6),
            Text(
              toolCallSummary,
              key: const ValueKey('agent-activity-tool-call-summary'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ],
          if (toolCallFailureEvidence != null) ...[
            const SizedBox(height: 6),
            Text(
              toolCallFailureEvidence,
              key: const ValueKey('agent-activity-tool-call-failure-evidence'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
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

String? _activityToolCallSummary(Map<String, Object?> metadata) {
  final journal = _metadataObject(metadata['toolCallExecutionJournal']);
  if (journal.isEmpty) {
    return null;
  }
  final status = journal['status'] as String? ?? 'unknown';
  final entries = _metadataIterable(journal['entries']);
  final entryCount = _metadataInt(journal['entryCount']) ?? entries.length;
  final replayCandidateCount = _metadataInt(journal['replayCandidateCount']);
  final sourceEventCount = _metadataInt(journal['sourceEventCount']);
  final parts = <String>[
    'Tool calls: $status',
    '$entryCount entr${entryCount == 1 ? 'y' : 'ies'}',
  ];
  if (replayCandidateCount != null && replayCandidateCount > 0) {
    parts.add('$replayCandidateCount replayable');
  }
  if (sourceEventCount != null && sourceEventCount > 0) {
    parts.add('$sourceEventCount event(s)');
  }
  return parts.join(' · ');
}

String? _activityToolCallFailureEvidence(Map<String, Object?> metadata) {
  final journal = _metadataObject(metadata['toolCallExecutionJournal']);
  if (journal.isEmpty) {
    return null;
  }
  for (final value in _metadataIterable(journal['entries'])) {
    final entry = _metadataObject(value);
    final status = entry['status'] as String?;
    if (status != 'failed' && status != 'permission_blocked') {
      continue;
    }
    final toolId = entry['toolId'] as String?;
    final callId = entry['callId'] as String?;
    final label = toolId == null || toolId.trim().isEmpty
        ? callId ?? 'unknown'
        : toolId;
    final errorMessage = (entry['errorMessage'] as String?)?.trim();
    final permissionReason = (entry['permissionReason'] as String?)?.trim();
    final evidence = errorMessage == null || errorMessage.isEmpty
        ? permissionReason
        : errorMessage;
    if (evidence == null || evidence.isEmpty) {
      return 'Tool call evidence: $label · $status';
    }
    return 'Tool call evidence: $label · $status · $evidence';
  }
  return null;
}

String? _activityValidationSummary(Map<String, Object?> metadata) {
  final validationPlan = _metadataObject(metadata['validationPlan']);
  final validationResult = _metadataObject(metadata['validationResult']);
  final validationPipeline = _metadataObject(metadata['validationPipeline']);
  if (validationPlan.isEmpty &&
      validationResult.isEmpty &&
      validationPipeline.isEmpty) {
    return null;
  }
  final planStatus = validationPlan['status'] as String?;
  final planReason = validationPlan['reason'] as String?;
  if (validationResult.isEmpty && validationPipeline.isEmpty) {
    final reason = planReason == null || planReason.trim().isEmpty
        ? ''
        : ' · $planReason';
    return 'Validation: plan ${planStatus ?? 'unknown'}$reason';
  }
  final resultStatus = validationResult['status'] as String? ?? 'unknown';
  final pipelineStatus = validationPipeline['status'] as String? ?? 'unknown';
  final progressNumerator = validationPipeline['progressNumerator'] as int?;
  final progressDenominator = validationPipeline['progressDenominator'] as int?;
  final nextCommandId = validationPipeline['nextCommandId'] as String?;
  final progress = progressNumerator == null || progressDenominator == null
      ? ''
      : ' $progressNumerator/$progressDenominator';
  final next = nextCommandId == null ? '' : ' · next $nextCommandId';
  return 'Validation: $resultStatus · pipeline $pipelineStatus$progress$next';
}

String? _activityValidationFailureEvidence(Map<String, Object?> metadata) {
  final failedResults = metadata['validationFailedCommandResults'];
  if (failedResults is! Iterable || failedResults.isEmpty) {
    return null;
  }
  final firstResult = _metadataObject(failedResults.first);
  final commandId = firstResult['commandId'] as String?;
  final message = firstResult['message'] as String?;
  if (commandId == null || message == null || message.trim().isEmpty) {
    return null;
  }
  return 'Failure evidence: $commandId · $message';
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

int? _metadataInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

List<Object?> _metadataIterable(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is Iterable) {
    return value.toList(growable: false);
  }
  return const <Object?>[];
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
