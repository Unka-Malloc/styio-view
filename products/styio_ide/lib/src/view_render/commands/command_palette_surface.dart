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
    this.displayPreferences,
    this.livePreferenceController,
    this.initialCategory,
    this.onExecuteCommand,
    this.onExecuteCommandWithInput,
    this.onRecordRecentCommand,
    this.blockedReasonForCommand,
    this.keybindingProfile,
    this.keybindingConflictReview,
    this.onSaveKeybindingOverride,
    this.onClearKeybindingOverride,
  });

  final ViewportProfile viewportProfile;
  final List<AppCommandDescriptor> commands;
  final CommandPaletteRecentCommandHistory? recentHistory;
  final CommandPaletteDisplayPreferences? displayPreferences;
  final CommandPaletteLivePreferenceController? livePreferenceController;
  final AppCommandCategory? initialCategory;
  final Future<void> Function(AppCommandId commandId)? onExecuteCommand;
  final Future<void> Function(AppCommandId commandId, String input)?
  onExecuteCommandWithInput;
  final Future<void> Function(AppCommandId commandId)? onRecordRecentCommand;
  final String? Function(AppCommandId commandId)? blockedReasonForCommand;
  final CommandKeybindingProfile? keybindingProfile;
  final CommandKeybindingConflictReview? keybindingConflictReview;
  final Future<void> Function(CommandKeybindingOverride override)?
  onSaveKeybindingOverride;
  final Future<void> Function(AppCommandId commandId)?
  onClearKeybindingOverride;

  @override
  State<CommandPaletteSurface> createState() => _CommandPaletteSurfaceState();
}

class _CommandPaletteSurfaceState extends State<CommandPaletteSurface> {
  late final TextEditingController _queryController;
  late final TextEditingController _commandInputController;
  late final TextEditingController _keybindingController;
  StreamSubscription<CommandPaletteLivePreferenceState>?
  _livePreferenceSubscription;
  CommandPaletteDisplayPreferences? _liveDisplayPreferences;
  var _query = '';
  AppCommandCategory? _category;
  var _selectedIndex = 0;
  AppCommandId? _keybindingCommand;
  CommandShortcutCapturePolicyResult _keybindingCapturePolicyResult =
      const CommandShortcutCapturePolicy().evaluate(null);

