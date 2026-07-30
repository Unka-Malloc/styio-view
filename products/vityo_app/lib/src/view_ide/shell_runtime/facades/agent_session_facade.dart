// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public Agent session, provider, patch, and shared-receipt facade.
mixin ShellRuntimeAgentSessionFacade on ShellRuntimeFacadeHost {
  AgentCommandResultContext? get lastAgentIdeCommandResult =>
      _lastAgentIdeCommandResult;
  AgentPromptProfileManifest get agentProviderProfileManifest =>
      _agentProviderProfileManifest;
  AgentCommandResultContext? get _lastAgentIdeCommandResult =>
      _agentController.lastCommandResult;
  AgentPromptProfileManifest get _agentProviderProfileManifest =>
      _agentController.providerProfileManifest;

  List<DocumentState> get _agentWorkspaceDocumentSamples => <DocumentState>[
    editorController.document,
    for (final entry in _editorWorkspaceStateController.cachedDocumentEntries)
      if (entry.key != editorController.document.documentId) entry.value,
  ];

  AgentSessionContext get agentSessionContext =>
      _agentSessionContextController.build();

  Future<AgentPromptProfileManifest> refreshAgentProviderProfileManifest() =>
      _agentProviderConfigurationController.refreshManifest();

  Future<Map<String, Object?>> collectAgentCodingCheckpoint() =>
      _agentSessionContextController.collectCodingCheckpoint();

  Future<AgentCodePatchApplicationResult?> applyAgentPendingPatch() =>
      _agentPatchLifecycleController.applyPending();

  Future<AgentCodePatchApplicationResult> applyAgentWorkspacePatchTool(
    AgentCodePatch patch,
  ) => _agentPatchLifecycleController.apply(patch);

  void _recordAgentIdeCommandResult(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => _agentCommandReceiptController.record(
    suggestion,
    applied: applied,
    message: message,
    metadata: metadata,
  );

  bool _blockAgentDiskBackedCommandWhenDirty(
    AgentIdeCommandSuggestion suggestion,
  ) => _agentCommandReceiptController.blockDiskBackedCommandWhenDirty(
    suggestion,
  );

  Future<AgentProviderConfigurationResult?> saveAndMountAgentProfile(
    AgentPromptProfile profile, {
    String? bearerToken,
  }) => _agentProviderConfigurationController.saveAndMount(
    profile,
    bearerToken: bearerToken,
  );

  Future<AgentProviderConfigurationResult?> failoverAgentProviderProfile(
    String profileKey,
  ) => _agentProviderConfigurationController.failover(profileKey);
}
