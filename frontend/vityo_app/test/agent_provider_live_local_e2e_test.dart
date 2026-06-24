@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_network_transport.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/network/network.dart';

void main() {
  test(
    'OpenAI-compatible agent provider reaches live local HTTP route',
    () async {
      final requestBodies = <Map<String, Object?>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(() async {
        await for (final request in server) {
          final bodyText = await utf8.decoder.bind(request).join();
          requestBodies.add(
            (jsonDecode(bodyText) as Map).map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            ),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'id': 'chatcmpl-live-local',
              'choices': <Object?>[
                <String, Object?>{
                  'finish_reason': 'stop',
                  'message': <String, Object?>{
                    'role': 'assistant',
                    'content': 'local provider ok',
                  },
                },
              ],
              'usage': <String, Object?>{'prompt_tokens': 1},
            }),
          );
          await request.response.close();
        }
      }());

      final endpoint = AgentProviderEndpoint(
        route: AgentProviderRoute.desktopLocalBridge,
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        model: 'local-agent-test',
      );
      final defaultProfile = AgentPromptProfile.defaultForPlatform(
        PlatformTarget.linux,
      );
      final profile = AgentPromptProfile(
        profileId: defaultProfile.profileId,
        displayName: defaultProfile.displayName,
        systemPrompt: defaultProfile.systemPrompt,
        endpoint: endpoint,
        contextChannels: defaultProfile.contextChannels,
      );
      final controller = AgentCodingSessionController(
        profile: profile,
        adapter: OpenAICompatibleAgentProviderAdapter(
          transport: NetworkAgentProviderTransport(
            networkManager: LocalNetworkManager.linuxDebianArmForTest(),
            timeout: const Duration(seconds: 5),
          ),
          endpoint: endpoint,
        ),
        contextProvider: _context,
      );

      controller.updatePrompt('Explain this file.');
      final response = await controller.sendPrompt();

      expect(response?.providerMessageId, 'chatcmpl-live-local');
      expect(response?.contentParts.single.text, 'local provider ok');
      expect(controller.lastError, isNull);
      expect(controller.lastProviderFailure, isNull);
      expect(controller.conversationTurns.map((turn) => turn.role), [
        AgentConversationRole.user,
        AgentConversationRole.assistant,
      ]);
      expect(requestBodies, hasLength(1));
      expect(requestBodies.single['model'], 'local-agent-test');
      final messages = requestBodies.single['messages']! as List<Object?>;
      expect(messages.last, isA<Map>());
      expect((messages.last! as Map)['content'], 'Explain this file.');
    },
  );

  test(
    'OpenAI Responses Codex Spark provider posts tool schema locally',
    () async {
      final requestBodies = <Map<String, Object?>>[];
      final requestPaths = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(() async {
        await for (final request in server) {
          requestPaths.add(request.uri.path);
          final bodyText = await utf8.decoder.bind(request).join();
          requestBodies.add(
            (jsonDecode(bodyText) as Map).map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            ),
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(<String, Object?>{
              'id': 'resp-codex-spark-local',
              'status': 'completed',
              'output_text': 'codex spark local ok',
            }),
          );
          await request.response.close();
        }
      }());

      final preset = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      );
      final endpoint = AgentProviderEndpoint(
        route: AgentProviderRoute.desktopLocalBridge,
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        model: preset.endpoint.model,
        protocol: preset.endpoint.protocol,
        reasoningEffort: preset.endpoint.reasoningEffort,
        requiresCredential: false,
      );
      final profile = preset.copyWith(endpoint: endpoint);
      final controller = AgentCodingSessionController(
        profile: profile,
        adapter: OpenAIResponsesAgentProviderAdapter(
          transport: NetworkAgentProviderTransport(
            networkManager: LocalNetworkManager.linuxDebianArmForTest(),
            timeout: const Duration(seconds: 5),
          ),
          endpoint: endpoint,
        ),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      controller.updatePrompt('Patch this Styio file.');
      final response = await controller.sendPrompt();

      expect(response?.providerMessageId, 'resp-codex-spark-local');
      expect(response?.contentParts.single.text, 'codex spark local ok');
      expect(controller.lastError, isNull);
      expect(controller.lastProviderFailure, isNull);
      expect(requestPaths, <String>['/v1/responses']);
      expect(requestBodies, hasLength(1));
      expect(requestBodies.single['model'], 'gpt-5.3-codex-spark');
      expect(requestBodies.single['tool_choice'], 'auto');
      expect(
        (requestBodies.single['reasoning']! as Map<String, Object?>)['effort'],
        'high',
      );
      final tools = requestBodies.single['tools']! as List<Object?>;
      final toolNames = tools
          .whereType<Map<String, Object?>>()
          .map((tool) => tool['name'])
          .toList(growable: false);
      expect(toolNames, contains('vityo_code_patch'));
      expect(toolNames, contains('vityo_ide_command'));
    },
  );
}

AgentSessionContext _context() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}
