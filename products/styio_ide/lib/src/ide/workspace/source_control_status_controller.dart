import 'dart:async';

import 'package:flutter/foundation.dart';

import 'source_control_diff_session_store.dart';
import 'source_control_status.dart';

class SourceControlStatusController extends ChangeNotifier {
  SourceControlStatusController({
    required this.provider,
    required this.workspaceRoot,
    this.diffProvider,
    this.actionProvider,
    this.partialPatchProvider,
    this.branchProvider,
    this.branchActionProvider,
    this.historyProvider,
    this.diffSessionStore,
  });

  final SourceControlStatusProvider provider;
  final SourceControlDiffProvider? diffProvider;
  final SourceControlActionProvider? actionProvider;
  final SourceControlPartialPatchProvider? partialPatchProvider;
  final SourceControlBranchProvider? branchProvider;
  final SourceControlBranchActionProvider? branchActionProvider;
  final SourceControlHistoryProvider? historyProvider;
  final SourceControlDiffSessionStore? diffSessionStore;
  final String workspaceRoot;

  SourceControlStatusSnapshot? _snapshot;
  SourceControlDiffSnapshot? _diffPreview;
  SourceControlActionResult? _lastActionResult;
  SourceControlPartialPatchResult? _lastPartialPatchResult;
  SourceControlHunkSelectionState? _hunkSelectionState;
  SourceControlHunkDiscardConfirmationPlan? _pendingHunkDiscardConfirmation;
  SourceControlBranchSnapshot? _branchSnapshot;
  SourceControlBranchSwitchPlan? _pendingBranchSwitchPlan;
  SourceControlBranchSwitchResult? _lastBranchSwitchResult;
  SourceControlHistorySnapshot? _historySnapshot;
  SourceControlActionPlan? _pendingActionPlan;
  SourceControlDiffSessionState? _diffSessionState;
  int _generation = 0;
  int _diffGeneration = 0;
  int _actionGeneration = 0;
  int _partialPatchGeneration = 0;
  int _branchGeneration = 0;
  int _branchSwitchGeneration = 0;
  int _historyGeneration = 0;

