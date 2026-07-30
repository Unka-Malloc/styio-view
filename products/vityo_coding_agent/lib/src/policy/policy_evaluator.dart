library;

import '../tools/tool_catalog.dart';
import 'permission_grant_store.dart';

final class ToolRoot {
  const ToolRoot({required this.id, required this.uri});

  final String id;
  final String uri;
}

final class ExecutionPolicy {
  const ExecutionPolicy({
    required this.version,
    required this.allowedRisks,
    this.allowedNetworkHosts = const <String>{},
    required this.maxResultBytes,
    this.denyRawCredentials = true,
  });

  ExecutionPolicy.snapshot(ExecutionPolicy other)
    : version = other.version,
      allowedRisks = Set<ToolRisk>.unmodifiable(other.allowedRisks),
      allowedNetworkHosts = Set<String>.unmodifiable(other.allowedNetworkHosts),
      maxResultBytes = other.maxResultBytes,
      denyRawCredentials = other.denyRawCredentials;

  final int version;
  final Set<ToolRisk> allowedRisks;
  final Set<String> allowedNetworkHosts;
  final int maxResultBytes;
  final bool denyRawCredentials;
}

final class ToolEffect {
  const ToolEffect({
    required this.toolId,
    required this.risk,
    this.requestedPath,
    this.resolvedPath,
    this.networkHost,
    this.rawCredentialDetected = false,
    this.secretAudienceValid = true,
  });

  final String toolId;
  final ToolRisk risk;
  final String? requestedPath;
  final String? resolvedPath;
  final String? networkHost;
  final bool rawCredentialDetected;
  final bool secretAudienceValid;
}

enum PolicyDecisionCode { allowed, policyDenied, permissionDenied }

final class PolicyDecision {
  const PolicyDecision({required this.code, required this.reason});

  const PolicyDecision.allowed()
    : code = PolicyDecisionCode.allowed,
      reason = 'allowed';

  final PolicyDecisionCode code;
  final String reason;

  bool get allowed => code == PolicyDecisionCode.allowed;
}

abstract interface class PolicyEvaluator {
  PolicyDecision evaluate({
    required ToolEffect effect,
    required ExecutionPolicy policy,
    required List<ToolRoot> roots,
    required PermissionGrantStore grants,
    required String sessionId,
  });
}

final class DefaultPolicyEvaluator implements PolicyEvaluator {
  const DefaultPolicyEvaluator();

  @override
  PolicyDecision evaluate({
    required ToolEffect effect,
    required ExecutionPolicy policy,
    required List<ToolRoot> roots,
    required PermissionGrantStore grants,
    required String sessionId,
  }) {
    if (policy.version < 0 || policy.maxResultBytes <= 0) {
      return const PolicyDecision(
        code: PolicyDecisionCode.policyDenied,
        reason: 'invalid policy snapshot',
      );
    }
    if (!policy.allowedRisks.contains(effect.risk)) {
      return const PolicyDecision(
        code: PolicyDecisionCode.policyDenied,
        reason: 'risk not allowed',
      );
    }
    if ((policy.denyRawCredentials && effect.rawCredentialDetected) ||
        !effect.secretAudienceValid) {
      return const PolicyDecision(
        code: PolicyDecisionCode.policyDenied,
        reason: 'credential policy rejected',
      );
    }
    if (effect.networkHost case final host?) {
      final normalized = host.trim().toLowerCase();
      if (normalized.isEmpty ||
          !policy.allowedNetworkHosts
              .map((entry) => entry.toLowerCase())
              .contains(normalized)) {
        return const PolicyDecision(
          code: PolicyDecisionCode.policyDenied,
          reason: 'network host not allowed',
        );
      }
    }

    String? rootId;
    if (effect.requestedPath case final requested?) {
      if (_containsTraversal(requested)) {
        return const PolicyDecision(
          code: PolicyDecisionCode.policyDenied,
          reason: 'path traversal rejected',
        );
      }
      final resolved = effect.resolvedPath;
      if (resolved == null) {
        return const PolicyDecision(
          code: PolicyDecisionCode.policyDenied,
          reason: 'path resolution failed',
        );
      }
      final requestedRoot = _matchingRoot(requested, roots);
      final resolvedRoot = _matchingRoot(resolved, roots);
      if (requestedRoot == null ||
          resolvedRoot == null ||
          requestedRoot.id != resolvedRoot.id) {
        return const PolicyDecision(
          code: PolicyDecisionCode.policyDenied,
          reason: 'path escaped approved roots',
        );
      }
      rootId = resolvedRoot.id;
    } else if (roots.isNotEmpty) {
      rootId = roots.first.id;
    }
    if (rootId == null ||
        !grants.allows(
          sessionId: sessionId,
          toolId: effect.toolId,
          risk: effect.risk,
          rootId: rootId,
        )) {
      return const PolicyDecision(
        code: PolicyDecisionCode.permissionDenied,
        reason: 'current permission grant does not allow the effect',
      );
    }
    return const PolicyDecision.allowed();
  }

  static bool _containsTraversal(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return true;
    final withoutSuffix = value.split(RegExp(r'[?#]')).first;
    final authorityEnd = withoutSuffix.indexOf(
      '/',
      withoutSuffix.indexOf('://') + 3,
    );
    final rawPath = authorityEnd < 0
        ? ''
        : withoutSuffix.substring(authorityEnd + 1);
    return rawPath.split('/').any((segment) {
      try {
        return Uri.decodeComponent(segment) == '..';
      } on FormatException {
        return true;
      }
    });
  }

  static ToolRoot? _matchingRoot(String value, List<ToolRoot> roots) {
    final candidate = Uri.tryParse(value);
    if (candidate == null || !candidate.hasScheme) return null;
    final candidateSegments = _normalizedSegments(candidate.pathSegments);
    if (candidateSegments == null) return null;
    for (final root in roots) {
      final rootUri = Uri.tryParse(root.uri);
      if (rootUri == null ||
          rootUri.scheme != candidate.scheme ||
          rootUri.authority != candidate.authority) {
        continue;
      }
      final rootSegments = _normalizedSegments(rootUri.pathSegments);
      if (rootSegments == null ||
          candidateSegments.length < rootSegments.length) {
        continue;
      }
      var matches = true;
      for (var index = 0; index < rootSegments.length; index += 1) {
        if (candidateSegments[index] != rootSegments[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return root;
    }
    return null;
  }

  static List<String>? _normalizedSegments(List<String> segments) {
    final result = <String>[];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') return null;
      result.add(segment);
    }
    return result;
  }
}
