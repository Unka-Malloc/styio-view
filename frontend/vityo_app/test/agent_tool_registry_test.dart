import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent tool registry selects OpenAI Responses patch tools', () {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );

    expect(selection.toolIds.first, 'readWorkspaceFile');
    expect(selection.toolIds, contains('applyWorkspacePatch'));
    expect(selection.toolIds, contains('previewWorkspaceEdit'));
    expect(selection.toolIds, contains('runIdeCommand'));
    expect(selection.toolIds, contains('collectStyioLanguageContext'));
    expect(selection.toolIds, contains('collectAgentValidationContext'));
    expect(selection.toolIds, contains('collectAgentRecoveryContext'));
    expect(selection.toolIds, contains('collectAgentCodingCheckpoint'));
    expect(selection.toolIds, isNot(contains('openLocalShell')));
    expect(selection.rejectedToolIds, contains('openLocalShell'));
    expect(selection.toJson()['toolCount'], selection.tools.length);
    expect(selection.todoItems.join('\n'), contains('File System Manager'));
    expect(selection.todoItems.join('\n'), isNot(contains('per-tool')));
  });

  test('agent tool registry exposes local bridge shell tools only locally', () {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.linux);
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.localBridge,
    );

    expect(selection.toolIds, contains('openLocalShell'));
    final shell = selection.tools.singleWhere(
      (tool) => tool.toolId == 'openLocalShell',
    );
    expect(shell.permissionMode, AgentToolPermissionMode.review);
    expect(shell.toJson()['schema'], isA<List<Object?>>());
  });

  test('agent tool registry manifest is metadata-only', () {
    final manifest = AgentToolRegistry().manifest();
    final tools = manifest['tools']! as List<Object?>;
    final readTool = tools.whereType<Map<String, Object?>>().firstWhere(
      (tool) => tool['toolId'] == 'readWorkspaceFile',
    );

    expect(manifest['toolCount'], tools.length);
    expect(readTool['displayName'], 'Read Workspace File');
    expect(readTool.containsKey('execute'), isFalse);
    expect(readTool['permissionMode'], 'never');
  });

  test('agent tool registry resolves provider-specific output budgets', () {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final context = AgentToolSelectionContext.fromProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );
    final registry = AgentToolRegistry(
      tools: const <AgentToolDefinition>[
        AgentToolDefinition(
          toolId: 'collectExtensionContext',
          displayName: 'Collect Extension Context',
          description: 'Collect context from an extension.',
          outputLimit: 12000,
          providerOutputLimits: <AgentProviderKind, int>{
            AgentProviderKind.cloudOpenAICompatible: 4096,
          },
        ),
      ],
    );
    final manifestTool = (registry.manifest()['tools']! as List<Object?>)
        .whereType<Map<String, Object?>>()
        .single;

    expect(
      registry.outputLimitForTool(
        toolId: 'collectExtensionContext',
        context: context,
      ),
      4096,
    );
    expect(manifestTool['outputLimit'], 12000);
    expect(manifestTool['providerOutputLimits'], <String, Object?>{
      'cloud_openai_compatible': 4096,
    });
  });
}
