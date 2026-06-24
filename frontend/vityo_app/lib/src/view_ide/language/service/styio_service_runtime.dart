import 'dart:async';

import '../../editor/document_state.dart';
import '../../environment/configuration/language_service_configuration.dart';
import '../../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../../foundation/foundation.dart';
import '../../runtime/runtime.dart';
import '../../toolchain/toolchain.dart';
import 'capability_routed_styio_language_service.dart';
import 'language_service_foundation.dart';
import 'local_styio_language_service.dart';
import 'project_document_rule_registry.dart';
import 'project_styio_document_service.dart';
import 'project_styio_language_service.dart';
import 'styio_language_service.dart';
import 'styio_service_capability_detector.dart';
import 'styio_service_connector.dart';
import 'styio_service_manager_connector.dart';
import 'styio_service_project_document_rule_provider.dart';

enum StyioServiceRuntimeSessionState {
  initialized,
  refreshing,
  active,
  failed,
  disposed,
}

class StyioServiceRuntimeStatusSnapshot {
  const StyioServiceRuntimeStatusSnapshot({
    required this.state,
    required this.disposed,
    required this.providerManifest,
    this.capabilitySnapshot,
    this.cacheSnapshot,
    this.allowLocalFallback = true,
    this.primaryCapabilities = const <StyioServiceCapability>[
      StyioServiceCapability.diagnostics,
      StyioServiceCapability.completion,
      StyioServiceCapability.hover,
      StyioServiceCapability.parameterInfo,
      StyioServiceCapability.definition,
      StyioServiceCapability.semanticTokens,
    ],
  });

  final StyioServiceRuntimeSessionState state;
  final bool disposed;
  final LanguageProviderRegistryManifest providerManifest;
  final StyioServiceCapabilitySnapshot? capabilitySnapshot;
  final StyioServiceResultCacheSnapshot? cacheSnapshot;
  final bool allowLocalFallback;
  final Iterable<StyioServiceCapability> primaryCapabilities;

  StyioServiceCapabilityState stateOf(StyioServiceCapability capability) {
    final snapshot = capabilitySnapshot;
    if (snapshot == null) {
      return disposed
          ? StyioServiceCapabilityState.unavailable
          : StyioServiceCapabilityState.empty;
    }
    return snapshot.stateOf(capability);
  }

  int get usableCapabilityCount {
    if (capabilitySnapshot == null) {
      return 0;
    }
    return primaryCapabilities
        .where((capability) => _isUsableState(stateOf(capability)))
        .length;
  }

  int get freshCapabilityCount {
    if (capabilitySnapshot == null) {
      return 0;
    }
    return primaryCapabilities
        .where(
          (capability) =>
              stateOf(capability) == StyioServiceCapabilityState.available,
        )
        .length;
  }

  String get capabilityHealth {
    return capabilitySnapshot?.healthSummary.health.wireValue ??
        StyioServiceCapabilityHealth.unavailable.wireValue;
  }

  int get missingCapabilityCount {
    return capabilitySnapshot?.healthSummary.missingCapabilities.length ?? 0;
  }

  int get blockedCapabilityCount {
    return capabilitySnapshot?.healthSummary.blockedCapabilities.length ?? 0;
  }

  int get cacheLookupHits => cacheSnapshot?.lookupHits ?? 0;
  int get cacheLookupMisses => cacheSnapshot?.lookupMisses ?? 0;
  int get cacheLookupCount => cacheSnapshot?.lookupCount ?? 0;
  double get cacheLookupHitRate => cacheSnapshot?.lookupHitRate ?? 0;

  Map<String, String> get primaryCapabilityStates {
    return <String, String>{
      for (final capability in primaryCapabilities)
        capability.wireValue: stateOf(capability).name,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'disposed': disposed,
      'allowLocalFallback': allowLocalFallback,
      'usableCapabilityCount': usableCapabilityCount,
      'freshCapabilityCount': freshCapabilityCount,
      'capabilityHealth': capabilityHealth,
      'missingCapabilityCount': missingCapabilityCount,
      'blockedCapabilityCount': blockedCapabilityCount,
      'cacheLookupHits': cacheLookupHits,
      'cacheLookupMisses': cacheLookupMisses,
      'cacheLookupCount': cacheLookupCount,
      'cacheLookupHitRate': cacheLookupHitRate,
      'primaryCapabilityStates': primaryCapabilityStates,
      'providerManifest': providerManifest.toJson(),
      if (capabilitySnapshot != null)
        'capabilitySnapshot': capabilitySnapshot!.toJson(),
      if (cacheSnapshot != null) 'cacheSnapshot': cacheSnapshot!.toJson(),
    };
  }
}

