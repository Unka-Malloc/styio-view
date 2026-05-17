import '../resource_coordinator/resource_coordinator.dart';

enum FoundationWorkspaceState {
  closed,
  opening,
  open,
  reloading,
  disposed,
}

class FoundationWorkspaceScope {
  const FoundationWorkspaceScope({
    required this.workspaceId,
    required this.rootPath,
    this.displayName,
    this.remoteTargetId,
  });

  final String workspaceId;
  final String rootPath;
  final String? displayName;
  final String? remoteTargetId;

  bool get isRemote => remoteTargetId != null;
}

class FoundationWorkspace {
  FoundationWorkspace({
    required this.scope,
    required FoundationResourceCoordinator resourceCoordinator,
  }) : _resourceCoordinator = resourceCoordinator;

  final FoundationWorkspaceScope scope;
  final FoundationResourceCoordinator _resourceCoordinator;
  FoundationWorkspaceState _state = FoundationWorkspaceState.closed;

  FoundationWorkspaceState get state => _state;

  void open() {
    if (_state == FoundationWorkspaceState.disposed) {
      throw StateError('Workspace ${scope.workspaceId} has been disposed.');
    }
    _state = FoundationWorkspaceState.open;
  }

  void reload() {
    if (_state != FoundationWorkspaceState.open) {
      throw StateError('Workspace ${scope.workspaceId} is not open.');
    }
    _state = FoundationWorkspaceState.reloading;
    _state = FoundationWorkspaceState.open;
  }

  void close() {
    if (_state != FoundationWorkspaceState.disposed) {
      _state = FoundationWorkspaceState.closed;
    }
  }

  void dispose() {
    _state = FoundationWorkspaceState.disposed;
  }

  FoundationResourceLocation workspaceCacheLocation(String namespace) {
    return _resourceCoordinator.location(
      kind: FoundationResourceKind.workspaceCache,
      namespace: namespace,
      scope: FoundationResourceScope.workspace,
      workspaceId: scope.workspaceId,
    );
  }
}

class FoundationWorkspaceServiceContainer {
  final Map<String, Object> _services = <String, Object>{};

  void register<T extends Object>(String key, T service) {
    if (_services.containsKey(key)) {
      throw StateError('Workspace service $key is already registered.');
    }
    _services[key] = service;
  }

  T lookup<T extends Object>(String key) {
    final service = _services[key];
    if (service is! T) {
      throw StateError('Workspace service $key is not registered as $T.');
    }
    return service;
  }

  bool unregister(String key) {
    return _services.remove(key) != null;
  }
}
