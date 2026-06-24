import '../../foundation/foundation.dart';
import 'vityo_theme_override.dart';

class VityoThemeOverrideStore {
  VityoThemeOverrideStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'vityo.theme-override',
             layer: 'configuration',
             stateFamily: 'theme',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const VityoThemeOverrideStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'theme.override';

  final FoundationDataStoreOwner _owner;

  Future<void> saveOverride({
    required String workspaceId,
    String key = 'default',
    required VityoThemeOverride override,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: key,
      value: override.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<VityoThemeOverride?> readOverride({
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
    return value == null ? null : VityoThemeOverride.fromJson(value);
  }

  Future<bool> deleteOverride({
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
}
