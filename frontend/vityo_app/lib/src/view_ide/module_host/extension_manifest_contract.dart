import '../foundation/foundation.dart';
import 'module_manifest.dart';

enum ExtensionContributionKind {
  command,
  language,
  theme,
  debugger,
  task,
  view,
  agent,
  toolchain,
}

extension ExtensionContributionKindX on ExtensionContributionKind {
  String get wireValue => switch (this) {
    ExtensionContributionKind.command => 'command',
    ExtensionContributionKind.language => 'language',
    ExtensionContributionKind.theme => 'theme',
    ExtensionContributionKind.debugger => 'debugger',
    ExtensionContributionKind.task => 'task',
    ExtensionContributionKind.view => 'view',
    ExtensionContributionKind.agent => 'agent',
    ExtensionContributionKind.toolchain => 'toolchain',
  };
}

class ExtensionContributionPoint {
  const ExtensionContributionPoint({
    required this.kind,
    required this.id,
    required this.target,
    this.title,
    this.metadata = const <String, Object?>{},
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  factory ExtensionContributionPoint.fromJson(Map<String, Object?> json) {
    return ExtensionContributionPoint(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      kind: _contributionKindFromWire(json['kind']),
      id: json['id'] as String? ?? '',
      target: json['target'] as String? ?? '',
      title: _jsonNullableString(json['title']),
      metadata: _jsonObjectMap(json['metadata']),
      extensions: _collectUnknown(json),
    );
  }

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'kind',
    'id',
    'target',
    'title',
    'metadata',
    'valid',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }

  final int schemaVersion;
  final ExtensionContributionKind kind;
  final String id;
  final String target;
  final String? title;
  final Map<String, Object?> metadata;
  final Map<String, Object?> extensions;

  bool get valid => id.trim().isNotEmpty && target.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'kind': kind.wireValue,
      'id': id,
      'target': target,
      if (title != null) 'title': title,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'valid': valid,
      ...extensions,
    };
  }
}

class ExtensionManifest {
  const ExtensionManifest({
    required this.extensionId,
    required this.displayName,
    required this.version,
    required this.publisher,
    required this.entrypoint,
    this.moduleId,
    this.description = '',
    this.activationEvents = const <String>[],
    this.contributions = const <ExtensionContributionPoint>[],
    this.capabilities = const <String, bool>{},
    this.trustedByDefault = false,
    this.metadata = const <String, Object?>{},
    this.schemaVersion = 1,
    this.extensions = const <String, Object?>{},
  });

  factory ExtensionManifest.fromJson(Map<String, Object?> json) {
    return ExtensionManifest(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensionId: json['extensionId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      version: json['version'] as String? ?? '',
      publisher: json['publisher'] as String? ?? '',
      entrypoint: json['entrypoint'] as String? ?? '',
      moduleId: _jsonNullableString(json['moduleId']),
      description: json['description'] as String? ?? '',
      activationEvents: _jsonStringList(json['activationEvents']),
      contributions: _jsonContributionPoints(json['contributions']),
      capabilities: _jsonBoolMap(json['capabilities']),
      trustedByDefault: json['trustedByDefault'] as bool? ?? false,
      metadata: _jsonObjectMap(json['metadata']),
      extensions: _collectUnknown(json),
    );
  }

  factory ExtensionManifest.fromModuleManifest({
    required ModuleManifest module,
    required String publisher,
    List<String> activationEvents = const <String>[],
    List<ExtensionContributionPoint> contributions =
        const <ExtensionContributionPoint>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionManifest(
      extensionId: module.moduleId,
      moduleId: module.moduleId,
      displayName: module.displayName,
      version: module.version,
      publisher: publisher,
      entrypoint: module.entrypoint,
      description: module.description,
      activationEvents: activationEvents,
      contributions: contributions,
      capabilities: module.capabilityFlags,
      trustedByDefault:
          module.enabledByDefault && module.kind == ModuleKind.core,
      metadata: metadata,
    );
  }

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'extensionId',
    'displayName',
    'version',
    'publisher',
    'entrypoint',
    'moduleId',
    'description',
    'activationEvents',
    'contributions',
    'capabilities',
    'trustedByDefault',
    'metadata',
    'valid',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }

  final int schemaVersion;
  final String extensionId;
  final String displayName;
  final String version;
  final String publisher;
  final String entrypoint;
  final String? moduleId;
  final String description;
  final List<String> activationEvents;
  final List<ExtensionContributionPoint> contributions;
  final Map<String, bool> capabilities;
  final bool trustedByDefault;
  final Map<String, Object?> metadata;
  final Map<String, Object?> extensions;

  bool get valid {
    return extensionId.trim().isNotEmpty &&
        version.trim().isNotEmpty &&
        publisher.trim().isNotEmpty &&
        entrypoint.trim().isNotEmpty &&
        contributions.every((contribution) => contribution.valid);
  }

  List<ExtensionContributionPoint> contributionsFor(
    ExtensionContributionKind kind,
  ) {
    return contributions
        .where((contribution) => contribution.kind == kind)
        .toList(growable: false);
  }

  bool activatesOn(String event) => activationEvents.contains(event);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'extensionId': extensionId,
      'displayName': displayName,
      'version': version,
      'publisher': publisher,
      'entrypoint': entrypoint,
      if (moduleId != null) 'moduleId': moduleId,
      'description': description,
      'activationEvents': activationEvents,
      'contributions': contributions
          .map((contribution) => contribution.toJson())
          .toList(growable: false),
      'capabilities': capabilities,
      'trustedByDefault': trustedByDefault,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'valid': valid,
      ...extensions,
    };
  }
}

