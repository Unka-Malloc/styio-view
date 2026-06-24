import '../../foundation/foundation.dart';
import 'styio_language_service.dart';
import 'styio_service_capability_detector.dart';

enum StyioLanguageProviderCapability {
  syntaxDiagnostics,
  semanticSnapshot,
  completion,
  hover,
  definition,
  references,
  rename,
  semanticTokens,
  formatting,
  codeActions,
}

extension StyioLanguageProviderCapabilityWire
    on StyioLanguageProviderCapability {
  String get wireValue {
    return switch (this) {
      StyioLanguageProviderCapability.syntaxDiagnostics =>
        'language.syntax-diagnostics',
      StyioLanguageProviderCapability.semanticSnapshot =>
        'language.semantic-snapshot',
      StyioLanguageProviderCapability.completion => 'language.completion',
      StyioLanguageProviderCapability.hover => 'language.hover',
      StyioLanguageProviderCapability.definition => 'language.definition',
      StyioLanguageProviderCapability.references => 'language.references',
      StyioLanguageProviderCapability.rename => 'language.rename',
      StyioLanguageProviderCapability.semanticTokens =>
        'language.semantic-tokens',
      StyioLanguageProviderCapability.formatting => 'language.formatting',
      StyioLanguageProviderCapability.codeActions => 'language.code-actions',
    };
  }
}

const List<StyioLanguageProviderCapability>
defaultStyioLanguageProviderCapabilities = <StyioLanguageProviderCapability>[
  StyioLanguageProviderCapability.syntaxDiagnostics,
  StyioLanguageProviderCapability.semanticSnapshot,
  StyioLanguageProviderCapability.completion,
  StyioLanguageProviderCapability.hover,
  StyioLanguageProviderCapability.definition,
  StyioLanguageProviderCapability.references,
  StyioLanguageProviderCapability.rename,
  StyioLanguageProviderCapability.semanticTokens,
  StyioLanguageProviderCapability.formatting,
  StyioLanguageProviderCapability.codeActions,
];

class StyioLanguageProviderRegistration {
  const StyioLanguageProviderRegistration({
    required this.id,
    required this.service,
    this.priority = 0,
    this.state = FoundationRegistryEntryState.registered,
    this.capabilities = defaultStyioLanguageProviderCapabilities,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final StyioLanguageService service;
  final int priority;
  final FoundationRegistryEntryState state;
  final List<StyioLanguageProviderCapability> capabilities;
  final Map<String, Object?> metadata;
  final String todo;
}

class StyioLanguageProviderMissingCapabilityFact {
  const StyioLanguageProviderMissingCapabilityFact({
    required this.providerCapability,
    required this.requiredServiceCapabilities,
  });

  final StyioLanguageProviderCapability providerCapability;
  final List<StyioServiceCapability> requiredServiceCapabilities;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerCapability': providerCapability.wireValue,
      'requiredServiceCapabilities': requiredServiceCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
    };
  }
}

class StyioLanguageProviderBindingPlan {
  const StyioLanguageProviderBindingPlan({
    required this.providerId,
    required this.displayName,
    required this.state,
    required this.capabilities,
    this.priority = 0,
    this.metadata = const <String, Object?>{},
    this.missingServiceCapabilities = const <String>[],
    this.missingCapabilityFacts =
        const <StyioLanguageProviderMissingCapabilityFact>[],
    this.todo = '',
  });

  factory StyioLanguageProviderBindingPlan.fromStyioServiceSnapshot({
    required StyioServiceCapabilitySnapshot snapshot,
    String providerId = 'styio-service',
    String displayName = 'StyioService',
    int priority = 100,
    bool includeDerived = true,
  }) {
    final mappedCapabilities = <StyioLanguageProviderCapability>[];
    final missingServiceCapabilities = <String>[];
    final missingCapabilityFacts =
        <StyioLanguageProviderMissingCapabilityFact>[];
    for (final entry in _styioServiceCapabilityBindings.entries) {
      final providerCapability = entry.key;
      final serviceCapabilities = entry.value;
      final usable = serviceCapabilities.any((capability) {
        final status = snapshot.statuses[capability];
        return includeDerived
            ? status?.isUsable ?? false
            : status?.hasFreshPayload ?? false;
      });
      if (usable) {
        mappedCapabilities.add(providerCapability);
      } else {
        missingServiceCapabilities.add(
          '${providerCapability.wireValue}:'
          '${serviceCapabilities.map((capability) => capability.wireValue).join('|')}',
        );
        missingCapabilityFacts.add(
          StyioLanguageProviderMissingCapabilityFact(
            providerCapability: providerCapability,
            requiredServiceCapabilities:
                List<StyioServiceCapability>.unmodifiable(serviceCapabilities),
          ),
        );
      }
    }

    return StyioLanguageProviderBindingPlan(
      providerId: providerId,
      displayName: displayName,
      priority: priority,
      state: mappedCapabilities.isEmpty
          ? FoundationRegistryEntryState.disabled
          : FoundationRegistryEntryState.active,
      capabilities: List<StyioLanguageProviderCapability>.unmodifiable(
        mappedCapabilities,
      ),
      missingServiceCapabilities: List<String>.unmodifiable(
        missingServiceCapabilities,
      ),
      missingCapabilityFacts:
          List<StyioLanguageProviderMissingCapabilityFact>.unmodifiable(
            missingCapabilityFacts,
          ),
      metadata: <String, Object?>{
        'language': 'styio',
        'source': 'StyioServiceCapabilitySnapshot',
        'documentId': snapshot.documentId,
        'revision': snapshot.revision,
        'protocolVersion': snapshot.protocolVersion,
        if (snapshot.toolchainId.isNotEmpty)
          'toolchainId': snapshot.toolchainId,
        if (snapshot.parserEngine != null)
          'parserEngine': snapshot.parserEngine,
        if (snapshot.grammarVersion != null)
          'grammarVersion': snapshot.grammarVersion,
      },
      todo: missingServiceCapabilities.isEmpty
          ? ''
          : 'TODO: expose missing StyioService capabilities before enabling all IDE providers.',
    );
  }

