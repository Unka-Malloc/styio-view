import 'dart:convert';
import 'dart:io';

import 'edit_performance_budget.dart';
import 'rendered_input_performance_protocol.dart';

/// Raw latency arrays for one rendered profile lane before protocol summarization.
final class EditorRenderedInputLaneMeasurements {
  const EditorRenderedInputLaneMeasurements({
    required this.fixtureLineCount,
    required this.fixtureFingerprint,
    required this.operation,
    required this.glyphSubstitutionEnabled,
    required this.warmupLatencyMicros,
    required this.measuredLatencyMicros,
    required this.renderedLineCounts,
    required this.viewportLineLimit,
    this.operationSeed = 0,
  });

  final int fixtureLineCount;
  final String fixtureFingerprint;
  final EditorRenderedInputOperation operation;
  final bool glyphSubstitutionEnabled;
  final List<int> warmupLatencyMicros;
  final List<int> measuredLatencyMicros;
  final List<int> renderedLineCounts;
  final int viewportLineLimit;
  final int operationSeed;
}

/// Profile harness receipt for rendered editor input lanes.
final class EditorRenderedInputProfileReceipt {
  const EditorRenderedInputProfileReceipt({
    required this.protocolVersion,
    required this.platformFamily,
    required this.status,
    required this.lanes,
    this.viewportWidth = 1200,
    this.viewportHeight = 800,
    this.buildMode = 'profile',
    this.failureCode = '',
  });

  final String protocolVersion;
  final String platformFamily;
  final String status;
  final int viewportWidth;
  final int viewportHeight;
  final String buildMode;
  final String failureCode;
  final List<EditorRenderedInputPerformanceSample> lanes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'platformFamily': platformFamily,
      'status': status,
      'viewportWidth': viewportWidth,
      'viewportHeight': viewportHeight,
      'buildMode': buildMode,
      if (failureCode.isNotEmpty) 'failureCode': failureCode,
      'lanes': lanes.map((lane) => lane.toJson()).toList(growable: false),
    };
  }
}

/// Builds the frozen lane matrix and writes sanitized baseline evidence.
final class EditorRenderedInputProfileHarness {
  const EditorRenderedInputProfileHarness({
    this.protocol = const EditorRenderedInputSampleProtocol(),
    this.gate = const EditorEditPerformanceBudgetGate(),
  });

  final EditorRenderedInputSampleProtocol protocol;
  final EditorEditPerformanceBudgetGate gate;

  static const List<int> fixtureLineCounts = <int>[10000, 100000];
  static const List<EditorRenderedInputOperation> operations =
      EditorRenderedInputOperation.values;

  List<RenderedEditorFixture> loadFixtures() {
    return fixtureLineCounts
        .map(
          (lineCount) =>
              RenderedEditorFixtureGenerator(lineCount: lineCount).generate(),
        )
        .toList(growable: false);
  }

  EditorRenderedInputPerformanceSample buildLaneSample(
    EditorRenderedInputLaneMeasurements measurements,
  ) {
    return protocol.summarize(
      fixtureLineCount: measurements.fixtureLineCount,
      fixtureFingerprint: measurements.fixtureFingerprint,
      operation: measurements.operation,
      glyphSubstitutionEnabled: measurements.glyphSubstitutionEnabled,
      evidenceKind: EditorPerformanceEvidenceKind.renderedProfile,
      degradationState: EditorLargeFileDegradation.forLineCount(
        measurements.fixtureLineCount,
      ),
      warmupLatencyMicros: measurements.warmupLatencyMicros,
      measuredLatencyMicros: measurements.measuredLatencyMicros,
      renderedLineCounts: measurements.renderedLineCounts,
      correlatedFrameCount: measurements.measuredLatencyMicros.length,
      viewportLineLimit: measurements.viewportLineLimit,
      operationSeed: measurements.operationSeed,
    );
  }

