import 'package:flutter/foundation.dart';

import '../../backend_toolchain/backend_toolchain.dart';
import '../../interaction/toolchain_status_surface.dart';
import '../../toolchain/toolchain.dart' hide ToolchainRecoveryAction;

/// Owns active toolchain and Clang/C++ version selection state.
final class ToolchainController extends ChangeNotifier {
  ToolchainController({
    required this.projectGraph,
    required this.manager,
    required this.statusReport,
    required this.log,
    ClangCppVersionPreference? clangCppVersionPreference,
  }) : _clangCppVersionPreference = clangCppVersionPreference {
    statusReport?.addListener(_handleStatusReportChanged);
  }

  final ToolchainManager? manager;
  final ProjectGraphSnapshot Function() projectGraph;
  final ValueListenable<ToolchainManagerStatusReport>? statusReport;
  final void Function(String message) log;

  ClangCppVersionPreference? _clangCppVersionPreference;
  ToolchainStateSnapshot? _lastSnapshot;
  ToolchainInstallPlan? _lastInstallPlan;
  ToolchainInstallExecutionResult? _lastInstallExecutionResult;
  ToolchainManagerBootstrapSummary? _bootstrapSummary;
  ToolchainBootstrapActionDispatchResult? _lastBootstrapActionDispatch;
  bool _disposed = false;

  ClangCppVersionPreference? get clangCppVersionPreference =>
      _clangCppVersionPreference;
  ToolchainStateSnapshot? get lastSnapshot => _lastSnapshot;
  ToolchainInstallPlan? get lastInstallPlan => _lastInstallPlan;
  ToolchainInstallExecutionResult? get lastInstallExecutionResult =>
      _lastInstallExecutionResult;
  ToolchainManagerBootstrapSummary? get bootstrapSummary => _bootstrapSummary;
  ToolchainBootstrapActionDispatchResult? get lastBootstrapActionDispatch =>
      _lastBootstrapActionDispatch;
  ToolchainInstallPlanSurface? get installPlanSurface {
    final plan = _lastInstallPlan;
    return plan == null ? null : ToolchainInstallPlanSurface.fromPlan(plan);
  }

  ToolchainInstallExecutionSurface? get installExecutionSurface {
    final result = _lastInstallExecutionResult;
    return result == null
        ? null
        : ToolchainInstallExecutionSurface.fromResult(result);
  }

  ToolchainStatusSurface get statusSurface {
    final report = statusReport?.value;
    if (report != null) {
      return ToolchainStatusSurface.fromManagerStatusReport(report);
    }
    return ToolchainStatusSurface.fromProjectToolchain(
      projectGraph().toolchain,
    );
  }

  ToolchainSettingsSurface get settingsSurface {
    final report = statusReport?.value;
    if (report != null) {
      return ToolchainSettingsSurface.fromManagerStatusReport(
        report,
        clangCppVersionPreference: _clangCppVersionPreference,
      );
    }
    return ToolchainSettingsSurface.fromStatus(statusSurface);
  }

  Future<ToolchainSelectionResult?> selectCandidate(String id) async {
    final activeManager = manager;
    if (activeManager == null) {
      log('Toolchain selection unavailable: no ToolchainManager is wired.');
      notifyListeners();
      return null;
    }
    final result = await activeManager.selectToolchain(id);
    log(
      result.succeeded
          ? 'Toolchain selected: ${result.toolchainId} (${result.kind?.wireValue ?? "unknown"}).'
          : 'Toolchain selection failed: ${result.message ?? result.status.name}.',
    );
    await _refreshStatusAfterSelection(result);
    notifyListeners();
    return result;
  }

