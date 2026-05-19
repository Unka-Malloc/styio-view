import '../foundation/foundation.dart';

enum TestRunStatus { passed, failed, skipped, error, notRun }

extension TestRunStatusWire on TestRunStatus {
  String get wireValue {
    return switch (this) {
      TestRunStatus.passed => 'passed',
      TestRunStatus.failed => 'failed',
      TestRunStatus.skipped => 'skipped',
      TestRunStatus.error => 'error',
      TestRunStatus.notRun => 'not-run',
    };
  }
}

class TestRunRequest {
  const TestRunRequest({
    required this.workspaceRoot,
    this.targetId = '',
    this.filter = '',
    this.debug = false,
  });

  final String workspaceRoot;
  final String targetId;
  final String filter;
  final bool debug;
}

class TestCaseResult {
  const TestCaseResult({
    required this.name,
    required this.status,
    this.id = '',
    this.durationMs,
    this.message = '',
  });

  final String id;
  final String name;
  final TestRunStatus status;
  final int? durationMs;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (id.isNotEmpty) 'id': id,
      'name': name,
      'status': status.wireValue,
      if (durationMs != null) 'durationMs': durationMs,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class TestRunResult {
  const TestRunResult({
    required this.providerId,
    required this.status,
    required this.message,
    this.runner = '',
    this.totalCount = 0,
    this.passedCount = 0,
    this.failedCount = 0,
    this.skippedCount = 0,
    this.cases = const <TestCaseResult>[],
    this.metadata = const <String, Object?>{},
  });

  final String providerId;
  final String runner;
  final TestRunStatus status;
  final String message;
  final int totalCount;
  final int passedCount;
  final int failedCount;
  final int skippedCount;
  final List<TestCaseResult> cases;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      if (runner.isNotEmpty) 'runner': runner,
      'status': status.wireValue,
      'message': message,
      'totalCount': totalCount,
      'passedCount': passedCount,
      'failedCount': failedCount,
      'skippedCount': skippedCount,
      if (cases.isNotEmpty)
        'cases': cases
            .map((testCase) => testCase.toJson())
            .toList(growable: false),
      if (failedTests.isNotEmpty) 'failedTests': failedTests,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  List<Map<String, Object?>> get failedTests {
    return cases
        .where((testCase) => testCase.status == TestRunStatus.failed)
        .map((testCase) => testCase.toJson())
        .toList(growable: false);
  }
}

abstract class TestRunProvider {
  const TestRunProvider();

  String get providerId;

  Future<TestRunResult> run(TestRunRequest request);
}

class StaticTestRunProvider extends TestRunProvider {
  const StaticTestRunProvider({required this.providerId, required this.result});

  @override
  final String providerId;
  final TestRunResult result;

  @override
  Future<TestRunResult> run(TestRunRequest request) async {
    return result;
  }
}

class TestingProviderRegistration {
  const TestingProviderRegistration({
    required this.id,
    required this.provider,
    this.priority = 0,
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final TestRunProvider provider;
  final int priority;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;
  final String todo;
}

class TestingProviderRegistry {
  TestingProviderRegistry({
    FoundationProviderRegistry<TestRunProvider>? registry,
  }) : _registry = registry ?? FoundationProviderRegistry<TestRunProvider>();

  static const String owner = 'interaction.testing';
  static const String runCapability = 'testing.run';
  static const String discoverCapability = 'testing.discover';

  final FoundationProviderRegistry<TestRunProvider> _registry;

  void register(TestingProviderRegistration registration) {
    _registry.register(
      FoundationProviderRegistration<TestRunProvider>(
        id: registration.id,
        owner: owner,
        provider: registration.provider,
        layer: 'interaction',
        priority: registration.priority,
        state: registration.state,
        capabilities: const <String>[runCapability],
        metadata: <String, Object?>{
          ...registration.metadata,
          'providerContract': 'test-run-provider',
        },
        todo: registration.todo,
      ),
    );
  }

  FoundationRegistryEntry<TestRunProvider>? resolve({bool activeOnly = true}) {
    return _registry.resolve(
      capability: runCapability,
      owner: owner,
      activeOnly: activeOnly,
    );
  }

  TestRunProvider? provider({bool activeOnly = true}) {
    return resolve(activeOnly: activeOnly)?.value;
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(owner: owner, state: state);
  }
}

class CTestOutputParser {
  const CTestOutputParser();

  TestRunResult parse({
    required String providerId,
    required int exitCode,
    required String stdout,
    String stderr = '',
  }) {
    final summary = _summaryPattern.firstMatch(stdout);
    final failedCases = _failedCases(stdout);
    final totalCount = int.tryParse(summary?.group(3) ?? '') ?? 0;
    final failedCount =
        int.tryParse(summary?.group(2) ?? '') ??
        (exitCode == 0 ? 0 : failedCases.length);
    final passedCount = totalCount > 0 ? totalCount - failedCount : 0;
    final status = exitCode == 0 && failedCount == 0
        ? TestRunStatus.passed
        : TestRunStatus.failed;
    final message = status == TestRunStatus.passed
        ? 'CTest completed successfully.'
        : stderr.trim().isNotEmpty
        ? stderr.trim()
        : 'CTest reported $failedCount failed test(s).';

    return TestRunResult(
      providerId: providerId,
      runner: 'ctest',
      status: status,
      message: message,
      totalCount: totalCount,
      passedCount: passedCount,
      failedCount: failedCount,
      cases: List<TestCaseResult>.unmodifiable(failedCases),
      metadata: <String, Object?>{'exitCode': exitCode},
    );
  }

  static final RegExp _summaryPattern = RegExp(
    r'(\d+)% tests passed,\s+(\d+) tests failed out of\s+(\d+)',
  );

  static final RegExp _failedTestPattern = RegExp(
    r'^\s*\d+\s+-\s+(.+?)\s+\((.+)\)\s*$',
    multiLine: true,
  );

  List<TestCaseResult> _failedCases(String output) {
    return _failedTestPattern
        .allMatches(output)
        .map(
          (match) => TestCaseResult(
            name: match.group(1)?.trim() ?? 'unknown',
            status: TestRunStatus.failed,
            message: match.group(2)?.trim() ?? 'failed',
          ),
        )
        .toList(growable: false);
  }
}
