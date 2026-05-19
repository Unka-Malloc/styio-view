import 'package:flutter/foundation.dart';

import 'workspace_diagnostics.dart';

class WorkspaceDiagnosticsController extends ChangeNotifier {
  WorkspaceDiagnosticsController({
    required WorkspaceDiagnosticsProvider provider,
  }) : _provider = provider;

  final WorkspaceDiagnosticsProvider _provider;
  WorkspaceDiagnosticsSnapshot? _snapshot;
  int _generation = 0;

  WorkspaceDiagnosticsProvider get provider => _provider;
  WorkspaceDiagnosticsSnapshot? get snapshot => _snapshot;
  bool get hasSnapshot => _snapshot != null;

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

  void clear() {
    if (_snapshot == null) {
      return;
    }
    _snapshot = null;
    _generation++;
    notifyListeners();
  }
}
