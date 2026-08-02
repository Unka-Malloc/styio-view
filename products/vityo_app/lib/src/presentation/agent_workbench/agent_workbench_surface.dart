import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/workbench/agent_collaboration/agent_collaboration_service.dart';
import '../../ide/workbench/agent_collaboration/collaboration_store.dart';
import '../../ide/workspace/workspace_transaction_service.dart';
import 'change_review_view.dart';
import 'session_view.dart';
import 'task_session_list.dart';

/// Shell-facing Agent Workbench host driven only by collaboration projections.
final class AgentWorkbenchSurface extends StatefulWidget {
  const AgentWorkbenchSurface({required this.collaboration, super.key});

  final AgentCollaborationService? collaboration;

  @override
  State<AgentWorkbenchSurface> createState() => _AgentWorkbenchSurfaceState();
}

final class _AgentWorkbenchSurfaceState extends State<AgentWorkbenchSurface> {
  String? _selectedSessionId;
  CollaborationProjection? _projection;
  StreamSubscription<CollaborationProjection>? _projectionSubscription;

  @override
  void initState() {
    super.initState();
    _bind(widget.collaboration);
  }

  @override
  void didUpdateWidget(covariant AgentWorkbenchSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collaboration != widget.collaboration) {
      _bind(widget.collaboration);
    }
  }

  void _bind(AgentCollaborationService? collaboration) {
    unawaited(_projectionSubscription?.cancel());
    _projectionSubscription = null;
    _projection = collaboration?.projection;
    final ids = _projection?.orderedSessionIds ?? const <String>[];
    if (_selectedSessionId == null || !ids.contains(_selectedSessionId)) {
      _selectedSessionId = ids.isEmpty ? null : ids.first;
    }
    _projectionSubscription = collaboration?.changes.listen((projection) {
      if (!mounted || widget.collaboration != collaboration) {
        return;
      }
      setState(() {
        _projection = projection;
        final ordered = projection.orderedSessionIds;
        if (_selectedSessionId == null ||
            !ordered.contains(_selectedSessionId)) {
          _selectedSessionId = ordered.isEmpty ? null : ordered.first;
        }
      });
    });
  }

  @override
  void dispose() {
    unawaited(_projectionSubscription?.cancel());
    _projectionSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final collaboration = widget.collaboration;
    final projection = _projection;
    if (collaboration == null || projection == null) {
      return const Center(
        key: ValueKey<String>('agent-workbench-surface'),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No Agent is connected. The IDE remains fully operable without '
            'model providers or coding-loop ownership.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final selectedId = _selectedSessionId;
    final selectedSession = selectedId == null
        ? null
        : projection.sessions[selectedId];
    final pendingReviews =
        selectedSession?.changeReviews.values
            .where(
              (review) => review.outcome == WorkspaceTransactionOutcome.ready,
            )
            .toList(growable: false) ??
        const <AgentChangeReviewProjection>[];
    final pendingReview = pendingReviews.isEmpty ? null : pendingReviews.first;

    return Row(
      key: const ValueKey<String>('agent-workbench-surface'),
      children: <Widget>[
        SizedBox(
          width: 280,
          child: AgentTaskCenter(
            projection: projection,
            selectedSessionId: selectedId,
            onSelectSession: (sessionId) {
              setState(() => _selectedSessionId = sessionId);
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selectedSession == null
              ? const Center(child: Text('Select an Agent session.'))
              : pendingReview != null
              ? AgentChangeReviewView(
                  review: pendingReview,
                  onDecision: (decision) => collaboration.resolveChange(
                    sessionId: selectedSession.sessionId,
                    changeSetId: pendingReview.changeSet.id,
                    decision: decision,
                  ),
                )
              : AgentSessionView(
                  session: selectedSession,
                  commands: collaboration,
                ),
        ),
      ],
    );
  }
}
