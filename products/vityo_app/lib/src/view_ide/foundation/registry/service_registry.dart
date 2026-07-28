enum IdeServiceScope { application, project, module }

typedef IdeServiceFactory<T extends Object> = T Function(IdeServiceContext context);
typedef IdeServiceDisposer<T extends Object> = void Function(T service);

class IdeServiceKey<T extends Object> {
  const IdeServiceKey(this.id);

  final String id;
}

class IdeServiceContext {
  const IdeServiceContext({
    required this.scope,
    this.projectId,
    this.moduleId,
  });

  final IdeServiceScope scope;
  final String? projectId;
  final String? moduleId;
}

class IdeServiceRegistration<T extends Object> {
  const IdeServiceRegistration({
    required this.key,
    required this.scope,
    required this.factory,
    this.dispose,
    this.owner = 'core',
  });

  final IdeServiceKey<T> key;
  final IdeServiceScope scope;
  final IdeServiceFactory<T> factory;
  final IdeServiceDisposer<T>? dispose;
  final String owner;
}

class IdeServiceRegistry {
  IdeServiceRegistry({required this.context});

  final IdeServiceContext context;
  final Map<String, IdeServiceRegistration<Object>> _registrations =
      <String, IdeServiceRegistration<Object>>{};
  final Map<String, Object> _instances = <String, Object>{};

  bool contains<T extends Object>(IdeServiceKey<T> key) {
    return _registrations.containsKey(key.id);
  }

  void register<T extends Object>(IdeServiceRegistration<T> registration) {
    if (_registrations.containsKey(registration.key.id)) {
      throw StateError('Service `${registration.key.id}` is already registered.');
    }
    _registrations[registration.key.id] =
        registration as IdeServiceRegistration<Object>;
  }

  T get<T extends Object>(IdeServiceKey<T> key) {
    final existing = _instances[key.id];
    if (existing != null) {
      return existing as T;
    }
    final registration = _registrations[key.id];
    if (registration == null) {
      throw StateError('Service `${key.id}` is not registered.');
    }
    _assertScopeAllowed(registration);
    final instance = registration.factory(context);
    _instances[key.id] = instance;
    return instance as T;
  }

  bool disposeService<T extends Object>(IdeServiceKey<T> key) {
    final instance = _instances.remove(key.id);
    if (instance == null) {
      return false;
    }
    final registration = _registrations[key.id] as IdeServiceRegistration<T>?;
    registration?.dispose?.call(instance as T);
    return true;
  }

  void disposeAll() {
    final keys = _instances.keys.toList(growable: false);
    for (final key in keys.reversed) {
      final registration = _registrations[key];
      final instance = _instances.remove(key);
      if (registration != null && instance != null) {
        registration.dispose?.call(instance);
      }
    }
  }

  void _assertScopeAllowed(IdeServiceRegistration<Object> registration) {
    final requested = registration.scope.index;
    final current = context.scope.index;
    if (requested > current) {
      throw StateError(
        'Service `${registration.key.id}` requires ${registration.scope.name} scope.',
      );
    }
  }
}
