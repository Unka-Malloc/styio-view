library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

abstract interface class ReleaseCaseExecutor {
  Future<ReleaseCaseObservation> execute(ReleaseCase testCase);
}

final class ReleaseCase {
  ReleaseCase({
    required this.id,
    required this.category,
    required Map<String, Object?> fixture,
    required Map<String, Object?> expectedFacts,
    required Set<String> allowedEffects,
    required this.maxOperations,
    required this.maxDurationMs,
    required this.maxPeakMemoryBytes,
  }) : fixture = Map<String, Object?>.unmodifiable(fixture),
       expectedFacts = Map<String, Object?>.unmodifiable(expectedFacts),
       allowedEffects = Set<String>.unmodifiable(allowedEffects);

  final String id;
  final String category;
  final Map<String, Object?> fixture;
  final Map<String, Object?> expectedFacts;
  final Set<String> allowedEffects;
  final int maxOperations;
  final int maxDurationMs;
  final int maxPeakMemoryBytes;
}

final class ReleaseCaseObservation {
  ReleaseCaseObservation({
    required Map<String, Object?> finalFacts,
    required Set<String> effects,
    required this.operations,
    required this.durationMs,
    required this.peakMemoryBytes,
  }) : finalFacts = Map<String, Object?>.unmodifiable(finalFacts),
       effects = Set<String>.unmodifiable(effects);

  final Map<String, Object?> finalFacts;
  final Set<String> effects;
  final int operations;
  final int durationMs;
  final int peakMemoryBytes;
}

final class ReleaseCaseResult {
  const ReleaseCaseResult({
    required this.id,
    required this.passed,
    required this.reason,
  });

  final String id;
  final bool passed;
  final String reason;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'passed': passed,
    'reason': reason,
  };
}

final class ReleaseEvaluationReport {
  ReleaseEvaluationReport({
    required this.corpusVersion,
    required this.casesDigest,
    required List<ReleaseCaseResult> results,
  }) : results = List<ReleaseCaseResult>.unmodifiable(results);

  final String corpusVersion;
  final String casesDigest;
  final List<ReleaseCaseResult> results;

  bool get passed =>
      results.isNotEmpty && results.every((result) => result.passed);

  Map<String, Object?> toJson() => <String, Object?>{
    'corpusVersion': corpusVersion,
    'casesDigest': casesDigest,
    'passed': passed,
    'results': <Map<String, Object?>>[
      for (final result in results) result.toJson(),
    ],
  };
}

final class ReleaseEvaluationRunner {
  const ReleaseEvaluationRunner();

  Future<ReleaseEvaluationReport> run({
    required Map<String, Object?> manifest,
    required ReleaseCaseExecutor executor,
  }) async {
    final rawCases = (manifest['cases'] as List<Object?>)
        .cast<Map<String, Object?>>();
    final digest = sha256.convert(utf8.encode(jsonEncode(rawCases))).toString();
    if (manifest['schemaVersion'] != 1 ||
        manifest['corpusVersion'] is! String ||
        manifest['casesDigest'] != digest ||
        rawCases.isEmpty) {
      throw StateError('Release corpus manifest is invalid.');
    }
    final ids = <String>{};
    final cases = <ReleaseCase>[];
    for (final raw in rawCases) {
      final testCase = _decodeCase(raw);
      if (!ids.add(testCase.id)) {
        throw StateError('Release corpus case IDs must be unique.');
      }
      cases.add(testCase);
    }

    final results = <ReleaseCaseResult>[];
    for (final testCase in cases) {
      ReleaseCaseObservation observation;
      try {
        observation = await executor.execute(testCase);
      } on Object {
        results.add(
          ReleaseCaseResult(
            id: testCase.id,
            passed: false,
            reason: 'executor_failed',
          ),
        );
        continue;
      }
      results.add(_evaluate(testCase, observation));
    }
    return ReleaseEvaluationReport(
      corpusVersion: manifest['corpusVersion']! as String,
      casesDigest: digest,
      results: results,
    );
  }

  static ReleaseCase _decodeCase(Map<String, Object?> raw) {
    final fixture = raw['fixture'] as Map<String, Object?>;
    final expected = raw['expected'] as Map<String, Object?>;
    final budgets = raw['budgets'] as Map<String, Object?>;
    final effects = (expected['allowedEffects'] as List<Object?>)
        .cast<String>();
    final testCase = ReleaseCase(
      id: raw['id']! as String,
      category: raw['category']! as String,
      fixture: fixture,
      expectedFacts: expected['finalFacts']! as Map<String, Object?>,
      allowedEffects: effects.toSet(),
      maxOperations: budgets['maxOperations']! as int,
      maxDurationMs: budgets['maxDurationMs']! as int,
      maxPeakMemoryBytes: budgets['maxPeakMemoryBytes']! as int,
    );
    if (testCase.id.trim().isEmpty ||
        testCase.category.trim().isEmpty ||
        testCase.fixture['provider'] != 'deterministic-fake-v1' ||
        testCase.maxOperations <= 0 ||
        testCase.maxDurationMs <= 0 ||
        testCase.maxPeakMemoryBytes <= 0) {
      throw StateError('Release corpus case is invalid.');
    }
    return testCase;
  }

  static ReleaseCaseResult _evaluate(
    ReleaseCase testCase,
    ReleaseCaseObservation observation,
  ) {
    if (observation.operations < 0 ||
        observation.operations > testCase.maxOperations) {
      return ReleaseCaseResult(
        id: testCase.id,
        passed: false,
        reason: 'operation_budget_exceeded',
      );
    }
    if (observation.durationMs < 0 ||
        observation.durationMs > testCase.maxDurationMs) {
      return ReleaseCaseResult(
        id: testCase.id,
        passed: false,
        reason: 'latency_budget_exceeded',
      );
    }
    if (observation.peakMemoryBytes < 0 ||
        observation.peakMemoryBytes > testCase.maxPeakMemoryBytes) {
      return ReleaseCaseResult(
        id: testCase.id,
        passed: false,
        reason: 'memory_budget_exceeded',
      );
    }
    if (!testCase.allowedEffects.containsAll(observation.effects)) {
      return ReleaseCaseResult(
        id: testCase.id,
        passed: false,
        reason: 'effect_not_allowed',
      );
    }
    for (final expected in testCase.expectedFacts.entries) {
      if (!_jsonEqual(observation.finalFacts[expected.key], expected.value)) {
        return ReleaseCaseResult(
          id: testCase.id,
          passed: false,
          reason: 'final_fact_mismatch',
        );
      }
    }
    return ReleaseCaseResult(id: testCase.id, passed: true, reason: 'passed');
  }
}

bool _jsonEqual(Object? left, Object? right) =>
    jsonEncode(left) == jsonEncode(right);
