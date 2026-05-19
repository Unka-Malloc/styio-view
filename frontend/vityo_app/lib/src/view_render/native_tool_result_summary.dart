String? nativeToolMetadataSummaryText(
  Map<String, Object?> metadata, {
  bool describeUnstructured = false,
}) {
  final routeSummary = _backendRouteSelectionSummary(
    metadata['backendRouteSelection'],
  );
  final buildResult = metadata['buildResult'];
  if (buildResult is Map<String, Object?>) {
    final status = buildResult['status'] as String? ?? 'unknown';
    final diagnosticCount = buildResult['diagnosticCount'] as int? ?? 0;
    return _withRouteSelection(
      _withRequiredCommand(
        'build $status · diagnostics $diagnosticCount',
        _stringValue(buildResult['requiredCommand']) ??
            _stringValue(metadata['requiredCommand']),
      ),
      routeSummary,
    );
  }

  final formatResult = metadata['formatResult'];
  if (formatResult is Map<String, Object?>) {
    final status = formatResult['status'] as String? ?? 'unknown';
    final changed = formatResult['changed'] == true ? 'yes' : 'no';
    return _withRouteSelection(
      'format $status · changed $changed',
      routeSummary,
    );
  }

  final staticAnalysisResult = metadata['staticAnalysisResult'];
  if (staticAnalysisResult is Map<String, Object?>) {
    final status = staticAnalysisResult['status'] as String? ?? 'unknown';
    final diagnosticCount =
        staticAnalysisResult['diagnosticCount'] as int? ?? 0;
    return _withRouteSelection(
      _withRequiredCommand(
        'static analysis $status · diagnostics $diagnosticCount',
        _stringValue(staticAnalysisResult['requiredCommand']) ??
            _stringValue(metadata['requiredCommand']),
      ),
      routeSummary,
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
      return _withRouteSelection(
        _withRequiredCommand(
          'tests $status · $passedCount passed / $totalCount total',
          requiredCommand,
        ),
        routeSummary,
      );
    }
    return _withRouteSelection(
      _withRequiredCommand('tests $status', requiredCommand),
      routeSummary,
    );
  }

  final completedRequiredCommandFor = _stringValue(
    metadata['completedRequiredCommandFor'],
  );
  if (completedRequiredCommandFor != null) {
    return 'completed required command for $completedRequiredCommandFor';
  }

  final requiredCommand = _stringValue(metadata['requiredCommand']);
  if (requiredCommand != null) {
    return _withRouteSelection('requires $requiredCommand', routeSummary);
  }

  if (routeSummary != null) {
    return routeSummary;
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

String _withRouteSelection(String summary, String? routeSummary) {
  return routeSummary == null ? summary : '$summary · $routeSummary';
}

String? _backendRouteSelectionSummary(Object? value) {
  if (value is! Map<String, Object?>) {
    return null;
  }
  final routeKind = _stringValue(value['routeKind']);
  if (routeKind == null) {
    return null;
  }
  final adapterKind = _stringValue(value['adapterKind']);
  final allowed = value['allowed'] == true;
  final previewOnly = value['previewOnly'] == true;
  final blockedReason = _stringValue(value['blockedReason']);
  final summary = StringBuffer('route $routeKind');
  if (adapterKind != null) {
    summary.write(' via $adapterKind');
  }
  if (previewOnly) {
    summary.write(' · preview');
  }
  if (!allowed) {
    summary.write(' · blocked');
    if (blockedReason != null) {
      summary.write(' $blockedReason');
    }
  }
  return summary.toString();
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
