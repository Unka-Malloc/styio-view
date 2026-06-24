import '../module_host/module_host.dart';
import 'debug_launch_contract.dart';

enum ExtensionDebugContributionStatus { ready, invalidRoute, missingExecutable }

class ExtensionDebugContribution {
  const ExtensionDebugContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.profile,
  });

  factory ExtensionDebugContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.debugAdapterRegistry) {
      return ExtensionDebugContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionDebugContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready debugger route.',
      );
    }
    final executablePath =
        _metadataString(
          route.contribution.metadata,
          'debuggerExecutablePath',
        ) ??
        _metadataString(route.contribution.metadata, 'executablePath');
    if (executablePath == null) {
      return ExtensionDebugContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionDebugContributionStatus.missingExecutable,
        message:
            'Debugger contribution ${route.contribution.id} does not declare metadata.executablePath.',
      );
    }
    final debuggerId =
        _metadataString(route.contribution.metadata, 'debuggerId') ??
        route.contribution.id;
    final debuggerLabel =
        _metadataString(route.contribution.metadata, 'debuggerLabel') ??
        route.contribution.title ??
        route.contribution.id;
    final programPath = _metadataString(
      route.contribution.metadata,
      'programPath',
    );
    final configuration = DebugLaunchConfiguration(
      readiness: programPath == null
          ? DebugLaunchReadiness.missingProgram
          : DebugLaunchReadiness.ready,
      reason: programPath == null
          ? 'Debugger contribution $debuggerId is missing metadata.programPath.'
          : 'Debugger contribution $debuggerId is ready.',
      debuggerId: debuggerId,
      debuggerLabel: debuggerLabel,
      debuggerExecutablePath: executablePath,
      debuggerArguments: _metadataStringList(
        route.contribution.metadata,
        'debuggerArguments',
      ),
      adapterProtocol:
          _metadataString(route.contribution.metadata, 'adapterProtocol') ??
          'dap',
      programPath: programPath,
      cwd: _metadataString(route.contribution.metadata, 'cwd') ?? '',
      arguments: _metadataStringList(route.contribution.metadata, 'arguments'),
      environment: _metadataStringMap(
        route.contribution.metadata,
        'environment',
      ),
      stopOnEntry: route.contribution.metadata['stopOnEntry'] == true,
    );
    return ExtensionDebugContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionDebugContributionStatus.ready,
      message: 'Debugger contribution ${route.contribution.id} is ready.',
      profile: DebugLaunchProfile.fromConfiguration(
        id: debuggerId,
        displayName: debuggerLabel,
        configuration: configuration,
        metadata: <String, Object?>{
          ...route.contribution.metadata,
          'extensionId': route.extensionId,
          'contributionId': route.contribution.id,
          'source': 'extension-debug-contribution',
        },
      ),
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionDebugContributionStatus status;
  final String message;
  final DebugLaunchProfile? profile;

  bool get ready => status == ExtensionDebugContributionStatus.ready;
  bool get runnable => profile?.configuration.ready ?? false;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      'runnable': runnable,
      if (profile != null) 'profile': profile!.toJson(),
    };
  }
}

class ExtensionDebugContributionCatalog {
  const ExtensionDebugContributionCatalog({required this.contributions});

  factory ExtensionDebugContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionDebugContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.debugAdapterRegistry)
          .map(ExtensionDebugContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionDebugContribution> contributions;

  List<DebugLaunchProfile> get profiles {
    return contributions
        .map((contribution) => contribution.profile)
        .whereType<DebugLaunchProfile>()
        .toList(growable: false);
  }

  List<DebugLaunchProfile> get runnableProfiles {
    return profiles
        .where((profile) => profile.configuration.ready)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-debug-contributions.v1',
      'contributionCount': contributions.length,
      'profileCount': profiles.length,
      'runnableProfileCount': runnableProfiles.length,
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

List<String> _metadataStringList(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
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
  return Map<String, String>.unmodifiable(
    value.map(
      (key, value) =>
          MapEntry<String, String>(key.toString(), value.toString()),
    ),
  );
}
