import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('runtime execution planner creates ready dependency order', () {
    const configure = RuntimeTaskDefinition(
      id: 'configure',
      label: 'Configure',
      kind: RuntimeTaskKind.build,
      command: 'cmake',
    );
    const build = RuntimeTaskDefinition(
      id: 'build',
      label: 'Build',
      kind: RuntimeTaskKind.build,
      command: 'cmake',
      arguments: <String>['--build', 'build'],
      dependsOn: <String>['configure'],
    );
    final plan = const RuntimeExecutionPlanner().plan(
      definition: build,
      availableDefinitions: const <RuntimeTaskDefinition>[configure],
    );
    final restored = RuntimeExecutionPlan.fromJson(plan.toJson());

    expect(plan.status, RuntimeExecutionPlanStatus.ready);
    expect(plan.executionOrder, <String>['configure', 'build']);
    expect(restored.ready, isTrue);
    expect(restored.executionOrder, <String>['configure', 'build']);
  });

  test('runtime execution plan creates serializable ready handoff', () {
    const definition = RuntimeTaskDefinition(
      id: 'styio-test',
      label: 'Styio tests',
      kind: RuntimeTaskKind.test,
      command: 'styio',
      arguments: <String>['test'],
      workingDirectory: '/workspace',
      environment: <String, String>{'STYIO_PROFILE': 'nightly'},
    );

    final plan = const RuntimeExecutionPlanner().plan(definition: definition);
    final handoff = plan.createHandoff(
      target: RuntimeExecutionHandoffTarget.toolchainManager,
      outputChannelId: 'test-output',
      metadata: const <String, Object?>{'requester': 'agent'},
    );
    final restored = RuntimeExecutionHandoff.fromJson(handoff.toJson());

    expect(handoff.ready, isTrue);
    expect(handoff.status, RuntimeExecutionHandoffStatus.ready);
    expect(handoff.target, RuntimeExecutionHandoffTarget.toolchainManager);
    expect(handoff.command, 'styio');
    expect(handoff.arguments, <String>['test']);
    expect(handoff.outputChannelId, 'test-output');
    expect(handoff.metadata['planStatus'], 'ready');
    expect(handoff.metadata['requester'], 'agent');
    expect(restored.target, RuntimeExecutionHandoffTarget.toolchainManager);
    expect(restored.environment['STYIO_PROFILE'], 'nightly');
  });

  test(
    'runtime execution handoff binding normalizes manager route metadata',
    () {
      const definition = RuntimeTaskDefinition(
        id: 'native-test',
        label: 'Native tests',
        kind: RuntimeTaskKind.test,
        command: 'ctest',
        arguments: <String>['--output-on-failure'],
      );
      final plan = const RuntimeExecutionPlanner().plan(definition: definition);
      final handoff = plan.createHandoff(
        target: RuntimeExecutionHandoffTarget.toolchainManager,
        outputChannelId: 'native.test.output',
      );

      final binding = handoff.bind(
        metadata: const <String, Object?>{'requester': 'agent'},
      );
      final event = binding.outputEvent(
        message: 'ctest finished',
        timestamp: DateTime.utc(2026, 5, 20),
      );
      final subscriptionPlan = binding.outputSubscriptionPlan(
        retentionPolicy: const RuntimeOutputRetentionPolicy.ephemeral(
          maxEventsPerChannel: 10,
        ),
        metadata: const <String, Object?>{'consumer': 'output-panel'},
      );

      expect(binding.ready, isTrue);
      expect(binding.managerId, 'toolchain-manager');
      expect(binding.routeKind, 'toolchain-task');
      expect(binding.outputChannel.id, 'native.test.output');
      expect(binding.outputChannel.kind, RuntimeOutputChannelKind.nativeTools);
      expect(binding.metadata['toolchainManagerRoute'], isTrue);
      expect(binding.metadata['requester'], 'agent');
      expect(event.channelId, 'native.test.output');
      expect(event.metadata['managerId'], 'toolchain-manager');
      expect(subscriptionPlan.status, RuntimeOutputSubscriptionStatus.pending);
      expect(subscriptionPlan.managerId, 'toolchain-manager');
      expect(subscriptionPlan.routeKind, 'toolchain-task');
      expect(subscriptionPlan.channelIds, <String>['native.test.output']);
      expect(subscriptionPlan.kinds, <RuntimeOutputChannelKind>[
        RuntimeOutputChannelKind.nativeTools,
      ]);
      expect(subscriptionPlan.metadata['consumer'], 'output-panel');
      expect(binding.toJson()['outputChannel'], isA<Map<String, Object?>>());
    },
  );

  test('runtime execution handoff binding preserves hosted blocked state', () {
    const definition = RuntimeTaskDefinition(
      id: 'hosted-run',
      label: 'Hosted run',
      kind: RuntimeTaskKind.run,
      command: 'styio',
      dependsOn: <String>['compile'],
    );
    final plan = const RuntimeExecutionPlanner().plan(definition: definition);
    final handoff = plan.createHandoff(
      target: RuntimeExecutionHandoffTarget.hostedExecutor,
    );

    final binding = handoff.bind();

    expect(binding.ready, isFalse);
    expect(binding.status, RuntimeExecutionHandoffBindingStatus.blocked);
    expect(binding.managerId, 'hosted-executor');
    expect(binding.routeKind, 'hosted-task');
    expect(binding.metadata['hostedExecutorRoute'], isTrue);
    expect(binding.outputChannel.kind, RuntimeOutputChannelKind.runtimeEvents);
  });

  test('runtime execution manager registry dispatches ready handoffs', () {
    const definition = RuntimeTaskDefinition(
      id: 'styio-test',
      label: 'Styio tests',
      kind: RuntimeTaskKind.test,
      command: 'styio',
      arguments: <String>['test'],
    );
    final binding = const RuntimeExecutionPlanner()
        .plan(definition: definition)
        .createHandoff(
          target: RuntimeExecutionHandoffTarget.toolchainManager,
          outputChannelId: 'test.styio',
        )
        .bind();
    final registry = RuntimeExecutionManagerRegistry(
      managers: const <RuntimeExecutionManagerRegistration>[
        RuntimeExecutionManagerRegistration(
          managerId: 'toolchain-manager',
          label: 'Toolchain Manager',
          routeKinds: <String>['toolchain-task'],
          metadata: <String, Object?>{'owner': 'Toolchain'},
        ),
      ],
    );

    final result = registry.dispatch(
      binding,
      timestamp: DateTime.utc(2026, 5, 20),
      metadata: const <String, Object?>{'requester': 'agent'},
    );

    expect(result.dispatched, isTrue);
    expect(result.status, RuntimeExecutionDispatchStatus.dispatched);
    expect(result.manager?.managerId, 'toolchain-manager');
    expect(result.outputSubscription.active, isTrue);
    expect(result.outputSubscription.channelIds, <String>['test.styio']);
    expect(result.outputEvent.metadata['dispatchStatus'], 'dispatched');
    expect(result.outputEvent.metadata['managerLabel'], 'Toolchain Manager');
    expect(result.metadata['owner'], 'Toolchain');
    expect(result.toJson()['outputSubscription'], isA<Map<String, Object?>>());
  });

  test('runtime execution dispatch exposes process handle identity', () {
    const definition = RuntimeTaskDefinition(
      id: 'styio-run',
      label: 'Run Styio',
      kind: RuntimeTaskKind.run,
      command: 'styio',
      arguments: <String>['run'],
    );
    final binding = const RuntimeExecutionPlanner()
        .plan(definition: definition)
        .createHandoff(
          target: RuntimeExecutionHandoffTarget.shellManager,
          outputChannelId: 'run.styio',
        )
        .bind();
    final registry = RuntimeExecutionManagerRegistry(
      managers: const <RuntimeExecutionManagerRegistration>[
        RuntimeExecutionManagerRegistration(
          managerId: 'shell-manager',
          label: 'Shell Manager',
          routeKinds: <String>[],
          metadata: <String, Object?>{
            'managerKind': 'shell',
            'processHandleSource': 'shell-manager',
          },
        ),
      ],
    );

    final result = registry.dispatch(
      binding,
      timestamp: DateTime.utc(2026, 5, 21),
      metadata: const <String, Object?>{
        'processHandleId': 'shell-proc-1',
        'pid': 4815,
        'runtimeSessionId': 'runtime-session-1',
      },
    );

    expect(result.hasProcessHandle, isTrue);
    expect(result.processHandle?.managerId, 'shell-manager');
    expect(result.processHandle?.processHandleId, 'shell-proc-1');
    expect(result.processHandle?.pid, 4815);
    expect(result.processHandle?.source, 'shell-manager');
    expect(
      result.processHandle?.metadata['runtimeSessionId'],
      'runtime-session-1',
    );
    expect(result.toJson()['processHandle'], isA<Map<String, Object?>>());
  });

  test('default runtime managers dispatch into live output buffer', () {
    const definition = RuntimeTaskDefinition(
      id: 'styio-build',
      label: 'Styio build',
      kind: RuntimeTaskKind.build,
      command: 'styio',
      arguments: <String>['build'],
    );
    final binding = const RuntimeExecutionPlanner()
        .plan(definition: definition)
        .createHandoff(
          target: RuntimeExecutionHandoffTarget.toolchainManager,
          outputChannelId: 'build.styio',
        )
        .bind();
    final registry = RuntimeExecutionManagerRegistry.defaultManagers();
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);

    final result = registry.dispatchToLiveBuffer(
      binding,
      buffer: buffer,
      timestamp: DateTime.utc(2026, 5, 20, 14),
      metadata: const <String, Object?>{'requester': 'agent'},
    );

    expect(registry.managers, hasLength(4));
    expect(result.dispatched, isTrue);
    expect(result.manager?.metadata['managerKind'], 'toolchain-task');
    expect(buffer.snapshot.visibleEvents.single.channelId, 'build.styio');
    expect(
      buffer.snapshot.visibleEvents.single.metadata['dispatchStatus'],
      'dispatched',
    );
    expect(
      buffer.snapshot.channelSnapshot.visibleChannels.single.latestMessage,
      contains('dispatched to Toolchain Manager'),
    );
    expect(
      buffer.snapshot.toJson()['subscriptionPlan'],
      isA<Map<String, Object?>>(),
    );
  });

  test(
    'runtime execution manager registry reports blocked and missing routes',
    () {
      const definition = RuntimeTaskDefinition(
        id: 'hosted-run',
        label: 'Hosted run',
        kind: RuntimeTaskKind.run,
        command: 'styio',
        dependsOn: <String>['compile'],
      );
      final blockedBinding = const RuntimeExecutionPlanner()
          .plan(definition: definition)
          .createHandoff(target: RuntimeExecutionHandoffTarget.hostedExecutor)
          .bind();
      const readyDefinition = RuntimeTaskDefinition(
        id: 'shell-run',
        label: 'Shell run',
        kind: RuntimeTaskKind.shell,
        command: 'echo',
      );
      final missingBinding = const RuntimeExecutionPlanner()
          .plan(definition: readyDefinition)
          .createHandoff(target: RuntimeExecutionHandoffTarget.shellManager)
          .bind();
      final registry = RuntimeExecutionManagerRegistry();

      final blocked = registry.dispatch(
        blockedBinding,
        timestamp: DateTime.utc(2026, 5, 20),
      );
      final missing = registry.dispatch(
        missingBinding,
        timestamp: DateTime.utc(2026, 5, 20),
      );

      expect(blocked.status, RuntimeExecutionDispatchStatus.blocked);
      expect(
        blocked.outputSubscription.status,
        RuntimeOutputSubscriptionStatus.blocked,
      );
      expect(missing.status, RuntimeExecutionDispatchStatus.missingManager);
      expect(
        missing.outputSubscription.status,
        RuntimeOutputSubscriptionStatus.pending,
      );
      expect(missing.message, contains('shell-manager'));
    },
  );

  test('runtime execution handoff preserves blocked plan reason', () {
    const definition = RuntimeTaskDefinition(
      id: 'build',
      label: 'Build',
      kind: RuntimeTaskKind.build,
      command: 'cmake',
      dependsOn: <String>['configure'],
    );

    final plan = const RuntimeExecutionPlanner().plan(definition: definition);
    final handoff = plan.createHandoff();

    expect(handoff.ready, isFalse);
    expect(handoff.status, RuntimeExecutionHandoffStatus.blocked);
    expect(handoff.target, RuntimeExecutionHandoffTarget.terminalRuntime);
    expect(handoff.metadata['planStatus'], 'blocked-missing-dependency');
    expect(handoff.metadata['missingDependencies'], <String>['configure']);
  });

  test(
    'runtime execution plan applies blocked state to lifecycle controller',
    () {
      final controller = RuntimeTaskLifecycleController(
        clock: () => DateTime.utc(2026, 5, 20),
      );
      const definition = RuntimeTaskDefinition(
        id: 'test',
        label: 'Test',
        kind: RuntimeTaskKind.test,
        command: 'ctest',
        dependsOn: <String>['build'],
      );

      final plan = const RuntimeExecutionPlanner().plan(definition: definition);
      final snapshot = plan.applyTo(controller);

      expect(plan.status, RuntimeExecutionPlanStatus.blockedMissingDependency);
      expect(snapshot.status, RuntimeTaskStatus.blocked);
      expect(
        snapshot.events.last.metadata['planStatus'],
        'blocked-missing-dependency',
      );
      expect(snapshot.events.last.metadata['missingDependencies'], <String>[
        'build',
      ]);
    },
  );

  test('runtime execution planner blocks unrunnable definitions', () {
    const definition = RuntimeTaskDefinition(
      id: 'missing-command',
      label: 'Missing command',
      kind: RuntimeTaskKind.shell,
      command: '',
    );

    final plan = const RuntimeExecutionPlanner().plan(definition: definition);

    expect(plan.ready, isFalse);
    expect(plan.status, RuntimeExecutionPlanStatus.blockedUnrunnable);
    expect(plan.toJson()['ready'], isFalse);
  });
}
