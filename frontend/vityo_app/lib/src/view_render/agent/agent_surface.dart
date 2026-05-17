import 'package:flutter/material.dart';

import '../../view_ide/backend_toolchain/adapter_contracts.dart';
import '../../view_ide/module_host/module_definition.dart';
import '../../view_ide/module_host/module_manifest.dart';
import '../../view_ide/platform/platform_target.dart';
import '../platform/viewport_profile.dart';

class AgentSurface extends StatelessWidget {
  const AgentSurface({
    super.key,
    required this.platformTarget,
    required this.viewportProfile,
    required this.visibleModules,
    required this.adapterCapabilities,
  });

  final PlatformTarget platformTarget;
  final ViewportProfile viewportProfile;
  final List<ModuleDefinition> visibleModules;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final agentModules = visibleModules
        .where(
          (module) => switch (module.manifest.slot) {
            ModuleSlot.agentSurface || ModuleSlot.cloudRuntime => true,
            _ => false,
          },
        )
        .toList(growable: false);
    final providerRoute = _providerRouteForPlatform(platformTarget);

    return Card(
      key: ValueKey('agent-surface-${viewportProfile.label.toLowerCase()}'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          children: [
            Text(
              'Agent Surface',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${platformTarget.label} agent route aligned to the ${viewportProfile.label.toLowerCase()} shell.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            if (viewportProfile.isMobile) ...[
              _AgentSection(
                title: 'Provider Route',
                body:
                    '$providerRoute. Mobile and narrow Web keep the same provider contract, but compress the presentation into a single vertical stack.',
                accent: const Color(0xFFE1E8F5),
              ),
              const SizedBox(height: 12),
              const _AgentSection(
                title: 'Context Injection',
                body:
                    'Current file, selection, diagnostics, and runtime context stay as separate injection channels for M6.',
                accent: Color(0xFFEDE6D9),
              ),
              const SizedBox(height: 12),
              _AdapterSection(adapterCapabilities: adapterCapabilities),
              const SizedBox(height: 12),
              _AgentModuleSection(modules: agentModules),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _AgentSection(
                      title: 'Provider Route',
                      body:
                          '$providerRoute. Desktop and wide Web keep the prompt/profile surface adjacent to runtime panels while sharing the same adapter contract.',
                      accent: const Color(0xFFE1E8F5),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: _AgentSection(
                      title: 'Context Injection',
                      body:
                          'Current file, selection, diagnostics, and runtime context remain independent channels so agent prompts do not collapse language-service boundaries.',
                      accent: Color(0xFFEDE6D9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AdapterSection(adapterCapabilities: adapterCapabilities),
              const SizedBox(height: 14),
              _AgentModuleSection(modules: agentModules),
            ],
          ],
        ),
      ),
    );
  }
}

class _AgentSection extends StatelessWidget {
  const _AgentSection({
    required this.title,
    required this.body,
    required this.accent,
  });

  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(body, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AdapterSection extends StatelessWidget {
  const _AdapterSection({required this.adapterCapabilities});

  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF6),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Adapter Routes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 10),
          for (final snapshot in adapterCapabilities)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '${snapshot.adapterKind.label}: language ${snapshot.languageService.level.label}, execution ${snapshot.execution.level.label}',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentModuleSection extends StatelessWidget {
  const _AgentModuleSection({required this.modules});

  final List<ModuleDefinition> modules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F2E9),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mounted Adapters And Slots',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          if (modules.isEmpty)
            Text(
              'No agent adapter modules are visible for this target.',
              style: theme.textTheme.bodySmall,
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: modules
                  .map(
                    (module) => Chip(label: Text(module.manifest.displayName)),
                  )
                  .toList(growable: false),
            ),
          const SizedBox(height: 12),
          Text(
            'Local agent runtime stays external; iOS keeps the cloud route as the compliance floor.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _providerRouteForPlatform(PlatformTarget platformTarget) {
  switch (platformTarget) {
    case PlatformTarget.ios:
      return 'Cloud-only OpenAI-compatible provider route';
    case PlatformTarget.web:
      return 'Hosted provider route with cloud profile sync';
    case PlatformTarget.android:
      return 'Cloud provider route with optional local bridge slot';
    case PlatformTarget.windows:
    case PlatformTarget.linux:
    case PlatformTarget.macos:
      return 'Desktop provider route with local bridge reservation';
    case PlatformTarget.unknown:
      return 'Provider route pending platform resolution';
  }
}
