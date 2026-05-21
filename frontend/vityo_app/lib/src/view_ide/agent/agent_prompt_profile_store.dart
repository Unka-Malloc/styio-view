import '../foundation/foundation.dart';
import 'agent_profile.dart';

class AgentPromptProfileManifestEntry {
  const AgentPromptProfileManifestEntry({
    required this.key,
    required this.profileId,
    required this.displayName,
    required this.route,
    required this.protocol,
    required this.model,
    required this.requiresCredential,
  });

  factory AgentPromptProfileManifestEntry.fromProfile({
    required String key,
    required AgentPromptProfile profile,
  }) {
    return AgentPromptProfileManifestEntry(
      key: key,
      profileId: profile.profileId,
      displayName: profile.displayName,
      route: profile.endpoint.route.wireValue,
      protocol: profile.endpoint.protocol,
      model: profile.endpoint.model,
      requiresCredential: profile.endpoint.requiresCredential,
    );
  }

  factory AgentPromptProfileManifestEntry.fromJson(Map<String, Object?> json) {
    return AgentPromptProfileManifestEntry(
      key: json['key'] as String? ?? 'default',
      profileId: json['profileId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      route:
          json['route'] as String? ?? AgentProviderRoute.unresolved.wireValue,
      protocol: json['protocol'] as String? ?? 'openai-compatible',
      model: json['model'] as String? ?? '',
      requiresCredential: json['requiresCredential'] as bool? ?? false,
    );
  }

  final String key;
  final String profileId;
  final String displayName;
  final String route;
  final String protocol;
  final String model;
  final bool requiresCredential;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'profileId': profileId,
      'displayName': displayName,
      'route': route,
      'protocol': protocol,
      'model': model,
      'requiresCredential': requiresCredential,
    };
  }
}

class AgentPromptProfileManifest {
  const AgentPromptProfileManifest({this.entries = const []});

  factory AgentPromptProfileManifest.fromJson(Map<String, Object?> json) {
    final entriesJson = json['entries'];
    return AgentPromptProfileManifest(
      entries: entriesJson is List
          ? entriesJson
                .map(_manifestEntryFromJson)
                .whereType<AgentPromptProfileManifestEntry>()
                .toList(growable: false)
          : const <AgentPromptProfileManifestEntry>[],
    );
  }

  final List<AgentPromptProfileManifestEntry> entries;

  String? keyForProfileId(String profileId) {
    final normalizedProfileId = profileId.trim();
    if (normalizedProfileId.isEmpty) {
      return null;
    }
    for (final entry in entries) {
      if (entry.profileId == normalizedProfileId) {
        return entry.key;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': 1,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class AgentPromptProfileStore {
  AgentPromptProfileStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'agent.prompt-profile',
             layer: 'service',
             stateFamily: 'agent-profile',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const AgentPromptProfileStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'agent.profile';
  static const String _manifestKey = '__manifest__';

  final FoundationDataStoreOwner _owner;

  Future<void> saveProfile({
    required String workspaceId,
    String key = 'default',
    required AgentPromptProfile profile,
  }) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: key,
      value: profile.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    await _upsertManifestEntry(
      workspaceId: workspaceId,
      entry: AgentPromptProfileManifestEntry.fromProfile(
        key: key,
        profile: profile,
      ),
    );
  }

  Future<AgentPromptProfile?> readProfile({
    required String workspaceId,
    String key = 'default',
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    return value == null ? null : AgentPromptProfile.fromJson(value);
  }

  Future<bool> deleteProfile({
    required String workspaceId,
    String key = 'default',
  }) async {
    final deleted = await _owner.delete(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (deleted) {
      await _removeManifestEntry(workspaceId: workspaceId, key: key);
    }
    return deleted;
  }

  Future<AgentPromptProfileManifest> readProfileManifest({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _manifestKey,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    return value == null
        ? const AgentPromptProfileManifest()
        : AgentPromptProfileManifest.fromJson(value);
  }

  Stream<FoundationDataStoreChange> watchProfiles({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<void> _upsertManifestEntry({
    required String workspaceId,
    required AgentPromptProfileManifestEntry entry,
  }) async {
    await _owner.updateJson(
      namespaceName: _namespaceName,
      key: _manifestKey,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
      update: (current) async {
        final manifest = current == null
            ? const AgentPromptProfileManifest()
            : AgentPromptProfileManifest.fromJson(current);
        final entries = <AgentPromptProfileManifestEntry>[
          for (final existing in manifest.entries)
            if (existing.key != entry.key) existing,
          entry,
        ]..sort((left, right) => left.key.compareTo(right.key));
        return AgentPromptProfileManifest(entries: entries).toJson();
      },
    );
  }

  Future<void> _removeManifestEntry({
    required String workspaceId,
    required String key,
  }) async {
    await _owner.updateJson(
      namespaceName: _namespaceName,
      key: _manifestKey,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
      update: (current) async {
        if (current == null) {
          return const AgentPromptProfileManifest().toJson();
        }
        final manifest = AgentPromptProfileManifest.fromJson(current);
        final entries = <AgentPromptProfileManifestEntry>[
          for (final existing in manifest.entries)
            if (existing.key != key) existing,
        ];
        return AgentPromptProfileManifest(entries: entries).toJson();
      },
    );
  }
}

AgentPromptProfileManifestEntry? _manifestEntryFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return AgentPromptProfileManifestEntry.fromJson(value);
  }
  if (value is Map) {
    return AgentPromptProfileManifestEntry.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return null;
}
