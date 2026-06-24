import '../foundation/foundation.dart';
import 'testing_provider.dart';

class TestRunConfigurationSet {
  const TestRunConfigurationSet({
    required this.workspaceId,
    this.selectedConfigurationId = '',
    this.configurations = const <TestRunConfiguration>[],
    this.updatedAt,
  });

  factory TestRunConfigurationSet.fromJson(Map<String, Object?> json) {
    return TestRunConfigurationSet(
      workspaceId: json['workspaceId'] as String? ?? '',
      selectedConfigurationId: json['selectedConfigurationId'] as String? ?? '',
      configurations: _jsonConfigurations(json['configurations']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final String selectedConfigurationId;
  final List<TestRunConfiguration> configurations;
  final DateTime? updatedAt;

  TestRunConfiguration? get selectedConfiguration {
    if (selectedConfigurationId.isNotEmpty) {
      for (final configuration in configurations) {
        if (configuration.id == selectedConfigurationId) {
          return configuration;
        }
      }
    }
    return configurations.isEmpty ? null : configurations.first;
  }

  TestRunConfigurationSet upsertConfiguration(
    TestRunConfiguration configuration,
  ) {
    final nextConfigurations = <TestRunConfiguration>[];
    var replaced = false;
    for (final existing in configurations) {
      if (existing.id == configuration.id) {
        nextConfigurations.add(configuration);
        replaced = true;
      } else {
        nextConfigurations.add(existing);
      }
    }
    if (!replaced) {
      nextConfigurations.add(configuration);
    }
    nextConfigurations.sort((left, right) => left.id.compareTo(right.id));
    return copyWith(
      configurations: nextConfigurations,
      selectedConfigurationId: selectedConfigurationId.isEmpty
          ? configuration.id
          : selectedConfigurationId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  TestRunConfigurationSet selectConfiguration(String configurationId) {
    final normalizedId = configurationId.trim();
    if (normalizedId.isEmpty ||
        !configurations.any(
          (configuration) => configuration.id == normalizedId,
        )) {
      return this;
    }
    return copyWith(
      selectedConfigurationId: normalizedId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  TestRunConfigurationSet removeConfiguration(String configurationId) {
    final nextConfigurations = configurations
        .where((configuration) => configuration.id != configurationId)
        .toList(growable: false);
    return copyWith(
      configurations: nextConfigurations,
      selectedConfigurationId: selectedConfigurationId == configurationId
          ? ''
          : selectedConfigurationId,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  TestRunConfigurationSet copyWith({
    String? workspaceId,
    String? selectedConfigurationId,
    List<TestRunConfiguration>? configurations,
    DateTime? updatedAt,
  }) {
    return TestRunConfigurationSet(
      workspaceId: workspaceId ?? this.workspaceId,
      selectedConfigurationId:
          selectedConfigurationId ?? this.selectedConfigurationId,
      configurations: configurations ?? this.configurations,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      if (selectedConfigurationId.isNotEmpty)
        'selectedConfigurationId': selectedConfigurationId,
      'configurationCount': configurations.length,
      'selectedConfigurationReady': selectedConfiguration?.ready ?? false,
      'configurations': configurations
          .map((configuration) => configuration.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class TestRunConfigurationStore {
  TestRunConfigurationStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.testing.run-configurations',
             layer: 'interaction',
             stateFamily: 'test-run-configurations',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const TestRunConfigurationStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'interaction.testing.run-configurations';
  static const String _key = 'configurations';

  final FoundationDataStoreOwner _owner;

  Future<void> saveConfigurationSet(TestRunConfigurationSet set) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: set.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: set.workspaceId,
    );
  }

  Future<TestRunConfigurationSet> readConfigurationSet({
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
      return TestRunConfigurationSet(workspaceId: workspaceId);
    }
    final set = TestRunConfigurationSet.fromJson(value);
    return set.workspaceId.isEmpty
        ? set.copyWith(workspaceId: workspaceId)
        : set;
  }

  Future<bool> deleteConfigurationSet({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchConfigurationSet({
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

List<TestRunConfiguration> _jsonConfigurations(Object? value) {
  if (value is! List) {
    return const <TestRunConfiguration>[];
  }
  return value
      .whereType<Map>()
      .map(
        (configuration) => TestRunConfiguration.fromJson(
          configuration.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
