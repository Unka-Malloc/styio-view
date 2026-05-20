import 'package:flutter/foundation.dart';

import 'workspace_controller.dart';
import 'workspace_file_operations.dart';
import 'workspace_file_explorer_state_store.dart';

enum WorkspaceFileExplorerNodeKind { directory, file }

extension WorkspaceFileExplorerNodeKindX on WorkspaceFileExplorerNodeKind {
  String get wireValue {
    return switch (this) {
      WorkspaceFileExplorerNodeKind.directory => 'directory',
      WorkspaceFileExplorerNodeKind.file => 'file',
    };
  }
}

class WorkspaceFileExplorerNode {
  const WorkspaceFileExplorerNode({
    required this.name,
    required this.path,
    required this.kind,
    this.children = const <WorkspaceFileExplorerNode>[],
  });

  final String name;
  final String path;
  final WorkspaceFileExplorerNodeKind kind;
  final List<WorkspaceFileExplorerNode> children;

  int get fileCount {
    if (kind == WorkspaceFileExplorerNodeKind.file) {
      return 1;
    }
    return children.fold<int>(0, (total, child) => total + child.fileCount);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'path': path,
      'kind': kind.wireValue,
      'fileCount': fileCount,
      if (children.isNotEmpty)
        'children': children
            .map((child) => child.toJson())
            .toList(growable: false),
    };
  }
}

class WorkspaceFileExplorerSnapshot {
  const WorkspaceFileExplorerSnapshot({
    required this.roots,
    required this.activeFilePath,
    required this.openFilePaths,
    this.state,
    this.discovery,
  });

  final List<WorkspaceFileExplorerNode> roots;
  final String activeFilePath;
  final List<String> openFilePaths;
  final WorkspaceFileExplorerState? state;
  final WorkspaceFileExplorerDiscoveryResult? discovery;

  int get fileCount {
    return roots.fold<int>(0, (total, root) => total + root.fileCount);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'activeFilePath': activeFilePath,
      'openFilePaths': openFilePaths,
      'fileCount': fileCount,
      if (state != null) 'state': state!.toJson(),
      if (discovery != null) 'discovery': discovery!.toJson(),
      'roots': roots.map((root) => root.toJson()).toList(growable: false),
    };
  }
}

class WorkspaceFileExplorerDiscoveryResult {
  const WorkspaceFileExplorerDiscoveryResult({
    required this.source,
    required this.filePaths,
    this.ignoredPaths = const <String>[],
    this.truncated = false,
  });

  factory WorkspaceFileExplorerDiscoveryResult.fromPaths({
    required Iterable<String> discoveredPaths,
    Iterable<String> seedPaths = const <String>[],
    String source = 'file-system-manager',
    int maxFiles = 5000,
  }) {
    final filePaths = <String>[];
    final ignoredPaths = <String>[];
    final seen = <String>{};
    var truncated = false;

    void collectPath(String rawPath) {
      if (filePaths.length >= maxFiles) {
        truncated = true;
        return;
      }
      final normalizedPath = _normalizeWorkspaceFileExplorerPath(rawPath);
      if (_validateWorkspaceFileExplorerPath(normalizedPath) != null) {
        ignoredPaths.add(rawPath);
        return;
      }
      if (seen.add(normalizedPath)) {
        filePaths.add(normalizedPath);
      }
    }

    for (final seedPath in seedPaths) {
      collectPath(seedPath);
    }
    for (final discoveredPath in discoveredPaths) {
      collectPath(discoveredPath);
    }
    filePaths.sort();

    return WorkspaceFileExplorerDiscoveryResult(
      source: source,
      filePaths: List.unmodifiable(filePaths),
      ignoredPaths: List.unmodifiable(ignoredPaths),
      truncated: truncated,
    );
  }

  final String source;
  final List<String> filePaths;
  final List<String> ignoredPaths;
  final bool truncated;

  int get fileCount => filePaths.length;
  int get ignoredPathCount => ignoredPaths.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source,
      'fileCount': fileCount,
      'ignoredPathCount': ignoredPathCount,
      'truncated': truncated,
      'filePaths': filePaths,
      if (ignoredPaths.isNotEmpty) 'ignoredPaths': ignoredPaths,
    };
  }
}

String _normalizeWorkspaceFileExplorerPath(String path) {
  return path.trim().replaceAll('\\', '/');
}

String? _validateWorkspaceFileExplorerPath(String path) {
  if (path.isEmpty) {
    return 'Workspace file path is empty.';
  }
  if (path.startsWith('/') || path.contains('..')) {
    return 'Workspace file path must stay inside the workspace.';
  }
  return null;
}

class WorkspaceFileExplorerActionRequest {
  const WorkspaceFileExplorerActionRequest({
    required this.kind,
    required this.path,
    this.nextPath = '',
    this.text = '',
    this.open = false,
  });

  final WorkspaceFileOperationKind kind;
  final String path;
  final String nextPath;
  final String text;
  final bool open;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'path': path,
      if (nextPath.isNotEmpty) 'nextPath': nextPath,
      if (text.isNotEmpty) 'textLength': text.length,
      'open': open,
    };
  }
}

class WorkspaceFileExplorerController extends ChangeNotifier {
  WorkspaceFileExplorerController({
    required this.workspaceController,
    required this.operationService,
    this.stateStore,
    String? stateWorkspaceId,
  }) {
    _state = WorkspaceFileExplorerState(
      workspaceId: stateWorkspaceId ?? workspaceController.activeProject.id,
    );
    workspaceController.addListener(_handleWorkspaceChanged);
  }

