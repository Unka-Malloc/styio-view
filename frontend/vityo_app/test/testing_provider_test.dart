import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
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

  test(
    'testing provider catalog supplies discovery and run providers',
    () async {
      final catalog = TestingProviderCatalog()
        ..registerDiscoveryProvider(
          const TestingDiscoveryProviderRegistration(
            id: 'styio-discovery',
            provider: StaticTestDiscoveryProvider(
              providerId: 'styio-discovery',
              result: TestDiscoveryResult(
                providerId: 'styio-discovery',
                roots: <TestNode>[
                  TestNode(
                    id: 'suite:styio',
                    label: 'Styio',
                    kind: TestNodeKind.suite,
                    children: <TestNode>[
                      TestNode(
                        id: 'test:syntax',
                        label: 'syntax',
                        kind: TestNodeKind.test,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            state: FoundationRegistryEntryState.active,
          ),
        )
        ..registerRunProvider(
          const TestingProviderRegistration(
            id: 'ctest-runner',
            provider: StaticTestRunProvider(
              providerId: 'ctest-runner',
              result: TestRunResult(
                providerId: 'ctest-runner',
                runner: 'ctest',
                status: TestRunStatus.passed,
                message: 'CTest passed.',
                totalCount: 1,
                passedCount: 1,
              ),
            ),
            state: FoundationRegistryEntryState.active,
          ),
        );
      final controller = TestingSessionController(providerCatalog: catalog);
      addTearDown(controller.dispose);

      final discovery = await controller.discover(
        const TestDiscoveryRequest(workspaceRoot: '/workspace/vityo'),
      );
      final run = await controller.run(
        const TestRunRequest(workspaceRoot: '/workspace/vityo'),
      );
      final manifest = catalog.manifest();
      final health = catalog.healthSnapshot();
      final retryPlan = catalog.retryPlan();

      expect(discovery.providerId, 'styio-discovery');
      expect(discovery.testCount, 1);
      expect(run.providerId, 'ctest-runner');
      expect(run.runner, 'ctest');
      expect(health.ready, isTrue);
      expect(health.summary, contains('discovery ready'));
      expect(health.summary, contains('run ready'));
      expect(
        retryPlan.actions.map((action) => action.id),
        containsAll(<String>[
          'testing.discovery.retry.styio-discovery',
          'testing.run.retry.ctest-runner',
        ]),
      );
      expect(
        ((manifest['run']! as Map<String, Object?>)['entries']!
            as List<Object?>),
        hasLength(1),
      );
      expect(
        ((manifest['discovery']! as Map<String, Object?>)['entries']!
            as List<Object?>),
        hasLength(1),
      );
    },
  );

  test('testing provider catalog reports missing provider retry blockers', () {
    final health = TestingProviderCatalog().healthSnapshot();
    final retryPlan = TestingProviderCatalog().retryPlan();

    expect(health.ready, isFalse);
    expect(health.hasActiveDiscoveryProvider, isFalse);
    expect(health.hasActiveRunProvider, isFalse);
    expect(health.retryActions, hasLength(2));
    expect(retryPlan.ready, isFalse);
    expect(
      retryPlan.message,
      contains('TODO: register an active testing provider'),
    );
    expect(
      retryPlan.actions.map((action) => action.toJson()['enabled']),
      everyElement(isFalse),
    );
  });

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
    final subscription = result.outputSubscriptionPlan(taskId: 'test.static.1');
    final outputEvent = result.outputEvent(
      timestamp: DateTime.utc(2026, 5, 20),
    );

    expect(result.providerId, 'static');
    expect(result.toJson()['runner'], 'fixture');
    expect(result.toJson()['status'], 'passed');
    expect(result.toJson()['totalCount'], 2);
    expect(subscription.managerId, 'testing-session');
    expect(subscription.routeKind, 'test-run');
    expect(subscription.channelIds, <String>['test.static']);
    expect(outputEvent.channelId, 'test.static');
    expect(outputEvent.metadata['status'], 'passed');
  });

  test('test run configuration builds run and discovery requests', () {
    const configuration = TestRunConfiguration(
      id: 'styio-parser',
      label: 'Styio parser fixtures',
      workspaceRoot: '/workspace/vityo',
      providerId: 'styio',
      targetId: 'parser',
      filter: 'syntax',
      debug: true,
      metadata: <String, Object?>{'source': 'fixture'},
    );

    final runRequest = configuration.toRunRequest();
    final discoveryRequest = configuration.toDiscoveryRequest();
    final json = configuration.toJson();

    expect(configuration.ready, isTrue);
    expect(runRequest.toJson(), <String, Object?>{
      'workspaceRoot': '/workspace/vityo',
      'targetId': 'parser',
      'filter': 'syntax',
      'debug': true,
    });
    expect(discoveryRequest.toJson(), <String, Object?>{
      'workspaceRoot': '/workspace/vityo',
      'targetId': 'parser',
      'filter': 'syntax',
    });
    expect(json['providerId'], 'styio');
    expect(json['metadata'], <String, Object?>{'source': 'fixture'});
  });

  test('testing session controller caches discovery and run results', () async {
    final taskController = RuntimeTaskLifecycleController(
      clock: () => DateTime.utc(2026, 5, 20),
    );
    final outputBuffer = RuntimeOutputLiveBuffer(
      subscriptionPlan: RuntimeOutputStreamSubscriptionPlan.forManager(
        taskId: 'test.static-runner.1',
        managerId: 'testing-session',
        routeKind: 'test-run',
        channelIds: const <String>['test.static-runner'],
        kinds: const <RuntimeOutputChannelKind>[
          RuntimeOutputChannelKind.runtimeEvents,
        ],
        status: RuntimeOutputSubscriptionStatus.active,
      ),
    );
    addTearDown(outputBuffer.dispose);
    final controller = TestingSessionController(
      runtimeTaskLifecycleController: taskController,
      runtimeOutputBuffer: outputBuffer,
      clock: () => DateTime.utc(2026, 5, 20, 9),
      discoveryProvider: const StaticTestDiscoveryProvider(
        providerId: 'static-discovery',
        result: TestDiscoveryResult(
          providerId: 'static-discovery',
          roots: <TestNode>[
            TestNode(
              id: 'suite:styio',
              label: 'Styio',
              kind: TestNodeKind.suite,
              children: <TestNode>[
                TestNode(
                  id: 'test:syntax',
                  label: 'syntax fixture',
                  kind: TestNodeKind.test,
                ),
              ],
            ),
          ],
        ),
      ),
      runProvider: const StaticTestRunProvider(
        providerId: 'static-runner',
        result: TestRunResult(
          providerId: 'static-runner',
          runner: 'fixture',
          status: TestRunStatus.passed,
          message: 'Fixture tests passed.',
          totalCount: 1,
          passedCount: 1,
        ),
      ),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });

    final discovery = await controller.discover(
      const TestDiscoveryRequest(workspaceRoot: '/workspace/vityo'),
    );
    final run = await controller.run(
      const TestRunRequest(workspaceRoot: '/workspace/vityo'),
    );

    expect(discovery.testCount, 1);
    expect(run.status, TestRunStatus.passed);
    expect(controller.discovery, same(discovery));
    expect(controller.lastRun, same(run));
    expect(controller.runHistory, <TestRunResult>[run]);
    expect(controller.lastRuntimeTask?.status, RuntimeTaskStatus.succeeded);
    expect(
      taskController.snapshotFor('test.static-runner.1')?.status,
      RuntimeTaskStatus.succeeded,
    );
    expect(
      (run.metadata['runtimeTask']! as Map<String, Object?>)['status'],
      'succeeded',
    );
    expect(
      (run.metadata['outputSubscription']!
          as Map<String, Object?>)['managerId'],
      'testing-session',
    );
    expect(outputBuffer.snapshot.visibleEvents, hasLength(1));
    expect(
      outputBuffer.snapshot.visibleEvents.single.message,
      'Fixture tests passed.',
    );
    expect(
      outputBuffer.snapshot.visibleEvents.single.metadata['totalCount'],
      1,
    );
    expect(notifications, 2);

    controller.clear();

    expect(controller.discovery, isNull);
    expect(controller.lastRun, isNull);
    expect(controller.runHistory, isEmpty);
    expect(notifications, 3);
  });

  test(
    'testing session controller reruns failed cases with focused filter',
    () async {
      TestRunRequest? capturedRequest;
      final controller = TestingSessionController(
        runProvider: _CapturingTestRunProvider(
          onRun: (request) {
            capturedRequest = request;
            return TestRunResult(
              providerId: 'fixture-runner',
              runner: 'fixture',
              status: TestRunStatus.passed,
              message: 'focused pass',
              totalCount: 2,
              passedCount: 2,
              metadata: <String, Object?>{'request': request.toJson()},
            );
          },
        ),
      );
      addTearDown(controller.dispose);
      controller.recordRunResult(
        const TestRunResult(
          providerId: 'fixture-runner',
          status: TestRunStatus.failed,
          message: 'two failed',
          totalCount: 3,
          failedCount: 2,
          cases: <TestCaseResult>[
            TestCaseResult(
              id: 'test:parser',
              name: 'parser rejects invalid resource',
              status: TestRunStatus.failed,
            ),
            TestCaseResult(name: 'agent.patch', status: TestRunStatus.failed),
          ],
          metadata: <String, Object?>{
            'debuggerExecutablePath': '/usr/bin/lldb-dap',
            'programPath': 'build/vityo-tests',
          },
        ),
      );

      final result = await controller.rerunFailed(
        workspaceRoot: '/workspace/vityo',
      );

      expect(result.status, TestRunStatus.passed);
      expect(capturedRequest?.workspaceRoot, '/workspace/vityo');
      expect(capturedRequest?.filter, 'test:parser|agent\\.patch');
      expect(capturedRequest?.debug, isFalse);
      expect(controller.lastRunConfiguration?.id, 'rerun-failed');
      expect(
        controller.lastRunConfiguration?.metadata['debuggerExecutablePath'],
        '/usr/bin/lldb-dap',
      );
      expect(
        controller.lastRunConfiguration?.metadata['programPath'],
        'build/vityo-tests',
      );
      expect(controller.runHistory.first, same(result));
    },
  );

  test(
    'test debug launch route planner maps failed-test configuration to DAP route',
    () {
      const lastRun = TestRunResult(
        providerId: 'ctest',
        status: TestRunStatus.failed,
        message: 'failed',
        totalCount: 2,
        failedCount: 1,
        cases: <TestCaseResult>[
          TestCaseResult(
            id: 'parser.syntax',
            name: 'parser syntax',
            status: TestRunStatus.failed,
          ),
        ],
        metadata: <String, Object?>{
          'debuggerId': 'lldb-dap',
          'debuggerLabel': 'LLDB DAP',
          'debuggerExecutablePath': '/usr/bin/lldb-dap',
          'debuggerArguments': <String>['--stdio'],
          'programPath': 'build/vityo-tests',
          'cwd': '/workspace/vityo',
          'arguments': <String>['--gtest_color=no'],
          'environment': <String, String>{'VITYO_TEST': '1'},
        },
      );
      final configuration = const FailedTestRerunPlanner().plan(
        lastRun: lastRun,
        workspaceRoot: '/workspace/vityo',
        debug: true,
      )!;

      final route = const TestDebugLaunchRoutePlanner().plan(configuration);
      final launch =
          route.handoff.plan.definition.metadata['launch']!
              as Map<String, Object?>;

      expect(configuration.debug, isTrue);
      expect(route.ready, isTrue);
      expect(route.profileId, 'test-debug.rerun-failed');
      expect(route.handoff.command, '/usr/bin/lldb-dap');
      expect(route.handoff.arguments, <String>[
        '--stdio',
        '/workspace/vityo/build/vityo-tests',
      ]);
      expect(launch['arguments'], <String>[
        '--gtest_color=no',
        '--test-filter=parser\\.syntax',
      ]);
      expect(launch['environment'], <String, String>{'VITYO_TEST': '1'});
      expect(route.toJson()['status'], 'ready');
    },
  );

  test('testing session controller records missing providers', () async {
    final controller = TestingSessionController();
    addTearDown(controller.dispose);

    final discovery = await controller.discover(
      const TestDiscoveryRequest(workspaceRoot: '/workspace/vityo'),
    );
    final run = await controller.run(
      const TestRunRequest(workspaceRoot: '/workspace/vityo'),
    );

    expect(discovery.providerId, 'unavailable');
    expect(discovery.message, contains('not configured'));
    expect(discovery.message, contains('Testing provider retry plan'));
    expect(run.providerId, 'unavailable');
    expect(run.status, TestRunStatus.error);
    expect(run.message, contains('not configured'));
    expect(run.message, contains('Testing provider retry plan'));
  });

  test(
    'testing session controller surfaces provider retry actions on failures',
    () async {
      final catalog = TestingProviderCatalog()
        ..registerDiscoveryProvider(
          const TestingDiscoveryProviderRegistration(
            id: 'throwing-discovery',
            provider: _ThrowingTestDiscoveryProvider(),
            state: FoundationRegistryEntryState.active,
          ),
        )
        ..registerRunProvider(
          const TestingProviderRegistration(
            id: 'throwing-runner',
            provider: _ThrowingTestRunProvider(),
            state: FoundationRegistryEntryState.active,
          ),
        );
      final controller = TestingSessionController(providerCatalog: catalog);
      addTearDown(controller.dispose);

      final discovery = await controller.discover(
        const TestDiscoveryRequest(workspaceRoot: '/workspace/vityo'),
      );
      final run = await controller.run(
        const TestRunRequest(workspaceRoot: '/workspace/vityo'),
      );

      expect(discovery.message, contains('Testing providers: discovery ready'));
      expect(
        discovery.message,
        contains('Retry actions: Retry discovery with throwing-discovery'),
      );
      expect(run.message, contains('Testing providers: discovery ready'));
      expect(
        run.message,
        contains('Retry actions: Retry run with throwing-runner'),
      );
    },
  );

  test('testing session controller accepts externally recorded results', () {
    final controller = TestingSessionController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications++;
    });

    controller.recordDiscoveryResult(
      const TestDiscoveryResult(
        providerId: 'external-discovery',
        roots: <TestNode>[
          TestNode(
            id: 'test:external',
            label: 'external',
            kind: TestNodeKind.test,
          ),
        ],
      ),
    );
    controller.recordRunResult(
      const TestRunResult(
        providerId: 'external-runner',
        status: TestRunStatus.notRun,
        message: 'Blocked by prerequisite.',
      ),
    );

    expect(controller.discovery?.providerId, 'external-discovery');
    expect(controller.lastRun?.providerId, 'external-runner');
    expect(controller.lastRun?.status, TestRunStatus.notRun);
    expect(controller.runHistory.single.providerId, 'external-runner');
    expect(notifications, 2);
  });

  test('test run history store persists structured run results', () async {
    final store = TestRunHistoryStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    const result = TestRunResult(
      providerId: 'ctest',
      runner: 'ctest',
      status: TestRunStatus.failed,
      message: 'One failed.',
      totalCount: 2,
      passedCount: 1,
      failedCount: 1,
      cases: <TestCaseResult>[
        TestCaseResult(
          id: 'parser.syntax',
          name: 'parser syntax',
          status: TestRunStatus.failed,
          message: 'Unexpected token.',
        ),
      ],
    );

    await store.appendRun(workspaceId: 'demo', result: result);
    final restored = await store.readHistory(workspaceId: 'demo');

    expect(restored.workspaceId, 'demo');
    expect(restored.runs.single.providerId, 'ctest');
    expect(restored.runs.single.status, TestRunStatus.failed);
    expect(restored.runs.single.failedTests.single['id'], 'parser.syntax');
    expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
    expect((await store.readHistory(workspaceId: 'demo')).runs, isEmpty);
  });

  test('testing session controller persists and reloads run history', () async {
    final store = TestRunHistoryStore.fromDataStore(
      dataStore: await _createDataStore(),
    );
    final controller = TestingSessionController(
      testRunHistoryStore: store,
      testRunHistoryWorkspaceId: 'demo',
      runProvider: const StaticTestRunProvider(
        providerId: 'static-runner',
        result: TestRunResult(
          providerId: 'static-runner',
          runner: 'fixture',
          status: TestRunStatus.passed,
          message: 'Fixture tests passed.',
          totalCount: 1,
          passedCount: 1,
        ),
      ),
    );
    addTearDown(controller.dispose);

    final run = await controller.run(
      const TestRunRequest(workspaceRoot: '/workspace/vityo'),
    );
    final restoredController = TestingSessionController(
      testRunHistoryStore: store,
      testRunHistoryWorkspaceId: 'demo',
    );
    addTearDown(restoredController.dispose);
    await restoredController.loadRunHistory();

    expect(run.status, TestRunStatus.passed);
    expect(restoredController.runHistory.single.providerId, 'static-runner');
    expect(restoredController.lastRun?.message, 'Fixture tests passed.');
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

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_test_run_history_test_',
  );
  addTearDown(() => tempRoot.delete(recursive: true));
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}

class _CapturingTestRunProvider extends TestRunProvider {
  const _CapturingTestRunProvider({required this.onRun});

  final TestRunResult Function(TestRunRequest request) onRun;

  @override
  String get providerId => 'capturing';

  @override
  Future<TestRunResult> run(TestRunRequest request) async {
    return onRun(request);
  }
}

class _ThrowingTestDiscoveryProvider extends TestDiscoveryProvider {
  const _ThrowingTestDiscoveryProvider();

  @override
  String get providerId => 'throwing-discovery';

  @override
  Future<TestDiscoveryResult> discover(TestDiscoveryRequest request) async {
    throw StateError('discovery failed');
  }
}

class _ThrowingTestRunProvider extends TestRunProvider {
  const _ThrowingTestRunProvider();

  @override
  String get providerId => 'throwing-runner';

  @override
  Future<TestRunResult> run(TestRunRequest request) async {
    throw StateError('run failed');
  }
}