class ExtensionManifestRegistry {
  ExtensionManifestRegistry([
    Iterable<ExtensionManifest> manifests = const <ExtensionManifest>[],
  ])  : schemaVersion = 1,
        extensions = const <String, Object?>{},
        _manifests = <String, ExtensionManifest>{} {
    for (final manifest in manifests) {
      register(manifest);
    }
  }

  factory ExtensionManifestRegistry.fromJson(Map<String, Object?> json) {
    final registry = ExtensionManifestRegistry._blank(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
    );
    for (final manifest in _jsonExtensionManifests(json['manifests'])) {
      registry.register(manifest);
    }
    return registry;
  }

  ExtensionManifestRegistry._blank({
    required this.schemaVersion,
    required this.extensions,
  }) : _manifests = <String, ExtensionManifest>{};

  static const Set<String> _knownKeys = <String>{
    'schemaVersion',
    'manifests',
    'extensionCount',
    'validExtensionCount',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return {
      for (final e in json.entries)
        if (!_knownKeys.contains(e.key)) e.key: e.value,
    };
  }

  final int schemaVersion;
  final Map<String, Object?> extensions;

  final Map<String, ExtensionManifest> _manifests;

  void register(ExtensionManifest manifest) {
    if (!manifest.valid) {
      throw StateError(
        'Extension ${manifest.extensionId} manifest is invalid.',
      );
    }
    if (_manifests.containsKey(manifest.extensionId)) {
      throw StateError(
        'Extension ${manifest.extensionId} is already registered.',
      );
    }
    _manifests[manifest.extensionId] = manifest;
  }

  bool unregister(String extensionId) {
    return _manifests.remove(extensionId) != null;
  }

  ExtensionManifest? lookup(String extensionId) => _manifests[extensionId];

  List<ExtensionManifest> list() {
    final manifests = _manifests.values.toList(growable: false);
    manifests.sort(
      (left, right) => left.extensionId.compareTo(right.extensionId),
    );
    return manifests;
  }

  List<ExtensionManifest> activationCandidates(String event) {
    return list()
        .where((manifest) => manifest.activatesOn(event))
        .toList(growable: false);
  }

  List<ExtensionContributionPoint> contributionsFor(
    ExtensionContributionKind kind,
  ) {
    return list()
        .expand((manifest) => manifest.contributionsFor(kind))
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    final manifests = list();
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'extensionCount': manifests.length,
      'validExtensionCount': manifests
          .where((manifest) => manifest.valid)
          .length,
      'manifests': manifests
          .map((manifest) => manifest.toJson())
          .toList(growable: false),
      ...extensions,
    };
  }
}

