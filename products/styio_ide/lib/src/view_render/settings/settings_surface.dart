import 'package:flutter/material.dart';

import '../../view_ide/commands/commands.dart';
import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/foundation/foundation.dart';
import '../../view_ide/environment/configuration/vityo_theme_override.dart';
import '../../view_ide/toolchain/toolchain_catalog.dart';
import '../../view_ide/toolchain/toolchain_manager.dart';
import '../platform/viewport_profile.dart';
import '../theme/theme.dart';

class SettingsSurface extends StatelessWidget {
  const SettingsSurface({
    super.key,
    required this.viewportProfile,
    required this.toolchainStatus,
    this.toolchainSettings,
    this.toolchainInstallPlan,
    this.toolchainInstallExecution,
    this.toolchainBootstrapSummary,
    this.toolchainBootstrapActionDispatch,
    this.onToolchainRecoveryAction,
    this.onToolchainBootstrapAction,
    this.onSelectToolchain,
    this.onSelectClangCppVersion,
    this.onClearToolchain,
    this.onExecuteToolchainInstallPlan,
    this.ideCapabilities,
    this.commandPalettePreferences = const CommandPaletteDisplayPreferences(
      workspaceId: 'default',
    ),
    this.onSaveCommandPalettePreferences,
    this.themeOverride = const VityoThemeOverride(),
    this.onSaveThemeOverride,
  });

  final ViewportProfile viewportProfile;
  final ToolchainStatusSurface toolchainStatus;
  final ToolchainSettingsSurface? toolchainSettings;
  final ToolchainInstallPlanSurface? toolchainInstallPlan;
  final ToolchainInstallExecutionSurface? toolchainInstallExecution;
  final ToolchainManagerBootstrapSummary? toolchainBootstrapSummary;
  final ToolchainBootstrapActionDispatchResult?
  toolchainBootstrapActionDispatch;
  final Future<void> Function(ToolchainRecoveryAction action)?
  onToolchainRecoveryAction;
  final Future<void> Function(String actionId)? onToolchainBootstrapAction;
  final Future<void> Function(String id)? onSelectToolchain;
  final Future<void> Function(String versionId, String cppStandard)?
  onSelectClangCppVersion;
  final Future<void> Function(ToolchainKind kind)? onClearToolchain;
  final Future<void> Function()? onExecuteToolchainInstallPlan;
  final IdeCapabilityFrameworkSnapshot? ideCapabilities;
  final CommandPaletteDisplayPreferences commandPalettePreferences;
  final Future<void> Function(CommandPaletteDisplayPreferences preferences)?
  onSaveCommandPalettePreferences;
  final VityoThemeOverride themeOverride;
  final Future<void> Function(VityoThemeOverride override)? onSaveThemeOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final settings =
        toolchainSettings ??
        ToolchainSettingsSurface.fromStatus(toolchainStatus);
    final capabilitySnapshot =
        ideCapabilities ?? const VityoIdeCapabilityFramework().snapshot();