  final String providerId;
  final String displayName;
  final int priority;
  final FoundationRegistryEntryState state;
  final List<StyioLanguageProviderCapability> capabilities;
  final Map<String, Object?> metadata;
  final List<String> missingServiceCapabilities;
  final List<StyioLanguageProviderMissingCapabilityFact> missingCapabilityFacts;
  final String todo;

  bool get active => state == FoundationRegistryEntryState.active;

  StyioLanguageProviderRegistration registration({
    required StyioLanguageService service,
  }) {
    return StyioLanguageProviderRegistration(
      id: providerId,
      service: service,
      priority: priority,
      state: state,
      capabilities: capabilities,
      metadata: <String, Object?>{
        ...metadata,
        'displayName': displayName,
        if (missingServiceCapabilities.isNotEmpty)
          'missingServiceCapabilities': missingServiceCapabilities,
        if (missingCapabilityFacts.isNotEmpty)
          'missingCapabilityFacts': missingCapabilityFacts
              .map((fact) => fact.toJson())
              .toList(growable: false),
      },
      todo: todo,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'displayName': displayName,
      'priority': priority,
      'state': state.name,
      'active': active,
      'capabilities': capabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (missingServiceCapabilities.isNotEmpty)
        'missingServiceCapabilities': missingServiceCapabilities,
      if (missingCapabilityFacts.isNotEmpty)
        'missingCapabilityFacts': missingCapabilityFacts
            .map((fact) => fact.toJson())
            .toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class StyioLanguageProviderCapabilityCoverage {
  const StyioLanguageProviderCapabilityCoverage({
    required this.capability,
    required this.providerIds,
  });

  final StyioLanguageProviderCapability capability;
  final List<String> providerIds;

  bool get covered => providerIds.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capability': capability.wireValue,
      'covered': covered,
      'providerIds': providerIds,
    };
  }
}

class StyioLanguageProviderReadinessReport {
  const StyioLanguageProviderReadinessReport({
    required this.coverage,
    this.todo = '',
  });

  factory StyioLanguageProviderReadinessReport.fromProviderCapabilities({
    required String providerId,
    required Iterable<StyioLanguageProviderCapability> providedCapabilities,
    Iterable<StyioLanguageProviderCapability> requiredCapabilities =
        defaultStyioLanguageProviderCapabilities,
  }) {
    final provided = providedCapabilities.toSet();
    final coverage = requiredCapabilities
        .map((capability) {
          return StyioLanguageProviderCapabilityCoverage(
            capability: capability,
            providerIds: provided.contains(capability)
                ? <String>[providerId]
                : const <String>[],
          );
        })
        .toList(growable: false);
    return StyioLanguageProviderReadinessReport(
      coverage: coverage,
      todo: coverage.every((entry) => entry.covered)
          ? ''
          : 'TODO: expose missing StyioService capabilities before enabling all IDE language providers.',
    );
  }

  final List<StyioLanguageProviderCapabilityCoverage> coverage;
  final String todo;

  bool get ready => coverage.every((entry) => entry.covered);

  List<StyioLanguageProviderCapability> get missingCapabilities {
    return coverage
        .where((entry) => !entry.covered)
        .map((entry) => entry.capability)
        .toList(growable: false);
  }

