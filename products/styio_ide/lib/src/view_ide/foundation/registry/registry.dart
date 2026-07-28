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

class DisposableRegistration {
  DisposableRegistration({
    required this.id,
    required this.kind,
    required this.owner,
    required this.scopeId,
    required bool Function() onDispose,
  }) : _onDispose = onDispose;

  final String id;
  final String kind;
  final String owner;
  final String scopeId;
  final bool Function() _onDispose;
  bool _disposed = false;

  bool get disposed => _disposed;

  bool dispose() {
    if (_disposed) {
      return false;
    }
    _disposed = true;
    return _onDispose();
  }
}

class RegistryScope {
  RegistryScope({required this.id, required this.owner});

  final String id;
  final String owner;
  final List<DisposableRegistration> _registrations =
      <DisposableRegistration>[];
  bool _disposed = false;

  bool get disposed => _disposed;

  DisposableRegistration register<T>({
    required FoundationRegistry<T> registry,
    required ContributionDescriptor<T> contribution,
  }) {
    if (_disposed) {
      throw StateError('Registry scope $id is already disposed.');
    }
    final registration = registry.registerContribution(
      contribution,
      scopeId: id,
    );
    _registrations.add(registration);
    return registration;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    for (final registration in _registrations.reversed) {
      registration.dispose();
    }
    _registrations.clear();
  }
}

