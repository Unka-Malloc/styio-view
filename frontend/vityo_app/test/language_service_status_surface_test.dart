import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_capability_detector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_runtime.dart';

void main() {
  test('language service status surface projects ready runtime status', () {
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://status',
      revision: 1,
      toolchainId: 'styio-nightly',
      completions: <CompletionItem>[
        CompletionItem(
          label: 'value',
          kind: CompletionItemKind.variable,
          insertText: 'value',
        ),
      ],
      parameterInfos: <ParameterInfoPayload>[
        ParameterInfoPayload(
          callableName: 'value',
          signature: 'value()',
          parameters: <ParameterInfoParameter>[],
          activeParameterIndex: -1,
          invocationRange: SourceRange(start: 0, end: 7),
          callableRange: SourceRange(start: 0, end: 5),
        ),
      ],
    );
    final capabilitySnapshot = const StyioServiceCapabilityDetector().detect(
      response,
    );
    final runtimeSnapshot = StyioServiceRuntimeStatusSnapshot(
      state: StyioServiceRuntimeSessionState.active,
      disposed: false,
      providerManifest: LanguageProviderRegistry<String>().manifest(),
      capabilitySnapshot: capabilitySnapshot,
      allowLocalFallback: false,
    );

    final surface = LanguageServiceStatusSurface.fromRuntimeSnapshot(
      runtimeSnapshot,
    );

    expect(surface.severity, LanguageServiceStatusSeverity.ready);
    expect(surface.localFallbackEnabled, isFalse);
    expect(surface.toolchainId, 'styio-nightly');
    expect(surface.usableCapabilityCount, 3);
    expect(
      surface.primaryCapabilityStates[StyioServiceCapability
          .diagnostics
          .wireValue],
      StyioServiceCapabilityState.available.name,
    );
    expect(
      surface.primaryCapabilityStates[StyioServiceCapability
          .completion
          .wireValue],
      StyioServiceCapabilityState.available.name,
    );
    expect(
      surface.primaryCapabilityStates[StyioServiceCapability
          .definition
          .wireValue],
      StyioServiceCapabilityState.empty.name,
    );
    expect(
      surface.primaryCapabilityStates[StyioServiceCapability
          .parameterInfo
          .wireValue],
      StyioServiceCapabilityState.available.name,
    );
    expect(surface.capabilities.where((item) => item.usable), hasLength(3));
    expect(surface.toJson()['actionable'], isFalse);
    expect(surface.toJson()['localFallbackEnabled'], isFalse);
  });

  test('language service status surface treats clean diagnostics as ready', () {
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://clean-syntax',
      revision: 1,
      toolchainId: 'styio-nightly',
    );
    final capabilitySnapshot = const StyioServiceCapabilityDetector().detect(
      response,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.diagnostics,
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
        StyioServiceCapability.semanticTokens,
      ],
    );
    final runtimeSnapshot = StyioServiceRuntimeStatusSnapshot(
      state: StyioServiceRuntimeSessionState.active,
      disposed: false,
      providerManifest: LanguageProviderRegistry<String>().manifest(),
      capabilitySnapshot: capabilitySnapshot,
    );

    final surface = LanguageServiceStatusSurface.fromRuntimeSnapshot(
      runtimeSnapshot,
    );

    expect(surface.severity, LanguageServiceStatusSeverity.ready);
    expect(surface.usableCapabilityCount, 1);
    expect(surface.freshCapabilityCount, 1);
    expect(
      surface.primaryCapabilityStates[StyioServiceCapability
          .diagnostics
          .wireValue],
      StyioServiceCapabilityState.available.name,
    );
    expect(
      surface.primaryCapabilityStates[StyioServiceCapability
          .completion
          .wireValue],
      StyioServiceCapabilityState.empty.name,
    );
  });

  test(
    'language service status surface preserves unsupported capabilities',
    () {
      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://unsupported-capability',
        revision: 1,
        toolchainId: 'styio-nightly',
        capabilityStates: <String, String>{
          'diagnostics': 'available',
          'completion': 'available',
          'hover': 'unsupported',
          'semantic-tokens': 'empty',
        },
        capabilityMessages: <String, String>{
          'hover': 'hover facts are not emitted by this toolchain',
        },
      );
      final capabilitySnapshot = const StyioServiceCapabilityDetector().detect(
        response,
        expectedCapabilities: const <StyioServiceCapability>[
          StyioServiceCapability.diagnostics,
          StyioServiceCapability.completion,
          StyioServiceCapability.hover,
          StyioServiceCapability.semanticTokens,
        ],
      );
      final runtimeSnapshot = StyioServiceRuntimeStatusSnapshot(
        state: StyioServiceRuntimeSessionState.active,
        disposed: false,
        providerManifest: LanguageProviderRegistry<String>().manifest(),
        capabilitySnapshot: capabilitySnapshot,
      );

      final surface = LanguageServiceStatusSurface.fromRuntimeSnapshot(
        runtimeSnapshot,
      );

      expect(surface.severity, LanguageServiceStatusSeverity.ready);
      expect(surface.usableCapabilityCount, 2);
      expect(surface.freshCapabilityCount, 2);
      expect(
        surface.primaryCapabilityStates[StyioServiceCapability.hover.wireValue],
        StyioServiceCapabilityState.unsupported.name,
      );
      expect(
        surface.capabilities
            .singleWhere(
              (item) =>
                  item.capability == StyioServiceCapability.hover.wireValue,
            )
            .usable,
        isFalse,
      );
    },
  );

  test(
    'language service status surface projects unavailable disposed status',
    () {
      final runtimeSnapshot = StyioServiceRuntimeStatusSnapshot(
        state: StyioServiceRuntimeSessionState.disposed,
        disposed: true,
        providerManifest: LanguageProviderRegistry<String>().manifest(),
      );

      final surface = LanguageServiceStatusSurface.fromRuntimeSnapshot(
        runtimeSnapshot,
      );

      expect(surface.severity, LanguageServiceStatusSeverity.unavailable);
      expect(surface.actionable, isTrue);
      expect(surface.capabilities, isEmpty);
      expect(
        surface.primaryCapabilityStates[StyioServiceCapability.hover.wireValue],
        StyioServiceCapabilityState.unavailable.name,
      );
      expect(
        surface.primaryCapabilityStates[StyioServiceCapability
            .parameterInfo
            .wireValue],
        StyioServiceCapabilityState.unavailable.name,
      );
      expect(
        surface.primaryCapabilityStates[StyioServiceCapability
            .definition
            .wireValue],
        StyioServiceCapabilityState.unavailable.name,
      );
    },
  );
}
