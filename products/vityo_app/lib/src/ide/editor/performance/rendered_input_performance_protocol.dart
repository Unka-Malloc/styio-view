import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'edit_performance_budget.dart';

/// Frozen protocol identifier for rendered editor input evidence.
const String kEditorRenderedInputProtocolVersion = 'req-input-004-v1';

/// Operation families measured on large generated fixtures.
enum EditorRenderedInputOperation {
  typing,
  compositionUpdate,
  compositionCommit,
  multiCursorMovement,
  rectangularProjection,
  viewportMovement;

  String get label => switch (this) {
    EditorRenderedInputOperation.typing => 'typing',
    EditorRenderedInputOperation.compositionUpdate => 'compositionUpdate',
    EditorRenderedInputOperation.compositionCommit => 'compositionCommit',
    EditorRenderedInputOperation.multiCursorMovement => 'multiCursorMovement',
    EditorRenderedInputOperation.rectangularProjection =>
      'rectangularProjection',
    EditorRenderedInputOperation.viewportMovement => 'viewportMovement',
  };

  static EditorRenderedInputOperation? parse(String? value) {
    if (value == null) return null;
    for (final operation in EditorRenderedInputOperation.values) {
      if (operation.label == value) return operation;
    }
    return null;
  }
}

/// Evidence lane classification. Synthetic clocks may test rejection only.
enum EditorPerformanceEvidenceKind {
  renderedProfile,
  synthetic,
  unsupported,
  notRun;

  String get label => name;

  static EditorPerformanceEvidenceKind? parse(String? value) {
    if (value == null) return null;
    for (final kind in EditorPerformanceEvidenceKind.values) {
      if (kind.label == value) return kind;
    }
    return null;
  }
}

/// Truthful large-file render degradation exposed to UI and semantics.
enum EditorLargeFileDegradation {
  viewportBounded,
  largeFileReducedDecorations,
  unsupported;

  String get label => name;

  static EditorLargeFileDegradation forLineCount(int lineCount) {
    if (lineCount <= 0) {
      return EditorLargeFileDegradation.unsupported;
    }
    if (lineCount <= 10000) {
      return EditorLargeFileDegradation.viewportBounded;
    }
    return EditorLargeFileDegradation.largeFileReducedDecorations;
  }

  static EditorLargeFileDegradation? parse(String? value) {
    if (value == null) return null;
    for (final state in EditorLargeFileDegradation.values) {
      if (state.label == value) return state;
    }
    return null;
  }
}

/// Deterministic generated fixture metadata for rendered editor lanes.
final class RenderedEditorFixture {
  const RenderedEditorFixture({
    required this.version,
    required this.lineCount,
    required this.text,
    required this.fingerprint,
    required this.isGenerated,
  });

  final String version;
  final int lineCount;
  final String text;
  final String fingerprint;
  final bool isGenerated;
}

/// Summarized rendered input lane sample after warmups are excluded.
final class EditorRenderedInputPerformanceSample {
  const EditorRenderedInputPerformanceSample({
    required this.fixtureLineCount,
    required this.fixtureFingerprint,
    required this.operation,
    required this.glyphSubstitutionEnabled,
    required this.evidenceKind,
    required this.degradationState,
    required this.warmupCount,
    required this.sampleCount,
    required this.medianEditLatencyMicros,
    required this.p95EditLatencyMicros,
    required this.renderedLineCount,
    required this.correlatedFrameCount,
    required this.viewportLineLimit,
    this.protocolVersion = kEditorRenderedInputProtocolVersion,
    this.fixtureVersion = kRenderedEditorFixtureVersion,
    this.operationSeed = 0,
    this.failureCode = '',
  });

