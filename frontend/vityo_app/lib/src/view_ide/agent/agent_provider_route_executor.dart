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

class AgentProviderRouteExecutor {
  const AgentProviderRouteExecutor({this.localServiceManager});

  final LocalServiceManager? localServiceManager;

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
