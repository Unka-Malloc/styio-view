import '../module_host/module_host.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';

enum ExtensionAgentProviderContributionStatus {
  ready,
  invalidRoute,
  missingKind,
}

class ExtensionAgentProviderContribution {
  const ExtensionAgentProviderContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.manifest,
  });

  factory ExtensionAgentProviderContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.agentProviderRegistry) {
      return ExtensionAgentProviderContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionAgentProviderContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready agent provider route.',
      );
    }
    final kind = _agentProviderKindFromMetadata(route.contribution.metadata);
    if (kind == null) {
      return ExtensionAgentProviderContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionAgentProviderContributionStatus.missingKind,
        message:
            'Agent provider contribution ${route.contribution.id} does not declare metadata.kind.',
      );
    }
    final providerId =
        _metadataString(route.contribution.metadata, 'providerId') ??
        route.contribution.id;
    final manifest = AgentProviderRegistrationManifest(
      providerId: providerId,
      displayName:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          providerId,
      kind: kind,
      priority: route.contribution.metadata['priority'] as int? ?? 0,
      supportsCodePatch:
          route.contribution.metadata['supportsCodePatch'] as bool? ?? false,
      supportedRoutes: _metadataStringList(
        route.contribution.metadata,
        'supportedRoutes',
      ),
      supportedProtocols: _metadataStringList(
        route.contribution.metadata,
        'supportedProtocols',
      ),
      capabilities: _metadataStringList(
        route.contribution.metadata,
        'capabilities',
      ),
    );
    return ExtensionAgentProviderContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionAgentProviderContributionStatus.ready,
      message: 'Agent provider contribution ${route.contribution.id} is ready.',
      manifest: manifest,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionAgentProviderContributionStatus status;
  final String message;
  final AgentProviderRegistrationManifest? manifest;

  bool get ready => status == ExtensionAgentProviderContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (manifest != null) 'manifest': manifest!.toJson(),
    };
  }
}

class ExtensionAgentProviderContributionCatalog {
  const ExtensionAgentProviderContributionCatalog({
    required this.contributions,
  });

  factory ExtensionAgentProviderContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionAgentProviderContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.agentProviderRegistry)
          .where((route) => route.registryTargetId == 'agent.providers')
          .map(ExtensionAgentProviderContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionAgentProviderContribution> contributions;

  List<AgentProviderRegistrationManifest> get readyManifests {
    return contributions
        .map((contribution) => contribution.manifest)
        .whereType<AgentProviderRegistrationManifest>()
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-agent-provider-contributions.v1',
      'contributionCount': contributions.length,
      'readyProviderCount': readyManifests.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}

AgentProviderKind? _agentProviderKindFromMetadata(
  Map<String, Object?> metadata,
) {
  return switch (_metadataString(metadata, 'kind')) {
    'cloud_openai_compatible' => AgentProviderKind.cloudOpenAICompatible,
    'local_bridge' => AgentProviderKind.localBridge,
    'local_only_fallback' => AgentProviderKind.localOnlyFallback,
    _ => null,
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
