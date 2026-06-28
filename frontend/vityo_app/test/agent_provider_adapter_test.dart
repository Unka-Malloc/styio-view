import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_credential_resolver.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/agent/agent_tool_call_result_context.dart';
import 'package:vityo_app/src/agent/agent_tool_registry.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/interaction/language_service_status_surface.dart';
import 'package:vityo_app/src/view_ide/agent/agent_tool_session_transcript.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent provider request preserves profile and IDE context', () {
    const document = DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: 'value = 1\n',
      revision: 1,
    );
    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: const SelectionState.collapsed(0),
      diagnostics: const [],
      workspaceFiles: const <String>[
        '/workspace/demo/src/main.styio',
        '/workspace/demo/src/other.styio',
        '/workspace/demo/CMakeLists.txt',
        '/workspace/demo/build/compile_commands.json',
      ],
      openDocumentIds: const <String>['/workspace/demo/src/main.styio'],
      dirtyDocumentIds: const <String>['/workspace/demo/src/other.styio'],
      activeFilePath: '/workspace/demo/src/main.styio',
    );
    final request = AgentProviderRequest(
      requestId: 'agent-request-1',
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      context: context,
      userPrompt: 'Explain this file.',
    );

    final json = request.toJson();
    final profileJson = json['profile']! as Map<String, Object?>;
    final contextJson = json['context']! as Map<String, Object?>;
    final documentJson = contextJson['document']! as Map<String, Object?>;
    final ideCapabilitiesJson =
        contextJson['ideCapabilities']! as Map<String, Object?>;
    final ideCapabilityClosureJson =
        contextJson['ideCapabilityClosure']! as Map<String, Object?>;
    final ideCapabilityIds = (ideCapabilitiesJson['entries']! as List<Object?>)
        .map((entry) => (entry! as Map<String, Object?>)['id'])
        .toSet();

    expect(json['requestId'], 'agent-request-1');
    expect(json['userPrompt'], 'Explain this file.');
    expect(
      (profileJson['endpoint']! as Map<String, Object?>)['route'],
      'web-hosted',
    );
    expect(documentJson['documentId'], '/workspace/demo/src/main.styio');
    expect(ideCapabilitiesJson['version'], 'vityo-ide-capability-framework-v1');
    expect(ideCapabilitiesJson['missingRequiredCapabilityIds'], isEmpty);
    expect(ideCapabilityClosureJson['isFrameworkClosed'], isTrue);
    expect(ideCapabilityClosureJson['isRuntimeMature'], isFalse);
    expect(ideCapabilityClosureJson['hardFailureCount'], 0);
    expect(
      ideCapabilityClosureJson['runtimeMaturityBlockerCapabilityIds'],
      isNot(contains('runtime.execution')),
    );
    expect(ideCapabilityIds, contains('interaction.search'));
    expect(ideCapabilityIds, contains('runtime.execution'));
  });

  test(
    'configured provider uses explicit environment API key for Codex Spark',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_provider_config_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = _createAgentProviderConfigurationStore(
        tempRoot,
      );
      final profile = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      );
      final resolver = AgentProviderCredentialResolver(
        configurationStore: configurationStore,
        environment: const <String, String>{
          'OPENAI_API_KEY': '  explicit-env-token  ',
        },
      );
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: configurationStore,
        transport: _RecordingAgentProviderTransport(),
        environment: const <String, String>{
          'OPENAI_API_KEY': '  explicit-env-token  ',
        },
      );

      final token = await resolver.bearerTokenForEndpoint(profile.endpoint);
      final execution = await factory.resolveExecution(profile);

      expect(token, 'explicit-env-token');
      expect(profile.endpoint.protocol, 'openai-responses');
      expect(profile.endpoint.model, 'gpt-5.3-codex-spark');
      expect(
        profile.toJson().toString().toLowerCase(),
        isNot(contains('oauth')),
      );
      expect(execution.status, AgentProviderExecutionResolutionStatus.ready);
      expect(execution.selectedEndpointIndex, 0);
      expect(
        execution.endpoints.single.credentialReadiness,
        AgentProviderCredentialReadiness.available,
      );
    },
  );

  test('OpenAI Responses tool schema constrains coding contracts', () async {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final transport = _RecordingAgentProviderTransport();
    final adapter = OpenAIResponsesAgentProviderAdapter(
      transport: transport,
      endpoint: profile.endpoint,
    );

    await adapter.send(
      AgentProviderRequest(
        requestId: 'agent-request-responses-schema',
        profile: profile,
        context:
            AgentSessionContext.fromEditorState(
              document: const DocumentState(
                documentId: '/workspace/demo/src/main.styio',
                text: 'value = 1\n',
                revision: 1,
              ),
              selection: const SelectionState.collapsed(0),
              diagnostics: const [],
            ).withAgentCodingState(
              toolCatalog: const AgentToolSelection(
                context: AgentToolSelectionContext(
                  providerKind: AgentProviderKind.cloudOpenAICompatible,
                  protocol: 'openai-compatible',
                  model: 'gpt-5.3-codex-spark',
                ),
                tools: <AgentToolDefinition>[
                  AgentToolDefinition(
                    toolId: 'readWorkspaceFile',
                    displayName: 'Read Workspace File',
                    description: 'Read an IDE-owned workspace file.',
                    permissionMode: AgentToolPermissionMode.never,
                    capabilities: <String>['workspace.read'],
                  ),
                  AgentToolDefinition(
                    toolId: 'applyWorkspacePatch',
                    displayName: 'Apply Workspace Patch',
                    description: 'Apply a reviewed workspace patch.',
                    permissionMode: AgentToolPermissionMode.review,
                    capabilities: <String>['workspace.patch.apply'],
                  ),
                ],
                rejectedToolIds: <String>['openLocalShell'],
              ),
              toolPermissionPlan: const AgentToolPermissionPlan(
                status: AgentToolPermissionPlanStatus.reviewRequired,
                decisions: <AgentToolPermissionDecision>[
                  AgentToolPermissionDecision(
                    toolId: 'applyWorkspacePatch',
                    displayName: 'Apply Workspace Patch',
                    permissionMode: AgentToolPermissionMode.review,
                    action: AgentToolPermissionAction.ask,
                    status: AgentToolPermissionDecisionStatus.reviewRequired,
                    source: 'tool-default',
                    reason: 'Tool applyWorkspacePatch requires review.',
                  ),
                ],
              ),
            ),
        userPrompt: 'Suggest a safe IDE command.',
      ),
    );

    final tools = transport.body['tools']! as List<Object?>;
    final toolNames = tools
        .cast<Map<String, Object?>>()
        .map((tool) => tool['name'])
        .toSet();
    final registryToolNames = AgentToolRegistry()
        .selectForProfile(
          profile: profile,
          providerKind: AgentProviderKind.cloudOpenAICompatible,
        )
        .toolIds
        .toSet();
    expect(toolNames, contains('readWorkspaceFile'));
    expect(toolNames, contains('previewWorkspaceEdit'));
    expect(toolNames, contains('applyWorkspacePatch'));
    expect(toolNames, contains('runIdeCommand'));
    expect(toolNames, contains('collectStyioLanguageContext'));
    expect(toolNames, contains('collectAgentValidationContext'));
    expect(toolNames, contains('collectAgentCodingCheckpoint'));
    expect(toolNames, containsAll(registryToolNames));
    final ideTool = tools.cast<Map<String, Object?>>().firstWhere(
      (tool) => tool['name'] == 'vityo_ide_command',
    );
    final readTool = tools.cast<Map<String, Object?>>().firstWhere(
      (tool) => tool['name'] == 'readWorkspaceFile',
    );
    final readParameters = readTool['parameters']! as Map<String, Object?>;
    final readProperties =
        readParameters['properties']! as Map<String, Object?>;
    expect(readParameters['required'], <String>['path']);
    expect(readProperties['path'], isA<Map<String, Object?>>());
    final applyTool = tools.cast<Map<String, Object?>>().firstWhere(
      (tool) => tool['name'] == 'applyWorkspacePatch',
    );
    final applyParameters = applyTool['parameters']! as Map<String, Object?>;
    expect(applyParameters['required'], isEmpty);
    final parameters = ideTool['parameters']! as Map<String, Object?>;
    final properties = parameters['properties']! as Map<String, Object?>;
    final contentParts = properties['contentParts']! as Map<String, Object?>;
    final items = contentParts['items']! as Map<String, Object?>;
    final itemProperties = items['properties']! as Map<String, Object?>;
    final command = itemProperties['command']! as Map<String, Object?>;
    final commandProperties = command['properties']! as Map<String, Object?>;
    final commandId = commandProperties['commandId']! as Map<String, Object?>;
    final prerequisiteForCommandId =
        commandProperties['prerequisiteForCommandId']! as Map<String, Object?>;
    final patch = itemProperties['patch']! as Map<String, Object?>;
    final patchProperties = patch['properties']! as Map<String, Object?>;
    final edits = patchProperties['edits']! as Map<String, Object?>;
    final editItems = edits['items']! as Map<String, Object?>;
    final editProperties = editItems['properties']! as Map<String, Object?>;
    final operation = editProperties['operation']! as Map<String, Object?>;
    final editOperationSchemas = editItems['oneOf']! as List<Object?>;
    final plan = itemProperties['plan']! as Map<String, Object?>;
    final planProperties = plan['properties']! as Map<String, Object?>;
    final planRisks = planProperties['risks']! as Map<String, Object?>;
    final diagnosticSummary =
        itemProperties['diagnosticSummary']! as Map<String, Object?>;
    final diagnosticProperties =
        diagnosticSummary['properties']! as Map<String, Object?>;
    final diagnosticSeverity =
        diagnosticProperties['severity']! as Map<String, Object?>;
    final diagnosticSuggestedCommandIds =
        diagnosticProperties['suggestedCommandIds']! as Map<String, Object?>;
    final diagnosticSuggestedCommandItem =
        diagnosticSuggestedCommandIds['items']! as Map<String, Object?>;

    expect(commandId['enum'], contains('renameSymbol'));
    expect(commandId['enum'], contains('runBuild'));
    expect(commandId['enum'], isNot(contains('deleteWorkspace')));
    expect(prerequisiteForCommandId['enum'], commandId['enum']);
    expect(patch['required'], contains('edits'));
    expect(operation['enum'], <String>['replace', 'create', 'delete']);
    expect(editItems.containsKey('required'), isFalse);
    expect(editOperationSchemas, hasLength(3));
    expect(
      (editOperationSchemas[0]! as Map<String, Object?>)['required'],
      <String>['documentId', 'start', 'end', 'replacementText'],
    );
    expect(
      (editOperationSchemas[1]! as Map<String, Object?>)['required'],
      <String>['documentId', 'operation', 'replacementText'],
    );
    expect(
      (editOperationSchemas[2]! as Map<String, Object?>)['required'],
      <String>['documentId', 'operation'],
    );
    expect(plan['required'], contains('summary'));
    expect(plan['required'], contains('steps'));
    expect(planProperties['acceptanceCriteria'], isA<Map<String, Object?>>());
    expect(planRisks['description'], isNot(contains('TODO')));
    expect(diagnosticSummary['required'], contains('severity'));
    expect(diagnosticSeverity['enum'], <String>['info', 'warning', 'error']);
    expect(diagnosticSuggestedCommandItem['enum'], commandId['enum']);
  });

  test('OpenAI compatible provider sends agent tool results', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final transport = _RecordingAgentProviderTransport();
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: transport,
      endpoint: profile.endpoint,
    );
    final toolCallTimeline = const AgentToolCallLifecycleTracker()
        .track(const <AgentToolCallEvent>[
          AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{"path":"main.styio"}',
          ),
        ]);
    final toolCallJournal = AgentToolCallExecutionJournal.fromTimeline(
      timeline: toolCallTimeline,
    );
    final toolReplayPlan = AgentToolCallReplayPlan.fromJournal(toolCallJournal);

    await adapter.send(
      AgentProviderRequest(
        requestId: 'agent-request-tool-results',
        profile: profile,
        context:
            AgentSessionContext.fromEditorState(
              document: const DocumentState(
                documentId: '/workspace/demo/src/main.styio',
                text: 'value = 1\n',
                revision: 1,
              ),
              selection: const SelectionState.collapsed(0),
              diagnostics: const [],
            ).withAgentCodingState(
              conversationCompaction: const AgentConversationCompactionContext(
                status: AgentConversationCompactionStatus.windowedAndTruncated,
                retainedTurnCount: 2,
                sentTurnCount: 2,
                omittedTurnCount: 3,
                maxRetainedTurnCount: 2,
                maxTurnTextLength: 10,
                truncatedRetainedTurnCount: 1,
                summary: 'Anchored summary\n- user: previous request',
                summaryTurnCount: 3,
              ),
              toolCallTimeline: toolCallTimeline,
              toolCallExecutionJournal: toolCallJournal,
              toolReplayPlan: toolReplayPlan,
              toolCatalog: const AgentToolSelection(
                context: AgentToolSelectionContext(
                  providerKind: AgentProviderKind.cloudOpenAICompatible,
                  protocol: 'openai-compatible',
                  model: 'gpt-5.3-codex-spark',
                ),
                tools: <AgentToolDefinition>[
                  AgentToolDefinition(
                    toolId: 'readWorkspaceFile',
                    displayName: 'Read Workspace File',
                    description: 'Read an IDE-owned workspace file.',
                    permissionMode: AgentToolPermissionMode.never,
                    capabilities: <String>['workspace.read'],
                  ),
                  AgentToolDefinition(
                    toolId: 'applyWorkspacePatch',
                    displayName: 'Apply Workspace Patch',
                    description: 'Apply a reviewed workspace patch.',
                    permissionMode: AgentToolPermissionMode.review,
                    capabilities: <String>['workspace.patch.apply'],
                  ),
                ],
                rejectedToolIds: <String>['openLocalShell'],
              ),
              toolPermissionPlan: const AgentToolPermissionPlan(
                status: AgentToolPermissionPlanStatus.reviewRequired,
                decisions: <AgentToolPermissionDecision>[
                  AgentToolPermissionDecision(
                    toolId: 'applyWorkspacePatch',
                    displayName: 'Apply Workspace Patch',
                    permissionMode: AgentToolPermissionMode.review,
                    action: AgentToolPermissionAction.ask,
                    status: AgentToolPermissionDecisionStatus.reviewRequired,
                    source: 'tool-default',
                    reason: 'Tool applyWorkspacePatch requires review.',
                  ),
                ],
              ),
            ),
        userPrompt: 'Continue after tool execution.',
        toolCallResults: <AgentToolCallResultContext>[
          AgentToolCallResultContext(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            status: AgentToolCallResultContextStatus.success,
            message: 'Agent tool call completed.',
            output: '{"text":"value = 1"}',
            outputTruncated: true,
            outputOriginalLength: 120,
            outputLimit: 20,
            outputOmittedLength: 100,
            createdAt: DateTime.utc(2026, 5, 22),
            metadata: const <String, Object?>{'source': 'test'},
          ),
        ],
        toolSessionTranscript: const AgentToolSessionTranscript(
          status: AgentToolCallTimelineStatus.complete,
          parts: <AgentToolSessionPart>[
            AgentToolSessionPart(
              callId: 'call-read',
              toolId: 'readWorkspaceFile',
              status: AgentToolSessionPartStatus.completed,
              inputText: '{"path":"main.styio"}',
              output: '{"text":"value = 1"}',
            ),
          ],
        ),
      ),
    );

    final messages = transport.body['messages']! as List<Object?>;
    final toolResultMessage = messages.cast<Map<String, Object?>>().firstWhere(
      (message) => message['name'] == 'vityo_agent_tool_results',
    );
    final toolSessionTranscriptMessage = messages
        .cast<Map<String, Object?>>()
        .firstWhere(
          (message) => message['name'] == 'vityo_agent_tool_session_transcript',
        );
    final content =
        jsonDecode(toolResultMessage['content']! as String)
            as Map<String, Object?>;
    final transcriptContent =
        jsonDecode(toolSessionTranscriptMessage['content']! as String)
            as Map<String, Object?>;
    final results = content['toolCallResults']! as List<Object?>;
    final result = results.single! as Map<String, Object?>;
    final transcript =
        transcriptContent['toolSessionTranscript']! as Map<String, Object?>;
    final transcriptParts = transcript['parts']! as List<Object?>;
    final transcriptPart = transcriptParts.single! as Map<String, Object?>;
    final metadata = transport.body['metadata']! as Map<String, Object?>;

    expect(toolResultMessage['role'], 'user');
    expect(toolSessionTranscriptMessage['role'], 'user');
    expect(result['callId'], 'call-read');
    expect(result['toolId'], 'readWorkspaceFile');
    expect(result['success'], isTrue);
    expect(result['output'], '{"text":"value = 1"}');
    expect(transcript['status'], 'complete');
    expect(transcriptPart['callId'], 'call-read');
    expect(transcriptPart['status'], 'completed');
    expect(transcriptPart['inputText'], '{"path":"main.styio"}');
    expect(result['outputTruncated'], isTrue);
    expect(result['outputOriginalLength'], 120);
    expect(result['outputLimit'], 20);
    expect(result['outputOmittedLength'], 100);
    expect(metadata['toolCallResultCount'], 1);
    expect(metadata['toolCallResultIds'], <String>['call-read']);
    expect(metadata['toolCallResultTruncatedCount'], 1);
    expect(metadata['toolCallResultTruncatedIds'], <String>['call-read']);
    expect(metadata['toolSessionTranscriptPartCount'], 1);
    expect(metadata['toolSessionTranscriptStatus'], 'complete');
    expect(
      metadata['agentConversationCompactionStatus'],
      'windowedAndTruncated',
    );
    expect(metadata['agentConversationCompactionRetainedTurnCount'], 2);
    expect(metadata['agentConversationCompactionSentTurnCount'], 2);
    expect(metadata['agentConversationCompactionOmittedTurnCount'], 3);
    expect(
      metadata['agentConversationCompactionTruncatedRetainedTurnCount'],
      1,
    );
    expect(metadata['agentConversationCompactionHasSummary'], isTrue);
    expect(metadata['agentConversationCompactionSummaryTurnCount'], 3);
    expect(
      metadata['agentConversationCompactionSummaryLength'],
      greaterThan(0),
    );
    expect(metadata['agentToolCallTimelineStatus'], 'running');
    expect(metadata['agentToolCallTimelineCallCount'], 1);
    expect(metadata['agentToolCallTimelineCallIds'], <String>['call-read']);
    expect(metadata['agentToolExecutionJournalStatus'], 'running');
    expect(metadata['agentToolExecutionJournalEntryCount'], 1);
    expect(metadata['agentToolExecutionJournalReplayCandidateCount'], 1);
    expect(metadata['agentToolReplayPlanStatus'], 'ready');
    expect(metadata['agentToolReplayPlanReady'], isTrue);
    expect(metadata['agentToolReplayPlanRequestCount'], 1);
    expect(metadata['agentToolCatalogToolCount'], 2);
    expect(metadata['agentToolCatalogToolIds'], <String>[
      'readWorkspaceFile',
      'applyWorkspacePatch',
    ]);
    expect(metadata['agentToolCatalogRejectedToolIds'], <String>[
      'openLocalShell',
    ]);
    expect(metadata['agentToolPermissionStatus'], 'review_required');
    expect(metadata['agentToolPermissionReviewToolIds'], <String>[
      'applyWorkspacePatch',
    ]);
  });

  test('OpenAI compatible provider sends replay follow-up summary', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final transport = _RecordingAgentProviderTransport();
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: transport,
      endpoint: profile.endpoint,
    );

    await adapter.send(
      AgentProviderRequest(
        requestId: 'agent-request-replay-follow-up',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Continue after replay.',
        toolCallResults: <AgentToolCallResultContext>[
          AgentToolCallResultContext(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            status: AgentToolCallResultContextStatus.success,
            message: 'Agent tool call completed.',
            output: '{"text":"value = 1"}',
            createdAt: DateTime.utc(2026, 5, 22),
            metadata: const <String, Object?>{
              'replayedFromJournal': true,
              'replayToolId': 'readWorkspaceFile',
            },
          ),
        ],
      ),
    );

    final messages = transport.body['messages']! as List<Object?>;
    final replayMessage = messages.cast<Map<String, Object?>>().firstWhere(
      (message) => message['name'] == 'vityo_agent_replay_follow_up',
    );
    final replayContent =
        jsonDecode(replayMessage['content']! as String) as Map<String, Object?>;
    final replayedResults =
        replayContent['replayedToolResults']! as List<Object?>;
    final metadata = transport.body['metadata']! as Map<String, Object?>;

    expect(replayMessage['role'], 'user');
    expect(replayContent['source'], 'vityo-agent-tool-replay');
    expect(replayContent['replayedToolResultCount'], 1);
    expect(
      (replayedResults.single! as Map<String, Object?>)['callId'],
      'call-read',
    );
    expect(metadata['toolReplayResultCount'], 1);
    expect(metadata['toolReplayResultIds'], <String>['call-read']);
  });

  test('OpenAI-compatible adapter preserves executable tool calls', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: _ExecutableToolCallTransport(),
      endpoint: profile.endpoint,
    );

    final response = await adapter.send(
      AgentProviderRequest(
        requestId: 'agent-request-executable-tool-call',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Read main.styio.',
      ),
    );

    final event = response.toolCallEvents.single;
    expect(event.kind, AgentToolCallEventKind.callStarted);
    expect(event.callId, 'call-read');
    expect(event.toolId, 'readWorkspaceFile');
    expect(event.input, '{"path":"main.styio"}');
    expect(event.metadata['source'], 'openai-compatible-tool-call');
  });

  test('OpenAI Responses adapter exposes injected registry tools', () async {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final transport = _CustomExecutableToolCallTransport();
    final adapter = OpenAIResponsesAgentProviderAdapter(
      transport: transport,
      endpoint: profile.endpoint,
      toolRegistry: AgentToolRegistry(
        tools: const <AgentToolDefinition>[
          ...AgentToolRegistry.defaultAgentTools,
          AgentToolDefinition(
            toolId: 'collectExtensionContext',
            displayName: 'Collect Extension Context',
            description: 'Collect context provided by an extension tool.',
            priority: 55,
            permissionMode: AgentToolPermissionMode.never,
            capabilities: <String>['extension.context'],
            schema: <AgentToolSchemaProperty>[
              AgentToolSchemaProperty(
                name: 'extensionId',
                type: 'string',
                required: true,
                description: 'Extension id.',
              ),
            ],
          ),
        ],
      ),
    );

    final response = await adapter.send(
      AgentProviderRequest(
        requestId: 'agent-request-custom-tool',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Collect extension context.',
      ),
    );

    final tools = transport.body['tools']! as List<Object?>;
    final customTool = tools.cast<Map<String, Object?>>().firstWhere(
      (tool) => tool['name'] == 'collectExtensionContext',
    );
    final parameters = customTool['parameters']! as Map<String, Object?>;
    final event = response.toolCallEvents.single;

    expect(parameters['required'], <String>['extensionId']);
    expect(event.toolId, 'collectExtensionContext');
    expect(event.input, '{"extensionId":"demo"}');
  });

  test('agent code patch edit parses delete operation from JSON', () {
    final edit = AgentCodePatchEdit.fromJson(<String, Object?>{
      'documentId': 'obsolete.txt',
      'operation': 'delete',
      'start': 0,
      'end': 0,
      'replacementText': '',
    });

    expect(edit.operation, AgentCodePatchEditOperation.delete);
    expect(edit.documentId, 'obsolete.txt');
  });

  test('agent IDE command suggestion preserves prerequisite command link', () {
    final suggestion = AgentIdeCommandSuggestion.fromJson(<String, Object?>{
      'commandId': 'saveAll',
      'reason': 'Save before build.',
      'prerequisiteForCommandId': 'runBuild',
    });
    final json = suggestion.toJson();

    expect(suggestion.commandId, 'saveAll');
    expect(suggestion.registered, isTrue);
    expect(suggestion.requiresInput, isFalse);
    expect(suggestion.inputMissing, isFalse);
    expect(suggestion.prerequisiteForCommandId, 'runBuild');
    expect(json['registered'], isTrue);
    expect(json['requiresInput'], isFalse);
    expect(json['inputMissing'], isFalse);
    expect(json['prerequisiteForCommandId'], 'runBuild');

    final missingInput = AgentIdeCommandSuggestion.fromJson(<String, Object?>{
      'commandId': 'renameSymbol',
      'reason': 'Rename the selected symbol.',
    });
    final missingInputJson = missingInput.toJson();

    expect(missingInput.registered, isTrue);
    expect(missingInput.requiresInput, isTrue);
    expect(missingInput.inputMissing, isTrue);
    expect(missingInputJson['inputLabel'], 'New symbol name');
    expect(missingInputJson['inputContract'], contains('active language'));
    expect(missingInputJson['inputExamples'], contains('newName'));

    final unknownCommand = AgentIdeCommandSuggestion.fromJson(<String, Object?>{
      'commandId': 'deleteWorkspace',
      'reason': 'This command is not registered.',
    });
    final unknownCommandJson = unknownCommand.toJson();

    expect(unknownCommand.registered, isFalse);
    expect(unknownCommand.requiresInput, isFalse);
    expect(unknownCommand.inputMissing, isFalse);
    expect(unknownCommandJson['registered'], isFalse);
  });

  test('agent coding plan content part preserves steps and criteria', () {
    final part = AgentContentPart.fromJson(<String, Object?>{
      'kind': 'plan',
      'text': 'Plan ready.',
      'plan': <String, Object?>{
        'summary': 'Refactor the editor binding.',
        'steps': <String>['Read current binding.', 'Patch controller.'],
        'acceptance_criteria': <String>['Widget test passes.'],
        'risks': <String>['Dirty workspace files.'],
      },
    });
    final json = part.toJson();
    final planJson = json['plan']! as Map<String, Object?>;

    expect(part.kind, AgentContentPartKind.plan);
    expect(part.plan?.summary, 'Refactor the editor binding.');
    expect(part.plan?.steps, <String>[
      'Read current binding.',
      'Patch controller.',
    ]);
    expect(part.plan?.acceptanceCriteria, <String>['Widget test passes.']);
    expect(part.plan?.risks, <String>['Dirty workspace files.']);
    expect(json['kind'], 'plan');
    expect(planJson['acceptanceCriteria'], <String>['Widget test passes.']);
  });

  test('agent diagnostic summary content part preserves triage facts', () {
    final part = AgentContentPart.fromJson(<String, Object?>{
      'kind': 'diagnostic_summary',
      'text': 'Diagnostics summarized.',
      'diagnostic_summary': <String, Object?>{
        'title': 'Build failed.',
        'summary': 'Parser target failed with one error.',
        'severity': 'error',
        'diagnostic_count': 1,
        'affected_documents': <String>['src/parser.cc'],
        'suggested_command_ids': <String>['runBuild'],
      },
    });
    final json = part.toJson();
    final summaryJson = json['diagnosticSummary']! as Map<String, Object?>;

    expect(part.kind, AgentContentPartKind.diagnosticSummary);
    expect(part.diagnosticSummary?.title, 'Build failed.');
    expect(
      part.diagnosticSummary?.summary,
      'Parser target failed with one error.',
    );
    expect(part.diagnosticSummary?.severity, 'error');
    expect(part.diagnosticSummary?.diagnosticCount, 1);
    expect(part.diagnosticSummary?.affectedDocuments, <String>[
      'src/parser.cc',
    ]);
    expect(part.diagnosticSummary?.suggestedCommandIds, <String>['runBuild']);
    expect(summaryJson['diagnosticCount'], 1);
    expect(summaryJson['suggestedCommandIds'], <String>['runBuild']);
  });

  test('local-only adapter returns configuration fallback response', () async {
    const document = DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: 'value = 1\n',
      revision: 1,
    );
    final context = AgentSessionContext.fromEditorState(
      document: document,
      selection: const SelectionState.collapsed(0),
      diagnostics: const [],
      workspaceFiles: const <String>[
        '/workspace/demo/src/main.styio',
        '/workspace/demo/src/other.styio',
        '/workspace/demo/CMakeLists.txt',
        '/workspace/demo/build/compile_commands.json',
      ],
      openDocumentIds: const <String>['/workspace/demo/src/main.styio'],
      dirtyDocumentIds: const <String>['/workspace/demo/src/other.styio'],
      languageServiceStatus: _agentLanguageServiceStatus,
    );
    final request = AgentProviderRequest(
      requestId: 'agent-request-2',
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.macos),
      context: context,
      userPrompt: 'Refactor this file.',
      attachments: const <AgentRequestAttachment>[
        AgentRequestAttachment(
          attachmentId: 'note-1',
          kind: 'text',
          name: 'note.txt',
          content: 'prefer simple edits',
        ),
      ],
    );
    const adapter = LocalOnlyAgentProviderAdapter();

    final response = await adapter.send(request);
    final json = response.toJson();

    expect(adapter.kind, AgentProviderKind.localOnlyFallback);
    expect(adapter.supportsCodePatch, isFalse);
    expect(json['requestId'], 'agent-request-2');
    expect(json['finishReason'], 'provider_not_configured');
    expect(json['contentParts'], isA<List<Object?>>());
    expect(
      (json['usage']! as Map<String, Object?>)['documentId'],
      '/workspace/demo/src/main.styio',
    );
    expect(
      (json['usage']! as Map<String, Object?>)['contextSchemaVersion'],
      88,
    );
    expect((json['usage']! as Map<String, Object?>)['selectionStartLine'], 0);
    expect((json['usage']! as Map<String, Object?>)['selectionStartColumn'], 0);
    expect((json['usage']! as Map<String, Object?>)['selectionEndLine'], 0);
    expect((json['usage']! as Map<String, Object?>)['selectionEndColumn'], 0);
    expect((json['usage']! as Map<String, Object?>)['workspaceFileCount'], 4);
    expect((json['usage']! as Map<String, Object?>)['openDocumentCount'], 1);
    expect((json['usage']! as Map<String, Object?>)['dirtyDocumentCount'], 1);
    expect(
      (json['usage']! as Map<String, Object?>)['workspaceDocumentSampleCount'],
      1,
    );
    expect(
      (json['usage']!
          as Map<String, Object?>)['workspaceDocumentSamplesTruncated'],
      isFalse,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['workspaceBuildSystemHints'],
      <String>['compilation-database', 'cmake'],
    );
    expect(
      (json['usage']! as Map<String, Object?>)['hasLanguageHover'],
      isFalse,
    );
    expect((json['usage']! as Map<String, Object?>)['hasFocusToken'], isFalse);
    expect(
      (json['usage']!
          as Map<String, Object?>)['languageFocusedDiagnosticCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageReferenceCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['hasParameterInfo'],
      isFalse,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageParameterCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageCompletionCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageCodeActionCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageSemanticSpanCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageDocumentSymbolCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageInlayHintCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageSemanticBlockCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageRefactorPreviewCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageSurroundTemplateCount'],
      0,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageServiceSeverity'],
      'ready',
    );
    expect(
      (json['usage']!
          as Map<String, Object?>)['languageServiceUsableCapabilityCount'],
      2,
    );
    expect(
      (json['usage']!
          as Map<String, Object?>)['languageServiceFreshCapabilityCount'],
      1,
    );
    expect(
      (json['usage']!
          as Map<String, Object?>)['languageServiceLocalFallbackEnabled'],
      isTrue,
    );
    expect(
      ((json['usage']!
              as Map<
                String,
                Object?
              >)['languageServicePrimaryCapabilityStates']!
          as Map<String, Object?>)['completion'],
      'derived',
    );
    expect((json['usage']! as Map<String, Object?>)['debugStatus'], 'idle');
    expect((json['usage']! as Map<String, Object?>)['debugBreakpointCount'], 0);
    expect((json['usage']! as Map<String, Object?>)['debugThreadCount'], 0);
    expect(
      (json['usage']! as Map<String, Object?>)['persistenceCommandCount'],
      2,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['executionCommandCount'],
      1,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['diagnosticCommandCount'],
      5,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['languageServiceCommandCount'],
      1,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['navigationCommandCount'],
      7,
    );
    expect((json['usage']! as Map<String, Object?>)['refactorCommandCount'], 3);
    expect(
      (json['usage']! as Map<String, Object?>)['dependencyCommandCount'],
      2,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['deploymentCommandCount'],
      2,
    );
    expect((json['usage']! as Map<String, Object?>)['moduleCommandCount'], 1);
    expect(
      (json['usage']! as Map<String, Object?>)['surfaceCommandCount'],
      StyioCommandRegistry.surfaceCommands.length,
    );
    expect((json['usage']! as Map<String, Object?>)['testingCommandCount'], 4);
    expect((json['usage']! as Map<String, Object?>)['debugCommandCount'], 7);
    expect(
      (json['usage']! as Map<String, Object?>)['debugReadyCommandCount'],
      1,
    );
    expect(
      (json['usage']! as Map<String, Object?>)['debugBlockedCommandCount'],
      6,
    );
    expect((json['usage']! as Map<String, Object?>)['skillCount'], 15);
    expect(
      (json['usage']! as Map<String, Object?>)['activeSkillCount'],
      greaterThan(0),
    );
    expect(
      (json['usage']! as Map<String, Object?>)['activeSkillIds'],
      contains('styio-language-service-truth'),
    );
    final usageActiveSkillReasons =
        (json['usage']! as Map<String, Object?>)['activeSkillReasons']!
            as Map<String, Object?>;
    expect(
      usageActiveSkillReasons['styio-language-service-truth'],
      isA<List<Object?>>(),
    );
    expect(
      (json['usage']! as Map<String, Object?>)['skillIds'],
      contains('cpp-clang-toolchain-defaults'),
    );
    expect(
      (json['usage']! as Map<String, Object?>)['skillIds'],
      contains('cpp-clang-version-handoff'),
    );
    expect(
      (json['usage']! as Map<String, Object?>)['skillIds'],
      contains('cpp-compilation-database'),
    );
    expect(
      (json['usage']! as Map<String, Object?>)['skillIds'],
      contains('cpp-clang-format-tidy'),
    );
    expect(
      (json['usage']! as Map<String, Object?>)['skillIds'],
      contains('reference-grounded-ide-development'),
    );
    expect((json['usage']! as Map<String, Object?>)['toolchainCount'], 0);
    expect(
      (json['usage']! as Map<String, Object?>)['hasNativeCompiler'],
      isFalse,
    );
    expect((json['usage']! as Map<String, Object?>)['attachmentCount'], 1);
    expect(
      (json['usage']! as Map<String, Object?>)['attachmentKinds'],
      <String>['text'],
    );
    expect(
      (json['usage']! as Map<String, Object?>)['conversationTurnCount'],
      0,
    );
  });

  test(
    'OpenAI-compatible adapter posts chat request with IDE context',
    () async {
      const document = DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      );
      const symbolSearch = WorkspaceSymbolSearchResult(
        matches: <WorkspaceSymbolMatch>[
          WorkspaceSymbolMatch(
            documentId: '/workspace/demo/src/main.styio',
            name: 'value',
            kind: ResolvedElementKind.variable,
            nameRange: SourceRange(start: 0, end: 5),
            declarationRange: SourceRange(start: 0, end: 9),
            lineNumber: 1,
            lineText: 'value = 1',
            score: 1000,
          ),
        ],
      );
      final context = AgentSessionContext.fromEditorState(
        document: document,
        selection: const SelectionState.collapsed(0),
        diagnostics: const [],
        lastWorkspaceSymbolSearch:
            AgentWorkspaceSymbolSearchResultContext.fromWorkspaceResult(
              query: 'value',
              scannedDocumentCount: 1,
              result: symbolSearch,
            ),
        lastCommandResult: AgentCommandResultContext(
          commandId: 'searchWorkspace',
          input: 'value',
          applied: true,
          message: 'Agent command searchWorkspace completed for value.',
          metadata: <String, Object?>{
            'searchResult': <String, Object?>{'matchCount': 1},
            'requiredCommand': 'runBuild',
            'backendRouteSelection': <String, Object?>{
              'routeKind': 'blocked',
              'adapterKind': 'none',
              'allowed': false,
              'previewOnly': false,
              'blockedReason': 'no-backend-route',
            },
            'toolchainSelectionStatus': 'selected',
            'toolchainSelectionMessage': 'Clang/C++ version selected.',
            'toolchainId': 'native-clang-cpp-compiler',
            'cppStandard': 'c++23',
            'buildEngineHandoffCount': 3,
            'preferredBuildEngineHandoff': <String, Object?>{
              'engineFamily': 'cmake',
              'generatorFamily': 'ninja',
              'arguments': <String>['-G', 'Ninja'],
            },
            'settingsRoute': 'settings',
            'settingsSection': 'toolchain',
            'recoveryForCommandId': 'runBuild',
          },
          completedAt: DateTime.utc(2026, 5, 19, 1, 2, 3),
        ),
        pendingPatch: const AgentPendingPatchContext(
          patchId: 'patch-pending',
          summary: 'Pending change.',
          baseRevision: 1,
          documentIds: <String>['/workspace/demo/src/main.styio'],
          editCount: 1,
          operationCounts: <String, int>{'replace': 1},
          edits: <AgentPendingPatchEditContext>[
            AgentPendingPatchEditContext(
              documentId: '/workspace/demo/src/main.styio',
              operation: 'replace',
              start: 8,
              end: 9,
              replacementTextSample: '2',
              replacementTextLength: 1,
              replacementTextTruncated: false,
            ),
          ],
          editsTruncated: false,
        ),
        recentPatchProposals: const <AgentPendingPatchContext>[
          AgentPendingPatchContext(
            patchId: 'patch-pending',
            summary: 'Pending change.',
            baseRevision: 1,
            documentIds: <String>['/workspace/demo/src/main.styio'],
            editCount: 1,
            operationCounts: <String, int>{'replace': 1},
            edits: <AgentPendingPatchEditContext>[
              AgentPendingPatchEditContext(
                documentId: '/workspace/demo/src/main.styio',
                operation: 'replace',
                start: 8,
                end: 9,
                replacementTextSample: '2',
                replacementTextLength: 1,
                replacementTextTruncated: false,
              ),
            ],
            editsTruncated: false,
          ),
        ],
        pendingIdeCommands: const <AgentPendingIdeCommandContext>[
          AgentPendingIdeCommandContext(
            commandId: 'runBuild',
            reason: 'Use the registered build command.',
            prerequisiteForCommandId: 'saveAll',
            text: 'Run the build.',
          ),
        ],
        recentIdeCommandSuggestions: const <AgentPendingIdeCommandContext>[
          AgentPendingIdeCommandContext(
            commandId: 'runBuild',
            reason: 'Use the registered build command.',
            prerequisiteForCommandId: 'saveAll',
            text: 'Run the build.',
          ),
        ],
        lastProviderFailure: const AgentProviderFailureContext(
          kind: 'timeout',
          message: 'provider timed out',
          operation: 'agent.provider.postJson',
          recoveryHint: 'Retry the provider request.',
        ),
        providerExecutionResolution: const AgentProviderExecutionResolution(
          profileId: 'cloud',
          status: AgentProviderExecutionResolutionStatus.fallbackReady,
          selectedEndpointIndex: 1,
          endpoints: <AgentProviderEndpointReadiness>[
            AgentProviderEndpointReadiness(
              endpointIndex: 0,
              fallback: false,
              endpoint: AgentProviderEndpoint(
                route: AgentProviderRoute.webHosted,
                baseUrl: 'https://primary.example.test/v1',
                model: 'gpt-primary',
                requiresCredential: true,
              ),
              plan: AgentProviderExecutionPlan(
                routeKind: AgentProviderExecutionRouteKind.cloud,
                providerKind: AgentProviderKind.cloudOpenAICompatible,
                route: AgentProviderRoute.webHosted,
                endpointBaseUrl: 'https://primary.example.test/v1',
              ),
              credentialReadiness: AgentProviderCredentialReadiness.unavailable,
            ),
            AgentProviderEndpointReadiness(
              endpointIndex: 1,
              fallback: true,
              endpoint: AgentProviderEndpoint(
                route: AgentProviderRoute.webHosted,
                baseUrl: 'https://fallback.example.test/v1',
                model: 'gpt-fallback',
              ),
              plan: AgentProviderExecutionPlan(
                routeKind: AgentProviderExecutionRouteKind.cloud,
                providerKind: AgentProviderKind.cloudOpenAICompatible,
                route: AgentProviderRoute.webHosted,
                endpointBaseUrl: 'https://fallback.example.test/v1',
              ),
              credentialReadiness: AgentProviderCredentialReadiness.available,
            ),
          ],
        ),
        lastPatchApplication: AgentPatchApplicationContext(
          patchId: 'patch-applied',
          summary: 'Change value.',
          baseRevision: 1,
          documentIds: const <String>['/workspace/demo/src/main.styio'],
          editCount: 1,
          operationCounts: const <String, int>{'replace': 1},
          applied: true,
          pendingPatchRetained: false,
          message: 'Applied 1 agent patch edit(s).',
          appliedEditCount: 1,
          appliedOperationCounts: const <String, int>{'replace': 1},
          changedDocumentIds: const <String>['/workspace/demo/src/main.styio'],
          skippedNoOpDocumentIds: const <String>[
            '/workspace/demo/src/noop.styio',
          ],
          recordedAt: DateTime.utc(2026, 5, 19, 2, 3, 4),
        ),
        languageServiceStatus: _agentLanguageServiceStatus,
        toolchainSnapshot: const ToolchainStateSnapshot(
          targetId: 'agent-provider-toolchain',
          entries: <ToolchainStateEntry>[
            ToolchainStateEntry(
              id: 'native-clang-cpp-compiler',
              kind: ToolchainKind.compiler,
              displayName: 'Clang C/C++ Compiler',
              executablePath: '/usr/bin/clang++',
              active: true,
              metadata: <String, Object?>{
                'compilerFamily': 'clang',
                'cCompilerPath': '/usr/bin/clang',
                'cxxCompilerPath': '/usr/bin/clang++',
                'defaultForNativeCode': true,
              },
            ),
            ToolchainStateEntry(
              id: 'native-cmake-build-tool',
              kind: ToolchainKind.buildTool,
              displayName: 'CMake Build System',
              executablePath: '/usr/bin/cmake',
              active: true,
              metadata: <String, Object?>{'toolFamily': 'cmake'},
            ),
            ToolchainStateEntry(
              id: 'native-ninja-build-tool',
              kind: ToolchainKind.buildTool,
              displayName: 'Ninja Build Tool',
              executablePath: '/usr/bin/ninja',
              active: false,
              metadata: <String, Object?>{'toolFamily': 'ninja'},
            ),
          ],
        ),
      );
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-3',
        profile: profile,
        context: context,
        userPrompt: 'Explain this file.',
      );
      final transport = _RecordingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: profile.endpoint,
        authorizationToken: '  secret-token  ',
      );

      final response = await adapter.send(request);

      expect(adapter.kind, AgentProviderKind.cloudOpenAICompatible);
      expect(adapter.supportsCodePatch, isTrue);
      expect(
        transport.endpoint.toString(),
        '/api/styio-agent/v1/chat/completions',
      );
      expect(transport.headers['Authorization'], 'Bearer secret-token');
      expect(transport.body['model'], profile.endpoint.model);
      final messages = transport.body['messages']! as List<Object?>;
      expect(messages, hasLength(3));
      final systemMessage = messages.first! as Map<String, Object?>;
      expect(systemMessage['content'], contains('contentParts'));
      expect(systemMessage['content'], contains('"kind":"plan"'));
      expect(systemMessage['content'], contains('diagnostic_summary'));
      expect(
        systemMessage['content'],
        contains('"suggestedCommandIds":["previewQuickFix","applyQuickFix"]'),
      );
      expect(systemMessage['content'], contains('code_patch'));
      expect(systemMessage['content'], contains('ide_command'));
      expect(systemMessage['content'], contains('agent.recentCodingPlans'));
      expect(
        systemMessage['content'],
        contains('agent.recentDiagnosticSummaries'),
      );
      expect(systemMessage['content'], contains('agent.recoveryPlan'));
      expect(systemMessage['content'], contains('agent.savedProviderProfiles'));
      expect(systemMessage['content'], contains('commands catalog'));
      expect(systemMessage['content'], contains('Styio-first skills'));
      expect(systemMessage['content'], contains('C++/Clang skills'));
      expect(systemMessage['content'], contains('reference-grounded IDE'));
      expect(systemMessage['content'], contains('debug.threads'));
      expect(systemMessage['content'], contains('selectDebugThread'));
      expect(systemMessage['content'], contains('document.textStart'));
      expect(
        systemMessage['content'],
        contains('patch.baseRevision is a fallback for replace edits only'),
      );
      expect(systemMessage['content'], contains('workspace.dirtyDocumentIds'));
      expect(systemMessage['content'], contains('workspace.documentSamples'));
      expect(systemMessage['content'], contains('workspace.buildFacts'));
      expect(
        systemMessage['content'],
        contains('workspace.buildFacts.toolingHints'),
      );
      expect(
        systemMessage['content'],
        contains('workspace.buildFacts.hasCompilationDatabase'),
      );
      expect(systemMessage['content'], contains('toolchains.clangCpp'));
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.preferenceStatus'),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.cmakeExecutablePath'),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.selection.candidate.version'),
      );
      expect(
        systemMessage['content'],
        contains(
          'toolchains.clangCpp.selection.candidate.metadata.clangVendor',
        ),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.selection.preferredBuildEngineHandoff'),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.selection.buildEngineHandoffs'),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.selection.cmakeNinjaConfigureArguments'),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.clangCpp.ninjaExecutablePath'),
      );
      expect(
        systemMessage['content'],
        contains('toolchains.nativeTools.languageServices'),
      );
      expect(systemMessage['content'], contains('Ninja'));
      expect(
        systemMessage['content'],
        contains('Do not patch inactive dirty documents'),
      );
      expect(systemMessage['content'], contains('documentId must not contain'));
      expect(
        systemMessage['content'],
        contains(
          'do not use create/delete file operations on the active document',
        ),
      );
      expect(systemMessage['content'], contains('commands.diagnosticCommands'));
      expect(systemMessage['content'], contains('previewQuickFix'));
      expect(
        systemMessage['content'],
        contains('agent.workspaceEdit.suggestedCommandIds'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.workspaceEditPreview'),
      );
      expect(
        systemMessage['content'],
        contains('workspaceEditPreview.confirmationPlan.riskLevel'),
      );
      expect(
        systemMessage['content'],
        contains('commands.languageServiceCommands'),
      );
      expect(
        systemMessage['content'],
        contains('commands.persistenceCommands'),
      );
      expect(systemMessage['content'], contains('commands.executionCommands'));
      expect(systemMessage['content'], contains('commands.dependencyCommands'));
      expect(systemMessage['content'], contains('commands.deploymentCommands'));
      expect(systemMessage['content'], contains('commands.moduleCommands'));
      expect(systemMessage['content'], contains('commands.surfaceCommands'));
      expect(systemMessage['content'], contains('showRuntime'));
      expect(systemMessage['content'], contains('metadata.moduleHostRefresh'));
      expect(systemMessage['content'], contains('commands.refactorCommands'));
      expect(systemMessage['content'], contains('commands.toolchainCommands'));
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.toolchainCommand'),
      );
      expect(systemMessage['content'], contains('useActiveCompiler'));
      expect(systemMessage['content'], contains('requiresInput true'));
      expect(systemMessage['content'], contains('inputContract'));
      expect(systemMessage['content'], contains('inputExamples'));
      expect(systemMessage['content'], contains('missing-input commands'));
      expect(systemMessage['content'], contains('selectClangCppVersion'));
      expect(systemMessage['content'], contains('commands.nativeToolCommands'));
      expect(systemMessage['content'], contains('commands.testingCommands'));
      expect(systemMessage['content'], contains('rerunFailedTests'));
      expect(systemMessage['content'], contains('debugFailedTests'));
      expect(systemMessage['content'], contains('runTestConfiguration'));
      expect(systemMessage['content'], contains('debugTestConfiguration'));
      expect(
        systemMessage['content'],
        contains('commands.nativeToolCommandReadiness'),
      );
      expect(systemMessage['content'], contains('requiredToolFamilies'));
      expect(systemMessage['content'], contains('toolFamily'));
      expect(systemMessage['content'], contains('requiredCommandId'));
      expect(systemMessage['content'], contains('before the blocked command'));
      expect(systemMessage['content'], contains('has no requiredCommandId'));
      expect(
        systemMessage['content'],
        contains('before retrying the missing-tool command'),
      );
      expect(systemMessage['content'], contains('commands.debugCommands'));
      expect(systemMessage['content'], contains('debug.suggestedCommandIds'));
      expect(systemMessage['content'], contains('commands.settingsCommands'));
      expect(
        systemMessage['content'],
        contains('commands.debugCommandReadiness'),
      );
      expect(systemMessage['content'], contains('debug.status'));
      expect(systemMessage['content'], contains('debug.launch.ready'));
      expect(systemMessage['content'], contains('debug.stackFrames'));
      expect(systemMessage['content'], contains('commands.lastResult'));
      expect(systemMessage['content'], contains('commands.recentResults'));
      expect(
        systemMessage['content'],
        contains('commands.recentResults includes metadata.requiredCommand'),
      );
      expect(systemMessage['content'], contains('agent.pendingPatch'));
      expect(systemMessage['content'], contains('agent.suggestedCommandIds'));
      expect(systemMessage['content'], contains('agent.workspaceCheckpoint'));
      expect(
        systemMessage['content'],
        contains('agent.conversationCompaction'),
      );
      expect(systemMessage['content'], contains('summaryTurnCount'));
      expect(systemMessage['content'], contains('agent.toolCallTimeline'));
      expect(
        systemMessage['content'],
        contains('agent.toolCallExecutionJournal'),
      );
      expect(systemMessage['content'], contains('agent.toolReplayPlan'));
      expect(systemMessage['content'], contains('agent.toolCatalog'));
      expect(systemMessage['content'], contains('agent.toolPermissions'));
      expect(systemMessage['content'], contains('outputTruncated true'));
      expect(systemMessage['content'], contains('agent.changeReviewGate'));
      expect(systemMessage['content'], contains('agent.autonomyPolicy'));
      expect(systemMessage['content'], contains('agent.loopGuard'));
      expect(systemMessage['content'], contains('agent.validationPlan'));
      expect(systemMessage['content'], contains('agent.validationResult'));
      expect(systemMessage['content'], contains('agent.validationPipeline'));
      expect(
        systemMessage['content'],
        contains('agent.validationPlan.registeredCommandIds'),
      );
      expect(
        systemMessage['content'],
        contains('agent.validationPlan.commandPlans'),
      );
      expect(
        systemMessage['content'],
        contains('agent.validationResult.status'),
      );
      expect(
        systemMessage['content'],
        contains('agent.validationPipeline.nextCommandId'),
      );
      expect(
        systemMessage['content'],
        contains('commands.registeredCommandIds'),
      );
      expect(systemMessage['content'], contains('agent.recentPatchProposals'));
      expect(systemMessage['content'], contains('agent.pendingIdeCommands'));
      expect(systemMessage['content'], contains('inputMissing'));
      expect(
        systemMessage['content'],
        contains('agent.recentIdeCommandSuggestions'),
      );
      expect(systemMessage['content'], contains('agent.lastProviderFailure'));
      expect(systemMessage['content'], contains('agent.providerExecution'));
      expect(
        systemMessage['content'],
        contains('agent.recentPatchApplications'),
      );
      expect(systemMessage['content'], contains('agent.lastPatchApplication'));
      expect(
        systemMessage['content'],
        contains('agent.lastPatchApplication.skippedNoOpDocumentIds'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.buildResult'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.formatResult'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.requiredCommand'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.completedRequiredCommandFor'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.recoveryForCommandId'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.backendRouteSelection'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.toolchainSelectionStatus'),
      );
      expect(systemMessage['content'], contains('toolchainSelectionMessage'));
      expect(systemMessage['content'], contains('status is not selected'));
      expect(
        systemMessage['content'],
        contains('before another selection or build/test retry'),
      );
      expect(
        systemMessage['content'],
        contains('backendRouteSelection.allowed is false'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.staticAnalysisResult'),
      );
      expect(
        systemMessage['content'],
        contains('commands.lastResult.metadata.testResult'),
      );
      expect(systemMessage['content'], contains('language.hoverMarkdown'));
      expect(systemMessage['content'], contains('language.focusToken'));
      expect(systemMessage['content'], contains('language.focusedDiagnostics'));
      expect(systemMessage['content'], contains('suggestedCommandIds'));
      expect(systemMessage['content'], contains('language.resolvedElement'));
      expect(systemMessage['content'], contains('language.resolvedReference'));
      expect(
        systemMessage['content'],
        contains('language.definition.agentCommandId'),
      );
      expect(
        systemMessage['content'],
        contains('language.references.agentCommandIds'),
      );
      expect(systemMessage['content'], contains('language.parameterInfo'));
      expect(systemMessage['content'], contains('language.serviceStatus'));
      expect(
        systemMessage['content'],
        contains('language.serviceStatus.suggestedCommandIds'),
      );
      expect(
        systemMessage['content'],
        contains('metadata.projectLanguage.suggestedCommandIds'),
      );
      expect(
        systemMessage['content'],
        contains('metadata.projectLanguage.semanticFeatureMatrix'),
      );
      expect(
        systemMessage['content'],
        contains(
          'metadata.ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds',
        ),
      );
      expect(
        systemMessage['content'],
        contains('metadata.projectLanguage.syntaxValidationAuthority'),
      );
      expect(
        systemMessage['content'],
        contains('metadata.projectLanguage.workspaceQuickFixes'),
      );
      expect(
        systemMessage['content'],
        contains('metadata.projectLanguage.syntaxValidationAuthority'),
      );
      expect(
        systemMessage['content'],
        contains('metadata.projectLanguage.syntaxValidationReport'),
      );
      expect(
        systemMessage['content'],
        contains('language.serviceStatus.syntaxValidationReady'),
      );
      expect(systemMessage['content'], contains('language.completions'));
      expect(systemMessage['content'], contains('language.codeActions'));
      expect(systemMessage['content'], contains('agentCommandInput'));
      expect(systemMessage['content'], contains('agentCommandLabelInput'));
      expect(systemMessage['content'], contains('language.semanticSpans'));
      expect(
        systemMessage['content'],
        contains('language.semanticFeatureMatrix'),
      );
      expect(systemMessage['content'], contains('preferredSource'));
      expect(systemMessage['content'], contains('fallbackActive'));
      expect(systemMessage['content'], contains('conflictPolicy'));
      expect(systemMessage['content'], contains('language.documentSymbols'));
      expect(systemMessage['content'], contains('language.inlayHints'));
      expect(systemMessage['content'], contains('language.semanticBlocks'));
      expect(systemMessage['content'], contains('language.refactorPreviews'));
      expect(systemMessage['content'], contains('agentCommandId'));
      expect(systemMessage['content'], contains('language.surroundTemplates'));
      expect(systemMessage['content'], contains('workspace.lastSymbolSearch'));
      expect(
        systemMessage['content'],
        contains('commands.workspaceFileCommands'),
      );
      expect(systemMessage['content'], contains('deleteWorkspaceFile'));
      expect(systemMessage['content'], contains('previewWorkspaceReplace'));
      expect(systemMessage['content'], contains('applyWorkspaceReplace'));
      expect(
        systemMessage['content'],
        contains('workspace.sourceControlContext'),
      );
      expect(
        systemMessage['content'],
        contains('workspace.sourceControlContext.suggestedCommandIds'),
      );
      expect(systemMessage['content'], contains('stageSourceControl'));
      expect(systemMessage['content'], contains('unstageSourceControl'));
      expect(
        systemMessage['content'],
        contains('planSourceControlBranchSwitch'),
      );
      expect(
        systemMessage['content'],
        contains('planSourceControlCommitDraft'),
      );
      expect(systemMessage['content'], contains('testing.rerunFailed'));
      expect(systemMessage['content'], contains('testing.suggestedCommandIds'));
      expect(systemMessage['content'], contains('testing.debugFailed'));
      expect(
        systemMessage['content'],
        contains('testing.debugFailedRoutePlan'),
      );
      expect(
        systemMessage['content'],
        contains('metadata.sourceControlContext'),
      );
      expect(systemMessage['content'], contains('zero-based coordinates'));
      expect(
        systemMessage['content'],
        contains('edit offsets are still authoritative'),
      );
      expect(systemMessage['content'], contains('toolchains.activeCompiler'));
      expect(systemMessage['content'], contains('toolchains.nativeTools'));
      expect(systemMessage['content'], contains('skills.activeSkillIds'));
      expect(systemMessage['content'], contains('ideCapabilityClosure'));
      expect(
        systemMessage['content'],
        contains('ideCapabilityClosure.isRuntimeMature'),
      );
      expect(
        systemMessage['content'],
        contains('ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds'),
      );
      final metadata = transport.body['metadata']! as Map<String, Object?>;
      expect(metadata['contextSchemaVersion'], 88);
      expect(metadata['selectionStartLine'], 0);
      expect(metadata['selectionStartColumn'], 0);
      expect(metadata['selectionEndLine'], 0);
      expect(metadata['selectionEndColumn'], 0);
      expect(metadata['skillCount'], 15);
      expect(metadata['activeSkillCount'], greaterThan(0));
      expect(
        metadata['activeSkillIds'],
        contains('styio-language-service-truth'),
      );
      expect(
        metadata['activeSkillIds'],
        isNot(contains('cpp-clang-version-handoff')),
      );
      expect(
        metadata['activeSkillIds'],
        isNot(contains('styio-cpp-compiler-project')),
      );
      final activeSkillReasons =
          metadata['activeSkillReasons']! as Map<String, Object?>;
      expect(
        activeSkillReasons['styio-language-service-truth'],
        isA<List<Object?>>(),
      );
      expect(metadata['skillIds'], contains('styio-cpp-compiler-project'));
      expect(metadata['skillIds'], contains('cpp-clang-version-handoff'));
      expect(metadata['skillIds'], contains('cpp-clang-format-tidy'));
      expect(metadata['skillIds'], contains('cpp-cmake-build-graph'));
      expect(metadata['skillIds'], contains('cpp-clangd-indexing'));
      expect(
        metadata['skillIds'],
        contains('reference-grounded-ide-development'),
      );
      expect(metadata['toolchainCount'], 3);
      expect(metadata['hasNativeCompiler'], isTrue);
      expect(metadata['workspaceToolingHints'], isA<List<Object?>>());
      expect(metadata['nativeBuildToolCount'], 2);
      expect(metadata['nativeBuildToolFamilies'], <String>['cmake', 'ninja']);
      expect(metadata['nativeDebuggerCount'], 0);
      expect(metadata['nativeDebuggerFamilies'], isEmpty);
      expect(metadata['nativeFormatterCount'], 0);
      expect(metadata['nativeFormatterFamilies'], isEmpty);
      expect(metadata['nativeStaticAnalyzerCount'], 0);
      expect(metadata['nativeStaticAnalyzerFamilies'], isEmpty);
      expect(metadata['nativeTestRunnerCount'], 0);
      expect(metadata['nativeTestRunnerFamilies'], isEmpty);
      expect(metadata['nativeLanguageServiceCount'], 0);
      expect(metadata['nativeLanguageServiceFamilies'], isEmpty);
      expect(metadata['nativeToolCommandCount'], 4);
      expect(metadata['nativeToolReadyCommandCount'], 1);
      expect(metadata['nativeToolBlockedCommandCount'], 3);
      expect(metadata['testingCommandCount'], 4);
      expect(metadata['debugReadyCommandCount'], 1);
      expect(metadata['debugBlockedCommandCount'], 6);
      expect(metadata['activeCompilerId'], 'native-clang-cpp-compiler');
      expect(metadata['openDocumentCount'], 0);
      expect(metadata['dirtyDocumentCount'], 0);
      expect(metadata['workspaceDocumentSampleCount'], 1);
      expect(metadata['workspaceDocumentSamplesTruncated'], isFalse);
      expect(metadata['workspaceLastSymbolSearchMatchCount'], 1);
      expect(metadata['hasLanguageHover'], isFalse);
      expect(metadata['hasFocusToken'], isFalse);
      expect(metadata['languageFocusedDiagnosticCount'], 0);
      expect(metadata['languageReferenceCount'], 0);
      expect(metadata['hasResolvedElement'], isFalse);
      expect(metadata['hasResolvedReference'], isFalse);
      expect(metadata['hasParameterInfo'], isFalse);
      expect(metadata['languageParameterCount'], 0);
      expect(metadata['languageCompletionCount'], 0);
      expect(metadata['languageCodeActionCount'], 0);
      expect(metadata['languageSemanticSpanCount'], 0);
      expect(metadata['languageDocumentSymbolCount'], 0);
      expect(metadata['languageInlayHintCount'], 0);
      expect(metadata['languageSemanticBlockCount'], 0);
      expect(metadata['languageRefactorPreviewCount'], 0);
      expect(metadata['languageSurroundTemplateCount'], 0);
      expect(metadata['languageServiceSeverity'], 'ready');
      expect(metadata['languageServiceUsableCapabilityCount'], 2);
      expect(metadata['languageServiceFreshCapabilityCount'], 1);
      expect(metadata['languageServiceLocalFallbackEnabled'], isTrue);
      expect(metadata['languageServiceParserEngine'], 'nightly');
      expect(metadata['languageServiceGrammarVersion'], '2026.05');
      expect(metadata['providerExecutionStatus'], 'fallback_ready');
      expect(metadata['providerExecutionEndpointCount'], 2);
      expect(metadata['providerExecutionMissingCredentialEndpointCount'], 1);
      expect(metadata['providerExecutionSelectedEndpointIndex'], 1);
      expect(metadata['providerExecutionSelectedRouteKind'], 'cloud');
      expect(
        metadata['providerExecutionSelectedProviderKind'],
        'cloud_openai_compatible',
      );
      expect(
        metadata['providerExecutionSelectedCredentialReadiness'],
        'available',
      );
      expect(
        (metadata['languageServicePrimaryCapabilityStates']!
            as Map<String, Object?>)['hover'],
        'unsupported',
      );
      expect(metadata['debugStatus'], 'idle');
      expect(metadata['debugBreakpointCount'], 0);
      expect(metadata['debugThreadCount'], 0);
      expect(metadata['debugStackFrameCount'], 0);
      expect(metadata['debugVariableCount'], 0);
      expect(metadata['persistenceCommandCount'], 2);
      expect(metadata['executionCommandCount'], 1);
      expect(metadata['diagnosticCommandCount'], 5);
      expect(metadata['languageServiceCommandCount'], 1);
      expect(metadata['navigationCommandCount'], 7);
      expect(metadata['refactorCommandCount'], 3);
      expect(metadata['dependencyCommandCount'], 2);
      expect(metadata['deploymentCommandCount'], 2);
      expect(metadata['moduleCommandCount'], 1);
      expect(
        metadata['surfaceCommandCount'],
        StyioCommandRegistry.surfaceCommands.length,
      );
      expect(metadata['testingCommandCount'], 4);
      expect(metadata['debugCommandCount'], 7);
      expect(metadata['settingsCommandCount'], 1);
      expect(metadata['recentCommandResultCount'], 1);
      expect(metadata['recentCommandIds'], <String>['searchWorkspace']);
      expect(metadata['lastCommandId'], 'searchWorkspace');
      expect(metadata['lastCommandInput'], 'value');
      expect(metadata['lastCommandApplied'], isTrue);
      expect(
        metadata['lastCommandMessage'],
        'Agent command searchWorkspace completed for value.',
      );
      expect(metadata['lastCommandMetadataKeys'], <String>[
        'searchResult',
        'requiredCommand',
        'backendRouteSelection',
        'toolchainSelectionStatus',
        'toolchainSelectionMessage',
        'toolchainId',
        'cppStandard',
        'buildEngineHandoffCount',
        'preferredBuildEngineHandoff',
        'settingsRoute',
        'settingsSection',
        'recoveryForCommandId',
      ]);
      expect(metadata['lastCommandRequiredCommandId'], 'runBuild');
      expect(metadata['lastCommandRecoveryForCommandId'], 'runBuild');
      expect(metadata['lastCommandBackendRouteKind'], 'blocked');
      expect(metadata['lastCommandBackendRouteAdapterKind'], 'none');
      expect(metadata['lastCommandBackendRouteAllowed'], isFalse);
      expect(metadata['lastCommandBackendRoutePreviewOnly'], isFalse);
      expect(
        metadata['lastCommandBackendRouteBlockedReason'],
        'no-backend-route',
      );
      expect(metadata['lastCommandToolchainSelectionStatus'], 'selected');
      expect(
        metadata['lastCommandToolchainSelectionMessage'],
        'Clang/C++ version selected.',
      );
      expect(metadata['lastCommandToolchainId'], 'native-clang-cpp-compiler');
      expect(metadata['lastCommandCppStandard'], 'c++23');
      expect(metadata['lastCommandSettingsRoute'], 'settings');
      expect(metadata['lastCommandSettingsSection'], 'toolchain');
      expect(metadata['lastCommandBuildEngineHandoffCount'], 3);
      expect(metadata['lastCommandPreferredBuildEngine'], 'cmake');
      expect(metadata['lastCommandPreferredBuildGenerator'], 'ninja');
      expect(metadata['lastCommandCompletedAt'], '2026-05-19T01:02:03.000Z');
      expect(metadata['pendingPatchId'], 'patch-pending');
      expect(metadata['pendingPatchEditCount'], 1);
      expect(metadata['pendingPatchDocumentCount'], 1);
      expect(metadata['pendingPatchEditsTruncated'], isFalse);
      expect(metadata['agentSuggestedCommandCount'], 4);
      expect(metadata['agentSuggestedCommandIds'], <String>[
        'runBuild',
        'collectAgentCodingCheckpoint',
        'retryAgentProvider',
        'replayAgentPrompt',
      ]);
      expect(metadata['agentChangeReviewStatus'], 'needsReview');
      expect(metadata['agentChangeReviewCanApplyPreview'], isTrue);
      expect(metadata['agentChangeReviewRequiresUserReview'], isTrue);
      expect(
        metadata['agentChangeReviewIssueCodes'],
        contains('agent.change.requires-review'),
      );
      expect(metadata['agentAutonomyMode'], 'reviewBeforeApply');
      expect(metadata['agentAutonomyCanProposePatches'], isTrue);
      expect(metadata['agentAutonomyCanApplyWithoutReview'], isFalse);
      expect(metadata['agentAutonomyRequiresExplicitUserApproval'], isTrue);
      expect(metadata['agentValidationStatus'], 'waitingForReview');
      expect(metadata['agentValidationShouldRun'], isFalse);
      expect(
        metadata['agentValidationRegisteredCommandIds'],
        contains('collectAgentCodingCheckpoint'),
      );
      expect(metadata['agentValidationCommandPlanCount'], 1);
      expect(metadata['agentValidationInputCommandIds'], isEmpty);
      expect(metadata['agentValidationResultStatus'], 'notStarted');
      expect(
        metadata['agentValidationMissingCommandIds'],
        contains('collectAgentCodingCheckpoint'),
      );
      expect(metadata['agentValidationPipelineStatus'], 'waiting');
      expect(metadata['agentValidationPipelineNextCommandId'], isNull);
      expect(metadata['agentValidationPipelineProgress'], '0/0');
      expect(metadata['recentPatchProposalCount'], 1);
      expect(metadata['recentPatchProposalIds'], <String>['patch-pending']);
      expect(metadata['pendingIdeCommandCount'], 1);
      expect(metadata['pendingIdeCommandMissingInputCount'], 0);
      expect(metadata['pendingIdeCommandIds'], <String>['runBuild']);
      expect(metadata['recentIdeCommandSuggestionCount'], 1);
      expect(metadata['recentIdeCommandSuggestionIds'], <String>['runBuild']);
      expect(metadata['lastProviderFailureKind'], 'timeout');
      expect(
        metadata['lastProviderFailureOperation'],
        'agent.provider.postJson',
      );
      expect(metadata['recentPatchApplicationCount'], 1);
      expect(metadata['recentPatchApplicationPatchIds'], <String>[
        'patch-applied',
      ]);
      expect(metadata['lastPatchApplicationPatchId'], 'patch-applied');
      expect(metadata['lastPatchApplicationApplied'], isTrue);
      expect(metadata['lastPatchApplicationPendingPatchRetained'], isFalse);
      expect(
        metadata['lastPatchApplicationMessage'],
        'Applied 1 agent patch edit(s).',
      );
      expect(metadata['lastPatchApplicationEditCount'], 1);
      expect(metadata['lastPatchApplicationAppliedEditCount'], 1);
      expect(metadata['lastPatchApplicationChangedDocumentCount'], 1);
      expect(metadata['lastPatchApplicationSkippedNoOpDocumentCount'], 1);
      final providerContractMessage = messages.first! as Map<String, Object?>;
      expect(
        providerContractMessage['content'],
        contains('OpenCode-style explicit agent registries'),
      );
      expect(
        providerContractMessage['content'],
        contains('schema-backed tool definitions'),
      );
      expect(
        providerContractMessage['content'],
        contains('allow/deny/ask permission rules'),
      );
      expect(
        providerContractMessage['content'],
        contains('agent.agentRegistry'),
      );
      expect(providerContractMessage['content'], contains('activeAgentId'));
      expect(providerContractMessage['content'], contains('resultSchema'));
      expect(providerContractMessage['content'], contains('resultJsonSchema'));
      expect(
        providerContractMessage['content'],
        contains('deferred capability entries'),
      );
      final contextMessage = messages[1]! as Map<String, Object?>;
      expect(contextMessage['name'], 'vityo_ide_context');
      expect(
        contextMessage['content'],
        contains('/workspace/demo/src/main.styio'),
      );
      expect(contextMessage['content'], contains('documentSamples'));
      expect(contextMessage['content'], contains('"debug"'));
      expect(contextMessage['content'], contains('"serviceStatus"'));
      expect(contextMessage['content'], contains('pendingPatch'));
      expect(contextMessage['content'], contains('patch-pending'));
      expect(contextMessage['content'], contains('recentPatchProposals'));
      expect(contextMessage['content'], contains('pendingIdeCommands'));
      expect(contextMessage['content'], contains('runBuild'));
      expect(
        contextMessage['content'],
        contains('recentIdeCommandSuggestions'),
      );
      expect(contextMessage['content'], contains('lastProviderFailure'));
      expect(contextMessage['content'], contains('provider timed out'));
      expect(contextMessage['content'], contains('recentPatchApplications'));
      expect(contextMessage['content'], contains('lastPatchApplication'));
      expect(contextMessage['content'], contains('patch-applied'));
      expect(contextMessage['content'], contains('lastResult'));
      expect(contextMessage['content'], contains('cmakeExecutablePath'));
      expect(contextMessage['content'], contains('/usr/bin/cmake'));
      expect(contextMessage['content'], contains('ninjaExecutablePath'));
      expect(contextMessage['content'], contains('/usr/bin/ninja'));
      final promptMessage = messages.last! as Map<String, Object?>;
      expect(promptMessage['content'], 'Explain this file.');
      expect(response.requestId, 'agent-request-3');
      expect(response.providerMessageId, 'chatcmpl-test');
      expect(response.contentParts.single.text, 'Context received.');
      expect(response.finishReason, 'stop');
    },
  );

  test(
    'OpenAI-compatible adapter places IDE context before current prompt after history',
    () async {
      const document = DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      );
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-message-order',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: document,
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Now change it.',
        conversationTurns: <AgentConversationTurn>[
          AgentConversationTurn(
            turnId: 'turn-1',
            role: AgentConversationRole.user,
            text: 'Explain it first.',
            createdAt: DateTime.utc(2026, 5, 18),
          ),
          AgentConversationTurn(
            turnId: 'turn-2',
            role: AgentConversationRole.assistant,
            text: 'It sets value to 1.',
            createdAt: DateTime.utc(2026, 5, 18, 0, 1),
          ),
        ],
      );
      final transport = _RecordingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: profile.endpoint,
      );

      await adapter.send(request);

      final messages = transport.body['messages']! as List<Object?>;
      expect(messages, hasLength(5));
      expect(
        (messages[1]! as Map<String, Object?>)['content'],
        'Explain it first.',
      );
      expect(
        (messages[2]! as Map<String, Object?>)['content'],
        'It sets value to 1.',
      );
      expect(
        (messages[3]! as Map<String, Object?>)['name'],
        'vityo_ide_context',
      );
      expect(
        (messages[4]! as Map<String, Object?>)['content'],
        'Now change it.',
      );
    },
  );

  test(
    'OpenAI-compatible adapter sends attachments before current prompt',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-attachments',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Use the attached note.',
        attachments: const <AgentRequestAttachment>[
          AgentRequestAttachment(
            attachmentId: 'note-1',
            kind: 'text',
            name: 'note.txt',
            content: 'prefer simple edits',
            metadata: <String, Object?>{
              'documentId': 'main.styio',
              'revision': 1,
            },
          ),
        ],
      );
      final transport = _RecordingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: profile.endpoint,
      );

      await adapter.send(request);

      final messages = transport.body['messages']! as List<Object?>;
      final metadata = transport.body['metadata']! as Map<String, Object?>;
      final attachmentMessage = messages[2]! as Map<String, Object?>;
      final promptMessage = messages.last! as Map<String, Object?>;

      expect(metadata['attachmentCount'], 1);
      expect(metadata['attachmentKinds'], <String>['text']);
      expect(metadata['conversationTurnCount'], 0);
      expect(attachmentMessage['name'], 'vityo_agent_attachments');
      expect(attachmentMessage['content'], contains('note.txt'));
      expect(attachmentMessage['content'], contains('prefer simple edits'));
      expect(
        attachmentMessage['content'],
        contains('"documentId":"main.styio"'),
      );
      expect(attachmentMessage['content'], contains('"revision":1'));
      expect(promptMessage['content'], 'Use the attached note.');
    },
  );

  test('OpenAI-compatible adapter truncates oversized attachments', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final request = AgentProviderRequest(
      requestId: 'agent-request-large-attachment',
      profile: profile,
      context: AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: '/workspace/demo/src/main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const [],
      ),
      userPrompt: 'Use the attached note.',
      attachments: <AgentRequestAttachment>[
        AgentRequestAttachment(
          attachmentId: 'large-note',
          kind: 'text',
          name: 'large-note.txt',
          content: List<String>.filled(20001, 'a').join(),
        ),
      ],
    );
    final transport = _RecordingAgentProviderTransport();
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: transport,
      endpoint: profile.endpoint,
    );

    await adapter.send(request);

    final messages = transport.body['messages']! as List<Object?>;
    final metadata = transport.body['metadata']! as Map<String, Object?>;
    final attachmentMessage = messages[2]! as Map<String, Object?>;
    final attachmentJson = Map<String, Object?>.from(
      jsonDecode(attachmentMessage['content']! as String) as Map,
    );
    final attachments = attachmentJson['attachments']! as List<Object?>;
    final attachment = attachments.single! as Map<String, Object?>;

    expect(metadata['attachmentTruncatedCount'], 1);
    expect((attachment['content']! as String).length, 20000);
    expect(attachment['contentTruncated'], isTrue);
  });

  test(
    'OpenAI-compatible adapter drops non-json-safe attachment metadata',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-attachment-metadata',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Use the attached note.',
        attachments: const <AgentRequestAttachment>[
          AgentRequestAttachment(
            attachmentId: 'note-1',
            kind: 'text',
            name: 'note.txt',
            content: 'prefer simple edits',
            metadata: <String, Object?>{
              'documentId': 'main.styio',
              'revision': 1,
              'invalid': Object(),
            },
          ),
        ],
      );
      final transport = _RecordingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: profile.endpoint,
      );

      await adapter.send(request);

      final messages = transport.body['messages']! as List<Object?>;
      final attachmentMessage = messages[2]! as Map<String, Object?>;
      final attachmentJson = Map<String, Object?>.from(
        jsonDecode(attachmentMessage['content']! as String) as Map,
      );
      final attachments = attachmentJson['attachments']! as List<Object?>;
      final attachment = attachments.single! as Map<String, Object?>;
      final metadata = Map<String, Object?>.from(
        attachment['metadata']! as Map,
      );

      expect(metadata['documentId'], 'main.styio');
      expect(metadata['revision'], 1);
      expect(metadata.containsKey('invalid'), isFalse);
    },
  );

  test(
    'OpenAI-compatible adapter parses structured code patch content',
    () async {
      const document = DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      );
      final context = AgentSessionContext.fromEditorState(
        document: document,
        selection: const SelectionState.collapsed(0),
        diagnostics: const [],
      );
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-4',
        profile: profile,
        context: context,
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _StructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(response.contentParts.first.text, 'Patch ready.');
      expect(patchPart.patch?.patchId, 'patch-1');
      expect(patchPart.patch?.baseRevision, 1);
      expect(
        patchPart.patch?.edits.single.documentId,
        '/workspace/demo/src/main.styio',
      );
      expect(patchPart.patch?.edits.single.replacementText, '2');
    },
  );

  test(
    'OpenAI-compatible adapter parses structured IDE command content',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-command',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\nvalue\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(10),
          diagnostics: const [],
        ),
        userPrompt: 'Rename value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _StructuredIdeCommandTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final commandPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.ideCommand,
      );

      expect(commandPart.text, 'Use Rename Symbol.');
      expect(commandPart.ideCommand?.commandId, 'renameSymbol');
      expect(commandPart.ideCommand?.input, 'price');
      expect(commandPart.ideCommand?.reason, contains('safe refactor'));
      expect(commandPart.toJson()['ideCommand'], isA<Map<String, Object?>>());
    },
  );

  test('OpenAI-compatible adapter parses structured plan content', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final request = AgentProviderRequest(
      requestId: 'agent-request-plan',
      profile: profile,
      context: AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: '/workspace/demo/src/main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const [],
      ),
      userPrompt: 'Plan this refactor.',
    );
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: _StructuredPlanTransport(),
      endpoint: profile.endpoint,
    );

    final response = await adapter.send(request);
    final planPart = response.contentParts.singleWhere(
      (part) => part.kind == AgentContentPartKind.plan,
    );

    expect(planPart.text, 'Plan before patch.');
    expect(planPart.plan?.summary, 'Update active document safely.');
    expect(planPart.plan?.steps, <String>[
      'Inspect IDE facts.',
      'Prepare patch.',
    ]);
    expect(planPart.plan?.acceptanceCriteria, <String>[
      'Patch preview is shown.',
    ]);
  });

  test(
    'OpenAI-compatible adapter parses structured diagnostic summary content',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-diagnostic-summary',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Summarize diagnostics.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _StructuredDiagnosticSummaryTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final summaryPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.diagnosticSummary,
      );

      expect(summaryPart.text, 'Diagnostics summarized.');
      expect(summaryPart.diagnosticSummary?.title, 'Build failed.');
      expect(summaryPart.diagnosticSummary?.severity, 'error');
      expect(summaryPart.diagnosticSummary?.diagnosticCount, 1);
      expect(summaryPart.diagnosticSummary?.affectedDocuments, <String>[
        'src/parser.cc',
      ]);
      expect(summaryPart.diagnosticSummary?.suggestedCommandIds, <String>[
        'runBuild',
      ]);
    },
  );

  test(
    'OpenAI-compatible adapter parses fenced structured code patch content',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-5',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _FencedStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-fenced');
      expect(patchPart.patch?.edits.single.replacementText, '3');
    },
  );

  test(
    'OpenAI-compatible adapter skips non-json fences before patch JSON',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-mixed-fences',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _MixedFenceStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-mixed-fences');
      expect(patchPart.patch?.edits.single.replacementText, '5');
    },
  );

  test(
    'OpenAI-compatible adapter parses prefixed structured code patch content',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-prefixed',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _PrefixedStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-prefixed');
      expect(patchPart.patch?.edits.single.replacementText, '6');
    },
  );

  test(
    'OpenAI-compatible adapter parses structured code patch tool call arguments',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-tool-call',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _ToolCallStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-tool-call');
      expect(patchPart.patch?.edits.single.replacementText, '7');
    },
  );

  test(
    'OpenAI-compatible adapter parses tool call arguments when content is blank',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-tool-call-blank-content',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _ToolCallBlankContentStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-tool-call-blank-content');
      expect(patchPart.patch?.edits.single.replacementText, '8');
    },
  );

  test(
    'OpenAI-compatible adapter merges text content and tool call patch',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-tool-call-with-text',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _ToolCallWithTextStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(response.contentParts.first.text, 'I prepared a patch.');
      expect(patchPart.patch?.patchId, 'patch-tool-call-with-text');
      expect(patchPart.patch?.edits.single.replacementText, '9');
    },
  );

  test(
    'OpenAI-compatible adapter parses responses output message and function call',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-responses-output',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _ResponsesOutputStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(response.providerMessageId, 'resp-patch-output');
      expect(response.finishReason, 'completed');
      expect(response.contentParts.first.text, 'I prepared a patch.');
      expect(response.contentParts.where((part) => part.text.isEmpty), isEmpty);
      expect(patchPart.patch?.patchId, 'patch-responses-output');
      expect(patchPart.patch?.edits.single.replacementText, '10');
    },
  );

  test('OpenAI-compatible adapter parses output text content blocks', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final request = AgentProviderRequest(
      requestId: 'agent-request-output-text',
      profile: profile,
      context: AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: '/workspace/demo/src/main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const [],
      ),
      userPrompt: 'Explain value.',
    );
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: _OutputTextBlockTransport(),
      endpoint: profile.endpoint,
    );

    final response = await adapter.send(request);

    expect(response.contentParts.single.text, 'Value is set to 1.');
  });

  test(
    'OpenAI-compatible adapter parses structured code patch content blocks',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-blocks',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _StructuredPatchBlocksTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-blocks');
      expect(
        patchPart.patch?.edits.single.operation,
        AgentCodePatchEditOperation.create,
      );
      expect(
        patchPart.patch?.edits.single.replacementText,
        'created by agent\n',
      );
    },
  );

  test(
    'OpenAI-compatible adapter parses snake case structured code patch content',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-6',
        profile: profile,
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
        ),
        userPrompt: 'Change value.',
      );
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: _SnakeCaseStructuredPatchTransport(),
        endpoint: profile.endpoint,
      );

      final response = await adapter.send(request);
      final patchPart = response.contentParts.singleWhere(
        (part) => part.kind == AgentContentPartKind.codePatch,
      );

      expect(patchPart.patch?.patchId, 'patch-snake');
      expect(patchPart.patch?.baseRevision, 1);
      expect(
        patchPart.patch?.edits.single.documentId,
        '/workspace/demo/src/main.styio',
      );
      expect(patchPart.patch?.edits.single.replacementText, '4');
    },
  );

  test(
    'OpenAI-compatible adapter filters context by profile channels',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final request = AgentProviderRequest(
        requestId: 'agent-request-filter',
        profile: AgentPromptProfile(
          profileId: profile.profileId,
          displayName: profile.displayName,
          systemPrompt: profile.systemPrompt,
          endpoint: profile.endpoint,
          contextChannels: const <String>['file'],
        ),
        context: AgentSessionContext.fromEditorState(
          document: const DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          selection: const SelectionState.collapsed(0),
          diagnostics: const [],
          workspaceFiles: const <String>['/workspace/demo/src/main.styio'],
          activeFilePath: '/workspace/demo/src/main.styio',
        ),
        userPrompt: 'Explain this file.',
      );
      final transport = _RecordingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: profile.endpoint,
      );

      await adapter.send(request);

      final messages = transport.body['messages']! as List<Object?>;
      final contextMessage = messages[1]! as Map<String, Object?>;
      final contextJson = Map<String, Object?>.from(
        jsonDecode(contextMessage['content']! as String) as Map,
      );

      expect(contextJson.containsKey('document'), isTrue);
      expect(contextJson.containsKey('workspace'), isFalse);
      expect(contextJson.containsKey('selection'), isFalse);
      expect(contextJson.containsKey('language'), isFalse);
      expect(contextJson.containsKey('commands'), isFalse);
    },
  );

  test(
    'OpenAI-compatible adapter accepts full chat completions endpoint',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final transport = _RecordingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: AgentProviderEndpoint(
          route: profile.endpoint.route,
          baseUrl: 'https://agent.example.test/v1/chat/completions',
          model: profile.endpoint.model,
        ),
      );

      await adapter.send(
        AgentProviderRequest(
          requestId: 'agent-request-endpoint',
          profile: profile,
          context: AgentSessionContext.fromEditorState(
            document: const DocumentState(
              documentId: 'main.styio',
              text: 'value = 1\n',
              revision: 1,
            ),
            selection: const SelectionState.collapsed(0),
            diagnostics: const [],
          ),
          userPrompt: 'Explain this file.',
        ),
      );

      expect(
        transport.endpoint.toString(),
        'https://agent.example.test/v1/chat/completions',
      );
    },
  );
}

