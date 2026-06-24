String? requiredCommandIdFromAgentMetadata(Map<String, Object?> metadata) {
  final topLevel = _metadataString(metadata['requiredCommand']);
  if (topLevel != null) {
    return topLevel;
  }
  for (final key in const <String>[
    'buildResult',
    'staticAnalysisResult',
    'testResult',
  ]) {
    final value = metadata[key];
    if (value is Map) {
      final nested = _metadataString(value['requiredCommand']);
      if (nested != null) {
        return nested;
      }
    }
  }
  return null;
}

class AgentCommandBackendRouteMetadata {
  const AgentCommandBackendRouteMetadata({
    required this.routeKind,
    required this.allowed,
    required this.previewOnly,
    this.adapterKind,
    this.blockedReason,
  });

  final String routeKind;
  final String? adapterKind;
  final bool allowed;
  final bool previewOnly;
  final String? blockedReason;

  bool get blocked => !allowed;
}

class AgentCommandToolchainSelectionMetadata {
  const AgentCommandToolchainSelectionMetadata({
    required this.status,
    this.toolchainId,
    this.cppStandard,
    this.selectionMessage,
  });

  final String status;
  final String? toolchainId;
  final String? cppStandard;
  final String? selectionMessage;

  bool get selected => status == 'selected' || status == 'cleared';

  bool get settingsRecoveryRecommended => !selected;
}

AgentCommandBackendRouteMetadata? backendRouteFromAgentMetadata(
  Map<String, Object?> metadata,
) {
  final value = metadata['backendRouteSelection'];
  if (value is! Map) {
    return null;
  }
  final routeKind = _metadataString(value['routeKind']);
  if (routeKind == null) {
    return null;
  }
  return AgentCommandBackendRouteMetadata(
    routeKind: routeKind,
    adapterKind: _metadataString(value['adapterKind']),
    allowed: value['allowed'] == true,
    previewOnly: value['previewOnly'] == true,
    blockedReason: _metadataString(value['blockedReason']),
  );
}

AgentCommandToolchainSelectionMetadata? toolchainSelectionFromAgentMetadata(
  Map<String, Object?> metadata,
) {
  final status = _metadataString(metadata['toolchainSelectionStatus']);
  if (status == null) {
    return null;
  }
  return AgentCommandToolchainSelectionMetadata(
    status: status,
    toolchainId: _metadataString(metadata['toolchainId']),
    cppStandard: _metadataString(metadata['cppStandard']),
    selectionMessage: _metadataString(metadata['toolchainSelectionMessage']),
  );
}

String? _metadataString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
