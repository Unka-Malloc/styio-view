import 'styio_service_capability_detector.dart';

enum StyioServiceCapabilityTier {
  syntax,
  semantic,
  authoring,
  navigation,
  refactor,
}

extension StyioServiceCapabilityTierX on StyioServiceCapabilityTier {
  String get wireValue => switch (this) {
    StyioServiceCapabilityTier.syntax => 'syntax',
    StyioServiceCapabilityTier.semantic => 'semantic',
    StyioServiceCapabilityTier.authoring => 'authoring',
    StyioServiceCapabilityTier.navigation => 'navigation',
    StyioServiceCapabilityTier.refactor => 'refactor',
  };

  String get label => switch (this) {
    StyioServiceCapabilityTier.syntax => 'Syntax',
    StyioServiceCapabilityTier.semantic => 'Semantic',
    StyioServiceCapabilityTier.authoring => 'Authoring',
    StyioServiceCapabilityTier.navigation => 'Navigation',
    StyioServiceCapabilityTier.refactor => 'Refactor',
  };
}

enum StyioServiceCapabilityTierStatus { ready, degraded, unavailable, blocked }

extension StyioServiceCapabilityTierStatusX
    on StyioServiceCapabilityTierStatus {
  String get wireValue => switch (this) {
    StyioServiceCapabilityTierStatus.ready => 'ready',
    StyioServiceCapabilityTierStatus.degraded => 'degraded',
    StyioServiceCapabilityTierStatus.unavailable => 'unavailable',
    StyioServiceCapabilityTierStatus.blocked => 'blocked',
  };
}

class StyioServiceCapabilityTierRequirement {
  const StyioServiceCapabilityTierRequirement({
    required this.tier,
    required this.requiredCapabilities,
    this.optionalCapabilities = const <StyioServiceCapability>[],
    this.description = '',
  });

  final StyioServiceCapabilityTier tier;
  final List<StyioServiceCapability> requiredCapabilities;
  final List<StyioServiceCapability> optionalCapabilities;
  final String description;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'tier': tier.wireValue,
      'label': tier.label,
      'requiredCapabilities': requiredCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      'optionalCapabilities': optionalCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      if (description.isNotEmpty) 'description': description,
    };
  }
}

const List<StyioServiceCapabilityTierRequirement>
defaultStyioServiceCapabilityTierRequirements = <StyioServiceCapabilityTierRequirement>[
  StyioServiceCapabilityTierRequirement(
    tier: StyioServiceCapabilityTier.syntax,
    requiredCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.syntax,
      StyioServiceCapability.diagnostics,
    ],
    description:
        'Minimum Styio parsing and syntax diagnostics required before Vityo can trust language-aware edits.',
  ),
  StyioServiceCapabilityTierRequirement(
    tier: StyioServiceCapabilityTier.semantic,
    requiredCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.analysis,
      StyioServiceCapability.documentSymbols,
      StyioServiceCapability.references,
      StyioServiceCapability.definition,
    ],
    optionalCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.semanticTokens,
    ],
    description:
        'Semantic facts used by resolved references, symbol-sensitive edits, diagnostics, and semantic highlighting.',
  ),
  StyioServiceCapabilityTierRequirement(
    tier: StyioServiceCapabilityTier.authoring,
    requiredCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.completion,
      StyioServiceCapability.hover,
      StyioServiceCapability.codeActions,
    ],
    optionalCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.inlayHints,
      StyioServiceCapability.parameterInfo,
      StyioServiceCapability.formatting,
    ],
    description:
        'Interactive authoring features exposed through completion popup, hover widget, quick fixes, hints, and formatting.',
  ),
  StyioServiceCapabilityTierRequirement(
    tier: StyioServiceCapabilityTier.navigation,
    requiredCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.definition,
      StyioServiceCapability.references,
      StyioServiceCapability.documentSymbols,
    ],
    optionalCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.semanticBlocks,
    ],
    description:
        'Navigation and structure features for definition, references, outline, folding, and structural movement.',
  ),
  StyioServiceCapabilityTierRequirement(
    tier: StyioServiceCapabilityTier.refactor,
    requiredCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.rename,
    ],
    optionalCapabilities: <StyioServiceCapability>[
      StyioServiceCapability.safeDelete,
      StyioServiceCapability.inlineVariable,
      StyioServiceCapability.introduceVariable,
      StyioServiceCapability.extractFunction,
      StyioServiceCapability.changeSignature,
      StyioServiceCapability.surround,
    ],
    description:
        'Refactoring features that must stay backed by StyioService facts and safe workspace edit previews.',
  ),
];

