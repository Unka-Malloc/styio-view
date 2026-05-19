import '../../foundation/foundation.dart';
import 'styio_language_service.dart';

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
}

List<String> _capabilityWireValues(
  List<StyioLanguageProviderCapability> capabilities,
) {
  return capabilities
      .map((capability) => capability.wireValue)
      .toList(growable: false);
}