  final String protocolVersion;
  final String fixtureVersion;
  final int fixtureLineCount;
  final String fixtureFingerprint;
  final EditorRenderedInputOperation operation;
  final bool glyphSubstitutionEnabled;
  final EditorPerformanceEvidenceKind evidenceKind;
  final EditorLargeFileDegradation degradationState;
  final int warmupCount;
  final int sampleCount;
  final int medianEditLatencyMicros;
  final int p95EditLatencyMicros;
  final int renderedLineCount;
  final int correlatedFrameCount;
  final int viewportLineLimit;
  final int operationSeed;
  final String failureCode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protocolVersion': protocolVersion,
      'fixtureVersion': fixtureVersion,
      'fixtureLineCount': fixtureLineCount,
      'fixtureFingerprint': fixtureFingerprint,
      'operation': operation.label,
      'glyphSubstitutionEnabled': glyphSubstitutionEnabled,
      'evidenceKind': evidenceKind.label,
      'degradationState': degradationState.label,
      'warmupCount': warmupCount,
      'sampleCount': sampleCount,
      'medianEditLatencyMicros': medianEditLatencyMicros,
      'p95EditLatencyMicros': p95EditLatencyMicros,
      'renderedLineCount': renderedLineCount,
      'correlatedFrameCount': correlatedFrameCount,
      'viewportLineLimit': viewportLineLimit,
      'operationSeed': operationSeed,
      if (failureCode.isNotEmpty) 'failureCode': failureCode,
    };
  }

  factory EditorRenderedInputPerformanceSample.fromJson(
    Map<String, Object?> json,
  ) {
    final operation = EditorRenderedInputOperation.parse(
      json['operation'] as String?,
    );
    final evidenceKind = EditorPerformanceEvidenceKind.parse(
      json['evidenceKind'] as String?,
    );
    final degradationState = EditorLargeFileDegradation.parse(
      json['degradationState'] as String?,
    );
    if (operation == null || evidenceKind == null || degradationState == null) {
      throw const FormatException(
        'Invalid rendered input performance sample JSON.',
      );
    }
    return EditorRenderedInputPerformanceSample(
      protocolVersion:
          json['protocolVersion'] as String? ??
          kEditorRenderedInputProtocolVersion,
      fixtureVersion:
          json['fixtureVersion'] as String? ?? kRenderedEditorFixtureVersion,
      fixtureLineCount: json['fixtureLineCount'] as int? ?? 0,
      fixtureFingerprint: json['fixtureFingerprint'] as String? ?? '',
      operation: operation,
      glyphSubstitutionEnabled:
          json['glyphSubstitutionEnabled'] as bool? ?? false,
      evidenceKind: evidenceKind,
      degradationState: degradationState,
      warmupCount: json['warmupCount'] as int? ?? 0,
      sampleCount: json['sampleCount'] as int? ?? 0,
      medianEditLatencyMicros: json['medianEditLatencyMicros'] as int? ?? -1,
      p95EditLatencyMicros: json['p95EditLatencyMicros'] as int? ?? -1,
      renderedLineCount: json['renderedLineCount'] as int? ?? 0,
      correlatedFrameCount: json['correlatedFrameCount'] as int? ?? 0,
      viewportLineLimit: json['viewportLineLimit'] as int? ?? 0,
      operationSeed: json['operationSeed'] as int? ?? 0,
      failureCode: json['failureCode'] as String? ?? '',
    );
  }
}

/// Frozen fixture generator version correlated with acceptance fingerprints.
const String kRenderedEditorFixtureVersion = 'rendered-editor-fixture-v1';

/// Generates deterministic large fixtures and summarizes rendered samples.
final class EditorRenderedInputSampleProtocol {
  const EditorRenderedInputSampleProtocol({
    this.requiredWarmupCount = 10,
    this.requiredSampleCount = 40,
  });

  final int requiredWarmupCount;
  final int requiredSampleCount;

  static int nearestRankStatistic(List<int> sortedSamples, double rank) {
    if (sortedSamples.isEmpty) {
      throw ArgumentError.value(
        sortedSamples,
        'sortedSamples',
        'must not be empty',
      );
    }
    final index = (rank * sortedSamples.length).ceil() - 1;
    return sortedSamples[index.clamp(0, sortedSamples.length - 1)];
  }

