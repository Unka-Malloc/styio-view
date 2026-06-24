import 'package:flutter/foundation.dart';

import 'workspace_diagnostics.dart';
import 'workspace_diagnostics_filter_store.dart';

class WorkspaceDiagnosticsController extends ChangeNotifier {
  WorkspaceDiagnosticsController({
    required WorkspaceDiagnosticsProvider provider,
    WorkspaceDiagnosticsFilterStore? filterStore,
    WorkspaceDiagnosticsProducerLifecycleController?
    producerLifecycleController,
    WorkspaceDiagnosticsProducerProcessHandleRegistry?
    producerProcessHandleRegistry,
    Map<String, WorkspaceDiagnosticsProducerCancellationAdapter>
        producerCancellationAdapters =
        const <String, WorkspaceDiagnosticsProducerCancellationAdapter>{},
    String workspaceId = 'default',
  }) : _provider = provider,
       _filterStore = filterStore,
       _producerLifecycleController = producerLifecycleController,
       _producerProcessHandleRegistry = producerProcessHandleRegistry,
       _producerCancellationAdapters =
           Map<String, WorkspaceDiagnosticsProducerCancellationAdapter>.of(
             producerCancellationAdapters,
           ),
       _workspaceId = workspaceId;

  final WorkspaceDiagnosticsProvider _provider;
  final WorkspaceDiagnosticsFilterStore? _filterStore;
  final WorkspaceDiagnosticsProducerLifecycleController?
  _producerLifecycleController;
  final WorkspaceDiagnosticsProducerProcessHandleRegistry?
  _producerProcessHandleRegistry;
  final Map<String, WorkspaceDiagnosticsProducerCancellationAdapter>
  _producerCancellationAdapters;
  final String _workspaceId;
  WorkspaceDiagnosticsSnapshot? _snapshot;
  WorkspaceDiagnosticsFilterState _filterState =
      const WorkspaceDiagnosticsFilterState();
  int _generation = 0;

  WorkspaceDiagnosticsProvider get provider => _provider;
  WorkspaceDiagnosticsSnapshot? get snapshot => _snapshot;
  WorkspaceDiagnosticsFilterState get filterState => _filterState;
  List<WorkspaceDiagnosticsProducerLifecycleSnapshot>
  get diagnosticsProducerLifecycles =>
      _producerLifecycleController?.snapshots ??
      const <WorkspaceDiagnosticsProducerLifecycleSnapshot>[];
  bool get hasSnapshot => _snapshot != null;
  WorkspaceDiagnosticsView? get view {
    final currentSnapshot = _snapshot;
    if (currentSnapshot == null) {
      return null;
    }
    return WorkspaceDiagnosticsView.fromSnapshot(
      currentSnapshot,
      filter: _filterState,
    );
  }

  Future<WorkspaceDiagnosticsFilterState> loadFilter({
    String key = 'default',
  }) async {
    final store = _filterStore;
    if (store == null) {
      return _filterState;
    }
    _filterState = await store.readFilter(workspaceId: _workspaceId, key: key);
    notifyListeners();
    return _filterState;
  }

  Future<void> setFilter(
    WorkspaceDiagnosticsFilterState filter, {
    bool persist = true,
    String key = 'default',
  }) async {
    _filterState = filter;
    notifyListeners();
    if (persist) {
      await _filterStore?.saveFilter(
        workspaceId: _workspaceId,
        key: key,
        filter: filter,
      );
    }
  }

  Future<void> clearFilter({
    bool persist = true,
    String key = 'default',
  }) async {
    _filterState = const WorkspaceDiagnosticsFilterState();
    notifyListeners();
    if (persist) {
      await _filterStore?.deleteFilter(workspaceId: _workspaceId, key: key);
    }
  }

  Future<WorkspaceDiagnosticsSnapshot> refresh(
    WorkspaceDiagnosticsRequest request,
  ) async {
    final generation = ++_generation;
    try {
      final nextSnapshot = await _provider.collect(request);
      if (generation == _generation) {
        _snapshot = nextSnapshot;
        notifyListeners();
      }
      return nextSnapshot;
    } on Object catch (error) {
      final fallback = WorkspaceDiagnosticsSnapshot(
        providerId: _provider.providerId,
        diagnostics: const <WorkspaceDiagnostic>[],
        message:
            'Workspace diagnostics unavailable: $error. '
            'TODO: surface retry and provider health details.',
      );
      if (generation == _generation) {
        _snapshot = fallback;
        notifyListeners();
      }
      return fallback;
    }
  }

  Future<WorkspaceDiagnosticsProducerLifecycleSnapshot?>
  cancelDiagnosticsProducer(
    WorkspaceDiagnosticsProducerLifecycleSnapshot snapshot, {
    String reason = 'User cancelled diagnostics producer.',
  }) async {
    final lifecycleController = _producerLifecycleController;
    if (lifecycleController == null) {
      return null;
    }
    final plan = lifecycleController.planForProvider(snapshot.providerId);
    if (plan == null) {
      return null;
    }
    final adapter =
        _producerCancellationAdapters[snapshot.providerId] ??
        _producerProcessHandleRegistry?.adapterForProvider(snapshot.providerId);
    final result = adapter == null
        ? lifecycleController.requestCancellation(plan, reason: reason)
        : await lifecycleController.requestProcessCancellation(
            plan,
            adapter: adapter,
            reason: reason,
          );
    notifyListeners();
    return result;
  }

  void clear() {
    if (_snapshot == null) {
      return;
    }
    _snapshot = null;
    _generation++;
    notifyListeners();
  }
}
