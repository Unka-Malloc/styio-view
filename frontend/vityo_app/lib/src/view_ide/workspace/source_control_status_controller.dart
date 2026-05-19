import 'package:flutter/foundation.dart';

import 'source_control_status.dart';

class SourceControlStatusController extends ChangeNotifier {
  SourceControlStatusController({
    required this.provider,
    required this.workspaceRoot,
  });

  final SourceControlStatusProvider provider;
  final String workspaceRoot;

  SourceControlStatusSnapshot? _snapshot;
  int _generation = 0;

  SourceControlStatusSnapshot? get snapshot => _snapshot;
  bool get hasSnapshot => _snapshot != null;

  Future<SourceControlStatusSnapshot> refresh() async {
    final generation = ++_generation;
    final nextSnapshot = await provider.status(workspaceRoot: workspaceRoot);
    if (generation == _generation) {
      _snapshot = nextSnapshot;
      notifyListeners();
    }
    return nextSnapshot;
  }

  void recordStatus(SourceControlStatusSnapshot snapshot) {
    _generation++;
    _snapshot = snapshot;
    notifyListeners();
  }

  void clear() {
    if (_snapshot == null) {
      return;
    }
    _generation++;
    _snapshot = null;
    notifyListeners();
  }
}
