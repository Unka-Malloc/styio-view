import 'configuration_store.dart';
import 'shell_configuration.dart';

class ShellConfigurationStore {
  const ShellConfigurationStore({required ConfigurationStore configurationStore})
    : _configurationStore = configurationStore;

  final ConfigurationStore _configurationStore;

  Future<void> save(
    ShellConfiguration configuration, {
    String? workspaceId,
  }) {
    return _configurationStore.write(
      ConfigurationSettingRecord(
        key: _key(workspaceId: workspaceId),
        value: configuration.toJson(),
      ),
    );
  }

  Future<ShellConfiguration?> load({String? workspaceId}) async {
    final record = await _configurationStore.read(
      _key(workspaceId: workspaceId),
    );
    return record == null ? null : ShellConfiguration.fromJson(record.value);
  }

  Future<bool> delete({String? workspaceId}) {
    return _configurationStore.delete(_key(workspaceId: workspaceId));
  }

  ConfigurationSettingKey _key({String? workspaceId}) {
    return ConfigurationSettingKey(
      namespace: 'shell',
      name: 'configuration',
      workspaceId: workspaceId,
    );
  }
}
