import '../foundation/foundation.dart';

enum WorkspaceFileExplorerSortMode { foldersFirst, alphabetical }

extension WorkspaceFileExplorerSortModeX on WorkspaceFileExplorerSortMode {
  String get wireValue => switch (this) {
    WorkspaceFileExplorerSortMode.foldersFirst => 'folders-first',
    WorkspaceFileExplorerSortMode.alphabetical => 'alphabetical',
  };
}

class WorkspaceFileExplorerState {
  const WorkspaceFileExplorerState({
    required this.workspaceId,
    this.expandedPaths = const <String>[],
    this.selectedPath = '',
    this.revealedPath = '',
    this.sortMode = WorkspaceFileExplorerSortMode.foldersFirst,
    this.updatedAt,
  });

  factory WorkspaceFileExplorerState.fromJson(Map<String, Object?> json) {
    return WorkspaceFileExplorerState(
      workspaceId: json['workspaceId'] as String? ?? '',
      expandedPaths: _jsonStringList(json['expandedPaths']),
      selectedPath: json['selectedPath'] as String? ?? '',
      revealedPath: json['revealedPath'] as String? ?? '',
      sortMode: _sortModeFromWire(json['sortMode']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<String> expandedPaths;
  final String selectedPath;
  final String revealedPath;
  final WorkspaceFileExplorerSortMode sortMode;
  final DateTime? updatedAt;

  WorkspaceFileExplorerState toggleExpanded(String path) {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return this;
    }
    final nextExpanded = expandedPaths.contains(normalizedPath)
        ? expandedPaths
              .where((expandedPath) => expandedPath != normalizedPath)
              .toList(growable: false)
        : _sortedPaths(<String>[...expandedPaths, normalizedPath]);
    return copyWith(
      expandedPaths: nextExpanded,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  WorkspaceFileExplorerState selectPath(String path) {
    return copyWith(
      selectedPath: _normalizePath(path),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  WorkspaceFileExplorerState revealPath(String path) {
    final normalizedPath = _normalizePath(path);
    return copyWith(
      selectedPath: normalizedPath,
      revealedPath: normalizedPath,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  WorkspaceFileExplorerState withSortMode(WorkspaceFileExplorerSortMode mode) {
    return copyWith(sortMode: mode, updatedAt: DateTime.now().toUtc());
  }

  WorkspaceFileExplorerState copyWith({
    String? workspaceId,
    List<String>? expandedPaths,
    String? selectedPath,
    String? revealedPath,
    WorkspaceFileExplorerSortMode? sortMode,
    DateTime? updatedAt,
  }) {
    return WorkspaceFileExplorerState(
      workspaceId: workspaceId ?? this.workspaceId,
      expandedPaths: expandedPaths == null
          ? this.expandedPaths
          : _sortedPaths(expandedPaths),
      selectedPath: selectedPath ?? this.selectedPath,
      revealedPath: revealedPath ?? this.revealedPath,
      sortMode: sortMode ?? this.sortMode,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'expandedPaths': expandedPaths,
      'selectedPath': selectedPath,
      'revealedPath': revealedPath,
      'sortMode': sortMode.wireValue,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceFileExplorerStateStore {
  WorkspaceFileExplorerStateStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.file-explorer-state',
             layer: 'workspace',
             stateFamily: 'file-explorer-state',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceFileExplorerStateStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'workspace.file-explorer-state';
  static const String _key = 'state';

  final FoundationDataStoreOwner _owner;

  Future<void> saveState(WorkspaceFileExplorerState state) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: state.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: state.workspaceId,
    );
  }

  Future<WorkspaceFileExplorerState> readState({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return WorkspaceFileExplorerState(workspaceId: workspaceId);
    }
    final state = WorkspaceFileExplorerState.fromJson(value);
    return state.workspaceId.isEmpty
        ? state.copyWith(workspaceId: workspaceId)
        : state;
  }

  Future<bool> deleteState({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchState({required String workspaceId}) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

WorkspaceFileExplorerSortMode _sortModeFromWire(Object? value) {
  return switch (value) {
    'folders-first' => WorkspaceFileExplorerSortMode.foldersFirst,
    'alphabetical' => WorkspaceFileExplorerSortMode.alphabetical,
    _ => WorkspaceFileExplorerSortMode.foldersFirst,
  };
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return _sortedPaths(value.map((item) => '$item'));
}

List<String> _sortedPaths(Iterable<String> paths) {
  final result =
      paths
          .map(_normalizePath)
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return result;
}

String _normalizePath(String path) {
  return path.trim().replaceAll('\\', '/');
}