ConfigurationStore _createAgentProviderConfigurationStore(Directory root) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  return ConfigurationStore(
    dataStore: FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    ),
    credentialDataStore: InMemoryCredentialDataStore(),
  );
}

class _RecordingAgentProviderTransport implements AgentProviderTransport {
  late Uri endpoint;
  late Map<String, String> headers;
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.endpoint = endpoint;
    this.headers = headers;
    this.body = body;
    return <String, Object?>{
      'id': 'chatcmpl-test',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'Context received.',
          },
        },
      ],
      'usage': <String, Object?>{'prompt_tokens': 12, 'completion_tokens': 3},
    };
  }
}

class _StructuredPatchTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
{
  "contentParts": [
    {
      "kind": "text",
      "text": "Patch ready."
    },
    {
      "kind": "code_patch",
      "text": "Change value.",
      "patch": {
        "patchId": "patch-1",
        "summary": "Change value.",
        "baseRevision": 1,
        "edits": [
          {
            "documentId": "/workspace/demo/src/main.styio",
            "start": 8,
            "end": 9,
            "replacementText": "2"
          }
        ]
      }
    }
  ]
}
''',
          },
        },
      ],
    };
  }
}

class _StructuredIdeCommandTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-command',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
{
  "contentParts": [
    {
      "kind": "ide_command",
      "text": "Use Rename Symbol.",
      "command": {
        "commandId": "renameSymbol",
        "input": "price",
        "reason": "Use the registered safe refactor instead of raw edits."
      }
    }
  ]
}
''',
          },
        },
      ],
    };
  }
}

