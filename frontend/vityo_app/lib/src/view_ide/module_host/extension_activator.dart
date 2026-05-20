import '../foundation/foundation.dart';
import 'extension_contribution_router.dart';
import 'extension_manifest_contract.dart';

enum ExtensionActivationDecisionStatus { activated, blockedUntrusted }

extension ExtensionActivationDecisionStatusX
    on ExtensionActivationDecisionStatus {
  String get wireValue => switch (this) {
    ExtensionActivationDecisionStatus.activated => 'activated',
    ExtensionActivationDecisionStatus.blockedUntrusted => 'blocked-untrusted',
  };
}

class ExtensionActivationPolicy {
  const ExtensionActivationPolicy({this.allowUntrusted = false});

  final bool allowUntrusted;

  bool canActivate(ExtensionManifest manifest) {
    return allowUntrusted || manifest.trustedByDefault;
  }
}

class ExtensionActivationDecision {
  const ExtensionActivationDecision({
    required this.extensionId,
    required this.event,
    required this.status,
    required this.message,
  });

  factory ExtensionActivationDecision.fromJson(Map<String, Object?> json) {
    return ExtensionActivationDecision(
      extensionId: json['extensionId'] as String? ?? '',
      event: json['event'] as String? ?? '',
      status: _activationDecisionStatusFromWire(json['status'] as String?),
      message: json['message'] as String? ?? '',
    );
  }

  final String extensionId;
  final String event;
  final ExtensionActivationDecisionStatus status;
  final String message;

  bool get activated => status == ExtensionActivationDecisionStatus.activated;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'event': event,
      'status': status.wireValue,
      'message': message,
      'activated': activated,
    };
  }
}

class ExtensionActivationSession {
  const ExtensionActivationSession({
    required this.event,
    required this.activatedAt,
    required this.decisions,
  });

  factory ExtensionActivationSession.fromJson(Map<String, Object?> json) {
    return ExtensionActivationSession(
      event: json['event'] as String? ?? '',
      activatedAt:
          DateTime.tryParse(json['activatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      decisions: _activationDecisionsFromJson(json['decisions']),
    );
  }

  final String event;
  final DateTime activatedAt;
  final List<ExtensionActivationDecision> decisions;

  List<String> get activatedExtensionIds {
    return decisions
        .where((decision) => decision.activated)
        .map((decision) => decision.extensionId)
        .toList(growable: false);
  }

  List<String> get blockedExtensionIds {
    return decisions
        .where((decision) => !decision.activated)
        .map((decision) => decision.extensionId)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'event': event,
      'activatedAt': activatedAt.toIso8601String(),
      'decisionCount': decisions.length,
      'activatedExtensionIds': activatedExtensionIds,
      'blockedExtensionIds': blockedExtensionIds,
      'decisions': decisions
          .map((decision) => decision.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionActivationHistory {
  ExtensionActivationHistory({
    required this.workspaceId,
    this.sessions = const <ExtensionActivationSession>[],
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory ExtensionActivationHistory.fromJson(Map<String, Object?> json) {
    return ExtensionActivationHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sessions: _activationSessionsFromJson(json['sessions']),
    );
  }

  final String workspaceId;
  final List<ExtensionActivationSession> sessions;
  final DateTime updatedAt;

  ExtensionActivationHistory append(
    ExtensionActivationSession session, {
    int maxEntries = 50,
    DateTime? updatedAt,
  }) {
    final nextSessions = <ExtensionActivationSession>[session, ...sessions];
    return ExtensionActivationHistory(
      workspaceId: workspaceId,
      sessions: nextSessions.take(maxEntries).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'updatedAt': updatedAt.toIso8601String(),
      'sessionCount': sessions.length,
      'sessions': sessions
          .map((session) => session.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionActivationHistoryStore {
  ExtensionActivationHistoryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'extension.activation-history',
             layer: 'extension',
             stateFamily: 'extension-activation',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const ExtensionActivationHistoryStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'extension.activation-history';
  static const String _key = 'sessions';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(ExtensionActivationHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<ExtensionActivationHistory> readHistory({
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
      return ExtensionActivationHistory(workspaceId: workspaceId);
    }
    final history = ExtensionActivationHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? ExtensionActivationHistory(
            workspaceId: workspaceId,
            sessions: history.sessions,
            updatedAt: history.updatedAt,
          )
        : history;
  }

  Future<ExtensionActivationHistory> appendSession({
    required String workspaceId,
    required ExtensionActivationSession session,
    int maxEntries = 50,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(session, maxEntries: maxEntries);
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
}

class ExtensionActivator {
  const ExtensionActivator({
    this.policy = const ExtensionActivationPolicy(),
    this.router = const ExtensionContributionRouter(),
    this.clock,
  });

  final ExtensionActivationPolicy policy;
  final ExtensionContributionRouter router;
  final DateTime Function()? clock;

  ExtensionActivationSession activate({
    required ExtensionManifestRegistry registry,
    required String event,
  }) {
    final activatedAt = (clock ?? DateTime.now)().toUtc();
    final decisions = _activationCandidates(registry, event)
        .map((manifest) => _activateManifest(manifest, event))
        .toList(growable: false);
    return ExtensionActivationSession(
      event: event,
      activatedAt: activatedAt,
      decisions: decisions,
    );
  }

  ExtensionContributionRouteManifest routeActivatedContributions({
    required ExtensionManifestRegistry registry,
    required String event,
  }) {
    final session = activate(registry: registry, event: event);
    final activeRegistry = ExtensionManifestRegistry(
      session.activatedExtensionIds
          .map(registry.lookup)
          .whereType<ExtensionManifest>(),
    );
    return router.routeRegistry(activeRegistry);
  }

  Iterable<ExtensionManifest> _activationCandidates(
    ExtensionManifestRegistry registry,
    String event,
  ) {
    return registry.list().where(
      (manifest) => manifest.activatesOn(event) || manifest.activatesOn('*'),
    );
  }

  ExtensionActivationDecision _activateManifest(
    ExtensionManifest manifest,
    String event,
  ) {
    if (!policy.canActivate(manifest)) {
      return ExtensionActivationDecision(
        extensionId: manifest.extensionId,
        event: event,
        status: ExtensionActivationDecisionStatus.blockedUntrusted,
        message:
            'Extension ${manifest.extensionId} is blocked by the activation '
            'trust policy.',
      );
    }
    return ExtensionActivationDecision(
      extensionId: manifest.extensionId,
      event: event,
      status: ExtensionActivationDecisionStatus.activated,
      message: 'Extension ${manifest.extensionId} activated for $event.',
    );
  }
}

ExtensionActivationDecisionStatus _activationDecisionStatusFromWire(
  String? value,
) {
  return switch (value) {
    'blocked-untrusted' => ExtensionActivationDecisionStatus.blockedUntrusted,
    _ => ExtensionActivationDecisionStatus.activated,
  };
}

List<ExtensionActivationDecision> _activationDecisionsFromJson(Object? value) {
  if (value is! List) {
    return const <ExtensionActivationDecision>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => ExtensionActivationDecision.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}

List<ExtensionActivationSession> _activationSessionsFromJson(Object? value) {
  if (value is! List) {
    return const <ExtensionActivationSession>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => ExtensionActivationSession.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .toList(growable: false);
}
