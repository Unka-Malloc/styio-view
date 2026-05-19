import '../platform/platform_target.dart';
import '../environment/configuration/configuration.dart';

enum AgentProviderRoute {
  desktopLocalBridge,
  androidCloudWithLocalBridge,
  iosCloudOnly,
  webHosted,
  unresolved,
}

extension AgentProviderRouteX on AgentProviderRoute {
  String get wireValue {
    switch (this) {
      case AgentProviderRoute.desktopLocalBridge:
        return 'desktop-local-bridge';
      case AgentProviderRoute.androidCloudWithLocalBridge:
        return 'android-cloud-local-bridge';
      case AgentProviderRoute.iosCloudOnly:
        return 'ios-cloud-only';
      case AgentProviderRoute.webHosted:
        return 'web-hosted';
      case AgentProviderRoute.unresolved:
        return 'unresolved';
    }
  }

  bool get allowsLocalBridge {
    switch (this) {
      case AgentProviderRoute.desktopLocalBridge:
      case AgentProviderRoute.androidCloudWithLocalBridge:
        return true;
      case AgentProviderRoute.iosCloudOnly:
      case AgentProviderRoute.webHosted:
      case AgentProviderRoute.unresolved:
        return false;
    }
  }
}

AgentProviderRoute agentProviderRouteForPlatform(
  PlatformTarget platformTarget,
) {
  switch (platformTarget) {
    case PlatformTarget.ios:
      return AgentProviderRoute.iosCloudOnly;
    case PlatformTarget.web:
      return AgentProviderRoute.webHosted;
    case PlatformTarget.android:
      return AgentProviderRoute.androidCloudWithLocalBridge;
    case PlatformTarget.windows:
    case PlatformTarget.linux:
    case PlatformTarget.macos:
      return AgentProviderRoute.desktopLocalBridge;
    case PlatformTarget.unknown:
      return AgentProviderRoute.unresolved;
  }
}

class AgentProviderEndpoint {
  const AgentProviderEndpoint({
    required this.route,
    required this.baseUrl,
    required this.model,
    this.apiKeyEnvironmentName = 'OPENAI_API_KEY',
    this.protocol = 'openai-compatible',
    this.credentialReference,
  });

  final AgentProviderRoute route;
  final String baseUrl;
  final String model;
  final String apiKeyEnvironmentName;
  final String protocol;
  final CredentialReference? credentialReference;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'route': route.wireValue,
      'baseUrl': baseUrl,
      'model': model,
      'apiKeyEnvironmentName': apiKeyEnvironmentName,
      'protocol': protocol,
      if (credentialReference != null)
        'credentialReference': credentialReference!.toJson(),
    };
  }

  factory AgentProviderEndpoint.fromJson(Map<String, Object?> json) {
    final credentialReference = json['credentialReference'];
    return AgentProviderEndpoint(
      route: _agentProviderRouteFromWireValue(json['route'] as String?),
      baseUrl: json['baseUrl'] as String? ?? '',
      model: json['model'] as String? ?? '',
      apiKeyEnvironmentName:
          json['apiKeyEnvironmentName'] as String? ?? 'OPENAI_API_KEY',
      protocol: json['protocol'] as String? ?? 'openai-compatible',
      credentialReference: credentialReference is Map<String, Object?>
          ? CredentialReference.fromJson(credentialReference)
          : credentialReference is Map
          ? CredentialReference.fromJson(
              credentialReference.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
    );
  }
}

class AgentPromptProfile {
  const AgentPromptProfile({
    required this.profileId,
    required this.displayName,
    required this.systemPrompt,
    required this.endpoint,
    this.contextChannels = defaultContextChannels,
  });

  static const List<String> defaultContextChannels = <String>[
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
    'toolchains',
  ];

  final String profileId;
  final String displayName;
  final String systemPrompt;
  final AgentProviderEndpoint endpoint;
  final List<String> contextChannels;

