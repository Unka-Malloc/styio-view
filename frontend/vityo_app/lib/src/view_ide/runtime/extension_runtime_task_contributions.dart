import '../module_host/module_host.dart';
import 'runtime_task_lifecycle.dart';

enum ExtensionRuntimeTaskContributionStatus {
  ready,
  invalidRoute,
  missingCommand,
}

class ExtensionRuntimeTaskContribution {
  const ExtensionRuntimeTaskContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.definition,
  });

  factory ExtensionRuntimeTaskContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.runtimeTaskRegistry) {
      return ExtensionRuntimeTaskContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionRuntimeTaskContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready runtime task route.',
      );
    }
    final command = _metadataString(route.contribution.metadata, 'command');
    if (command == null) {
      return ExtensionRuntimeTaskContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionRuntimeTaskContributionStatus.missingCommand,
        message:
            'Runtime task contribution ${route.contribution.id} does not declare metadata.command.',
      );
    }
    final definition = RuntimeTaskDefinition(
      id:
          _metadataString(route.contribution.metadata, 'taskId') ??
          route.contribution.id,
      label:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          route.contribution.id,
      kind: _runtimeTaskKindFromMetadata(route.contribution.metadata),
      command: command,
      arguments: _metadataStringList(route.contribution.metadata, 'arguments'),
      workingDirectory: _metadataString(
        route.contribution.metadata,
        'workingDirectory',
      ),
      environment: _metadataStringMap(
        route.contribution.metadata,
        'environment',
      ),
      dependsOn: _metadataStringList(route.contribution.metadata, 'dependsOn'),
      group: _metadataString(route.contribution.metadata, 'group'),
      terminalProfileId: _metadataString(
        route.contribution.metadata,
        'terminalProfileId',
      ),
      background: route.contribution.metadata['background'] as bool? ?? false,
      metadata: <String, Object?>{
        ...route.contribution.metadata,
        'extensionId': route.extensionId,
        'contributionId': route.contribution.id,
        'source': 'extension-runtime-task-contribution',
      },
    );
    return ExtensionRuntimeTaskContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionRuntimeTaskContributionStatus.ready,
      message: 'Runtime task contribution ${route.contribution.id} is ready.',
      definition: definition,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionRuntimeTaskContributionStatus status;
  final String message;
  final RuntimeTaskDefinition? definition;

  bool get ready => status == ExtensionRuntimeTaskContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (definition != null) 'definition': definition!.toJson(),
    };
  }
}

class ExtensionRuntimeTaskContributionCatalog {
  const ExtensionRuntimeTaskContributionCatalog({required this.contributions});

  factory ExtensionRuntimeTaskContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionRuntimeTaskContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.runtimeTaskRegistry)
          .map(ExtensionRuntimeTaskContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionRuntimeTaskContribution> contributions;

  List<RuntimeTaskDefinition> get readyDefinitions {
    return contributions
        .map((contribution) => contribution.definition)
        .whereType<RuntimeTaskDefinition>()
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-runtime-task-contributions.v1',
      'contributionCount': contributions.length,
      'readyDefinitionCount': readyDefinitions.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}

RuntimeTaskKind _runtimeTaskKindFromMetadata(Map<String, Object?> metadata) {
  final value = _metadataString(metadata, 'kind');
  return switch (value) {
    'shell' => RuntimeTaskKind.shell,
    'build' => RuntimeTaskKind.build,
    'test' => RuntimeTaskKind.test,
    'debug' => RuntimeTaskKind.debug,
    'agent' => RuntimeTaskKind.agent,
    'toolchain' => RuntimeTaskKind.toolchain,
    _ => RuntimeTaskKind.run,
  };
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

List<String> _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .map((item) => item.trim())
      .toList(growable: false);
}

Map<String, String> _metadataStringMap(
  Map<String, Object?> metadata,
  String key,
) {
  final value = metadata[key];
  if (value is! Map) {
    return const <String, String>{};
  }
  return value.map((key, value) => MapEntry(key.toString(), value.toString()));
}
