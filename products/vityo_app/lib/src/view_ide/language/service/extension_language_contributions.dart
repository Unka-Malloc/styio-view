import '../../module_host/module_host.dart';
import 'language_service_foundation.dart';

enum ExtensionLanguageContributionStatus {
  ready,
  invalidRoute,
  missingProvider,
}

class ExtensionLanguageContribution {
  const ExtensionLanguageContribution({
    required this.extensionId,
    required this.contributionId,
    required this.target,
    required this.status,
    required this.message,
    this.entry,
  });

  factory ExtensionLanguageContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind !=
            ExtensionContributionRegistryKind.languageProviderRegistry) {
      return ExtensionLanguageContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionLanguageContributionStatus.invalidRoute,
        message:
            'Route ${route.contribution.id} is not a ready language route.',
      );
    }
    final providerId =
        _metadataString(route.contribution.metadata, 'providerId') ??
        route.contribution.id;
    if (providerId.trim().isEmpty) {
      return ExtensionLanguageContribution(
        extensionId: route.extensionId,
        contributionId: route.contribution.id,
        target: route.registryTargetId,
        status: ExtensionLanguageContributionStatus.missingProvider,
        message:
            'Language contribution ${route.contribution.id} has no provider id.',
      );
    }
    final entry = LanguageProviderRegistryManifestEntry(
      languageId:
          _metadataString(route.contribution.metadata, 'languageId') ?? 'styio',
      providerId: providerId,
      displayName:
          _metadataString(route.contribution.metadata, 'displayName') ??
          route.contribution.title ??
          route.contribution.id,
      priority: _metadataInt(route.contribution.metadata, 'priority'),
      capabilities: _metadataStringList(
        route.contribution.metadata,
        'capabilities',
      ),
    );
    return ExtensionLanguageContribution(
      extensionId: route.extensionId,
      contributionId: route.contribution.id,
      target: route.registryTargetId,
      status: ExtensionLanguageContributionStatus.ready,
      message: 'Language contribution ${route.contribution.id} is ready.',
      entry: entry,
    );
  }

  final String extensionId;
  final String contributionId;
  final String target;
  final ExtensionLanguageContributionStatus status;
  final String message;
  final LanguageProviderRegistryManifestEntry? entry;

  bool get ready => status == ExtensionLanguageContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'contributionId': contributionId,
      'target': target,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (entry != null) 'entry': entry!.toJson(),
    };
  }
}

class ExtensionLanguageContributionCatalog {
  const ExtensionLanguageContributionCatalog({required this.contributions});

  factory ExtensionLanguageContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionLanguageContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.languageProviderRegistry)
          .map(ExtensionLanguageContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionLanguageContribution> contributions;

  List<LanguageProviderRegistryManifestEntry> get readyEntries {
    return contributions
        .map((contribution) => contribution.entry)
        .whereType<LanguageProviderRegistryManifestEntry>()
        .toList(growable: false);
  }

  LanguageProviderRegistryManifest toManifest() {
    return LanguageProviderRegistryManifest(entries: readyEntries);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-language-contributions.v1',
      'contributionCount': contributions.length,
      'readyEntryCount': readyEntries.length,
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

int _metadataInt(Map<String, Object?> metadata, String key) {
  final value = metadata[key];
  return value is int ? value : 0;
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
