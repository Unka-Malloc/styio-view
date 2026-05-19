import '../module_host/module_host.dart';
import 'app_commands.dart';

class ExtensionCommandContribution {
  const ExtensionCommandContribution({
    required this.extensionId,
    required this.commandId,
    required this.target,
    required this.label,
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionCommandContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    final metadataLabel = route.contribution.metadata['label'];
    return ExtensionCommandContribution(
      extensionId: route.extensionId,
      commandId: route.contribution.id,
      target: route.registryTargetId,
      label:
          route.contribution.title ??
          (metadataLabel is String && metadataLabel.trim().isNotEmpty
              ? metadataLabel.trim()
              : route.contribution.id),
      metadata: route.contribution.metadata,
    );
  }

  final String extensionId;
  final String commandId;
  final String target;
  final String label;
  final Map<String, Object?> metadata;

  bool get valid {
    return extensionId.trim().isNotEmpty &&
        commandId.trim().isNotEmpty &&
        target.trim().isNotEmpty;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'id': commandId,
      'target': target,
      'label': label,
      'category': AppCommandCategory.module.wireValue,
      'dynamic': true,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'valid': valid,
    };
  }
}

class ExtensionCommandContributionCatalog {
  const ExtensionCommandContributionCatalog({required this.commands});

  factory ExtensionCommandContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionCommandContributionCatalog(
      commands: routes
          .routesFor(ExtensionContributionRegistryKind.commandRegistry)
          .where((route) => route.ready)
          .map(ExtensionCommandContribution.fromRoute)
          .where((command) => command.valid)
          .toList(growable: false),
    );
  }

  final List<ExtensionCommandContribution> commands;

  bool get hasCommands => commands.isNotEmpty;

  ExtensionCommandContribution? lookup(String commandId) {
    for (final command in commands) {
      if (command.commandId == commandId) {
        return command;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-command-contributions.v1',
      'commandCount': commands.length,
      'commands': commands
          .map((command) => command.toJson())
          .toList(growable: false),
    };
  }

  Map<String, Object?> mergeWithStaticManifest({
    Map<String, Object?>? staticManifest,
  }) {
    final baseManifest =
        staticManifest ?? StyioCommandRegistry.contributionManifest;
    return <String, Object?>{
      ...baseManifest,
      'extensionCommandSchema': 'vityo.extension-command-contributions.v1',
      'extensionCommandCount': commands.length,
      'extensionCommands': commands
          .map((command) => command.toJson())
          .toList(growable: false),
    };
  }
}
