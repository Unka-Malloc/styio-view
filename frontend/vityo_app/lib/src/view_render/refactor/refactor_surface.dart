import 'package:flutter/material.dart';

import '../../view_ide/commands/commands.dart';
import '../../view_ide/language/semantic_snapshot_panel.dart';
import '../platform/viewport_profile.dart';

class RefactorSurface extends StatelessWidget {
  const RefactorSurface({
    super.key,
    required this.viewportProfile,
    this.semanticSnapshotPanelViewModel,
    this.refactorCommands,
    this.onExecuteCommand,
  });

  final ViewportProfile viewportProfile;
  final SemanticSnapshotPanelViewModel? semanticSnapshotPanelViewModel;
  final List<AppCommandDescriptor>? refactorCommands;
  final Future<void> Function(AppCommandId commandId)? onExecuteCommand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final commands =
        refactorCommands ??
        StyioCommandRegistry.refactorCommands.toList(growable: false);
    final viewModel = semanticSnapshotPanelViewModel;

    return Card(
      key: const ValueKey('refactor-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Refactor', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Refactor surface for safe IDE commands and semantic rename-safety telemetry. TODO: bind to a dedicated shell tab once layout ownership is finalized.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Chip(label: Text('commands ${commands.length}')),
                  if (viewModel != null)
                    Chip(label: Text('events ${viewModel.itemCount}')),
                  if (viewModel != null)
                    Chip(
                      label: Text(
                        'rename-safety ${viewModel.renameSafetyCount}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Registered refactors', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final command in commands)
                ListTile(
                  key: ValueKey('refactor-command-${command.id.name}'),
                  dense: true,
                  leading: const Icon(Icons.transform_rounded),
                  title: Text(command.label),
                  subtitle: Text(command.description),
                  trailing: command.requiresInput
                      ? Chip(label: Text('input ${command.inputLabel}'))
                      : null,
                  onTap: onExecuteCommand == null
                      ? null
                      : () {
                          onExecuteCommand!(command.id);
                        },
                ),
              if (viewModel != null) ...[
                const SizedBox(height: 12),
                _RefactorSemanticPanel(viewModel: viewModel),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RefactorSemanticPanel extends StatelessWidget {
  const _RefactorSemanticPanel({required this.viewModel});

  final SemanticSnapshotPanelViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('refactor-semantic-snapshot-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Semantic ${viewModel.title}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              Chip(label: Text('revision ${viewModel.revision}')),
              Chip(label: Text('items ${viewModel.itemCount}')),
              Chip(label: Text('rename-safety ${viewModel.renameSafetyCount}')),
            ],
          ),
          const SizedBox(height: 8),
          if (viewModel.empty)
            Text(
              'No refactor semantic events recorded.',
              style: theme.textTheme.bodySmall,
            )
          else
            for (final item in viewModel.items.take(5))
              ListTile(
                key: ValueKey('refactor-semantic-event-${item.id}'),
                dense: true,
                leading: Icon(
                  item.severity == 'warning'
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                ),
                title: Text(
                  item.actionLabel.isEmpty ? item.title : item.actionLabel,
                ),
                subtitle: Text(
                  '${item.documentId} · ${item.kind.wireValue} · ${item.message}',
                ),
              ),
        ],
      ),
    );
  }
}