class ExtensionActivationPlan {
  const ExtensionActivationPlan({
    required this.event,
    required this.candidates,
    required this.activatableExtensionIds,
    required this.blockedExtensionIds,
  });

  factory ExtensionActivationPlan.fromRegistry({
    required ExtensionManifestRegistry registry,
    required String event,
    Iterable<String> enabledExtensionIds = const <String>[],
    Iterable<String> trustedExtensionIds = const <String>[],
  }) {
    final enabled = enabledExtensionIds.toSet();
    final trusted = trustedExtensionIds.toSet();
    final candidates = registry.activationCandidates(event);
    final activatableIds = <String>[];
    final blockedIds = <String>[];
    for (final candidate in candidates) {
      final enabledForActivation =
          enabled.isEmpty || enabled.contains(candidate.extensionId);
      final trustedForActivation =
          candidate.trustedByDefault || trusted.contains(candidate.extensionId);
      if (enabledForActivation && trustedForActivation) {
        activatableIds.add(candidate.extensionId);
      } else {
        blockedIds.add(candidate.extensionId);
      }
    }
    return ExtensionActivationPlan(
      event: event,
      candidates: List<ExtensionManifest>.unmodifiable(candidates),
      activatableExtensionIds: List<String>.unmodifiable(activatableIds),
      blockedExtensionIds: List<String>.unmodifiable(blockedIds),
    );
  }

  final String event;
  final List<ExtensionManifest> candidates;
  final List<String> activatableExtensionIds;
  final List<String> blockedExtensionIds;

  bool get canActivate => activatableExtensionIds.isNotEmpty;
  int get candidateCount => candidates.length;
  int get blockedCount => blockedExtensionIds.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'event': event,
      'candidateCount': candidateCount,
      'activatableExtensionIds': activatableExtensionIds,
      'blockedExtensionIds': blockedExtensionIds,
      'blockedCount': blockedCount,
      'canActivate': canActivate,
    };
  }
}

class ExtensionManifestRegistryStore {
  ExtensionManifestRegistryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'extension.manifest-registry',
             layer: 'extension',
             stateFamily: 'extension-manifest',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const ExtensionManifestRegistryStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'extension.manifest-registry';
  static const String _key = 'manifests';

  final FoundationDataStoreOwner _owner;

  Future<void> saveRegistry({
    required String workspaceId,
    required ExtensionManifestRegistry registry,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: registry.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<ExtensionManifestRegistry> readRegistry({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    return value == null
        ? ExtensionManifestRegistry()
        : ExtensionManifestRegistry.fromJson(value);
  }

  Future<bool> deleteRegistry({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchRegistry({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

ExtensionContributionKind _contributionKindFromWire(Object? value) {
  return switch (value) {
    'command' => ExtensionContributionKind.command,
    'language' => ExtensionContributionKind.language,
    'theme' => ExtensionContributionKind.theme,
    'debugger' => ExtensionContributionKind.debugger,
    'task' => ExtensionContributionKind.task,
    'view' => ExtensionContributionKind.view,
    'agent' => ExtensionContributionKind.agent,
    'toolchain' => ExtensionContributionKind.toolchain,
    _ => ExtensionContributionKind.view,
  };
}

String? _jsonNullableString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, bool> _jsonBoolMap(Object? value) {
  if (value is! Map) {
    return const <String, bool>{};
  }
  return Map<String, bool>.unmodifiable(
    value.map(
      (key, value) => MapEntry<String, bool>(key.toString(), value == true),
    ),
  );
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}

List<ExtensionContributionPoint> _jsonContributionPoints(Object? value) {
  if (value is! List) {
    return const <ExtensionContributionPoint>[];
  }
  return value
      .whereType<Map>()
      .map(
        (contribution) => ExtensionContributionPoint.fromJson(
          contribution.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

List<ExtensionManifest> _jsonExtensionManifests(Object? value) {
  if (value is! List) {
    return const <ExtensionManifest>[];
  }
  return value
      .whereType<Map>()
      .map(
        (manifest) => ExtensionManifest.fromJson(
          manifest.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .where((manifest) => manifest.valid)
      .toList(growable: false);
}
