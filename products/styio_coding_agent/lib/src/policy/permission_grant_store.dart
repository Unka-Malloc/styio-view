library;

import 'dart:collection';

import '../tools/tool_catalog.dart';

final class PermissionGrant {
  const PermissionGrant({
    required this.id,
    required this.sessionId,
    required this.toolId,
    required this.risks,
    required this.rootIds,
  });

  final String id;
  final String sessionId;
  final String toolId;
  final Set<ToolRisk> risks;
  final Set<String> rootIds;
}

final class PermissionGrantStore {
  PermissionGrantStore({required this.maxGrants}) {
    if (maxGrants <= 0) throw ArgumentError.value(maxGrants, 'maxGrants');
  }

  final int maxGrants;
  final LinkedHashMap<String, _StoredGrant> _grants =
      LinkedHashMap<String, _StoredGrant>();
  int _version = 0;

  int get version => _version;
  int get activeGrantCount => _grants.length;

  void grant(PermissionGrant grant) {
    if (grant.id.isEmpty ||
        grant.sessionId.isEmpty ||
        grant.toolId.isEmpty ||
        grant.risks.isEmpty) {
      throw ArgumentError('Permission grant fields cannot be empty.');
    }
    _grants.remove(grant.id);
    _grants[grant.id] = _StoredGrant.from(grant);
    while (_grants.length > maxGrants) {
      _grants.remove(_grants.keys.first);
    }
    _version += 1;
  }

  void revoke(String grantId) {
    _grants.remove(grantId);
    _version += 1;
  }

  bool allows({
    required String sessionId,
    required String toolId,
    required ToolRisk risk,
    required String rootId,
  }) => _grants.values.any(
    (grant) =>
        grant.sessionId == sessionId &&
        grant.toolId == toolId &&
        grant.risks.contains(risk) &&
        grant.rootIds.contains(rootId),
  );
}

final class _StoredGrant {
  _StoredGrant.from(PermissionGrant grant)
    : id = grant.id,
      sessionId = grant.sessionId,
      toolId = grant.toolId,
      risks = Set<ToolRisk>.unmodifiable(grant.risks),
      rootIds = Set<String>.unmodifiable(grant.rootIds);

  final String id;
  final String sessionId;
  final String toolId;
  final Set<ToolRisk> risks;
  final Set<String> rootIds;
}