  SourceControlStatusSnapshot? get snapshot => _snapshot;
  SourceControlDiffSnapshot? get diffPreview => _diffPreview;
  SourceControlActionResult? get lastActionResult => _lastActionResult;
  SourceControlPartialPatchResult? get lastPartialPatchResult =>
      _lastPartialPatchResult;
  SourceControlHunkSelectionState? get hunkSelectionState =>
      _hunkSelectionState;
  SourceControlHunkDiscardConfirmationPlan?
  get pendingHunkDiscardConfirmation => _pendingHunkDiscardConfirmation;
  SourceControlBranchSnapshot? get branchSnapshot => _branchSnapshot;
  SourceControlBranchSwitchPlan? get pendingBranchSwitchPlan =>
      _pendingBranchSwitchPlan;
  SourceControlBranchSwitchResult? get lastBranchSwitchResult =>
      _lastBranchSwitchResult;
  SourceControlHistorySnapshot? get historySnapshot => _historySnapshot;
  SourceControlActionPlan? get pendingActionPlan => _pendingActionPlan;
  SourceControlDiffSessionState? get diffSessionState => _diffSessionState;
  bool get hasSnapshot => _snapshot != null;
  bool get hasDiffPreview => _diffPreview != null;
  SourceControlAgentContextSnapshot get agentContextSnapshot {
    return SourceControlAgentContextSnapshot.fromState(
      workspaceRoot: workspaceRoot,
      status: _snapshot,
      diffPreview: _diffPreview,
      pendingActionPlan: _pendingActionPlan,
      lastActionResult: _lastActionResult,
      hunkSelectionState: _hunkSelectionState,
      pendingHunkDiscardConfirmation: _pendingHunkDiscardConfirmation,
      lastPartialPatchResult: _lastPartialPatchResult,
      branchSnapshot: _branchSnapshot,
      pendingBranchSwitchPlan: _pendingBranchSwitchPlan,
      lastBranchSwitchResult: _lastBranchSwitchResult,
      historySnapshot: _historySnapshot,
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

  Future<SourceControlDiffSessionState> restoreDiffSession() async {
    final store = diffSessionStore;
    if (store == null) {
      final empty = SourceControlDiffSessionState(workspaceId: workspaceRoot);
      _diffSessionState = empty;
      return empty;
    }
    final session = await store.readSession(workspaceId: workspaceRoot);
    _diffSessionState = session;
    _restoreHunkSelectionFromSession(session);
    notifyListeners();
    return session;
  }

  Future<void> persistDiffSession({SourceControlDiffWindowBinding? binding}) {
    return _persistDiffSession(binding: binding);
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

  SourceControlHunkSelectionState? bindHunkSelection({
    SourceControlDiffSnapshot? snapshot,
    List<int> selectedHunkIndexes = const <int>[],
  }) {
    final activeSnapshot = snapshot ?? _diffPreview;
    if (activeSnapshot == null) {
      return null;
    }
    final selection = SourceControlHunkSelectionState.fromDiff(
      snapshot: activeSnapshot,
      selectedHunkIndexes: selectedHunkIndexes,
    );
    _hunkSelectionState = selection;
    _pendingHunkDiscardConfirmation = null;
    unawaited(_persistDiffSession());
    notifyListeners();
    return selection;
  }

  SourceControlHunkSelectionState? toggleHunkSelection(int hunkIndex) {
    final current = _hunkSelectionState;
    if (current == null) {
      return bindHunkSelection(selectedHunkIndexes: <int>[hunkIndex]);
    }
    final next = current.toggle(hunkIndex);
    _hunkSelectionState = next;
    _pendingHunkDiscardConfirmation = null;
    unawaited(_persistDiffSession());
    notifyListeners();
    return next;
  }

  SourceControlHunkSelectionState? selectAllHunks() {
    final current = _hunkSelectionState;
    final activeSnapshot = current?.snapshot ?? _diffPreview;
    if (activeSnapshot == null) {
      return null;
    }
    final next = SourceControlHunkSelectionState.all(activeSnapshot);
    _hunkSelectionState = next;
    _pendingHunkDiscardConfirmation = null;
    unawaited(_persistDiffSession());
    notifyListeners();
    return next;
  }

  SourceControlHunkSelectionState? clearHunkSelection() {
    final current = _hunkSelectionState;
    final activeSnapshot = current?.snapshot ?? _diffPreview;
    if (activeSnapshot == null) {
      return null;
    }
    final next = SourceControlHunkSelectionState.fromDiff(
      snapshot: activeSnapshot,
    );
    _hunkSelectionState = next;
    _pendingHunkDiscardConfirmation = null;
    unawaited(_persistDiffSession());
    notifyListeners();
    return next;
  }

  SourceControlDiffHunkActionPlan? planSelectedHunkAction(
    SourceControlActionKind kind,
  ) {
    final selection = _hunkSelectionState;
    if (selection == null) {
      return null;
    }
    final plan = selection.toActionPlan(kind: kind);
    _pendingHunkDiscardConfirmation = kind == SourceControlActionKind.discard
        ? SourceControlHunkDiscardConfirmationPlan.fromActionPlan(plan)
        : null;
    notifyListeners();
    return plan;
  }

  SourceControlHunkDiscardConfirmationPlan planHunkDiscardConfirmation(
    SourceControlDiffHunkActionPlan plan,
  ) {
    final confirmation =
        SourceControlHunkDiscardConfirmationPlan.fromActionPlan(plan);
    _pendingHunkDiscardConfirmation = confirmation;
    notifyListeners();
    return confirmation;
  }

  Future<SourceControlPartialPatchResult> confirmPendingHunkDiscard() async {
    final pending = _pendingHunkDiscardConfirmation;
    if (pending == null) {
      return const SourceControlPartialPatchResult(
        kind: SourceControlActionKind.discard,
        path: '',
        selectedHunkIndexes: <int>[],
        applied: false,
        message:
            'Source control hunk discard skipped: no pending confirmation plan.',
      );
    }
    final confirmed = SourceControlHunkDiscardConfirmationPlan.fromActionPlan(
      pending.actionPlan,
      confirmed: true,
    );
    _pendingHunkDiscardConfirmation = confirmed;
    if (!confirmed.canRun) {
      final result = SourceControlPartialPatchResult(
        kind: SourceControlActionKind.discard,
        path: confirmed.path,
        selectedHunkIndexes: confirmed.selectedHunkIndexes,
        applied: false,
        message: confirmed.blockedReason,
      );
      _lastPartialPatchResult = result;
      notifyListeners();
      return result;
    }
    final result = await runHunkAction(confirmed.actionPlan);
    if (result.applied) {
      _pendingHunkDiscardConfirmation = null;
      _hunkSelectionState = _hunkSelectionState?.clear();
      notifyListeners();
    }
    return result;
  }

  Future<SourceControlBranchSnapshot> refreshBranches() async {
    final provider = branchProvider;
    final generation = ++_branchGeneration;
    final nextSnapshot = provider == null
        ? SourceControlBranchSnapshot(
            providerKind: this.provider.providerKind,
            available: false,
            message:
                'Source control branches skipped: no branch provider is configured.',
          )
        : await provider.branches(workspaceRoot: workspaceRoot);
    if (generation == _branchGeneration) {
      _branchSnapshot = nextSnapshot;
      notifyListeners();
    }
    return nextSnapshot;
  }

  SourceControlBranchSwitchPlan planBranchSwitch(String targetBranch) {
    final snapshot =
        _branchSnapshot ??
        SourceControlBranchSnapshot(
          providerKind: provider.providerKind,
          available: false,
          message:
              'Source control branch switch skipped: branch facts have not been loaded.',
        );
    final plan = SourceControlBranchSwitchPlan.fromSnapshot(
      snapshot: snapshot,
      targetBranch: targetBranch,
    );
    _pendingBranchSwitchPlan = plan;
    notifyListeners();
    return plan;
  }

  Future<SourceControlBranchSwitchResult> confirmPendingBranchSwitch() async {
    final plan = _pendingBranchSwitchPlan;
    if (plan == null) {
      return SourceControlBranchSwitchResult(
        providerKind: provider.providerKind,
        targetBranch: '',
        applied: false,
        message: 'Source control branch switch skipped: no pending plan.',
      );
    }
    if (!plan.canRun) {
      final result = SourceControlBranchSwitchResult(
        providerKind: plan.providerKind,
        targetBranch: plan.targetBranch,
        applied: false,
        message: plan.blockedReason,
      );
      _lastBranchSwitchResult = result;
      notifyListeners();
      return result;
    }
    final actionProvider = branchActionProvider;
    final generation = ++_branchSwitchGeneration;
    final result = actionProvider == null
        ? SourceControlBranchSwitchResult(
            providerKind: plan.providerKind,
            targetBranch: plan.targetBranch,
            applied: false,
            message:
                'Source control branch switch skipped: no branch action provider is configured.',
          )
        : await actionProvider.switchBranch(
            workspaceRoot: workspaceRoot,
            plan: plan,
          );
    if (generation == _branchSwitchGeneration) {
      _lastBranchSwitchResult = result;
      if (result.applied) {
        _pendingBranchSwitchPlan = null;
      }
      notifyListeners();
    }
    return result;
  }

  Future<SourceControlHistorySnapshot> refreshHistory({int limit = 25}) async {
    final provider = historyProvider;
    final generation = ++_historyGeneration;
    final nextSnapshot = provider == null
        ? SourceControlHistorySnapshot(
            providerKind: this.provider.providerKind,
            available: false,
            message:
                'Source control history skipped: no history provider is configured.',
          )
        : await provider.history(workspaceRoot: workspaceRoot, limit: limit);
    if (generation == _historyGeneration) {
      _historySnapshot = nextSnapshot;
      notifyListeners();
    }
    return nextSnapshot;
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
      final restoredIndexes = _diffSessionState?.path == nextSnapshot.path
          ? _diffSessionState!.selectedHunkIndexes
          : const <int>[];
      _hunkSelectionState = SourceControlHunkSelectionState.fromDiff(
        snapshot: nextSnapshot,
        selectedHunkIndexes: restoredIndexes,
      );
      _pendingHunkDiscardConfirmation = null;
      await _persistDiffSession();
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
    _partialPatchGeneration++;
    _branchGeneration++;
    _branchSwitchGeneration++;
    _historyGeneration++;
    _snapshot = null;
    _diffPreview = null;
    _lastActionResult = null;
    _lastPartialPatchResult = null;
    _hunkSelectionState = null;
    _pendingHunkDiscardConfirmation = null;
    _branchSnapshot = null;
    _pendingBranchSwitchPlan = null;
    _lastBranchSwitchResult = null;
    _historySnapshot = null;
    _pendingActionPlan = null;
    _diffSessionState = null;
    unawaited(
      diffSessionStore
              ?.deleteSession(workspaceId: workspaceRoot)
              .then((_) {}) ??
          Future<void>.value(),
    );
    notifyListeners();
  }

  void _restoreHunkSelectionFromSession(SourceControlDiffSessionState session) {
    final diff = _diffPreview;
    if (diff == null || diff.path != session.path) {
      return;
    }
    _hunkSelectionState = SourceControlHunkSelectionState.fromDiff(
      snapshot: diff,
      selectedHunkIndexes: session.selectedHunkIndexes,
    );
    _pendingHunkDiscardConfirmation = null;
  }

  Future<void> _persistDiffSession({
    SourceControlDiffWindowBinding? binding,
  }) async {
    final store = diffSessionStore;
    final diff =
        binding?.snapshot ?? _hunkSelectionState?.snapshot ?? _diffPreview;
    if (diff == null) {
      return;
    }
    final session = SourceControlDiffSessionState.fromDiffWindow(
      workspaceId: workspaceRoot,
      binding:
          binding ??
          SourceControlDiffWindowBinding(
            snapshot: diff,
            startLine: _diffSessionState?.path == diff.path
                ? _diffSessionState!.windowStartLine
                : 0,
            lineLimit: _diffSessionState?.path == diff.path
                ? _diffSessionState!.windowLineLimit
                : 200,
          ),
      hunkSelectionState: _hunkSelectionState,
    );
    _diffSessionState = session;
    if (store != null) {
      await store.saveSession(session);
    }
  }
}
