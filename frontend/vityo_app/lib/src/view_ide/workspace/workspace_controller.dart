import 'package:flutter/foundation.dart';

import '../backend_toolchain/project_graph_contract.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController({
    required ProjectGraphSnapshot projectSnapshot,
    String? activeFilePath,
  }) : _projectSnapshot = projectSnapshot,
       _activeFilePath =
           activeFilePath ??
           (projectSnapshot.editorFiles.isNotEmpty
               ? projectSnapshot.editorFiles.first
               : '') {
    _rememberRecent(_activeFilePath);
  }

  ProjectGraphSnapshot _projectSnapshot;
  String _activeFilePath;
  final List<String> _recentFiles = <String>[];

  ProjectGraphSnapshot get activeProject => _projectSnapshot;

  List<String> get files => _projectSnapshot.editorFiles;

  List<String> get recentFiles => List<String>.unmodifiable(_recentFiles);

  List<ProjectTargetDescriptor> get targets => _projectSnapshot.targets;

  String get activeFilePath => _activeFilePath;

  void replaceProject(
    ProjectGraphSnapshot projectSnapshot, {
    String? activeFilePath,
  }) {
    _projectSnapshot = projectSnapshot;
    _activeFilePath =
        activeFilePath ??
        (projectSnapshot.editorFiles.contains(_activeFilePath)
            ? _activeFilePath
            : projectSnapshot.editorFiles.isNotEmpty
            ? projectSnapshot.editorFiles.first
            : '');
    _recentFiles.removeWhere(
      (filePath) => !projectSnapshot.editorFiles.contains(filePath),
    );
    _rememberRecent(_activeFilePath);
    notifyListeners();
  }

  void openFile(String filePath) {
    final changedActiveFile = _activeFilePath != filePath;
    _activeFilePath = filePath;
    final changedRecentFiles = _rememberRecent(filePath);
    if (!changedActiveFile && !changedRecentFiles) {
      return;
    }
    notifyListeners();
  }

  void openTarget(ProjectTargetDescriptor target) {
    final changedActiveFile = _activeFilePath != target.filePath;
    _activeFilePath = target.filePath;
    final changedRecentFiles = _rememberRecent(target.filePath);
    if (!changedActiveFile && !changedRecentFiles) {
      return;
    }
    notifyListeners();
  }

  bool _rememberRecent(String filePath) {
    if (filePath.isEmpty || !_projectSnapshot.editorFiles.contains(filePath)) {
      return false;
    }
    final existingIndex = _recentFiles.indexOf(filePath);
    if (existingIndex == 0) {
      return false;
    }
    if (existingIndex > 0) {
      _recentFiles.removeAt(existingIndex);
    }
    _recentFiles.insert(0, filePath);
    if (_recentFiles.length > 20) {
      _recentFiles.removeRange(20, _recentFiles.length);
    }
    return true;
  }
}