class ContributionDescriptor<T> {
  const ContributionDescriptor({
    required this.id,
    required this.kind,
    required this.owner,
    required this.value,
    this.state = FoundationRegistryEntryState.registered,
    this.order = 0,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String kind;
  final String owner;
  final T value;
  final FoundationRegistryEntryState state;
  final int order;
  final Map<String, Object?> metadata;

  FoundationRegistryEntry<T> toRegistryEntry() {
    return FoundationRegistryEntry<T>(
      id: id,
      kind: kind,
      owner: owner,
      value: value,
      state: state,
      metadata: Map<String, Object?>.unmodifiable(<String, Object?>{
        ...metadata,
        'order': order,
      }),
    );
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

  DisposableRegistration registerContribution({
    required String id,
    required T value,
    required String scopeId,
    FoundationRegistryEntryState state =
        FoundationRegistryEntryState.registered,
    int order = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _registry.registerContribution(
      ContributionDescriptor<T>(
        id: id,
        kind: kind,
        owner: owner,
        value: value,
        state: state,
        order: order,
        metadata: metadata,
      ),
      scopeId: scopeId,
    );
  }

  DisposableRegistration registerScoped({
    required String id,
    required T value,
    required String scopeId,
    FoundationRegistryEntryState state =
        FoundationRegistryEntryState.registered,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _registry.registerScoped(
      FoundationRegistryEntry<T>(
        id: id,
        kind: kind,
        owner: owner,
        value: value,
        state: state,
        metadata: metadata,
      ),
      scopeId: scopeId,
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

class _FoundationRegistryRecord<T> {
  const _FoundationRegistryRecord({
    required this.entry,
    required this.scopeId,
    required this.sequence,
  });

  final FoundationRegistryEntry<T> entry;
  final String scopeId;
  final int sequence;

  _FoundationRegistryRecord<T> copyWith({FoundationRegistryEntry<T>? entry}) {
    return _FoundationRegistryRecord<T>(
      entry: entry ?? this.entry,
      scopeId: scopeId,
      sequence: sequence,
    );
  }
}

class FoundationRegistry<T> {
  final Map<String, List<_FoundationRegistryRecord<T>>> _recordsById =
      <String, List<_FoundationRegistryRecord<T>>>{};
  int _sequence = 0;

  void register(FoundationRegistryEntry<T> entry) {
    _validateEntry(entry);
    if (contains(entry.id)) {
      throw StateError('Registry entry ${entry.id} is already registered.');
    }
    _pushRecord(entry, scopeId: '');
  }

  DisposableRegistration registerContribution(
    ContributionDescriptor<T> contribution, {
    required String scopeId,
  }) {
    final entry = contribution.toRegistryEntry();
    _validateEntry(entry);
    final record = _pushRecord(entry, scopeId: scopeId);
    return DisposableRegistration(
      id: entry.id,
      kind: entry.kind,
      owner: entry.owner,
      scopeId: scopeId,
      onDispose: () => _removeRecord(entry.id, record.sequence),
    );
  }

  DisposableRegistration registerScoped(
    FoundationRegistryEntry<T> entry, {
    required String scopeId,
  }) {
    _validateEntry(entry);
    final record = _pushRecord(entry, scopeId: scopeId);
    return DisposableRegistration(
      id: entry.id,
      kind: entry.kind,
      owner: entry.owner,
      scopeId: scopeId,
      onDispose: () => _removeRecord(entry.id, record.sequence),
    );
  }

  bool unregister(String id) {
    final records = _recordsById[id];
    if (records == null || records.isEmpty) {
      return false;
    }
    records.removeLast();
    if (records.isEmpty) {
      _recordsById.remove(id);
    }
    return true;
  }

  bool contains(String id) {
    final records = _recordsById[id];
    return records != null && records.isNotEmpty;
  }

  FoundationRegistryEntry<T>? lookup(String id) {
    final records = _recordsById[id];
    if (records == null || records.isEmpty) {
      return null;
    }
    return records.last.entry;
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
    final entries = _activeEntries
        .where((entry) {
          return (kind == null || entry.kind == kind) &&
              (owner == null || entry.owner == owner) &&
              (state == null || entry.state == state);
        })
        .toList(growable: false);
    entries.sort((left, right) {
      final orderCompare = _order(left).compareTo(_order(right));
      if (orderCompare != 0) {
        return orderCompare;
      }
      return left.id.compareTo(right.id);
    });
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
    _replaceActiveRecord(id, entry.copyWith(state: state));
  }

  void updateMetadata(
    String id,
    Map<String, Object?> metadata, {
    bool merge = true,
  }) {
    final entry = requireEntry(id);
    _replaceActiveRecord(
      id,
      entry.copyWith(
        metadata: Map<String, Object?>.unmodifiable(
          merge ? <String, Object?>{...entry.metadata, ...metadata} : metadata,
        ),
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

  Iterable<FoundationRegistryEntry<T>> get _activeEntries sync* {
    for (final records in _recordsById.values) {
      if (records.isNotEmpty) {
        yield records.last.entry;
      }
    }
  }

  _FoundationRegistryRecord<T> _pushRecord(
    FoundationRegistryEntry<T> entry, {
    required String scopeId,
  }) {
    final record = _FoundationRegistryRecord<T>(
      entry: entry.copyWith(
        metadata: Map<String, Object?>.unmodifiable(entry.metadata),
      ),
      scopeId: scopeId,
      sequence: _sequence++,
    );
    _recordsById.putIfAbsent(entry.id, () => <_FoundationRegistryRecord<T>>[]);
    _recordsById[entry.id]!.add(record);
    return record;
  }

  bool _removeRecord(String id, int sequence) {
    final records = _recordsById[id];
    if (records == null) {
      return false;
    }
    final originalLength = records.length;
    records.removeWhere((record) => record.sequence == sequence);
    if (records.isEmpty) {
      _recordsById.remove(id);
    }
    return records.length != originalLength;
  }

  void _replaceActiveRecord(String id, FoundationRegistryEntry<T> entry) {
    final records = _recordsById[id];
    if (records == null || records.isEmpty) {
      throw StateError('Registry entry $id is not registered.');
    }
    records[records.length - 1] = records.last.copyWith(entry: entry);
  }
}

int _order<T>(FoundationRegistryEntry<T> entry) {
  final order = entry.metadata['order'];
  return order is int ? order : 0;
}

// ---------------------------------------------------------------------------
// Foundation Registry Lifecycle State -- every concrete registry instance
// must emit a manifest projection without runtime values and have
// lifecycle-state tests.
// ---------------------------------------------------------------------------

/// Lifecycle state of a foundation registry instance.
enum FoundationRegistryLifecycleState {
  created,
  warming,
  ready,
  reloading,
  stopped,
  disposed,
}

class FoundationRegistryValidator {
  const FoundationRegistryValidator();

  /// Validates that every registered entry in [registry] can produce a valid
  /// manifest entry (no runtime values). Returns diagnostic messages for any
  /// entry that fails the projection check.
  List<String> validateManifestProjection<T>(
    FoundationRegistry<T> registry,
  ) {
    final diagnostics = <String>[];
    final manifest = registry.manifest();
    for (final entry in manifest.entries) {
      final json = entry.toJson();
      if (json['id'] == null || (json['id'] as String).trim().isEmpty) {
        diagnostics.add('Manifest entry missing id: $json');
      }
      if (json['kind'] == null || (json['kind'] as String).trim().isEmpty) {
        diagnostics.add('Manifest entry ${json['id']} missing kind.');
      }
      if (json['owner'] == null || (json['owner'] as String).trim().isEmpty) {
        diagnostics.add('Manifest entry ${json['id']} missing owner.');
      }
      if (json['state'] == null) {
        diagnostics.add('Manifest entry ${json['id']} missing state.');
      }
    }
    return diagnostics;
  }
}
