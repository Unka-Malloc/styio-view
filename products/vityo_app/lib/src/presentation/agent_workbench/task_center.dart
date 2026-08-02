import 'package:flutter/material.dart';

import '../../ide/workbench/agent_collaboration/agent_collaboration_service.dart';
import 'agent_workbench_surface.dart';

export 'task_session_list.dart' show AgentTaskCenter;

/// Canonical module presentation entry for `agent.surface.basic`.
final class TaskCenter extends StatelessWidget {
  const TaskCenter({
    required this.collaboration,
    super.key,
  });

  final AgentCollaborationService? collaboration;

  @override
  Widget build(BuildContext context) {
    return AgentWorkbenchSurface(collaboration: collaboration);
  }
}
