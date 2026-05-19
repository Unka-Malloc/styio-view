import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';

void main() {
  test('edit performance budget accepts substitution enabled baseline', () {
    const gate = EditorEditPerformanceBudgetGate();

    final result = gate.evaluate(
      const EditorEditPerformanceSample(
        glyphSubstitutionEnabled: true,
        medianEditLatencyMicros: 7000,
        p95EditLatencyMicros: 14000,
        renderedLineCount: 400,
      ),
    );

    expect(result.passed, isTrue);
    expect(result.status, EditorEditPerformanceStatus.passed);
  });

  test('edit performance budget rejects substitution disabled baseline over p95', () {
    const gate = EditorEditPerformanceBudgetGate();

    final result = gate.evaluate(
      const EditorEditPerformanceSample(
        glyphSubstitutionEnabled: false,
        medianEditLatencyMicros: 7000,
        p95EditLatencyMicros: 17000,
        renderedLineCount: 400,
      ),
    );

    expect(result.passed, isFalse);
    expect(result.status, EditorEditPerformanceStatus.p95OverBudget);
  });

  test('edit performance budget rejects substitution delta over budget', () {
    const gate = EditorEditPerformanceBudgetGate();

    final result = gate.compareSubstitutionDelta(
      enabled: const EditorEditPerformanceSample(
        glyphSubstitutionEnabled: true,
        medianEditLatencyMicros: 7000,
        p95EditLatencyMicros: 15000,
        renderedLineCount: 400,
      ),
      disabled: const EditorEditPerformanceSample(
        glyphSubstitutionEnabled: false,
        medianEditLatencyMicros: 5000,
        p95EditLatencyMicros: 11000,
        renderedLineCount: 400,
      ),
    );

    expect(result.passed, isFalse);
    expect(result.status, EditorEditPerformanceStatus.deltaOverBudget);
    expect(result.p95DeltaMicros, 4000);
  });
}
