import '../foundation/foundation.dart';
import 'workspace_diagnostics.dart';

class WorkspaceDiagnosticsFilterStore {
  WorkspaceDiagnosticsFilterStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.diagnostics-filter',
             layer: 'interaction',
             stateFamily: 'diagnostics-filter',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceDiagnosticsFilterStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'workspace.diagnostics-filter';
  static const String _defaultKey = 'default';

  final FoundationDataStoreOwner _owner;

  Future<void> saveFilter({
    required String workspaceId,
    String key = _defaultKey,
    required WorkspaceDiagnosticsFilterState filter,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: key,
      value: filter.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<WorkspaceDiagnosticsFilterState> readFilter({
    required String workspaceId,
    String key = _defaultKey,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );

    return value == null
        ? const WorkspaceDiagnosticsFilterState()
        : WorkspaceDiagnosticsFilterState.fromJson(value);
  }

  Future<bool> deleteFilter({
    required String workspaceId,
    String key = _defaultKey,
  }) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchFilters({
    required String workspaceId,
    String? key,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}
