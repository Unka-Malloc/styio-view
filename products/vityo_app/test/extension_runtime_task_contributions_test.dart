import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test(
    'extension runtime task catalog converts task routes to definitions',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.tasks',
            displayName: 'Styio Tasks',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'tasks.dart',
            trustedByDefault: true,
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.task,
                id: 'styio.build',
                target: 'runtime.tasks',
                title: 'Build Styio',
                metadata: <String, Object?>{
                  'taskId': 'build.styio',
                  'kind': 'build',
                  'command': 'ninja',
                  'arguments': <String>['-C', 'build'],
                  'workingDirectory': '/workspace/styio',
                  'environment': <String, String>{'CC': 'clang'},
                  'group': 'build',
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );

      final catalog = ExtensionRuntimeTaskContributionCatalog.fromRoutes(
        routes,
      );
      final definition = catalog.readyDefinitions.single;

      expect(definition.id, 'build.styio');
      expect(definition.kind, RuntimeTaskKind.build);
      expect(definition.command, 'ninja');
      expect(definition.arguments, <String>['-C', 'build']);
      expect(definition.environment['CC'], 'clang');
      expect(definition.metadata['extensionId'], 'styio.tasks');
      expect(catalog.toJson()['readyDefinitionCount'], 1);
    },
  );

  test(
    'extension runtime task execution bridge dispatches contribution routes',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.tasks',
            displayName: 'Styio Tasks',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'tasks.dart',
            trustedByDefault: true,
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.task,
                id: 'styio.build',
                target: 'runtime.tasks',
                title: 'Build Styio',
                metadata: <String, Object?>{
                  'taskId': 'build.styio',
                  'kind': 'build',
                  'command': 'ninja',
                  'arguments': <String>['-C', 'build'],
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );
      final catalog = ExtensionRuntimeTaskContributionCatalog.fromRoutes(
        routes,
      );
      final plan = ExtensionRuntimeTaskExecutionPlan.fromContribution(
        catalog.contributions.single,
      );
      final buffer = RuntimeOutputLiveBuffer();
      final telemetry = ExtensionRuntimeTaskInMemoryTelemetrySink();
      final bridge = ExtensionRuntimeTaskExecutionBridge(
        telemetrySink: telemetry,
      );

      final dispatch = bridge.dispatchToLiveBuffer(
        plan: plan,
        buffer: buffer,
        timestamp: DateTime.utc(2026, 5, 20, 19),
      );
      final retry = bridge.recordRetry(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 20, 19, 1),
        reason: 'Retry after transient extension task failure.',
        metadata: const <String, Object?>{'attempt': 2},
      );
      final cancellation = bridge.recordCancellation(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 20, 19, 2),
        reason: 'User cancelled extension task.',
        metadata: const <String, Object?>{'processHandleId': 'task-1'},
      );

      expect(plan.ready, isTrue);
      expect(plan.binding.managerId, 'toolchain-manager');
      expect(
        plan.binding.outputChannel.kind,
        RuntimeOutputChannelKind.nativeTools,
      );
      expect(dispatch.status, RuntimeExecutionDispatchStatus.dispatched);
      expect(
        buffer.snapshot.visibleEvents.single.metadata['extensionId'],
        'styio.tasks',
      );
      expect(telemetry.records.map((record) => record.kind), <Object>[
        ExtensionRuntimeTaskTelemetryKind.dispatch,
        ExtensionRuntimeTaskTelemetryKind.retry,
        ExtensionRuntimeTaskTelemetryKind.cancellation,
      ]);
      expect(retry.toJson()['message'], contains('Retry'));
      expect(cancellation.toJson()['message'], contains('cancelled'));
      expect(plan.toJson()['ready'], isTrue);
    },
  );

  test('extension runtime task telemetry persists through DataStore', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_extension_runtime_task_telemetry_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final sink = ExtensionRuntimeTaskDataStoreTelemetrySink.fromDataStore(
      dataStore: _createDataStore(tempRoot),
      workspaceId: 'demo',
      maxRecords: 2,
    );
    final plan = ExtensionRuntimeTaskExecutionPlan.fromContribution(
      const ExtensionRuntimeTaskContribution(
        extensionId: 'styio.tasks',
        contributionId: 'build',
        target: 'runtime.tasks',
        status: ExtensionRuntimeTaskContributionStatus.ready,
        message: 'ready',
        definition: RuntimeTaskDefinition(
          id: 'build',
          label: 'Build',
          kind: RuntimeTaskKind.build,
          command: 'styio',
          arguments: <String>['build'],
        ),
      ),
    );

    sink
      ..record(
        ExtensionRuntimeTaskTelemetryRecord.retry(
          plan: plan,
          timestamp: DateTime.utc(2026, 5, 21, 1),
          reason: 'first retry',
        ),
      )
      ..record(
        ExtensionRuntimeTaskTelemetryRecord.retry(
          plan: plan,
          timestamp: DateTime.utc(2026, 5, 21, 1, 1),
          reason: 'retry after failure',
        ),
      )
      ..record(
        ExtensionRuntimeTaskTelemetryRecord.cancellation(
          plan: plan,
          timestamp: DateTime.utc(2026, 5, 21, 1, 2),
          reason: 'cancelled by user',
          metadata: const <String, Object?>{'processHandleId': 'task-1'},
        ),
      );

    await sink.flush();
    final snapshot = await sink.readTelemetry();

    expect(snapshot.workspaceId, 'demo');
    expect(snapshot.records, hasLength(2));
    expect(snapshot.records.map((record) => record.kind), <Object>[
      ExtensionRuntimeTaskTelemetryKind.cancellation,
      ExtensionRuntimeTaskTelemetryKind.retry,
    ]);
    expect(snapshot.records.first.metadata['processHandleId'], 'task-1');
    expect(snapshot.toJson()['recordCount'], 2);
  });

  test('extension runtime task retry policy plans backoff windows', () {
    final plan = _createRuntimeTaskPlan();
    const policy = ExtensionRuntimeTaskRetryPolicy(
      maxAttempts: 3,
      initialDelay: Duration(milliseconds: 100),
      backoffMultiplier: 3,
    );

    final firstRetry = ExtensionRuntimeTaskRetryPlan.fromFailure(
      plan: plan,
      failedAttempt: 1,
      failureKind: ExtensionRuntimeTaskRetryFailureKind.transient,
      reason: 'transient worker failure',
      policy: policy,
    );
    final secondRetry = ExtensionRuntimeTaskRetryPlan.fromFailure(
      plan: plan,
      failedAttempt: 2,
      failureKind: ExtensionRuntimeTaskRetryFailureKind.timeout,
      policy: policy,
    );
    final exhausted = ExtensionRuntimeTaskRetryPlan.fromFailure(
      plan: plan,
      failedAttempt: 3,
      failureKind: ExtensionRuntimeTaskRetryFailureKind.unavailable,
      policy: policy,
    );
    final invalidConfiguration = ExtensionRuntimeTaskRetryPlan.fromFailure(
      plan: plan,
      failedAttempt: 1,
      failureKind: ExtensionRuntimeTaskRetryFailureKind.invalidConfiguration,
      policy: policy,
    );

    expect(firstRetry.retryable, isTrue);
    expect(firstRetry.nextAttempt, 2);
    expect(
      firstRetry.delayBeforeNextAttempt,
      const Duration(milliseconds: 100),
    );
    expect(firstRetry.toJson()['extensionId'], 'styio.tasks');
    expect(firstRetry.toJson()['contributionId'], 'build');
    expect(firstRetry.toJson()['failureKind'], 'transient');
    expect(firstRetry.toJson()['policy'], policy.toJson());
    expect(firstRetry.message, contains('transient worker failure'));
    expect(secondRetry.retryable, isTrue);
    expect(
      secondRetry.delayBeforeNextAttempt,
      const Duration(milliseconds: 300),
    );
    expect(exhausted.retryable, isFalse);
    expect(exhausted.nextAttempt, 3);
    expect(exhausted.delayBeforeNextAttempt, Duration.zero);
    expect(invalidConfiguration.retryable, isFalse);
  });

  test(
    'extension runtime task cancellation registry binds process handles',
    () {
      final plan = _createRuntimeTaskPlan();
      final registry = ExtensionRuntimeTaskCancellationRegistry();

      final handle = registry.register(
        plan: plan,
        processHandleId: 'process-build-1',
        metadata: const <String, Object?>{'pid': 42},
      );
      final requested = registry.requestCancellation(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 21, 2),
        reason: 'user cancelled task',
        metadata: const <String, Object?>{'source': 'editor'},
      );
      final missing = ExtensionRuntimeTaskCancellationRegistry()
          .requestCancellation(
            plan: plan,
            timestamp: DateTime.utc(2026, 5, 21, 2, 1),
            reason: 'missing process handle',
          );

      expect(handle.state, ExtensionRuntimeTaskCancellationState.registered);
      expect(handle.canCancel, isTrue);
      expect(handle.toJson()['processHandleId'], 'process-build-1');
      expect(requested.state, ExtensionRuntimeTaskCancellationState.requested);
      expect(requested.canCancel, isTrue);
      expect(requested.message, contains('user cancelled task'));
      expect(requested.toJson()['requestedAt'], '2026-05-21T02:00:00.000Z');
      expect(requested.metadata['pid'], 42);
      expect(requested.metadata['source'], 'editor');
      expect(registry.lookup(plan)?.state, requested.state);
      expect(missing.state, ExtensionRuntimeTaskCancellationState.unavailable);
      expect(missing.canCancel, isFalse);
    },
  );

  test(
    'extension runtime task bridge dispatches cancellation adapters',
    () async {
      final plan = _createRuntimeTaskPlan();
      final telemetry = ExtensionRuntimeTaskInMemoryTelemetrySink();
      final cancelledHandles = <String>[];
      final bridge = ExtensionRuntimeTaskExecutionBridge(
        telemetrySink: telemetry,
        cancellationAdapters: <ExtensionRuntimeTaskCancellationAdapter>[
          ExtensionRuntimeTaskCancellationAdapter(
            managerId: 'toolchain-manager',
            routeKinds: const <String>['toolchain-task'],
            cancel:
                ({
                  required plan,
                  required handle,
                  required timestamp,
                  required reason,
                }) async {
                  cancelledHandles.add(handle.processHandleId);
                  return const ExtensionRuntimeTaskCancellationAdapterResult.accepted(
                    processTerminated: true,
                    message: 'Terminated extension task process.',
                    metadata: <String, Object?>{'pid': 42},
                  );
                },
          ),
        ],
      );

      final handle = bridge.registerCancellationHandle(
        plan: plan,
        processHandleId: 'process-build-1',
        metadata: const <String, Object?>{'source': 'toolchain'},
      );
      final result = await bridge.dispatchCancellation(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 21, 3),
        reason: 'user cancelled build',
        metadata: const <String, Object?>{'source': 'editor'},
      );

      expect(handle.canCancel, isTrue);
      expect(
        result.status,
        ExtensionRuntimeTaskCancellationDispatchStatus.dispatched,
      );
      expect(result.dispatched, isTrue);
      expect(
        result.handle.state,
        ExtensionRuntimeTaskCancellationState.completed,
      );
      expect(result.handle.canCancel, isFalse);
      expect(result.adapterResult?.processTerminated, isTrue);
      expect(cancelledHandles, <String>['process-build-1']);
      expect(
        bridge.cancellationRegistry.lookup(plan)?.state,
        ExtensionRuntimeTaskCancellationState.completed,
      );
      expect(result.toJson()['status'], 'dispatched');
      expect(
        telemetry.records.single.kind,
        ExtensionRuntimeTaskTelemetryKind.cancellation,
      );
      expect(telemetry.records.single.metadata['dispatchStatus'], 'dispatched');
      final telemetryAdapterResult =
          telemetry.records.single.metadata['adapterResult']!
              as Map<String, Object?>;
      expect(telemetryAdapterResult['processTerminated'], isTrue);
    },
  );

  test(
    'extension runtime task bridge reports missing cancellation adapters',
    () async {
      final plan = _createRuntimeTaskPlan();
      final telemetry = ExtensionRuntimeTaskInMemoryTelemetrySink();
      final bridge = ExtensionRuntimeTaskExecutionBridge(
        telemetrySink: telemetry,
      );

      bridge.registerCancellationHandle(
        plan: plan,
        processHandleId: 'process-build-1',
      );
      final result = await bridge.dispatchCancellation(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 21, 3, 1),
        reason: 'user cancelled build',
      );

      expect(
        result.status,
        ExtensionRuntimeTaskCancellationDispatchStatus.missingAdapter,
      );
      expect(result.dispatched, isFalse);
      expect(
        result.handle.state,
        ExtensionRuntimeTaskCancellationState.requested,
      );
      expect(result.toJson()['status'], 'missing-adapter');
      expect(
        telemetry.records.single.metadata['dispatchStatus'],
        'missing-adapter',
      );
    },
  );

  test(
    'extension runtime task cancellation adapters expose termination requests',
    () async {
      final plan = _createRuntimeTaskPlan();
      final telemetry = ExtensionRuntimeTaskInMemoryTelemetrySink();
      final requests = <ExtensionRuntimeTaskTerminationRequest>[];
      final bridge = ExtensionRuntimeTaskExecutionBridge(
        telemetrySink: telemetry,
        cancellationAdapters: <ExtensionRuntimeTaskCancellationAdapter>[
          ExtensionRuntimeTaskCancellationAdapter.processManager(
            terminate: (request) async {
              requests.add(request);
              return const ExtensionRuntimeTaskTerminationResult.accepted(
                processTerminated: true,
                message: 'Process handle terminated.',
                metadata: <String, Object?>{'pid': 42},
              );
            },
          ),
        ],
      );

      bridge.registerCancellationHandle(
        plan: plan,
        processHandleId: 'process-build-1',
      );
      final result = await bridge.dispatchCancellation(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 21, 4),
        reason: 'user cancelled build',
      );

      expect(result.dispatched, isTrue);
      expect(result.adapterResult?.processTerminated, isTrue);
      expect(requests, hasLength(1));
      expect(requests.single.managerId, 'toolchain-manager');
      expect(requests.single.backendKind, 'process-manager');
      expect(
        requests.single.signal,
        ExtensionRuntimeTaskTerminationSignal.terminate,
      );
      expect(requests.single.toJson()['processHandleId'], 'process-build-1');
      expect(
        telemetry.records.single.metadata['adapterResult'],
        containsPair('processTerminated', true),
      );
    },
  );

  test(
    'extension runtime task dispatch binds process handles for cancellation',
    () async {
      final plan = _createRuntimeTaskPlan();
      final buffer = RuntimeOutputLiveBuffer();
      final requests = <ExtensionRuntimeTaskTerminationRequest>[];
      final bridge = ExtensionRuntimeTaskExecutionBridge(
        cancellationAdapters: <ExtensionRuntimeTaskCancellationAdapter>[
          ExtensionRuntimeTaskCancellationAdapter.processManager(
            terminate: (request) async {
              requests.add(request);
              return const ExtensionRuntimeTaskTerminationResult.accepted(
                processTerminated: true,
                message: 'Bound process handle terminated.',
              );
            },
          ),
        ],
      );

      final dispatch = bridge.dispatchToLiveBuffer(
        plan: plan,
        buffer: buffer,
        timestamp: DateTime.utc(2026, 5, 21, 6),
        metadata: const <String, Object?>{'processHandleId': 'pid-42'},
      );
      final handle = bridge.cancellationRegistry.lookup(plan);
      final cancellation = await bridge.dispatchCancellation(
        plan: plan,
        timestamp: DateTime.utc(2026, 5, 21, 6, 1),
        reason: 'agent stopped validation',
      );

      expect(dispatch.dispatched, isTrue);
      expect(handle?.processHandleId, 'pid-42');
      expect(handle?.metadata['source'], 'runtime-dispatch-result');
      expect(cancellation.dispatched, isTrue);
      expect(requests.single.handle.processHandleId, 'pid-42');
      expect(cancellation.toJson()['status'], 'dispatched');
    },
  );

  test('extension runtime task dispatch binds typed pid process handles', () {
    final plan = _createRuntimeTaskPlan();
    final buffer = RuntimeOutputLiveBuffer();
    final bridge = ExtensionRuntimeTaskExecutionBridge();

    final dispatch = bridge.dispatchToLiveBuffer(
      plan: plan,
      buffer: buffer,
      timestamp: DateTime.utc(2026, 5, 21, 6, 30),
      metadata: const <String, Object?>{
        'pid': 6060,
        'processHandleSource': 'toolchain-manager',
      },
    );
    final handle = bridge.cancellationRegistry.lookup(plan);
    final processHandle =
        handle?.metadata['processHandle'] as Map<String, Object?>?;

    expect(dispatch.processHandle?.pid, 6060);
    expect(handle?.processHandleId, '6060');
    expect(processHandle?['pid'], 6060);
    expect(processHandle?['source'], 'toolchain-manager');
  });

  test('extension runtime task catalog reports missing command metadata', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken.tasks',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.task,
        id: 'broken',
        target: 'runtime.tasks',
      ),
    );

    final catalog = ExtensionRuntimeTaskContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.readyDefinitions, isEmpty);
    expect(
      catalog.contributions.single.status,
      ExtensionRuntimeTaskContributionStatus.missingCommand,
    );
  });
}

ExtensionRuntimeTaskExecutionPlan _createRuntimeTaskPlan() {
  return ExtensionRuntimeTaskExecutionPlan.fromContribution(
    const ExtensionRuntimeTaskContribution(
      extensionId: 'styio.tasks',
      contributionId: 'build',
      target: 'runtime.tasks',
      status: ExtensionRuntimeTaskContributionStatus.ready,
      message: 'ready',
      definition: RuntimeTaskDefinition(
        id: 'build',
        label: 'Build',
        kind: RuntimeTaskKind.build,
        command: 'styio',
        arguments: <String>['build'],
      ),
    ),
  );
}

FoundationDataStore _createDataStore(Directory tempRoot) {
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
