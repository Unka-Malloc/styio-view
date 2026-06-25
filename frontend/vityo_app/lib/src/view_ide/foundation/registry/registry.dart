import '../datastore/datastore.dart';
import '../resource_coordinator/resource_coordinator.dart';
export 'service_registry.dart';

enum FoundationRegistryEntryState { registered, active, disabled }

enum FoundationRegistrationCategory {
  schema,
  provider,
  command,
  capability,
  renderer,
  policy,
}

extension FoundationRegistrationCategoryWire on FoundationRegistrationCategory {
  String get wireValue {
    return switch (this) {
      FoundationRegistrationCategory.schema => 'schema',
      FoundationRegistrationCategory.provider => 'provider',
      FoundationRegistrationCategory.command => 'command',
      FoundationRegistrationCategory.capability => 'capability',
      FoundationRegistrationCategory.renderer => 'renderer',
      FoundationRegistrationCategory.policy => 'policy',
    };
  }
}

class FoundationRegistryEntry<T> {
  const FoundationRegistryEntry({
    required this.id,
    required this.kind,
    required this.owner,
    required this.value,
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String kind;
  final String owner;
  final T value;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;

  FoundationRegistryEntry<T> copyWith({
    FoundationRegistryEntryState? state,
    Map<String, Object?>? metadata,
  }) {
    return FoundationRegistryEntry<T>(
      id: id,
      kind: kind,
      owner: owner,
      value: value,
      state: state ?? this.state,
      metadata: metadata ?? this.metadata,
    );
  }

  FoundationRegistryManifestEntry toManifestEntry() {
    return FoundationRegistryManifestEntry(
      id: id,
      kind: kind,
      owner: owner,
      state: state,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }
}

class FoundationRegistryManifestEntry {
  const FoundationRegistryManifestEntry({
    required this.id,
    required this.kind,
    required this.owner,
    required this.state,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String kind;
  final String owner;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'owner': owner,
      'state': state.name,
      'metadata': metadata,
    };
  }

  factory FoundationRegistryManifestEntry.fromJson(Map<String, Object?> json) {
    final metadata = json['metadata'];
    return FoundationRegistryManifestEntry(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      owner: json['owner'] as String? ?? '',
      state: FoundationRegistryEntryState.values.firstWhere(
        (state) => state.name == json['state'],
        orElse: () => FoundationRegistryEntryState.registered,
      ),
      metadata: metadata is Map<String, Object?>
          ? Map<String, Object?>.unmodifiable(metadata)
          : metadata is Map
          ? Map<String, Object?>.unmodifiable(
              metadata.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const <String, Object?>{},
    );
  }
}

class FoundationRegistryManifest {
  const FoundationRegistryManifest({required this.entries});

  final List<FoundationRegistryManifestEntry> entries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  factory FoundationRegistryManifest.fromJson(Map<String, Object?> json) {
    final entries = json['entries'];
    return FoundationRegistryManifest(
      entries: entries is Iterable
          ? entries
                .whereType<Map>()
                .map(
                  (entry) => FoundationRegistryManifestEntry.fromJson(
                    entry.map(
                      (key, value) =>
                          MapEntry<String, Object?>(key.toString(), value),
                    ),
                  ),
                )
                .toList(growable: false)
          : const <FoundationRegistryManifestEntry>[],
    );
  }
}

class FoundationRegistryManifestStore {
  const FoundationRegistryManifestStore({
    required FoundationDataStoreOwner owner,
    this.namespaceName = 'foundation.registry.manifests',
    this.schemaVersion = 1,
  }) : _owner = owner;

  final FoundationDataStoreOwner _owner;
  final String namespaceName;
  final int schemaVersion;

  Future<void> writeManifest({
    required String key,
    required FoundationRegistryManifest manifest,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _owner.writeJson(
      namespaceName: namespaceName,
      key: key,
      value: manifest.toJson(),
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
    );
  }

  Future<FoundationRegistryManifest?> readManifest({
    required String key,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) async {
    final json = await _owner.readJson(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
    );
    return json == null ? null : FoundationRegistryManifest.fromJson(json);
  }

  Future<bool> deleteManifest({
    required String key,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _owner.delete(
      namespaceName: namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
    );
  }
}

class FoundationProviderRegistration<T> {
  const FoundationProviderRegistration({
    required this.id,
    required this.owner,
    required this.provider,
    this.layer = '',
    this.priority = 0,
    this.capabilities = const <String>[],
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final String owner;
  final T provider;
  final String layer;
  final int priority;
  final List<String> capabilities;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;
  final String todo;

  FoundationRegistryEntry<T> toRegistryEntry() {
    return FoundationRegistryEntry<T>(
      id: id,
      kind: FoundationRegistrationCategory.provider.wireValue,
      owner: owner,
      value: provider,
      state: state,
      metadata: Map<String, Object?>.unmodifiable(<String, Object?>{
        ...metadata,
        if (layer.isNotEmpty) 'layer': layer,
        'priority': priority,
        if (capabilities.isNotEmpty)
          'capabilities': List<String>.unmodifiable(capabilities),
        if (todo.isNotEmpty) 'todo': todo,
      }),
    );
  }
}

class FoundationProviderRegistry<T> {
  FoundationProviderRegistry({FoundationRegistry<T>? registry})
    : _registry = registry ?? FoundationRegistry<T>();

  final FoundationRegistry<T> _registry;

  void register(FoundationProviderRegistration<T> registration) {
    _registry.register(registration.toRegistryEntry());
  }

  bool unregister(String id) {
    return _registry.unregister(id);
  }

  FoundationRegistryEntry<T>? lookup(String id) {
    final entry = _registry.lookup(id);
    if (entry == null ||
        entry.kind != FoundationRegistrationCategory.provider.wireValue) {
      return null;
    }
    return entry;
  }

  FoundationRegistryEntry<T> requireProvider(String id) {
    final entry = lookup(id);
    if (entry == null) {
      throw StateError('Provider $id is not registered.');
    }
    return entry;
  }

  List<FoundationRegistryEntry<T>> list({
    String? owner,
    FoundationRegistryEntryState? state,
  }) {
    return _sortByPriority(
      _registry.list(
        kind: FoundationRegistrationCategory.provider.wireValue,
        owner: owner,
        state: state,
      ),
    );
  }

  List<FoundationRegistryEntry<T>> providersForCapability(
    String capability, {
    String? owner,
    FoundationRegistryEntryState? state,
  }) {
    return _sortByPriority(
      list(owner: owner, state: state)
          .where((entry) => _capabilities(entry).contains(capability))
          .toList(growable: false),
    );
  }

  FoundationRegistryEntry<T>? resolve({
    required String capability,
    String? owner,
    bool activeOnly = true,
  }) {
    final state = activeOnly ? FoundationRegistryEntryState.active : null;
    final candidates = providersForCapability(
      capability,
      owner: owner,
      state: state,
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  FoundationRegistryManifest manifest({
    String? owner,
    FoundationRegistryEntryState? state,
  }) {
    return _registry.manifest(
      kind: FoundationRegistrationCategory.provider.wireValue,
      owner: owner,
      state: state,
    );
  }

  void setState(String id, FoundationRegistryEntryState state) {
    requireProvider(id);
    _registry.setState(id, state);
  }
}

List<FoundationRegistryEntry<T>> _sortByPriority<T>(
  List<FoundationRegistryEntry<T>> entries,
) {
  final sorted = entries.toList(growable: false);
  sorted.sort((left, right) {
    final priorityOrder = _priority(right).compareTo(_priority(left));
    if (priorityOrder != 0) {
      return priorityOrder;
    }
    return left.id.compareTo(right.id);
  });
  return sorted;
}

int _priority<T>(FoundationRegistryEntry<T> entry) {
  final priority = entry.metadata['priority'];
  return priority is int ? priority : 0;
}

Set<String> _capabilities<T>(FoundationRegistryEntry<T> entry) {
  final capabilities = entry.metadata['capabilities'];
  if (capabilities is Iterable) {
    return capabilities.map((capability) => capability.toString()).toSet();
  }
  return const <String>{};
}

class FoundationRegistryRegistrar<T> {
  const FoundationRegistryRegistrar({
    required FoundationRegistry<T> registry,
    required this.owner,
    required this.category,
  }) : _registry = registry;

  final FoundationRegistry<T> _registry;
  final String owner;
  final FoundationRegistrationCategory category;

  String get kind => category.wireValue;

  void register({
    required String id,
    required T value,
    FoundationRegistryEntryState state =
        FoundationRegistryEntryState.registered,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _registry.register(
      FoundationRegistryEntry<T>(
        id: id,
        kind: kind,
        owner: owner,
        value: value,
        state: state,
        metadata: metadata,
      ),
    );
  }

  bool unregister(String id) {
    return _registry.unregister(id);
  }

  FoundationRegistryEntry<T>? lookup(String id) {
    final entry = _registry.lookup(id);
    if (entry == null || entry.kind != kind || entry.owner != owner) {
      return null;
    }
    return entry;
  }

  FoundationRegistryEntry<T> requireEntry(String id) {
    final entry = lookup(id);
    if (entry == null) {
      throw StateError(
        'Registry entry $id is not registered for $owner/$kind.',
      );
    }
    return entry;
  }

  List<FoundationRegistryEntry<T>> list({FoundationRegistryEntryState? state}) {
    return _registry.list(kind: kind, owner: owner, state: state);
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(kind: kind, owner: owner, state: state);
  }

  void setState(String id, FoundationRegistryEntryState state) {
    requireEntry(id);
    _registry.setState(id, state);
  }

  void updateMetadata(
    String id,
    Map<String, Object?> metadata, {
    bool merge = true,
  }) {
    requireEntry(id);
    _registry.updateMetadata(id, metadata, merge: merge);
  }
}

class FoundationRegistry<T> {
  final Map<String, FoundationRegistryEntry<T>> _entries =
      <String, FoundationRegistryEntry<T>>{};

  void register(FoundationRegistryEntry<T> entry) {
    _validateEntry(entry);
    if (_entries.containsKey(entry.id)) {
      throw StateError('Registry entry ${entry.id} is already registered.');
    }
    _entries[entry.id] = entry.copyWith(
      metadata: Map<String, Object?>.unmodifiable(entry.metadata),
    );
  }

  bool unregister(String id) {
    return _entries.remove(id) != null;
  }

  bool contains(String id) {
    return _entries.containsKey(id);
  }

  FoundationRegistryEntry<T>? lookup(String id) {
    return _entries[id];
  }

  FoundationRegistryEntry<T> requireEntry(String id) {
    final entry = lookup(id);
    if (entry == null) {
      throw StateError('Registry entry $id is not registered.');
    }
    return entry;
  }

  List<FoundationRegistryEntry<T>> list({
    String? kind,
    String? owner,
    FoundationRegistryEntryState? state,
  }) {
    final entries = _entries.values
        .where((entry) {
          return (kind == null || entry.kind == kind) &&
              (owner == null || entry.owner == owner) &&
              (state == null || entry.state == state);
        })
        .toList(growable: false);
    entries.sort((left, right) => left.id.compareTo(right.id));
    return entries;
  }

  FoundationRegistryManifest manifest({
    String? kind,
    String? owner,
    FoundationRegistryEntryState? state,
  }) {
    return FoundationRegistryManifest(
      entries: list(
        kind: kind,
        owner: owner,
        state: state,
      ).map((entry) => entry.toManifestEntry()).toList(growable: false),
    );
  }

  void setState(String id, FoundationRegistryEntryState state) {
    final entry = requireEntry(id);
    _entries[id] = entry.copyWith(state: state);
  }

  void updateMetadata(
    String id,
    Map<String, Object?> metadata, {
    bool merge = true,
  }) {
    final entry = requireEntry(id);
    _entries[id] = entry.copyWith(
      metadata: Map<String, Object?>.unmodifiable(
        merge ? <String, Object?>{...entry.metadata, ...metadata} : metadata,
      ),
    );
  }

  List<String> kinds({String? owner}) {
    final values = list(
      owner: owner,
    ).map((entry) => entry.kind).toSet().toList();
    values.sort();
    return values;
  }

  List<String> owners({String? kind}) {
    final values = list(
      kind: kind,
    ).map((entry) => entry.owner).toSet().toList();
    values.sort();
    return values;
  }

  void _validateEntry(FoundationRegistryEntry<T> entry) {
    _validateSegment('id', entry.id);
    _validateSegment('kind', entry.kind);
    _validateSegment('owner', entry.owner);
  }

  void _validateSegment(String field, String value) {
    if (value.trim().isEmpty) {
      throw ArgumentError.value(
        value,
        field,
        'Registry entry $field is empty.',
      );
    }
  }
}