  Future<ToolchainSelectionResult?> selectClangCppVersion(
    String versionId, {
    String? cppStandard,
  }) async {
    final activeManager = manager;
    if (activeManager == null) {
      log(
        'Clang/C++ version selection unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }
    final snapshotBeforeSelection =
        statusReport?.value.snapshot ?? await activeManager.snapshot();
    final versionManager = ClangCppVersionManager.fromSnapshot(
      snapshotBeforeSelection,
      preference: _clangCppVersionPreference,
    );
    if (versionManager.candidateFor(versionId) == null) {
      final message =
          'Clang/C++ version selection failed: $versionId is not a registered Clang/C++ compiler candidate.';
      log(message);
      notifyListeners();
      return ToolchainSelectionResult(
        status: ToolchainSelectionStatus.missing,
        kind: ToolchainKind.compiler,
        toolchainId: versionId,
        message: message,
        snapshot: snapshotBeforeSelection,
      );
    }
    final requestedStandard = cppStandard == null
        ? null
        : CppLanguageStandard.fromWireValue(cppStandard);
    if (cppStandard != null &&
        cppStandard.trim().isNotEmpty &&
        requestedStandard == null) {
      final supportedStandards = CppLanguageStandard.values
          .map((standard) => 'c++${standard.cmakeValue}')
          .join(', ');
      final message =
          'Clang/C++ version selection failed: unsupported C++ standard $cppStandard. Supported standards: $supportedStandards.';
      log(message);
      notifyListeners();
      return ToolchainSelectionResult(
        status: ToolchainSelectionStatus.missing,
        kind: ToolchainKind.compiler,
        toolchainId: versionId,
        message: message,
        snapshot: snapshotBeforeSelection,
      );
    }
    final result = await activeManager.selectToolchain(versionId);
    if (result.succeeded) {
      final preference = ClangCppVersionPreference(
        versionId: versionId,
        cppStandard:
            requestedStandard ??
            _clangCppVersionPreference?.cppStandard ??
            CppLanguageStandard.cpp20,
      );
      await activeManager.saveClangCppVersionPreference(preference);
      _clangCppVersionPreference = preference;
    }
    log(
      result.succeeded
          ? 'Clang/C++ version selected: ${result.toolchainId}.'
          : 'Clang/C++ version selection failed: ${result.message ?? result.status.name}.',
    );
    await _refreshStatusAfterSelection(result);
    notifyListeners();
    return result;
  }

  Future<ToolchainSelectionResult?> clearCandidate(ToolchainKind kind) async {
    final activeManager = manager;
    if (activeManager == null) {
      log('Toolchain clear unavailable: no ToolchainManager is wired.');
      notifyListeners();
      return null;
    }
    final result = await activeManager.clearActiveToolchain(kind);
    log(
      result.succeeded
          ? 'Toolchain active selection cleared: ${kind.wireValue}.'
          : 'Toolchain clear failed: ${result.message ?? result.status.name}.',
    );
    await _refreshStatusAfterSelection(result);
    notifyListeners();
    return result;
  }

  ToolchainInstallPlan? planManagedInstallation({
    ToolchainKind kind = ToolchainKind.languageService,
    ToolchainInstallPolicy policy = const ToolchainInstallPolicy(),
  }) {
    final activeManager = manager;
    if (activeManager == null) {
      log(
        'Toolchain install planning unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }
    final plan = activeManager.planInstallation(
      ToolchainInstallRequest(requirement: ToolchainRequirement(kind: kind)),
      policy: policy,
    );
    _lastInstallPlan = plan;
    log(
      'Toolchain install plan ${plan.status.name}: ${plan.mode.name}'
      '${plan.message == null ? '' : ' (${plan.message})'}.',
    );
    notifyListeners();
    return plan;
  }

  Future<ToolchainInstallExecutionResult?> executeLastInstallPlan() async {
    final activeManager = manager;
    final plan = _lastInstallPlan;
    if (activeManager == null) {
      log(
        'Toolchain install execution unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }
    if (plan == null) {
      log(
        'Toolchain install execution unavailable: no install plan is prepared.',
      );
      notifyListeners();
      return null;
    }
    if (plan.mode != ToolchainInstallMode.manualSelection) {
      log(
        'Toolchain install execution blocked: ${plan.mode.name} requires an explicit confirmation flow.',
      );
      notifyListeners();
      return null;
    }
    final result = await activeManager.executeInstallPlan(plan);
    _lastInstallExecutionResult = result;
    log(
      'Toolchain install execution ${result.status.name}: ${result.message ?? result.plan.mode.name}.',
    );
    await _refreshStatusAfterInstall(result);
    notifyListeners();
    return result;
  }

  Future<ToolchainManagerBootstrapSummary?> refreshBootstrapSummary({
    String reason = 'toolchain bootstrap refresh',
  }) async {
    final activeManager = manager;
    if (activeManager == null) {
      if (!_disposed) {
        log(
          'Toolchain bootstrap summary unavailable: no ToolchainManager is wired.',
        );
      }
      return null;
    }
    try {
      final summary = await activeManager.bootstrapSummary();
      if (_disposed) {
        return summary;
      }
      _bootstrapSummary = summary;
      log(
        'Toolchain bootstrap summary refreshed: '
        '${summary.ready ? 'ready' : 'actionable'} ($reason).',
      );
      return summary;
    } on Object catch (error) {
      if (!_disposed) {
        log('Toolchain bootstrap summary refresh failed: $error');
      }
      return null;
    }
  }

  Future<ToolchainBootstrapActionDispatchResult?> handleBootstrapAction(
    String actionId,
  ) async {
    final summary =
        _bootstrapSummary ??
        await refreshBootstrapSummary(reason: 'action $actionId');
    if (summary == null) {
      final result = ToolchainBootstrapActionDispatchResult(
        status: ToolchainBootstrapActionDispatchStatus.blocked,
        actionId: actionId,
        message:
            'Toolchain bootstrap action blocked: no bootstrap summary is available.',
        todo:
            'TODO: provide a ToolchainManager before routing bootstrap actions.',
      );
      _lastBootstrapActionDispatch = result;
      notifyListeners();
      return result;
    }
    final fallbackInstallKind = summary.managerReport.requirement.kind;
    final router = ToolchainBootstrapActionRouter(
      onSettingsAction: _dispatchBootstrapSettingsAction,
      onInstallerAction: (step) => _dispatchBootstrapInstallerAction(
        step,
        fallbackInstallKind: fallbackInstallKind,
      ),
      onProjectAction: _dispatchBootstrapProjectAction,
    );
    final result = await router.dispatch(summary.executionPlan(), actionId);
    _lastBootstrapActionDispatch = result;
    log(
      'Toolchain bootstrap action ${result.status.wireValue}: '
      '${result.actionId}${result.message.isEmpty ? '' : ' (${result.message})'}.',
    );
    notifyListeners();
    return result;
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchBootstrapSettingsAction(ToolchainBootstrapActionStep step) async {
    if (step.actionId == 'select-existing-toolchain') {
      log('Toolchain bootstrap selection route requested: ${step.actionId}.');
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Selection route requested.',
      );
    }
    if (step.actionId == 'install-managed-toolchain') {
      final plan = planManagedInstallation();
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No managed install plan could be prepared.',
          todo: 'TODO: bind the generic install action to the installer flow.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Managed install plan prepared.',
      );
    }
    if (step.actionId == 'open-toolchain-settings') {
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Toolchain settings route requested.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Settings bootstrap action is not implemented.',
      todo: 'TODO: bind ${step.actionId} to the concrete Settings UI action.',
    );
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchBootstrapInstallerAction(
    ToolchainBootstrapActionStep step, {
    required ToolchainKind fallbackInstallKind,
  }) async {
    if (step.actionId == 'plan-managed-toolchain-installation') {
      final plan = planManagedInstallation(kind: fallbackInstallKind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No managed install plan could be prepared.',
          todo: 'TODO: bind the managed installer to production installer UX.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message:
            'Managed install plan prepared for ${fallbackInstallKind.wireValue}.',
      );
    }
    if (step.actionId == 'verify-toolchain') {
      await refreshBootstrapSummary(reason: 'verify action');
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Toolchain verification refreshed.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Installer bootstrap action is not implemented.',
      todo: 'TODO: bind ${step.actionId} to the concrete installer executor.',
    );
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchBootstrapProjectAction(ToolchainBootstrapActionStep step) async {
    if (step.actionId == 'open-toolchain-settings') {
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Toolchain settings panel should stay focused.',
      );
    }
    if (step.actionId == 'validate-project-toolchain') {
      await refreshBootstrapSummary(reason: step.actionId);
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Project toolchain bootstrap facts refreshed.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Project bootstrap action is not implemented.',
      todo:
          'TODO: bind ${step.actionId} to the concrete project bootstrap runner.',
    );
  }

  Future<void> handleRecoveryAction(ToolchainRecoveryAction action) async {
    log('Toolchain recovery requested: ${action.id}.');
    if (action.id == 'show-toolchain-logs') {
      log('Toolchain log view requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'select-existing-toolchain') {
      log('Toolchain selection route requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'configure-managed-download') {
      log('Toolchain managed download configuration route requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'enable-toolchain-installation') {
      log('Toolchain installation policy settings route requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'retry-external-installer') {
      await executeLastInstallPlan();
      return;
    }
    if (action.id == 'install-managed-toolchain') {
      planManagedInstallation();
      return;
    }
    if (action.id == 'use-degraded-mode') {
      log('Toolchain degraded mode requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'fix-toolchain-precondition') {
      log('Toolchain precondition recovery: ${action.description}');
      notifyListeners();
      return;
    }
    log('Toolchain recovery action is not wired: ${action.id}.');
    notifyListeners();
  }

  Future<void> _refreshStatusAfterSelection(
    ToolchainSelectionResult result,
  ) async {
    _lastSnapshot = result.snapshot;
    final activeManager = manager;
    final notifier = statusReport;
    if (activeManager == null ||
        notifier is! ValueNotifier<ToolchainManagerStatusReport>) {
      return;
    }
    final kind = result.kind ?? notifier.value.requirement.kind;
    notifier.value = await activeManager.statusReport(kind: kind);
  }

  Future<void> _refreshStatusAfterInstall(
    ToolchainInstallExecutionResult result,
  ) async {
    final activeManager = manager;
    final notifier = statusReport;
    if (activeManager == null ||
        notifier is! ValueNotifier<ToolchainManagerStatusReport>) {
      return;
    }
    notifier.value = await activeManager.statusReport(
      kind: result.plan.requirement.kind,
    );
  }

  void _handleStatusReportChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    statusReport?.removeListener(_handleStatusReportChanged);
    super.dispose();
  }
}