class StyioServiceRuntimeOutputBinding {
  const StyioServiceRuntimeOutputBinding({required this.snapshot});

  final StyioServiceRuntimeStatusSnapshot snapshot;

  List<RuntimeOutputEvent> runtimeOutputEvents({
    DateTime? timestamp,
    String channelId = 'language-service.styio',
    String label = 'Styio Language Service',
  }) {
    final resolvedTimestamp = timestamp ?? DateTime.now().toUtc();
    return <RuntimeOutputEvent>[
      RuntimeOutputEvent(
        channelId: channelId,
        label: label,
        kind: RuntimeOutputChannelKind.languageService,
        message:
            'StyioService ${snapshot.state.name}: ${snapshot.usableCapabilityCount} usable primary capability/capabilities; health ${snapshot.capabilityHealth}.',
        timestamp: resolvedTimestamp,
        metadata: <String, Object?>{
          'state': snapshot.state.name,
          'disposed': snapshot.disposed,
          'allowLocalFallback': snapshot.allowLocalFallback,
          'usableCapabilityCount': snapshot.usableCapabilityCount,
          'freshCapabilityCount': snapshot.freshCapabilityCount,
          'capabilityHealth': snapshot.capabilityHealth,
          'missingCapabilityCount': snapshot.missingCapabilityCount,
          'blockedCapabilityCount': snapshot.blockedCapabilityCount,
          'cacheLookupHits': snapshot.cacheLookupHits,
          'cacheLookupMisses': snapshot.cacheLookupMisses,
          'cacheLookupCount': snapshot.cacheLookupCount,
          'cacheLookupHitRate': snapshot.cacheLookupHitRate,
          'providerCount': snapshot.providerManifest.entries.length,
        },
      ),
      for (final entry in snapshot.primaryCapabilityStates.entries)
        RuntimeOutputEvent(
          channelId: '$channelId.${entry.key}',
          label: '$label ${entry.key}',
          kind: RuntimeOutputChannelKind.languageService,
          message: '${entry.key} ${entry.value}',
          timestamp: resolvedTimestamp,
          metadata: <String, Object?>{
            'state': snapshot.state.name,
            'capability': entry.key,
            'capabilityState': entry.value,
            'usable': _isUsableState(
              StyioServiceCapabilityState.values.firstWhere(
                (state) => state.name == entry.value,
                orElse: () => StyioServiceCapabilityState.empty,
              ),
            ),
          },
        ),
    ];
  }

  RuntimeOutputPanelSnapshot outputPanelSnapshot({
    DateTime? timestamp,
    String channelId = 'language-service.styio',
    String label = 'Styio Language Service',
    RuntimeOutputChannelFilterState filter =
        const RuntimeOutputChannelFilterState(),
  }) {
    return RuntimeOutputPanelSnapshot(
      events: runtimeOutputEvents(
        timestamp: timestamp,
        channelId: channelId,
        label: label,
      ),
      filter: filter,
    );
  }

  Map<String, Object?> toJson() {
    final outputSnapshot = outputPanelSnapshot();
    return <String, Object?>{
      'state': snapshot.state.name,
      'usableCapabilityCount': snapshot.usableCapabilityCount,
      'freshCapabilityCount': snapshot.freshCapabilityCount,
      'capabilityHealth': snapshot.capabilityHealth,
      'missingCapabilityCount': snapshot.missingCapabilityCount,
      'blockedCapabilityCount': snapshot.blockedCapabilityCount,
      'cacheLookupHits': snapshot.cacheLookupHits,
      'cacheLookupMisses': snapshot.cacheLookupMisses,
      'cacheLookupCount': snapshot.cacheLookupCount,
      'cacheLookupHitRate': snapshot.cacheLookupHitRate,
      'outputEventCount': outputSnapshot.events.length,
      'outputSnapshot': outputSnapshot.toJson(),
    };
  }
}

bool _isUsableState(StyioServiceCapabilityState state) {
  return state == StyioServiceCapabilityState.available ||
      state == StyioServiceCapabilityState.derived;
}

