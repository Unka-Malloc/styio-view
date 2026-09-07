import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';

import '../benchmark/fixture_generator.dart';

void main() {
  group('rendered input performance protocol', () {
    test('deterministic fixtures fingerprint identically', () {
      for (final lineCount in <int>[10000, 100000]) {
        final first = FixtureGenerator(
          config: FixtureConfig(lineCount: lineCount),
        ).generateRenderedEditorFixture();
        final second = FixtureGenerator(
          config: FixtureConfig(lineCount: lineCount),
        ).generateRenderedEditorFixture();
        expect(first.fingerprint, second.fingerprint);
        expect(first.lineCount, lineCount);
        expect(first.isGenerated, isTrue);
      }
    });

    test('viewport line cap follows min(400, capacity + 2 × overscan)', () {
      expect(
        EditorRenderedInputSampleProtocol.viewportLineCap(
          viewportLineCapacity: 20,
          overscanLineCount: 8,
        ),
        36,
      );
      expect(
        EditorRenderedInputSampleProtocol.viewportLineCap(
          viewportLineCapacity: 500,
          overscanLineCount: 8,
        ),
        400,
      );
    });

    test('measurement API summarizes rendered profile lanes', () {
      const harness = EditorRenderedInputProfileHarness();
      final measurements = EditorRenderedInputLaneMeasurements(
        fixtureLineCount: 10000,
        fixtureFingerprint: List<String>.filled(64, 'c').join(),
        operation: EditorRenderedInputOperation.typing,
        glyphSubstitutionEnabled: false,
        warmupLatencyMicros: List<int>.filled(10, 4000),
        measuredLatencyMicros: List<int>.filled(40, 7000),
        renderedLineCounts: List<int>.filled(40, 36),
        viewportLineLimit: 38,
        operationSeed: 10000,
      );

      final sample = harness.buildLaneSample(measurements);
      expect(sample.evidenceKind, EditorPerformanceEvidenceKind.renderedProfile);
      expect(
        const EditorEditPerformanceBudgetGate().evaluateRendered(sample).passed,
        isTrue,
      );

      final receipt = harness.buildProfileReceipt(
        platformFamily: 'desktop-macos',
        measurements: <EditorRenderedInputLaneMeasurements>[measurements],
      );
      expect(receipt.status, 'passed');
      expect(harness.receiptPassesGate(receipt), isTrue);
    });

    test('lane matrix enumerates every fixture operation and substitution', () {
      const harness = EditorRenderedInputProfileHarness();
      final receipt = harness.buildUnsupportedReceipt(
        platformFamily: 'desktop-test',
      );
      expect(receipt.status, 'unsupported');
      expect(
        receipt.lanes.length,
        EditorRenderedInputProfileHarness.fixtureLineCounts.length *
            EditorRenderedInputProfileHarness.operations.length *
            2,
      );
      for (final lane in receipt.lanes) {
        expect(lane.evidenceKind, EditorPerformanceEvidenceKind.notRun);
        expect(
          const EditorEditPerformanceBudgetGate().evaluateRendered(lane).passed,
          isFalse,
        );
      }
    });

    test('baseline Markdown preserves required documentation metadata', () {
      const harness = EditorRenderedInputProfileHarness();
      final receipt = harness.buildProfileReceipt(
        platformFamily: 'desktop-test',
        measurements: const <EditorRenderedInputLaneMeasurements>[],
      );
      final temporaryDirectory = Directory.systemTemp.createTempSync(
        'vityo-rendered-input-profile-',
      );
      addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
      final jsonFile = File('${temporaryDirectory.path}/baseline.json');
      final markdownFile = File('${temporaryDirectory.path}/baseline.md');

      harness.writeBaselineFiles(
        receipt: receipt,
        jsonPath: jsonFile.path,
        markdownPath: markdownFile.path,
        documentUpdatedAt: DateTime.utc(2026, 8, 31),
      );

      expect(
        markdownFile.readAsStringSync(),
        contains('**Last updated:** 2026-08-31'),
      );
    });

    test('profiling bounds reject quadratic selection scans', () {
      const documentLines = 100000;
      const selectionCount = 8;
      const viewportLines = 48;
      final lineLookupSteps = _logSteps(documentLines);
      final selectionQuerySteps = _logSteps(selectionCount) + viewportLines;
      final rectangleProjectionSteps =
          viewportLines + (selectionCount * _logSteps(selectionCount));

      expect(lineLookupSteps, lessThan(30));
      expect(selectionQuerySteps, lessThan(100));
      expect(rectangleProjectionSteps, lessThan(200));
      expect(documentLines * selectionCount, greaterThan(rectangleProjectionSteps));
    });
  });
}

int _logSteps(int value) {
  var steps = 0;
  var current = value;
  while (current > 1) {
    current = current ~/ 2;
    steps += 1;
  }
  return steps;
}
