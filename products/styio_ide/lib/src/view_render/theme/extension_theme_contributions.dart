import '../../view_ide/module_host/module_host.dart';
import '../../view_ide/environment/configuration/vityo_theme_override.dart';

enum ExtensionThemeContributionStatus { ready, invalidRoute, missingPalette }

class ExtensionThemeContribution {
  const ExtensionThemeContribution({
    required this.extensionId,
    required this.themeId,
    required this.target,
    required this.title,
    required this.status,
    required this.message,
    this.override,
  });

  factory ExtensionThemeContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind != ExtensionContributionRegistryKind.themeRegistry) {
      return ExtensionThemeContribution(
        extensionId: route.extensionId,
        themeId: route.contribution.id,
        target: route.registryTargetId,
        title: route.contribution.title ?? route.contribution.id,
        status: ExtensionThemeContributionStatus.invalidRoute,
        message: 'Route ${route.contribution.id} is not a ready theme route.',
      );
    }
    final override = VityoThemeOverride.fromJson(route.contribution.metadata);
    if (override.toJson().isEmpty) {
      return ExtensionThemeContribution(
        extensionId: route.extensionId,
        themeId: route.contribution.id,
        target: route.registryTargetId,
        title: route.contribution.title ?? route.contribution.id,
        status: ExtensionThemeContributionStatus.missingPalette,
        message:
            'Theme contribution ${route.contribution.id} does not declare palette colors.',
      );
    }
    return ExtensionThemeContribution(
      extensionId: route.extensionId,
      themeId: route.contribution.id,
      target: route.registryTargetId,
      title: route.contribution.title ?? route.contribution.id,
      status: ExtensionThemeContributionStatus.ready,
      message: 'Theme contribution ${route.contribution.id} is ready.',
      override: override,
    );
  }

  final String extensionId;
  final String themeId;
  final String target;
  final String title;
  final ExtensionThemeContributionStatus status;
  final String message;
  final VityoThemeOverride? override;

  bool get ready => status == ExtensionThemeContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'themeId': themeId,
      'target': target,
      'title': title,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (override != null) 'override': override!.toJson(),
    };
  }
}

class ExtensionThemeContributionCatalog {
  const ExtensionThemeContributionCatalog({required this.contributions});

  factory ExtensionThemeContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionThemeContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.themeRegistry)
          .map(ExtensionThemeContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionThemeContribution> contributions;

  List<ExtensionThemeContribution> get readyThemes {
    return contributions
        .where((contribution) => contribution.ready)
        .toList(growable: false);
  }

  ExtensionThemeContribution? lookup(String themeId) {
    for (final contribution in contributions) {
      if (contribution.themeId == themeId) {
        return contribution;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-theme-contributions.v1',
      'contributionCount': contributions.length,
      'readyThemeCount': readyThemes.length,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
    };
  }
}
