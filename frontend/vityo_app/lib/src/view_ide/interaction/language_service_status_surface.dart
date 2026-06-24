import 'dart:async';

import 'package:flutter/foundation.dart';

import '../language/service/styio_language_provider_registry.dart';
import '../language/service/styio_service_capability_detector.dart';
import '../language/service/styio_service_capability_profile.dart';
import '../language/service/styio_service_runtime.dart';

enum LanguageServiceStatusSeverity {
  ready,
  refreshing,
  degraded,
  unavailable,
  failed,
}

class LanguageServiceCapabilityStatusItem {
  const LanguageServiceCapabilityStatusItem({
    required this.capability,
    required this.state,
    required this.usable,
    required this.fresh,
  });

  final String capability;
  final String state;
  final bool usable;
  final bool fresh;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capability': capability,
      'state': state,
      'usable': usable,
      'fresh': fresh,
    };
  }
}

class LanguageServiceStatusSurface {
  const LanguageServiceStatusSurface({
    required this.runtimeState,
    required this.severity,
    required this.title,
    required this.message,
    required this.usableCapabilityCount,
    required this.freshCapabilityCount,
    required this.primaryCapabilityStates,
    required this.capabilities,
    this.capabilityProfile,
    this.toolchainId = '',
    this.parserEngine,
    this.grammarVersion,
    this.localFallbackEnabled = true,
    this.capabilityHealth = 'unavailable',
    this.missingCapabilityCount = 0,
    this.blockedCapabilityCount = 0,
    this.providerReadiness = 'unknown',
    this.providerReadinessSummary = '',
    this.providerMissingCapabilityCount = 0,
    this.cacheLookupHits = 0,
    this.cacheLookupMisses = 0,
    this.cacheLookupCount = 0,
    this.cacheLookupHitRate = 0,
  });

  factory LanguageServiceStatusSurface.unavailable({
    String runtimeState = 'initialized',
    String message =
        'StyioService is not currently available for this session.',
  }) {
    return LanguageServiceStatusSurface(
      runtimeState: runtimeState,
      severity: LanguageServiceStatusSeverity.unavailable,
      title: 'StyioService unavailable',
      message: message,
      usableCapabilityCount: 0,
      freshCapabilityCount: 0,
      primaryCapabilityStates: _fallbackPrimaryStates(
        StyioServiceCapabilityState.unavailable,
      ),
      capabilities: const <LanguageServiceCapabilityStatusItem>[],
      localFallbackEnabled: true,
    );
  }

  factory LanguageServiceStatusSurface.refreshing() {
    return LanguageServiceStatusSurface(
      runtimeState: StyioServiceRuntimeSessionState.refreshing.name,
      severity: LanguageServiceStatusSeverity.refreshing,
      title: 'StyioService refreshing',
      message: 'StyioService is refreshing language facts.',
      usableCapabilityCount: 0,
      freshCapabilityCount: 0,
      primaryCapabilityStates: _fallbackPrimaryStates(
        StyioServiceCapabilityState.empty,
      ),
      capabilities: const <LanguageServiceCapabilityStatusItem>[],
      localFallbackEnabled: true,
    );
  }

  factory LanguageServiceStatusSurface.failed({
    String message = 'StyioService failed while refreshing language facts.',
  }) {
    return LanguageServiceStatusSurface(
      runtimeState: StyioServiceRuntimeSessionState.failed.name,
      severity: LanguageServiceStatusSeverity.failed,
      title: 'StyioService failed',
      message: message,
      usableCapabilityCount: 0,
      freshCapabilityCount: 0,
      primaryCapabilityStates: _fallbackPrimaryStates(
        StyioServiceCapabilityState.failed,
      ),
      capabilities: const <LanguageServiceCapabilityStatusItem>[],
      localFallbackEnabled: true,
    );
  }

