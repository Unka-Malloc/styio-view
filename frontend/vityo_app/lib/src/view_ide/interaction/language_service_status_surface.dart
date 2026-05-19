import '../language/service/styio_service_capability_detector.dart';
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
    this.toolchainId = '',
    this.parserEngine,
    this.grammarVersion,
    this.localFallbackEnabled = true,
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
    StyioServiceRuntimeStatusSnapshot snapshot,
  ) {
    final capabilitySnapshot = snapshot.capabilitySnapshot;
    final severity = _severityFor(snapshot);
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
      localFallbackEnabled: snapshot.allowLocalFallback,
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
  final bool localFallbackEnabled;

  bool get actionable {
    return severity == LanguageServiceStatusSeverity.unavailable ||
        severity == LanguageServiceStatusSeverity.failed;
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
      'primaryCapabilityStates': primaryCapabilityStates,
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(growable: false),
      'actionable': actionable,
    };
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
