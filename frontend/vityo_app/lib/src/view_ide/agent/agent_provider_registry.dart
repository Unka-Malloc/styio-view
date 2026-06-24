import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_route_executor.dart';

typedef RegisteredAgentProviderAdapterCreator =
    Future<AgentProviderAdapter> Function(AgentPromptProfile profile);

enum AgentProviderSelectionStatus { ready, unsupportedProfile }

extension AgentProviderSelectionStatusX on AgentProviderSelectionStatus {
  String get wireValue {
    return switch (this) {
      AgentProviderSelectionStatus.ready => 'ready',
      AgentProviderSelectionStatus.unsupportedProfile => 'unsupported_profile',
    };
  }
}

class AgentProviderRegistration {
  const AgentProviderRegistration({
    required this.providerId,
    required this.displayName,
    required this.kind,
    required this.createAdapter,
    this.priority = 0,
    this.supportsCodePatch = false,
    this.supportedRoutes = const <String>[],
    this.supportedProtocols = const <String>[],
    this.capabilities = const <String>[],
  });

  final String providerId;
  final String displayName;
  final AgentProviderKind kind;
  final RegisteredAgentProviderAdapterCreator createAdapter;
  final int priority;
  final bool supportsCodePatch;
  final List<String> supportedRoutes;
  final List<String> supportedProtocols;
  final List<String> capabilities;

  bool supportsProfile(AgentPromptProfile profile) {
    final normalizedRoutes = _normalizedSet(supportedRoutes);
    final normalizedProtocols = _normalizedSet(supportedProtocols);
    final routeMatches =
        normalizedRoutes.isEmpty ||
        normalizedRoutes.contains(
          profile.endpoint.route.wireValue.trim().toLowerCase(),
        );
    final protocolMatches =
        normalizedProtocols.isEmpty ||
        normalizedProtocols.contains(
          profile.endpoint.protocol.trim().toLowerCase(),
        );
    return routeMatches && protocolMatches;
  }

  AgentProviderRegistrationManifest toManifest() {
    return AgentProviderRegistrationManifest(
      providerId: providerId,
      displayName: displayName,
      kind: kind,
      priority: priority,
      supportsCodePatch: supportsCodePatch,
      supportedRoutes: supportedRoutes,
      supportedProtocols: supportedProtocols,
      capabilities: capabilities,
    );
  }
}

class AgentProviderSelectionPlan {
  const AgentProviderSelectionPlan({
    required this.status,
    required this.route,
    required this.protocol,
    required this.requiresCredential,
    required this.candidates,
    this.selectedProvider,
    this.credentialReadiness,
    this.executionStatus,
    this.selectedEndpointIndex,
    this.message = '',
    this.todo = '',
  });

  final AgentProviderSelectionStatus status;
  final AgentProviderRoute route;
  final String protocol;
  final bool requiresCredential;
  final List<AgentProviderRegistrationManifest> candidates;
  final AgentProviderRegistrationManifest? selectedProvider;
  final AgentProviderCredentialReadiness? credentialReadiness;
  final AgentProviderExecutionResolutionStatus? executionStatus;
  final int? selectedEndpointIndex;
  final String message;
  final String todo;

  bool get ready => status == AgentProviderSelectionStatus.ready;
  bool get executable {
    return ready &&
        credentialReadiness != AgentProviderCredentialReadiness.unavailable &&
        executionStatus != AgentProviderExecutionResolutionStatus.blocked;
  }