  factory LanguageServiceStatusSurface.fromRuntimeSnapshot(
    StyioServiceRuntimeStatusSnapshot snapshot, {
    StyioLanguageProviderReadinessReport? providerReadiness,
  }) {
    final capabilitySnapshot = snapshot.capabilitySnapshot;
    final healthSummary = capabilitySnapshot?.healthSummary;
    final capabilityProfile = capabilitySnapshot == null
        ? null
        : StyioServiceCapabilityProfile.fromSnapshot(capabilitySnapshot);
    final severity = _severityFor(snapshot);
    final providerReady = providerReadiness?.ready;
    return LanguageServiceStatusSurface(
      runtimeState: snapshot.state.name,
      severity: severity,
      title: _titleFor(severity),
      message: _messageFor(snapshot, severity),
      toolchainId: capabilitySnapshot?.toolchainId ?? '',
      parserEngine: capabilitySnapshot?.parserEngine,
      grammarVersion: capabilitySnapshot?.grammarVersion,
      usableCapabilityCount: snapshot.usableCapabilityCount,
      freshCapabilityCount: snapshot.freshCapabilityCount,
      primaryCapabilityStates: snapshot.primaryCapabilityStates,
      capabilityProfile: capabilityProfile,
      localFallbackEnabled: snapshot.allowLocalFallback,
      capabilityHealth:
          healthSummary?.health.wireValue ??
          StyioServiceCapabilityHealth.unavailable.wireValue,
      missingCapabilityCount: healthSummary?.missingCapabilities.length ?? 0,
      blockedCapabilityCount: healthSummary?.blockedCapabilities.length ?? 0,
      providerReadiness: providerReady == null
          ? 'unknown'
          : providerReady
          ? 'ready'
          : 'degraded',
      providerReadinessSummary: providerReadiness?.summary ?? '',
      providerMissingCapabilityCount:
          providerReadiness?.missingCapabilities.length ?? 0,
      cacheLookupHits: snapshot.cacheLookupHits,
      cacheLookupMisses: snapshot.cacheLookupMisses,
      cacheLookupCount: snapshot.cacheLookupCount,
      cacheLookupHitRate: snapshot.cacheLookupHitRate,
      capabilities: capabilitySnapshot == null
          ? const <LanguageServiceCapabilityStatusItem>[]
          : snapshot.primaryCapabilities
                .map((capability) => capabilitySnapshot.statuses[capability])
                .nonNulls
                .map(_capabilityItem)
                .toList(growable: false),
    );
  }

  final String runtimeState;
  final LanguageServiceStatusSeverity severity;
  final String title;
  final String message;
  final String toolchainId;
  final String? parserEngine;
  final String? grammarVersion;
  final int usableCapabilityCount;
  final int freshCapabilityCount;
  final Map<String, String> primaryCapabilityStates;
  final List<LanguageServiceCapabilityStatusItem> capabilities;
  final StyioServiceCapabilityProfile? capabilityProfile;
  final bool localFallbackEnabled;
  final String capabilityHealth;
  final int missingCapabilityCount;
  final int blockedCapabilityCount;
  final String providerReadiness;
  final String providerReadinessSummary;
  final int providerMissingCapabilityCount;
  final int cacheLookupHits;
  final int cacheLookupMisses;
  final int cacheLookupCount;
  final double cacheLookupHitRate;

  bool get actionable {
    return severity == LanguageServiceStatusSeverity.unavailable ||
        severity == LanguageServiceStatusSeverity.failed;
  }

  bool get refreshRecommended {
    if (severity == LanguageServiceStatusSeverity.refreshing) {
      return false;
    }
    return severity != LanguageServiceStatusSeverity.ready ||
        capabilityHealth != StyioServiceCapabilityHealth.ready.wireValue ||
        missingCapabilityCount > 0 ||
        blockedCapabilityCount > 0 ||
        providerReadiness == 'degraded' ||
        providerMissingCapabilityCount > 0;
  }

  bool get syntaxValidationReady {
    return _stateUsable(
          primaryCapabilityStates[StyioServiceCapability.diagnostics.wireValue],
        ) ||
        _stateUsable(
          primaryCapabilityStates[StyioServiceCapability.syntax.wireValue],
        );
  }

  bool get semanticFactsReady {
    return _stateUsable(
          primaryCapabilityStates[StyioServiceCapability
              .semanticTokens
              .wireValue],
        ) ||
        _stateUsable(
          primaryCapabilityStates[StyioServiceCapability.definition.wireValue],
        ) ||
        _stateUsable(
          primaryCapabilityStates[StyioServiceCapability.references.wireValue],
        );
  }

