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

String? _metadataString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