class StyioServiceCapabilityTierReadiness {
  const StyioServiceCapabilityTierReadiness({
    required this.requirement,
    required this.status,
    required this.missingRequiredCapabilities,
    required this.missingOptionalCapabilities,
    required this.blockedCapabilities,
    required this.todo,
  });

  factory StyioServiceCapabilityTierReadiness.evaluate({
    required StyioServiceCapabilitySnapshot snapshot,
    required StyioServiceCapabilityTierRequirement requirement,
  }) {
    final missingRequired = _missingCapabilities(
      snapshot,
      requirement.requiredCapabilities,
    );
    final missingOptional = _missingCapabilities(
      snapshot,
      requirement.optionalCapabilities,
    );
    final blocked = <StyioServiceCapability>[
      ..._blockedCapabilities(snapshot, requirement.requiredCapabilities),
      ..._blockedCapabilities(snapshot, requirement.optionalCapabilities),
    ];
    final status = _tierStatus(
      missingRequired: missingRequired,
      missingOptional: missingOptional,
      blockedCapabilities: blocked,
    );
    return StyioServiceCapabilityTierReadiness(
      requirement: requirement,
      status: status,
      missingRequiredCapabilities: List<StyioServiceCapability>.unmodifiable(
        missingRequired,
      ),
      missingOptionalCapabilities: List<StyioServiceCapability>.unmodifiable(
        missingOptional,
      ),
      blockedCapabilities: List<StyioServiceCapability>.unmodifiable(blocked),
      todo: _tierTodo(requirement.tier, status),
    );
  }

  final StyioServiceCapabilityTierRequirement requirement;
  final StyioServiceCapabilityTierStatus status;
  final List<StyioServiceCapability> missingRequiredCapabilities;
  final List<StyioServiceCapability> missingOptionalCapabilities;
  final List<StyioServiceCapability> blockedCapabilities;
  final String todo;

  StyioServiceCapabilityTier get tier => requirement.tier;

  bool get ready => status == StyioServiceCapabilityTierStatus.ready;

