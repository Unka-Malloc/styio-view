// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public toolchain facade backed by the toolchain domain controller.
mixin ShellRuntimeToolchainFacade on ShellRuntimeFacadeHost {
  ToolchainCommandResult? get lastToolchainCommand =>
      _toolchainController.lastCommand;
  ToolchainInstallPlan? get lastToolchainInstallPlan =>
      _toolchainController.lastInstallPlan;
  ToolchainInstallExecutionResult? get lastToolchainInstallExecutionResult =>
      _toolchainController.lastInstallExecutionResult;
  ToolchainManagerBootstrapSummary? get toolchainBootstrapSummary =>
      _toolchainController.bootstrapSummary;
  ToolchainBootstrapActionDispatchResult?
  get lastToolchainBootstrapActionDispatch =>
      _toolchainController.lastBootstrapActionDispatch;

  ToolchainInstallPlanSurface? get toolchainInstallPlanSurface =>
      _toolchainController.installPlanSurface;
  ToolchainInstallExecutionSurface? get toolchainInstallExecutionSurface =>
      _toolchainController.installExecutionSurface;
  ToolchainStatusSurface get toolchainStatusSurface =>
      _toolchainController.statusSurface;
  ToolchainSettingsSurface get toolchainSettingsSurface =>
      _toolchainController.settingsSurface;

  Future<ToolchainSelectionResult?> selectToolchainCandidate(String id) =>
      _toolchainController.selectCandidate(id);

  Future<ToolchainSelectionResult?> selectClangCppVersion(
    String versionId, {
    String? cppStandard,
  }) => _toolchainController.selectClangCppVersion(
    versionId,
    cppStandard: cppStandard,
  );

  Future<ToolchainSelectionResult?> clearToolchainCandidate(
    ToolchainKind kind,
  ) => _toolchainController.clearCandidate(kind);

  ToolchainInstallPlan? planManagedToolchainInstallation({
    ToolchainKind kind = ToolchainKind.languageService,
    ToolchainInstallPolicy policy = const ToolchainInstallPolicy(),
  }) =>
      _toolchainController.planManagedInstallation(kind: kind, policy: policy);

  Future<ToolchainInstallExecutionResult?> executeLastToolchainInstallPlan() =>
      _toolchainController.executeLastInstallPlan();

  Future<ToolchainManagerBootstrapSummary?> refreshToolchainBootstrapSummary({
    String reason = 'toolchain bootstrap refresh',
  }) => _toolchainController.refreshBootstrapSummary(reason: reason);

  Future<ToolchainBootstrapActionDispatchResult?>
  handleToolchainBootstrapAction(String actionId) =>
      _toolchainController.handleBootstrapAction(actionId);

  Future<ToolchainCommandResult> installManagedCompiler({
    required String styioBinaryPath,
  }) => _toolchainController.installManagedCompiler(
    styioBinaryPath: styioBinaryPath,
  );

  Future<ToolchainCommandResult> useManagedCompiler({
    required String compilerVersion,
    String? channel,
  }) => _toolchainController.useManagedCompiler(
    compilerVersion: compilerVersion,
    channel: channel,
  );

  Future<ToolchainCommandResult> pinManagedCompiler({
    required String compilerVersion,
    String? channel,
  }) => _toolchainController.pinManagedCompiler(
    compilerVersion: compilerVersion,
    channel: channel,
  );

  Future<ToolchainCommandResult> clearPinnedCompiler() =>
      _toolchainController.clearPinnedCompiler();

  Future<void> handleToolchainRecoveryAction(ToolchainRecoveryAction action) =>
      _toolchainController.handleRecoveryAction(action);
}