  String get summary {
    final coveredCount = coverage.where((entry) => entry.covered).length;
    return 'Styio language providers cover $coveredCount/${coverage.length} required IDE capabilities.';
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'summary': summary,
      'coverage': coverage.map((entry) => entry.toJson()).toList(),
      if (missingCapabilities.isNotEmpty)
        'missingCapabilities': missingCapabilities
            .map((capability) => capability.wireValue)
            .toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class StyioLanguageProviderRegistry {
  StyioLanguageProviderRegistry({
    FoundationProviderRegistry<StyioLanguageService>? registry,
  }) : _registry =
           registry ?? FoundationProviderRegistry<StyioLanguageService>();

  static const String owner = 'service.styio-language';

  final FoundationProviderRegistry<StyioLanguageService> _registry;

  void register(StyioLanguageProviderRegistration registration) {
    _registry.register(
      FoundationProviderRegistration<StyioLanguageService>(
        id: registration.id,
        owner: owner,
        provider: registration.service,
        layer: 'service',
        priority: registration.priority,
        state: registration.state,
        capabilities: _capabilityWireValues(registration.capabilities),
        metadata: <String, Object?>{
          ...registration.metadata,
          'language': 'styio',
          'providerContract': 'styio-language-service',
        },
        todo: registration.todo,
      ),
    );
  }

  FoundationRegistryEntry<StyioLanguageService>? resolve(
    StyioLanguageProviderCapability capability, {
    bool activeOnly = true,
  }) {
    return _registry.resolve(
      capability: capability.wireValue,
      owner: owner,
      activeOnly: activeOnly,
    );
  }

  StyioLanguageService? serviceFor(
    StyioLanguageProviderCapability capability, {
    bool activeOnly = true,
  }) {
    return resolve(capability, activeOnly: activeOnly)?.value;
  }

  List<FoundationRegistryEntry<StyioLanguageService>> providersFor(
    StyioLanguageProviderCapability capability, {
    FoundationRegistryEntryState? state,
  }) {
    return _registry.providersForCapability(
      capability.wireValue,
      owner: owner,
      state: state,
    );
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(owner: owner, state: state);
  }

  StyioLanguageProviderReadinessReport readinessReport({
    List<StyioLanguageProviderCapability> requiredCapabilities =
        defaultStyioLanguageProviderCapabilities,
    bool activeOnly = true,
  }) {
    final coverage = requiredCapabilities
        .map((capability) {
          final providers = providersFor(
            capability,
            state: activeOnly ? FoundationRegistryEntryState.active : null,
          );
          return StyioLanguageProviderCapabilityCoverage(
            capability: capability,
            providerIds: providers
                .map((provider) => provider.id)
                .toList(growable: false),
          );
        })
        .toList(growable: false);
    final report = StyioLanguageProviderReadinessReport(
      coverage: coverage,
      todo: coverage.every((entry) => entry.covered)
          ? ''
          : 'TODO: connect StyioService provider capabilities until all required IDE language features are covered.',
    );
    return report;
  }
}

const Map<StyioLanguageProviderCapability, List<StyioServiceCapability>>
_styioServiceCapabilityBindings =
    <StyioLanguageProviderCapability, List<StyioServiceCapability>>{
      StyioLanguageProviderCapability.syntaxDiagnostics:
          <StyioServiceCapability>[
            StyioServiceCapability.syntax,
            StyioServiceCapability.diagnostics,
          ],
      StyioLanguageProviderCapability.semanticSnapshot:
          <StyioServiceCapability>[
            StyioServiceCapability.analysis,
            StyioServiceCapability.documentSymbols,
            StyioServiceCapability.references,
            StyioServiceCapability.semanticTokens,
          ],
      StyioLanguageProviderCapability.completion: <StyioServiceCapability>[
        StyioServiceCapability.completion,
      ],
      StyioLanguageProviderCapability.hover: <StyioServiceCapability>[
        StyioServiceCapability.hover,
      ],
      StyioLanguageProviderCapability.definition: <StyioServiceCapability>[
        StyioServiceCapability.definition,
      ],
      StyioLanguageProviderCapability.references: <StyioServiceCapability>[
        StyioServiceCapability.references,
      ],
      StyioLanguageProviderCapability.rename: <StyioServiceCapability>[
        StyioServiceCapability.rename,
      ],
      StyioLanguageProviderCapability.semanticTokens: <StyioServiceCapability>[
        StyioServiceCapability.semanticTokens,
      ],
      StyioLanguageProviderCapability.formatting: <StyioServiceCapability>[
        StyioServiceCapability.formatting,
      ],
      StyioLanguageProviderCapability.codeActions: <StyioServiceCapability>[
        StyioServiceCapability.codeActions,
      ],
    };

List<String> _capabilityWireValues(
  List<StyioLanguageProviderCapability> capabilities,
) {
  return capabilities
      .map((capability) => capability.wireValue)
      .toList(growable: false);
}
