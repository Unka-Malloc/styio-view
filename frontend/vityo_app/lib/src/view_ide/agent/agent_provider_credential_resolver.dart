import '../environment/configuration/configuration.dart';
import '../environment/system_compatibility/local_service/local_service.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_route_executor.dart';

enum AgentProviderCredentialLookupSource {
  credentialDataStore,
  environmentVariable,
  hostedSession,
  noClientCredential,
}

extension AgentProviderCredentialLookupSourceX
    on AgentProviderCredentialLookupSource {
  String get wireValue {
    return switch (this) {
      AgentProviderCredentialLookupSource.credentialDataStore =>
        'credential-data-store',
      AgentProviderCredentialLookupSource.environmentVariable =>
        'environment-variable',
      AgentProviderCredentialLookupSource.hostedSession => 'hosted-session',
      AgentProviderCredentialLookupSource.noClientCredential =>
        'no-client-credential',
    };
  }
}

enum AgentProviderCredentialLookupStatus { available, unavailable, skipped }

extension AgentProviderCredentialLookupStatusX
    on AgentProviderCredentialLookupStatus {
  String get wireValue {
    return switch (this) {
      AgentProviderCredentialLookupStatus.available => 'available',
      AgentProviderCredentialLookupStatus.unavailable => 'unavailable',
      AgentProviderCredentialLookupStatus.skipped => 'skipped',
    };
  }
}

class AgentProviderCredentialLookupStep {
  const AgentProviderCredentialLookupStep({
    required this.source,
    required this.status,
    this.targetName = '',
    this.reference,
    this.message = '',
    this.todo = '',
  });

  final AgentProviderCredentialLookupSource source;
  final AgentProviderCredentialLookupStatus status;
  final String targetName;
  final CredentialReference? reference;
  final String message;
  final String todo;

  bool get available => status == AgentProviderCredentialLookupStatus.available;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.wireValue,
      'status': status.wireValue,
      if (targetName.isNotEmpty) 'targetName': targetName,
      if (reference != null) 'reference': reference!.toJson(),
      if (message.isNotEmpty) 'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class AgentProviderCredentialLookupPlan {
  const AgentProviderCredentialLookupPlan({
    required this.policy,
    required this.requiresCredential,
    required this.steps,
    this.message = '',
    this.todo = '',
  });

  final AgentProviderCredentialPolicy policy;
  final bool requiresCredential;
  final List<AgentProviderCredentialLookupStep> steps;
  final String message;
  final String todo;

  bool get resolvesLocally {
    return steps.any((step) => step.available);
  }

  AgentProviderCredentialLookupStep? get selectedStep {
    for (final step in steps) {
      if (step.available) {
        return step;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'policy': policy.wireValue,
      'requiresCredential': requiresCredential,
      'resolvesLocally': resolvesLocally,
      if (selectedStep != null)
        'selectedSource': selectedStep!.source.wireValue,
      if (message.isNotEmpty) 'message': message,
      if (todo.isNotEmpty) 'todo': todo,
      'steps': steps.map((step) => step.toJson()).toList(growable: false),
    };
  }
}

class AgentProviderCredentialResolution {
  const AgentProviderCredentialResolution({
    required this.lookupPlan,
    this.bearerToken,
  });

  final String? bearerToken;
  final AgentProviderCredentialLookupPlan lookupPlan;

  bool get resolved {
    final token = bearerToken;
    return token != null && token.trim().isNotEmpty;
  }
}

class AgentProviderCredentialResolver {
  const AgentProviderCredentialResolver({
    required this.configurationStore,
    this.environment = const <String, String>{},
  });

  final ConfigurationStore configurationStore;
  final Map<String, String> environment;

  Future<String?> bearerTokenForEndpoint(AgentProviderEndpoint endpoint) async {
    return (await resolveBearerTokenForEndpoint(endpoint)).bearerToken;
  }

