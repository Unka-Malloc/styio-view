import 'package:flutter/foundation.dart';

import 'source_control_status.dart';

class SourceControlStatusController extends ChangeNotifier {
  SourceControlStatusController({
    required this.provider,
    required this.workspaceRoot,
    this.diffProvider,
    this.actionProvider,
    this.partialPatchProvider,
  });

  final SourceControlStatusProvider provider;
  final SourceControlDiffProvider? diffProvider;
  final SourceControlActionProvider? actionProvider;
  final SourceControlPartialPatchProvider? partialPatchProvider;
  final String workspaceRoot;

  SourceControlStatusSnapshot? _snapshot;
  SourceControlDiffSnapshot? _diffPreview;
  SourceControlActionResult? _lastActionResult;
  SourceControlPartialPatchResult? _lastPartialPatchResult;
  SourceControlActionPlan? _pendingActionPlan;
  int _generation = 0;
  int _diffGeneration = 0;
  int _actionGeneration = 0;
  int _partialPatchGeneration = 0;

  SourceControlStatusSnapshot? get snapshot => _snapshot;
  SourceControlDiffSnapshot? get diffPreview => _diffPreview;
  SourceControlActionResult? get lastActionResult => _lastActionResult;
  SourceControlPartialPatchResult? get lastPartialPatchResult =>
      _lastPartialPatchResult;
  SourceControlActionPlan? get pendingActionPlan => _pendingActionPlan;
  bool get hasSnapshot => _snapshot != null;
  bool get hasDiffPreview => _diffPreview != null;
  SourceControlAgentContextSnapshot get agentContextSnapshot {
    return SourceControlAgentContextSnapshot.fromState(
      workspaceRoot: workspaceRoot,
      status: _snapshot,
      diffPreview: _diffPreview,
      pendingActionPlan: _pendingActionPlan,
      lastActionResult: _lastActionResult,
    );
  }

  SourceControlActionPlan planAction(SourceControlActionRequest request) {
    final plan = SourceControlActionPlan.fromRequest(request);
    _pendingActionPlan = plan;
    notifyListeners();
    return plan;
  }

  void clearActionPlan() {
    if (_pendingActionPlan == null) {
      return;
    }
    _pendingActionPlan = null;
    notifyListeners();
  }

  Future<SourceControlActionResult> confirmPendingAction() async {
    final plan = _pendingActionPlan;
    if (plan == null) {
      return const SourceControlActionResult(
        kind: SourceControlActionKind.stage,
        applied: false,
        message: 'Source control action skipped: no pending action plan.',
      );
    }
    if (!plan.canRun) {
      final result = SourceControlActionResult(
        kind: plan.request.kind,
        applied: false,
        paths: plan.normalizedPaths,
        message: plan.blockedReason,
      );
      _lastActionResult = result;
      notifyListeners();
      return result;
    }
    final result = await runAction(plan.request);
    if (identical(plan, _pendingActionPlan)) {
      _pendingActionPlan = null;
      notifyListeners();
    }
    return result;
  }

  Future<SourceControlStatusSnapshot> refresh() async {
    final generation = ++_generation;
    final nextSnapshot = await provider.status(workspaceRoot: workspaceRoot);
    if (generation == _generation) {
      _snapshot = nextSnapshot;
      notifyListeners();
    }
    return nextSnapshot;
  }

  Future<SourceControlActionResult> runAction(
    SourceControlActionRequest request,
  ) async {
    final provider = actionProvider;
    final generation = ++_actionGeneration;
    final result = provider == null
        ? SourceControlActionResult(
            kind: request.kind,
            applied: false,
            paths: request.paths,
            message:
                'Source control action skipped: no action provider is configured.',
          )
        : await provider.runAction(
            workspaceRoot: workspaceRoot,
            request: request,
          );
    if (generation == _actionGeneration) {
      _lastActionResult = result;
      notifyListeners();
    }
    return result;
  }

  Future<SourceControlPartialPatchResult> runHunkAction(
    SourceControlDiffHunkActionPlan plan,
  ) async {
    final provider = partialPatchProvider;
    final generation = ++_partialPatchGeneration;
    final result = provider == null
        ? SourceControlPartialPatchResult(
            kind: plan.kind,
            path: plan.path,
            selectedHunkIndexes: plan.selectedHunkIndexes,
            applied: false,
            message:
                'Source control hunk action skipped: no partial patch provider is configured.',
          )
        : await provider.runHunkAction(
            workspaceRoot: workspaceRoot,
            plan: plan,
          );
    if (generation == _partialPatchGeneration) {
      _lastPartialPatchResult = result;
      notifyListeners();
    }
    return result;
  }

  void recordStatus(SourceControlStatusSnapshot snapshot) {
    _generation++;
    _snapshot = snapshot;
    notifyListeners();
  }

  Future<SourceControlDiffSnapshot> previewDiff(String path) async {
    final provider = diffProvider;
    final normalizedPath = path.trim();
    final generation = ++_diffGeneration;
    final nextSnapshot = provider == null
        ? SourceControlDiffSnapshot(
            providerKind: this.provider.providerKind,
            path: normalizedPath,
            available: false,
            message:
                'Source control diff skipped: no diff provider is configured.',
          )
        : await provider.diff(
            workspaceRoot: workspaceRoot,
            path: normalizedPath,
          );
    if (generation == _diffGeneration) {
      _diffPreview = nextSnapshot;
      notifyListeners();
    }
    return nextSnapshot;
  }

  void clear() {
    if (_snapshot == null) {
      return;
    }
    _generation++;
    _diffGeneration++;
    _actionGeneration++;
    _snapshot = null;
    _diffPreview = null;
    _lastActionResult = null;
    _pendingActionPlan = null;
    notifyListeners();
  }
}
