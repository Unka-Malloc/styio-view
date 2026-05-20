import '../foundation/foundation.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';

enum AgentCodingSessionOutcome { succeeded, failed, cancelled }

extension AgentCodingSessionOutcomeX on AgentCodingSessionOutcome {
  String get wireValue => switch (this) {
    AgentCodingSessionOutcome.succeeded => 'succeeded',
    AgentCodingSessionOutcome.failed => 'failed',
    AgentCodingSessionOutcome.cancelled => 'cancelled',
  };
}

enum AgentCodingSessionCheckpointStatus { empty, ready, needsRecovery }

extension AgentCodingSessionCheckpointStatusX
    on AgentCodingSessionCheckpointStatus {
  String get wireValue => switch (this) {
    AgentCodingSessionCheckpointStatus.empty => 'empty',
    AgentCodingSessionCheckpointStatus.ready => 'ready',
    AgentCodingSessionCheckpointStatus.needsRecovery => 'needsRecovery',
  };
}

class AgentCodingSessionHistoryRecord {
  const AgentCodingSessionHistoryRecord({
    required this.requestId,
    required this.profileId,
    required this.providerKind,
    required this.prompt,
    required this.outcome,
    required this.createdAt,
    required this.completedAt,
    this.responseTextSample = '',
    this.contentPartCount = 0,
    this.patchCount = 0,
    this.ideCommandCount = 0,
    this.planCount = 0,
    this.diagnosticSummaryCount = 0,
    this.errorMessage,
    this.metadata = const <String, Object?>{},
  });

