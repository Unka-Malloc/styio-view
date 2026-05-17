enum FoundationLifecycleState {
  registered,
  initializing,
  ready,
  reloading,
  stopped,
  disposed,
}

typedef FoundationLifecycleAction = Future<void> Function();

class FoundationLifecycleComponent {
  const FoundationLifecycleComponent({
    required this.id,
    this.onInitialize,
    this.onReload,
    this.onStop,
    this.onDispose,
  });

  final String id;
  final FoundationLifecycleAction? onInitialize;
  final FoundationLifecycleAction? onReload;
  final FoundationLifecycleAction? onStop;
  final FoundationLifecycleAction? onDispose;
}

class FoundationLifecycleCoordinator {
  final Map<String, FoundationLifecycleComponent> _components =
      <String, FoundationLifecycleComponent>{};
  final Map<String, FoundationLifecycleState> _states =
      <String, FoundationLifecycleState>{};

  void register(FoundationLifecycleComponent component) {
    if (_components.containsKey(component.id)) {
      throw StateError('Lifecycle component ${component.id} is registered.');
    }
    _components[component.id] = component;
    _states[component.id] = FoundationLifecycleState.registered;
  }

  bool unregister(String id) {
    _states.remove(id);
    return _components.remove(id) != null;
  }

  FoundationLifecycleState stateOf(String id) {
    final state = _states[id];
    if (state == null) {
      throw StateError('Lifecycle component $id is not registered.');
    }
    return state;
  }

  Future<void> initializeAll() async {
    for (final component in _components.values) {
      _states[component.id] = FoundationLifecycleState.initializing;
      await component.onInitialize?.call();
      _states[component.id] = FoundationLifecycleState.ready;
    }
  }

  Future<void> reloadAll() async {
    for (final component in _components.values) {
      _ensureRegistered(component.id);
      _states[component.id] = FoundationLifecycleState.reloading;
      await component.onReload?.call();
      _states[component.id] = FoundationLifecycleState.ready;
    }
  }

  Future<void> stopAll() async {
    for (final component in _components.values.toList().reversed) {
      _ensureRegistered(component.id);
      await component.onStop?.call();
      _states[component.id] = FoundationLifecycleState.stopped;
    }
  }

  Future<void> disposeAll() async {
    for (final component in _components.values.toList().reversed) {
      _ensureRegistered(component.id);
      await component.onDispose?.call();
      _states[component.id] = FoundationLifecycleState.disposed;
    }
  }

  void _ensureRegistered(String id) {
    if (!_components.containsKey(id)) {
      throw StateError('Lifecycle component $id is not registered.');
    }
  }
}
