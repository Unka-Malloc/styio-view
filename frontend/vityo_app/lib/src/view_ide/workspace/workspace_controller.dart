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
               : '');

  ProjectGraphSnapshot _projectSnapshot;
  String _activeFilePath;

  ProjectGraphSnapshot get activeProject => _projectSnapshot;

  List<String> get files => _projectSnapshot.editorFiles;

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
    notifyListeners();
  }

  void openFile(String filePath) {
    if (_activeFilePath == filePath) {
      return;
    }
    _activeFilePath = filePath;
    notifyListeners();
  }

  void openTarget(ProjectTargetDescriptor target) {
    if (_activeFilePath == target.filePath) {
      return;
    }
    _activeFilePath = target.filePath;
    notifyListeners();
  }
}