  CommandShortcutCapturePolicy get _shortcutCapturePolicy {
    return CommandShortcutCapturePolicy.forPlatform(
      widget.viewportProfile.platformTarget,
    );
  }

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _commandInputController = TextEditingController();
    _keybindingController = TextEditingController();
    _attachLivePreferenceController(widget.livePreferenceController);
    _category =
        widget.initialCategory ?? _effectivePreferences?.defaultCategory;
    _keybindingCommand = widget.commands.isEmpty
        ? null
        : widget.commands.first.id;
    _syncKeybindingDraft();
  }

  @override
  void didUpdateWidget(CommandPaletteSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.livePreferenceController != widget.livePreferenceController) {
      _livePreferenceSubscription?.cancel();
      _attachLivePreferenceController(widget.livePreferenceController);
      _category =
          widget.initialCategory ?? _effectivePreferences?.defaultCategory;
      _selectedIndex = 0;
    }
    _syncCommandInputDraft();
    final commandStillRegistered = widget.commands.any(
      (command) => command.id == _keybindingCommand,
    );
    if (!commandStillRegistered) {
      _keybindingCommand = widget.commands.isEmpty
          ? null
          : widget.commands.first.id;
      _syncKeybindingDraft();
    } else if (oldWidget.keybindingProfile != widget.keybindingProfile) {
      _syncKeybindingDraft();
    }
  }

  @override
  void dispose() {
    _livePreferenceSubscription?.cancel();
    _keybindingController.dispose();
    _commandInputController.dispose();
    _queryController.dispose();
    super.dispose();
  }

  CommandPaletteDisplayPreferences? get _effectivePreferences {
    return _liveDisplayPreferences ?? widget.displayPreferences;
  }

  void _attachLivePreferenceController(
    CommandPaletteLivePreferenceController? controller,
  ) {
    _liveDisplayPreferences = controller?.state.preferences;
    _livePreferenceSubscription = controller?.stream.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _liveDisplayPreferences = state.preferences;
        _category = widget.initialCategory ?? state.preferences.defaultCategory;
        _selectedIndex = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final displayPreferences = _effectivePreferences;
    final showRecentCommands = displayPreferences?.showRecentCommands ?? true;
    final showCategoryFilters = displayPreferences?.showCategoryFilters ?? true;
    final overlayState = CommandPaletteModel(commands: widget.commands)
        .overlayStateFor(
          CommandPaletteQueryState(
            query: _query,
            category: _category,
            recentCommandIds: showRecentCommands
                ? widget.recentHistory?.commandIds ?? const <AppCommandId>[]
                : const <AppCommandId>[],
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
          child: ListView(
            key: const ValueKey('command-palette-content-scroll'),
            children: [
              Text('Command Palette', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Searchable command registry surface backed by reusable query scoring, overlay selection state, persisted recent command ranking, display preferences, category filters, keyboard navigation, and typed input dispatch contracts.',
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
                  if (widget.recentHistory != null && showRecentCommands)
                    Chip(
                      label: Text(
                        'recent ${widget.recentHistory!.commandIds.length}',
                      ),
                    ),
                  if (displayPreferences != null)
                    const Chip(label: Text('preferences workspace')),
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
              if (showCategoryFilters) ...[
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
              ],
              if (overlayState.selectedEntry?.command.requiresInput ??
                  false) ...[
                TextField(
                  key: const ValueKey('command-palette-command-input'),
                  controller: _commandInputController,
                  decoration: InputDecoration(
                    labelText:
                        overlayState.selectedEntry!.command.inputLabel.isEmpty
                        ? 'Command input'
                        : overlayState.selectedEntry!.command.inputLabel,
                    helperText:
                        overlayState
                            .selectedEntry!
                            .command
                            .inputContract
                            .isEmpty
                        ? 'Input is passed to the command router, for example a workspace file path.'
                        : overlayState.selectedEntry!.command.inputContract,
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (overlayState
                    .selectedEntry!
                    .command
                    .inputExamples
                    .isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Examples: ${overlayState.selectedEntry!.command.inputExamples.join(', ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (_showsKeybindingEditor) ...[
                SizedBox(
                  height: compact ? 190 : 220,
                  child: _buildKeybindingEditor(theme),
                ),
                const SizedBox(height: 12),
              ],
              if (visibleEntries.isEmpty)
                SizedBox(
                  height: 96,
                  child: Center(
                    key: const ValueKey('command-palette-empty-state'),
                    child: Text(
                      _query.trim().isEmpty
                          ? 'No commands registered.'
                          : 'No commands match "$_query".',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                )
              else
                ListView.separated(
                  key: const ValueKey('command-palette-command-list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: visibleEntries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = visibleEntries[index];
                    final command = entry.command;
                    final blockedReason = widget.blockedReasonForCommand?.call(
                      command.id,
                    );
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
                      leading: const Icon(Icons.keyboard_command_key_rounded),
                      trailing: compact
                          ? null
                          : Wrap(
                              spacing: 8,
                              children: [
                                Chip(label: Text(command.category.wireValue)),
                                Chip(label: Text(_shortcutHintFor(command))),
                                if (widget.keybindingProfile?.hasOverrideFor(
                                      command.id,
                                    ) ??
                                    false)
                                  const Chip(label: Text('override')),
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
                          _canExecuteCommand(command.id) &&
                          blockedReason == null,
                      onTap:
                          !_canExecuteCommand(command.id) ||
                              blockedReason != null
                          ? null
                          : () {
                              _executeCommand(command.id);
                            },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _showsKeybindingEditor {
    return widget.keybindingProfile != null ||
        widget.keybindingConflictReview != null ||
        widget.onSaveKeybindingOverride != null ||
        widget.onClearKeybindingOverride != null;
  }

  Widget _buildKeybindingEditor(ThemeData theme) {
    final selectedDescriptor = _descriptorFor(_keybindingCommand);
    final profile = widget.keybindingProfile;
    final conflictReview =
        widget.keybindingConflictReview ??
        (profile == null
            ? const CommandKeybindingConflictReview()
            : CommandKeybindingResolver.reviewConflicts(
                profile: profile,
                descriptors: widget.commands,
              ));
    final hasSelectedOverride =
        selectedDescriptor != null &&
        (profile?.hasOverrideFor(selectedDescriptor.id) ?? false);
    final parsedShortcut = parseCommandShortcutExpression(
      _keybindingController.text,
    );
    final policyResult =
        _sameShortcut(_keybindingCapturePolicyResult.shortcut, parsedShortcut)
        ? _keybindingCapturePolicyResult
        : _shortcutCapturePolicy.evaluate(parsedShortcut);
    return Container(
      key: const ValueKey('command-palette-keybinding-editor'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Keybinding overrides', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Workspace-level shortcut remap draft. Focus the shortcut field and press the physical key combination to capture it. Reserved shortcuts are blocked before they reach persistence.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AppCommandId>(
              key: const ValueKey('command-palette-keybinding-command'),
              initialValue: _keybindingCommand,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Command',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final command in widget.commands)
                  DropdownMenuItem<AppCommandId>(
                    value: command.id,
                    child: Text(command.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (commandId) {
                setState(() {
                  _keybindingCommand = commandId;
                  _syncKeybindingDraft();
                });
              },
            ),
            const SizedBox(height: 8),
            Focus(
              key: const ValueKey(
                'command-palette-keybinding-shortcut-capture',
              ),
              onKeyEvent: _captureKeybindingShortcut,
              child: TextField(
                key: const ValueKey(
                  'command-palette-keybinding-shortcut-input',
                ),
                controller: _keybindingController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Captured shortcut',
                  helperText:
                      'Focus this field and press a key combination. Physical keys are captured for layout-stable shortcuts.',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('command-palette-keybinding-capture-policy'),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: policyResult.allowed
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : theme.colorScheme.errorContainer.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${policyResult.message} ${policyResult.accessibilityHint}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('command-palette-keybinding-save'),
                  onPressed:
                      selectedDescriptor == null ||
                          widget.onSaveKeybindingOverride == null ||
                          !policyResult.allowed
                      ? null
                      : _saveKeybindingOverride,
                  child: const Text('Save override'),
                ),
                OutlinedButton(
                  key: const ValueKey('command-palette-keybinding-clear'),
                  onPressed:
                      selectedDescriptor == null ||
                          widget.onClearKeybindingOverride == null ||
                          !hasSelectedOverride
                      ? null
                      : _clearKeybindingOverride,
                  child: const Text('Clear override'),
                ),
                if (conflictReview.hasConflicts)
                  Chip(
                    key: const ValueKey(
                      'command-palette-keybinding-conflict-chip',
                    ),
                    label: Text('conflicts ${conflictReview.conflicts.length}'),
                  )
                else
                  const Chip(label: Text('conflicts 0')),
                if (hasSelectedOverride)
                  const Chip(
                    key: ValueKey(
                      'command-palette-keybinding-selected-override',
                    ),
                    label: Text('selected override'),
                  ),
              ],
            ),
            if (conflictReview.hasConflicts) ...[
              const SizedBox(height: 8),
              for (final conflict in conflictReview.conflicts)
                _buildConflictRow(conflict),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConflictRow(CommandKeybindingConflict conflict) {
    final profile = widget.keybindingProfile;
    return Padding(
      key: ValueKey(
        'command-palette-keybinding-conflict-${conflict.signature}',
      ),
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Chip(label: Text(conflict.signature)),
          if (conflict.shortcutLabel.isNotEmpty)
            Chip(label: Text('shortcut ${conflict.shortcutLabel}')),
          Text(
            conflict.commandIds.map((commandId) => commandId.name).join(', '),
          ),
          for (final preview in conflict.commandPreviews)
            Chip(
              key: ValueKey(
                'command-palette-keybinding-conflict-detail-${preview.commandId.name}',
              ),
              label: Text(
                '${preview.label} · ${preview.category.wireValue} · ${preview.sourceLabel}',
              ),
            ),
          for (final commandId in conflict.commandIds)
            TextButton(
              key: ValueKey(
                'command-palette-keybinding-edit-conflict-${commandId.name}',
              ),
              onPressed: () {
                setState(() {
                  _keybindingCommand = commandId;
                  _keybindingController.text = conflict.signature;
                });
              },
              child: Text('Edit ${commandId.name}'),
            ),
          for (final commandId in conflict.commandIds)
            if ((profile?.hasOverrideFor(commandId) ?? false) &&
                widget.onClearKeybindingOverride != null)
              TextButton(
                key: ValueKey(
                  'command-palette-keybinding-clear-conflict-${commandId.name}',
                ),
                onPressed: () {
                  unawaited(widget.onClearKeybindingOverride!(commandId));
                },
                child: Text('Clear ${commandId.name}'),
              ),
        ],
      ),
    );
  }

  void _moveSelection(CommandPaletteOverlayState overlayState, int delta) {
    if (overlayState.entries.isEmpty) {
      return;
    }
    setState(() {
      _selectedIndex = overlayState.moveSelection(delta).selectedIndex;
      _syncCommandInputDraft();
    });
  }

  void _executeSelected(CommandPaletteOverlayState overlayState) {
    final entry = overlayState.selectedEntry;
    if (entry == null || !_canExecuteCommand(entry.command.id)) {
      return;
    }
    final commandId = entry.command.id;
    if (widget.blockedReasonForCommand?.call(commandId) != null) {
      return;
    }
    _executeCommand(commandId);
  }

  void _executeCommand(AppCommandId commandId) {
    final descriptor = _descriptorFor(commandId);
    if (descriptor?.requiresInput ?? false) {
      final input = _commandInputController.text.trim();
      if (widget.onRecordRecentCommand != null) {
        unawaited(widget.onRecordRecentCommand!(commandId));
      }
      if (widget.onExecuteCommandWithInput != null) {
        unawaited(widget.onExecuteCommandWithInput!(commandId, input));
        return;
      }
    }
    if (widget.onExecuteCommand == null) {
      return;
    }
    if (widget.onRecordRecentCommand != null) {
      unawaited(widget.onRecordRecentCommand!(commandId));
    }
    unawaited(widget.onExecuteCommand!(commandId));
  }

  bool _canExecuteCommand(AppCommandId commandId) {
    final descriptor = _descriptorFor(commandId);
    if (descriptor?.requiresInput ?? false) {
      return widget.onExecuteCommandWithInput != null ||
          widget.onExecuteCommand != null;
    }
    return widget.onExecuteCommand != null;
  }

  void _saveKeybindingOverride() {
    final commandId = _keybindingCommand;
    if (commandId == null || widget.onSaveKeybindingOverride == null) {
      return;
    }
    final shortcut = parseCommandShortcutExpression(_keybindingController.text);
    if (shortcut == null) {
      return;
    }
    final policyResult = _shortcutCapturePolicy.evaluate(shortcut);
    if (!policyResult.allowed) {
      setState(() {
        _keybindingCapturePolicyResult = policyResult;
      });
      return;
    }
    unawaited(
      widget.onSaveKeybindingOverride!(
        CommandKeybindingOverride(
          commandId: commandId,
          shortcuts: <AppCommandShortcutSpec>[shortcut],
        ),
      ),
    );
  }

  KeyEventResult _captureKeybindingShortcut(FocusNode node, KeyEvent event) {
    final shortcut = _shortcutFromPhysicalKeyEvent(event);
    if (shortcut == null) {
      return KeyEventResult.ignored;
    }
    final policyResult = _shortcutCapturePolicy.evaluate(shortcut);
    setState(() {
      _keybindingController.text = commandShortcutSignature(shortcut);
      _keybindingCapturePolicyResult = policyResult;
    });
    return KeyEventResult.handled;
  }

  AppCommandShortcutSpec? _shortcutFromPhysicalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || _isShortcutModifierOnly(event.logicalKey)) {
      return null;
    }
    final keyToken = _shortcutKeyTokenFor(event);
    if (keyToken.isEmpty) {
      return null;
    }
    final keyboard = HardwareKeyboard.instance;
    return AppCommandShortcutSpec(
      keyToken,
      control: keyboard.isControlPressed,
      meta: keyboard.isMetaPressed,
      shift: keyboard.isShiftPressed,
    );
  }

  bool _isShortcutModifierOnly(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight ||
        key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight;
  }

  String _shortcutKeyTokenFor(KeyEvent event) {
    final physicalName = event.physicalKey.debugName;
    if (physicalName != null && physicalName.trim().isNotEmpty) {
      final compact = physicalName.trim().replaceAll(' ', '');
      return '${compact[0].toLowerCase()}${compact.substring(1)}';
    }
    final label = event.logicalKey.keyLabel.trim();
    if (label.length == 1) {
      return 'key${label.toUpperCase()}';
    }
    final logicalName = event.logicalKey.debugName ?? '';
    final compact = logicalName.trim().replaceAll(' ', '');
    if (compact.isEmpty) {
      return '';
    }
    return '${compact[0].toLowerCase()}${compact.substring(1)}';
  }

  void _clearKeybindingOverride() {
    final commandId = _keybindingCommand;
    if (commandId == null || widget.onClearKeybindingOverride == null) {
      return;
    }
    unawaited(widget.onClearKeybindingOverride!(commandId));
  }

  void _syncKeybindingDraft() {
    final descriptor = _descriptorFor(_keybindingCommand);
    if (descriptor == null) {
      _keybindingController.text = '';
      return;
    }
    final shortcuts =
        widget.keybindingProfile?.effectiveShortcutsFor(descriptor) ??
        descriptor.shortcuts;
    final shortcut = shortcuts.isEmpty ? null : shortcuts.first;
    _keybindingController.text = shortcut == null
        ? ''
        : commandShortcutDisplayLabel(shortcut);
    _keybindingCapturePolicyResult = const CommandShortcutCapturePolicy()
        .evaluate(shortcut);
  }

  void _syncCommandInputDraft() {
    _commandInputController.text = '';
  }

  String _shortcutHintFor(AppCommandDescriptor descriptor) {
    final shortcuts =
        widget.keybindingProfile?.effectiveShortcutsFor(descriptor) ??
        descriptor.shortcuts;
    if (shortcuts.isEmpty) {
      return descriptor.shortcutHint;
    }
    return shortcuts.map(commandShortcutDisplayLabel).join(' / ');
  }

  AppCommandDescriptor? _descriptorFor(AppCommandId? commandId) {
    if (commandId == null) {
      return null;
    }
    for (final command in widget.commands) {
      if (command.id == commandId) {
        return command;
      }
    }
    return null;
  }

  bool _sameShortcut(
    AppCommandShortcutSpec? left,
    AppCommandShortcutSpec? right,
  ) {
    if (left == null || right == null) {
      return left == right;
    }
    return commandShortcutSignature(left) == commandShortcutSignature(right);
  }
}