  final WorkspaceController workspaceController;
  final WorkspaceFileOperationService operationService;
  final WorkspaceFileExplorerStateStore? stateStore;

  WorkspaceFileOperationResult? _lastResult;
  late WorkspaceFileExplorerState _state;

  WorkspaceFileOperationResult? get lastResult => _lastResult;
  WorkspaceFileExplorerState get state => _state;

  WorkspaceFileExplorerSnapshot get snapshot {
    return WorkspaceFileExplorerSnapshot(
      roots: buildWorkspaceFileExplorerTree(workspaceController.files),
      activeFilePath: workspaceController.activeFilePath,
      openFilePaths: workspaceController.openFilePaths,
      state: _state,
    );
  }

  WorkspaceFileExplorerSnapshot snapshotFromDiscovery(
    WorkspaceFileExplorerDiscoveryResult discovery,
  ) {
    return WorkspaceFileExplorerSnapshot(
      roots: buildWorkspaceFileExplorerTree(discovery.filePaths),
      activeFilePath: workspaceController.activeFilePath,
      openFilePaths: workspaceController.openFilePaths,
      state: _state,
      discovery: discovery,
    );
  }

  Future<WorkspaceFileExplorerState> restoreState() async {
    final store = stateStore;
    if (store == null) {
      return _state;
    }
    _state = await store.readState(workspaceId: _state.workspaceId);
    notifyListeners();
    return _state;
  }

  Future<void> persistState() async {
    await stateStore?.saveState(_state);
  }

  Future<void> toggleDirectory(String path) async {
    _state = _state.toggleExpanded(path);
    await persistState();
    notifyListeners();
  }

  Future<void> selectPath(String path) async {
    _state = _state.selectPath(path);
    await persistState();
    notifyListeners();
  }

  Future<void> setSortMode(WorkspaceFileExplorerSortMode sortMode) async {
    _state = _state.withSortMode(sortMode);
    await persistState();
    notifyListeners();
  }

  Future<WorkspaceFileOperationResult> run(
    WorkspaceFileExplorerActionRequest request,
  ) async {
    final result = switch (request.kind) {
      WorkspaceFileOperationKind.create => await operationService.createFile(
        path: request.path,
        text: request.text,
        open: request.open,
      ),
      WorkspaceFileOperationKind.rename => await operationService.renameFile(
        path: request.path,
        nextPath: request.nextPath,
        open: request.open,
      ),
      WorkspaceFileOperationKind.delete => await operationService.deleteFile(
        request.path,
      ),
      WorkspaceFileOperationKind.reveal => operationService.revealFile(
        request.path,
      ),
    };
    if (result.applied && request.kind == WorkspaceFileOperationKind.reveal) {
      _state = _state.revealPath(result.path);
      await persistState();
    }
    _lastResult = result;
    notifyListeners();
    return result;
  }

  void _handleWorkspaceChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    workspaceController.removeListener(_handleWorkspaceChanged);
    super.dispose();
  }
}

List<WorkspaceFileExplorerNode> buildWorkspaceFileExplorerTree(
  Iterable<String> filePaths,
) {
  final root = _MutableWorkspaceFileExplorerNode.directory('', '');
  final sortedPaths =
      filePaths
          .map((path) => path.trim().replaceAll('\\', '/'))
          .where((path) => path.isNotEmpty)
          .toList(growable: false)
        ..sort();

  for (final filePath in sortedPaths) {
    final parts = filePath
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    var cursor = root;
    for (var index = 0; index < parts.length; index += 1) {
      final part = parts[index];
      final path = parts.take(index + 1).join('/');
      final isFile = index == parts.length - 1;
      cursor = cursor.child(
        name: part,
        path: path,
        kind: isFile
            ? WorkspaceFileExplorerNodeKind.file
            : WorkspaceFileExplorerNodeKind.directory,
      );
    }
  }

  return root.children.map((child) => child.freeze()).toList(growable: false);
}

class _MutableWorkspaceFileExplorerNode {
  _MutableWorkspaceFileExplorerNode({
    required this.name,
    required this.path,
    required this.kind,
  });

  factory _MutableWorkspaceFileExplorerNode.directory(
    String name,
    String path,
  ) {
    return _MutableWorkspaceFileExplorerNode(
      name: name,
      path: path,
      kind: WorkspaceFileExplorerNodeKind.directory,
    );
  }

  final String name;
  final String path;
  final WorkspaceFileExplorerNodeKind kind;
  final List<_MutableWorkspaceFileExplorerNode> children =
      <_MutableWorkspaceFileExplorerNode>[];

  _MutableWorkspaceFileExplorerNode child({
    required String name,
    required String path,
    required WorkspaceFileExplorerNodeKind kind,
  }) {
    for (final child in children) {
      if (child.name == name && child.path == path) {
        return child;
      }
    }
    final next = _MutableWorkspaceFileExplorerNode(
      name: name,
      path: path,
      kind: kind,
    );
    children.add(next);
    children.sort((left, right) {
      if (left.kind != right.kind) {
        return left.kind == WorkspaceFileExplorerNodeKind.directory ? -1 : 1;
      }
      return left.name.compareTo(right.name);
    });
    return next;
  }

  WorkspaceFileExplorerNode freeze() {
    return WorkspaceFileExplorerNode(
      name: name,
      path: path,
      kind: kind,
      children: children.map((child) => child.freeze()).toList(growable: false),
    );
  }
}
