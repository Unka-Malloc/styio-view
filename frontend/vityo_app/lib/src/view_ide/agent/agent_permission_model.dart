import 'dart:convert';

import '../environment/configuration/log_redactor.dart';

enum AgentRole { build, plan, general, explore, scout, review }

enum AgentCapability {
  fileRead,
  fileWrite,
  processExec,
  network,
  secretAccess,
  moduleInstall,
  cloudUpload,
  terminalInteractive,
}

class AgentPermissionSet {
  const AgentPermissionSet(this.capabilities);

  final Set<AgentCapability> capabilities;

  bool allows(AgentCapability capability) => capabilities.contains(capability);

  bool allowsAll(Iterable<AgentCapability> capabilities) {
    return capabilities.every(allows);
  }

  bool deniesAll(Iterable<AgentCapability> capabilities) {
    return capabilities.every((capability) => !allows(capability));
  }

  bool isSubsetOf(AgentPermissionSet parent) {
    return capabilities.every(parent.capabilities.contains);
  }

  AgentPermissionSet intersect(AgentPermissionSet other) {
    return AgentPermissionSet(
      capabilities.intersection(other.capabilities),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capabilities': capabilities
          .map((capability) => capability.name)
          .toList(growable: false),
    };
  }
}

class AgentRolePolicy {
  const AgentRolePolicy._();

  static const Map<AgentRole, AgentPermissionSet> defaults =
      <AgentRole, AgentPermissionSet>{
    AgentRole.build: AgentPermissionSet(<AgentCapability>{
      AgentCapability.fileRead,
      AgentCapability.fileWrite,
      AgentCapability.processExec,
    }),
    AgentRole.plan: AgentPermissionSet(<AgentCapability>{
      AgentCapability.fileRead,
    }),
    AgentRole.general: AgentPermissionSet(<AgentCapability>{
      AgentCapability.fileRead,
      AgentCapability.fileWrite,
      AgentCapability.processExec,
    }),
    AgentRole.explore: AgentPermissionSet(<AgentCapability>{
      AgentCapability.fileRead,
    }),
    AgentRole.scout: AgentPermissionSet(<AgentCapability>{
      AgentCapability.network,
    }),
    AgentRole.review: AgentPermissionSet(<AgentCapability>{
      AgentCapability.fileRead,
    }),
  };

  static AgentPermissionSet permissionsFor(AgentRole role) {
    return defaults[role] ?? const AgentPermissionSet(<AgentCapability>{});
  }
}

class AgentSpawnPolicyDecision {
  const AgentSpawnPolicyDecision.allowed(this.permissions)
      : deniedReason = '',
        allowed = true;

  const AgentSpawnPolicyDecision.denied(this.deniedReason)
      : permissions = const AgentPermissionSet(<AgentCapability>{}),
        allowed = false;

  final bool allowed;
  final AgentPermissionSet permissions;
  final String deniedReason;
}

class AgentPermissionLattice {
  const AgentPermissionLattice();

  AgentSpawnPolicyDecision deriveChildPermissions({
    required AgentPermissionSet parent,
    required AgentRole requestedRole,
    AgentPermissionSet? requestedPermissions,
  }) {
    final rolePermissions = AgentRolePolicy.permissionsFor(requestedRole);
    final requested = requestedPermissions == null
        ? rolePermissions
        : requestedPermissions.intersect(rolePermissions);
    if (!requested.isSubsetOf(parent)) {
      return const AgentSpawnPolicyDecision.denied(
        'Child agent permissions must be a subset of the parent permissions.',
      );
    }
    return AgentSpawnPolicyDecision.allowed(requested);
  }

  bool isReadOnlyReview(AgentRole role, AgentPermissionSet permissions) {
    return role == AgentRole.review &&
        permissions.allows(AgentCapability.fileRead) &&
        permissions.capabilities.length == 1;
  }
}

enum AiProviderRetentionPolicy { none, session, providerDefault }

class AgentProviderCapabilityProfile {
  const AgentProviderCapabilityProfile({
    required this.maxInputTokens,
    required this.retentionPolicy,
    this.supportsTools = false,
    this.supportsStreaming = false,
    this.networkRequired = true,
    this.redactionRequired = true,
  });

  final int maxInputTokens;
  final AiProviderRetentionPolicy retentionPolicy;
  final bool supportsTools;
  final bool supportsStreaming;
  final bool networkRequired;
  final bool redactionRequired;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxInputTokens': maxInputTokens,
      'retentionPolicy': retentionPolicy.name,
      'supportsTools': supportsTools,
      'supportsStreaming': supportsStreaming,
      'networkRequired': networkRequired,
      'redactionRequired': redactionRequired,
    };
  }
}

class AiProviderCapabilityProfile extends AgentProviderCapabilityProfile {
  const AiProviderCapabilityProfile({
    required this.providerId,
    required super.maxInputTokens,
    required super.retentionPolicy,
    super.supportsTools,
    super.supportsStreaming,
    super.networkRequired,
    super.redactionRequired,
  });

  final String providerId;

  AgentProviderCapabilityProfile get neutralProfile {
    return AgentProviderCapabilityProfile(
      maxInputTokens: maxInputTokens,
      retentionPolicy: retentionPolicy,
      supportsTools: supportsTools,
      supportsStreaming: supportsStreaming,
      networkRequired: networkRequired,
      redactionRequired: redactionRequired,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      ...super.toJson(),
    };
  }
}

class AgentContextPolicy {
  const AgentContextPolicy({
    this.uploadCodeByDefault = false,
    this.maxContextBytes = 65536,
    this.includeSecrets = false,
  });

  final bool uploadCodeByDefault;
  final int maxContextBytes;
  final bool includeSecrets;
}

class AgentContextMinimizer {
  const AgentContextMinimizer({this.policy = const AgentContextPolicy()});

  final AgentContextPolicy policy;

  String minimize(String context) {
    final safe = policy.includeSecrets
        ? context
        : _redactAgentContextSecrets(context);
    return _truncateUtf8(safe, policy.maxContextBytes);
  }
}

final LogRedactor _agentContextLogRedactor = LogRedactor();

String _redactAgentContextSecrets(String value) {
  return _agentContextLogRedactor.redact(value);
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) {
    return '';
  }
  final bytes = utf8.encode(value);
  if (bytes.length <= maxBytes) {
    return value;
  }
  var end = maxBytes;
  while (end > 0) {
    try {
      return utf8.decode(bytes.take(end).toList(growable: false));
    } on FormatException {
      end -= 1;
    }
  }
  return '';
}
