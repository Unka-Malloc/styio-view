import '../module_host/module_host.dart';
import 'toolchain_catalog.dart';

enum ExtensionToolchainContributionStatus {
  ready,
  invalidRoute,
  missingExecutable,
}

class ExtensionToolchainContribution {
  const ExtensionToolchainContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.descriptor,
  });

  factory ExtensionToolchainContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.toolchainCatalog) {
      return ExtensionToolchainContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionToolchainContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready toolchain route.',
      );
    }
    final executablePath = _metadataString(
      route.contribution.metadata,
      'executablePath',
    );
    if (executablePath == null) {
      return ExtensionToolchainContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionToolchainContributionStatus.missingExecutable,
        message:
            'Toolchain contribution ${route.contribution.id} does not declare metadata.executablePath.',
      );
    }
    final descriptor = ToolchainDescriptor(
      id:
          _metadataString(route.contribution.metadata, 'toolchainId') ??
          route.contribution.id,
      kind: toolchainKindFromWireValue(
        _metadataString(route.contribution.metadata, 'kind'),
      ),
      displayName:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          route.contribution.id,
      executablePath: executablePath,
      version: _metadataString(route.contribution.metadata, 'version'),
      channel: _metadataString(route.contribution.metadata, 'channel'),
      metadata: <String, Object?>{
        ...route.contribution.metadata,
        'extensionId': route.extensionId,
        'contributionId': route.contribution.id,
        'source': 'extension-toolchain-contribution',
      },
    );
    return ExtensionToolchainContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionToolchainContributionStatus.ready,
      message: 'Toolchain contribution ${route.contribution.id} is ready.',
      descriptor: descriptor,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionToolchainContributionStatus status;
  final String message;
  final ToolchainDescriptor? descriptor;

  bool get ready => status == ExtensionToolchainContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (descriptor != null) 'descriptor': descriptor!.toJson(),
    };
  }
}

class ExtensionToolchainContributionCatalog {
  const ExtensionToolchainContributionCatalog({required this.contributions});

  factory ExtensionToolchainContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionToolchainContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.toolchainCatalog)
          .map(ExtensionToolchainContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionToolchainContribution> contributions;

  List<ToolchainDescriptor> get readyDescriptors {
    return contributions
        .map((contribution) => contribution.descriptor)
        .whereType<ToolchainDescriptor>()
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-toolchain-contributions.v1',
      'contributionCount': contributions.length,
      'readyDescriptorCount': readyDescriptors.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}

String? _metadataString(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}
