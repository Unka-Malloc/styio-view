import 'package:flutter/material.dart';

import '../../view_ide/module_host/module_definition.dart';
import '../../view_ide/module_host/module_lifecycle.dart';
import '../platform/viewport_profile.dart';

class ExtensionsSurface extends StatelessWidget {
  const ExtensionsSurface({
    super.key,
    required this.viewportProfile,
    required this.visibleModules,
    required this.mountedModules,
    this.moduleStates = const <ModuleLifecycleState>[],
    this.onRefreshModules,
    this.onEnableModule,
    this.onDisableModule,
    this.onTrustModule,
  });

  final ViewportProfile viewportProfile;
  final List<ModuleDefinition> visibleModules;
  final List<ModuleDefinition> mountedModules;
  final List<ModuleLifecycleState> moduleStates;
  final Future<void> Function()? onRefreshModules;
  final Future<void> Function(String moduleId)? onEnableModule;
  final Future<void> Function(String moduleId)? onDisableModule;
  final Future<void> Function(String moduleId)? onTrustModule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final mountedIds = mountedModules
        .map((module) => module.manifest.moduleId)
        .toSet();
    final statesById = <String, ModuleLifecycleState>{
      for (final state in moduleStates) state.moduleId: state,
    };
    final disabledCount = visibleModules.where((module) {
      final state =
          statesById[module.manifest.moduleId] ??
          defaultModuleLifecycleState(module);
      return !state.enabled;
    }).length;
    final untrustedCount = visibleModules.where((module) {
      final state =
          statesById[module.manifest.moduleId] ??
          defaultModuleLifecycleState(module);
      return !state.trusted;
    }).length;

    return Card(
      key: const ValueKey('extensions-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Text('Extensions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              'Module/extension inventory backed by Vityo module manifests. TODO: add marketplace index, install, enable, disable, trust, update, and extension host isolation.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Chip(label: Text('visible ${visibleModules.length}')),
                Chip(label: Text('mounted ${mountedModules.length}')),
                Chip(label: Text('disabled $disabledCount')),
                Chip(label: Text('untrusted $untrustedCount')),
                const Chip(label: Text('marketplace scaffolded')),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('extensions-refresh-modules'),
              onPressed: onRefreshModules,
              icon: const Icon(Icons.extension_rounded),
              label: const Text('Refresh Modules'),
            ),
            const SizedBox(height: 12),
            Text('Installed Modules', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            if (visibleModules.isEmpty)
              Text(
                'No visible modules are registered for this platform.',
                style: theme.textTheme.bodySmall,
              )
            else
              Column(
                key: const ValueKey('extensions-module-list'),
                children: [
                  for (final module in visibleModules)
                    _ExtensionModuleCard(
                      module: module,
                      mounted: mountedIds.contains(module.manifest.moduleId),
                      state:
                          statesById[module.manifest.moduleId] ??
                          defaultModuleLifecycleState(module),
                      onEnableModule: onEnableModule,
                      onDisableModule: onDisableModule,
                      onTrustModule: onTrustModule,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtensionModuleCard extends StatelessWidget {
  const _ExtensionModuleCard({
    required this.module,
    required this.mounted,
    required this.state,
    required this.onEnableModule,
    required this.onDisableModule,
    required this.onTrustModule,
  });

  final ModuleDefinition module;
  final bool mounted;
  final ModuleLifecycleState state;
  final Future<void> Function(String moduleId)? onEnableModule;
  final Future<void> Function(String moduleId)? onDisableModule;
  final Future<void> Function(String moduleId)? onTrustModule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final manifest = module.manifest;
    return Container(
      key: ValueKey('extensions-module-${manifest.moduleId}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                mounted
                    ? Icons.extension_rounded
                    : Icons.extension_off_rounded,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  manifest.displayName,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${manifest.moduleId} · ${manifest.version} · ${manifest.kind.name} · ${manifest.slot.name}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(mounted ? 'mounted' : 'visible')),
              Chip(label: Text(state.enabled ? 'enabled' : 'disabled')),
              Chip(label: Text(state.trustState.wireValue)),
              if (state.updateAvailable) const Chip(label: Text('update')),
              if (state.enabled)
                TextButton(
                  key: ValueKey('extensions-disable-${manifest.moduleId}'),
                  onPressed: onDisableModule == null
                      ? null
                      : () {
                          onDisableModule!(manifest.moduleId);
                        },
                  child: const Text('Disable'),
                )
              else
                TextButton(
                  key: ValueKey('extensions-enable-${manifest.moduleId}'),
                  onPressed: onEnableModule == null
                      ? null
                      : () {
                          onEnableModule!(manifest.moduleId);
                        },
                  child: const Text('Enable'),
                ),
              if (!state.trusted)
                TextButton(
                  key: ValueKey('extensions-trust-${manifest.moduleId}'),
                  onPressed: onTrustModule == null
                      ? null
                      : () {
                          onTrustModule!(manifest.moduleId);
                        },
                  child: const Text('Trust'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
