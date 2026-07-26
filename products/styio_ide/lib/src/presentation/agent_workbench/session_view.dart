import 'package:flutter/material.dart';

import '../../ide/agent_client/agent_client.dart';
import '../../ide/workbench/agent_collaboration/collaboration_store.dart';

final class AgentSessionView extends StatefulWidget {
  const AgentSessionView({
    required this.session,
    required this.commands,
    super.key,
  });

  final CollaborationSessionProjection session;
  final AgentWorkbenchCommandPort commands;

  @override
  State<AgentSessionView> createState() => _AgentSessionViewState();
}

final class _AgentSessionViewState extends State<AgentSessionView> {
  final TextEditingController _steerController = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _steerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Agent session ${session.title}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              session.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (session.droppedTimelineCount > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '${session.droppedTimelineCount} earlier activities omitted',
              ),
            ),
          Expanded(
            child: ListView.builder(
              key: ValueKey<String>('agent-timeline-${session.sessionId}'),
              itemCount: session.timeline.length,
              itemBuilder: (context, index) {
                final entry = session.timeline[index];
                return ListTile(
                  dense: true,
                  title: Text(entry.label),
                  subtitle: Text(entry.kind.name),
                );
              },
            ),
          ),
          for (final permission in session.pendingPermissions.values)
            _PermissionCard(permission: permission),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    key: const ValueKey<String>('agent-steer-input'),
                    controller: _steerController,
                    enabled: !_sending,
                    decoration: const InputDecoration(
                      labelText: 'Steer Agent',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _steer(),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('agent-steer-submit'),
                  tooltip: 'Send steering message',
                  onPressed: _sending ? null : _steer,
                  icon: const Icon(Icons.send_outlined),
                ),
                Semantics(
                  label: 'Cancel Agent task',
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey<String>('agent-cancel'),
                    tooltip: 'Cancel Agent task',
                    onPressed: () => widget.commands.cancel(session.sessionId),
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('agent-retry'),
                  tooltip: 'Retry Agent task',
                  onPressed: () => widget.commands.retry(session.sessionId),
                  icon: const Icon(Icons.refresh),
                ),
                Semantics(
                  label: 'Reconnect Agent',
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    key: const ValueKey<String>('agent-reconnect'),
                    tooltip: 'Reconnect Agent',
                    onPressed: () =>
                        widget.commands.reconnect(session.sessionId),
                    icon: const Icon(Icons.link),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _steer() async {
    final prompt = _steerController.text.trim();
    if (prompt.isEmpty || _sending) {
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.commands.steer(widget.session.sessionId, prompt);
      _steerController.clear();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }
}

final class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.permission});

  final CollaborationPermissionProjection permission;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Permission required',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: <Widget>[
              const Text('Permission required'),
              if (permission.options.contains('allow_once'))
                FilledButton(
                  key: ValueKey<String>(
                    'permission-${permission.id}-allow_once',
                  ),
                  onPressed: () =>
                      permission.resolve(AgentPermissionDecision.allowOnce),
                  child: const Text('Allow once'),
                ),
              if (permission.options.contains('reject_once'))
                OutlinedButton(
                  key: ValueKey<String>(
                    'permission-${permission.id}-reject_once',
                  ),
                  onPressed: () =>
                      permission.resolve(AgentPermissionDecision.rejectOnce),
                  child: const Text('Reject'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
