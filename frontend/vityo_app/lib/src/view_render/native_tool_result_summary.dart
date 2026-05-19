String? nativeToolMetadataSummaryText(
  Map<String, Object?> metadata, {
  bool describeUnstructured = false,
}) {
  final buildResult = metadata['buildResult'];
  if (buildResult is Map<String, Object?>) {
    final status = buildResult['status'] as String? ?? 'unknown';
    final diagnosticCount = buildResult['diagnosticCount'] as int? ?? 0;
    return _withRequiredCommand(
      'build $status · diagnostics $diagnosticCount',
      _stringValue(buildResult['requiredCommand']) ??
          _stringValue(metadata['requiredCommand']),
    );
  }

  final formatResult = metadata['formatResult'];
  if (formatResult is Map<String, Object?>) {
    final status = formatResult['status'] as String? ?? 'unknown';
    final changed = formatResult['changed'] == true ? 'yes' : 'no';
    return 'format $status · changed $changed';
  }

  final staticAnalysisResult = metadata['staticAnalysisResult'];
  if (staticAnalysisResult is Map<String, Object?>) {
    final status = staticAnalysisResult['status'] as String? ?? 'unknown';
    final diagnosticCount =
        staticAnalysisResult['diagnosticCount'] as int? ?? 0;
    return _withRequiredCommand(
      'static analysis $status · diagnostics $diagnosticCount',
      _stringValue(staticAnalysisResult['requiredCommand']) ??
          _stringValue(metadata['requiredCommand']),
    );
  }

  final testResult = metadata['testResult'];
  if (testResult is Map<String, Object?>) {
    final status = testResult['status'] as String? ?? 'unknown';
    final requiredCommand =
        _stringValue(testResult['requiredCommand']) ??
        _stringValue(metadata['requiredCommand']);
    final passedCount = testResult['passedCount'] as int?;
    final totalCount = testResult['totalCount'] as int?;
    if (passedCount != null && totalCount != null) {
      return _withRequiredCommand(
        'tests $status · $passedCount passed / $totalCount total',
        requiredCommand,
      );
    }
    return _withRequiredCommand('tests $status', requiredCommand);
  }

  final completedRequiredCommandFor = _stringValue(
    metadata['completedRequiredCommandFor'],
  );
  if (completedRequiredCommandFor != null) {
    return 'completed required command for $completedRequiredCommandFor';
  }

  final requiredCommand = _stringValue(metadata['requiredCommand']);
  if (requiredCommand != null) {
    return 'requires $requiredCommand';
  }

  if (metadata.isEmpty) {
    return describeUnstructured ? 'no structured metadata' : null;
  }
  return describeUnstructured ? 'metadata ${metadata.keys.join(', ')}' : null;
}

int nativeToolMetadataDiagnosticCount(Map<String, Object?> metadata) {
  final buildResult = metadata['buildResult'];
  if (buildResult is Map<String, Object?>) {
    return buildResult['diagnosticCount'] as int? ?? 0;
  }
  final staticAnalysisResult = metadata['staticAnalysisResult'];
  if (staticAnalysisResult is Map<String, Object?>) {
    return staticAnalysisResult['diagnosticCount'] as int? ?? 0;
  }
  return 0;
}

String _withRequiredCommand(String summary, String? requiredCommand) {
  return requiredCommand == null
      ? summary
      : '$summary · requires $requiredCommand';
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
