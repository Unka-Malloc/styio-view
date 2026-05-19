import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';

void main() {
  test(
    'testing provider registry resolves highest-priority active provider',
    () {
      final registry = TestingProviderRegistry()
        ..register(
          const TestingProviderRegistration(
            id: 'low',
            provider: StaticTestRunProvider(
              providerId: 'low',
              result: TestRunResult(
                providerId: 'low',
                status: TestRunStatus.passed,
                message: 'ok',
              ),
            ),
            priority: 1,
            state: FoundationRegistryEntryState.active,
          ),
        )
        ..register(
          const TestingProviderRegistration(
            id: 'high',
            provider: StaticTestRunProvider(
              providerId: 'high',
              result: TestRunResult(
                providerId: 'high',
                status: TestRunStatus.passed,
                message: 'ok',
              ),
            ),
            priority: 10,
            state: FoundationRegistryEntryState.active,
            metadata: <String, Object?>{'runner': 'ctest'},
          ),
        );

      final resolved = registry.resolve();
      final manifest = registry.manifest().toJson();
      final entries = manifest['entries']! as List<Object?>;

      expect(resolved?.id, 'high');
      expect(registry.provider(), same(resolved?.value));
      expect(entries, hasLength(2));
      expect(
        ((entries.first! as Map<String, Object?>)['metadata']!
            as Map<String, Object?>)['providerContract'],
        'test-run-provider',
      );
    },
  );

  test('static testing provider returns configured result', () async {
    const provider = StaticTestRunProvider(
      providerId: 'static',
      result: TestRunResult(
        providerId: 'static',
        runner: 'fixture',
        status: TestRunStatus.passed,
        message: 'Fixture tests passed.',
        totalCount: 2,
        passedCount: 2,
      ),
    );

    final result = await provider.run(
      const TestRunRequest(workspaceRoot: '/workspace/vityo'),
    );

    expect(result.providerId, 'static');
    expect(result.toJson()['runner'], 'fixture');
    expect(result.toJson()['status'], 'passed');
    expect(result.toJson()['totalCount'], 2);
  });

  test('test discovery result counts nested test tree', () {
    const result = TestDiscoveryResult(
      providerId: 'static',
      roots: <TestNode>[
        TestNode(
          id: 'suite:language',
          label: 'language',
          kind: TestNodeKind.suite,
          children: <TestNode>[
            TestNode(
              id: 'test:syntax',
              label: 'syntax contract',
              kind: TestNodeKind.test,
              uri: 'test/syntax_test.dart',
            ),
            TestNode(
              id: 'test:semantic',
              label: 'semantic snapshot',
              kind: TestNodeKind.test,
              uri: 'test/semantic_test.dart',
            ),
          ],
        ),
      ],
    );

    final json = result.toJson();
    final roots = json['roots']! as List<Object?>;
    final root = roots.single! as Map<String, Object?>;

    expect(result.testCount, 2);
    expect(json['testCount'], 2);
    expect(root['kind'], 'suite');
    expect(root['testCount'], 2);
  });

  test('testing discovery provider registry resolves active provider', () {
    const result = TestDiscoveryResult(
      providerId: 'discovery',
      roots: <TestNode>[],
    );
    final registry = TestingDiscoveryProviderRegistry()
      ..register(
        const TestingDiscoveryProviderRegistration(
          id: 'low-discovery',
          provider: StaticTestDiscoveryProvider(
            providerId: 'low-discovery',
            result: result,
          ),
          priority: 1,
          state: FoundationRegistryEntryState.active,
        ),
      )
      ..register(
        const TestingDiscoveryProviderRegistration(
          id: 'high-discovery',
          provider: StaticTestDiscoveryProvider(
            providerId: 'high-discovery',
            result: result,
          ),
          priority: 10,
          state: FoundationRegistryEntryState.active,
          metadata: <String, Object?>{'runner': 'ctest'},
        ),
      );

    final resolved = registry.resolve();
    final manifest = registry.manifest().toJson();
    final entries = manifest['entries']! as List<Object?>;

    expect(resolved?.id, 'high-discovery');
    expect(registry.provider(), same(resolved?.value));
    expect(
      ((entries.first! as Map<String, Object?>)['metadata']!
          as Map<String, Object?>)['providerContract'],
      'test-discovery-provider',
    );
  });

  test('CTest output parser produces structured failed test result', () {
    final result = const CTestOutputParser().parse(
      providerId: 'ctest',
      exitCode: 8,
      stdout: '''
80% tests passed, 2 tests failed out of 10

The following tests FAILED:
	  3 - syntax.contract (Failed)
	  8 - agent.patch (Timeout)
''',
    );
    final json = result.toJson();

    expect(result.status, TestRunStatus.failed);
    expect(result.runner, 'ctest');
    expect(result.totalCount, 10);
    expect(result.passedCount, 8);
    expect(result.failedCount, 2);
    expect(result.failedTests, hasLength(2));
    expect(result.failedTests.first['name'], 'syntax.contract');
    expect(json['failedTests'], isNotEmpty);
    expect(json['metadata'], <String, Object?>{'exitCode': 8});
  });
}
