import '../../view_ide/module_host/module_host.dart';

enum ExtensionViewContributionStatus { ready, invalidRoute, missingViewKind }

class ExtensionViewContribution {
  const ExtensionViewContribution({
    required this.extensionId,
    required this.viewId,
    required this.target,
    required this.title,
    required this.status,
    required this.message,
    this.viewKind,
    this.location,
    this.icon,
    this.order = 0,
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionViewContribution.fromRoute(
    ExtensionContributionRoute route,
  ) {
    if (!route.ready ||
        route.registryKind != ExtensionContributionRegistryKind.viewRegistry) {
      return ExtensionViewContribution(
        extensionId: route.extensionId,
        viewId: route.contribution.id,
        target: route.registryTargetId,
        title: route.contribution.title ?? route.contribution.id,
        status: ExtensionViewContributionStatus.invalidRoute,
        message: 'Route ${route.contribution.id} is not a ready view route.',
      );
    }
    final viewKind = _metadataString(route.contribution.metadata, 'viewKind');
    if (viewKind == null) {
      return ExtensionViewContribution(
        extensionId: route.extensionId,
        viewId: route.contribution.id,
        target: route.registryTargetId,
        title: route.contribution.title ?? route.contribution.id,
        status: ExtensionViewContributionStatus.missingViewKind,
        message:
            'View contribution ${route.contribution.id} does not declare metadata.viewKind.',
      );
    }
    return ExtensionViewContribution(
      extensionId: route.extensionId,
      viewId: route.contribution.id,
      target: route.registryTargetId,
      title: route.contribution.title ?? route.contribution.id,
      status: ExtensionViewContributionStatus.ready,
      message: 'View contribution ${route.contribution.id} is ready.',
      viewKind: viewKind,
      location: _metadataString(route.contribution.metadata, 'location'),
      icon: _metadataString(route.contribution.metadata, 'icon'),
      order: route.contribution.metadata['order'] as int? ?? 0,
      metadata: route.contribution.metadata,
    );
  }

  final String extensionId;
  final String viewId;
  final String target;
  final String title;
  final ExtensionViewContributionStatus status;
  final String message;
  final String? viewKind;
  final String? location;
  final String? icon;
  final int order;
  final Map<String, Object?> metadata;

  bool get ready => status == ExtensionViewContributionStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'viewId': viewId,
      'target': target,
      'title': title,
      'status': status.name,
      'message': message,
      'ready': ready,
      if (viewKind != null) 'viewKind': viewKind,
      if (location != null) 'location': location,
      if (icon != null) 'icon': icon,
      'order': order,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionViewContributionCatalog {
  const ExtensionViewContributionCatalog({required this.contributions});

  factory ExtensionViewContributionCatalog.fromRoutes(
    ExtensionContributionRouteManifest routes,
  ) {
    return ExtensionViewContributionCatalog(
      contributions: routes
          .routesFor(ExtensionContributionRegistryKind.viewRegistry)
          .map(ExtensionViewContribution.fromRoute)
          .toList(growable: false),
    );
  }

  final List<ExtensionViewContribution> contributions;

  List<ExtensionViewContribution> get readyViews {
    final views = contributions
        .where((contribution) => contribution.ready)
        .toList(growable: false);
    views.sort((left, right) {
      final orderCompare = left.order.compareTo(right.order);
      if (orderCompare != 0) {
        return orderCompare;
      }
      return left.viewId.compareTo(right.viewId);
    });
    return views;
  }

  List<ExtensionViewContribution> viewsForLocation(String location) {
    return readyViews
        .where((view) => view.location == location)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schema': 'vityo.extension-view-contributions.v1',
      'contributionCount': contributions.length,
      'readyViewCount': readyViews.length,
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
