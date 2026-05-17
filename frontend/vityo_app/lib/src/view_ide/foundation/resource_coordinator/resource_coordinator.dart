import '../../environment/system_compatibility/file_system/file_system_manager.dart';
import '../../environment/system_compatibility/resource/resource_manager.dart';

enum FoundationResourceKind {
  appData,
  cache,
  state,
  log,
  temp,
  runtime,
  workspaceCache,
}

enum FoundationResourceScope {
  user,
  workspace,
  session,
}

extension FoundationResourceKindX on FoundationResourceKind {
  String get directoryName => switch (this) {
    FoundationResourceKind.appData => 'data',
    FoundationResourceKind.cache => 'cache',
    FoundationResourceKind.state => 'state',
    FoundationResourceKind.log => 'logs',
    FoundationResourceKind.temp => 'temp',
    FoundationResourceKind.runtime => 'runtime',
    FoundationResourceKind.workspaceCache => 'workspace-cache',
  };
}

class FoundationResourceLocation {
  const FoundationResourceLocation({
    required this.kind,
    required this.scope,
    required this.namespace,
    required this.path,
    required this.cleanupAllowed,
  });

  final FoundationResourceKind kind;
  final FoundationResourceScope scope;
  final String namespace;
  final String path;
  final bool cleanupAllowed;
}

class FoundationResourceBudget {
  const FoundationResourceBudget({
    required this.namespace,
    required this.processorCount,
    this.softLimitBytes,
    this.hardLimitBytes,
  });

  final String namespace;
  final int processorCount;
  final int? softLimitBytes;
  final int? hardLimitBytes;
}

class FoundationResourceCoordinator {
  const FoundationResourceCoordinator({
    required ResourceManager resourceManager,
    required FileSystemManager fileSystemManager,
    String productDirectoryName = 'vityo',
  }) : _resourceManager = resourceManager,
       _fileSystemManager = fileSystemManager,
       _productDirectoryName = productDirectoryName;

  final ResourceManager _resourceManager;
  final FileSystemManager _fileSystemManager;
  final String _productDirectoryName;

  FoundationResourceLocation location({
    required FoundationResourceKind kind,
    required String namespace,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    final snapshot = _resourceManager.snapshot();
    final root = _rootFor(kind, snapshot);
    final scopedSegments = <String>[
      root,
      _productDirectoryName,
      kind.directoryName,
      if (scope == FoundationResourceScope.workspace) 'workspace',
      if (scope == FoundationResourceScope.workspace && workspaceId != null)
        _sanitize(workspaceId),
      if (scope == FoundationResourceScope.session) 'session',
      _sanitize(namespace),
    ];
    return FoundationResourceLocation(
      kind: kind,
      scope: scope,
      namespace: namespace,
      path: _fileSystemManager.joinPath(scopedSegments),
      cleanupAllowed: _cleanupAllowed(kind),
    );
  }

  FoundationResourceBudget budgetFor(String namespace) {
    final snapshot = _resourceManager.snapshot();
    return FoundationResourceBudget(
      namespace: namespace,
      processorCount: snapshot.processorCount,
    );
  }

  String _rootFor(FoundationResourceKind kind, ResourceSnapshot snapshot) {
    final home = snapshot.homePath;
    switch (kind) {
      case FoundationResourceKind.appData:
        return home == null
            ? snapshot.systemTempPath
            : _fileSystemManager.joinPath(<String>[home, '.local', 'share']);
      case FoundationResourceKind.cache:
      case FoundationResourceKind.workspaceCache:
        return home == null
            ? snapshot.systemTempPath
            : _fileSystemManager.joinPath(<String>[home, '.cache']);
      case FoundationResourceKind.state:
      case FoundationResourceKind.log:
        return home == null
            ? snapshot.systemTempPath
            : _fileSystemManager.joinPath(<String>[home, '.local', 'state']);
      case FoundationResourceKind.temp:
        return snapshot.systemTempPath;
      case FoundationResourceKind.runtime:
        return snapshot.systemTempPath;
    }
  }

  bool _cleanupAllowed(FoundationResourceKind kind) {
    return switch (kind) {
      FoundationResourceKind.cache ||
      FoundationResourceKind.temp ||
      FoundationResourceKind.workspaceCache => true,
      _ => false,
    };
  }

  String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }
}