  AgentProviderSelectionPlan withExecutionResolution(
    AgentProviderExecutionResolution resolution,
  ) {
    final selectedEndpoint = resolution.selectedEndpoint;
    final health = resolution.toHealthReport();
    return AgentProviderSelectionPlan(
      status: status,
      route: route,
      protocol: protocol,
      requiresCredential: requiresCredential,
      candidates: candidates,
      selectedProvider: selectedProvider,
      credentialReadiness: selectedEndpoint?.credentialReadiness,
      executionStatus: resolution.status,
      selectedEndpointIndex: resolution.selectedEndpointIndex,
      message: health.message,
      todo:
          selectedEndpoint?.credentialReadiness ==
              AgentProviderCredentialReadiness.unavailable
          ? 'Configure the referenced agent provider credential in Credential DataStore.'
          : todo.startsWith('Resolve this profile credential')
          ? ''
          : todo,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'route': route.wireValue,
      'protocol': protocol,
      'requiresCredential': requiresCredential,
      'ready': ready,
      'executable': executable,
      if (credentialReadiness != null)
        'credentialReadiness': credentialReadiness!.wireValue,
      if (executionStatus != null)
        'executionStatus': executionStatus!.wireValue,
      if (selectedEndpointIndex != null)
        'selectedEndpointIndex': selectedEndpointIndex,
      if (selectedProvider != null)
        'selectedProvider': selectedProvider!.toJson(),
      'candidateCount': candidates.length,
      'candidates': candidates
          .map((candidate) => candidate.toJson())
          .toList(growable: false),
      if (message.isNotEmpty) 'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class AgentProviderRegistry {
  AgentProviderRegistry({
    Iterable<AgentProviderRegistration> registrations =
        const <AgentProviderRegistration>[],
  }) {
    for (final registration in registrations) {
      register(registration);
    }
  }

  final Map<String, AgentProviderRegistration> _registrations =
      <String, AgentProviderRegistration>{};

  List<AgentProviderRegistration> get registrations {
    final values = _registrations.values.toList(growable: false);
    values.sort(_compareRegistrationPriority);
    return List<AgentProviderRegistration>.unmodifiable(values);
  }

  AgentProviderRegistry register(AgentProviderRegistration registration) {
    final providerId = registration.providerId.trim();
    if (providerId.isEmpty) {
      throw ArgumentError.value(
        registration.providerId,
        'providerId',
        'Provider id must not be empty.',
      );
    }
    _registrations[providerId] = registration;
    return this;
  }

  AgentProviderRegistration? resolve(AgentPromptProfile profile) {
    for (final registration in registrations) {
      if (registration.supportsProfile(profile)) {
        return registration;
      }
    }
    return null;
  }

  AgentProviderSelectionPlan selectionPlan(AgentPromptProfile profile) {
    final candidates = registrations
        .where((registration) => registration.supportsProfile(profile))
        .map((registration) => registration.toManifest())
        .toList(growable: false);
    final selectedProvider = candidates.isEmpty ? null : candidates.first;
    return AgentProviderSelectionPlan(
      status: selectedProvider == null
          ? AgentProviderSelectionStatus.unsupportedProfile
          : AgentProviderSelectionStatus.ready,
      route: profile.endpoint.route,
      protocol: profile.endpoint.protocol,
      requiresCredential: profile.endpoint.requiresCredential,
      selectedProvider: selectedProvider,
      candidates: List<AgentProviderRegistrationManifest>.unmodifiable(
        candidates,
      ),
      message: selectedProvider == null
          ? 'No agent provider registration supports this route and protocol.'
          : 'Agent provider registration is ready.',
      todo: selectedProvider == null
          ? 'Install or enable an agent provider contribution for this profile.'
          : profile.endpoint.requiresCredential
          ? 'Resolve this profile credential through Credential DataStore before sending.'
          : '',
    );
  }

  Future<AgentProviderAdapter> createAdapter(AgentPromptProfile profile) async {
    final registration = resolve(profile);
    if (registration == null) {
      throw StateError(
        'No agent provider registration supports route '
        '${profile.endpoint.route} and protocol ${profile.endpoint.protocol}.',
      );
    }
    return registration.createAdapter(profile);
  }

  AgentProviderRegistryManifest manifest() {
    return AgentProviderRegistryManifest(
      providers: registrations
          .map((registration) => registration.toManifest())
          .toList(growable: false),
    );
  }
}

class AgentProviderRegistryManifest {
  const AgentProviderRegistryManifest({required this.providers});

  final List<AgentProviderRegistrationManifest> providers;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providers': providers
          .map((provider) => provider.toJson())
          .toList(growable: false),
    };
  }
}

class AgentProviderRegistrationManifest {
  const AgentProviderRegistrationManifest({
    required this.providerId,
    required this.displayName,
    required this.kind,
    required this.priority,
    required this.supportsCodePatch,
    required this.supportedRoutes,
    required this.supportedProtocols,
    required this.capabilities,
  });

  final String providerId;
  final String displayName;
  final AgentProviderKind kind;
  final int priority;
  final bool supportsCodePatch;
  final List<String> supportedRoutes;
  final List<String> supportedProtocols;
  final List<String> capabilities;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'displayName': displayName,
      'kind': kind.wireValue,
      'priority': priority,
      'supportsCodePatch': supportsCodePatch,
      'supportedRoutes': supportedRoutes,
      'supportedProtocols': supportedProtocols,
      'capabilities': capabilities,
    };
  }
}

int _compareRegistrationPriority(
  AgentProviderRegistration left,
  AgentProviderRegistration right,
) {
  final priorityCompare = right.priority.compareTo(left.priority);
  if (priorityCompare != 0) {
    return priorityCompare;
  }
  return left.providerId.compareTo(right.providerId);
}

Set<String> _normalizedSet(Iterable<String> values) {
  return values
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
}