  EditorRenderedInputProfileReceipt buildProfileReceipt({
    required String platformFamily,
    required List<EditorRenderedInputLaneMeasurements> measurements,
    int viewportWidth = 1200,
    int viewportHeight = 800,
    String buildMode = 'profile',
  }) {
    final lanes = measurements.map(buildLaneSample).toList(growable: false);
    return EditorRenderedInputProfileReceipt(
      protocolVersion: kEditorRenderedInputProtocolVersion,
      platformFamily: platformFamily,
      status: _resolveReceiptStatus(platformFamily, lanes),
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      buildMode: buildMode,
      lanes: lanes,
    );
  }

  bool receiptPassesGate(EditorRenderedInputProfileReceipt receipt) {
    if (receipt.status != 'passed') {
      return false;
    }
    for (final lane in receipt.lanes) {
      if (!gate.evaluateRendered(lane).passed) {
        return false;
      }
    }
    for (final lineCount in fixtureLineCounts) {
      for (final operation in operations) {
        final disabled = _tryLaneFor(
          receipt.lanes,
          lineCount: lineCount,
          operation: operation,
          glyphSubstitutionEnabled: false,
        );
        final enabled = _tryLaneFor(
          receipt.lanes,
          lineCount: lineCount,
          operation: operation,
          glyphSubstitutionEnabled: true,
        );
        if (disabled == null || enabled == null) {
          continue;
        }
        if (!gate
            .compareRenderedSubstitutionDelta(
              enabled: enabled,
              disabled: disabled,
            )
            .passed) {
          return false;
        }
      }
    }
    return true;
  }

  EditorRenderedInputProfileReceipt buildUnsupportedReceipt({
    required String platformFamily,
    String failureCode = 'rendered_profile_unavailable',
  }) {
    final fixtures = loadFixtures();
    final lanes = <EditorRenderedInputPerformanceSample>[];
    for (final fixture in fixtures) {
      for (final operation in operations) {
        for (final substitution in <bool>[false, true]) {
          lanes.add(
            EditorRenderedInputPerformanceSample(
              fixtureLineCount: fixture.lineCount,
              fixtureFingerprint: fixture.fingerprint,
              operation: operation,
              glyphSubstitutionEnabled: substitution,
              evidenceKind: EditorPerformanceEvidenceKind.notRun,
              degradationState: EditorLargeFileDegradation.forLineCount(
                fixture.lineCount,
              ),
              warmupCount: 0,
              sampleCount: 0,
              medianEditLatencyMicros: -1,
              p95EditLatencyMicros: -1,
              renderedLineCount: 0,
              correlatedFrameCount: 0,
              viewportLineLimit: 0,
              operationSeed: fixture.lineCount,
              failureCode: failureCode,
            ),
          );
        }
      }
    }
    return EditorRenderedInputProfileReceipt(
      protocolVersion: kEditorRenderedInputProtocolVersion,
      platformFamily: platformFamily,
      status: 'unsupported',
      failureCode: failureCode,
      lanes: lanes,
    );
  }

  void writeBaselineFiles({
    required EditorRenderedInputProfileReceipt receipt,
    required String jsonPath,
    required String markdownPath,
    String jsonProjection = 'docs/review/performance-baseline.json',
    DateTime? documentUpdatedAt,
  }) {
    final jsonFile = File(jsonPath);
    jsonFile.parent.createSync(recursive: true);
    final existing = _readExistingBaseline(jsonFile);
    existing['rendered_editor_input'] = receipt.toJson();
    jsonFile.writeAsStringSync(_encodeJson(existing));

    final markdownFile = File(markdownPath);
    markdownFile.parent.createSync(recursive: true);
    markdownFile.writeAsStringSync(
      _renderMarkdown(
        receipt,
        jsonProjection,
        documentUpdatedAt ?? DateTime.now(),
      ),
    );
  }

  Map<String, Object?> _readExistingBaseline(File jsonFile) {
    if (!jsonFile.existsSync()) {
      return <String, Object?>{};
    }
    final decoded = jsonDecode(jsonFile.readAsStringSync());
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    return <String, Object?>{};
  }

