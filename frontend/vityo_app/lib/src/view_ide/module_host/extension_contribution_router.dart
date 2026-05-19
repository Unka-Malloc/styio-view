import 'extension_manifest_contract.dart';

enum ExtensionContributionRouteStatus { ready, unsupported, invalid }

enum ExtensionContributionRegistryKind {
  commandRegistry,
  languageProviderRegistry,
  debugAdapterRegistry,
  runtimeTaskRegistry,
  viewRegistry,
  agentProviderRegistry,
  toolchainCatalog,
  themeRegistry,
}

extension ExtensionContributionRegistryKindX
    on ExtensionContributionRegistryKind {
  String get wireValue => switch (this) {
    ExtensionContributionRegistryKind.commandRegistry => 'command-registry',
    ExtensionContributionRegistryKind.languageProviderRegistry =>
      'language-provider-registry',
    ExtensionContributionRegistryKind.debugAdapterRegistry =>
      'debug-adapter-registry',
    ExtensionContributionRegistryKind.runtimeTaskRegistry =>
      'runtime-task-registry',
    ExtensionContributionRegistryKind.viewRegistry => 'view-registry',
    ExtensionContributionRegistryKind.agentProviderRegistry =>
      'agent-provider-registry',
    ExtensionContributionRegistryKind.toolchainCatalog => 'toolchain-catalog',
    ExtensionContributionRegistryKind.themeRegistry => 'theme-registry',
  };
}

class ExtensionContributionRoute {
  const ExtensionContributionRoute({
    required this.extensionId,
    required this.contribution,
    required this.registryKind,
    required this.registryTargetId,
    required this.status,
    required this.message,
  });

  final String extensionId;
  final ExtensionContributionPoint contribution;
  final ExtensionContributionRegistryKind registryKind;
  final String registryTargetId;
  final ExtensionContributionRouteStatus status;
  final String message;

  bool get ready => status == ExtensionContributionRouteStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contribution': contribution.toJson(),
      'registryKind': registryKind.wireValue,
      'registryTargetId': registryTargetId,
      'status': status.name,
      'message': message,
      'ready': ready,
    };
  }
}

class ExtensionContributionRouteManifest {
  const ExtensionContributionRouteManifest({required this.routes});

  final List<ExtensionContributionRoute> routes;

  List<ExtensionContributionRoute> get readyRoutes {
    return routes.where((route) => route.ready).toList(growable: false);
  }

  List<ExtensionContributionRoute> routesFor(
    ExtensionContributionRegistryKind registryKind,
  ) {
    return routes
        .where((route) => route.registryKind == registryKind)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'routeCount': routes.length,
      'readyRouteCount': readyRoutes.length,
      'routes': routes.map((route) => route.toJson()).toList(growable: false),
    };
  }
}

class ExtensionContributionRouter {
  const ExtensionContributionRouter();

  ExtensionContributionRouteManifest routeRegistry(
    ExtensionManifestRegistry registry,
  ) {
    return ExtensionContributionRouteManifest(
      routes: registry
          .list()
          .expand(
            (manifest) => manifest.contributions.map(
              (contribution) => routeContribution(
                extensionId: manifest.extensionId,
                contribution: contribution,
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  ExtensionContributionRoute routeContribution({
    required String extensionId,
    required ExtensionContributionPoint contribution,
  }) {
    if (!contribution.valid) {
      return ExtensionContributionRoute(
        extensionId: extensionId,
        contribution: contribution,
        registryKind: _registryKindFor(contribution.kind),
        registryTargetId: contribution.target,
        status: ExtensionContributionRouteStatus.invalid,
        message: 'Extension contribution ${contribution.id} is invalid.',
      );
    }
    return ExtensionContributionRoute(
      extensionId: extensionId,
      contribution: contribution,
      registryKind: _registryKindFor(contribution.kind),
      registryTargetId: contribution.target,
      status: ExtensionContributionRouteStatus.ready,
      message:
          'Route ${contribution.kind.wireValue} contribution '
          '${contribution.id} to ${contribution.target}.',
    );
  }

  ExtensionContributionRegistryKind _registryKindFor(
    ExtensionContributionKind kind,
  ) {
    return switch (kind) {
      ExtensionContributionKind.command =>
        ExtensionContributionRegistryKind.commandRegistry,
      ExtensionContributionKind.language =>
        ExtensionContributionRegistryKind.languageProviderRegistry,
      ExtensionContributionKind.debugger =>
        ExtensionContributionRegistryKind.debugAdapterRegistry,
      ExtensionContributionKind.task =>
        ExtensionContributionRegistryKind.runtimeTaskRegistry,
      ExtensionContributionKind.view =>
        ExtensionContributionRegistryKind.viewRegistry,
      ExtensionContributionKind.agent =>
        ExtensionContributionRegistryKind.agentProviderRegistry,
      ExtensionContributionKind.toolchain =>
        ExtensionContributionRegistryKind.toolchainCatalog,
      ExtensionContributionKind.theme =>
        ExtensionContributionRegistryKind.themeRegistry,
    };
  }
}
