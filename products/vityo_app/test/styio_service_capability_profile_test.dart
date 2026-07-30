import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';

void main() {
  test('StyioService capability profile groups IDE feature tiers', () {
    final snapshot = _snapshotWith(
      available: const <StyioServiceCapability>{
        StyioServiceCapability.syntax,
        StyioServiceCapability.diagnostics,
        StyioServiceCapability.analysis,
        StyioServiceCapability.documentSymbols,
        StyioServiceCapability.references,
        StyioServiceCapability.definition,
        StyioServiceCapability.semanticTokens,
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
        StyioServiceCapability.codeActions,
      },
      unavailable: const <StyioServiceCapability>{
        StyioServiceCapability.rename,
      },
    );

    final profile = StyioServiceCapabilityProfile.fromSnapshot(snapshot);
    final syntax = profile.tier(StyioServiceCapabilityTier.syntax);
    final authoring = profile.tier(StyioServiceCapabilityTier.authoring);
    final refactor = profile.tier(StyioServiceCapabilityTier.refactor);
    final json = profile.toJson();

    expect(profile.syntaxReady, isTrue);
    expect(profile.semanticReady, isTrue);
    expect(profile.canDriveIntelligentCoding, isTrue);
    expect(syntax.status, StyioServiceCapabilityTierStatus.ready);
    expect(authoring.status, StyioServiceCapabilityTierStatus.degraded);
    expect(
      authoring.missingOptionalCapabilities,
      contains(StyioServiceCapability.formatting),
    );
    expect(refactor.status, StyioServiceCapabilityTierStatus.blocked);
    expect(
      refactor.blockedCapabilities,
      contains(StyioServiceCapability.rename),
    );
    expect(json['canDriveIntelligentCoding'], isTrue);
    expect(json['blockingTierCount'], 1);
    expect(json['todoItems'], isA<List<Object?>>());
  });

  test('StyioService capability profile blocks missing syntax floor', () {
    final snapshot = _snapshotWith(
      available: const <StyioServiceCapability>{StyioServiceCapability.syntax},
    );

    final profile = StyioServiceCapabilityProfile.fromSnapshot(snapshot);
    final syntax = profile.tier(StyioServiceCapabilityTier.syntax);

    expect(profile.syntaxReady, isFalse);
    expect(profile.canDriveIntelligentCoding, isFalse);
    expect(syntax.status, StyioServiceCapabilityTierStatus.unavailable);
    expect(
      syntax.missingRequiredCapabilities,
      contains(StyioServiceCapability.diagnostics),
    );
    expect(
      syntax.todo,
      contains('TODO: expose required StyioService syntax capabilities'),
    );
  });
}

StyioServiceCapabilitySnapshot _snapshotWith({
  Set<StyioServiceCapability> available = const <StyioServiceCapability>{},
  Set<StyioServiceCapability> unavailable = const <StyioServiceCapability>{},
}) {
  return StyioServiceCapabilitySnapshot(
    documentId: 'main.styio',
    revision: 7,
    protocolVersion: 'styio-service-test',
    toolchainId: 'styio-nightly',
    parserEngine: 'styio-nightly',
    grammarVersion: 'test-contract',
    statuses: <StyioServiceCapability, StyioServiceCapabilityStatus>{
      for (final capability in StyioServiceCapability.values)
        capability: StyioServiceCapabilityStatus(
          capability: capability,
          state: available.contains(capability)
              ? StyioServiceCapabilityState.available
              : unavailable.contains(capability)
              ? StyioServiceCapabilityState.unavailable
              : StyioServiceCapabilityState.empty,
        ),
    },
  );
}
