import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

import '../../benchmark/fixture_generator.dart';

void main() {
  group('REQ-INPUT-004 rendered large-file acceptance', () {
    test('fixtures are exact, deterministic, generated, and fingerprinted', () {
      for (final lineCount in <int>[10000, 100000]) {
        final first = FixtureGenerator(
          config: FixtureConfig(lineCount: lineCount),
        ).generateRenderedEditorFixture();
        final second = FixtureGenerator(
          config: FixtureConfig(lineCount: lineCount),
        ).generateRenderedEditorFixture();

        expect(first.lineCount, lineCount);
        expect(first.version, isNotEmpty);
        expect(first.fingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(second.fingerprint, first.fingerprint);
        expect(second.text, first.text);
        expect(first.isGenerated, isTrue);
      }
    });

    test('warmup is excluded and nearest-rank statistics are frozen', () {
      const protocol = EditorRenderedInputSampleProtocol();
      final sample = protocol.summarize(
        fixtureLineCount: 10000,
        fixtureFingerprint: List<String>.filled(64, 'a').join(),
        operation: EditorRenderedInputOperation.compositionCommit,
        glyphSubstitutionEnabled: true,
        evidenceKind: EditorPerformanceEvidenceKind.renderedProfile,
        degradationState: EditorLargeFileDegradation.viewportBounded,
        warmupLatencyMicros: List<int>.filled(10, 50000),
        measuredLatencyMicros: <int>[
          ...List<int>.filled(20, 7000),
          ...List<int>.filled(18, 15000),
          ...List<int>.filled(2, 16000),
        ],
        renderedLineCounts: List<int>.filled(40, 48),
        correlatedFrameCount: 40,
        viewportLineLimit: 64,
      );

      expect(sample.warmupCount, 10);
      expect(sample.sampleCount, 40);
      expect(sample.medianEditLatencyMicros, 7000);
      expect(sample.p95EditLatencyMicros, 15000);
      expect(sample.renderedLineCount, 48);
      expect(
        const EditorEditPerformanceBudgetGate().evaluateRendered(sample).passed,
        isTrue,
      );

      expect(
        () => protocol.summarize(
          fixtureLineCount: 10000,
          fixtureFingerprint: List<String>.filled(64, 'a').join(),
          operation: EditorRenderedInputOperation.typing,
          glyphSubstitutionEnabled: false,
          evidenceKind: EditorPerformanceEvidenceKind.renderedProfile,
          degradationState: EditorLargeFileDegradation.viewportBounded,
          warmupLatencyMicros: List<int>.filled(9, 1),
          measuredLatencyMicros: List<int>.filled(40, 1),
          renderedLineCounts: List<int>.filled(40, 1),
          correlatedFrameCount: 40,
          viewportLineLimit: 64,
        ),
        throwsArgumentError,
      );
    });

    test('synthetic, unsupported, and unbounded samples cannot pass', () {
      const gate = EditorEditPerformanceBudgetGate();
      final synthetic = _sample(
        evidenceKind: EditorPerformanceEvidenceKind.synthetic,
      );
      expect(gate.evaluateRendered(synthetic).passed, isFalse);
      expect(
        gate.evaluateRendered(synthetic).status,
        EditorEditPerformanceStatus.nonRenderedEvidence,
      );

      final unsupported = _sample(
        degradationState: EditorLargeFileDegradation.unsupported,
      );
      expect(gate.evaluateRendered(unsupported).passed, isFalse);
      expect(
        gate.evaluateRendered(unsupported).status,
        EditorEditPerformanceStatus.unsupported,
      );

      final unbounded = _sample(renderedLineCount: 401, viewportLineLimit: 64);
      expect(gate.evaluateRendered(unbounded).passed, isFalse);
      expect(
        gate.evaluateRendered(unbounded).status,
        EditorEditPerformanceStatus.unboundedRendering,
      );
    });

    test('substitution delta compares matched rendered lanes', () {
      const gate = EditorEditPerformanceBudgetGate();
      final disabled = _sample(
        glyphSubstitutionEnabled: false,
        medianMicros: 5000,
        p95Micros: 11000,
      );
      final enabledAtBudget = _sample(
        glyphSubstitutionEnabled: true,
        medianMicros: 7000,
        p95Micros: 14000,
      );
      final enabledOverBudget = _sample(
        glyphSubstitutionEnabled: true,
        medianMicros: 7000,
        p95Micros: 15000,
      );

      final passing = gate.compareRenderedSubstitutionDelta(
        enabled: enabledAtBudget,
        disabled: disabled,
      );
      expect(passing.passed, isTrue);
      expect(passing.p95DeltaMicros, 3000);

      final failing = gate.compareRenderedSubstitutionDelta(
        enabled: enabledOverBudget,
        disabled: disabled,
      );
      expect(failing.passed, isFalse);
      expect(failing.status, EditorEditPerformanceStatus.deltaOverBudget);
      expect(failing.p95DeltaMicros, 4000);
    });

    testWidgets('10k and 100k editors render only the bounded viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final lineCount in <int>[10000, 100000]) {
        final fixture = FixtureGenerator(
          config: FixtureConfig(lineCount: lineCount),
        ).generateRenderedEditorFixture();
        final controller = EditorSessionController(
          initialDocument: DocumentState(
            documentId: 'generated-$lineCount.styio',
            text: fixture.text,
            revision: 0,
          ),
          languageService: const LocalStyioLanguageService(),
        );

        await tester.pumpWidget(_harness(controller));
        await tester.pump();

        final renderedLines = find
            .byWidgetPredicate((widget) {
              final key = widget.key;
              return key is ValueKey<String> &&
                  key.value.startsWith('source-line-');
            }, skipOffstage: false)
            .evaluate()
            .length;
        expect(renderedLines, greaterThan(0));
        expect(renderedLines, lessThanOrEqualTo(400));
        expect(renderedLines, lessThan(lineCount));
        expect(
          find.byKey(
            ValueKey(
              lineCount == 10000
                  ? 'source-editor-degradation-viewportBounded'
                  : 'source-editor-degradation-largeFileReducedDecorations',
            ),
            skipOffstage: false,
          ),
          findsOneWidget,
        );

        controller.dispose();
      }
    });
  });
}

EditorRenderedInputPerformanceSample _sample({
  EditorPerformanceEvidenceKind evidenceKind =
      EditorPerformanceEvidenceKind.renderedProfile,
  EditorLargeFileDegradation degradationState =
      EditorLargeFileDegradation.viewportBounded,
  bool glyphSubstitutionEnabled = false,
  int medianMicros = 7000,
  int p95Micros = 14000,
  int renderedLineCount = 48,
  int viewportLineLimit = 64,
}) {
  return EditorRenderedInputPerformanceSample(
    fixtureLineCount: 10000,
    fixtureFingerprint: List<String>.filled(64, 'b').join(),
    operation: EditorRenderedInputOperation.typing,
    glyphSubstitutionEnabled: glyphSubstitutionEnabled,
    evidenceKind: evidenceKind,
    degradationState: degradationState,
    warmupCount: 10,
    sampleCount: 40,
    medianEditLatencyMicros: medianMicros,
    p95EditLatencyMicros: p95Micros,
    renderedLineCount: renderedLineCount,
    correlatedFrameCount: 40,
    viewportLineLimit: viewportLineLimit,
  );
}

Widget _harness(EditorSessionController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1200,
        height: 800,
        child: EditorSurface(
          controller: controller,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1200,
            height: 800,
          ),
        ),
      ),
    ),
  );
}
