import '../platform/platform_target.dart';

enum AgentProviderRoute {
  desktopLocalBridge,
  androidCloudWithLocalBridge,
  iosCloudOnly,
  webHosted,
  unresolved,
}

extension AgentProviderRouteX on AgentProviderRoute {
  String get wireValue {
    switch (this) {
      case AgentProviderRoute.desktopLocalBridge:
        return 'desktop-local-bridge';
      case AgentProviderRoute.androidCloudWithLocalBridge:
        return 'android-cloud-local-bridge';
      case AgentProviderRoute.iosCloudOnly:
        return 'ios-cloud-only';
      case AgentProviderRoute.webHosted:
        return 'web-hosted';
      case AgentProviderRoute.unresolved:
        return 'unresolved';
    }
  }

  bool get allowsLocalBridge {
    switch (this) {
      case AgentProviderRoute.desktopLocalBridge:
      case AgentProviderRoute.androidCloudWithLocalBridge:
        return true;
      case AgentProviderRoute.iosCloudOnly:
      case AgentProviderRoute.webHosted:
      case AgentProviderRoute.unresolved:
        return false;
    }
  }
}

AgentProviderRoute agentProviderRouteForPlatform(
  PlatformTarget platformTarget,
) {
  switch (platformTarget) {
    case PlatformTarget.ios:
      return AgentProviderRoute.iosCloudOnly;
    case PlatformTarget.web:
      return AgentProviderRoute.webHosted;
    case PlatformTarget.android:
      return AgentProviderRoute.androidCloudWithLocalBridge;
    case PlatformTarget.windows:
    case PlatformTarget.linux:
    case PlatformTarget.macos:
      return AgentProviderRoute.desktopLocalBridge;
    case PlatformTarget.unknown:
      return AgentProviderRoute.unresolved;
  }
}

class AgentProviderEndpoint {
  const AgentProviderEndpoint({
    required this.route,
    required this.baseUrl,
    required this.model,
    this.apiKeyEnvironmentName = 'OPENAI_API_KEY',
    this.protocol = 'openai-compatible',
  });

  final AgentProviderRoute route;
  final String baseUrl;
  final String model;
  final String apiKeyEnvironmentName;
  final String protocol;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'route': route.wireValue,
      'baseUrl': baseUrl,
      'model': model,
      'apiKeyEnvironmentName': apiKeyEnvironmentName,
      'protocol': protocol,
    };
  }

  factory AgentProviderEndpoint.fromJson(Map<String, Object?> json) {
    return AgentProviderEndpoint(
      route: _agentProviderRouteFromWireValue(json['route'] as String?),
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      apiKeyEnvironmentName:
          json['apiKeyEnvironmentName'] as String? ?? 'OPENAI_API_KEY',
      protocol: json['protocol'] as String? ?? 'openai-compatible',
    );
  }
}

class AgentPromptProfile {
  const AgentPromptProfile({
    required this.profileId,
    required this.displayName,
    required this.systemPrompt,
    required this.endpoint,
    this.contextChannels = const <String>[
      'file',
      'selection',
      'diagnostics',
      'runtime',
    ],
  });

  final String profileId;
  final String displayName;
  final String systemPrompt;
  final AgentProviderEndpoint endpoint;
  final List<String> contextChannels;

  bool get allowsLocalBridge => endpoint.route.allowsLocalBridge;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'displayName': displayName,
      'systemPrompt': systemPrompt,
      'endpoint': endpoint.toJson(),
      'contextChannels': contextChannels,
    };
  }

  factory AgentPromptProfile.fromJson(Map<String, Object?> json) {
    return AgentPromptProfile(
      profileId: json['profileId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      endpoint: AgentProviderEndpoint.fromJson(
        Map<String, Object?>.from(json['endpoint'] as Map? ?? const {}),
      ),
      contextChannels: (json['contextChannels'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false),
    );
  }

  factory AgentPromptProfile.defaultForPlatform(PlatformTarget platformTarget) {
    final route = agentProviderRouteForPlatform(platformTarget);
    return AgentPromptProfile(
      profileId: 'default-${platformTarget.wireValue}',
      displayName: '${platformTarget.label} Default',
      systemPrompt:
          'Use the current file, selection, diagnostics, and runtime context without crossing adapter boundaries.',
      endpoint: AgentProviderEndpoint(
        route: route,
        baseUrl: route == AgentProviderRoute.webHosted
            ? '/api/styio-agent/v1'
            : 'https://api.openai.com/v1',
        model: 'gpt-5.4',
      ),
    );
  }
}

AgentProviderRoute _agentProviderRouteFromWireValue(String? value) {
  for (final route in AgentProviderRoute.values) {
    if (route.wireValue == value) {
      return route;
    }
  }
  return AgentProviderRoute.unresolved;
}
