import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_provider_registry.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_capability_detector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_runtime.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('language service status surface projects ready runtime status', () {
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://status',
      revision: 1,
      toolchainId: 'styio-nightly',
      parserEngine: 'nightly',
      grammarVersion: '2026.05',
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
      cacheSnapshot: const StyioServiceResultCacheSnapshot(
        entries: <StyioServiceResultCacheEntry>[],
        lookupHits: 3,
        lookupMisses: 1,
      ),
      allowLocalFallback: false,
    );
    const providerReadiness = StyioLanguageProviderReadinessReport(
      coverage: <StyioLanguageProviderCapabilityCoverage>[
        StyioLanguageProviderCapabilityCoverage(
          capability: StyioLanguageProviderCapability.completion,
          providerIds: <String>['styio-service'],
        ),
        StyioLanguageProviderCapabilityCoverage(
          capability: StyioLanguageProviderCapability.rename,
          providerIds: <String>[],
        ),
      ],
    );

    final surface = LanguageServiceStatusSurface.fromRuntimeSnapshot(
      runtimeSnapshot,
      providerReadiness: providerReadiness,
    );

    expect(surface.severity, LanguageServiceStatusSeverity.ready);
    expect(surface.localFallbackEnabled, isFalse);
    expect(surface.toolchainId, 'styio-nightly');
    expect(surface.parserEngine, 'nightly');
    expect(surface.grammarVersion, '2026.05');
    expect(surface.usableCapabilityCount, 3);
    expect(surface.capabilityHealth, 'degraded');
    expect(surface.missingCapabilityCount, greaterThan(0));
    expect(surface.blockedCapabilityCount, 0);
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
    expect(surface.toJson()['parserEngine'], 'nightly');
    expect(surface.toJson()['grammarVersion'], '2026.05');
    expect(surface.toJson()['syntaxValidationReady'], isTrue);
    expect(surface.toJson()['semanticFactsReady'], isFalse);
    expect(surface.toJson()['canDriveIntelligentCoding'], isFalse);
    final capabilityProfile =
        surface.toJson()['capabilityProfile']! as Map<String, Object?>;
    expect(capabilityProfile['syntaxReady'], isTrue);
    expect(capabilityProfile['semanticReady'], isFalse);
    expect(capabilityProfile['canDriveIntelligentCoding'], isFalse);
    expect(surface.toJson()['capabilityHealth'], 'degraded');
    expect(surface.toJson()['missingCapabilityCount'], greaterThan(0));
    expect(surface.toJson()['providerReadiness'], 'degraded');
    expect(surface.toJson()['providerReadinessSummary'], contains('1/2'));
    expect(surface.toJson()['providerMissingCapabilityCount'], 1);
    expect(surface.cacheLookupHits, 3);
    expect(surface.cacheLookupMisses, 1);
    expect(surface.cacheLookupCount, 4);
    expect(surface.cacheLookupHitRate, 0.75);
    expect(surface.toJson()['cacheLookupHits'], 3);
    expect(surface.toJson()['cacheLookupMisses'], 1);
    expect(surface.toJson()['cacheLookupCount'], 4);
    expect(surface.toJson()['cacheLookupHitRate'], 0.75);
    expect(surface.toJson()['refreshRecommended'], isTrue);
    expect(
      surface.toJson()['unavailablePrimaryCapabilities'],
      contains(StyioServiceCapability.definition.wireValue),
    );
  });

  test('language service runtime status binds to runtime output events', () {
    const response = StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: 'fixture://status-output',
      revision: 1,
      toolchainId: 'styio-nightly',
      completions: <CompletionItem>[
        CompletionItem(
          label: 'value',
          kind: CompletionItemKind.variable,
          insertText: 'value',
        ),
      ],
    );
    final capabilitySnapshot = const StyioServiceCapabilityDetector().detect(
      response,
      expectedCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.diagnostics,
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
      ],
    );
    final runtimeSnapshot = StyioServiceRuntimeStatusSnapshot(
      state: StyioServiceRuntimeSessionState.active,
      disposed: false,
      providerManifest: LanguageProviderRegistry<String>().manifest(),
      capabilitySnapshot: capabilitySnapshot,
      allowLocalFallback: false,
      primaryCapabilities: const <StyioServiceCapability>[
        StyioServiceCapability.diagnostics,
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
      ],
    );

    final binding = StyioServiceRuntimeOutputBinding(snapshot: runtimeSnapshot);
    final outputSnapshot = binding.outputPanelSnapshot(
      timestamp: DateTime.utc(2026, 5, 20, 17),
    );

    expect(outputSnapshot.events, hasLength(4));
    expect(
      outputSnapshot.events.first.kind,
      RuntimeOutputChannelKind.languageService,
    );
    expect(outputSnapshot.events.first.metadata['usableCapabilityCount'], 2);
    expect(
      outputSnapshot.events.first.metadata['capabilityHealth'],
      'degraded',
    );
    expect(
      outputSnapshot.events.first.metadata['missingCapabilityCount'],
      greaterThan(0),
    );
    expect(outputSnapshot.events.first.metadata['cacheLookupCount'], 0);
    expect(outputSnapshot.events.first.metadata['allowLocalFallback'], isFalse);
    expect(outputSnapshot.events.first.message, contains('health degraded'));
    expect(
      outputSnapshot.events.map((event) => event.message),
      containsAll(<String>[
        'diagnostics available',
        'completion available',
        'hover empty',
      ]),
    );
    expect(binding.toJson()['outputEventCount'], 4);
    expect(binding.toJson()['capabilityHealth'], 'degraded');
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
    expect(surface.syntaxValidationReady, isTrue);
    expect(surface.semanticFactsReady, isFalse);
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
      expect(surface.refreshRecommended, isTrue);
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

  test(
    'language service status controller maps runtime events to surfaces',
    () async {
      final events = StreamController<StyioServiceRuntimeSessionEvent>(
        sync: true,
      );
      final controller = LanguageServiceStatusController(
        runtimeEvents: events.stream,
      );
      final severities = <LanguageServiceStatusSeverity>[];
      controller.listenable.addListener(() {
        severities.add(controller.value.severity);
      });

      events.add(
        StyioServiceRuntimeSessionEvent(
          state: StyioServiceRuntimeSessionState.refreshing,
        ),
      );

      expect(
        controller.value.severity,
        LanguageServiceStatusSeverity.refreshing,
      );

      const response = StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: 'fixture://controller-ready',
        revision: 1,
        toolchainId: 'styio-nightly',
        completions: <CompletionItem>[
          CompletionItem(
            label: 'value',
            kind: CompletionItemKind.variable,
            insertText: 'value',
          ),
        ],
      );
      final capabilitySnapshot = const StyioServiceCapabilityDetector().detect(
        response,
      );
      events.add(
        StyioServiceRuntimeSessionEvent(
          state: StyioServiceRuntimeSessionState.active,
          statusSnapshot: StyioServiceRuntimeStatusSnapshot(
            state: StyioServiceRuntimeSessionState.active,
            disposed: false,
            providerManifest: LanguageProviderRegistry<String>().manifest(),
            capabilitySnapshot: capabilitySnapshot,
          ),
        ),
      );

      expect(controller.value.severity, LanguageServiceStatusSeverity.ready);
      expect(controller.value.toolchainId, 'styio-nightly');
      expect(controller.value.usableCapabilityCount, greaterThan(0));
      expect(controller.value.providerReadiness, 'degraded');
      expect(controller.value.providerMissingCapabilityCount, greaterThan(0));
      expect(severities, <LanguageServiceStatusSeverity>[
        LanguageServiceStatusSeverity.refreshing,
        LanguageServiceStatusSeverity.ready,
      ]);

      await controller.dispose();
      await events.close();
    },
  );

  test(
    'language service status controller handles snapshotless failures',
    () async {
      final controller = LanguageServiceStatusController();

      controller.handleRuntimeEvent(
        StyioServiceRuntimeSessionEvent(
          state: StyioServiceRuntimeSessionState.failed,
        ),
      );

      expect(controller.value.severity, LanguageServiceStatusSeverity.failed);
      expect(controller.value.actionable, isTrue);
      await controller.dispose();
    },
  );
}
