import '../../foundation/foundation.dart';

class EditorSessionSnapshot {
  const EditorSessionSnapshot({
    this.activeDocumentId,
    this.openDocumentIds = const <String>[],
    this.dirtyDocumentIds = const <String>[],
    this.cursorOffsets = const <String, int>{},
    this.selectionAnchors = const <String, int>{},
  });

  final String? activeDocumentId;
  final List<String> openDocumentIds;
  final List<String> dirtyDocumentIds;
  final Map<String, int> cursorOffsets;
  final Map<String, int> selectionAnchors;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (activeDocumentId != null) 'activeDocumentId': activeDocumentId,
      'openDocumentIds': openDocumentIds,
      'dirtyDocumentIds': dirtyDocumentIds,
      'cursorOffsets': cursorOffsets,
      'selectionAnchors': selectionAnchors,
    };
  }

  factory EditorSessionSnapshot.fromJson(Map<String, Object?> json) {
    return EditorSessionSnapshot(
      activeDocumentId: json['activeDocumentId'] as String?,
      openDocumentIds: _stringList(json['openDocumentIds']),
      dirtyDocumentIds: _stringList(json['dirtyDocumentIds']),
      cursorOffsets: _intMap(json['cursorOffsets']),
      selectionAnchors: _intMap(json['selectionAnchors']),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  static Map<String, int> _intMap(Object? value) {
    if (value is! Map) {
      return const <String, int>{};
    }
    return value.map((key, value) {
      final parsed = value is int ? value : int.tryParse(value.toString()) ?? 0;
      return MapEntry<String, int>(key.toString(), parsed);
    });
  }
}

class EditorSessionDataStore {
  EditorSessionDataStore.fromDataStore({required FoundationDataStore dataStore})
    : this(
        owner: FoundationDataStoreOwner(
          descriptor: const FoundationDataStoreOwnerDescriptor(
            ownerId: 'interaction.editor-session',
            layer: 'interaction',
            stateFamily: 'editor-session',
            allowedNamespaces: <String>{_namespaceName},
          ),
          dataStore: dataStore,
        ),
      );

  const EditorSessionDataStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'editor.session';

  final FoundationDataStoreOwner _owner;

  Future<void> saveSession({
    required String workspaceId,
    String key = 'default',
    required EditorSessionSnapshot snapshot,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: key,
      value: snapshot.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<EditorSessionSnapshot?> readSession({
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
    return value == null ? null : EditorSessionSnapshot.fromJson(value);
  }

  Future<bool> deleteSession({
    required String workspaceId,
    String key = 'default',
  }) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchSessions({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}
