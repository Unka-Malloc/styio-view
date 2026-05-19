import '../environment/configuration/configuration.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';

class AgentProviderCredentialResolver {
  const AgentProviderCredentialResolver({required this.configurationStore});

  final ConfigurationStore configurationStore;

  Future<String?> bearerTokenForEndpoint(AgentProviderEndpoint endpoint) async {
    final reference = endpoint.credentialReference;
    if (reference == null) {
      return null;
    }
    final record = await configurationStore.resolveCredential(reference);
    final token = record?.secretValue.trim();
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }
}

class ConfiguredAgentProviderAdapterFactory {
  const ConfiguredAgentProviderAdapterFactory({
    required this.configurationStore,
    required this.transport,
  });

  final ConfigurationStore configurationStore;
  final AgentProviderTransport transport;

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
          ],
          createAdapter: create,
        ),
      ],
    );
  }

  Future<AgentProviderAdapter> create(AgentPromptProfile profile) async {
    if (profile.endpoint.protocol != 'openai-compatible' ||
        profile.endpoint.baseUrl.isEmpty) {
      return const LocalOnlyAgentProviderAdapter();
    }
    final token = await AgentProviderCredentialResolver(
      configurationStore: configurationStore,
    ).bearerTokenForEndpoint(profile.endpoint);
    return OpenAICompatibleAgentProviderAdapter(
      transport: transport,
      endpoint: profile.endpoint,
      authorizationToken: token,
      adapterId: profile.endpoint.route.wireValue,
    );
  }
}