class _StructuredPlanTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-plan',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
{
  "contentParts": [
    {
      "kind": "plan",
      "text": "Plan before patch.",
      "plan": {
        "summary": "Update active document safely.",
        "steps": ["Inspect IDE facts.", "Prepare patch."],
        "acceptanceCriteria": ["Patch preview is shown."]
      }
    }
  ]
}
''',
          },
        },
      ],
    };
  }
}

class _StructuredDiagnosticSummaryTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-diagnostic-summary',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
{
  "contentParts": [
    {
      "kind": "diagnostic_summary",
      "text": "Diagnostics summarized.",
      "diagnosticSummary": {
        "title": "Build failed.",
        "summary": "Parser target failed with one error.",
        "severity": "error",
        "diagnosticCount": 1,
        "affectedDocuments": ["src/parser.cc"],
        "suggestedCommandIds": ["runBuild"]
      }
    }
  ]
}
''',
          },
        },
      ],
    };
  }
}

class _FencedStructuredPatchTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-fenced',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
```json
{
  "contentParts": [
    {
      "kind": "code_patch",
      "text": "Change value.",
      "patch": {
        "patchId": "patch-fenced",
        "summary": "Change value.",
        "baseRevision": 1,
        "edits": [
          {
            "documentId": "/workspace/demo/src/main.styio",
            "start": 8,
            "end": 9,
            "replacementText": "3"
          }
        ]
      }
    }
  ]
}
```
''',
          },
        },
      ],
    };
  }
}

class _MixedFenceStructuredPatchTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-mixed-fences',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
Here is the current code:

```styio
value = 1
```

And here is the patch:

```json
{
  "contentParts": [
    {"kind": "text", "text": "Patch ready."},
    {
      "kind": "code_patch",
      "text": "Change value.",
      "patch": {
        "patchId": "patch-mixed-fences",
        "summary": "Change value.",
        "edits": [
          {
            "documentId": "/workspace/demo/src/main.styio",
            "start": 8,
            "end": 9,
            "replacementText": "5"
          }
        ]
      }
    }
  ]
}
```
''',
          },
        },
      ],
    };
  }
}

class _PrefixedStructuredPatchTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-prefixed',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
Here is the patch:
{
  "contentParts": [
    {
      "kind": "code_patch",
      "text": "Change value.",
      "patch": {
        "patchId": "patch-prefixed",
        "summary": "Change value.",
        "baseRevision": 1,
        "edits": [
          {
            "documentId": "/workspace/demo/src/main.styio",
            "start": 8,
            "end": 9,
            "replacementText": "6"
          }
        ]
      }
    }
  ]
}
''',
          },
        },
      ],
    };
  }
}

class _ExecutableToolCallTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-executable-tool-call',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'tool_calls',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': null,
            'tool_calls': <Object?>[
              <String, Object?>{
                'id': 'call-read',
                'type': 'function',
                'function': <String, Object?>{
                  'name': 'readWorkspaceFile',
                  'arguments': '{"path":"main.styio"}',
                },
              },
            ],
          },
        },
      ],
    };
  }
}

class _CustomExecutableToolCallTransport implements AgentProviderTransport {
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    this.body = body;
    return <String, Object?>{
      'id': 'resp-custom-tool-call',
      'output': <Object?>[
        <String, Object?>{
          'type': 'function_call',
          'call_id': 'call-extension',
          'name': 'collectExtensionContext',
          'arguments': '{"extensionId":"demo"}',
        },
      ],
    };
  }
}

class _ToolCallStructuredPatchTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-tool-call',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'tool_calls',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': null,
            'tool_calls': <Object?>[
              <String, Object?>{
                'type': 'function',
                'function': <String, Object?>{
                  'name': 'vityo_code_patch',
                  'arguments': jsonEncode(<String, Object?>{
                    'contentParts': <Object?>[
                      <String, Object?>{
                        'kind': 'code_patch',
                        'text': 'Change value.',
                        'patch': <String, Object?>{
                          'patchId': 'patch-tool-call',
                          'summary': 'Change value.',
                          'baseRevision': 1,
                          'edits': <Object?>[
                            <String, Object?>{
                              'documentId': '/workspace/demo/src/main.styio',
                              'start': 8,
                              'end': 9,
                              'replacementText': '7',
                            },
                          ],
                        },
                      },
                    ],
                  }),
                },
              },
            ],
          },
        },
      ],
    };
  }
}

class _ToolCallBlankContentStructuredPatchTransport
    implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-tool-call-blank-content',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'tool_calls',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '',
            'tool_calls': <Object?>[
              <String, Object?>{
                'type': 'function',
                'function': <String, Object?>{
                  'name': 'vityo_code_patch',
                  'arguments': jsonEncode(<String, Object?>{
                    'contentParts': <Object?>[
                      <String, Object?>{
                        'kind': 'code_patch',
                        'text': 'Change value.',
                        'patch': <String, Object?>{
                          'patchId': 'patch-tool-call-blank-content',
                          'summary': 'Change value.',
                          'baseRevision': 1,
                          'edits': <Object?>[
                            <String, Object?>{
                              'documentId': '/workspace/demo/src/main.styio',
                              'start': 8,
                              'end': 9,
                              'replacementText': '8',
                            },
                          ],
                        },
                      },
                    ],
                  }),
                },
              },
            ],
          },
        },
      ],
    };
  }
}

class _ToolCallWithTextStructuredPatchTransport
    implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-tool-call-with-text',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'tool_calls',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'I prepared a patch.',
            'tool_calls': <Object?>[
              <String, Object?>{
                'type': 'function',
                'function': <String, Object?>{
                  'name': 'vityo_code_patch',
                  'arguments': jsonEncode(<String, Object?>{
                    'contentParts': <Object?>[
                      <String, Object?>{
                        'kind': 'code_patch',
                        'text': 'Change value.',
                        'patch': <String, Object?>{
                          'patchId': 'patch-tool-call-with-text',
                          'summary': 'Change value.',
                          'baseRevision': 1,
                          'edits': <Object?>[
                            <String, Object?>{
                              'documentId': '/workspace/demo/src/main.styio',
                              'start': 8,
                              'end': 9,
                              'replacementText': '9',
                            },
                          ],
                        },
                      },
                    ],
                  }),
                },
              },
            ],
          },
        },
      ],
    };
  }
}

class _ResponsesOutputStructuredPatchTransport
    implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'resp-patch-output',
      'status': 'completed',
      'output': <Object?>[
        <String, Object?>{
          'type': 'message',
          'role': 'assistant',
          'content': <Object?>[
            <String, Object?>{
              'type': 'output_text',
              'text': 'I prepared a patch.',
            },
          ],
        },
        <String, Object?>{
          'type': 'function_call',
          'name': 'vityo_code_patch',
          'arguments': jsonEncode(<String, Object?>{
            'contentParts': <Object?>[
              <String, Object?>{
                'kind': 'code_patch',
                'text': 'Change value.',
                'patch': <String, Object?>{
                  'patchId': 'patch-responses-output',
                  'summary': 'Change value.',
                  'baseRevision': 1,
                  'edits': <Object?>[
                    <String, Object?>{
                      'documentId': '/workspace/demo/src/main.styio',
                      'start': 8,
                      'end': 9,
                      'replacementText': '10',
                    },
                  ],
                },
              },
            ],
          }),
        },
      ],
    };
  }
}

class _OutputTextBlockTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-output-text',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': <Object?>[
              <String, Object?>{
                'type': 'output_text',
                'text': 'Value is set to 1.',
              },
            ],
          },
        },
      ],
    };
  }
}

class _StructuredPatchBlocksTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-blocks',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': <Object?>[
              <String, Object?>{
                'type': 'text',
                'text': jsonEncode(<String, Object?>{
                  'contentParts': <Object?>[
                    <String, Object?>{'kind': 'text', 'text': 'Patch ready.'},
                    <String, Object?>{
                      'kind': 'code_patch',
                      'text': 'Change value to 5.',
                      'patch': <String, Object?>{
                        'patchId': 'patch-blocks',
                        'summary': 'Update value.',
                        'edits': <Object?>[
                          <String, Object?>{
                            'documentId': '/workspace/demo/src/helper.txt',
                            'operation': 'create',
                            'start': 0,
                            'end': 0,
                            'replacementText': 'created by agent\n',
                          },
                        ],
                      },
                    },
                  ],
                }),
              },
            ],
          },
        },
      ],
    };
  }
}

class _SnakeCaseStructuredPatchTransport implements AgentProviderTransport {
  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-patch-snake',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': '''
{
  "content_parts": [
    {
      "kind": "code_patch",
      "content": "Change value.",
      "patch": {
        "patch_id": "patch-snake",
        "summary": "Change value.",
        "base_revision": 1,
        "edits": [
          {
            "document_id": "/workspace/demo/src/main.styio",
            "start": 8,
            "end": 9,
            "replacement_text": "4"
          }
        ]
      }
    }
  ]
}
''',
          },
        },
      ],
    };
  }
}

const _agentLanguageServiceStatus = LanguageServiceStatusSurface(
  runtimeState: 'active',
  severity: LanguageServiceStatusSeverity.ready,
  title: 'StyioService ready',
  message: 'StyioService has 2 usable capability result(s).',
  toolchainId: 'styio-cli-nightly',
  parserEngine: 'nightly',
  grammarVersion: '2026.05',
  usableCapabilityCount: 2,
  freshCapabilityCount: 1,
  primaryCapabilityStates: <String, String>{
    'diagnostics': 'available',
    'completion': 'derived',
    'hover': 'unsupported',
  },
  capabilities: <LanguageServiceCapabilityStatusItem>[
    LanguageServiceCapabilityStatusItem(
      capability: 'diagnostics',
      state: 'available',
      usable: true,
      fresh: true,
    ),
    LanguageServiceCapabilityStatusItem(
      capability: 'completion',
      state: 'derived',
      usable: true,
      fresh: false,
    ),
    LanguageServiceCapabilityStatusItem(
      capability: 'hover',
      state: 'unsupported',
      usable: false,
      fresh: false,
    ),
  ],
  localFallbackEnabled: true,
);
