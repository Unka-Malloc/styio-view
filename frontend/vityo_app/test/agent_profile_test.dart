import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test(
    'agent prompt profile preserves OpenAI-compatible endpoint contract',
    () {
      final profile = AgentPromptProfile.defaultForPlatform(
        PlatformTarget.macos,
      );
      final decoded = AgentPromptProfile.fromJson(profile.toJson());

      expect(decoded.profileId, 'default-macos');
      expect(decoded.endpoint.protocol, 'openai-compatible');
      expect(decoded.endpoint.route, AgentProviderRoute.desktopLocalBridge);
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
          'language',
          'commands',
          'skills',
          'toolchains',
        ]),
      );
      expect(decoded.systemPrompt, contains('Clang'));
      expect(decoded.systemPrompt, contains('commands.persistenceCommands'));
      expect(decoded.systemPrompt, contains('save/save-all'));
      expect(decoded.systemPrompt, contains('skills.activeSkillIds'));
      expect(
        decoded.systemPrompt,
        contains('workspace-activated coding skills'),
      );
      expect(decoded.systemPrompt, contains('language.focusToken'));
      expect(decoded.systemPrompt, contains('token nearest'));
      expect(decoded.systemPrompt, contains('language.focusedDiagnostics'));
      expect(decoded.systemPrompt, contains('diagnostics nearest'));
      expect(decoded.systemPrompt, contains('language.resolvedElement'));
      expect(decoded.systemPrompt, contains('language.resolvedReference'));
      expect(decoded.systemPrompt, contains('primary resolved symbol facts'));
      expect(decoded.systemPrompt, contains('language.parameterInfo'));
      expect(decoded.systemPrompt, contains('signature help'));
      expect(decoded.systemPrompt, contains('language.codeActions.edits'));
      expect(decoded.systemPrompt, contains('quick-fix edits'));
      expect(decoded.systemPrompt, contains('language.semanticSpans'));
      expect(decoded.systemPrompt, contains('semantic token evidence'));
      expect(decoded.systemPrompt, contains('language.documentSymbols'));
      expect(decoded.systemPrompt, contains('document outline'));
      expect(decoded.systemPrompt, contains('language.inlayHints'));
      expect(decoded.systemPrompt, contains('parameter/type hints'));
      expect(decoded.systemPrompt, contains('language.semanticBlocks'));
      expect(decoded.systemPrompt, contains('structural block ranges'));
      expect(decoded.systemPrompt, contains('language.refactorPreviews'));
      expect(decoded.systemPrompt, contains('safeDelete and inlineVariable'));
      expect(decoded.systemPrompt, contains('language.surroundTemplates'));
      expect(decoded.systemPrompt, contains('surround-with templates'));
      expect(
        decoded.systemPrompt,
        contains('zero-based navigation coordinates'),
      );
      expect(decoded.systemPrompt, contains('source range line/column'));
      expect(decoded.systemPrompt, contains('use offsets for patches'));
      expect(decoded.systemPrompt, contains('metadata.requiredCommand'));
      expect(
        decoded.systemPrompt,
        contains('metadata.completedRequiredCommandFor'),
      );
      expect(decoded.systemPrompt, contains('commands.settingsCommands'));
      expect(decoded.systemPrompt, contains('commands.toolchainCommands'));
      expect(decoded.systemPrompt, contains('requiresInput true'));
      expect(decoded.systemPrompt, contains('missing-input commands'));
      expect(decoded.systemPrompt, contains('selectClangCppVersion'));
      expect(decoded.systemPrompt, contains('metadata.formatResult'));
      expect(decoded.systemPrompt, contains('staticAnalysisResult'));
      expect(
        decoded.systemPrompt,
        contains('nested buildResult/staticAnalysisResult/testResult.requiredCommand'),
      );
      expect(decoded.systemPrompt, contains('backendRouteSelection'));
      expect(
        decoded.systemPrompt,
        contains('backendRouteSelection.allowed is false'),
      );
      expect(decoded.systemPrompt, contains('buildResult'));
      expect(decoded.systemPrompt, contains('testResult'));
      expect(decoded.systemPrompt, contains('debug.status'));
      expect(decoded.systemPrompt, contains('debug.launch.ready'));
      expect(decoded.systemPrompt, contains('debug.threads'));
      expect(decoded.systemPrompt, contains('debug.stackFrames'));
      expect(decoded.systemPrompt, contains('commands.debugCommands'));
      expect(decoded.systemPrompt, contains('select thread and frame ids'));
      expect(decoded.systemPrompt, contains('VS Code'));
      expect(decoded.systemPrompt, contains('IntelliJ Community'));
      expect(decoded.systemPrompt, contains('Eclipse Theia'));
      expect(decoded.systemPrompt, contains('Monaco Editor'));
      expect(decoded.systemPrompt, contains('targeted test or gate'));
      expect(decoded.systemPrompt, contains('clang++'));
      expect(decoded.systemPrompt, contains('compile_commands.json'));
      expect(decoded.systemPrompt, contains('CMake or Ninja target ownership'));
      expect(decoded.systemPrompt, contains('clangd-style symbol facts'));
      expect(
        decoded.systemPrompt,
        contains('workspace.buildFacts.toolingHints'),
      );
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
      expect(
        decoded.systemPrompt,
        contains('before the blocked native command'),
      );
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
    },
  );

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
    expect(android.endpoint.route.allowsLocalBridge, isTrue);
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
    },
  );
}
