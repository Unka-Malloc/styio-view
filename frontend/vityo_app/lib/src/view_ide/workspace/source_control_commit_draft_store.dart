import '../foundation/foundation.dart';
import 'source_control_status.dart';

enum SourceControlCommitDialogStatus { closed, editing, ready, blocked }

extension SourceControlCommitDialogStatusX on SourceControlCommitDialogStatus {
  String get wireValue {
    return switch (this) {
      SourceControlCommitDialogStatus.closed => 'closed',
      SourceControlCommitDialogStatus.editing => 'editing',
      SourceControlCommitDialogStatus.ready => 'ready',
      SourceControlCommitDialogStatus.blocked => 'blocked',
    };
  }
}

class SourceControlCommitDraft {
  const SourceControlCommitDraft({
    required this.workspaceId,
    this.message = '',
    this.selectedPaths = const <String>[],
    this.amend = false,
    this.signOff = false,
    this.updatedAt,
  });

  factory SourceControlCommitDraft.fromJson(Map<String, Object?> json) {
    return SourceControlCommitDraft(
      workspaceId: json['workspaceId'] as String? ?? '',
      message: json['message'] as String? ?? '',
      selectedPaths: _jsonStringList(json['selectedPaths']),
      amend: json['amend'] as bool? ?? false,
      signOff: json['signOff'] as bool? ?? false,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final String message;
  final List<String> selectedPaths;
  final bool amend;
  final bool signOff;
  final DateTime? updatedAt;

  bool get hasMessage => message.trim().isNotEmpty;

  SourceControlActionPlan toCommitActionPlan() {
    return SourceControlActionPlan.fromRequest(
      SourceControlActionRequest(
        kind: SourceControlActionKind.commit,
        message: message,
        paths: selectedPaths,
      ),
    );
  }

  SourceControlCommitDraft copyWith({
    String? workspaceId,
    String? message,
    List<String>? selectedPaths,
    bool? amend,
    bool? signOff,
    DateTime? updatedAt,
  }) {
    return SourceControlCommitDraft(
      workspaceId: workspaceId ?? this.workspaceId,
      message: message ?? this.message,
      selectedPaths: selectedPaths == null
          ? this.selectedPaths
          : _normalizePaths(selectedPaths),
      amend: amend ?? this.amend,
      signOff: signOff ?? this.signOff,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'message': message,
      'selectedPaths': selectedPaths,
      'amend': amend,
      'signOff': signOff,
      'hasMessage': hasMessage,
      'commitPlan': toCommitActionPlan().toJson(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class SourceControlCommitDialogState {
  const SourceControlCommitDialogState({
    required this.draft,
    required this.status,
    this.validationMessage = '',
  });

  factory SourceControlCommitDialogState.fromDraft({
    required SourceControlCommitDraft draft,
    bool open = false,
  }) {
    if (!open) {
      return SourceControlCommitDialogState(
        draft: draft,
        status: SourceControlCommitDialogStatus.closed,
      );
    }
    final plan = draft.toCommitActionPlan();
    if (plan.canRun) {
      return SourceControlCommitDialogState(
        draft: draft,
        status: SourceControlCommitDialogStatus.ready,
      );
    }
    return SourceControlCommitDialogState(
      draft: draft,
      status: SourceControlCommitDialogStatus.blocked,
      validationMessage: plan.blockedReason,
    );
  }

  final SourceControlCommitDraft draft;
  final SourceControlCommitDialogStatus status;
  final String validationMessage;

  SourceControlActionPlan get plan => draft.toCommitActionPlan();
  bool get open => status != SourceControlCommitDialogStatus.closed;
  bool get canSubmit => status == SourceControlCommitDialogStatus.ready;

  SourceControlCommitDialogState edit({
    String? message,
    List<String>? selectedPaths,
    bool? amend,
    bool? signOff,
  }) {
    return SourceControlCommitDialogState.fromDraft(
      open: open,
      draft: draft.copyWith(
        message: message,
        selectedPaths: selectedPaths,
        amend: amend,
        signOff: signOff,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'open': open,
      'canSubmit': canSubmit,
      'validationMessage': validationMessage,
      'draft': draft.toJson(),
      'plan': plan.toJson(),
    };
  }
}

class SourceControlCommitDraftStore {
  SourceControlCommitDraftStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.source-control.commit-draft',
             layer: 'interaction',
             stateFamily: 'source-control-commit-draft',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const SourceControlCommitDraftStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName =
      'interaction.source-control.commit-draft';
  static const String _key = 'draft';

  final FoundationDataStoreOwner _owner;

  Future<void> saveDraft(SourceControlCommitDraft draft) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: draft.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: draft.workspaceId,
    );
  }

  Future<SourceControlCommitDraft> readDraft({
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
      return SourceControlCommitDraft(workspaceId: workspaceId);
    }
    final draft = SourceControlCommitDraft.fromJson(value);
    return draft.workspaceId.isEmpty
        ? draft.copyWith(workspaceId: workspaceId)
        : draft;
  }

  Future<bool> deleteDraft({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchDraft({required String workspaceId}) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return _normalizePaths(value.map((item) => '$item'));
}

List<String> _normalizePaths(Iterable<String> paths) {
  final result =
      paths
          .map((path) => path.trim())
          .where((path) => path.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return result;
}
