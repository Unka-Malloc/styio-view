class EditorEditPerformanceSample {
  const EditorEditPerformanceSample({
    required this.glyphSubstitutionEnabled,
    required this.medianEditLatencyMicros,
    required this.p95EditLatencyMicros,
    required this.renderedLineCount,
  });

  final bool glyphSubstitutionEnabled;
  final int medianEditLatencyMicros;
  final int p95EditLatencyMicros;
  final int renderedLineCount;
}

enum EditorEditPerformanceStatus {
  passed,
  invalidSample,
  medianOverBudget,
  p95OverBudget,
  deltaOverBudget,
}

class EditorEditPerformanceResult {
  const EditorEditPerformanceResult({
    required this.status,
    required this.sample,
    required this.maxMedianMicros,
    required this.maxP95Micros,
  });

  final EditorEditPerformanceStatus status;
  final EditorEditPerformanceSample sample;
  final int maxMedianMicros;
  final int maxP95Micros;

  bool get passed => status == EditorEditPerformanceStatus.passed;
}

class EditorEditPerformanceDeltaResult {
  const EditorEditPerformanceDeltaResult({
    required this.status,
    required this.enabledSample,
    required this.disabledSample,
    required this.maxDeltaMicros,
  });

  final EditorEditPerformanceStatus status;
  final EditorEditPerformanceSample enabledSample;
  final EditorEditPerformanceSample disabledSample;
  final int maxDeltaMicros;

  bool get passed => status == EditorEditPerformanceStatus.passed;

  int get p95DeltaMicros =>
      enabledSample.p95EditLatencyMicros - disabledSample.p95EditLatencyMicros;
}

class EditorEditPerformanceBudgetGate {
  const EditorEditPerformanceBudgetGate({
    this.maxMedianMicros = 8000,
    this.maxP95Micros = 16000,
    this.maxSubstitutionDeltaMicros = 3000,
  });

  final int maxMedianMicros;
  final int maxP95Micros;
  final int maxSubstitutionDeltaMicros;

  EditorEditPerformanceResult evaluate(EditorEditPerformanceSample sample) {
    if (sample.medianEditLatencyMicros < 0 ||
        sample.p95EditLatencyMicros < 0 ||
        sample.renderedLineCount <= 0 ||
        sample.p95EditLatencyMicros < sample.medianEditLatencyMicros) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.invalidSample,
        sample: sample,
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    if (sample.medianEditLatencyMicros > maxMedianMicros) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.medianOverBudget,
        sample: sample,
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    if (sample.p95EditLatencyMicros > maxP95Micros) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.p95OverBudget,
        sample: sample,
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    return EditorEditPerformanceResult(
      status: EditorEditPerformanceStatus.passed,
      sample: sample,
      maxMedianMicros: maxMedianMicros,
      maxP95Micros: maxP95Micros,
    );
  }

  EditorEditPerformanceDeltaResult compareSubstitutionDelta({
    required EditorEditPerformanceSample enabled,
    required EditorEditPerformanceSample disabled,
  }) {
    final enabledResult = evaluate(enabled);
    if (!enabledResult.passed) {
      return EditorEditPerformanceDeltaResult(
        status: enabledResult.status,
        enabledSample: enabled,
        disabledSample: disabled,
        maxDeltaMicros: maxSubstitutionDeltaMicros,
      );
    }
    final disabledResult = evaluate(disabled);
    if (!disabledResult.passed) {
      return EditorEditPerformanceDeltaResult(
        status: disabledResult.status,
        enabledSample: enabled,
        disabledSample: disabled,
        maxDeltaMicros: maxSubstitutionDeltaMicros,
      );
    }
    final delta = enabled.p95EditLatencyMicros - disabled.p95EditLatencyMicros;
    return EditorEditPerformanceDeltaResult(
      status: delta <= maxSubstitutionDeltaMicros
          ? EditorEditPerformanceStatus.passed
          : EditorEditPerformanceStatus.deltaOverBudget,
      enabledSample: enabled,
      disabledSample: disabled,
      maxDeltaMicros: maxSubstitutionDeltaMicros,
    );
  }
}
