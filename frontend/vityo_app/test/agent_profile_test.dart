import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent prompt profile preserves OpenAI-compatible endpoint contract', () {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.macos);
    final decoded = AgentPromptProfile.fromJson(profile.toJson());

    expect(decoded.profileId, 'default-macos');
    expect(decoded.endpoint.protocol, 'openai-compatible');
    expect(decoded.endpoint.route, AgentProviderRoute.desktopLocalBridge);
    expect(decoded.endpoint.requiresCredential, isTrue);
    expect(decoded.allowsLocalBridge, isTrue);
    expect(
      decoded.contextChannels,
      containsAll(<String>[
        'file',
        'selection',
        'diagnostics',
        'runtime',
        'debug',
        'workspace',
        'agent',
        'language',
        'commands',
        'skills',
        'testing',
        'toolchains',
        'ideCapabilities',
        'ideCapabilityClosure',
      ]),
    );
    expect(decoded.systemPrompt, contains('ideCapabilities.entries'));
    expect(
      decoded.systemPrompt,
      contains('scaffolded or deferred capability entries'),
    );
    expect(
      decoded.systemPrompt,
      contains('OpenCode-style explicit agent registries'),
    );
    expect(decoded.systemPrompt, contains('schema-backed tool definitions'));
    expect(decoded.systemPrompt, contains('allow/deny/ask permission rules'));
    expect(decoded.systemPrompt, contains('agent.agentRegistry'));
    expect(decoded.systemPrompt, contains('activeAgentId'));
    expect(decoded.systemPrompt, contains('subagentIds'));
    expect(decoded.systemPrompt, contains('resultSchema'));
    expect(decoded.systemPrompt, contains('resultJsonSchema'));
    expect(
      decoded.systemPrompt,
      contains('ideCapabilityClosure.isRuntimeMature'),
    );
    expect(
      decoded.systemPrompt,
      contains('ideCapabilityClosure.isRuntimeContractMature'),
    );
    expect(
      decoded.systemPrompt,
      contains('ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds'),
    );
    expect(
      decoded.systemPrompt,
      contains('ideCapabilityClosure.runtimeMaturityBlockingTodoCapabilityIds'),
    );
    expect(
      decoded.systemPrompt,
      contains('ideCapabilityClosure.nonBlockingTodoCapabilityIds'),
    );
    expect(decoded.systemPrompt, contains('Clang'));
    expect(decoded.systemPrompt, contains('commands.persistenceCommands'));
    expect(decoded.systemPrompt, contains('save/save-all'));
    expect(decoded.systemPrompt, contains('commands.executionCommands'));
    expect(decoded.systemPrompt, contains('metadata.executionSession'));
    expect(decoded.systemPrompt, contains('commands.dependencyCommands'));
    expect(decoded.systemPrompt, contains('metadata.dependencySourceCommand'));
    expect(decoded.systemPrompt, contains('commands.deploymentCommands'));
    expect(decoded.systemPrompt, contains('metadata.deploymentCommand'));
    expect(decoded.systemPrompt, contains('commands.moduleCommands'));
    expect(decoded.systemPrompt, contains('metadata.moduleHostRefresh'));
    expect(decoded.systemPrompt, contains('commands.surfaceCommands'));
    expect(decoded.systemPrompt, contains('showRuntime'));
    expect(decoded.systemPrompt, contains('commands.workspaceFileCommands'));
    expect(decoded.systemPrompt, contains('createWorkspaceFile'));
    expect(decoded.systemPrompt, contains('renameWorkspaceFile'));
    expect(decoded.systemPrompt, contains('deleteWorkspaceFile'));
    expect(decoded.systemPrompt, contains('previewWorkspaceReplace'));
    expect(decoded.systemPrompt, contains('applyWorkspaceReplace'));
    expect(decoded.systemPrompt, contains('testing.discovered.testCount'));
    expect(decoded.systemPrompt, contains('testing.suggestedCommandIds'));
    expect(decoded.systemPrompt, contains('testing.lastRun.failedTests'));
    expect(decoded.systemPrompt, contains('commands.testingCommands'));
    expect(decoded.systemPrompt, contains('rerunFailedTests'));
    expect(decoded.systemPrompt, contains('debugFailedTests'));
    expect(decoded.systemPrompt, contains('runTestConfiguration'));
    expect(decoded.systemPrompt, contains('debugTestConfiguration'));
    expect(decoded.systemPrompt, contains('testing.configurationSet'));
    expect(decoded.systemPrompt, contains('testing.rerunFailed'));
    expect(decoded.systemPrompt, contains('testing.debugFailed'));
    expect(decoded.systemPrompt, contains('testing.debugFailedRoutePlan'));
    expect(decoded.systemPrompt, contains('skills.activeSkillIds'));
    expect(decoded.systemPrompt, contains('workspace-activated coding skills'));
    expect(decoded.systemPrompt, contains('workspace.sourceControlContext'));
    expect(
      decoded.systemPrompt,
      contains('workspace.sourceControlContext.suggestedCommandIds'),
    );
    expect(decoded.systemPrompt, contains('commands.sourceControlCommands'));
    expect(decoded.systemPrompt, contains('commands.registeredCommandIds'));
    expect(decoded.systemPrompt, contains('stageSourceControl'));
    expect(decoded.systemPrompt, contains('unstageSourceControl'));
    expect(decoded.systemPrompt, contains('planSourceControlBranchSwitch'));
    expect(decoded.systemPrompt, contains('planSourceControlCommitDraft'));
    expect(decoded.systemPrompt, contains('ready source-control actions'));
    expect(
      decoded.systemPrompt,
      contains('workspace.sourceControlContext.requiresHumanConfirmation'),
    );
    expect(decoded.systemPrompt, contains('language.focusToken'));
    expect(decoded.systemPrompt, contains('token nearest'));
    expect(decoded.systemPrompt, contains('language.focusedDiagnostics'));
    expect(decoded.systemPrompt, contains('suggestedCommandIds'));
    expect(decoded.systemPrompt, contains('diagnostics nearest'));
    expect(decoded.systemPrompt, contains('language.resolvedElement'));
    expect(decoded.systemPrompt, contains('language.resolvedReference'));
    expect(decoded.systemPrompt, contains('primary resolved symbol facts'));
    expect(
      decoded.systemPrompt,
      contains('language.definition.agentCommandId'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.references.agentCommandIds'),
    );
    expect(decoded.systemPrompt, contains('language.parameterInfo'));
    expect(decoded.systemPrompt, contains('signature help'));
    expect(decoded.systemPrompt, contains('language.codeActions'));
    expect(decoded.systemPrompt, contains('agentCommandInput'));
    expect(decoded.systemPrompt, contains('agentCommandLabelInput'));
    expect(decoded.systemPrompt, contains('quick-fix command inputs'));
    expect(decoded.systemPrompt, contains('language.semanticSpans'));
    expect(decoded.systemPrompt, contains('semantic token evidence'));
    expect(decoded.systemPrompt, contains('language.semanticFeatureMatrix'));
    expect(decoded.systemPrompt, contains('serviceBackedFeatureCount'));
    expect(decoded.systemPrompt, contains('codeActionFactCount'));
    expect(decoded.systemPrompt, contains('quick-fix availability'));
    expect(decoded.systemPrompt, contains('language.documentSymbols'));
    expect(decoded.systemPrompt, contains('document outline'));
    expect(decoded.systemPrompt, contains('language.inlayHints'));
    expect(decoded.systemPrompt, contains('parameter/type hints'));
    expect(decoded.systemPrompt, contains('language.semanticBlocks'));
    expect(decoded.systemPrompt, contains('structural block ranges'));
    expect(decoded.systemPrompt, contains('language.refactorPreviews'));
    expect(decoded.systemPrompt, contains('agentCommandId'));
    expect(decoded.systemPrompt, contains('safeDelete and inlineVariable'));
    expect(decoded.systemPrompt, contains('language.surroundTemplates'));
    expect(decoded.systemPrompt, contains('surround-with templates'));
    expect(decoded.systemPrompt, contains('zero-based navigation coordinates'));
    expect(decoded.systemPrompt, contains('source range line/column'));
    expect(decoded.systemPrompt, contains('use offsets for patches'));
    expect(decoded.systemPrompt, contains('metadata.requiredCommand'));
    expect(
      decoded.systemPrompt,
      contains('metadata.completedRequiredCommandFor'),
    );
    expect(decoded.systemPrompt, contains('metadata.recoveryForCommandId'));
    expect(
      decoded.systemPrompt,
      contains('agent.lastPatchApplication.pendingPatchRetained'),
    );
    expect(decoded.systemPrompt, contains('agent.suggestedCommandIds'));
    expect(decoded.systemPrompt, contains('agent.changeReviewGate'));
    expect(decoded.systemPrompt, contains('agent.autonomyPolicy'));
    expect(decoded.systemPrompt, contains('agent.validationPlan'));
    expect(decoded.systemPrompt, contains('agent.validationResult'));
    expect(decoded.systemPrompt, contains('agent.validationPipeline'));
    expect(decoded.systemPrompt, contains('agent.validationPlan.commandPlans'));
    expect(decoded.systemPrompt, contains('agent.validationResult.status'));
    expect(
      decoded.systemPrompt,
      contains('agent.validationPipeline.nextCommandId'),
    );
    expect(
      decoded.systemPrompt,
      contains('agent.validationPlan.registeredCommandIds'),
    );
    expect(decoded.systemPrompt, contains('inputMissing'));
    expect(decoded.systemPrompt, contains('provider recovery commands'));
    expect(decoded.systemPrompt, contains('commands.settingsCommands'));
    expect(decoded.systemPrompt, contains('commands.toolchainCommands'));
    expect(decoded.systemPrompt, contains('toolchains.suggestedCommandIds'));
    expect(
      decoded.systemPrompt,
      contains('toolchains.bootstrap.executionPlan'),
    );
    expect(decoded.systemPrompt, contains('metadata.toolchainCommand'));
    expect(decoded.systemPrompt, contains('useActiveCompiler'));
    expect(decoded.systemPrompt, contains('requiresInput true'));
    expect(decoded.systemPrompt, contains('inputContract'));
    expect(decoded.systemPrompt, contains('inputExamples'));
    expect(decoded.systemPrompt, contains('missing-input commands'));
    expect(decoded.systemPrompt, contains('selectClangCppVersion'));
    expect(decoded.systemPrompt, contains('metadata.formatResult'));
    expect(decoded.systemPrompt, contains('staticAnalysisResult'));
    expect(
      decoded.systemPrompt,
      contains(
        'nested buildResult/staticAnalysisResult/testResult.requiredCommand',
      ),
    );
    expect(decoded.systemPrompt, contains('agent.workspaceEdit.preview'));
    expect(
      decoded.systemPrompt,
      contains('agent.workspaceEdit.suggestedCommandIds'),
    );
    expect(
      decoded.systemPrompt,
      contains('agent.workspaceEdit.lastApplyResult'),
    );
    expect(decoded.systemPrompt, contains('metadata.workspaceEditPreview'));
    expect(decoded.systemPrompt, contains('confirmationPlan.riskLevel'));
    expect(decoded.systemPrompt, contains('confirmationPlan.blockingReasons'));
    expect(decoded.systemPrompt, contains('collectAgentCodingCheckpoint'));
    expect(decoded.systemPrompt, contains('metadata.sourceControlContext'));
    expect(decoded.systemPrompt, contains('metadata.languageServiceStatus'));
    expect(
      decoded.systemPrompt,
      contains('metadata.agentContextSchemaVersion'),
    );
    expect(decoded.systemPrompt, contains('applying applyQuickFix'));
    expect(decoded.systemPrompt, contains('backendRouteSelection'));
    expect(decoded.systemPrompt, contains('toolchainSelectionStatus'));
    expect(decoded.systemPrompt, contains('toolchainSelectionMessage'));
    expect(decoded.systemPrompt, contains('status is not selected'));
    expect(
      decoded.systemPrompt,
      contains('before another selection or build/test retry'),
    );
    expect(
      decoded.systemPrompt,
      contains('backendRouteSelection.allowed is false'),
    );
    expect(decoded.systemPrompt, contains('buildResult'));
    expect(decoded.systemPrompt, contains('testResult'));
    expect(decoded.systemPrompt, contains('debug.suggestedCommandIds'));
    expect(decoded.systemPrompt, contains('debug.status'));
    expect(decoded.systemPrompt, contains('debug.launch.ready'));
    expect(decoded.systemPrompt, contains('debug.threads'));
    expect(decoded.systemPrompt, contains('debug.stackFrames'));
    expect(decoded.systemPrompt, contains('commands.debugCommands'));
    expect(decoded.systemPrompt, contains('ready debugger commands'));
    expect(decoded.systemPrompt, contains('select thread and frame ids'));
    expect(decoded.systemPrompt, contains('VS Code'));
    expect(decoded.systemPrompt, contains('IntelliJ Community'));
    expect(decoded.systemPrompt, contains('Eclipse Theia'));
    expect(decoded.systemPrompt, contains('Monaco Editor'));
    expect(decoded.systemPrompt, contains('targeted test or gate'));
    expect(decoded.systemPrompt, contains('Styio-first'));
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.suggestedCommandIds'),
    );
    expect(
      decoded.systemPrompt,
      contains('metadata.projectLanguage.suggestedCommandIds'),
    );
    expect(
      decoded.systemPrompt,
      contains('metadata.projectLanguage.semanticFeatureMatrix'),
    );
    expect(
      decoded.systemPrompt,
      contains('metadata.projectLanguage.syntaxValidationAuthority'),
    );
    expect(
      decoded.systemPrompt,
      contains('metadata.projectLanguage.workspaceQuickFixes'),
    );
    expect(
      decoded.systemPrompt,
      contains('metadata.projectLanguage.syntaxValidationAuthority'),
    );
    expect(
      decoded.systemPrompt,
      contains('metadata.projectLanguage.syntaxValidationReport'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.parserEngine'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.grammarVersion'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.capabilityHealth'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.missingCapabilityCount'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.blockedCapabilityCount'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.syntaxValidationReady'),
    );
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.semanticFactsReady'),
    );
    expect(
      decoded.systemPrompt,
      contains('semanticFeatureMatrix preferredSource'),
    );
    expect(decoded.systemPrompt, contains('fallbackActive'));
    expect(decoded.systemPrompt, contains('conflictPolicy'));
    expect(
      decoded.systemPrompt,
      contains('language.serviceStatus.unavailablePrimaryCapabilities'),
    );
    expect(decoded.systemPrompt, contains('real StyioService facts'));
    expect(
      decoded.systemPrompt,
      isNot(contains('Default native-code work assumes')),
    );
    expect(
      decoded.systemPrompt,
      contains(
        'Only when workspace.buildFacts or user intent proves native C/C++ work',
      ),
    );
    expect(decoded.systemPrompt, contains('clang++'));
    expect(decoded.systemPrompt, contains('compile_commands.json'));
    expect(decoded.systemPrompt, contains('CMake or Ninja target ownership'));
    expect(decoded.systemPrompt, contains('clangd-style symbol facts'));
    expect(decoded.systemPrompt, contains('workspace.buildFacts.toolingHints'));
    expect(
      decoded.systemPrompt,
      contains('workspace.buildFacts.hasCompilationDatabase'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.nativeTools.languageServices'),
    );
    expect(
      decoded.systemPrompt,
      contains('commands.nativeToolCommandReadiness.toolFamily'),
    );
    expect(decoded.systemPrompt, contains('requiredToolFamilies'));
    expect(decoded.systemPrompt, contains('requiredCommandId'));
    expect(decoded.systemPrompt, contains('before the blocked native command'));
    expect(decoded.systemPrompt, contains('has no requiredCommandId'));
    expect(
      decoded.systemPrompt,
      contains('before retrying the missing-tool command'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.cmakeExecutablePath'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.selection.candidate.version'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.selection.candidate.metadata.clangVendor'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.selection.preferredBuildEngineHandoff'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.selection.buildEngineHandoffs'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.selection.cmakeNinjaConfigureArguments'),
    );
    expect(
      decoded.systemPrompt,
      contains('toolchains.clangCpp.ninjaExecutablePath'),
    );
    expect(decoded.systemPrompt, contains('toolchains.nativeTools'));
  });

  test('agent provider route keeps iOS cloud-only and Web hosted', () {
    final ios = AgentPromptProfile.defaultForPlatform(PlatformTarget.ios);
    final web = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final android = AgentPromptProfile.defaultForPlatform(
      PlatformTarget.android,
    );

    expect(ios.endpoint.route, AgentProviderRoute.iosCloudOnly);
    expect(ios.allowsLocalBridge, isFalse);
    expect(web.endpoint.route, AgentProviderRoute.webHosted);
    expect(web.endpoint.baseUrl, '/api/styio-agent/v1');
    expect(web.endpoint.requiresCredential, isFalse);
    expect(
      web.endpoint.credentialPolicy,
      AgentProviderCredentialPolicy.hostedSessionCredential,
    );
    expect(ios.endpoint.requiresCredential, isTrue);
    expect(
      ios.endpoint.credentialPolicy,
      AgentProviderCredentialPolicy.explicitUserCredential,
    );
    expect(android.endpoint.route.allowsLocalBridge, isTrue);
    expect(android.endpoint.requiresCredential, isTrue);
  });

  test('agent prompt profile exposes OpenAI Codex Spark preset', () {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final decoded = AgentPromptProfile.fromJson(profile.toJson());

    expect(decoded.profileId, 'openai-codex-spark-linux');
    expect(decoded.displayName, 'Linux OpenAI Codex Spark');
    expect(decoded.endpoint.baseUrl, 'https://api.openai.com/v1');
    expect(decoded.endpoint.model, 'gpt-5.3-codex-spark');
    expect(decoded.endpoint.protocol, 'openai-responses');
    expect(decoded.endpoint.reasoningEffort, 'high');
    expect(decoded.endpoint.requiresCredential, isTrue);
    expect(
      decoded.endpoint.credentialPolicy,
      AgentProviderCredentialPolicy.explicitUserCredential,
    );
    expect(
      decoded.endpoint.credentialReference?.key.stableId,
      AgentPromptProfile.openAIApiCredentialReference.key.stableId,
    );
    expect(
      decoded.endpoint.credentialReference?.kind,
      AgentPromptProfile.openAIApiCredentialReference.kind,
    );
    expect(decoded.endpoint.route, AgentProviderRoute.desktopLocalBridge);
    expect(decoded.contextChannels, AgentPromptProfile.defaultContextChannels);
    expect(profile.toJson().toString().toLowerCase(), isNot(contains('oauth')));
  });

  test(
    'agent prompt profile uses default context channels when json omits them',
    () {
      final profile = AgentPromptProfile.fromJson(<String, Object?>{
        'profileId': 'legacy',
        'displayName': 'Legacy',
        'systemPrompt': 'Use context.',
        'endpoint': const <String, Object?>{
          'route': 'web-hosted',
          'baseUrl': '/api/styio-agent/v1',
          'model': 'gpt-test',
        },
      });

      expect(
        profile.contextChannels,
        AgentPromptProfile.defaultContextChannels,
      );
      expect(
        profile.endpoint.credentialPolicy,
        AgentProviderCredentialPolicy.explicitUserCredential,
      );
    },
  );
}
