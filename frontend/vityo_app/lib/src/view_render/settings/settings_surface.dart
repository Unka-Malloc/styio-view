import 'package:flutter/material.dart';

import '../../view_ide/interaction/interaction.dart';
import '../../view_ide/toolchain/toolchain_catalog.dart';
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
    this.onToolchainRecoveryAction,
    this.onSelectToolchain,
    this.onSelectClangCppVersion,
    this.onClearToolchain,
    this.onExecuteToolchainInstallPlan,
    this.themeOverride = const VityoThemeOverride(),
    this.onSaveThemeOverride,
  });

  final ViewportProfile viewportProfile;
  final ToolchainStatusSurface toolchainStatus;
  final ToolchainSettingsSurface? toolchainSettings;
  final ToolchainInstallPlanSurface? toolchainInstallPlan;
  final ToolchainInstallExecutionSurface? toolchainInstallExecution;
  final Future<void> Function(ToolchainRecoveryAction action)?
  onToolchainRecoveryAction;
  final Future<void> Function(String id)? onSelectToolchain;
  final Future<void> Function(String versionId)? onSelectClangCppVersion;
  final Future<void> Function(ToolchainKind kind)? onClearToolchain;
  final Future<void> Function()? onExecuteToolchainInstallPlan;
  final VityoThemeOverride themeOverride;
  final Future<void> Function(VityoThemeOverride override)? onSaveThemeOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final settings =
        toolchainSettings ??
        ToolchainSettingsSurface.fromStatus(toolchainStatus);

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
                onRecoveryAction: onToolchainRecoveryAction,
                onSelectToolchain: onSelectToolchain,
                onSelectClangCppVersion: onSelectClangCppVersion,
                onClearToolchain: onClearToolchain,
                onExecuteToolchainInstallPlan: onExecuteToolchainInstallPlan,
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

class _ThemeSettingsCardState extends State<_ThemeSettingsCard> {
  late final TextEditingController _accentController;

  @override
  void initState() {
    super.initState();
    _accentController = TextEditingController(
      text: _colorToHex(widget.themeOverride.accent),
    );
  }

  @override
  void didUpdateWidget(covariant _ThemeSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _colorToHex(widget.themeOverride.accent);
    if (_accentController.text != nextText) {
      _accentController.text = nextText;
    }
  }

  @override
  void dispose() {
    _accentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            'Persist a workspace theme override through Configuration DataStore.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('settings-theme-accent-input'),
            controller: _accentController,
            decoration: const InputDecoration(
              labelText: 'Accent color',
              hintText: '#2F6F73',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('settings-theme-save-button'),
                onPressed: widget.onSaveThemeOverride == null
                    ? null
                    : () {
                        final accent = _parseHexColor(_accentController.text);
                        if (accent == null) {
                          return;
                        }
                        widget.onSaveThemeOverride!(
                          widget.themeOverride.copyWith(accent: accent),
                        );
                      },
                child: const Text('Save theme override'),
              ),
              OutlinedButton(
                key: const ValueKey('settings-theme-reset-button'),
                onPressed: widget.onSaveThemeOverride == null
                    ? null
                    : () {
                        widget.onSaveThemeOverride!(const VityoThemeOverride());
                      },
                child: const Text('Reset theme'),
              ),
              if (widget.themeOverride.accent != null)
                Chip(
                  label: Text(
                    'accent ${_colorToHex(widget.themeOverride.accent)}',
                  ),
                ),
            ],
          ),
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
    required this.onRecoveryAction,
    required this.onSelectToolchain,
    required this.onSelectClangCppVersion,
    required this.onClearToolchain,
    required this.onExecuteToolchainInstallPlan,
  });

  final ToolchainSettingsSurface settings;
  final ToolchainInstallPlanSurface? installPlan;
  final ToolchainInstallExecutionSurface? installExecution;
  final Future<void> Function(ToolchainRecoveryAction action)? onRecoveryAction;
  final Future<void> Function(String id)? onSelectToolchain;
  final Future<void> Function(String versionId)? onSelectClangCppVersion;
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
          if (settings.clangCppVersions != null) ...[
            const SizedBox(height: 14),
            _ClangCppVersionManagerView(
              versions: settings.clangCppVersions!,
              onSelectClangCppVersion:
                  onSelectClangCppVersion ?? onSelectToolchain,
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
            _ToolchainInstallExecutionView(result: installExecution!),
          ],
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
  final Future<void> Function(String versionId)? onSelectClangCppVersion;

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
                          onSelectClangCppVersion!(candidate.versionId);
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
  const _ToolchainInstallExecutionView({required this.result});

  final ToolchainInstallExecutionSurface result;

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