  bool get canDriveIntelligentCoding {
    return capabilityProfile?.canDriveIntelligentCoding ?? semanticFactsReady;
  }

  List<String> get unavailablePrimaryCapabilities {
    return primaryCapabilityStates.entries
        .where((entry) => !_stateUsable(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'runtimeState': runtimeState,
      'severity': severity.name,
      'title': title,
      'message': message,
      if (toolchainId.isNotEmpty) 'toolchainId': toolchainId,
      if (parserEngine != null) 'parserEngine': parserEngine,
      if (grammarVersion != null) 'grammarVersion': grammarVersion,
      'usableCapabilityCount': usableCapabilityCount,
      'freshCapabilityCount': freshCapabilityCount,
      'localFallbackEnabled': localFallbackEnabled,
      'capabilityHealth': capabilityHealth,
      'missingCapabilityCount': missingCapabilityCount,
      'blockedCapabilityCount': blockedCapabilityCount,
      'providerReadiness': providerReadiness,
      if (providerReadinessSummary.isNotEmpty)
        'providerReadinessSummary': providerReadinessSummary,
      'providerMissingCapabilityCount': providerMissingCapabilityCount,
      'cacheLookupHits': cacheLookupHits,
      'cacheLookupMisses': cacheLookupMisses,
      'cacheLookupCount': cacheLookupCount,
      'cacheLookupHitRate': cacheLookupHitRate,
      'primaryCapabilityStates': primaryCapabilityStates,
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(growable: false),
      if (capabilityProfile != null)
        'capabilityProfile': capabilityProfile!.toJson(),
      'actionable': actionable,
      'refreshRecommended': refreshRecommended,
      'syntaxValidationReady': syntaxValidationReady,
      'semanticFactsReady': semanticFactsReady,
      'canDriveIntelligentCoding': canDriveIntelligentCoding,
      'unavailablePrimaryCapabilities': unavailablePrimaryCapabilities,
    };
  }

  static bool _stateUsable(String? state) {
    return state == StyioServiceCapabilityState.available.name ||
        state == StyioServiceCapabilityState.derived.name;
  }

  static LanguageServiceCapabilityStatusItem _capabilityItem(
    StyioServiceCapabilityStatus status,
  ) {
    return LanguageServiceCapabilityStatusItem(
      capability: status.capability.wireValue,
      state: status.state.name,
      usable: status.isUsable,
      fresh: status.hasFreshPayload,
    );
  }

  static LanguageServiceStatusSeverity _severityFor(
    StyioServiceRuntimeStatusSnapshot snapshot,
  ) {
    if (snapshot.state == StyioServiceRuntimeSessionState.failed) {
      return LanguageServiceStatusSeverity.failed;
    }
    if (snapshot.disposed ||
        snapshot.state == StyioServiceRuntimeSessionState.initialized) {
      return LanguageServiceStatusSeverity.unavailable;
    }
    if (snapshot.state == StyioServiceRuntimeSessionState.refreshing) {
      return LanguageServiceStatusSeverity.refreshing;
    }
    if (snapshot.usableCapabilityCount > 0) {
      return LanguageServiceStatusSeverity.ready;
    }
    return LanguageServiceStatusSeverity.degraded;
  }

  static String _titleFor(LanguageServiceStatusSeverity severity) {
    return switch (severity) {
      LanguageServiceStatusSeverity.ready => 'StyioService ready',
      LanguageServiceStatusSeverity.refreshing => 'StyioService refreshing',
      LanguageServiceStatusSeverity.degraded => 'StyioService degraded',
      LanguageServiceStatusSeverity.unavailable => 'StyioService unavailable',
      LanguageServiceStatusSeverity.failed => 'StyioService failed',
    };
  }

  static String _messageFor(
    StyioServiceRuntimeStatusSnapshot snapshot,
    LanguageServiceStatusSeverity severity,
  ) {
    return switch (severity) {
      LanguageServiceStatusSeverity.ready =>
        'StyioService has ${snapshot.usableCapabilityCount} usable capability result(s).',
      LanguageServiceStatusSeverity.refreshing =>
        'StyioService is refreshing language facts.',
      LanguageServiceStatusSeverity.degraded =>
        'StyioService responded without usable capability results.',
      LanguageServiceStatusSeverity.unavailable =>
        'StyioService is not currently available for this session.',
      LanguageServiceStatusSeverity.failed =>
        'StyioService failed while refreshing language facts.',
    };
  }

  static Map<String, String> _fallbackPrimaryStates(
    StyioServiceCapabilityState state,
  ) {
    return <String, String>{
      for (final capability in const <StyioServiceCapability>[
        StyioServiceCapability.diagnostics,
        StyioServiceCapability.completion,
        StyioServiceCapability.hover,
        StyioServiceCapability.parameterInfo,
        StyioServiceCapability.definition,
        StyioServiceCapability.semanticTokens,
      ])
        capability.wireValue: state.name,
    };
  }
}

class LanguageServiceStatusController {
  LanguageServiceStatusController({
    LanguageServiceStatusSurface? initialStatus,
    ValueNotifier<LanguageServiceStatusSurface>? notifier,
    Stream<StyioServiceRuntimeSessionEvent>? runtimeEvents,
  }) : notifier =
           notifier ??
           ValueNotifier<LanguageServiceStatusSurface>(
             initialStatus ?? LanguageServiceStatusSurface.unavailable(),
           ),
       _ownsNotifier = notifier == null {
    if (runtimeEvents != null) {
      bindRuntimeEvents(runtimeEvents);
    }
  }

