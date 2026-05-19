import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_code_patch_applier.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_credential_resolver.dart';
import 'package:vityo_app/src/agent/agent_provider_network_transport.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/network/network.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('configured provider factory resolves bearer token from credentials', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_credential_resolver_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final credentials = InMemoryCredentialDataStore();
    const credentialKey = CredentialDataStoreKey(
      namespace: 'agent.provider',
      name: 'openai',
      scope: CredentialScope.user,
    );
    const credentialReference = CredentialReference(
      key: credentialKey,
      kind: CredentialKind.token,
      displayName: 'OpenAI-compatible test token',
    );
    await credentials.write(
      CredentialSecretRecord(
        key: credentialKey,
        kind: CredentialKind.token,
        secretValue: '  test-token  ',
      ),
    );
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final configurationStore = ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: credentials,
    );
    const profile = AgentPromptProfile(
      profileId: 'cloud',
      displayName: 'Cloud Agent',
      systemPrompt: 'Use IDE context.',
      endpoint: AgentProviderEndpoint(
        route: AgentProviderRoute.webHosted,
        baseUrl: 'https://agent.example.test/v1',
        model: 'gpt-test',
        credentialReference: credentialReference,
      ),
    );
    final transport = _RecordingTransport();
    final factory = ConfiguredAgentProviderAdapterFactory(
      configurationStore: configurationStore,
      transport: transport,
    );

    final adapter = await factory.create(profile);
    await adapter.send(
      AgentProviderRequest(
        requestId: 'request-1',
        profile: profile,
        context: _emptyContext(),
        userPrompt: 'Explain this file.',
      ),
    );

    expect(adapter, isA<OpenAICompatibleAgentProviderAdapter>());
    expect(transport.headers['Authorization'], 'Bearer test-token');
  });

  test(
    'configured provider sends controller prompt through network transport',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_network_provider_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final configurationStore = ConfigurationStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
        credentialDataStore: InMemoryCredentialDataStore(),
      );
      const profile = AgentPromptProfile(
        profileId: 'network-cloud',
        displayName: 'Network Cloud Agent',
        systemPrompt: 'Use IDE context.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-network-test',
        ),
      );
      final network = _JsonAgentNetworkManager();
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: configurationStore,
        transport: NetworkAgentProviderTransport(networkManager: network),
      );
      final adapter = await factory.create(profile);
      final controller = AgentCodingSessionController(
        profile: profile,
        adapter: adapter,
        contextProvider: _emptyContext,
      );

      controller.updatePrompt('Explain through real transport.');
      final response = await controller.sendPrompt();

      expect(response, isNotNull);
      expect(response!.contentParts.single.text, 'network ok');
      expect(
        network.lastUri.toString(),
        'https://agent.example.test/v1/chat/completions',
      );
      expect(network.lastBody['model'], 'gpt-network-test');
      expect(network.lastBody['messages'], isA<List<Object?>>());
      expect(controller.conversationTurns.length, 2);
    },
  );

  test(
    'configured provider returns structured patch that controller applies to workspace',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_network_patch_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final configurationStore = ConfigurationStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
        credentialDataStore: InMemoryCredentialDataStore(),
      );
      const profile = AgentPromptProfile(
        profileId: 'network-patch',
        displayName: 'Network Patch Agent',
        systemPrompt: 'Use IDE context.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-network-test',
        ),
      );
      final network = _JsonAgentNetworkManager(
        responseBody: jsonEncode(<String, Object?>{
          'id': 'chatcmpl-network-patch',
          'choices': <Object?>[
            <String, Object?>{
              'finish_reason': 'stop',
              'message': <String, Object?>{
                'role': 'assistant',
                'content': jsonEncode(<String, Object?>{
                  'contentParts': <Object?>[
                    <String, Object?>{
                      'kind': 'code_patch',
                      'text': 'Patch ready.',
                      'patch': <String, Object?>{
                        'patchId': 'network-workspace-patch',
                        'summary': 'Update active and workspace files.',
                        'edits': <Object?>[
                          <String, Object?>{
                            'documentId': 'main.styio',
                            'baseRevision': 1,
                            'start': 8,
                            'end': 9,
                            'replacementText': '2',
                          },
                          <String, Object?>{
                            'documentId': 'other.styio',
                            'baseRevision': 1,
                            'start': 7,
                            'end': 10,
                            'replacementText': 'new',
                          },
                        ],
                      },
                    },
                  ],
                }),
              },
            },
          ],
        }),
      );
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: configurationStore,
        transport: NetworkAgentProviderTransport(networkManager: network),
      );
      final adapter = await factory.create(profile);
      final editorController = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final workspaceStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'other.styio': DocumentState(
            documentId: 'other.styio',
            text: 'name = old\n',
            revision: 1,
          ),
        },
      );
      final controller = AgentCodingSessionController(
        profile: profile,
        adapter: adapter,
        contextProvider: _emptyContext,
      );

      controller.updatePrompt('Patch this workspace.');
      final response = await controller.sendPrompt();
      final result = await controller.applyPendingWorkspacePatch(
        AgentWorkspaceCodePatchApplier(
          editorController: editorController,
          workspaceDocumentStore: workspaceStore,
        ),
      );
      final otherDocument = await workspaceStore.loadDocument('other.styio');

      expect(response, isNotNull);
      expect(controller.pendingPatch, isNull);
      expect(result?.applied, isTrue);
      expect(result?.appliedEditCount, 2);
      expect(editorController.document.text, 'value = 2\n');
      expect(otherDocument.text, 'name = new\n');
      expect(network.lastBody['model'], 'gpt-network-test');
    },
  );
}

AgentSessionContext _emptyContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: '',
      revision: 0,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}

class _RecordingTransport implements AgentProviderTransport {
  Map<String, String> headers = const <String, String>{};

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.headers = headers;
    return <String, Object?>{
      'id': 'chatcmpl-test',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'ok',
          },
        },
      ],
    };
  }
}

class _JsonAgentNetworkManager implements NetworkManager {
  _JsonAgentNetworkManager({
    this.responseBody =
        '{"id":"chatcmpl-network","choices":[{"finish_reason":"stop","message":{"role":"assistant","content":"network ok"}}]}',
  });

  final String responseBody;
  Uri? lastUri;
  Map<String, String> lastHeaders = const <String, String>{};
  Map<String, Object?> lastBody = const <String, Object?>{};

  @override
  NetworkFacts get facts => NetworkFacts.linuxDebianArm();

  @override
  NetworkCompatibility get compatibility => NetworkAdapter(facts).adapt();

  @override
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkTextResponse(
      status: NetworkRequestStatus.blocked,
      uri: uri,
      statusCode: null,
      body: '',
    );
  }

  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastUri = uri;
    lastHeaders = headers;
    lastBody = body;
    return NetworkTextResponse(
      status: NetworkRequestStatus.succeeded,
      uri: uri,
      statusCode: 200,
      body: responseBody,
    );
  }

  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkBinaryResponse(
      status: NetworkRequestStatus.blocked,
      uri: uri,
      statusCode: null,
      bytes: const <int>[],
    );
  }

  @override
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  }) {
    return NetworkFailureClassifier(sourceManager: 'test').classify(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      message: response.message,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  NetworkOperationFailure? failureForBytes(
    NetworkBinaryResponse response, {
    String operation = 'network.getBytes',
    String? recoveryHint,
  }) {
    return NetworkFailureClassifier(sourceManager: 'test').classify(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      message: response.message,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }
}
