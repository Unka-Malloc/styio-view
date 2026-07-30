enum AdapterKind { cli, ffi, cloud }

extension AdapterKindX on AdapterKind {
  String get wireValue {
    switch (this) {
      case AdapterKind.cli:
        return 'cli';
      case AdapterKind.ffi:
        return 'ffi';
      case AdapterKind.cloud:
        return 'cloud';
    }
  }

  String get label {
    switch (this) {
      case AdapterKind.cli:
        return 'CLI Adapter';
      case AdapterKind.ffi:
        return 'FFI Adapter';
      case AdapterKind.cloud:
        return 'Cloud Adapter';
    }
  }
}

enum AdapterCapabilityLevel { available, partial, unavailable }

extension AdapterCapabilityLevelX on AdapterCapabilityLevel {
  String get label {
    switch (this) {
      case AdapterCapabilityLevel.available:
        return 'available';
      case AdapterCapabilityLevel.partial:
        return 'partial';
      case AdapterCapabilityLevel.unavailable:
        return 'unavailable';
    }
  }
}

class AdapterEndpointCapability {
  const AdapterEndpointCapability({
    required this.level,
    required this.detail,
    this.supportedContractVersions = const <int>[],
  });

  final AdapterCapabilityLevel level;
  final String detail;
  final List<int> supportedContractVersions;

  bool get isAvailable => level == AdapterCapabilityLevel.available;

  bool get isPartial => level == AdapterCapabilityLevel.partial;
}

class AdapterCapabilitySnapshot {
  const AdapterCapabilitySnapshot({
    required this.adapterKind,
    required this.languageService,
    required this.projectGraph,
    required this.execution,
    required this.runtimeEvents,
  });

  final AdapterKind adapterKind;
  final AdapterEndpointCapability languageService;
  final AdapterEndpointCapability projectGraph;
  final AdapterEndpointCapability execution;
  final AdapterEndpointCapability runtimeEvents;

  AdapterCapabilitySnapshot merge(AdapterCapabilitySnapshot other) {
    assert(
      adapterKind == other.adapterKind,
      'Cannot merge snapshots from different adapter kinds.',
    );
    return AdapterCapabilitySnapshot(
      adapterKind: adapterKind,
      languageService: _mergeEndpoint(languageService, other.languageService),
      projectGraph: _mergeEndpoint(projectGraph, other.projectGraph),
      execution: _mergeEndpoint(execution, other.execution),
      runtimeEvents: _mergeEndpoint(runtimeEvents, other.runtimeEvents),
    );
  }
}

AdapterCapabilitySnapshot mergeCapabilitySnapshots(
  Iterable<AdapterCapabilitySnapshot> snapshots,
) {
  final byKind = <AdapterKind, AdapterCapabilitySnapshot>{};
  for (final snapshot in snapshots) {
    final previous = byKind[snapshot.adapterKind];
    byKind[snapshot.adapterKind] = previous == null
        ? snapshot
        : previous.merge(snapshot);
  }

  final ordered = <AdapterCapabilitySnapshot>[];
  for (final kind in AdapterKind.values) {
    final snapshot = byKind[kind];
    if (snapshot != null) {
      ordered.add(snapshot);
    }
  }
  return ordered.isEmpty
      ? const AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cli,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No adapter capabilities resolved.',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No adapter capabilities resolved.',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No adapter capabilities resolved.',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'No adapter capabilities resolved.',
          ),
        )
      : ordered.first;
}

List<AdapterCapabilitySnapshot> normalizeCapabilitySnapshots(
  Iterable<AdapterCapabilitySnapshot> snapshots,
) {
  final byKind = <AdapterKind, AdapterCapabilitySnapshot>{};
  for (final snapshot in snapshots) {
    final previous = byKind[snapshot.adapterKind];
    byKind[snapshot.adapterKind] = previous == null
        ? snapshot
        : previous.merge(snapshot);
  }

  final ordered = <AdapterCapabilitySnapshot>[];
  for (final kind in AdapterKind.values) {
    final snapshot = byKind[kind];
    if (snapshot != null) {
      ordered.add(snapshot);
    }
  }
  return ordered;
}

AdapterCapabilitySnapshot buildFfiAdapterCapability({
  required bool visible,
  required bool executionSlotVisible,
  required String detail,
}) {
  return AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.ffi,
    languageService: AdapterEndpointCapability(
      level: visible
          ? AdapterCapabilityLevel.partial
          : AdapterCapabilityLevel.unavailable,
      detail: detail,
    ),
    projectGraph: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Project graph is not exposed through FFI yet.',
    ),
    execution: AdapterEndpointCapability(
      level: executionSlotVisible
          ? AdapterCapabilityLevel.partial
          : AdapterCapabilityLevel.unavailable,
      detail: detail,
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: executionSlotVisible
          ? AdapterCapabilityLevel.partial
          : AdapterCapabilityLevel.unavailable,
      detail:
          'Runtime event streaming remains reserved for future FFI modules.',
    ),
  );
}

AdapterCapabilitySnapshot buildCloudAdapterCapability({
  required bool supportsCloudExecution,
  required bool supportsHostedProjectGraph,
  required String detail,
}) {
  return AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cloud,
    languageService: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail:
          'Cloud language service remains a future route; local mock layers stay active today.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: supportsHostedProjectGraph
          ? AdapterCapabilityLevel.partial
          : AdapterCapabilityLevel.unavailable,
      detail: detail,
    ),
    execution: AdapterEndpointCapability(
      level: supportsCloudExecution
          ? AdapterCapabilityLevel.partial
          : AdapterCapabilityLevel.unavailable,
      detail: detail,
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: supportsCloudExecution
          ? AdapterCapabilityLevel.partial
          : AdapterCapabilityLevel.unavailable,
      detail:
          'Hosted/cloud runtime streams will flow through the same event envelope once published.',
    ),
  );
}

AdapterEndpointCapability _mergeEndpoint(
  AdapterEndpointCapability left,
  AdapterEndpointCapability right,
) {
  if (_rank(right.level) > _rank(left.level)) {
    return AdapterEndpointCapability(
      level: right.level,
      detail: right.detail,
      supportedContractVersions: _mergeVersions(
        left.supportedContractVersions,
        right.supportedContractVersions,
      ),
    );
  }

  return AdapterEndpointCapability(
    level: left.level,
    detail: left.detail.isEmpty ? right.detail : left.detail,
    supportedContractVersions: _mergeVersions(
      left.supportedContractVersions,
      right.supportedContractVersions,
    ),
  );
}

int _rank(AdapterCapabilityLevel level) {
  switch (level) {
    case AdapterCapabilityLevel.available:
      return 3;
    case AdapterCapabilityLevel.partial:
      return 2;
    case AdapterCapabilityLevel.unavailable:
      return 1;
  }
}

List<int> _mergeVersions(List<int> left, List<int> right) {
  final merged = <int>{...left, ...right}.toList()..sort();
  return merged;
}
