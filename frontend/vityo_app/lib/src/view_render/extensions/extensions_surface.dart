import 'package:flutter/material.dart';

import '../../view_ide/module_host/module_definition.dart';
import '../platform/viewport_profile.dart';

class ExtensionsSurface extends StatelessWidget {
  const ExtensionsSurface({
    super.key,
    required this.viewportProfile,
    required this.visibleModules,
    required this.mountedModules,
    this.onRefreshModules,
  });

  final ViewportProfile viewportProfile;
  final List<ModuleDefinition> visibleModules;
  final List<ModuleDefinition> mountedModules;
  final Future<void> Function()? onRefreshModules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = viewportProfile.isMobile;
    final mountedIds = mountedModules
        .map((module) => module.manifest.moduleId)
        .toSet();

    return Card(
      key: const ValueKey('extensions-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
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
              Expanded(
                child: ListView.separated(
                  key: const ValueKey('extensions-module-list'),
                  itemCount: visibleModules.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final module = visibleModules[index];
                    final manifest = module.manifest;
                    final mounted = mountedIds.contains(manifest.moduleId);
                    return ListTile(
                      key: ValueKey('extensions-module-${manifest.moduleId}'),
                      dense: true,
                      leading: Icon(
                        mounted
                            ? Icons.extension_rounded
                            : Icons.extension_off_rounded,
                      ),
                      title: Text(manifest.displayName),
                      subtitle: Text(
                        '${manifest.moduleId} · ${manifest.version} · ${manifest.kind.name} · ${manifest.slot.name}',
                      ),
                      trailing: Chip(
                        label: Text(mounted ? 'mounted' : 'visible'),
                      ),
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