  Future<AgentProviderCredentialResolution> resolveBearerTokenForEndpoint(
    AgentProviderEndpoint endpoint,
  ) async {
    if (!endpoint.credentialPolicy.allowsClientCredentialLookup) {
      final source =
          endpoint.credentialPolicy ==
              AgentProviderCredentialPolicy.hostedSessionCredential
          ? AgentProviderCredentialLookupSource.hostedSession
          : AgentProviderCredentialLookupSource.noClientCredential;
      return AgentProviderCredentialResolution(
        lookupPlan: AgentProviderCredentialLookupPlan(
          policy: endpoint.credentialPolicy,
          requiresCredential: endpoint.requiresCredential,
          message:
              'Client-side credential lookup is disabled by provider policy.',
          todo: source == AgentProviderCredentialLookupSource.hostedSession
              ? 'Resolve hosted session credentials through the server-side agent route.'
              : '',
          steps: <AgentProviderCredentialLookupStep>[
            AgentProviderCredentialLookupStep(
              source: source,
              status: AgentProviderCredentialLookupStatus.skipped,
              targetName: endpoint.baseUrl,
              reference: endpoint.credentialReference,
              message:
                  'Vityo does not read local Codex CLI OAuth files or private provider auth caches.',
            ),
          ],
        ),
      );
    }
    final steps = <AgentProviderCredentialLookupStep>[];
    final reference = endpoint.credentialReference;
    if (reference != null) {
      final result = await configurationStore.injectCredential(
        CredentialInjectionBinding(
          targetName: 'Authorization',
          reference: reference,
        ),
      );
      if (result.injected) {
        steps.add(
          AgentProviderCredentialLookupStep(
            source: AgentProviderCredentialLookupSource.credentialDataStore,
            status: AgentProviderCredentialLookupStatus.available,
            targetName: 'Authorization',
            reference: reference,
            message: 'Credential DataStore provided a bearer token.',
          ),
        );
        return AgentProviderCredentialResolution(
          bearerToken: result.injectedValue!.value,
          lookupPlan: AgentProviderCredentialLookupPlan(
            policy: endpoint.credentialPolicy,
            requiresCredential: endpoint.requiresCredential,
            message: 'Agent provider credential resolved locally.',
            steps: List<AgentProviderCredentialLookupStep>.unmodifiable(steps),
          ),
        );
      }
      steps.add(
        AgentProviderCredentialLookupStep(
          source: AgentProviderCredentialLookupSource.credentialDataStore,
          status: AgentProviderCredentialLookupStatus.unavailable,
          targetName: 'Authorization',
          reference: reference,
          message: 'Credential DataStore result: ${result.status.name}.',
          todo:
              'Ask the user to configure this credential in Credential DataStore.',
        ),
      );
    }

    final environmentName = endpoint.apiKeyEnvironmentName.trim();
    if (environmentName.isEmpty) {
      return AgentProviderCredentialResolution(
        lookupPlan: AgentProviderCredentialLookupPlan(
          policy: endpoint.credentialPolicy,
          requiresCredential: endpoint.requiresCredential,
          message: 'No credential reference or environment variable is set.',
          todo: endpoint.requiresCredential
              ? 'Configure a CredentialReference for this provider profile.'
              : '',
          steps: List<AgentProviderCredentialLookupStep>.unmodifiable(steps),
        ),
      );
    }
    final environmentValue = environment[environmentName]?.trim();
    if (environmentValue == null || environmentValue.isEmpty) {
      steps.add(
        AgentProviderCredentialLookupStep(
          source: AgentProviderCredentialLookupSource.environmentVariable,
          status: AgentProviderCredentialLookupStatus.unavailable,
          targetName: environmentName,
          message: 'Environment variable is not available to Vityo.',
        ),
      );
      return AgentProviderCredentialResolution(
        lookupPlan: AgentProviderCredentialLookupPlan(
          policy: endpoint.credentialPolicy,
          requiresCredential: endpoint.requiresCredential,
          message: 'Agent provider credential is not available locally.',
          todo: endpoint.requiresCredential
              ? 'Configure Credential DataStore or an explicit provider environment variable.'
              : '',
          steps: List<AgentProviderCredentialLookupStep>.unmodifiable(steps),
        ),
      );
    }
    steps.add(
      AgentProviderCredentialLookupStep(
        source: AgentProviderCredentialLookupSource.environmentVariable,
        status: AgentProviderCredentialLookupStatus.available,
        targetName: environmentName,
        message: 'Environment variable provided a bearer token.',
      ),
    );
    return AgentProviderCredentialResolution(
      bearerToken: environmentValue,
      lookupPlan: AgentProviderCredentialLookupPlan(
        policy: endpoint.credentialPolicy,
        requiresCredential: endpoint.requiresCredential,
        message: 'Agent provider credential resolved locally.',
        steps: List<AgentProviderCredentialLookupStep>.unmodifiable(steps),
      ),
    );
  }
}

class ConfiguredAgentProviderAdapterFactory {
  const ConfiguredAgentProviderAdapterFactory({
    required this.configurationStore,
    required this.transport,
    this.environment = const <String, String>{},
    this.localBridgeTransport,
    this.localServiceManager,
    this.routeExecutor,
    this.endpointProbe,
  });

