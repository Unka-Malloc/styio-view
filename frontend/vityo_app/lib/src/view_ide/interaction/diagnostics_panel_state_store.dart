import '../foundation/foundation.dart';
import '../workspace/workspace.dart';

class DiagnosticsPanelState {
  const DiagnosticsPanelState({
    required this.workspaceId,
    this.selectedDocumentId = '',
    this.selectedDiagnosticCode = '',
    this.selectedRangeStart = 0,
    this.selectedRangeEnd = 0,
    this.filterState = const WorkspaceDiagnosticsFilterState(),
    this.updatedAt,
  });

  factory DiagnosticsPanelState.fromJson(Map<String, Object?> json) {
    return DiagnosticsPanelState(
      workspaceId: json['workspaceId'] as String? ?? '',
      selectedDocumentId: json['selectedDocumentId'] as String? ?? '',
      selectedDiagnosticCode: json['selectedDiagnosticCode'] as String? ?? '',
      selectedRangeStart: json['selectedRangeStart'] as int? ?? 0,
      selectedRangeEnd: json['selectedRangeEnd'] as int? ?? 0,
      filterState: _diagnosticsPanelFilterFromJson(json['filterState']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  factory DiagnosticsPanelState.fromDiagnostic({
    required String workspaceId,
    required WorkspaceDiagnostic diagnostic,
    WorkspaceDiagnosticsFilterState filterState =
        const WorkspaceDiagnosticsFilterState(),
    DateTime? updatedAt,
  }) {
    return DiagnosticsPanelState(
      workspaceId: workspaceId,
      selectedDocumentId: diagnostic.documentId,
      selectedDiagnosticCode: diagnostic.diagnostic.code,
      selectedRangeStart: diagnostic.diagnostic.range.start,
      selectedRangeEnd: diagnostic.diagnostic.range.end,
      filterState: filterState,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  final String workspaceId;
  final String selectedDocumentId;
  final String selectedDiagnosticCode;
  final int selectedRangeStart;
  final int selectedRangeEnd;
  final WorkspaceDiagnosticsFilterState filterState;
  final DateTime? updatedAt;

  bool get hasSelection {
    return selectedDocumentId.isNotEmpty && selectedDiagnosticCode.isNotEmpty;
  }

  DiagnosticsPanelState copyWith({
    String? workspaceId,
    String? selectedDocumentId,
    String? selectedDiagnosticCode,
    int? selectedRangeStart,
    int? selectedRangeEnd,
    WorkspaceDiagnosticsFilterState? filterState,
    DateTime? updatedAt,
  }) {
    return DiagnosticsPanelState(
      workspaceId: workspaceId ?? this.workspaceId,
      selectedDocumentId: selectedDocumentId ?? this.selectedDocumentId,
      selectedDiagnosticCode:
          selectedDiagnosticCode ?? this.selectedDiagnosticCode,
      selectedRangeStart: selectedRangeStart ?? this.selectedRangeStart,
      selectedRangeEnd: selectedRangeEnd ?? this.selectedRangeEnd,
      filterState: filterState ?? this.filterState,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'selectedDocumentId': selectedDocumentId,
      'selectedDiagnosticCode': selectedDiagnosticCode,
      'selectedRangeStart': selectedRangeStart,
      'selectedRangeEnd': selectedRangeEnd,
      'filterState': filterState.toJson(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class DiagnosticsPanelStateStore {
  DiagnosticsPanelStateStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.diagnostics-panel-state',
             layer: 'interaction',
             stateFamily: 'diagnostics-panel-state',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const DiagnosticsPanelStateStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'interaction.diagnostics-panel-state';
  static const String _defaultKey = 'default';

  final FoundationDataStoreOwner _owner;

  Future<void> saveState({
    required DiagnosticsPanelState state,
    String key = _defaultKey,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: key,
      value: state.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: state.workspaceId,
    );
  }

  Future<DiagnosticsPanelState> readState({
    required String workspaceId,
    String key = _defaultKey,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return DiagnosticsPanelState(workspaceId: workspaceId);
    }
    final state = DiagnosticsPanelState.fromJson(value);
    return state.workspaceId.isEmpty
        ? state.copyWith(workspaceId: workspaceId)
        : state;
  }

  Future<bool> deleteState({
    required String workspaceId,
    String key = _defaultKey,
  }) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchState({
    required String workspaceId,
    String? key,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

WorkspaceDiagnosticsFilterState _diagnosticsPanelFilterFromJson(Object? value) {
  if (value is! Map) {
    return const WorkspaceDiagnosticsFilterState();
  }
  return WorkspaceDiagnosticsFilterState.fromJson(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}
