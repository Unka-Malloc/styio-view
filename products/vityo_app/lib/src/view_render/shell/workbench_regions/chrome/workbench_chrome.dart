import 'package:flutter/material.dart';

import '../../../theme/vityo_theme.dart';

class WorkbenchTitleBar extends StatelessWidget {
  const WorkbenchTitleBar({
    required this.title,
    required this.commandHint,
    required this.connectionLabel,
    required this.onOpenCommands,
    this.actions = const <Widget>[],
    this.status = WorkbenchStatus.ready,
    super.key,
  });

  final String title;
  final String commandHint;
  final String connectionLabel;
  final VoidCallback onOpenCommands;
  final List<Widget> actions;
  final WorkbenchStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = VityoWorkbenchTokens.of(context);
    return Semantics(
      container: true,
      label: 'Workbench title and command strip',
      child: Container(
        key: const ValueKey('workbench-title-bar'),
        height: 38,
        decoration: BoxDecoration(
          color: tokens.region,
          border: Border(bottom: BorderSide(color: tokens.divider)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            final visibleActionCount = constraints.maxWidth >= 1180
                ? actions.length
                : constraints.maxWidth >= 840
                ? actions.length.clamp(0, 2)
                : 0;
            final visibleActions = actions.take(visibleActionCount);
            final statusColor = switch (status) {
              WorkbenchStatus.ready => tokens.success,
              WorkbenchStatus.reconnecting => tokens.warning,
              WorkbenchStatus.blocked => tokens.blocked,
              WorkbenchStatus.error => tokens.error,
            };
            return Row(
              children: [
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? 52 : 220),
                  child: Text(
                    compact ? 'Vityo' : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Align(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Semantics(
                        button: true,
                        label: 'Open command palette',
                        child: InkWell(
                          onTap: onOpenCommands,
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: tokens.canvas,
                              border: Border.all(color: tokens.divider),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              commandHint,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ...visibleActions,
                if (visibleActionCount > 0) const SizedBox(width: 8),
                if (compact)
                  Tooltip(
                    message: connectionLabel,
                    child: Icon(Icons.circle, size: 10, color: statusColor),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      connectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(width: 12),
              ],
            );
          },
        ),
      ),
    );
  }
}

class WorkbenchStatusBar extends StatelessWidget {
  const WorkbenchStatusBar({
    required this.leading,
    required this.trailing,
    this.status = WorkbenchStatus.ready,
    super.key,
  });

  final String leading;
  final String trailing;
  final WorkbenchStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = VityoWorkbenchTokens.of(context);
    final statusColor = switch (status) {
      WorkbenchStatus.ready => tokens.success,
      WorkbenchStatus.reconnecting => tokens.warning,
      WorkbenchStatus.blocked => tokens.blocked,
      WorkbenchStatus.error => tokens.error,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      label: 'Workbench status ${status.name}: $leading, $trailing',
      child: Container(
        key: const ValueKey('workbench-status-bar'),
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        color: statusColor,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                leading,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Text(
                trailing,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum WorkbenchStatus { ready, reconnecting, blocked, error }
