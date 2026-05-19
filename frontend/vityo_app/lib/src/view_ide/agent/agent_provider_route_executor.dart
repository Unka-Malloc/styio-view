import '../environment/system_compatibility/local_service/local_service.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';

enum AgentProviderExecutionRouteKind { cloud, localBridge, blocked }

extension AgentProviderExecutionRouteKindX on AgentProviderExecutionRouteKind {
  String get wireValue {
    return switch (this) {
      AgentProviderExecutionRouteKind.cloud => 'cloud',
      AgentProviderExecutionRouteKind.localBridge => 'local_bridge',
      AgentProviderExecutionRouteKind.blocked => 'blocked',
    };
  }
}

enum AgentProviderExecutionBlockReason {
  unsupportedProtocol,
  missingEndpoint,
  unresolvedRoute,
  localBridgeUnavailable,
  localBridgeNotAllowed,
}

extension AgentProviderExecutionBlockReasonX
    on AgentProviderExecutionBlockReason {
  String get wireValue {
    return switch (this) {
      AgentProviderExecutionBlockReason.unsupportedProtocol =>
        'unsupported_protocol',
      AgentProviderExecutionBlockReason.missingEndpoint => 'missing_endpoint',
      AgentProviderExecutionBlockReason.unresolvedRoute => 'unresolved_route',
      AgentProviderExecutionBlockReason.localBridgeUnavailable =>
        'local_bridge_unavailable',
      AgentProviderExecutionBlockReason.localBridgeNotAllowed =>
        'local_bridge_not_allowed',
    };
  }
}

enum AgentProviderCredentialReadiness { notReferenced, available, unavailable }

extension AgentProviderCredentialReadinessX on AgentProviderCredentialReadiness {
  String get wireValue {
    return switch (this) {
      AgentProviderCredentialReadiness.notReferenced => 'not_referenced',
      AgentProviderCredentialReadiness.available => 'available',
      AgentProviderCredentialReadiness.unavailable => 'unavailable',
    };
  }
}

enum AgentProviderExecutionResolutionStatus {
  ready,
  fallbackReady,
  blocked,
}

extension AgentProviderExecutionResolutionStatusX
    on AgentProviderExecutionResolutionStatus {
  String get wireValue {
    return switch (this) {
      AgentProviderExecutionResolutionStatus.ready => 'ready',
      AgentProviderExecutionResolutionStatus.fallbackReady => 'fallback_ready',
      AgentProviderExecutionResolutionStatus.blocked => 'blocked',
    };
  }
}

class AgentProviderExecutionPlan {
  const AgentProviderExecutionPlan({
    required this.routeKind,
    required this.providerKind,
    required this.route,
    required this.endpointBaseUrl,
    this.blockReason,
    this.recoveryHint,
  });

  final AgentProviderExecutionRouteKind routeKind;
  final AgentProviderKind providerKind;
  final AgentProviderRoute route;
  final String endpointBaseUrl;
  final AgentProviderExecutionBlockReason? blockReason;
  final String? recoveryHint;

  bool get executable => routeKind != AgentProviderExecutionRouteKind.blocked;
  bool get usesLocalBridge =>
      routeKind == AgentProviderExecutionRouteKind.localBridge;
  bool get usesCloud => routeKind == AgentProviderExecutionRouteKind.cloud;

