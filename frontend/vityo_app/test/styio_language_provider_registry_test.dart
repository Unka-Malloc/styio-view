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
    final readiness = registry.readinessReport(
      requiredCapabilities: const <StyioLanguageProviderCapability>[
        StyioLanguageProviderCapability.syntaxDiagnostics,
        StyioLanguageProviderCapability.completion,
        StyioLanguageProviderCapability.rename,
      ],
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
    expect(readiness.ready, isFalse);
    expect(readiness.missingCapabilities, <StyioLanguageProviderCapability>[
      StyioLanguageProviderCapability.rename,
    ]);
    expect(readiness.toJson()['todo'], startsWith('TODO:'));
  });

  test('Styio language provider readiness reports full active coverage', () {
    final registry = StyioLanguageProviderRegistry()
      ..register(
        const StyioLanguageProviderRegistration(
          id: 'styio-service',
          service: LocalStyioLanguageService(),
          priority: 10,
          state: FoundationRegistryEntryState.active,
        ),
      );

    final readiness = registry.readinessReport();
    final json = readiness.toJson();

    expect(readiness.ready, isTrue);
    expect(readiness.missingCapabilities, isEmpty);
    expect(readiness.summary, contains('10/10'));
    expect(json.containsKey('todo'), isFalse);
  });

  test('Styio language provider readiness can project a binding plan', () {
    final readiness =
        StyioLanguageProviderReadinessReport.fromProviderCapabilities(
          providerId: 'styio-service',
          providedCapabilities: const <StyioLanguageProviderCapability>[
            StyioLanguageProviderCapability.syntaxDiagnostics,
            StyioLanguageProviderCapability.completion,
          ],
          requiredCapabilities: const <StyioLanguageProviderCapability>[
            StyioLanguageProviderCapability.syntaxDiagnostics,
            StyioLanguageProviderCapability.completion,
            StyioLanguageProviderCapability.rename,
          ],
        );

    expect(readiness.ready, isFalse);
    expect(readiness.summary, contains('2/3'));
    expect(readiness.missingCapabilities, <StyioLanguageProviderCapability>[
      StyioLanguageProviderCapability.rename,
    ]);
    expect(readiness.toJson()['todo'], startsWith('TODO:'));
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

  test('StyioService capability snapshot builds provider binding plan', () {
    final snapshot = StyioServiceCapabilitySnapshot(
      documentId: 'file:///workspace/main.styio',
      revision: 9,
      protocolVersion: 'styio-cli-jsonl-v1',
      toolchainId: 'styio-nightly',
      parserEngine: 'styio-parser',
      grammarVersion: '2026-05',
      statuses: <StyioServiceCapability, StyioServiceCapabilityStatus>{
        for (final capability in StyioServiceCapability.values)
          capability: StyioServiceCapabilityStatus(
            capability: capability,
            state:
                <StyioServiceCapability>{
                  StyioServiceCapability.syntax,
                  StyioServiceCapability.diagnostics,
                  StyioServiceCapability.analysis,
                  StyioServiceCapability.completion,
                  StyioServiceCapability.hover,
                  StyioServiceCapability.semanticTokens,
                  StyioServiceCapability.references,
                  StyioServiceCapability.definition,
                }.contains(capability)
                ? StyioServiceCapabilityState.available
                : StyioServiceCapabilityState.empty,
          ),
      },
    );
    final plan = StyioLanguageProviderBindingPlan.fromStyioServiceSnapshot(
      snapshot: snapshot,
    );
    final registry = StyioLanguageProviderRegistry()
      ..register(
        plan.registration(service: const SimpleStyioLanguageService()),
      );

    expect(plan.active, isTrue);
    expect(plan.capabilities, contains(StyioLanguageProviderCapability.hover));
    expect(
      plan.capabilities,
      contains(StyioLanguageProviderCapability.semanticSnapshot),
    );
    expect(
      plan.capabilities,
      isNot(contains(StyioLanguageProviderCapability.rename)),
    );
    expect(plan.missingServiceCapabilities, isNotEmpty);
    expect(
      plan.missingCapabilityFacts.map((fact) => fact.providerCapability),
      contains(StyioLanguageProviderCapability.rename),
    );
    final missingRename = plan.missingCapabilityFacts.singleWhere(
      (fact) =>
          fact.providerCapability == StyioLanguageProviderCapability.rename,
    );
    expect(
      missingRename.requiredServiceCapabilities,
      contains(StyioServiceCapability.rename),
    );
    expect(plan.toJson()['todo'], startsWith('TODO:'));
    final missingFacts =
        plan.toJson()['missingCapabilityFacts']! as List<Object?>;
    expect(
      (missingFacts.first! as Map<String, Object?>).containsKey(
        'providerCapability',
      ),
      isTrue,
    );
    expect(
      registry.resolve(StyioLanguageProviderCapability.completion)?.id,
      'styio-service',
    );
    final manifestEntries =
        registry.manifest().toJson()['entries']! as List<Object?>;
    final manifestMetadata =
        (manifestEntries.single! as Map<String, Object?>)['metadata']!
            as Map<String, Object?>;
    expect(manifestMetadata['missingCapabilityFacts'], isA<List<Object?>>());
  });
}