class StyioServiceRuntimeSessionEvent {
  StyioServiceRuntimeSessionEvent({
    required this.state,
    this.lastResult,
    this.statusSnapshot,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final StyioServiceRuntimeSessionState state;
  final StyioServiceCapabilityNegotiationResult<Object?>? lastResult;
  final StyioServiceRuntimeStatusSnapshot? statusSnapshot;
  final DateTime emittedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      if (lastResult != null) 'lastResult': lastResult!.toJson(),
      if (statusSnapshot != null) 'statusSnapshot': statusSnapshot!.toJson(),
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

class StyioServiceRuntimeSession<T> {
  StyioServiceRuntimeSession({
    required StyioServiceAnalysisDriver driver,
    required LanguageProviderRegistry<T> registry,
    required String languageId,
    required String providerId,
    required String displayName,
    required T provider,
    int priority = 100,
    bool includeDerived = true,
    Iterable<StyioServiceCapability> expectedCapabilities =
        StyioServiceCapability.values,
    LanguageProviderRegistryManifestStore? providerManifestStore,
    String providerManifestKey = 'styio-service-providers',
    FoundationResourceScope providerManifestScope =
        FoundationResourceScope.user,
    String? providerManifestWorkspaceId,
    bool allowLocalFallback = true,
  }) : _registry = registry,
       _allowLocalFallback = allowLocalFallback,
       _capabilitySession = StyioServiceCapabilitySession<T>(
         driver: driver,
         registry: registry,
         languageId: languageId,
         providerId: providerId,
         displayName: displayName,
         provider: provider,
         priority: priority,
         includeDerived: includeDerived,
         expectedCapabilities: expectedCapabilities,
         manifestStore: providerManifestStore,
         manifestKey: providerManifestKey,
         manifestScope: providerManifestScope,
         manifestWorkspaceId: providerManifestWorkspaceId,
       );

  final LanguageProviderRegistry<T> _registry;
  final bool _allowLocalFallback;
  final StyioServiceCapabilitySession<T> _capabilitySession;
  final StreamController<StyioServiceRuntimeSessionEvent> _events =
      StreamController<StyioServiceRuntimeSessionEvent>.broadcast(sync: true);

  StyioServiceRuntimeSessionState _state =
      StyioServiceRuntimeSessionState.initialized;

  StyioServiceRuntimeSessionState get state => _state;

  bool get disposed => _state == StyioServiceRuntimeSessionState.disposed;

  StyioServiceCapabilityNegotiationResult<T>? get lastResult =>
      _capabilitySession.lastResult;

  LanguageProviderRegistryManifest get providerManifest => _registry.manifest();

  StyioServiceRuntimeStatusSnapshot get statusSnapshot {
    final result = lastResult;
    return StyioServiceRuntimeStatusSnapshot(
      state: state,
      disposed: disposed,
      providerManifest: providerManifest,
      allowLocalFallback: _allowLocalFallback,
      capabilitySnapshot: result == null
          ? null
          : const StyioServiceCapabilityDetector().detectReport(result.report),
      cacheSnapshot: result?.report.cacheSnapshot,
    );
  }

  Stream<StyioServiceRuntimeSessionEvent> get events => _events.stream;

  Future<StyioServiceCapabilityNegotiationResult<T>> refresh(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
  }) async {
    if (disposed) {
      throw StateError('StyioService runtime session is disposed.');
    }
    _state = StyioServiceRuntimeSessionState.refreshing;
    _emit();
    try {
      final result = await _capabilitySession.refresh(
        document,
        filePath: filePath,
        configPath: configPath,
        workingDirectory: workingDirectory,
      );
      _state = StyioServiceRuntimeSessionState.active;
      _emit();
      return result;
    } catch (_) {
      _state = StyioServiceRuntimeSessionState.failed;
      _emit();
      rethrow;
    }
  }

  Future<bool> dispose() async {
    if (disposed) {
      return false;
    }
    final unregistered = await _capabilitySession.dispose();
    _state = StyioServiceRuntimeSessionState.disposed;
    _emit();
    await _events.close();
    return unregistered;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'disposed': disposed,
      'providerManifest': providerManifest.toJson(),
      'statusSnapshot': statusSnapshot.toJson(),
      if (lastResult != null) 'lastResult': lastResult!.toJson(),
    };
  }

  void _emit() {
    if (_events.isClosed) {
      return;
    }
    final result = lastResult;
    _events.add(
      StyioServiceRuntimeSessionEvent(
        state: state,
        lastResult: result == null
            ? null
            : result as StyioServiceCapabilityNegotiationResult<Object?>,
        statusSnapshot: statusSnapshot,
      ),
    );
  }
}

CapabilityRoutedStyioLanguageService createRoutedStyioLanguageService({
  required StyioServiceResultCache resultCache,
  LocalStyioLanguageService localService = const LocalStyioLanguageService(),
  String protocolVersion = 'styio-cli-jsonl-v1',
  String toolchainId = '',
  String? configPath,
  String? workingDirectory,
  LanguageServiceConfiguration? languageServiceConfiguration,
  bool allowLocalFallback = true,
}) {
  final resolvedAllowLocalFallback =
      languageServiceConfiguration?.allowLocalFallback ?? allowLocalFallback;
  final cachedService = CachedStyioLanguageService(
    cache: resultCache,
    localService: localService,
    protocolVersion: protocolVersion,
    toolchainId: toolchainId,
    configPath: configPath,
    workingDirectory: workingDirectory,
    allowLocalFallback: resolvedAllowLocalFallback,
  );
  final registry = LanguageProviderRegistry<StyioLanguageService>()
    ..register(
      LanguageProviderRegistration<StyioLanguageService>(
        descriptor: LanguageProviderDescriptor(
          languageId: 'styio',
          providerId: 'cached-styio-service',
          displayName: 'Cached StyioService',
          priority: 100,
          capabilities: <String>{
            for (final capability in StyioServiceCapability.values)
              capability.wireValue,
          },
        ),
        provider: cachedService,
      ),
    );
  return CapabilityRoutedStyioLanguageService(
    registry: registry,
    fallback: localService,
  );
}

ProjectStyioLanguageService createRoutedProjectStyioLanguageService({
  required StyioServiceResultCache resultCache,
  LocalStyioLanguageService localService = const LocalStyioLanguageService(),
  String protocolVersion = 'styio-cli-jsonl-v1',
  String toolchainId = '',
  String? configPath,
  String? workingDirectory,
  StyioProjectAnalysisCache? analysisCache,
  LanguageServiceConfiguration? languageServiceConfiguration,
  bool allowLocalFallback = true,
}) {
  final resolvedAllowLocalFallback =
      languageServiceConfiguration?.allowLocalFallback ?? allowLocalFallback;
  final routedDocumentService = createRoutedStyioLanguageService(
    resultCache: resultCache,
    localService: localService,
    protocolVersion: protocolVersion,
    toolchainId: toolchainId,
    configPath: configPath,
    workingDirectory: workingDirectory,
    languageServiceConfiguration: languageServiceConfiguration,
    allowLocalFallback: resolvedAllowLocalFallback,
  );
  return ProjectStyioLanguageService(
    documentService: ProjectStyioDocumentService(
      currentService: routedDocumentService,
      projectRuleProvider: ProjectDocumentRuleRegistry(
        registrations: <ProjectDocumentRuleRegistration>[
          ProjectDocumentRuleRegistration(
            descriptor: const ProjectDocumentRuleProviderDescriptor(
              providerId: 'cached-styio-service-project-rules',
              displayName: 'Cached StyioService project rules',
              priority: 100,
            ),
            provider: StyioServiceProjectDocumentRuleProvider(
              cache: resultCache,
              protocolVersion: protocolVersion,
              toolchainId: toolchainId,
              configPath: configPath,
              workingDirectory: workingDirectory,
            ),
          ),
          if (resolvedAllowLocalFallback)
            ...ProjectDocumentRuleRegistry.current.registrations,
        ],
      ),
    ),
    analysisCache: analysisCache,
    allowLocalProjectFallback: resolvedAllowLocalFallback,
  );
}

Future<StyioServiceAnalysisDriver> createPlatformStyioServiceAnalysisDriver({
  required StyioServiceResultCache resultCache,
  ToolchainManager? toolchainManager,
}) async {
  if (toolchainManager != null) {
    return StyioServiceAnalysisDriver(
      connector: ToolchainManagerStyioServiceConnector(
        manager: toolchainManager,
      ),
      resultCache: resultCache,
    );
  }
  final catalog = await createPlatformStyioLanguageToolchainCatalog();
  final platformManagers = await createDetectedPlatformManagerBundle();
  final runtime = ToolchainRuntime.fromPlatformManagers(
    catalog: catalog,
    platformManagers: platformManagers,
  );
  return StyioServiceAnalysisDriver(
    connector: ToolchainStyioServiceConnector(runtime: runtime),
    resultCache: resultCache,
  );
}