  String get adapterId {
    return switch (routeKind) {
      AgentProviderExecutionRouteKind.localBridge =>
        'openai-compatible-local-bridge',
      AgentProviderExecutionRouteKind.cloud => 'openai-compatible-cloud',
      AgentProviderExecutionRouteKind.blocked => 'local-only-fallback',
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'routeKind': routeKind.wireValue,
      'providerKind': providerKind.wireValue,
      'route': route.wireValue,
      'endpointBaseUrl': endpointBaseUrl,
      'executable': executable,
      'usesLocalBridge': usesLocalBridge,
      'usesCloud': usesCloud,
      if (blockReason != null) 'blockReason': blockReason!.wireValue,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

class AgentProviderEndpointReadiness {
  const AgentProviderEndpointReadiness({
    required this.endpointIndex,
    required this.fallback,
    required this.endpoint,
    required this.plan,
    required this.credentialReadiness,
  });

  final int endpointIndex;
  final bool fallback;
  final AgentProviderEndpoint endpoint;
  final AgentProviderExecutionPlan plan;
  final AgentProviderCredentialReadiness credentialReadiness;

  bool get executable {
    return plan.executable &&
        credentialReadiness != AgentProviderCredentialReadiness.unavailable;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'endpointIndex': endpointIndex,
      'fallback': fallback,
      'endpoint': endpoint.toJson(),
      'plan': plan.toJson(),
      'credentialReadiness': credentialReadiness.wireValue,
      'executable': executable,
    };
  }
}

class AgentProviderExecutionResolution {
  const AgentProviderExecutionResolution({
    required this.profileId,
    required this.status,
    required this.endpoints,
    this.selectedEndpointIndex,
  });

  final String profileId;
  final AgentProviderExecutionResolutionStatus status;
  final List<AgentProviderEndpointReadiness> endpoints;
  final int? selectedEndpointIndex;

  AgentProviderEndpointReadiness? get selectedEndpoint {
    final selected = selectedEndpointIndex;
    if (selected == null) {
      return null;
    }
    for (final endpoint in endpoints) {
      if (endpoint.endpointIndex == selected) {
        return endpoint;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'status': status.wireValue,
      if (selectedEndpointIndex != null)
        'selectedEndpointIndex': selectedEndpointIndex,
      'endpoints': endpoints
          .map((endpoint) => endpoint.toJson())
          .toList(growable: false),
    };
  }
}

typedef AgentProviderCredentialAvailability =
    Future<bool> Function(AgentProviderEndpoint endpoint);

class AgentProviderRouteExecutor {
  const AgentProviderRouteExecutor({this.localServiceManager});

  final LocalServiceManager? localServiceManager;

  Future<AgentProviderExecutionResolution> resolve(
    AgentPromptProfile profile, {
    AgentProviderCredentialAvailability? credentialAvailable,
  }) async {
    final candidateEndpoints = <AgentProviderEndpoint>[
      profile.endpoint,
      ...profile.fallbackEndpoints,
    ];
    final endpoints = <AgentProviderEndpointReadiness>[];
    int? selectedEndpointIndex;
    for (var index = 0; index < candidateEndpoints.length; index += 1) {
      final endpoint = candidateEndpoints[index];
      final candidateProfile = profile.copyWith(endpoint: endpoint);
      final readiness = AgentProviderEndpointReadiness(
        endpointIndex: index,
        fallback: index > 0,
        endpoint: endpoint,
        plan: planFor(candidateProfile),
        credentialReadiness: await _credentialReadiness(
          endpoint,
          credentialAvailable,
        ),
      );
      endpoints.add(readiness);
      if (selectedEndpointIndex == null && readiness.executable) {
        selectedEndpointIndex = index;
      }
    }
    return AgentProviderExecutionResolution(
      profileId: profile.profileId,
      status: selectedEndpointIndex == null
          ? AgentProviderExecutionResolutionStatus.blocked
          : selectedEndpointIndex == 0
          ? AgentProviderExecutionResolutionStatus.ready
          : AgentProviderExecutionResolutionStatus.fallbackReady,
      endpoints: endpoints,
      selectedEndpointIndex: selectedEndpointIndex,
    );
  }

  AgentProviderExecutionPlan planFor(AgentPromptProfile profile) {
    final endpoint = profile.endpoint;
    final protocol = endpoint.protocol.trim().toLowerCase();
    final baseUrl = endpoint.baseUrl.trim();
    if (protocol != 'openai-compatible') {
      return _blocked(
        endpoint,
        AgentProviderExecutionBlockReason.unsupportedProtocol,
        'Configure an OpenAI-compatible provider protocol before sending agent requests.',
      );
    }
    if (baseUrl.isEmpty) {
      return _blocked(
        endpoint,
        AgentProviderExecutionBlockReason.missingEndpoint,
        'Configure a cloud endpoint or a loopback local bridge endpoint.',
      );
    }
    if (endpoint.route == AgentProviderRoute.unresolved) {
      return _blocked(
        endpoint,
        AgentProviderExecutionBlockReason.unresolvedRoute,
        'Select a supported agent provider route for this platform.',
      );
    }

    final loopbackEndpoint = _isLoopbackEndpoint(baseUrl);
    if (loopbackEndpoint && !endpoint.route.allowsLocalBridge) {
      return _blocked(
        endpoint,
        AgentProviderExecutionBlockReason.localBridgeNotAllowed,
        'This platform route only allows cloud execution. Use a cloud provider endpoint.',
      );
    }
    if (loopbackEndpoint) {
      if (!_localBridgeAvailable) {
        return _blocked(
          endpoint,
          AgentProviderExecutionBlockReason.localBridgeUnavailable,
          'Local bridge execution requires loopback local service support on this platform.',
        );
      }
      return AgentProviderExecutionPlan(
        routeKind: AgentProviderExecutionRouteKind.localBridge,
        providerKind: AgentProviderKind.localBridge,
        route: endpoint.route,
        endpointBaseUrl: baseUrl,
      );
    }
    return AgentProviderExecutionPlan(
      routeKind: AgentProviderExecutionRouteKind.cloud,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
      route: endpoint.route,
      endpointBaseUrl: baseUrl,
    );
  }

  Future<AgentProviderCredentialReadiness> _credentialReadiness(
    AgentProviderEndpoint endpoint,
    AgentProviderCredentialAvailability? credentialAvailable,
  ) async {
    if (endpoint.credentialReference == null) {
      return AgentProviderCredentialReadiness.notReferenced;
    }
    if (credentialAvailable == null) {
      return AgentProviderCredentialReadiness.available;
    }
    return await credentialAvailable(endpoint)
        ? AgentProviderCredentialReadiness.available
        : AgentProviderCredentialReadiness.unavailable;
  }

  bool get _localBridgeAvailable {
    final manager = localServiceManager;
    return manager != null && manager.compatibility.supportsLoopbackHttpServer;
  }

  AgentProviderExecutionPlan _blocked(
    AgentProviderEndpoint endpoint,
    AgentProviderExecutionBlockReason reason,
    String recoveryHint,
  ) {
    return AgentProviderExecutionPlan(
      routeKind: AgentProviderExecutionRouteKind.blocked,
      providerKind: AgentProviderKind.localOnlyFallback,
      route: endpoint.route,
      endpointBaseUrl: endpoint.baseUrl.trim(),
      blockReason: reason,
      recoveryHint: recoveryHint,
    );
  }
}

bool _isLoopbackEndpoint(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri == null) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