  factory AgentCodingSessionHistoryRecord.fromJson(Map<String, Object?> json) {
    return AgentCodingSessionHistoryRecord(
      requestId: json['requestId'] as String? ?? '',
      profileId: json['profileId'] as String? ?? '',
      providerKind: json['providerKind'] as String? ?? '',
      prompt: json['prompt'] as String? ?? '',
      outcome: _agentCodingSessionOutcomeFromWire(json['outcome'] as String?),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      responseTextSample: json['responseTextSample'] as String? ?? '',
      contentPartCount: json['contentPartCount'] as int? ?? 0,
      patchCount: json['patchCount'] as int? ?? 0,
      ideCommandCount: json['ideCommandCount'] as int? ?? 0,
      planCount: json['planCount'] as int? ?? 0,
      diagnosticSummaryCount: json['diagnosticSummaryCount'] as int? ?? 0,
      errorMessage: json['errorMessage'] as String?,
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  factory AgentCodingSessionHistoryRecord.fromResponse({
    required AgentPromptProfile profile,
    required AgentProviderKind providerKind,
    required String prompt,
    required AgentProviderResponseEnvelope response,
    required DateTime createdAt,
    required DateTime completedAt,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final contentParts = response.contentParts;
    return AgentCodingSessionHistoryRecord(
      requestId: response.requestId,
      profileId: profile.profileId,
      providerKind: providerKind.wireValue,
      prompt: prompt,
      outcome: AgentCodingSessionOutcome.succeeded,
      createdAt: createdAt.toUtc(),
      completedAt: completedAt.toUtc(),
      responseTextSample: _responseTextSample(contentParts),
      contentPartCount: contentParts.length,
      patchCount: contentParts.where((part) => part.patch != null).length,
      ideCommandCount: contentParts
          .where((part) => part.ideCommand != null)
          .length,
      planCount: contentParts.where((part) => part.plan != null).length,
      diagnosticSummaryCount: contentParts
          .where((part) => part.diagnosticSummary != null)
          .length,
      metadata: <String, Object?>{
        ...metadata,
        'finishReason': response.finishReason,
        if (response.providerMessageId != null)
          'providerMessageId': response.providerMessageId,
        if (response.usage != null) 'usage': response.usage,
      },
    );
  }

  factory AgentCodingSessionHistoryRecord.failure({
    required String requestId,
    required AgentPromptProfile profile,
    required AgentProviderKind providerKind,
    required String prompt,
    required String errorMessage,
    required DateTime createdAt,
    required DateTime completedAt,
    AgentCodingSessionOutcome outcome = AgentCodingSessionOutcome.failed,
  }) {
    return AgentCodingSessionHistoryRecord(
      requestId: requestId,
      profileId: profile.profileId,
      providerKind: providerKind.wireValue,
      prompt: prompt,
      outcome: outcome,
      createdAt: createdAt.toUtc(),
      completedAt: completedAt.toUtc(),
      errorMessage: errorMessage,
    );
  }

  final String requestId;
  final String profileId;
  final String providerKind;
  final String prompt;
  final AgentCodingSessionOutcome outcome;
  final DateTime createdAt;
  final DateTime completedAt;
  final String responseTextSample;
  final int contentPartCount;
  final int patchCount;
  final int ideCommandCount;
  final int planCount;
  final int diagnosticSummaryCount;
  final String? errorMessage;
  final Map<String, Object?> metadata;

  bool get succeeded => outcome == AgentCodingSessionOutcome.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestId': requestId,
      'profileId': profileId,
      'providerKind': providerKind,
      'prompt': prompt,
      'outcome': outcome.wireValue,
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt.toIso8601String(),
      'succeeded': succeeded,
      'responseTextSample': responseTextSample,
      'contentPartCount': contentPartCount,
      'patchCount': patchCount,
      'ideCommandCount': ideCommandCount,
      'planCount': planCount,
      'diagnosticSummaryCount': diagnosticSummaryCount,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentCodingSessionCheckpoint {
  const AgentCodingSessionCheckpoint({
    required this.workspaceId,
    required this.status,
    required this.updatedAt,
    required this.recordCount,
    this.latestRequestId,
    this.latestProfileId,
    this.latestProviderKind,
    this.latestOutcome,
    this.latestCompletedAt,
    this.recoveryTodo,
  });

  factory AgentCodingSessionCheckpoint.fromHistory(
    AgentCodingSessionHistory history,
  ) {
    final latest = history.records.isEmpty ? null : history.records.first;
    final latestOutcome = latest?.outcome;
    final needsRecovery =
        latestOutcome == AgentCodingSessionOutcome.failed ||
        latestOutcome == AgentCodingSessionOutcome.cancelled;
    return AgentCodingSessionCheckpoint(
      workspaceId: history.workspaceId,
      status: latest == null
          ? AgentCodingSessionCheckpointStatus.empty
          : needsRecovery
          ? AgentCodingSessionCheckpointStatus.needsRecovery
          : AgentCodingSessionCheckpointStatus.ready,
      updatedAt: history.updatedAt,
      recordCount: history.records.length,
      latestRequestId: latest?.requestId,
      latestProfileId: latest?.profileId,
      latestProviderKind: latest?.providerKind,
      latestOutcome: latestOutcome,
      latestCompletedAt: latest?.completedAt,
      recoveryTodo: needsRecovery
          ? 'TODO: route this checkpoint into provider retry, failover, or replay controls before resuming unrelated agent work.'
          : null,
    );
  }

  factory AgentCodingSessionCheckpoint.fromJson(Map<String, Object?> json) {
    return AgentCodingSessionCheckpoint(
      workspaceId: json['workspaceId'] as String? ?? '',
      status: _agentCodingSessionCheckpointStatusFromWire(
        json['status'] as String?,
      ),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      recordCount: json['recordCount'] as int? ?? 0,
      latestRequestId: json['latestRequestId'] as String?,
      latestProfileId: json['latestProfileId'] as String?,
      latestProviderKind: json['latestProviderKind'] as String?,
      latestOutcome: json['latestOutcome'] == null
          ? null
          : _agentCodingSessionOutcomeFromWire(
              json['latestOutcome'] as String?,
            ),
      latestCompletedAt: DateTime.tryParse(
        json['latestCompletedAt'] as String? ?? '',
      )?.toUtc(),
      recoveryTodo: json['recoveryTodo'] as String?,
    );
  }

  final String workspaceId;
  final AgentCodingSessionCheckpointStatus status;
  final DateTime updatedAt;
  final int recordCount;
  final String? latestRequestId;
  final String? latestProfileId;
  final String? latestProviderKind;
  final AgentCodingSessionOutcome? latestOutcome;
  final DateTime? latestCompletedAt;
  final String? recoveryTodo;

  bool get hasHistory => recordCount > 0;
  bool get needsRecovery =>
      status == AgentCodingSessionCheckpointStatus.needsRecovery;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'status': status.wireValue,
      'updatedAt': updatedAt.toIso8601String(),
      'recordCount': recordCount,
      'hasHistory': hasHistory,
      'needsRecovery': needsRecovery,
      if (latestRequestId != null) 'latestRequestId': latestRequestId,
      if (latestProfileId != null) 'latestProfileId': latestProfileId,
      if (latestProviderKind != null) 'latestProviderKind': latestProviderKind,
      if (latestOutcome != null) 'latestOutcome': latestOutcome!.wireValue,
      if (latestCompletedAt != null)
        'latestCompletedAt': latestCompletedAt!.toIso8601String(),
      if (recoveryTodo != null) 'recoveryTodo': recoveryTodo,
    };
  }
}

class AgentCodingSessionHistory {
  AgentCodingSessionHistory({
    required this.workspaceId,
    this.records = const <AgentCodingSessionHistoryRecord>[],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory AgentCodingSessionHistory.fromJson(Map<String, Object?> json) {
    return AgentCodingSessionHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      records: _historyRecordsFromJson(json['records']),
    );
  }

  final String workspaceId;
  final List<AgentCodingSessionHistoryRecord> records;
  final DateTime updatedAt;

  AgentCodingSessionHistory append(
    AgentCodingSessionHistoryRecord record, {
    int maxEntries = 50,
    DateTime? updatedAt,
  }) {
    final nextRecords = <AgentCodingSessionHistoryRecord>[record, ...records];
    return AgentCodingSessionHistory(
      workspaceId: workspaceId,
      records: nextRecords.take(maxEntries).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  AgentCodingSessionCheckpoint toCheckpoint() {
    return AgentCodingSessionCheckpoint.fromHistory(this);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'updatedAt': updatedAt.toIso8601String(),
      'recordCount': records.length,
      'records': records
          .map((record) => record.toJson())
          .toList(growable: false),
    };
  }
}

class AgentCodingSessionHistoryStore {
  AgentCodingSessionHistoryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'agent.coding-session-history',
             layer: 'service',
             stateFamily: 'agent-session-history',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const AgentCodingSessionHistoryStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'agent.coding-session-history';
  static const String _key = 'records';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(AgentCodingSessionHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<AgentCodingSessionHistory> readHistory({
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
      return AgentCodingSessionHistory(workspaceId: workspaceId);
    }
    final history = AgentCodingSessionHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? AgentCodingSessionHistory(
            workspaceId: workspaceId,
            records: history.records,
            updatedAt: history.updatedAt,
          )
        : history;
  }

  Future<AgentCodingSessionHistory> appendRecord({
    required String workspaceId,
    required AgentCodingSessionHistoryRecord record,
    int maxEntries = 50,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(record, maxEntries: maxEntries);
    await saveHistory(next);
    return next;
  }

  Future<AgentCodingSessionCheckpoint> readCheckpoint({
    required String workspaceId,
  }) async {
    final history = await readHistory(workspaceId: workspaceId);
    return history.toCheckpoint();
  }
}

AgentCodingSessionOutcome _agentCodingSessionOutcomeFromWire(String? value) {
  return switch (value) {
    'failed' => AgentCodingSessionOutcome.failed,
    'cancelled' => AgentCodingSessionOutcome.cancelled,
    _ => AgentCodingSessionOutcome.succeeded,
  };
}

AgentCodingSessionCheckpointStatus _agentCodingSessionCheckpointStatusFromWire(
  String? value,
) {
  return switch (value) {
    'ready' => AgentCodingSessionCheckpointStatus.ready,
    'needsRecovery' => AgentCodingSessionCheckpointStatus.needsRecovery,
    _ => AgentCodingSessionCheckpointStatus.empty,
  };
}

String _responseTextSample(List<AgentContentPart> contentParts) {
  final text = contentParts
      .map((part) => part.text.trim())
      .where((partText) => partText.isNotEmpty)
      .join('\n');
  if (text.length <= 1000) {
    return text;
  }
  return text.substring(0, 1000);
}

List<AgentCodingSessionHistoryRecord> _historyRecordsFromJson(Object? value) {
  if (value is! List) {
    return const <AgentCodingSessionHistoryRecord>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => AgentCodingSessionHistoryRecord.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}
