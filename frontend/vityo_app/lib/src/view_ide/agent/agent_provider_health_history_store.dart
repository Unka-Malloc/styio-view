import '../foundation/foundation.dart';
import 'agent_provider_route_executor.dart';

class AgentProviderHealthHistory {
  const AgentProviderHealthHistory({
    required this.workspaceId,
    this.reports = const <AgentProviderServiceHealthReport>[],
    this.updatedAt,
  });

  factory AgentProviderHealthHistory.fromJson(Map<String, Object?> json) {
    return AgentProviderHealthHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      reports: _jsonHealthReports(json['reports']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<AgentProviderServiceHealthReport> reports;
  final DateTime? updatedAt;

  AgentProviderServiceHealthReport? latestFor(String profileId) {
    for (final report in reports) {
      if (report.profileId == profileId) {
        return report;
      }
    }
    return null;
  }

  AgentProviderHealthHistory append(
    AgentProviderServiceHealthReport report, {
    int maxEntries = 30,
  }) {
    final nextReports = <AgentProviderServiceHealthReport>[
      report,
      ...reports,
    ].take(maxEntries).toList(growable: false);
    return copyWith(reports: nextReports, updatedAt: DateTime.now().toUtc());
  }

  AgentProviderHealthHistory copyWith({
    String? workspaceId,
    List<AgentProviderServiceHealthReport>? reports,
    DateTime? updatedAt,
  }) {
    return AgentProviderHealthHistory(
      workspaceId: workspaceId ?? this.workspaceId,
      reports: reports ?? this.reports,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'reportCount': reports.length,
      'reports': reports.map((report) => report.toJson()).toList(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class AgentProviderHealthHistoryStore {
  AgentProviderHealthHistoryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'service.remote-service.health-history',
             layer: 'service',
             stateFamily: 'remote-service-health',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const AgentProviderHealthHistoryStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'service.remote-service.health-history';
  static const String _key = 'reports';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(AgentProviderHealthHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<AgentProviderHealthHistory> readHistory({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return AgentProviderHealthHistory(workspaceId: workspaceId);
    }
    final history = AgentProviderHealthHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? history.copyWith(workspaceId: workspaceId)
        : history;
  }

  Future<AgentProviderHealthHistory> appendReport({
    required String workspaceId,
    required AgentProviderServiceHealthReport report,
    int maxEntries = 30,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(report, maxEntries: maxEntries);
    await saveHistory(next);
    return next;
  }

  Future<bool> deleteHistory({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchHistory({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<AgentProviderServiceHealthReport> _jsonHealthReports(Object? value) {
  if (value is! List) {
    return const <AgentProviderServiceHealthReport>[];
  }
  return value
      .whereType<Map>()
      .map(
        (report) => _healthReportFromJson(
          report.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

AgentProviderServiceHealthReport _healthReportFromJson(
  Map<String, Object?> json,
) {
  return AgentProviderServiceHealthReport(
    profileId: json['profileId'] as String? ?? '',
    status: _healthStatusFromWire(json['status']),
    endpointCount: json['endpointCount'] as int? ?? 0,
    blockedEndpointCount: json['blockedEndpointCount'] as int? ?? 0,
    missingCredentialCount: json['missingCredentialCount'] as int? ?? 0,
    unreachableEndpointCount: json['unreachableEndpointCount'] as int? ?? 0,
    fallbackActive: json['fallbackActive'] as bool? ?? false,
    message: json['message'] as String? ?? '',
    selectedEndpointIndex: json['selectedEndpointIndex'] as int?,
  );
}

AgentProviderServiceHealthStatus _healthStatusFromWire(Object? value) {
  return switch (value) {
    'ready' => AgentProviderServiceHealthStatus.ready,
    'degraded' => AgentProviderServiceHealthStatus.degraded,
    'blocked' => AgentProviderServiceHealthStatus.blocked,
    _ => AgentProviderServiceHealthStatus.blocked,
  };
}
