import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';

void main() {
  test('agent language context exposes StyioService capability profile', () {
    final surface = LanguageServiceStatusSurface.fromRuntimeSnapshot(
      StyioServiceRuntimeStatusSnapshot(
        state: StyioServiceRuntimeSessionState.active,
        disposed: false,
        providerManifest: LanguageProviderRegistry<String>().manifest(),
        capabilitySnapshot: _snapshotWith(
          available: const <StyioServiceCapability>{
            StyioServiceCapability.syntax,
            StyioServiceCapability.diagnostics,
            StyioServiceCapability.analysis,
            StyioServiceCapability.documentSymbols,
            StyioServiceCapability.references,
            StyioServiceCapability.definition,
          },
        ),
      ),
    );
    final context = AgentSessionContext.fromEditorState(
      document: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      selection: const SelectionState.collapsed(0),
      diagnostics: const [],
      languageServiceStatus: surface,
    );
    final languageJson = context.toJson()['language']! as Map<String, Object?>;
    final serviceStatus =
        languageJson['serviceStatus']! as Map<String, Object?>;
    final capabilityProfile =
        serviceStatus['capabilityProfile']! as Map<String, Object?>;

    expect(serviceStatus['canDriveIntelligentCoding'], isTrue);
    expect(capabilityProfile['syntaxReady'], isTrue);
    expect(capabilityProfile['semanticReady'], isTrue);
    expect(capabilityProfile['canDriveIntelligentCoding'], isTrue);
    expect(capabilityProfile['tiers'], isA<List<Object?>>());
  });
}

StyioServiceCapabilitySnapshot _snapshotWith({
  Set<StyioServiceCapability> available = const <StyioServiceCapability>{},
}) {
  return StyioServiceCapabilitySnapshot(
    documentId: 'main.styio',
    revision: 1,
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
              : StyioServiceCapabilityState.empty,
        ),
    },
  );
}