  final ConfigurationStore configurationStore;
  final AgentProviderTransport transport;
  final Map<String, String> environment;
  final AgentProviderTransport? localBridgeTransport;
  final LocalServiceManager? localServiceManager;
  final AgentProviderRouteExecutor? routeExecutor;
  final AgentProviderEndpointProbe? endpointProbe;

  AgentProviderRegistry createRegistry() {
    return AgentProviderRegistry(
      registrations: <AgentProviderRegistration>[
        AgentProviderRegistration(
          providerId: 'openai-compatible',
          displayName: 'OpenAI-compatible Agent Provider',
          kind: AgentProviderKind.cloudOpenAICompatible,
          priority: 100,
          supportsCodePatch: true,
          supportedRoutes: AgentProviderRoute.values
              .map((route) => route.wireValue)
              .toList(growable: false),
          supportedProtocols: const <String>[
            'openai-compatible',
            'openai-responses',
          ],
          capabilities: const <String>[
            'plan',
            'diagnostic_summary',
            'code_patch',
            'ide_command',
            'route_execution',
            'responses_api',
            'codex_agentic_coding',
          ],
          createAdapter: create,
        ),
      ],
    );
  }

  Future<AgentProviderSelectionPlan> resolveSelectionPlan(
    AgentPromptProfile profile,
  ) async {
    final registry = createRegistry();
    final selectionPlan = registry.selectionPlan(profile);
    if (!selectionPlan.ready) {
      return selectionPlan;
    }
    return selectionPlan.withExecutionResolution(
      await resolveExecution(profile),
    );
  }

  Future<AgentProviderAdapter> create(AgentPromptProfile profile) async {
    final execution = await resolveExecution(profile);
    final selectedEndpoint = execution.selectedEndpoint;
    if (selectedEndpoint == null) {
      return const LocalOnlyAgentProviderAdapter();
    }
    final executionPlan = selectedEndpoint.plan;
    final endpoint = selectedEndpoint.endpoint;
    final token = await AgentProviderCredentialResolver(
      configurationStore: configurationStore,
      environment: environment,
    ).bearerTokenForEndpoint(endpoint);
    final transport = _transportFor(executionPlan);
    if (endpoint.protocol.trim().toLowerCase() == 'openai-responses') {
      return OpenAIResponsesAgentProviderAdapter(
        transport: transport,
        endpoint: endpoint,
        authorizationToken: token,
        adapterId: executionPlan.adapterId,
        providerKind: executionPlan.providerKind,
      );
    }
    return OpenAICompatibleAgentProviderAdapter(
      transport: transport,
      endpoint: endpoint,
      authorizationToken: token,
      adapterId: executionPlan.adapterId,
      providerKind: executionPlan.providerKind,
    );
  }

  Future<AgentProviderExecutionResolution> resolveExecution(
    AgentPromptProfile profile,
  ) {
    final executor =
        routeExecutor ??
        AgentProviderRouteExecutor(localServiceManager: localServiceManager);
    final credentialResolver = AgentProviderCredentialResolver(
      configurationStore: configurationStore,
      environment: environment,
    );
    return executor.resolve(
      profile,
      endpointProbe: endpointProbe,
      credentialAvailable: (endpoint) async {
        return await credentialResolver.bearerTokenForEndpoint(endpoint) !=
            null;
      },
    );
  }

  Future<AgentProviderServiceHealthReport> resolveHealth(
    AgentPromptProfile profile,
  ) async {
    return (await resolveExecution(profile)).toHealthReport();
  }

  AgentProviderTransport _transportFor(AgentProviderExecutionPlan plan) {
    if (plan.usesLocalBridge) {
      return localBridgeTransport ?? transport;
    }
    return transport;
  }
}
