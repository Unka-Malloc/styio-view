import '../environment/configuration/configuration.dart';
import '../environment/system_compatibility/local_service/local_service.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_route_executor.dart';

class AgentProviderCredentialResolver {
  const AgentProviderCredentialResolver({required this.configurationStore});

  final ConfigurationStore configurationStore;

  Future<String?> bearerTokenForEndpoint(AgentProviderEndpoint endpoint) async {
    final reference = endpoint.credentialReference;
    if (reference == null) {
      return null;
    }
    final result = await configurationStore.injectCredential(
      CredentialInjectionBinding(
        targetName: 'Authorization',
        reference: reference,
      ),
    );
    if (!result.injected) {
      return null;
    }
    return result.injectedValue!.value;
  }
}

class ConfiguredAgentProviderAdapterFactory {
  const ConfiguredAgentProviderAdapterFactory({
    required this.configurationStore,
    required this.transport,
    this.localBridgeTransport,
    this.localServiceManager,
    this.routeExecutor,
  });

  final ConfigurationStore configurationStore;
  final AgentProviderTransport transport;
  final AgentProviderTransport? localBridgeTransport;
  final LocalServiceManager? localServiceManager;
  final AgentProviderRouteExecutor? routeExecutor;

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
          supportedProtocols: const <String>['openai-compatible'],
          capabilities: const <String>[
            'plan',
            'diagnostic_summary',
            'code_patch',
            'ide_command',
            'route_execution',
          ],
          createAdapter: create,
        ),
      ],
    );
  }

  Future<AgentProviderAdapter> create(AgentPromptProfile profile) async {
    final executionPlan =
        (routeExecutor ??
                AgentProviderRouteExecutor(
                  localServiceManager: localServiceManager,
                ))
            .planFor(profile);
    if (!executionPlan.executable) {
      return const LocalOnlyAgentProviderAdapter();
    }
    final token = await AgentProviderCredentialResolver(
      configurationStore: configurationStore,
    ).bearerTokenForEndpoint(profile.endpoint);
    return OpenAICompatibleAgentProviderAdapter(
      transport: _transportFor(executionPlan),
      endpoint: profile.endpoint,
      authorizationToken: token,
      adapterId: executionPlan.adapterId,
      providerKind: executionPlan.providerKind,
    );
  }

  AgentProviderTransport _transportFor(AgentProviderExecutionPlan plan) {
    if (plan.usesLocalBridge) {
      return localBridgeTransport ?? transport;
    }
    return transport;
  }
}
