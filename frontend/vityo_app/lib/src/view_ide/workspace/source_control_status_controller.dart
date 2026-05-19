import 'package:flutter/foundation.dart';

import 'source_control_status.dart';

class SourceControlStatusController extends ChangeNotifier {
  SourceControlStatusController({
    required this.provider,
    required this.workspaceRoot,
    this.diffProvider,
  });

  final SourceControlStatusProvider provider;
  final SourceControlDiffProvider? diffProvider;
  final String workspaceRoot;

  SourceControlStatusSnapshot? _snapshot;
  SourceControlDiffSnapshot? _diffPreview;
  int _generation = 0;
  int _diffGeneration = 0;

  SourceControlStatusSnapshot? get snapshot => _snapshot;
  SourceControlDiffSnapshot? get diffPreview => _diffPreview;
  bool get hasSnapshot => _snapshot != null;
  bool get hasDiffPreview => _diffPreview != null;

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
    _snapshot = null;
    _diffPreview = null;
    notifyListeners();
  }
}
