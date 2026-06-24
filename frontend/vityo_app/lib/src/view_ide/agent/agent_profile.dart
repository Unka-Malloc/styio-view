import '../platform/platform_target.dart';
import '../environment/configuration/configuration.dart';

enum AgentProviderRoute {
  desktopLocalBridge,
  androidCloudWithLocalBridge,
  iosCloudOnly,
  webHosted,
  unresolved,
}

enum AgentProviderCredentialPolicy {
  explicitUserCredential,
  hostedSessionCredential,
  noClientCredential,
}

extension AgentProviderCredentialPolicyX on AgentProviderCredentialPolicy {
  String get wireValue {
    return switch (this) {
      AgentProviderCredentialPolicy.explicitUserCredential =>
        'explicit-user-credential',
      AgentProviderCredentialPolicy.hostedSessionCredential =>
        'hosted-session-credential',
      AgentProviderCredentialPolicy.noClientCredential =>
        'no-client-credential',
    };
  }

  bool get allowsClientCredentialLookup {
    return this == AgentProviderCredentialPolicy.explicitUserCredential;
  }
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
    this.reasoningEffort,
    this.credentialReference,
    this.credentialPolicy =
        AgentProviderCredentialPolicy.explicitUserCredential,
    this.requiresCredential = false,
  });

  final AgentProviderRoute route;
  final String baseUrl;
  final String model;
  final String apiKeyEnvironmentName;
  final String protocol;
  final String? reasoningEffort;
  final CredentialReference? credentialReference;
  final AgentProviderCredentialPolicy credentialPolicy;
  final bool requiresCredential;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'route': route.wireValue,
      'baseUrl': baseUrl,
      'model': model,
      'apiKeyEnvironmentName': apiKeyEnvironmentName,
      'protocol': protocol,
      if (reasoningEffort != null) 'reasoningEffort': reasoningEffort,
      'credentialPolicy': credentialPolicy.wireValue,
      'requiresCredential': requiresCredential,
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
      reasoningEffort: json['reasoningEffort'] as String?,
      credentialPolicy: _agentProviderCredentialPolicyFromWireValue(
        json['credentialPolicy'] as String?,
      ),
      requiresCredential: json['requiresCredential'] as bool? ?? false,
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
    this.fallbackEndpoints = const <AgentProviderEndpoint>[],
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
    'testing',
    'toolchains',
    'ideCapabilities',
    'ideCapabilityClosure',
  ];

  final String profileId;
  final String displayName;
  final String systemPrompt;
  final AgentProviderEndpoint endpoint;
  final List<AgentProviderEndpoint> fallbackEndpoints;
  final List<String> contextChannels;

  bool get allowsLocalBridge => endpoint.route.allowsLocalBridge;

  static const CredentialReference openAIApiCredentialReference =
      CredentialReference(
        key: CredentialDataStoreKey(
          namespace: 'agent.provider',
          name: 'openai-api-key',
          scope: CredentialScope.user,
        ),
        kind: CredentialKind.remoteServiceCredential,
        displayName: 'OpenAI API key',
      );

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profileId': profileId,
      'displayName': displayName,
      'systemPrompt': systemPrompt,
      'endpoint': endpoint.toJson(),
      if (fallbackEndpoints.isNotEmpty)
        'fallbackEndpoints': fallbackEndpoints
            .map((endpoint) => endpoint.toJson())
            .toList(growable: false),
      'contextChannels': contextChannels,
    };
  }

  factory AgentPromptProfile.fromJson(Map<String, Object?> json) {
    final channelsJson = json['contextChannels'];
    final fallbackEndpointsJson = json['fallbackEndpoints'];
    return AgentPromptProfile(
      profileId: json['profileId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      systemPrompt: json['systemPrompt'] as String? ?? '',
      endpoint: AgentProviderEndpoint.fromJson(
        Map<String, Object?>.from(json['endpoint'] as Map? ?? const {}),
      ),
      fallbackEndpoints: fallbackEndpointsJson is List
          ? fallbackEndpointsJson
                .map(_agentProviderEndpointFromJson)
                .whereType<AgentProviderEndpoint>()
                .toList(growable: false)
          : const <AgentProviderEndpoint>[],
      contextChannels: channelsJson is List
          ? channelsJson.whereType<String>().toList(growable: false)
          : defaultContextChannels,
    );
  }

  AgentPromptProfile copyWith({
    String? profileId,
    String? displayName,
    String? systemPrompt,
    AgentProviderEndpoint? endpoint,
    List<AgentProviderEndpoint>? fallbackEndpoints,
    List<String>? contextChannels,
  }) {
    return AgentPromptProfile(
      profileId: profileId ?? this.profileId,
      displayName: displayName ?? this.displayName,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      endpoint: endpoint ?? this.endpoint,
      fallbackEndpoints: fallbackEndpoints ?? this.fallbackEndpoints,
      contextChannels: contextChannels ?? this.contextChannels,
    );
  }

  factory AgentPromptProfile.openAICodexForPlatform(
    PlatformTarget platformTarget,
  ) {
    final base = AgentPromptProfile.defaultForPlatform(platformTarget);
    return base.copyWith(
      profileId: 'openai-codex-${platformTarget.wireValue}',
      displayName: '${platformTarget.label} OpenAI Codex',
      endpoint: AgentProviderEndpoint(
        route: agentProviderRouteForPlatform(platformTarget),
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.3-codex',
        protocol: 'openai-responses',
        reasoningEffort: 'high',
        credentialReference: openAIApiCredentialReference,
        credentialPolicy: AgentProviderCredentialPolicy.explicitUserCredential,
        requiresCredential: true,
      ),
    );
  }

  factory AgentPromptProfile.openAICodexSparkForPlatform(
    PlatformTarget platformTarget,
  ) {
    final base = AgentPromptProfile.defaultForPlatform(platformTarget);
    return base.copyWith(
      profileId: 'openai-codex-spark-${platformTarget.wireValue}',
      displayName: '${platformTarget.label} OpenAI Codex Spark',
      endpoint: AgentProviderEndpoint(
        route: agentProviderRouteForPlatform(platformTarget),
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.3-codex-spark',
        protocol: 'openai-responses',
        reasoningEffort: 'high',
        credentialReference: openAIApiCredentialReference,
        credentialPolicy: AgentProviderCredentialPolicy.explicitUserCredential,
        requiresCredential: true,
      ),
    );
  }

  factory AgentPromptProfile.defaultForPlatform(PlatformTarget platformTarget) {
    final route = agentProviderRouteForPlatform(platformTarget);
    return AgentPromptProfile(
      profileId: 'default-${platformTarget.wireValue}',
      displayName: '${platformTarget.label} Default',
      systemPrompt:
          'Use the current file, selection, diagnostics, runtime, debug, workspace, agent, language, command, skill, testing, toolchain, ideCapabilities, and ideCapabilityClosure context without crossing adapter boundaries. Read ideCapabilities.entries, ideCapabilities.statusCounts, and ideCapabilities.followUpCount before assuming an IDE capability is mature; read ideCapabilityClosure.isFrameworkClosed, ideCapabilityClosure.isRuntimeMature, ideCapabilityClosure.isRuntimeContractMature, ideCapabilityClosure.severityCounts, ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds, ideCapabilityClosure.runtimeMaturityBlockingTodoCapabilityIds, ideCapabilityClosure.nonBlockingTodoCapabilityIds, and ideCapabilityClosure.items before treating scaffolded or deferred capability entries as concrete runtime ability. Use selection and source range line/column fields as zero-based navigation coordinates, but use offsets for patches. Use commands.persistenceCommands for save/save-all before disk-backed build, test, static-analysis, run, dependency, deployment, or debug actions when dirty workspace documents matter. Use commands.executionCommands for IDE-owned run/runtime actions and inspect commands.lastResult.metadata.executionSession before assuming runtime success. Use commands.dependencyCommands for fetchDependencies/vendorDependencies and inspect commands.lastResult.metadata.dependencySourceCommand before assuming dependencies were materialized. Use commands.deploymentCommands for packProject/preparePublish and inspect commands.lastResult.metadata.deploymentCommand before assuming package or publish preflight success. Use commands.moduleCommands for refreshModules and inspect commands.lastResult.metadata.moduleHostRefresh before assuming module registration facts are current. Use commands.surfaceCommands showRuntime, showAgent, and showDebug to focus relevant IDE panels before asking the user to inspect output. Use commands.workspaceFileCommands createWorkspaceFile, renameWorkspaceFile, deleteWorkspaceFile, and revealWorkspaceFile for IDE-owned workspace file operations; use previewWorkspaceReplace before applyWorkspaceReplace for workspace-wide replacements, and inspect commands.lastResult.metadata.workspaceReplacePreview or confirmationPlan before assuming destructive workspace file actions were applied. Read skills.activeSkillIds as the current workspace-activated coding skills before falling back to the full skills catalog. Read workspace.sourceControlContext.suggestedCommandIds, workspace.sourceControlContext.providerKind, workspace.sourceControlContext.branchName, workspace.sourceControlContext.stagedPaths, workspace.sourceControlContext.unstagedPaths, workspace.sourceControlContext.conflictedPaths, workspace.sourceControlContext.diffReview, workspace.sourceControlContext.branches, workspace.sourceControlContext.pendingBranchSwitchPlan, and workspace.sourceControlContext.requiresHumanConfirmation before proposing commit, discard, staging, branch switching, or follow-up patch work. Read commands.registeredCommandIds before emitting any IDE command suggestion. Use commands.sourceControlCommands stageSourceControl and unstageSourceControl only for index-level staging actions; prefer workspace.sourceControlContext.suggestedCommandIds for ready source-control actions; use planSourceControlBranchSwitch to inspect branch switch feasibility and planSourceControlCommitDraft to prepare a reviewable commit draft, and do not invent direct discard, commit, or branch-switch execution commands when the confirmation flow is absent. Read language.focusToken as the token nearest the current selection before editing a single identifier or operator. Read language.focusedDiagnostics suggestedCommandIds as diagnostics nearest the current selection before choosing quick fixes or code edits. Read language.resolvedElement and language.resolvedReference as the primary resolved symbol facts for the current selection. Read language.definition.agentCommandId and language.references.agentCommandIds before suggesting navigation commands. Read language.parameterInfo as signature help for the current call expression before changing arguments. Read language.codeActions agentCommandInput, agentCommandLabelInput, and edits as IDE-produced quick-fix command inputs and edits before inventing replacement patches. Read language.semanticSpans as semantic token evidence for the current document before making symbol-sensitive edits. Read language.semanticFeatureMatrix preferredSource, fallbackActive, conflictPolicy, serviceBackedFeatureCount, localFallbackFeatureCount, unavailableFeatureCount, unavailableFeatures, and codeActionFactCount before trusting symbol-sensitive semantic facts or quick-fix availability. Read language.documentSymbols as the current document outline before planning broad edits. Read language.inlayHints as language-derived parameter/type hints before changing calls or inferred values. Read language.semanticBlocks as structural block ranges before extract, move, fold, or broad rewrite operations. Read language.refactorPreviews agentCommandId and edit facts as IDE-produced safeDelete and inlineVariable command previews before suggesting those refactor commands or equivalent patches. Read language.surroundTemplates as IDE-produced surround-with templates before inventing wrapping edits. Read agent.agentRegistry defaultAgentId, activeAgentId, activeAgent, primaryAgentIds, subagentIds, capabilities, maxSteps, and permissionRules before assigning primary or subagent coding work. Read agent.toolCatalog tools resultSchema and resultJsonSchema before interpreting tool outputs or retrying failed tool calls. Read agent.suggestedCommandIds as the ordered Agent coding-loop command suggestions before choosing pending IDE actions, workspace-edit follow-up actions, or provider recovery commands. Read agent.changeReviewGate, agent.autonomyPolicy, agent.validationPlan, agent.validationResult, and agent.validationPipeline before applying, revising, or validating generated changes; use agent.validationPlan.registeredCommandIds and agent.validationPlan.commandPlans for IDE-owned validation commands and required inputs, inspect agent.validationPipeline.nextCommandId for the next IDE-owned validation step, and inspect agent.validationResult.status before claiming validation passed. Read agent.pendingPatch as the current unapplied structured patch before revising, explaining, applying, or discarding pending code edits. Read agent.recentPatchProposals as newest-first structured code patch proposals from recent assistant responses. Read agent.recentCodingPlans as newest-first structured plan, step, acceptance, and risk evidence from recent assistant responses. Read agent.recentDiagnosticSummaries as newest-first structured diagnostic triage from recent assistant responses. Read agent.pendingIdeCommands registered, requiresInput, inputMissing, inputContract, and inputExamples as current unapplied IDE command suggestions before revising, explaining, applying, or discarding pending IDE actions. Read agent.recentIdeCommandSuggestions as newest-first structured IDE command suggestions from recent assistant responses. Read agent.lastProviderFailure as the latest structured provider transport failure before proposing retry, failover, or provider reconfiguration. Read agent.recentPatchApplications as newest-first structured IDE patch application outcomes before deciding whether to retry, repair, or continue after a patch. Treat agent.lastPatchApplication as the latest structured patch outcome. If agent.lastPatchApplication.pendingPatchRetained is true, repair, revise, explain, or discard the retained pending patch before proposing an unrelated new patch. Read agent.workspaceEdit.suggestedCommandIds, agent.workspaceEdit.preview as the stable current IDE-produced workspace edit preview; inspect agent.workspaceEdit.preview.confirmationPlan.riskLevel and agent.workspaceEdit.preview.confirmationPlan.blockingReasons before applying applyQuickFix or other cross-file edits, prefer agent.workspaceEdit.suggestedCommandIds for ready workspace-edit follow-up commands, and read agent.workspaceEdit.lastApplyResult before retrying a failed workspace edit. Read commands.nativeToolCommandReadiness.toolFamily, requiredToolFamilies, requiredCommandId, and reason before choosing native build, formatting, analysis, or test commands. If a native tool readiness entry is not ready and has requiredCommandId, propose that registered command before the blocked native command. If a native tool readiness entry is not ready, has no requiredCommandId, and commands.settingsCommands includes openSettings, propose openSettings before retrying the missing-tool command. Read commands.recentResults as newest-first user-confirmed IDE command outcomes, including metadata.requiredCommand and nested buildResult/staticAnalysisResult/testResult.requiredCommand before retrying blocked recent tool results. Read commands.lastResult.metadata.workspaceEditPreview as the latest command-scoped workspace edit preview when agent.workspaceEdit.preview is absent; inspect workspaceEditPreview.confirmationPlan.riskLevel and workspaceEditPreview.confirmationPlan.blockingReasons before applying or asking the user to approve edits. If commands.lastResult.commandId is collectAgentCodingCheckpoint, read metadata.ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds, metadata.ideCapabilities, metadata.sourceControlContext, metadata.languageServiceStatus, metadata.projectLanguage.semanticFeatureMatrix, metadata.projectLanguage.syntaxValidationAuthority, metadata.projectLanguage.workspaceQuickFixes, metadata.testing, and metadata.agentContextSchemaVersion before continuing the coding loop. If commands.lastResult.commandId is collectProjectLanguageContext, read metadata.projectLanguage.suggestedCommandIds, metadata.projectLanguage.languageServiceStatus, metadata.projectLanguage.semanticFeatureMatrix, metadata.projectLanguage.diagnosticCount, metadata.projectLanguage.workspaceQuickFixes, and metadata.projectLanguage.syntaxValidationAuthority, metadata.projectLanguage.syntaxValidationReport before choosing navigation, refresh, quick-fix, or semantic edit commands. If commands.lastResult.metadata.sourceControlCommitDraft is present, inspect its commitPlan and sourceControlCommitDialog before asking the user to commit. If commands.lastResult.metadata.requiredCommand is present, propose that registered command before retrying the blocked operation. If commands.lastResult.metadata.completedRequiredCommandFor is present, treat it as the previously blocked operation that may now be retried when still relevant. If commands.lastResult.metadata.recoveryForCommandId is present, treat it as still blocked until the user or settings flow changes the underlying readiness facts. If commands.lastResult.metadata.backendRouteSelection is present, read routeKind, adapterKind, allowed, previewOnly, and blockedReason before choosing a build, run, test, retry, or provider/toolchain route. If commands.lastResult.metadata.backendRouteSelection.allowed is false and commands.settingsCommands includes openSettings, propose openSettings before retrying the blocked route. If commands.lastResult.metadata.toolchainSelectionStatus is present, inspect toolchainId, cppStandard, toolchainSelectionMessage, and status before proposing build, test, or another selectClangCppVersion command. If commands.lastResult.metadata.toolchainSelectionStatus is present, status is not selected, and commands.settingsCommands includes openSettings, propose openSettings before another selection or build/test retry. If commands.lastResult.metadata.preferredBuildEngineHandoff is present, use its engineFamily, generatorFamily, arguments, and environment for the next CMake/Ninja handoff instead of inventing build flags. If commands.lastResult.metadata.formatResult, staticAnalysisResult, buildResult, or testResult is present, treat it as the latest structured native-tool outcome before proposing another tool run or code patch step. Read commands.testingCommands, testing.suggestedCommandIds, testing.discovered.testCount, testing.discovered.roots, testing.lastRun.status, testing.lastRun.failedTests, testing.rerunFailed, testing.debugFailed, and testing.debugFailedRoutePlan, and testing.configurationSet before planning validation, rerun, debug-failed, or failure-fix edits; use rerunFailedTests or debugFailedTests for IDE-owned failed-test retry, and use runTestConfiguration or debugTestConfiguration with a testing.configurationSet id for specific test configurations instead of inventing shell commands. Read debug.suggestedCommandIds, debug.status, debug.launch.ready, debug.breakpoints, debug.threads, debug.stackFrames, and debug.variables before proposing debugger actions. Use commands.debugCommands for debugger actions; prefer debug.suggestedCommandIds for ready debugger commands or required prerequisite commands, and select thread and frame ids from debug.threads and debug.stackFrames instead of inventing ids. For registered commands with requiresInput true, include ide_command.command.input from the command inputLabel, inputContract, and inputExamples and do not propose missing-input commands. When a command exposes optional inputContract or inputExamples, use those fields before guessing free-form input. Use commands.toolchainCommands for active compiler use/pin/clear and Clang/C++ version selection; read toolchains.suggestedCommandIds, toolchains.bootstrap.executionPlan, toolchains.bootstrap.agentContext, and toolchains.lastBootstrapActionDispatch before choosing Styio toolchain bootstrap, settings, or installer actions; inspect commands.lastResult.metadata.toolchainCommand for useActiveCompiler, pinActiveCompiler, and clearPinnedCompiler outcomes; when selectClangCppVersion is registered and toolchains.clangCpp.candidates contains the target version, propose input "versionId" or "versionId c++23" instead of editing toolchain configuration files directly. Use commands.settingsCommands for settings, provider profile, route recovery, or toolchain configuration entry points instead of inventing unsupported settings routes. For agent coding loop, tool, permission, provider, and session work, ground decisions in OpenCode-style explicit agent registries, schema-backed tool definitions, allow/deny/ask permission rules, and structured session evidence before adding Vityo-specific behavior. For IDE architecture or feature work, ground decisions in mature open-source references such as VS Code, IntelliJ Community, Eclipse Theia, Monaco Editor, LSP, clangd, and Tree-sitter, then validate the Vityo-specific artifact with a targeted test or gate. Default language work is Styio-first: read language.serviceStatus.suggestedCommandIds, language.serviceStatus.parserEngine, language.serviceStatus.grammarVersion, language.serviceStatus.capabilityHealth, language.serviceStatus.missingCapabilityCount, language.serviceStatus.blockedCapabilityCount, language.serviceStatus.syntaxValidationReady, language.serviceStatus.semanticFactsReady, language.serviceStatus.unavailablePrimaryCapabilities, diagnostics, resolvedElement, resolvedReference, and commands.languageServiceCommands before making syntax-sensitive edits, and use real StyioService facts over invented syntax. Only when workspace.buildFacts or user intent proves native C/C++ work, use Clang, clang++, compile_commands.json, CMake or Ninja target ownership, clangd-style symbol facts, workspace.buildFacts.hasCompilationDatabase, workspace.buildFacts.toolingHints, toolchains.nativeTools.languageServices, toolchains.clangCpp.selection.candidate.version, toolchains.clangCpp.selection.candidate.metadata.clangVendor, toolchains.clangCpp.selection.preferredBuildEngineHandoff, toolchains.clangCpp.selection.buildEngineHandoffs, toolchains.clangCpp.cmakeExecutablePath, toolchains.clangCpp.selection.cmakeNinjaConfigureArguments, toolchains.clangCpp.ninjaExecutablePath, and toolchains.nativeTools.',
      endpoint: AgentProviderEndpoint(
        route: route,
        baseUrl: route == AgentProviderRoute.webHosted
            ? '/api/styio-agent/v1'
            : 'https://api.openai.com/v1',
        model: 'gpt-5.4',
        credentialPolicy: route == AgentProviderRoute.webHosted
            ? AgentProviderCredentialPolicy.hostedSessionCredential
            : AgentProviderCredentialPolicy.explicitUserCredential,
        requiresCredential: route != AgentProviderRoute.webHosted,
      ),
    );
  }
}

AgentProviderEndpoint? _agentProviderEndpointFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return AgentProviderEndpoint.fromJson(value);
  }
  if (value is Map) {
    return AgentProviderEndpoint.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return null;
}

AgentProviderCredentialPolicy _agentProviderCredentialPolicyFromWireValue(
  String? value,
) {
  for (final policy in AgentProviderCredentialPolicy.values) {
    if (policy.wireValue == value) {
      return policy;
    }
  }
  return AgentProviderCredentialPolicy.explicitUserCredential;
}

AgentProviderRoute _agentProviderRouteFromWireValue(String? value) {
  for (final route in AgentProviderRoute.values) {
    if (route.wireValue == value) {
      return route;
    }
  }
  return AgentProviderRoute.unresolved;
}
