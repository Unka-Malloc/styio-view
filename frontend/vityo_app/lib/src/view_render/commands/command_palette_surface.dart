import 'package:flutter/material.dart';

import '../../view_ide/commands/commands.dart';
import '../platform/viewport_profile.dart';

class CommandPaletteSurface extends StatefulWidget {
  const CommandPaletteSurface({
    super.key,
    required this.viewportProfile,
    this.commands = StyioCommandRegistry.commands,
    this.onExecuteCommand,
    this.blockedReasonForCommand,
  });

  final ViewportProfile viewportProfile;
  final List<AppCommandDescriptor> commands;
  final Future<void> Function(AppCommandId commandId)? onExecuteCommand;
  final String? Function(AppCommandId commandId)? blockedReasonForCommand;

  @override
  State<CommandPaletteSurface> createState() => _CommandPaletteSurfaceState();
}

class _CommandPaletteSurfaceState extends State<CommandPaletteSurface> {
  late final TextEditingController _queryController;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final normalizedQuery = _query.trim().toLowerCase();
    final visibleCommands = normalizedQuery.isEmpty
        ? widget.commands
        : widget.commands
              .where(
                (command) =>
                    command.label.toLowerCase().contains(normalizedQuery) ||
                    command.id.name.toLowerCase().contains(normalizedQuery) ||
                    command.description.toLowerCase().contains(normalizedQuery),
              )
              .toList(growable: false);

    return Card(
      key: const ValueKey('command-palette-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Command Palette', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Searchable command registry surface. TODO: promote this panel to an overlay palette with typed command inputs and recent command ranking.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('command-palette-query-input'),
              controller: _queryController,
              decoration: const InputDecoration(
                labelText: 'Search commands',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('registered ${widget.commands.length}')),
                Chip(label: Text('visible ${visibleCommands.length}')),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('command-palette-command-list'),
                itemCount: visibleCommands.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final command = visibleCommands[index];
                  final blockedReason = widget.blockedReasonForCommand?.call(
                    command.id,
                  );
                  return ListTile(
                    key: ValueKey('command-palette-${command.id.name}'),
                    dense: true,
                    title: Text(command.label),
                    subtitle: Text(command.description),
                    leading: const Icon(Icons.keyboard_command_key_rounded),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        Chip(label: Text(command.shortcutHint)),
                        if (command.requiresInput)
                          Chip(label: Text('input ${command.inputLabel}')),
                        if (blockedReason != null)
                          const Chip(label: Text('blocked')),
                      ],
                    ),
                    enabled:
                        widget.onExecuteCommand != null &&
                        blockedReason == null,
                    onTap:
                        widget.onExecuteCommand == null || blockedReason != null
                        ? null
                        : () {
                            widget.onExecuteCommand!(command.id);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