  String _encodeJson(Map<String, Object?> value) {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(value)}\n';
  }

  String _renderMarkdown(
    EditorRenderedInputProfileReceipt receipt,
    String jsonPath,
    DateTime documentUpdatedAt,
  ) {
    final updated = documentUpdatedAt.toIso8601String().substring(0, 10);
    final buffer = StringBuffer()
      ..writeln('# Performance Baseline')
      ..writeln()
      ..writeln(
        '**Purpose:** Record Vityo performance baselines for regression detection.',
      )
      ..writeln()
      ..writeln('**Last updated:** $updated')
      ..writeln()
      ..writeln('## Rendered editor input (REQ-INPUT-004)')
      ..writeln()
      ..writeln('- **Protocol:** ${receipt.protocolVersion}')
      ..writeln('- **Platform family:** ${receipt.platformFamily}')
      ..writeln('- **Status:** ${receipt.status}')
      ..writeln(
        '- **Viewport:** ${receipt.viewportWidth}×${receipt.viewportHeight}',
      )
      ..writeln('- **JSON projection:** `$jsonPath`')
      ..writeln('## Lane summary')
      ..writeln()
      ..writeln(
        '| Fixture | Operation | Substitution | Evidence | Degradation | Median µs | P95 µs | Rendered lines | Status |',
      )
      ..writeln('| --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |');

    for (final lane in receipt.lanes) {
      final evaluation = gate.evaluateRendered(lane);
      buffer.writeln(
        '| ${lane.fixtureLineCount} | ${lane.operation.label} | '
        '${lane.glyphSubstitutionEnabled ? 'on' : 'off'} | ${lane.evidenceKind.label} | '
        '${lane.degradationState.label} | ${lane.medianEditLatencyMicros} | '
        '${lane.p95EditLatencyMicros} | ${lane.renderedLineCount} | '
        '${evaluation.status.name} |',
      );
    }

    buffer
      ..writeln()
      ..writeln('## Reproduce')
      ..writeln()
      ..writeln('```sh')
      ..writeln('cd products/vityo_app')
      ..writeln(
        'flutter test --no-pub '
        '--dart-define=VITYO_RENDERED_INPUT_PROFILE=true '
        '--dart-define=VITYO_WRITE_RENDERED_INPUT_BASELINE=true '
        'test/editor_rendered_input_profile_widget_test.dart',
      )
      ..writeln('```')
      ..writeln()
      ..writeln(
        'Rendered profile evidence requires a declared desktop host. '
        'The profile widget test measures real editor frames and writes '
        'sanitized baseline evidence.',
      );
    return buffer.toString();
  }

  String _resolveReceiptStatus(
    String platformFamily,
    List<EditorRenderedInputPerformanceSample> lanes,
  ) {
    if (!platformFamily.startsWith('desktop-')) {
      return 'unsupported';
    }
    for (final lane in lanes) {
      if (!gate.evaluateRendered(lane).passed) {
        return 'failed';
      }
    }
    for (final lineCount in fixtureLineCounts) {
      for (final operation in operations) {
        final disabled = _tryLaneFor(
          lanes,
          lineCount: lineCount,
          operation: operation,
          glyphSubstitutionEnabled: false,
        );
        final enabled = _tryLaneFor(
          lanes,
          lineCount: lineCount,
          operation: operation,
          glyphSubstitutionEnabled: true,
        );
        if (disabled == null || enabled == null) {
          continue;
        }
        if (!gate
            .compareRenderedSubstitutionDelta(
              enabled: enabled,
              disabled: disabled,
            )
            .passed) {
          return 'failed';
        }
      }
    }
    return 'passed';
  }

  EditorRenderedInputPerformanceSample? _tryLaneFor(
    List<EditorRenderedInputPerformanceSample> lanes, {
    required int lineCount,
    required EditorRenderedInputOperation operation,
    required bool glyphSubstitutionEnabled,
  }) {
    for (final lane in lanes) {
      if (lane.fixtureLineCount == lineCount &&
          lane.operation == operation &&
          lane.glyphSubstitutionEnabled == glyphSubstitutionEnabled) {
        return lane;
      }
    }
    return null;
  }
}
