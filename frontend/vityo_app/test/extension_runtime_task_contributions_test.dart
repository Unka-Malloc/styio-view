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
    expect(firstRetry.delayBeforeNextAttempt, const Duration(milliseconds: 100));
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

  test('extension runtime task cancellation registry binds process handles', () {
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