    return Card(
      key: const ValueKey('settings-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings Surface', style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(
                'Product settings entry backed by Vityo managers instead of ad-hoc runtime-only status.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              _ToolchainSettingsCard(
                settings: settings,
                installPlan: toolchainInstallPlan,
                installExecution: toolchainInstallExecution,
                bootstrapSummary: toolchainBootstrapSummary,
                bootstrapActionDispatch: toolchainBootstrapActionDispatch,
                onRecoveryAction: onToolchainRecoveryAction,
                onBootstrapAction: onToolchainBootstrapAction,
                onSelectToolchain: onSelectToolchain,
                onSelectClangCppVersion: onSelectClangCppVersion,
                onClearToolchain: onClearToolchain,
                onExecuteToolchainInstallPlan: onExecuteToolchainInstallPlan,
              ),
              const SizedBox(height: 14),
              _IdeCapabilityFrameworkCard(snapshot: capabilitySnapshot),
              const SizedBox(height: 14),
              _CommandPaletteSettingsCard(
                preferences: commandPalettePreferences,
                onSavePreferences: onSaveCommandPalettePreferences,
              ),
              const SizedBox(height: 14),
              _ThemeSettingsCard(
                themeOverride: themeOverride,
                onSaveThemeOverride: onSaveThemeOverride,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandPaletteSettingsCard extends StatefulWidget {
  const _CommandPaletteSettingsCard({
    required this.preferences,
    required this.onSavePreferences,
  });

  final CommandPaletteDisplayPreferences preferences;
  final Future<void> Function(CommandPaletteDisplayPreferences preferences)?
  onSavePreferences;

  @override
  State<_CommandPaletteSettingsCard> createState() =>
      _CommandPaletteSettingsCardState();
}

class _CommandPaletteSettingsCardState
    extends State<_CommandPaletteSettingsCard> {
  AppCommandCategory? _defaultCategory;
  late bool _showCategoryFilters;
  late bool _showRecentCommands;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant _CommandPaletteSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preferences != widget.preferences) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    _defaultCategory = widget.preferences.defaultCategory;
    _showCategoryFilters = widget.preferences.showCategoryFilters;
    _showRecentCommands = widget.preferences.showRecentCommands;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('settings-command-palette-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE8F1),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Command Palette Settings',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Workspace command palette display preferences. Persistence is delegated to CommandPaletteDisplayPreferencesStore.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<AppCommandCategory?>(
              key: const ValueKey('settings-command-palette-default-category'),
              initialValue: _defaultCategory,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Default category'),
              items: <DropdownMenuItem<AppCommandCategory?>>[
                const DropdownMenuItem<AppCommandCategory?>(
                  value: null,
                  child: Text(
                    'No default category',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...AppCommandCategory.values.map(
                  (category) => DropdownMenuItem<AppCommandCategory?>(
                    value: category,
                    child: Text(
                      category.wireValue,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: (category) {
                setState(() {
                  _defaultCategory = category;
                });
              },
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              key: const ValueKey('settings-command-palette-show-filters'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show category filters'),
              value: _showCategoryFilters,
              onChanged: (value) {
                setState(() {
                  _showCategoryFilters = value;
                });
              },
            ),
            SwitchListTile(
              key: const ValueKey('settings-command-palette-show-recent'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Show recent commands'),
              value: _showRecentCommands,
              onChanged: (value) {
                setState(() {
                  _showRecentCommands = value;
                });
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text('workspace ${widget.preferences.workspaceId}'),
                ),
                Chip(
                  label: Text(
                    'default ${_defaultCategory?.wireValue ?? 'none'}',
                  ),
                ),
                OutlinedButton(
                  key: const ValueKey('settings-command-palette-save'),
                  onPressed: widget.onSavePreferences == null
                      ? null
                      : () {
                          widget.onSavePreferences!(
                            CommandPaletteDisplayPreferences(
                              workspaceId: widget.preferences.workspaceId,
                              defaultCategory: _defaultCategory,
                              showCategoryFilters: _showCategoryFilters,
                              showRecentCommands: _showRecentCommands,
                              updatedAt: DateTime.now().toUtc(),
                            ),
                          );
                        },
                  child: const Text('Save command palette'),
                ),
                OutlinedButton(
                  key: const ValueKey('settings-command-palette-reset'),
                  onPressed: widget.onSavePreferences == null
                      ? null
                      : () {
                          setState(() {
                            _defaultCategory = null;
                            _showCategoryFilters = true;
                            _showRecentCommands = true;
                          });
                          widget.onSavePreferences!(
                            CommandPaletteDisplayPreferences(
                              workspaceId: widget.preferences.workspaceId,
                              updatedAt: DateTime.now().toUtc(),
                            ),
                          );
                        },
                  child: const Text('Reset command palette'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeCapabilityFrameworkCard extends StatelessWidget {
  const _IdeCapabilityFrameworkCard({required this.snapshot});

  final IdeCapabilityFrameworkSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final followUps = snapshot.followUps.take(8).toList(growable: false);
    final missingRequiredCapabilityIds = snapshot.missingRequiredCapabilityIds
        .toList(growable: false);
    final coveredRequiredCapabilityCount =
        requiredVityoIdeCapabilityIds.length -
        missingRequiredCapabilityIds.length;

    return Container(
      key: const ValueKey('settings-ide-capability-framework'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE6EEF1),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IDE Capability Framework', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Cross-layer maturity map for Vityo IDE capabilities. TODO entries are explicit follow-up work, not production-ready claims.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(label: Text('version ${snapshot.version}')),
              Chip(label: Text('entries ${snapshot.entries.length}')),
              Chip(
                label: Text(
                  'required $coveredRequiredCapabilityCount/${requiredVityoIdeCapabilityIds.length}',
                ),
              ),
              Chip(label: Text('follow-ups ${snapshot.followUps.length}')),
              for (final statusCount in snapshot.statusCounts.entries)
                Chip(label: Text('${statusCount.key} ${statusCount.value}')),
            ],
          ),
          const SizedBox(height: 12),
          Text('Layer Coverage', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: snapshot.layerCounts.entries
                .where((entry) => entry.value > 0)
                .map(
                  (entry) => Chip(label: Text('${entry.key} ${entry.value}')),
                )
                .toList(growable: false),
          ),
          if (missingRequiredCapabilityIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Missing Required Capabilities',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: missingRequiredCapabilityIds
                  .map(
                    (id) => Chip(
                      key: ValueKey('settings-ide-capability-missing-$id'),
                      label: Text(id),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Text('TODO Follow-ups', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (followUps.isEmpty)
            Text(
              'No framework follow-ups are currently recorded.',
              style: theme.textTheme.bodySmall,
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: followUps
                  .map(
                    (entry) => Padding(
                      key: ValueKey('settings-ide-capability-${entry.id}'),
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${entry.layer.wireValue} · ${entry.title} · ${entry.status.wireValue}: ${entry.todo}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _ThemeSettingsCard extends StatefulWidget {
  const _ThemeSettingsCard({
    required this.themeOverride,
    required this.onSaveThemeOverride,
  });

  final VityoThemeOverride themeOverride;
  final Future<void> Function(VityoThemeOverride override)? onSaveThemeOverride;

  @override
  State<_ThemeSettingsCard> createState() => _ThemeSettingsCardState();
}

enum _ThemeColorField { canvas, panel, ink, accent, muted }

extension _ThemeColorFieldX on _ThemeColorField {
  String get label => switch (this) {
    _ThemeColorField.canvas => 'Canvas',
    _ThemeColorField.panel => 'Panel',
    _ThemeColorField.ink => 'Ink',
    _ThemeColorField.accent => 'Accent',
    _ThemeColorField.muted => 'Muted',
  };

  String get hint => switch (this) {
    _ThemeColorField.canvas => '#F7F4EB',
    _ThemeColorField.panel => '#FFFDF5',
    _ThemeColorField.ink => '#2D2416',
    _ThemeColorField.accent => '#C7522A',
    _ThemeColorField.muted => '#A09880',
  };

  String get keyName => switch (this) {
    _ThemeColorField.canvas => 'canvas',
    _ThemeColorField.panel => 'panel',
    _ThemeColorField.ink => 'ink',
    _ThemeColorField.accent => 'accent',
    _ThemeColorField.muted => 'muted',
  };
}

class _ThemeSettingsCardState extends State<_ThemeSettingsCard> {
  late final Map<_ThemeColorField, TextEditingController> _controllers;
  late VityoThemePreset _previewPreset;

  @override
  void initState() {
    super.initState();
    _previewPreset = VityoThemePreset.parchment;
    _controllers = {
      for (final field in _ThemeColorField.values)
        field: TextEditingController(
          text: _colorToHex(_overrideColor(field, widget.themeOverride)),
        ),
    };
  }

  @override
  void didUpdateWidget(covariant _ThemeSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final field in _ThemeColorField.values) {
      final controller = _controllers[field]!;
      final nextText = _colorToHex(_overrideColor(field, widget.themeOverride));
      if (controller.text != nextText) {
        controller.text = nextText;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draftOverride = _draftOverride();
    final previewTheme = VityoTheme.light(
      preset: _previewPreset,
      overrides: draftOverride,
    );
    return Container(
      key: const ValueKey('settings-theme-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EFE6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme Settings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Edit workspace theme colors with a live preview against the active preset.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in VityoThemePreset.values)
                ChoiceChip(
                  key: ValueKey('settings-theme-preset-${preset.name}'),
                  label: Text(preset.name),
                  selected: _previewPreset == preset,
                  onSelected: (selected) {
                    if (!selected) {
                      return;
                    }
                    setState(() {
                      _previewPreset = preset;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final field in _ThemeColorField.values)
                    SizedBox(
                      width: fieldWidth,
                      child: TextField(
                        key: ValueKey('settings-theme-${field.keyName}-input'),
                        controller: _controllers[field],
                        onChanged: (_) {
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: field.label,
                          hintText: field.hint,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _ThemePreviewPanel(
            theme: previewTheme,
            preset: _previewPreset,
            themeOverride: draftOverride,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('settings-theme-save-button'),
                onPressed: widget.onSaveThemeOverride == null
                    ? null
                    : () {
                        widget.onSaveThemeOverride!(_draftOverride());
                      },
                child: const Text('Save theme override'),
              ),
              OutlinedButton(
                key: const ValueKey('settings-theme-reset-button'),
                onPressed: widget.onSaveThemeOverride == null
                    ? null
                    : () {
                        setState(() {
                          _previewPreset = VityoThemePreset.parchment;
                          for (final field in _ThemeColorField.values) {
                            _controllers[field]!.text = '';
                          }
                        });
                        widget.onSaveThemeOverride!(const VityoThemeOverride());
                      },
                child: const Text('Reset theme'),
              ),
              for (final field in _ThemeColorField.values)
                if (_overrideColor(field, draftOverride) != null)
                  Chip(
                    label: Text(
                      '${field.keyName} ${_colorToHex(_overrideColor(field, draftOverride))}',
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  VityoThemeOverride _draftOverride() {
    return VityoThemeOverride(
      canvas: _resolvedColor(_ThemeColorField.canvas)?.toARGB32(),
      panel: _resolvedColor(_ThemeColorField.panel)?.toARGB32(),
      ink: _resolvedColor(_ThemeColorField.ink)?.toARGB32(),
      accent: _resolvedColor(_ThemeColorField.accent)?.toARGB32(),
      muted: _resolvedColor(_ThemeColorField.muted)?.toARGB32(),
    );
  }

  Color? _resolvedColor(_ThemeColorField field) {
    final parsed = _parseHexColor(_controllers[field]!.text);
    if (parsed != null) {
      return parsed;
    }
    return _overrideColor(field, widget.themeOverride);
  }

  Color? _overrideColor(_ThemeColorField field, VityoThemeOverride override) {
    return switch (field) {
      _ThemeColorField.canvas =>
        override.canvas != null ? Color(override.canvas!) : null,
      _ThemeColorField.panel =>
        override.panel != null ? Color(override.panel!) : null,
      _ThemeColorField.ink =>
        override.ink != null ? Color(override.ink!) : null,
      _ThemeColorField.accent =>
        override.accent != null ? Color(override.accent!) : null,
      _ThemeColorField.muted =>
        override.muted != null ? Color(override.muted!) : null,
    };
  }
}

class _ThemePreviewPanel extends StatelessWidget {
  const _ThemePreviewPanel({
    required this.theme,
    required this.preset,
    required this.themeOverride,
  });

  final ThemeData theme;
  final VityoThemePreset preset;
  final VityoThemeOverride themeOverride;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('settings-theme-preview'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${preset.name} preview',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ThemeSwatch(
                      key: const ValueKey('settings-theme-preview-canvas'),
                      label: 'canvas',
                      color: theme.scaffoldBackgroundColor,
                    ),
                    _ThemeSwatch(
                      key: const ValueKey('settings-theme-preview-panel'),
                      label: 'panel',
                      color: theme.cardColor,
                    ),
                    _ThemeSwatch(
                      key: const ValueKey('settings-theme-preview-ink'),
                      label: 'ink',
                      color:
                          theme.textTheme.bodyMedium?.color ??
                          colorScheme.onSurface,
                    ),
                    _ThemeSwatch(
                      key: const ValueKey('settings-theme-preview-accent'),
                      label: 'accent',
                      color: colorScheme.primary,
                    ),
                    _ThemeSwatch(
                      key: const ValueKey('settings-theme-preview-muted'),
                      label: 'muted',
                      color:
                          theme.textTheme.bodySmall?.color ??
                          colorScheme.onSurface,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Card(
                  color: theme.cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Preview card', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          'Canvas, panel, ink, accent, and muted values follow the selected preset unless an override edits them.',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(label: Text('preset ${preset.name}')),
                            Chip(
                              label: Text(
                                'override ${themeOverride.toJson().length}',
                              ),
                            ),
                            const OutlinedButton(
                              onPressed: null,
                              child: Text('Action'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final onColor = color.computeLuminance() > 0.55
        ? const Color(0xFF1E252B)
        : const Color(0xFFFFFFFF);
    return Container(
      width: 110,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: onColor)),
          const SizedBox(height: 4),
          Text(_colorToHex(color), style: TextStyle(color: onColor)),
        ],
      ),
    );
  }
}

String _colorToHex(Color? color) {
  if (color == null) {
    return '';
  }
  final rgb = color.toARGB32() & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? _parseHexColor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final normalized = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
  if (normalized.length != 6 && normalized.length != 8) {
    return null;
  }
  final parsed = int.tryParse(normalized, radix: 16);
  if (parsed == null) {
    return null;
  }
  return Color(normalized.length == 6 ? 0xFF000000 | parsed : parsed);
}

class _ToolchainSettingsCard extends StatelessWidget {
  const _ToolchainSettingsCard({
    required this.settings,
    required this.installPlan,
    required this.installExecution,
    required this.bootstrapSummary,
    required this.bootstrapActionDispatch,
    required this.onRecoveryAction,
    required this.onBootstrapAction,
    required this.onSelectToolchain,
    required this.onSelectClangCppVersion,
    required this.onClearToolchain,
    required this.onExecuteToolchainInstallPlan,
  });

  final ToolchainSettingsSurface settings;
  final ToolchainInstallPlanSurface? installPlan;
  final ToolchainInstallExecutionSurface? installExecution;
  final ToolchainManagerBootstrapSummary? bootstrapSummary;
  final ToolchainBootstrapActionDispatchResult? bootstrapActionDispatch;
  final Future<void> Function(ToolchainRecoveryAction action)? onRecoveryAction;
  final Future<void> Function(String actionId)? onBootstrapAction;
  final Future<void> Function(String id)? onSelectToolchain;
  final Future<void> Function(String versionId, String cppStandard)?
  onSelectClangCppVersion;
  final Future<void> Function(ToolchainKind kind)? onClearToolchain;
  final Future<void> Function()? onExecuteToolchainInstallPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = settings.status;
    final accent = switch (status.severity) {
      ToolchainStatusSeverity.ready => const Color(0xFFDFF0DE),
      ToolchainStatusSeverity.unavailable => const Color(0xFFF0E8D6),
      ToolchainStatusSeverity.blocked => const Color(0xFFF4E8D8),
      ToolchainStatusSeverity.failed => const Color(0xFFF3D8D6),
    };
    final selectClangCppVersion =
        onSelectClangCppVersion ??
        (onSelectToolchain == null
            ? null
            : (String versionId, String _) {
                return onSelectToolchain!(versionId);
              });

    return Container(
      key: const ValueKey('settings-toolchain-status-card'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toolchain Settings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(status.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(status.message, style: theme.textTheme.bodySmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(label: Text('source ${status.source}')),
              Chip(label: Text('severity ${status.severity.name}')),
              if (status.version != null)
                Chip(label: Text('version ${status.version}')),
              if (status.channel != null)
                Chip(label: Text('channel ${status.channel}')),
              if (status.lastCommand != null)
                Chip(label: Text('command ${status.lastCommand}')),
            ],
          ),
          if (status.recoveryActions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Recovery', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: status.recoveryActions
                  .map(
                    (action) => OutlinedButton(
                      key: ValueKey('settings-toolchain-recovery-${action.id}'),
                      onPressed: onRecoveryAction == null
                          ? null
                          : () {
                              onRecoveryAction!(action);
                            },
                      child: Text(action.label),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if (bootstrapSummary != null) ...[
            const SizedBox(height: 12),
            _ToolchainBootstrapSummaryView(
              summary: bootstrapSummary!,
              dispatchResult: bootstrapActionDispatch,
              onBootstrapAction: onBootstrapAction,
            ),
          ],
          if (settings.clangCppVersions != null) ...[
            const SizedBox(height: 14),
            _ClangCppVersionManagerView(
              versions: settings.clangCppVersions!,
              onSelectClangCppVersion: selectClangCppVersion,
            ),
          ],
          const SizedBox(height: 14),
          _ToolchainCandidateList(
            toolchains: settings.toolchains,
            onSelectToolchain: onSelectToolchain,
            onClearToolchain: onClearToolchain,
          ),
          const SizedBox(height: 14),
          _ToolchainCapabilityList(capabilities: settings.capabilities),
          const SizedBox(height: 14),
          _ToolchainRecoveryStateView(state: settings.recoveryState),
          const SizedBox(height: 14),
          _ToolchainInstallHistoryList(entries: settings.installHistory),
          if (installPlan != null) ...[
            const SizedBox(height: 14),
            _ToolchainInstallPlanView(
              plan: installPlan!,
              onExecuteToolchainInstallPlan: onExecuteToolchainInstallPlan,
            ),
          ],
          if (installExecution != null) ...[
            const SizedBox(height: 14),
            _ToolchainInstallExecutionView(
              result: installExecution!,
              onRecoveryAction: onRecoveryAction,
            ),
          ],
        ],
      ),
    );
  }
}

class _ToolchainBootstrapSummaryView extends StatelessWidget {
  const _ToolchainBootstrapSummaryView({
    required this.summary,
    required this.dispatchResult,
    required this.onBootstrapAction,
  });

  final ToolchainManagerBootstrapSummary summary;
  final ToolchainBootstrapActionDispatchResult? dispatchResult;
  final Future<void> Function(String actionId)? onBootstrapAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('settings-toolchain-bootstrap-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Toolchain Bootstrap', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            summary.styioLifecycle.message,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Chip(label: Text(summary.ready ? 'ready' : 'actionable')),
              Chip(label: Text('manager ${summary.managerReport.status.name}')),
              Chip(label: Text('styio ${summary.styioLifecycle.state.name}')),
            ],
          ),
          if (dispatchResult != null) ...[
            const SizedBox(height: 10),
            Container(
              key: const ValueKey(
                'settings-toolchain-bootstrap-dispatch-result',
              ),
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last dispatch: '
                    '${dispatchResult!.status.wireValue} · '
                    '${dispatchResult!.actionId}',
                    style: theme.textTheme.labelLarge,
                  ),
                  if (dispatchResult!.message.isNotEmpty)
                    Text(
                      dispatchResult!.message,
                      style: theme.textTheme.bodySmall,
                    ),
                  if (dispatchResult!.todo.isNotEmpty)
                    Text(
                      dispatchResult!.todo,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          _ToolchainBootstrapActionGroup(
            label: 'Settings',
            keyPrefix: 'settings-toolchain-bootstrap-settings',
            actionIds: summary.settingsActionIds,
            onBootstrapAction: onBootstrapAction,
          ),
          _ToolchainBootstrapActionGroup(
            label: 'Installer',
            keyPrefix: 'settings-toolchain-bootstrap-installer',
            actionIds: summary.installerActionIds,
            onBootstrapAction: onBootstrapAction,
          ),
          _ToolchainBootstrapActionGroup(
            label: 'Project Bootstrap',
            keyPrefix: 'settings-toolchain-bootstrap-project',
            actionIds: summary.projectBootstrapActionIds,
            onBootstrapAction: onBootstrapAction,
          ),
        ],
      ),
    );
  }
}

class _ToolchainBootstrapActionGroup extends StatelessWidget {
  const _ToolchainBootstrapActionGroup({
    required this.label,
    required this.keyPrefix,
    required this.actionIds,
    required this.onBootstrapAction,
  });

  final String label;
  final String keyPrefix;
  final List<String> actionIds;
  final Future<void> Function(String actionId)? onBootstrapAction;

  @override
  Widget build(BuildContext context) {
    if (actionIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final actionId in actionIds)
                OutlinedButton(
                  key: ValueKey('$keyPrefix-$actionId'),
                  onPressed: onBootstrapAction == null
                      ? null
                      : () {
                          onBootstrapAction!(actionId);
                        },
                  child: Text(actionId),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ClangCppVersionManagerView extends StatelessWidget {
  const _ClangCppVersionManagerView({
    required this.versions,
    required this.onSelectClangCppVersion,
  });

  final ClangCppVersionSettingsSurface versions;
  final Future<void> Function(String versionId, String cppStandard)?
  onSelectClangCppVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preferred = versions.preferredBuildEngineHandoff;
    return Column(
      key: const ValueKey('settings-clang-cpp-version-manager'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Clang/C++ Versions', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          'IDE-selected Clang/C++ compiler version and external build engine handoff.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Chip(label: Text('preference ${versions.preferenceStatus}')),
            Chip(label: Text('standard c++${versions.defaultCppStandard}')),
            Chip(label: Text('flag ${versions.defaultCompilerFlag}')),
            Chip(label: Text('cmake ${versions.cmakeAvailable}')),
            Chip(label: Text('ninja ${versions.ninjaAvailable}')),
            if (preferred != null)
              Chip(
                key: const ValueKey('settings-clang-cpp-preferred-handoff'),
                label: Text('handoff ${preferred.label}'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: versions.supportedStandards
              .map(
                (standard) => ActionChip(
                  key: ValueKey(
                    'settings-clang-cpp-standard-${standard.cmakeValue}',
                  ),
                  label: Text('c++${standard.cmakeValue}'),
                  avatar: standard.active
                      ? const Icon(Icons.check, size: 16)
                      : null,
                  onPressed:
                      onSelectClangCppVersion == null ||
                          versions.activeVersionId == null
                      ? null
                      : () {
                          onSelectClangCppVersion!(
                            versions.activeVersionId!,
                            standard.cmakeValue,
                          );
                        },
                ),
              )
              .toList(growable: false),
        ),
        if (versions.preferenceMessage != null) ...[
          const SizedBox(height: 8),
          Text(versions.preferenceMessage!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: versions.candidates
              .map(
                (candidate) => Chip(
                  key: ValueKey(
                    'settings-clang-cpp-version-${candidate.versionId}',
                  ),
                  label: Text(_clangCppCandidateLabel(candidate)),
                  deleteIcon: candidate.active
                      ? null
                      : const Icon(Icons.check_circle_outline),
                  onDeleted: candidate.active || onSelectClangCppVersion == null
                      ? null
                      : () {
                          onSelectClangCppVersion!(
                            candidate.versionId,
                            versions.defaultCppStandard,
                          );
                        },
                  deleteButtonTooltipMessage: candidate.active
                      ? null
                      : 'Select ${candidate.displayName}',
                ),
              )
              .toList(growable: false),
        ),
        if (versions.buildEngineHandoffs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: versions.buildEngineHandoffs
                .map(
                  (handoff) => Chip(
                    key: ValueKey(
                      'settings-clang-cpp-handoff-${handoff.label}',
                    ),
                    label: Text('${handoff.label} ${handoff.executablePath}'),
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }
}

String _clangCppCandidateLabel(ClangCppVersionCandidateSurface candidate) {
  return <String>[
    if (candidate.active) 'active',
    'clang',
    candidate.displayName,
    if (candidate.version != null) candidate.version!,
    if (candidate.vendor != null) candidate.vendor!,
    if (candidate.source != null) candidate.source!,
  ].join(' ');
}

class _ToolchainInstallPlanView extends StatelessWidget {
  const _ToolchainInstallPlanView({
    required this.plan,
    required this.onExecuteToolchainInstallPlan,
  });

  final ToolchainInstallPlanSurface plan;
  final Future<void> Function()? onExecuteToolchainInstallPlan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-toolchain-install-plan'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Install Plan', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Chip(label: Text('plan ${plan.status}')),
            Chip(label: Text('mode ${plan.mode}')),
            Chip(label: Text('kind ${plan.kind}')),
            Chip(label: Text('actionable ${plan.actionable}')),
            if (plan.externalCommand != null)
              Chip(label: Text('command ${plan.externalCommand}')),
          ],
        ),
        if (plan.message != null) ...[
          const SizedBox(height: 8),
          Text(plan.message!, style: theme.textTheme.bodySmall),
        ],
        if (plan.downloadUri != null) ...[
          const SizedBox(height: 8),
          Text(plan.downloadUri!, style: theme.textTheme.bodySmall),
        ],
        if (plan.actionable && onExecuteToolchainInstallPlan != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('settings-toolchain-execute-install-plan'),
            onPressed: onExecuteToolchainInstallPlan,
            child: const Text('Continue install plan'),
          ),
        ],
      ],
    );
  }
}

class _ToolchainInstallExecutionView extends StatelessWidget {
  const _ToolchainInstallExecutionView({
    required this.result,
    required this.onRecoveryAction,
  });

  final ToolchainInstallExecutionSurface result;
  final Future<void> Function(ToolchainRecoveryAction action)? onRecoveryAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-toolchain-install-execution'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Install Execution', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Chip(label: Text('execution ${result.status}')),
            Chip(label: Text('mode ${result.mode}')),
            Chip(label: Text('kind ${result.kind}')),
            Chip(label: Text('success ${result.succeeded}')),
          ],
        ),
        if (result.message != null) ...[
          const SizedBox(height: 8),
          Text(result.message!, style: theme.textTheme.bodySmall),
        ],
        if (result.recoveryActions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Column(
            key: const ValueKey(
              'settings-toolchain-install-execution-recovery',
            ),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Install Recovery', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.recoveryActions
                    .map(
                      (action) => OutlinedButton(
                        key: ValueKey(
                          'settings-toolchain-install-execution-recovery-${action.id}',
                        ),
                        onPressed: onRecoveryAction == null
                            ? null
                            : () {
                                onRecoveryAction!(action);
                              },
                        child: Text(action.label),
                      ),
                    )
                    .toList(growable: false),
              ),
              for (final action in result.recoveryActions)
                if (action.description.isNotEmpty)
                  Text(action.description, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ],
    );
  }
}

class _ToolchainCandidateList extends StatelessWidget {
  const _ToolchainCandidateList({
    required this.toolchains,
    required this.onSelectToolchain,
    required this.onClearToolchain,
  });

  final List<ToolchainCandidateSurface> toolchains;
  final Future<void> Function(String id)? onSelectToolchain;
  final Future<void> Function(ToolchainKind kind)? onClearToolchain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-toolchain-candidates'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Registered Toolchains', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (toolchains.isEmpty)
          Text(
            'No manager catalog entries are available for selection yet.',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: toolchains
                .map((toolchain) {
                  final labelParts = <String>[
                    if (toolchain.active) 'active',
                    toolchain.kind.wireValue,
                    toolchain.displayName,
                    if (toolchain.version != null) toolchain.version!,
                    if (toolchain.channel != null) toolchain.channel!,
                  ];
                  return Chip(
                    key: ValueKey('settings-toolchain-${toolchain.id}'),
                    label: Text(labelParts.join(' ')),
                    deleteIcon: Icon(
                      toolchain.active
                          ? Icons.cancel_outlined
                          : Icons.check_circle_outline,
                    ),
                    onDeleted: toolchain.active
                        ? onClearToolchain == null
                              ? null
                              : () {
                                  onClearToolchain!(toolchain.kind);
                                }
                        : onSelectToolchain == null
                        ? null
                        : () {
                            onSelectToolchain!(toolchain.id);
                          },
                    deleteButtonTooltipMessage: toolchain.active
                        ? 'Clear active ${toolchain.displayName}'
                        : 'Select ${toolchain.displayName}',
                  );
                })
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _ToolchainCapabilityList extends StatelessWidget {
  const _ToolchainCapabilityList({required this.capabilities});

  final List<ToolchainCapabilitySurface> capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-toolchain-capabilities'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Capabilities', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (capabilities.isEmpty)
          Text(
            'No normalized capability states are available.',
            style: theme.textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: capabilities
                .map(
                  (capability) => Chip(
                    key: ValueKey(
                      'settings-toolchain-capability-${capability.kind.wireValue}',
                    ),
                    label: Text(
                      '${capability.kind.wireValue} ${capability.state}',
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}

class _ToolchainRecoveryStateView extends StatelessWidget {
  const _ToolchainRecoveryStateView({required this.state});

  final ToolchainRecoveryStateSurface state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-toolchain-recovery-state'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recovery State', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            Chip(label: Text('state ${state.kind}')),
            Chip(label: Text('actionable ${state.actionable}')),
            for (final actionId in state.actionIds)
              Chip(label: Text('action $actionId')),
          ],
        ),
        if (state.message != null) ...[
          const SizedBox(height: 8),
          Text(state.message!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _ToolchainInstallHistoryList extends StatelessWidget {
  const _ToolchainInstallHistoryList({required this.entries});

  final List<ToolchainInstallHistorySurface> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('settings-toolchain-install-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Install History', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'No persisted install execution history is available.',
            style: theme.textTheme.bodySmall,
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries
                .map(
                  (entry) => Padding(
                    key: ValueKey('settings-toolchain-install-${entry.id}'),
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${entry.kind} ${entry.mode} ${entry.status} '
                      'success=${entry.succeeded}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }
}
