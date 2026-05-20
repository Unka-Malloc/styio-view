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

  final workspaceDiagnostics = metadata['workspaceDiagnostics'];
  final sourceControl = metadata['sourceControl'];
  if (workspaceDiagnostics is Map<String, Object?> &&
      sourceControl is Map<String, Object?>) {
    final diagnosticCount = workspaceDiagnostics['totalCount'] as int? ?? 0;
    final sourceChangeCount = sourceControl['changeCount'] as int? ?? 0;
    final sourceControlDiff = metadata['sourceControlDiff'];
    final diffSummary = sourceControlDiff is Map<String, Object?>
        ? _checkpointDiffSummary(sourceControlDiff)
        : null;
    final projectLanguage = metadata['projectLanguage'];
    final languageSummary = projectLanguage is Map<String, Object?>
        ? _checkpointProjectLanguageSummary(projectLanguage)
        : null;
    final languageServiceStatus = metadata['languageServiceStatus'];
    final languageStatusSummary = languageServiceStatus is Map<String, Object?>
        ? _checkpointLanguageServiceSummary(languageServiceStatus)
        : null;
    final testing = metadata['testing'];
    final testingSummary = testing is Map<String, Object?>
        ? _checkpointTestingSummary(testing)
        : null;
    return <String>[
      'checkpoint diagnostics $diagnosticCount',
      'source changes $sourceChangeCount',
      if (diffSummary != null) diffSummary,
      if (languageSummary != null) languageSummary,
      if (languageStatusSummary != null) languageStatusSummary,
      if (testingSummary != null) testingSummary,
    ].join(' · ');
  }

  final settingsRouteSummary = _settingsRouteSummary(metadata);
  if (settingsRouteSummary != null) {
    return settingsRouteSummary;
  }

  final completedRequiredCommandFor = _stringValue(
    metadata['completedRequiredCommandFor'],
  );
  if (completedRequiredCommandFor != null) {
    return 'completed required command for $completedRequiredCommandFor';
  }

  final toolchainSelectionSummary = _toolchainSelectionSummary(metadata);
  if (toolchainSelectionSummary != null) {
    return _withRouteSelection(toolchainSelectionSummary, routeSummary);
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

String? _checkpointDiffSummary(Map<String, Object?> sourceControlDiff) {
  final path = _stringValue(sourceControlDiff['path']);
  if (path == null || path.isEmpty) {
    return null;
  }
  final lineCount = sourceControlDiff['lineCount'] as int?;
  if (lineCount == null) {
    return 'diff $path';
  }
  return 'diff $path $lineCount lines';
}

String? _checkpointProjectLanguageSummary(
  Map<String, Object?> projectLanguage,
) {
  final definitionCount = projectLanguage['definitionCount'] as int?;
  final referenceCount = projectLanguage['referenceCount'] as int?;
  final completionCount = projectLanguage['completionCount'] as int?;
  if (definitionCount == null &&
      referenceCount == null &&
      completionCount == null) {
    return null;
  }
  return 'language defs ${definitionCount ?? 0} refs ${referenceCount ?? 0} completions ${completionCount ?? 0}';
}

String? _checkpointLanguageServiceSummary(
  Map<String, Object?> languageServiceStatus,
) {
  final syntaxReady = languageServiceStatus['syntaxValidationReady'];
  final semanticReady = languageServiceStatus['semanticFactsReady'];
  if (syntaxReady is! bool && semanticReady is! bool) {
    return null;
  }
  return 'styio syntax ${syntaxReady == true ? 'ready' : 'not-ready'} semantic ${semanticReady == true ? 'ready' : 'not-ready'}';
}

String? _checkpointTestingSummary(Map<String, Object?> testing) {
  final hasLastRun = testing['hasLastRun'];
  final hasFailingTests = testing['hasFailingTests'];
  if (hasLastRun is! bool && hasFailingTests is! bool) {
    return null;
  }
  if (hasFailingTests == true) {
    return 'tests failing';
  }
  return hasLastRun == true ? 'tests recorded' : 'tests not-run';
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

String? _settingsRouteSummary(Map<String, Object?> metadata) {
  final settingsRoute = _stringValue(metadata['settingsRoute']);
  if (settingsRoute == null) {
    return null;
  }
  final parts = <String>['settings route $settingsRoute'];
  final settingsSection = _stringValue(metadata['settingsSection']);
  if (settingsSection != null) {
    parts.add('section $settingsSection');
  }
  final completedRequiredCommandFor = _stringValue(
    metadata['completedRequiredCommandFor'],
  );
  if (completedRequiredCommandFor != null) {
    parts.add('completed required command for $completedRequiredCommandFor');
  }
  final recoveryForCommandId = _stringValue(metadata['recoveryForCommandId']);
  if (recoveryForCommandId != null) {
    parts.add('recovery for $recoveryForCommandId');
  }
  return parts.join(' · ');
}

String? _toolchainSelectionSummary(Map<String, Object?> metadata) {
  final status = _stringValue(metadata['toolchainSelectionStatus']);
  if (status == null) {
    return null;
  }
  final parts = <String>['toolchain selection $status'];
  final toolchainId = _stringValue(metadata['toolchainId']);
  if (toolchainId != null) {
    parts.add(toolchainId);
  }
  final cppStandard = _stringValue(metadata['cppStandard']);
  if (cppStandard != null) {
    parts.add(cppStandard);
  }
  final selectionMessage = _stringValue(metadata['toolchainSelectionMessage']);
  if (selectionMessage != null) {
    parts.add(selectionMessage);
  }
  final preferredHandoff = _buildEngineHandoffSummary(
    metadata['preferredBuildEngineHandoff'],
  );
  if (preferredHandoff != null) {
    parts.add('handoff $preferredHandoff');
  } else {
    final handoffCount = metadata['buildEngineHandoffCount'];
    if (handoffCount is int) {
      parts.add('handoffs $handoffCount');
    }
  }
  return parts.join(' · ');
}

String? _buildEngineHandoffSummary(Object? value) {
  if (value is! Map<String, Object?>) {
    return null;
  }
  final engine = _stringValue(value['engineFamily']);
  if (engine == null) {
    return null;
  }
  final generator = _stringValue(value['generatorFamily']);
  return generator == null ? engine : '$engine+$generator';
}

String? _stringValue(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
