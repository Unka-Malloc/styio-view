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
    if (_activeFilePath.isNotEmpty) {
      _openFilePaths.add(_activeFilePath);
    }
  }

  ProjectGraphSnapshot _projectSnapshot;
  String _activeFilePath;
  final List<String> _openFilePaths = <String>[];

  ProjectGraphSnapshot get activeProject => _projectSnapshot;

  List<String> get files => _projectSnapshot.editorFiles;

  List<ProjectTargetDescriptor> get targets => _projectSnapshot.targets;

  String get activeFilePath => _activeFilePath;

  List<String> get openFilePaths => List.unmodifiable(_openFilePaths);

  void replaceProject(
    ProjectGraphSnapshot projectSnapshot, {
    String? activeFilePath,
  }) {
    _projectSnapshot = projectSnapshot;
    _openFilePaths.removeWhere(
      (path) => !projectSnapshot.editorFiles.contains(path),
    );
    _activeFilePath =
        activeFilePath ??
        (projectSnapshot.editorFiles.contains(_activeFilePath)
            ? _activeFilePath
            : projectSnapshot.editorFiles.isNotEmpty
            ? projectSnapshot.editorFiles.first
            : '');
    if (_activeFilePath.isNotEmpty && !_openFilePaths.contains(_activeFilePath)) {
      _openFilePaths.add(_activeFilePath);
    }
    notifyListeners();
  }

  void openFile(String filePath) {
    final added = !_openFilePaths.contains(filePath);
    if (added) {
      _openFilePaths.add(filePath);
    }
    if (_activeFilePath == filePath) {
      if (added) {
        notifyListeners();
      }
      return;
    }
    _activeFilePath = filePath;
    notifyListeners();
  }

  void closeFile(String filePath) {
    final removed = _openFilePaths.remove(filePath);
    if (!removed) {
      return;
    }
    if (_activeFilePath == filePath) {
      _activeFilePath = _openFilePaths.isNotEmpty
          ? _openFilePaths.last
          : _projectSnapshot.editorFiles.isNotEmpty
          ? _projectSnapshot.editorFiles.first
          : '';
      if (_activeFilePath.isNotEmpty &&
          !_openFilePaths.contains(_activeFilePath)) {
        _openFilePaths.add(_activeFilePath);
      }
    }
    notifyListeners();
  }

  void registerFile(String filePath, {bool open = false}) {
    if (filePath.trim().isEmpty) {
      return;
    }
    if (_projectSnapshot.editorFiles.contains(filePath)) {
      if (open) {
        openFile(filePath);
      }
      return;
    }
    _projectSnapshot = _projectSnapshot.copyWith(
      editorFiles: List<String>.unmodifiable(<String>[
        ..._projectSnapshot.editorFiles,
        filePath,
      ]),
    );
    if (open) {
      openFile(filePath);
      return;
    }
    notifyListeners();
  }

  void unregisterFile(String filePath) {
    if (!_projectSnapshot.editorFiles.contains(filePath)) {
      return;
    }
    _projectSnapshot = _projectSnapshot.copyWith(
      editorFiles: List<String>.unmodifiable(
        _projectSnapshot.editorFiles.where((path) => path != filePath),
      ),
    );
    _openFilePaths.remove(filePath);
    if (_activeFilePath == filePath) {
      _activeFilePath = _openFilePaths.isNotEmpty
          ? _openFilePaths.last
          : _projectSnapshot.editorFiles.isNotEmpty
          ? _projectSnapshot.editorFiles.first
          : '';
      if (_activeFilePath.isNotEmpty &&
          !_openFilePaths.contains(_activeFilePath)) {
        _openFilePaths.add(_activeFilePath);
      }
    }
    notifyListeners();
  }

  void restoreOpenFiles(
    List<String> filePaths, {
    String? activeFilePath,
  }) {
    final restored = <String>[];
    for (final filePath in filePaths) {
      if (!_projectSnapshot.editorFiles.contains(filePath) ||
          restored.contains(filePath)) {
        continue;
      }
      restored.add(filePath);
    }

    final nextActiveFilePath =
        activeFilePath != null && restored.contains(activeFilePath)
        ? activeFilePath
        : restored.contains(_activeFilePath)
        ? _activeFilePath
        : restored.isNotEmpty
        ? restored.last
        : _projectSnapshot.editorFiles.isNotEmpty
        ? _projectSnapshot.editorFiles.first
        : '';

    _openFilePaths
      ..clear()
      ..addAll(restored);
    if (nextActiveFilePath.isNotEmpty &&
        !_openFilePaths.contains(nextActiveFilePath)) {
      _openFilePaths.add(nextActiveFilePath);
    }
    _activeFilePath = nextActiveFilePath;
    notifyListeners();
  }

  void openTarget(ProjectTargetDescriptor target) {
    openFile(target.filePath);
  }
}