  bool get usable =>
      status == StyioServiceCapabilityTierStatus.ready ||
      status == StyioServiceCapabilityTierStatus.degraded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'tier': tier.wireValue,
      'label': tier.label,
      'status': status.wireValue,
      'ready': ready,
      'usable': usable,
      'requirement': requirement.toJson(),
      'missingRequiredCapabilities': missingRequiredCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      'missingOptionalCapabilities': missingOptionalCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      'blockedCapabilities': blockedCapabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class StyioServiceCapabilityProfile {
  const StyioServiceCapabilityProfile({
    required this.snapshot,
    required this.tiers,
  });

  factory StyioServiceCapabilityProfile.fromSnapshot(
    StyioServiceCapabilitySnapshot snapshot, {
    Iterable<StyioServiceCapabilityTierRequirement> requirements =
        defaultStyioServiceCapabilityTierRequirements,
  }) {
    return StyioServiceCapabilityProfile(
      snapshot: snapshot,
      tiers: requirements
          .map(
            (requirement) => StyioServiceCapabilityTierReadiness.evaluate(
              snapshot: snapshot,
              requirement: requirement,
            ),
          )
          .toList(growable: false),
    );
  }

  final StyioServiceCapabilitySnapshot snapshot;
  final List<StyioServiceCapabilityTierReadiness> tiers;

  StyioServiceCapabilityTierReadiness tier(StyioServiceCapabilityTier target) {
    return tiers.singleWhere((entry) => entry.tier == target);
  }

  bool get syntaxReady => tier(StyioServiceCapabilityTier.syntax).usable;

  bool get semanticReady => tier(StyioServiceCapabilityTier.semantic).usable;

  bool get canDriveIntelligentCoding => syntaxReady && semanticReady;

  List<StyioServiceCapabilityTierReadiness> get blockingTiers {
    return tiers
        .where(
          (entry) => entry.status == StyioServiceCapabilityTierStatus.blocked,
        )
        .toList(growable: false);
  }

  List<String> get todoItems {
    return tiers
        .map((entry) => entry.todo)
        .where((todo) => todo.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': snapshot.documentId,
      'revision': snapshot.revision,
      'protocolVersion': snapshot.protocolVersion,
      if (snapshot.toolchainId.isNotEmpty) 'toolchainId': snapshot.toolchainId,
      if (snapshot.parserEngine != null) 'parserEngine': snapshot.parserEngine,
      if (snapshot.grammarVersion != null)
        'grammarVersion': snapshot.grammarVersion,
      'syntaxReady': syntaxReady,
      'semanticReady': semanticReady,
      'canDriveIntelligentCoding': canDriveIntelligentCoding,
      'blockingTierCount': blockingTiers.length,
      'tiers': tiers.map((entry) => entry.toJson()).toList(growable: false),
      'todoItems': todoItems,
    };
  }
}

List<StyioServiceCapability> _missingCapabilities(
  StyioServiceCapabilitySnapshot snapshot,
  Iterable<StyioServiceCapability> capabilities,
) {
  return capabilities
      .where(
        (capability) => !(snapshot.statuses[capability]?.isUsable ?? false),
      )
      .toList(growable: false);
}

List<StyioServiceCapability> _blockedCapabilities(
  StyioServiceCapabilitySnapshot snapshot,
  Iterable<StyioServiceCapability> capabilities,
) {
  return capabilities
      .where((capability) => _isBlockedState(snapshot.stateOf(capability)))
      .toList(growable: false);
}

bool _isBlockedState(StyioServiceCapabilityState state) {
  return switch (state) {
    StyioServiceCapabilityState.unsupported ||
    StyioServiceCapabilityState.unavailable ||
    StyioServiceCapabilityState.failed ||
    StyioServiceCapabilityState.protocolError ||
    StyioServiceCapabilityState.stale => true,
    StyioServiceCapabilityState.available ||
    StyioServiceCapabilityState.derived ||
    StyioServiceCapabilityState.empty => false,
  };
}

StyioServiceCapabilityTierStatus _tierStatus({
  required List<StyioServiceCapability> missingRequired,
  required List<StyioServiceCapability> missingOptional,
  required List<StyioServiceCapability> blockedCapabilities,
}) {
  if (missingRequired.isEmpty && missingOptional.isEmpty) {
    return StyioServiceCapabilityTierStatus.ready;
  }
  if (blockedCapabilities.any(missingRequired.contains)) {
    return StyioServiceCapabilityTierStatus.blocked;
  }
  if (missingRequired.isNotEmpty) {
    return StyioServiceCapabilityTierStatus.unavailable;
  }
  if (blockedCapabilities.isNotEmpty || missingOptional.isNotEmpty) {
    return StyioServiceCapabilityTierStatus.degraded;
  }
  return StyioServiceCapabilityTierStatus.ready;
}

String _tierTodo(
  StyioServiceCapabilityTier tier,
  StyioServiceCapabilityTierStatus status,
) {
  return switch (status) {
    StyioServiceCapabilityTierStatus.ready => '',
    StyioServiceCapabilityTierStatus.degraded =>
      'TODO: fill optional StyioService ${tier.wireValue} capabilities before declaring this IDE feature tier mature.',
    StyioServiceCapabilityTierStatus.unavailable =>
      'TODO: expose required StyioService ${tier.wireValue} capabilities before enabling dependent IDE and Agent features.',
    StyioServiceCapabilityTierStatus.blocked =>
      'TODO: recover blocked StyioService ${tier.wireValue} capabilities before routing dependent IDE and Agent features.',
  };
}