  bool get allowsLocalBridge => endpoint.route.allowsLocalBridge;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'displayName': displayName,
      'systemPrompt': systemPrompt,
      'endpoint': endpoint.toJson(),
      'contextChannels': contextChannels,
    };
  }

  factory AgentPromptProfile.fromJson(Map<String, Object?> json) {
    final channelsJson = json['contextChannels'];
    return AgentPromptProfile(
      profileId: json['profileId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      endpoint: AgentProviderEndpoint.fromJson(
        Map<String, Object?>.from(json['endpoint'] as Map? ?? const {}),
      ),
      contextChannels: channelsJson is List
          ? channelsJson.whereType<String>().toList(growable: false)
          : defaultContextChannels,
    );
  }

  factory AgentPromptProfile.defaultForPlatform(PlatformTarget platformTarget) {
    final route = agentProviderRouteForPlatform(platformTarget);
    return AgentPromptProfile(
      profileId: 'default-${platformTarget.wireValue}',
      displayName: '${platformTarget.label} Default',
      systemPrompt:
          'Use the current file, selection, diagnostics, runtime, debug, workspace, agent, language, command, skill, and toolchain context without crossing adapter boundaries. Use selection and source range line/column fields as zero-based navigation coordinates, but use offsets for patches. Use commands.persistenceCommands for save/save-all before disk-backed build, test, static-analysis, or debug actions when dirty workspace documents matter. Read skills.activeSkillIds as the current workspace-activated coding skills before falling back to the full skills catalog. Read language.focusToken as the token nearest the current selection before editing a single identifier or operator. Read language.focusedDiagnostics as diagnostics nearest the current selection before choosing quick fixes or code edits. Read language.resolvedElement and language.resolvedReference as the primary resolved symbol facts for the current selection. Read language.parameterInfo as signature help for the current call expression before changing arguments. Read language.codeActions.edits as IDE-produced quick-fix edits before inventing replacement patches. Read language.semanticSpans as semantic token evidence for the current document before making symbol-sensitive edits. Read language.documentSymbols as the current document outline before planning broad edits. Read language.inlayHints as language-derived parameter/type hints before changing calls or inferred values. Read language.semanticBlocks as structural block ranges before extract, move, fold, or broad rewrite operations. Read language.refactorPreviews as IDE-produced safeDelete and inlineVariable edit facts before suggesting those refactor commands or equivalent patches. Read language.surroundTemplates as IDE-produced surround-with templates before inventing wrapping edits. Read agent.pendingPatch as the current unapplied structured patch before revising, explaining, applying, or discarding pending code edits. Read agent.recentPatchProposals as newest-first structured code patch proposals from recent assistant responses. Read agent.recentCodingPlans as newest-first structured plan, step, acceptance, and risk evidence from recent assistant responses. Read agent.recentDiagnosticSummaries as newest-first structured diagnostic triage from recent assistant responses. Read agent.pendingIdeCommands as current unapplied IDE command suggestions before revising, explaining, applying, or discarding pending IDE actions. Read agent.recentIdeCommandSuggestions as newest-first structured IDE command suggestions from recent assistant responses. Read agent.lastProviderFailure as the latest structured provider transport failure before proposing retry, failover, or provider reconfiguration. Read agent.recentPatchApplications as newest-first structured IDE patch application outcomes before deciding whether to retry, repair, or continue after a patch. Treat agent.lastPatchApplication as the latest structured patch outcome. Read commands.nativeToolCommandReadiness.toolFamily, requiredToolFamilies, requiredCommandId, and reason before choosing native build, formatting, analysis, or test commands. If a native tool readiness entry is not ready and has requiredCommandId, propose that registered command before the blocked native command. Read commands.recentResults as newest-first user-confirmed IDE command outcomes. If commands.lastResult.metadata.requiredCommand is present, propose that registered command before retrying the blocked operation. If commands.lastResult.metadata.completedRequiredCommandFor is present, treat it as the previously blocked operation that may now be retried when still relevant. If commands.lastResult.metadata.formatResult, staticAnalysisResult, buildResult, or testResult is present, treat it as the latest structured native-tool outcome before proposing another tool run or code patch step. Read debug.status, debug.launch.ready, debug.breakpoints, debug.threads, debug.stackFrames, and debug.variables before proposing debugger actions. Use commands.debugCommands for debugger actions; select thread and frame ids from debug.threads and debug.stackFrames instead of inventing ids. For IDE architecture or feature work, ground decisions in mature open-source references such as VS Code, IntelliJ Community, Eclipse Theia, Monaco Editor, LSP, clangd, and Tree-sitter, then validate the Vityo-specific artifact with a targeted test or gate. Default native-code work assumes C/C++ projects use Clang, clang++, compile_commands.json, CMake or Ninja target ownership, clangd-style symbol facts, workspace.buildFacts.toolingHints, toolchains.clangCpp.selection.candidate.version, toolchains.clangCpp.selection.candidate.metadata.clangVendor, toolchains.clangCpp.selection.preferredBuildEngineHandoff, toolchains.clangCpp.selection.buildEngineHandoffs, toolchains.clangCpp.cmakeExecutablePath, toolchains.clangCpp.selection.cmakeNinjaConfigureArguments, toolchains.clangCpp.ninjaExecutablePath, and toolchains.nativeTools unless the repository proves another compiler contract.',
      endpoint: AgentProviderEndpoint(
        route: route,
        baseUrl: route == AgentProviderRoute.webHosted
            ? '/api/styio-agent/v1'
            : 'https://api.openai.com/v1',
        model: 'gpt-5.4',
      ),
    );
  }
}

AgentProviderRoute _agentProviderRouteFromWireValue(String? value) {
  for (final route in AgentProviderRoute.values) {
    if (route.wireValue == value) {
      return route;
    }
  }
  return AgentProviderRoute.unresolved;
}