  EditorRenderedInputPerformanceSample summarize({
    required int fixtureLineCount,
    required String fixtureFingerprint,
    required EditorRenderedInputOperation operation,
    required bool glyphSubstitutionEnabled,
    required EditorPerformanceEvidenceKind evidenceKind,
    required EditorLargeFileDegradation degradationState,
    required List<int> warmupLatencyMicros,
    required List<int> measuredLatencyMicros,
    required List<int> renderedLineCounts,
    required int correlatedFrameCount,
    required int viewportLineLimit,
    int operationSeed = 0,
  }) {
    if (warmupLatencyMicros.length != requiredWarmupCount) {
      throw ArgumentError.value(
        warmupLatencyMicros,
        'warmupLatencyMicros',
        'must contain exactly $requiredWarmupCount warmups',
      );
    }
    if (measuredLatencyMicros.length != requiredSampleCount) {
      throw ArgumentError.value(
        measuredLatencyMicros,
        'measuredLatencyMicros',
        'must contain exactly $requiredSampleCount measured samples',
      );
    }
    if (renderedLineCounts.length != requiredSampleCount) {
      throw ArgumentError.value(
        renderedLineCounts,
        'renderedLineCounts',
        'must contain exactly $requiredSampleCount rendered counts',
      );
    }
    if (correlatedFrameCount != requiredSampleCount) {
      throw ArgumentError.value(
        correlatedFrameCount,
        'correlatedFrameCount',
        'must equal $requiredSampleCount correlated frames',
      );
    }

    final sorted = List<int>.from(measuredLatencyMicros)..sort();
    final median = nearestRankStatistic(sorted, 0.50);
    final p95 = nearestRankStatistic(sorted, 0.95);
    final maxRendered = renderedLineCounts.reduce(
      (current, next) => current > next ? current : next,
    );

    return EditorRenderedInputPerformanceSample(
      fixtureLineCount: fixtureLineCount,
      fixtureFingerprint: fixtureFingerprint,
      operation: operation,
      glyphSubstitutionEnabled: glyphSubstitutionEnabled,
      evidenceKind: evidenceKind,
      degradationState: degradationState,
      warmupCount: warmupLatencyMicros.length,
      sampleCount: measuredLatencyMicros.length,
      medianEditLatencyMicros: median,
      p95EditLatencyMicros: p95,
      renderedLineCount: maxRendered,
      correlatedFrameCount: correlatedFrameCount,
      viewportLineLimit: viewportLineLimit,
      operationSeed: operationSeed,
    );
  }

  /// Computes the bounded viewport line cap: min(400, capacity + 2 × overscan).
  static int viewportLineCap({
    required int viewportLineCapacity,
    required int overscanLineCount,
    int hardCap = 400,
  }) {
    final expanded = viewportLineCapacity + (overscanLineCount * 2);
    return expanded < hardCap ? expanded : hardCap;
  }
}

/// Deterministic large-document fixture generator for rendered lanes.
final class RenderedEditorFixtureGenerator {
  const RenderedEditorFixtureGenerator({required this.lineCount});

  final int lineCount;

  RenderedEditorFixture generate() {
    if (lineCount != 10000 && lineCount != 100000) {
      throw ArgumentError.value(
        lineCount,
        'lineCount',
        'rendered fixtures must be exactly 10000 or 100000 lines',
      );
    }
    final buffer = StringBuffer();
    for (var index = 0; index < lineCount; index += 1) {
      final lineLength = 24 + (index % 17);
      final codeUnitBase = 0x61 + (index * 17 % 26);
      buffer.write(
        List.generate(lineLength, (offset) {
          final codeUnit = codeUnitBase + (offset % 5);
          return String.fromCharCode(codeUnit);
        }).join(),
      );
      if (index < lineCount - 1) {
        buffer.write('\n');
      }
    }
    final text = buffer.toString();
    final digest = sha256.convert(utf8.encode(text)).toString();
    return RenderedEditorFixture(
      version: kRenderedEditorFixtureVersion,
      lineCount: lineCount,
      text: text,
      fingerprint: digest,
      isGenerated: true,
    );
  }
}

