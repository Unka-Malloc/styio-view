import 'package:flutter/foundation.dart';

import '../../backend_toolchain/backend_toolchain.dart';
import '../../interaction/toolchain_status_surface.dart';
import '../../toolchain/toolchain.dart' hide ToolchainRecoveryAction;

/// Owns active toolchain and Clang/C++ version selection state.
final class ToolchainController extends ChangeNotifier {
  ToolchainController({
    required this.managementAdapter,
    required this.projectGraph,
    required this.refreshProjectGraph,
    required this.manager,
    required this.statusReport,
    required this.log,
    ClangCppVersionPreference? clangCppVersionPreference,
  }) : _clangCppVersionPreference = clangCppVersionPreference {
    statusReport?.addListener(_handleStatusReportChanged);
  }

  final ToolchainManager? manager;
  final ToolchainManagementAdapter managementAdapter;
  final ProjectGraphSnapshot Function() projectGraph;
  final Future<void> Function({String? reason}) refreshProjectGraph;
  final ValueListenable<ToolchainManagerStatusReport>? statusReport;
  final void Function(String message) log;

  ClangCppVersionPreference? _clangCppVersionPreference;
  ToolchainStateSnapshot? _lastSnapshot;
  ToolchainInstallPlan? _lastInstallPlan;
  ToolchainInstallExecutionResult? _lastInstallExecutionResult;
  ToolchainManagerBootstrapSummary? _bootstrapSummary;
  ToolchainBootstrapActionDispatchResult? _lastBootstrapActionDispatch;
  ToolchainCommandResult? _lastCommand;
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
  ToolchainCommandResult? get lastCommand => _lastCommand;
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
      return ToolchainStatusSurface.fromManagerStatusReport(
        report,
        lastCommand: _lastCommand,
      );
    }
    return ToolchainStatusSurface.fromProjectToolchain(
      projectGraph().toolchain,
      lastCommand: _lastCommand,
    );
  }

  ToolchainSettingsSurface get settingsSurface {
    final report = statusReport?.value;
    if (report != null) {
      return ToolchainSettingsSurface.fromManagerStatusReport(
        report,
        lastCommand: _lastCommand,
        clangCppVersionPreference: _clangCppVersionPreference,
      );
    }
    return ToolchainSettingsSurface.fromStatus(statusSurface);
  }

  Future<ToolchainCommandResult> installManagedCompiler({
    required String styioBinaryPath,
  }) async {
    final result = await managementAdapter.installManagedCompiler(
      projectGraph: projectGraph(),
      styioBinaryPath: styioBinaryPath,
    );
    return _completeCommand(result, refreshReason: 'tool install completed');
  }

  Future<ToolchainCommandResult> useManagedCompiler({
    required String compilerVersion,
    String? channel,
  }) async {
    final result = await managementAdapter.useManagedCompiler(
      projectGraph: projectGraph(),
      compilerVersion: compilerVersion,
      channel: channel,
    );
    return _completeCommand(result, refreshReason: 'tool use completed');
  }

  Future<ToolchainCommandResult> pinManagedCompiler({
    required String compilerVersion,
    String? channel,
  }) async {
    final result = await managementAdapter.pinManagedCompiler(
      projectGraph: projectGraph(),
      compilerVersion: compilerVersion,
      channel: channel,
    );
    return _completeCommand(result, refreshReason: 'tool pin completed');
  }

  Future<ToolchainCommandResult> clearPinnedCompiler() async {
    final result = await managementAdapter.clearPinnedCompiler(
      projectGraph: projectGraph(),
    );
    return _completeCommand(result, refreshReason: 'tool pin clear completed');
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
    final fallbackInstallKind =
        _firstMissingStyioToolchainKind(summary) ??
        ToolchainKind.languageService;
    final router = ToolchainBootstrapActionRouter(
      onSettingsAction: _dispatchBootstrapSettingsAction,
      onInstallerAction: (step) => _dispatchBootstrapInstallerAction(
        step,
        fallbackInstallKind: fallbackInstallKind,
      ),
      onProjectAction: (step) => _dispatchBootstrapProjectAction(
        step,
        fallbackInstallKind: fallbackInstallKind,
      ),
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
    if (step.actionId.startsWith('select-styio-')) {
      log('Toolchain bootstrap selection route requested: ${step.actionId}.');
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Selection route requested.',
      );
    }
    if (step.actionId.startsWith('install-styio-')) {
      final kind =
          _toolchainKindForStyioBootstrapAction(step.actionId) ??
          ToolchainKind.languageService;
      final plan = planManagedInstallation(kind: kind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No managed install plan could be prepared.',
          todo:
              'TODO: bind Styio role install actions to the production installer flow.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Managed install plan prepared for ${kind.wireValue}.',
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
    if (step.actionId == 'install-managed-styio-toolchain') {
      final plan = planManagedInstallation(kind: fallbackInstallKind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No managed install plan could be prepared.',
          todo:
              'TODO: bind managed Styio installer to production installer UX.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message:
            'Managed install plan prepared for ${fallbackInstallKind.wireValue}.',
      );
    }
    if (step.actionId == 'verify-styio-toolchain') {
      await refreshBootstrapSummary(reason: 'verify action');
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Styio toolchain verification refreshed.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Installer bootstrap action is not implemented.',
      todo: 'TODO: bind ${step.actionId} to the concrete installer executor.',
    );
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchBootstrapProjectAction(
    ToolchainBootstrapActionStep step, {
    required ToolchainKind fallbackInstallKind,
  }) async {
    if (step.actionId == 'open-toolchain-settings') {
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Toolchain settings panel should stay focused.',
      );
    }
    if (step.actionId == 'bootstrap-styio-toolchain') {
      final summary = await refreshBootstrapSummary(reason: step.actionId);
      if (summary?.ready ?? false) {
        return ToolchainBootstrapActionDispatchResult.dispatched(
          step,
          message: 'Project Styio toolchain bootstrap is already ready.',
        );
      }
      final plan = planManagedInstallation(kind: fallbackInstallKind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No project bootstrap install plan could be prepared.',
          todo:
              'TODO: bind project bootstrap to the production Styio installer runner.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message:
            'Project bootstrap prepared managed install plan for ${fallbackInstallKind.wireValue}.',
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

  ToolchainKind? _toolchainKindForStyioBootstrapAction(String actionId) {
    for (final role in StyioToolchainRole.values) {
      if (actionId.endsWith(role.wireValue)) {
        return role.toolchainKind;
      }
    }
    return null;
  }

  ToolchainKind? _firstMissingStyioToolchainKind(
    ToolchainManagerBootstrapSummary summary,
  ) {
    for (final role in summary.styioLifecycle.missingRequiredRoles) {
      return role.role.toolchainKind;
    }
    return null;
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
    if (action.id == 'retry-tool-use') {
      final compiler = projectGraph().activeCompiler;
      if (compiler == null) {
        log('Toolchain retry blocked: no active compiler is resolved.');
        notifyListeners();
        return;
      }
      await useManagedCompiler(
        compilerVersion: compiler.compilerVersion,
        channel: compiler.channel,
      );
      return;
    }
    if (action.id == 'retry-tool-pin') {
      final compiler = projectGraph().activeCompiler;
      if (compiler == null) {
        log('Toolchain retry blocked: no active compiler is resolved.');
        notifyListeners();
        return;
      }
      await pinManagedCompiler(
        compilerVersion: compiler.compilerVersion,
        channel: compiler.channel,
      );
      return;
    }
    log('Toolchain recovery action is not wired: ${action.id}.');
    notifyListeners();
  }

  Future<ToolchainCommandResult> _completeCommand(
    ToolchainCommandResult result, {
    required String refreshReason,
  }) async {
    _lastCommand = result;
    log('${result.command} ${result.status.name}: ${result.statusMessage}');
    if (result.succeeded) {
      await refreshProjectGraph(reason: refreshReason);
    } else {
      notifyListeners();
    }
    return result;
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