  final ValueNotifier<LanguageServiceStatusSurface> notifier;
  final bool _ownsNotifier;
  StreamSubscription<StyioServiceRuntimeSessionEvent>? _runtimeSubscription;

  ValueListenable<LanguageServiceStatusSurface> get listenable => notifier;

  LanguageServiceStatusSurface get value => notifier.value;

  StreamSubscription<StyioServiceRuntimeSessionEvent> bindRuntimeEvents(
    Stream<StyioServiceRuntimeSessionEvent> events,
  ) {
    _runtimeSubscription?.cancel();
    return _runtimeSubscription = events.listen(handleRuntimeEvent);
  }

  void handleRuntimeEvent(StyioServiceRuntimeSessionEvent event) {
    notifier.value = surfaceForRuntimeEvent(event);
  }

  static LanguageServiceStatusSurface surfaceForRuntimeEvent(
    StyioServiceRuntimeSessionEvent event, {
    StyioLanguageProviderReadinessReport? providerReadiness,
  }) {
    final snapshot = event.statusSnapshot;
    if (snapshot != null) {
      return LanguageServiceStatusSurface.fromRuntimeSnapshot(
        snapshot,
        providerReadiness:
            providerReadiness ?? _providerReadinessForSnapshot(snapshot),
      );
    }
    return switch (event.state) {
      StyioServiceRuntimeSessionState.refreshing =>
        LanguageServiceStatusSurface.refreshing(),
      StyioServiceRuntimeSessionState.failed =>
        LanguageServiceStatusSurface.failed(),
      StyioServiceRuntimeSessionState.disposed =>
        LanguageServiceStatusSurface.unavailable(
          runtimeState: StyioServiceRuntimeSessionState.disposed.name,
          message: 'StyioService runtime session has been disposed.',
        ),
      StyioServiceRuntimeSessionState.initialized ||
      StyioServiceRuntimeSessionState.active =>
        LanguageServiceStatusSurface.unavailable(
          runtimeState: event.state.name,
        ),
    };
  }

  static StyioLanguageProviderReadinessReport? _providerReadinessForSnapshot(
    StyioServiceRuntimeStatusSnapshot snapshot,
  ) {
    final capabilitySnapshot = snapshot.capabilitySnapshot;
    if (capabilitySnapshot == null) {
      return null;
    }
    final plan = StyioLanguageProviderBindingPlan.fromStyioServiceSnapshot(
      snapshot: capabilitySnapshot,
    );
    return StyioLanguageProviderReadinessReport.fromProviderCapabilities(
      providerId: plan.providerId,
      providedCapabilities: plan.capabilities,
    );
  }

  Future<void> dispose() async {
    await _runtimeSubscription?.cancel();
    _runtimeSubscription = null;
    if (_ownsNotifier) {
      notifier.dispose();
    }
  }
}
