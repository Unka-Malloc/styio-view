import 'package:flutter/material.dart';

import '../../ide/workbench/agent_collaboration/collaboration_store.dart';
import '../../ide/workspace/workspace_transaction_service.dart';

final class AgentChangeReviewView extends StatelessWidget {
  const AgentChangeReviewView({
    required this.review,
    required this.onDecision,
    super.key,
  });

  final AgentChangeReviewProjection review;
  final Future<AgentChangeReviewProjection> Function(
    AgentChangeReviewDecision decision,
  )
  onDecision;

  @override
  Widget build(BuildContext context) {
    final ready = review.outcome == WorkspaceTransactionOutcome.ready;
    final committed = review.outcome == WorkspaceTransactionOutcome.committed;
    return Semantics(
      container: true,
      label: 'Agent change review',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${review.fileCount} files · ${review.hunkCount} hunks',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: review.changeSet.resources.length,
              itemBuilder: (context, index) {
                final resource = review.changeSet.resources[index];
                return ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(
                    resource.resourceId,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${resource.edits.length} '
                    '${resource.edits.length == 1 ? 'hunk' : 'hunks'}',
                  ),
                  children: <Widget>[
                    for (final edit in resource.edits)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${edit.start}–${edit.end}: '
                          '${_boundedReplacementPreview(edit.replacement)}',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (review.conflicts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                '${review.conflicts.length} conflicts require attention',
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: <Widget>[
                OutlinedButton(
                  key: const ValueKey<String>('change-review-reject'),
                  onPressed: ready
                      ? () => onDecision(AgentChangeReviewDecision.reject)
                      : null,
                  child: const Text('Reject'),
                ),
                FilledButton(
                  key: const ValueKey<String>('change-review-commit'),
                  onPressed: ready
                      ? () => onDecision(AgentChangeReviewDecision.commit)
                      : null,
                  child: const Text('Apply changes'),
                ),
                if (committed)
                  OutlinedButton(
                    key: const ValueKey<String>('change-review-revert'),
                    onPressed: () =>
                        onDecision(AgentChangeReviewDecision.revert),
                    child: const Text('Revert'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _boundedReplacementPreview(String replacement) {
  const maxCodeUnits = 512;
  if (replacement.length <= maxCodeUnits) {
    return replacement;
  }
  var end = maxCodeUnits;
  final last = replacement.codeUnitAt(end - 1);
  if (last >= 0xD800 && last <= 0xDBFF) {
    end -= 1;
  }
  return '${replacement.substring(0, end)}… '
      '(${replacement.length - end} code units omitted)';
}
