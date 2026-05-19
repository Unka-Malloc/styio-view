import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/language/service/simple_styio_language_service.dart';

void main() {
  test('Styio language provider registry resolves capability by priority', () {
    final registry = StyioLanguageProviderRegistry()
      ..register(
        const StyioLanguageProviderRegistration(
          id: 'local-fallback',
          service: SimpleStyioLanguageService(),
          priority: 1,
          state: FoundationRegistryEntryState.active,
          capabilities: <StyioLanguageProviderCapability>[
            StyioLanguageProviderCapability.syntaxDiagnostics,
            StyioLanguageProviderCapability.completion,
          ],
          todo: 'TODO: replace fallback facts with StyioService facts.',
        ),
      )
      ..register(
        const StyioLanguageProviderRegistration(
          id: 'styio-service',
          service: LocalStyioLanguageService(),
          priority: 10,
          state: FoundationRegistryEntryState.active,
          capabilities: <StyioLanguageProviderCapability>[
            StyioLanguageProviderCapability.syntaxDiagnostics,
            StyioLanguageProviderCapability.semanticSnapshot,
            StyioLanguageProviderCapability.completion,
          ],
          metadata: <String, Object?>{'protocol': 'styio-service-v1'},
        ),
      )
      ..register(
        const StyioLanguageProviderRegistration(
          id: 'disabled-experimental',
          service: LocalStyioLanguageService(),
          priority: 100,
          state: FoundationRegistryEntryState.disabled,
          capabilities: <StyioLanguageProviderCapability>[
            StyioLanguageProviderCapability.completion,
          ],
        ),
      );

    final resolved = registry.resolve(
      StyioLanguageProviderCapability.completion,
    );
    final candidates = registry.providersFor(
      StyioLanguageProviderCapability.completion,
      state: FoundationRegistryEntryState.active,
    );

    expect(resolved?.id, 'styio-service');
    expect(
      registry.serviceFor(StyioLanguageProviderCapability.completion),
      isA<LocalStyioLanguageService>(),
    );
    expect(candidates.map((entry) => entry.id), <String>[
      'styio-service',
      'local-fallback',
    ]);
  });

  test('Styio language provider registry emits manifest-only metadata', () {
    final registry = StyioLanguageProviderRegistry()
      ..register(
        const StyioLanguageProviderRegistration(
          id: 'styio-service',
          service: LocalStyioLanguageService(),
          priority: 10,
          state: FoundationRegistryEntryState.registered,
          capabilities: <StyioLanguageProviderCapability>[
            StyioLanguageProviderCapability.syntaxDiagnostics,
            StyioLanguageProviderCapability.semanticSnapshot,
            StyioLanguageProviderCapability.hover,
          ],
          metadata: <String, Object?>{'protocol': 'styio-service-v1'},
          todo: 'TODO: bind to external styio-nightly embedded API.',
        ),
      );

    final json = registry.manifest().toJson();
    final entries = json['entries']! as List<Object?>;
    final entry = entries.single! as Map<String, Object?>;
    final metadata = entry['metadata']! as Map<String, Object?>;

    expect(entry['id'], 'styio-service');
    expect(entry['owner'], StyioLanguageProviderRegistry.owner);
    expect(entry['kind'], 'provider');
    expect(metadata['language'], 'styio');
    expect(metadata['providerContract'], 'styio-language-service');
    expect(metadata['protocol'], 'styio-service-v1');
    expect(metadata['capabilities'], <String>[
      'language.syntax-diagnostics',
      'language.semantic-snapshot',
      'language.hover',
    ]);
    expect(metadata['todo'], startsWith('TODO:'));
    expect(entry.containsKey('service'), isFalse);
    expect(entry.containsKey('value'), isFalse);
  });
}
