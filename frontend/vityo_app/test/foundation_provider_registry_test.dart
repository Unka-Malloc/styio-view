import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('provider registry resolves highest-priority active provider', () {
    final registry = FoundationProviderRegistry<_Provider>()
      ..register(
        const FoundationProviderRegistration<_Provider>(
          id: 'low-scm',
          owner: 'interaction.source-control',
          provider: _Provider('low'),
          layer: 'interaction',
          priority: 1,
          state: FoundationRegistryEntryState.active,
          capabilities: <String>['source-control.status'],
        ),
      )
      ..register(
        const FoundationProviderRegistration<_Provider>(
          id: 'high-scm',
          owner: 'interaction.source-control',
          provider: _Provider('high'),
          layer: 'interaction',
          priority: 10,
          state: FoundationRegistryEntryState.active,
          capabilities: <String>['source-control.status'],
        ),
      )
      ..register(
        const FoundationProviderRegistration<_Provider>(
          id: 'disabled-scm',
          owner: 'interaction.source-control',
          provider: _Provider('disabled'),
          layer: 'interaction',
          priority: 100,
          state: FoundationRegistryEntryState.disabled,
          capabilities: <String>['source-control.status'],
        ),
      );

    final resolved = registry.resolve(capability: 'source-control.status');
    final candidates = registry.providersForCapability(
      'source-control.status',
      state: FoundationRegistryEntryState.active,
    );

    expect(resolved?.id, 'high-scm');
    expect(resolved?.value.name, 'high');
    expect(candidates.map((entry) => entry.id), <String>[
      'high-scm',
      'low-scm',
    ]);
  });

  test('provider registry manifest keeps runtime providers out of JSON', () {
    final registry = FoundationProviderRegistry<_Provider>()
      ..register(
        const FoundationProviderRegistration<_Provider>(
          id: 'styio-service',
          owner: 'service.styio-language',
          provider: _Provider('styio'),
          layer: 'service',
          priority: 5,
          state: FoundationRegistryEntryState.registered,
          capabilities: <String>['language.diagnostics', 'language.completion'],
          metadata: <String, Object?>{'protocol': 'styio-service'},
          todo: 'TODO: bind to real StyioService capability detector.',
        ),
      );

    final json = registry.manifest().toJson();
    final entries = json['entries']! as List<Object?>;
    final entry = entries.single! as Map<String, Object?>;
    final metadata = entry['metadata']! as Map<String, Object?>;

    expect(entry['id'], 'styio-service');
    expect(entry['kind'], 'provider');
    expect(entry['owner'], 'service.styio-language');
    expect(metadata['layer'], 'service');
    expect(metadata['priority'], 5);
    expect(metadata['protocol'], 'styio-service');
    expect(metadata['capabilities'], <String>[
      'language.diagnostics',
      'language.completion',
    ]);
    expect(metadata['todo'], startsWith('TODO:'));
    expect(entry.containsKey('provider'), isFalse);
    expect(entry.containsKey('value'), isFalse);
  });
}

class _Provider {
  const _Provider(this.name);

  final String name;
}