extension EditorEditPerformanceBudgetGateRendered
    on EditorEditPerformanceBudgetGate {
  EditorEditPerformanceResult evaluateRendered(
    EditorRenderedInputPerformanceSample sample,
  ) {
    if (sample.evidenceKind == EditorPerformanceEvidenceKind.synthetic) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.nonRenderedEvidence,
        sample: _toLegacySample(sample),
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    if (sample.evidenceKind == EditorPerformanceEvidenceKind.unsupported ||
        sample.evidenceKind == EditorPerformanceEvidenceKind.notRun ||
        sample.degradationState == EditorLargeFileDegradation.unsupported) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.unsupported,
        sample: _toLegacySample(sample),
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    if (sample.evidenceKind != EditorPerformanceEvidenceKind.renderedProfile) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.nonRenderedEvidence,
        sample: _toLegacySample(sample),
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    if (sample.warmupCount != 10 ||
        sample.sampleCount != 40 ||
        sample.correlatedFrameCount != 40) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.invalidSample,
        sample: _toLegacySample(sample),
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    if (sample.renderedLineCount > sample.viewportLineLimit) {
      return EditorEditPerformanceResult(
        status: EditorEditPerformanceStatus.unboundedRendering,
        sample: _toLegacySample(sample),
        maxMedianMicros: maxMedianMicros,
        maxP95Micros: maxP95Micros,
      );
    }
    return evaluate(_toLegacySample(sample));
  }

  EditorEditPerformanceDeltaResult compareRenderedSubstitutionDelta({
    required EditorRenderedInputPerformanceSample enabled,
    required EditorRenderedInputPerformanceSample disabled,
  }) {
    if (enabled.fixtureFingerprint != disabled.fixtureFingerprint ||
        enabled.fixtureLineCount != disabled.fixtureLineCount ||
        enabled.operation != disabled.operation ||
        enabled.operationSeed != disabled.operationSeed) {
      return EditorEditPerformanceDeltaResult(
        status: EditorEditPerformanceStatus.invalidSample,
        enabledSample: _toLegacySample(enabled),
        disabledSample: _toLegacySample(disabled),
        maxDeltaMicros: maxSubstitutionDeltaMicros,
      );
    }
    final enabledResult = evaluateRendered(enabled);
    if (!enabledResult.passed) {
      return EditorEditPerformanceDeltaResult(
        status: enabledResult.status,
        enabledSample: enabledResult.sample,
        disabledSample: _toLegacySample(disabled),
        maxDeltaMicros: maxSubstitutionDeltaMicros,
      );
    }
    final disabledResult = evaluateRendered(disabled);
    if (!disabledResult.passed) {
      return EditorEditPerformanceDeltaResult(
        status: disabledResult.status,
        enabledSample: enabledResult.sample,
        disabledSample: disabledResult.sample,
        maxDeltaMicros: maxSubstitutionDeltaMicros,
      );
    }
    return compareSubstitutionDelta(
      enabled: enabledResult.sample,
      disabled: disabledResult.sample,
    );
  }

  EditorEditPerformanceSample _toLegacySample(
    EditorRenderedInputPerformanceSample sample,
  ) {
    return EditorEditPerformanceSample(
      glyphSubstitutionEnabled: sample.glyphSubstitutionEnabled,
      medianEditLatencyMicros: sample.medianEditLatencyMicros,
      p95EditLatencyMicros: sample.p95EditLatencyMicros,
      renderedLineCount: sample.renderedLineCount,
    );
  }
}
