import 'configuration_store.dart';
import 'language_service_configuration.dart';

class LanguageServiceConfigurationStore {
  const LanguageServiceConfigurationStore({
    required ConfigurationStore configurationStore,
  }) : _configurationStore = configurationStore;

  final ConfigurationStore _configurationStore;

  Future<void> save(
    LanguageServiceConfiguration configuration, {
    String? workspaceId,
  }) {
    return _configurationStore.write(
      ConfigurationSettingRecord(
        key: _key(workspaceId: workspaceId),
        value: configuration.toJson(),
      ),
    );
  }

  Future<LanguageServiceConfiguration?> load({String? workspaceId}) async {
    final record = await _configurationStore.read(
      _key(workspaceId: workspaceId),
    );
    return record == null
        ? null
        : LanguageServiceConfiguration.fromJson(record.value);
  }

  Future<bool> delete({String? workspaceId}) {
    return _configurationStore.delete(_key(workspaceId: workspaceId));
  }

  ConfigurationSettingKey _key({String? workspaceId}) {
    return ConfigurationSettingKey(
      namespace: 'language-service',
      name: 'configuration',
      workspaceId: workspaceId,
    );
  }
}
