import '../foundation/foundation.dart';
import 'source_control_status.dart';

class SourceControlDiffSessionState {
  const SourceControlDiffSessionState({
    required this.workspaceId,
    this.providerKind = SourceControlProviderKind.git,
    this.path = '',
    this.windowStartLine = 0,
    this.windowLineLimit = 200,
    this.selectedHunkIndexes = const <int>[],
    this.updatedAt,
  });

  factory SourceControlDiffSessionState.fromJson(Map<String, Object?> json) {
    return SourceControlDiffSessionState(
      workspaceId: json['workspaceId'] as String? ?? '',
      providerKind: _providerKindFromJson(json['providerKind']),
      path: json['path'] as String? ?? '',
      windowStartLine: _nonNegativeInt(json['windowStartLine']),
      windowLineLimit: _positiveInt(json['windowLineLimit'], fallback: 200),
      selectedHunkIndexes: _jsonIntList(json['selectedHunkIndexes']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  factory SourceControlDiffSessionState.fromDiffWindow({
    required String workspaceId,
    required SourceControlDiffWindowBinding binding,
    SourceControlHunkSelectionState? hunkSelectionState,
  }) {
    return SourceControlDiffSessionState(
      workspaceId: workspaceId,
      providerKind: binding.snapshot.providerKind,
      path: binding.snapshot.path,
      windowStartLine: binding.window.startLine,
      windowLineLimit: binding.lineLimit <= 0 ? 200 : binding.lineLimit,
      selectedHunkIndexes:
          hunkSelectionState?.selectedHunkIndexes ?? const <int>[],
    );
  }

  final String workspaceId;
  final SourceControlProviderKind providerKind;
  final String path;
  final int windowStartLine;
  final int windowLineLimit;
  final List<int> selectedHunkIndexes;
  final DateTime? updatedAt;

  bool get hasPath => path.trim().isNotEmpty;
  bool get hasHunkSelection => selectedHunkIndexes.isNotEmpty;

  SourceControlDiffSessionState copyWith({
    String? workspaceId,
    SourceControlProviderKind? providerKind,
    String? path,
    int? windowStartLine,
    int? windowLineLimit,
    List<int>? selectedHunkIndexes,
    DateTime? updatedAt,
  }) {
    return SourceControlDiffSessionState(
      workspaceId: workspaceId ?? this.workspaceId,
      providerKind: providerKind ?? this.providerKind,
      path: path == null ? this.path : path.trim(),
      windowStartLine: _nonNegativeInt(windowStartLine ?? this.windowStartLine),
      windowLineLimit: _positiveInt(
        windowLineLimit ?? this.windowLineLimit,
        fallback: 200,
      ),
      selectedHunkIndexes: _normalizeIndexes(
        selectedHunkIndexes ?? this.selectedHunkIndexes,
      ),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'providerKind': providerKind.wireValue,
      'path': path,
      'hasPath': hasPath,
      'windowStartLine': windowStartLine,
      'windowLineLimit': windowLineLimit,
      'selectedHunkIndexes': selectedHunkIndexes,
      'selectedHunkCount': selectedHunkIndexes.length,
      'hasHunkSelection': hasHunkSelection,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class SourceControlDiffSessionStore {
  SourceControlDiffSessionStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.source-control.diff-session',
             layer: 'interaction',
             stateFamily: 'source-control-diff-session',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const SourceControlDiffSessionStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName =
      'interaction.source-control.diff-session';
  static const String _key = 'session';

  final FoundationDataStoreOwner _owner;

  Future<void> saveSession(SourceControlDiffSessionState session) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: session.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: session.workspaceId,
    );
  }

  Future<SourceControlDiffSessionState> readSession({
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
      return SourceControlDiffSessionState(workspaceId: workspaceId);
    }
    final session = SourceControlDiffSessionState.fromJson(value);
    return session.workspaceId.isEmpty
        ? session.copyWith(workspaceId: workspaceId)
        : session;
  }

  Future<bool> deleteSession({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchSession({
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

SourceControlProviderKind _providerKindFromJson(Object? value) {
  final wireValue = value?.toString();
  for (final kind in SourceControlProviderKind.values) {
    if (kind.wireValue == wireValue || kind.name == wireValue) {
      return kind;
    }
  }
  return SourceControlProviderKind.git;
}

int _nonNegativeInt(Object? value) {
  final parsed = _intValue(value);
  return parsed < 0 ? 0 : parsed;
}

int _positiveInt(Object? value, {required int fallback}) {
  final parsed = _intValue(value);
  return parsed <= 0 ? fallback : parsed;
}

int _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  return 0;
}

List<int> _jsonIntList(Object? value) {
  if (value is! List) {
    return const <int>[];
  }
  return _normalizeIndexes(value.map(_intValue));
}

List<int> _normalizeIndexes(Iterable<int> indexes) {
  final result = indexes.where((index) => index >= 0).toSet().toList()..sort();
  return List<int>.unmodifiable(result);
}
