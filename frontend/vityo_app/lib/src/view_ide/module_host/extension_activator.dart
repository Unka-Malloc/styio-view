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
