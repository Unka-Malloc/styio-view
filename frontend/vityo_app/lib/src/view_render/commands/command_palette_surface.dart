import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../view_ide/commands/commands.dart';
import '../platform/viewport_profile.dart';

class CommandPaletteSurface extends StatefulWidget {
  const CommandPaletteSurface({
    super.key,
    required this.viewportProfile,
    this.commands = StyioCommandRegistry.commands,
    this.recentHistory,
    this.initialCategory,
    this.onExecuteCommand,
    this.onRecordRecentCommand,
    this.blockedReasonForCommand,
  });

  final ViewportProfile viewportProfile;
  final List<AppCommandDescriptor> commands;
  final CommandPaletteRecentCommandHistory? recentHistory;
  final AppCommandCategory? initialCategory;
  final Future<void> Function(AppCommandId commandId)? onExecuteCommand;
  final Future<void> Function(AppCommandId commandId)? onRecordRecentCommand;
  final String? Function(AppCommandId commandId)? blockedReasonForCommand;

  @override
  State<CommandPaletteSurface> createState() => _CommandPaletteSurfaceState();
}

class _CommandPaletteSurfaceState extends State<CommandPaletteSurface> {
  late final TextEditingController _queryController;
  var _query = '';
  AppCommandCategory? _category;
  var _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _category = widget.initialCategory;
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
    final overlayState = CommandPaletteModel(commands: widget.commands)
        .overlayStateFor(
          CommandPaletteQueryState(
            query: _query,
            category: _category,
            recentCommandIds:
                widget.recentHistory?.commandIds ?? const <AppCommandId>[],
          ),
          selectedIndex: _selectedIndex,
        );
    final visibleEntries = overlayState.entries;
    final seenCategories = <AppCommandCategory>{};
    final categories = <AppCommandCategory>[
      for (final command in widget.commands)
        if (seenCategories.add(command.category)) command.category,
    ];

    return Focus(
      key: const ValueKey('command-palette-keyboard-focus'),
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveSelection(overlayState, 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveSelection(overlayState, -1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          _executeSelected(overlayState);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        key: const ValueKey('command-palette-surface'),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Command Palette', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Searchable command registry surface backed by reusable query scoring, overlay selection state, persisted recent command ranking, category filters, keyboard navigation, and typed input draft contracts. TODO: persist palette display preferences.',
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
                    _selectedIndex = 0;
                  });
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  Chip(label: Text('registered ${widget.commands.length}')),
                  Chip(label: Text('visible ${overlayState.visibleCount}')),
                  if (widget.recentHistory != null)
                    Chip(
                      label: Text(
                        'recent ${widget.recentHistory!.commandIds.length}',
                      ),
                    ),
                  if (_category != null)
                    Chip(label: Text('category ${_category!.wireValue}')),
                  if (overlayState.selectedEntry != null)
                    Chip(
                      key: const ValueKey('command-palette-selected-chip'),
                      label: Text(
                        'selected ${overlayState.selectedEntry!.command.label}',
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                key: const ValueKey('command-palette-category-filters'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    key: const ValueKey('command-palette-category-all'),
                    label: const Text('all'),
                    selected: _category == null,
                    onSelected: (_) {
                      setState(() {
                        _category = null;
                        _selectedIndex = 0;
                      });
                    },
                  ),
                  for (final category in categories)
                    FilterChip(
                      key: ValueKey(
                        'command-palette-category-${category.wireValue}',
                      ),
                      label: Text(category.wireValue),
                      selected: _category == category,
                      onSelected: (_) {
                        setState(() {
                          _category = category;
                          _selectedIndex = 0;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: visibleEntries.isEmpty
                    ? Center(
                        key: const ValueKey('command-palette-empty-state'),
                        child: Text(
                          _query.trim().isEmpty
                              ? 'No commands registered.'
                              : 'No commands match "$_query".',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        key: const ValueKey('command-palette-command-list'),
                        itemCount: visibleEntries.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final entry = visibleEntries[index];
                          final command = entry.command;
                          final blockedReason = widget.blockedReasonForCommand
                              ?.call(command.id);
                          final selected = index == overlayState.selectedIndex;
                          return ListTile(
                            key: ValueKey('command-palette-${command.id.name}'),
                            selected: selected,
                            dense: true,
                            title: Text(command.label),
                            subtitle: Text(
                              blockedReason == null
                                  ? command.description
                                  : '${command.description}\nBlocked: $blockedReason',
                            ),
                            leading: const Icon(
                              Icons.keyboard_command_key_rounded,
                            ),
                            trailing: Wrap(
                              spacing: 8,
                              children: [
                                Chip(label: Text(command.category.wireValue)),
                                Chip(label: Text(command.shortcutHint)),
                                if (entry.recent)
                                  Chip(
                                    label: Text('recent ${entry.recentRank}'),
                                  ),
                                if (command.requiresInput)
                                  Chip(
                                    label: Text('input ${command.inputLabel}'),
                                  ),
                                if (blockedReason != null)
                                  const Chip(label: Text('blocked')),
                              ],
                            ),
                            enabled:
                                widget.onExecuteCommand != null &&
                                blockedReason == null,
                            onTap:
                                widget.onExecuteCommand == null ||
                                    blockedReason != null
                                ? null
                                : () {
                                    _executeCommand(command.id);
                                  },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _moveSelection(CommandPaletteOverlayState overlayState, int delta) {
    if (overlayState.entries.isEmpty) {
      return;
    }
    setState(() {
      _selectedIndex = overlayState.moveSelection(delta).selectedIndex;
    });
  }

  void _executeSelected(CommandPaletteOverlayState overlayState) {
    final entry = overlayState.selectedEntry;
    if (entry == null || widget.onExecuteCommand == null) {
      return;
    }
    final commandId = entry.command.id;
    if (widget.blockedReasonForCommand?.call(commandId) != null) {
      return;
    }
    _executeCommand(commandId);
  }

  void _executeCommand(AppCommandId commandId) {
    if (widget.onExecuteCommand == null) {
      return;
    }
    if (widget.onRecordRecentCommand != null) {
      unawaited(widget.onRecordRecentCommand!(commandId));
    }
    unawaited(widget.onExecuteCommand!(commandId));
  }
}
