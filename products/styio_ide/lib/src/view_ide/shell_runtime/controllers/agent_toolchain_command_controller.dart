import '../../agent_client/agent.dart';
import '../../backend_toolchain/backend_toolchain.dart';
import '../../commands/commands.dart';
import '../../toolchain/toolchain.dart';
import 'agent_controller.dart';
import 'toolchain_controller.dart';

/// Owns agent-facing toolchain selection, recovery, and install routing.
final class AgentToolchainCommandController {
  const AgentToolchainCommandController({
    required this.agentController,
    required this.toolchainController,
    required this.blockedReasonForCommand,
    required this.executeCommand,
    required this.selectClangCppVersion,
    required this.handleBootstrapAction,
    required this.executeLastInstallPlan,
    required this.blockWhenDirty,
    required this.log,
    required this.notify,
  });

  final AgentController agentController;
  final ToolchainController toolchainController;
  final String? Function(AppCommandId commandId) blockedReasonForCommand;
  final Future<void> Function(AppCommandId commandId) executeCommand;
  final Future<ToolchainSelectionResult?> Function(
    String versionId, {
    String? cppStandard,
  })
  selectClangCppVersion;
  final Future<ToolchainBootstrapActionDispatchResult?> Function(
    String actionId,
  )
  handleBootstrapAction;
  final Future<ToolchainInstallExecutionResult?> Function()
  executeLastInstallPlan;
  final bool Function(AgentIdeCommandSuggestion suggestion) blockWhenDirty;
  final void Function(String message) log;
  final void Function() notify;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    return switch (suggestion.commandId) {
      'selectClangCppVersion' => _selectVersion(suggestion),
      'useActiveCompiler' => _compilerCommand(
        suggestion,
        AppCommandId.useActiveCompiler,
      ),
      'pinActiveCompiler' => _compilerCommand(
        suggestion,
        AppCommandId.pinActiveCompiler,
      ),
      'clearPinnedCompiler' => _compilerCommand(
        suggestion,
        AppCommandId.clearPinnedCompiler,
      ),
      'bootstrapStyioToolchain' => _bootstrap(suggestion),
      'executeToolchainInstallPlan' => _executeInstall(suggestion),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent toolchain command.',
      ),
    };
  }

  Future<bool> _selectVersion(AgentIdeCommandSuggestion suggestion) async {
    final input = _parseVersionInput(suggestion.input);
    if (input == null) {
      _recordMissingInput(suggestion, AppCommandId.selectClangCppVersion);
      notify();
      return false;
    }
    final result = await selectClangCppVersion(
      input.versionId,
      cppStandard: input.cppStandard,
    );
    final applied = result?.succeeded ?? false;
    final selection = result?.succeeded == true
        ? ClangCppVersionManager.fromSnapshot(
            result!.snapshot,
            preference: toolchainController.clangCppVersionPreference,
          ).select()
        : null;
    _record(
      suggestion,
      applied: applied,
      message: applied
          ? 'Agent command selectClangCppVersion selected ${input.versionId}.'
          : 'Agent command selectClangCppVersion failed for ${input.versionId}: ${result?.message ?? "selection was not applied"}.',
      metadata: <String, Object?>{
        'toolchainId': input.versionId,
        if (input.cppStandard != null) 'cppStandard': input.cppStandard,
        if (result != null) 'toolchainSelectionStatus': result.status.name,
        if (result?.message != null)
          'toolchainSelectionMessage': result!.message,
        if (selection != null) ..._selectionMetadata(selection),
      },
    );
    return applied;
  }

  Future<bool> _compilerCommand(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
  ) async {
    if (blockWhenDirty(suggestion)) {
      return false;
    }
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      final message =
          'Agent command ${suggestion.commandId} blocked: $blockedReason';
      _record(
        suggestion,
        applied: false,
        message: message,
        metadata: <String, Object?>{
          'blockedReason': blockedReason,
          'requiredCommand': 'openSettings',
        },
      );
      log(message);
      return false;
    }
    await executeCommand(commandId);
    final result = toolchainController.lastCommand;
    final applied = result?.succeeded ?? false;
    _record(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command ${suggestion.commandId} skipped: no toolchain command result was produced.'
          : 'Agent command ${suggestion.commandId} ${result.status.name}: ${result.statusMessage}',
      metadata: <String, Object?>{
        if (result != null) 'toolchainCommand': _commandMetadata(result),
      },
    );
    return applied;
  }

  Future<bool> _bootstrap(AgentIdeCommandSuggestion suggestion) async {
    final result = await handleBootstrapAction('bootstrap-styio-toolchain');
    final applied = result?.dispatched ?? false;
    _record(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command bootstrapStyioToolchain skipped: no bootstrap result was produced.'
          : 'Agent command bootstrapStyioToolchain ${result.status.wireValue}: ${result.message}',
      metadata: <String, Object?>{
        if (result != null) 'toolchainBootstrapActionDispatch': result.toJson(),
        if (toolchainController.bootstrapSummary != null)
          'toolchainBootstrap': toolchainController.bootstrapSummary!.toJson(),
      },
    );
    return applied;
  }

  Future<bool> _executeInstall(AgentIdeCommandSuggestion suggestion) async {
    final result = await executeLastInstallPlan();
    final applied =
        result != null &&
        result.status != ToolchainInstallExecutionStatus.failed &&
        result.status != ToolchainInstallExecutionStatus.blocked;
    _record(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command executeToolchainInstallPlan skipped: no install plan is prepared.'
          : 'Agent command executeToolchainInstallPlan ${result.status.name}: ${result.message ?? result.plan.mode.name}',
      metadata: <String, Object?>{
        if (toolchainController.lastInstallPlan != null)
          'toolchainInstallPlan': toolchainController.lastInstallPlan!.toJson(),
        if (result != null) 'toolchainInstallExecution': result.toJson(),
      },
    );
    return applied;
  }

  Map<String, Object?> _commandMetadata(ToolchainCommandResult result) =>
      <String, Object?>{
        'command': result.command,
        'status': result.status.name,
        'statusMessage': result.statusMessage,
        'succeeded': result.succeeded,
        if (result.payload != null) 'payload': result.payload,
        if (result.errorPayload != null) 'errorPayload': result.errorPayload,
      };

  void _recordMissingInput(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
  ) {
    final descriptor = StyioCommandRegistry.descriptorFor(commandId);
    _record(
      suggestion,
      applied: false,
      message: 'Agent command ${suggestion.commandId} skipped: missing input.',
      metadata: <String, Object?>{
        'reason': 'missing-input',
        'requiredInput': descriptor.inputLabel,
        'inputLabel': descriptor.inputLabel,
        'inputContract': descriptor.inputContract,
        'inputExamples': descriptor.inputExamples,
      },
    );
  }

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    required Map<String, Object?> metadata,
  }) {
    final effectiveMetadata = <String, Object?>{...metadata};
    final prerequisite = suggestion.prerequisiteForCommandId;
    if (prerequisite != null && prerequisite.isNotEmpty) {
      effectiveMetadata['completedRequiredCommandFor'] = prerequisite;
    }
    agentController.recordCommandResult(
      AgentCommandResultContext(
        commandId: suggestion.commandId,
        input: suggestion.input,
        applied: applied,
        message: message,
        metadata: effectiveMetadata,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

final class _VersionInput {
  const _VersionInput(this.versionId, this.cppStandard);
  final String versionId;
  final String? cppStandard;
}

_VersionInput? _parseVersionInput(String? input) {
  final trimmed = input?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  final parts = trimmed.split(RegExp(r'\s+'));
  final standard = parts.length <= 1 ? null : parts.skip(1).join(' ').trim();
  return _VersionInput(
    parts.first,
    standard == null || standard.isEmpty ? null : standard,
  );
}

Map<String, Object?> _selectionMetadata(ClangCppVersionSelection selection) {
  final preferred = selection.preferredBuildEngineHandoff;
  return <String, Object?>{
    'clangCppSelection': selection.toManifest(),
    'buildEngineHandoffCount': selection.buildEngineHandoffs.length,
    if (preferred != null)
      'preferredBuildEngineHandoff': preferred.toManifest(),
    if (selection.cmakeExecutablePath != null)
      'cmakeExecutablePath': selection.cmakeExecutablePath,
    if (selection.ninjaExecutablePath != null)
      'ninjaExecutablePath': selection.ninjaExecutablePath,
  };
}
