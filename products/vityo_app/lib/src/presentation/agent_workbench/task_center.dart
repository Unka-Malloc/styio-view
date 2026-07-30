import 'package:flutter/material.dart';

import '../../ide/workbench/agent_collaboration/collaboration_store.dart';

final class AgentTaskCenter extends StatelessWidget {
  const AgentTaskCenter({
    required this.projection,
    required this.onSelectSession,
    this.selectedSessionId,
    super.key,
  });

  final CollaborationProjection projection;
  final String? selectedSessionId;
  final ValueChanged<String> onSelectSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Agent task center',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              projection.attentionCount == 1
                  ? '1 action required'
                  : '${projection.attentionCount} actions required',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: projection.orderedSessionIds.length,
              itemBuilder: (context, index) {
                final session = projection.session(
                  projection.orderedSessionIds[index],
                );
                return ListTile(
                  key: ValueKey<String>('agent-task-${session.sessionId}'),
                  selected: session.sessionId == selectedSessionId,
                  title: Text(session.title),
                  subtitle: Text(_statusLabel(session.status)),
                  trailing: session.attentionRequired
                      ? const Icon(
                          Icons.notifications_active_outlined,
                          semanticLabel: 'Action required',
                        )
                      : null,
                  onTap: () => onSelectSession(session.sessionId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(CollaborationTaskStatus status) => switch (status) {
  CollaborationTaskStatus.active => 'Active',
  CollaborationTaskStatus.waitingForUser => 'Waiting for user',
  CollaborationTaskStatus.blocked => 'Blocked',
  CollaborationTaskStatus.completed => 'Completed',
  CollaborationTaskStatus.failed => 'Failed',
  CollaborationTaskStatus.cancelled => 'Cancelled',
};
