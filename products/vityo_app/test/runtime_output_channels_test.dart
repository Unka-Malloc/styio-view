import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('runtime output channel snapshot filters visible channels', () {
    const channels = <RuntimeOutputChannelSummary>[
      RuntimeOutputChannelSummary(
        id: 'runtime-events',
        label: 'Runtime events',
        kind: RuntimeOutputChannelKind.runtimeEvents,
        eventCount: 2,
        latestMessage: 'run.finished from styio.runtime',
      ),
      RuntimeOutputChannelSummary(
        id: 'stdout',
        label: 'Stdout',
        kind: RuntimeOutputChannelKind.stdout,
        eventCount: 0,
        latestMessage: 'No stdout event.',
      ),
      RuntimeOutputChannelSummary(
        id: 'stderr',
        label: 'Stderr',
        kind: RuntimeOutputChannelKind.stderr,
        eventCount: 1,
        latestMessage: 'compile failed',
      ),
    ];
    const filter = RuntimeOutputChannelFilterState(
      kinds: <RuntimeOutputChannelKind>[RuntimeOutputChannelKind.stderr],
    );

    final snapshot = RuntimeOutputChannelSnapshot(
      channels: channels,
      filter: RuntimeOutputChannelFilterState.fromJson(filter.toJson()),
    );
    final json = snapshot.toJson();

    expect(snapshot.totalEventCount, 3);
    expect(snapshot.visibleChannels.single.id, 'stderr');
    expect(snapshot.visibleChannels.single.hasOutput, isTrue);
    expect(json['visibleChannelCount'], 1);
    expect(json['totalEventCount'], 3);
  });

  test('runtime output channel filter can include empty channels', () {
    const channel = RuntimeOutputChannelSummary(
      id: 'stdout',
      label: 'Stdout',
      kind: RuntimeOutputChannelKind.stdout,
      eventCount: 0,
      latestMessage: 'No stdout event.',
    );

    const hidden = RuntimeOutputChannelSnapshot(
      channels: <RuntimeOutputChannelSummary>[channel],
    );
    const visible = RuntimeOutputChannelSnapshot(
      channels: <RuntimeOutputChannelSummary>[channel],
      filter: RuntimeOutputChannelFilterState(includeEmpty: true),
    );

    expect(hidden.visibleChannels, isEmpty);
    expect(visible.visibleChannels.single.id, 'stdout');
    expect(visible.filter.summary, 'include-empty');
  });

  test('runtime output channel snapshot round trips through JSON', () {
    const snapshot = RuntimeOutputChannelSnapshot(
      filter: RuntimeOutputChannelFilterState(
        kinds: <RuntimeOutputChannelKind>[RuntimeOutputChannelKind.stderr],
      ),
      channels: <RuntimeOutputChannelSummary>[
        RuntimeOutputChannelSummary(
          id: 'stderr',
          label: 'Stderr',
          kind: RuntimeOutputChannelKind.stderr,
          eventCount: 1,
          latestMessage: 'compile failed',
        ),
      ],
    );

    final restored = RuntimeOutputChannelSnapshot.fromJson(snapshot.toJson());

    expect(restored.filter.summary, 'kinds stderr');
    expect(restored.channels.single.id, 'stderr');
    expect(restored.visibleChannels.single.latestMessage, 'compile failed');
  });

  test(
    'runtime output panel snapshot aggregates agent language and debug events',
    () {
      final snapshot = RuntimeOutputPanelSnapshot(
        filter: const RuntimeOutputChannelFilterState(
          kinds: <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.agent,
            RuntimeOutputChannelKind.debug,
          ],
        ),
        events: <RuntimeOutputEvent>[
          RuntimeOutputEvent(
            channelId: 'agent.activity',
            label: 'Agent Activity',
            kind: RuntimeOutputChannelKind.agent,
            message: 'patch proposed',
            timestamp: DateTime.utc(2026, 5, 20, 8),
          ),
          RuntimeOutputEvent(
            channelId: 'language.styio',
            label: 'Styio Language Service',
            kind: RuntimeOutputChannelKind.languageService,
            message: 'diagnostics refreshed',
            timestamp: DateTime.utc(2026, 5, 20, 8, 1),
          ),
          RuntimeOutputEvent(
            channelId: 'debug.dap',
            label: 'Debug Adapter',
            kind: RuntimeOutputChannelKind.debug,
            message: 'stopped breakpoint',
            timestamp: DateTime.utc(2026, 5, 20, 8, 2),
          ),
        ],
      );
      final json = snapshot.toJson();

      expect(snapshot.channelSnapshot.channels, hasLength(3));
      expect(snapshot.visibleEvents.map((event) => event.channelId), <String>[
        'agent.activity',
        'debug.dap',
      ]);
      expect(snapshot.eventCountsByKind['agent'], 1);
      expect(snapshot.eventCountsByKind['language-service'], 1);
      expect(snapshot.eventCountsByKind['debug'], 1);
      expect(json['visibleEventCount'], 2);
      expect(
        ((json['channelSnapshot']!
            as Map<String, Object?>)['visibleChannelCount']),
        2,
      );
    },
  );

  test(
    'runtime output subscription plan filters and retains stream events',
    () {
      final plan = RuntimeOutputStreamSubscriptionPlan.forManager(
        taskId: 'native-test',
        managerId: 'toolchain-manager',
        routeKind: 'toolchain-task',
        channelIds: const <String>['native.test.output'],
        kinds: const <RuntimeOutputChannelKind>[
          RuntimeOutputChannelKind.nativeTools,
        ],
        status: RuntimeOutputSubscriptionStatus.active,
        retentionPolicy: const RuntimeOutputRetentionPolicy(
          maxEventsPerChannel: 1,
          maxEventAge: Duration(hours: 1),
          persistHistory: true,
          trimEmptyChannels: false,
        ),
      );
      final now = DateTime.utc(2026, 5, 20, 10);
      final events = <RuntimeOutputEvent>[
        RuntimeOutputEvent(
          channelId: 'native.test.output',
          label: 'Native tests',
          kind: RuntimeOutputChannelKind.nativeTools,
          message: 'old event',
          timestamp: DateTime.utc(2026, 5, 20, 8),
        ),
        RuntimeOutputEvent(
          channelId: 'native.test.output',
          label: 'Native tests',
          kind: RuntimeOutputChannelKind.nativeTools,
          message: 'first retained event',
          timestamp: DateTime.utc(2026, 5, 20, 9, 30),
        ),
        RuntimeOutputEvent(
          channelId: 'native.test.output',
          label: 'Native tests',
          kind: RuntimeOutputChannelKind.nativeTools,
          message: 'latest retained event',
          timestamp: DateTime.utc(2026, 5, 20, 9, 45),
        ),
        RuntimeOutputEvent(
          channelId: 'stderr',
          label: 'Stderr',
          kind: RuntimeOutputChannelKind.stderr,
          message: 'filtered out',
          timestamp: DateTime.utc(2026, 5, 20, 9, 50),
        ),
      ];

      final retained = plan.retain(events, now: now);
      final snapshot = RuntimeOutputPanelSnapshot(
        events: events,
        subscriptionPlan: plan,
      );
      final restored = RuntimeOutputStreamSubscriptionPlan.fromJson(
        plan.toJson(),
      );

      expect(plan.active, isTrue);
      expect(plan.accepts(events[1]), isTrue);
      expect(plan.accepts(events.last), isFalse);
      expect(retained.map((event) => event.message), <String>[
        'latest retained event',
      ]);
      expect(snapshot.visibleEvents.single.message, 'latest retained event');
      expect(snapshot.toJson()['sourceEventCount'], 4);
      expect(snapshot.toJson()['eventCount'], 1);
      expect(restored.retentionPolicy.persistHistory, isTrue);
      expect(restored.summary, contains('toolchain-manager -> toolchain-task'));
    },
  );

  test(
    'runtime output producer registry exposes default producer contracts',
    () {
      final registry = RuntimeOutputProducerRegistry.defaultProducers();
      final shell = registry.lookup('shell-manager');
      final subscriptions = registry.subscriptionPlansForTask(
        taskId: 'styio-run',
        retentionPolicy: const RuntimeOutputRetentionPolicy.ephemeral(
          maxEventsPerChannel: 10,
        ),
      );
      final directSubscription = shell!.createSubscriptionPlan(
        taskId: 'styio-run',
        outputChannelId: 'shell.styio-run',
      );

      expect(registry.producers, hasLength(7));
      expect(
        registry.activeProducers.map((producer) => producer.producerId),
        <String>[
          'agent',
          'debug-adapter',
          'hosted-executor',
          'language-service',
          'shell-manager',
          'terminal-runtime',
          'toolchain-manager',
        ],
      );
      expect(shell.kind, RuntimeOutputProducerKind.shellManager);
      expect(shell.outputKinds, <RuntimeOutputChannelKind>[
        RuntimeOutputChannelKind.stdout,
        RuntimeOutputChannelKind.stderr,
      ]);
      expect(subscriptions, hasLength(7));
      expect(
        subscriptions.map((subscription) => subscription.managerId),
        containsAll(<String>[
          'agent-runtime',
          'debug-adapter',
          'language-service',
          'shell-manager',
          'terminal-runtime',
          'toolchain-manager',
          'hosted-executor',
        ]),
      );
      expect(directSubscription.active, isTrue);
      expect(directSubscription.channelIds, <String>['shell.styio-run']);
      expect(directSubscription.metadata['producerKind'], 'shell-manager');
      expect(registry.toJson()['producerCount'], 7);
    },
  );

  test(
    'runtime output producer adapters publish emissions into live buffer',
    () async {
      final adapters = RuntimeOutputProducerAdapterRegistry.defaultAdapters();
      final agent = adapters.lookup('agent')!;
      final shell = adapters.lookup('shell-manager')!;
      final toolchain = adapters.lookup('toolchain-manager')!;
      final buffer = RuntimeOutputLiveBuffer();
      final controller = StreamController<RuntimeOutputProducerEmission>();
      final subscription = shell.bind(controller.stream, buffer);
      addTearDown(subscription.cancel);
      addTearDown(controller.close);
      addTearDown(buffer.dispose);

      controller.add(
        RuntimeOutputProducerEmission.stdout(
          message: 'styio run started',
          timestamp: DateTime.utc(2026, 5, 20, 11),
          metadata: const <String, Object?>{'taskId': 'styio-run'},
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final toolchainEvent = toolchain.event(
        RuntimeOutputProducerEmission.nativeTool(
          message: 'toolchain health ok',
          timestamp: DateTime.utc(2026, 5, 20, 11, 1),
        ),
      );
      final agentEvent = agent.event(
        RuntimeOutputProducerEmission(
          message: 'agent patch ready',
          timestamp: DateTime.utc(2026, 5, 20, 11, 2),
        ),
      );

      expect(adapters.adapters, hasLength(7));
      expect(buffer.snapshot.visibleEvents.single.channelId, 'runtime.shell');
      expect(
        buffer.snapshot.visibleEvents.single.kind,
        RuntimeOutputChannelKind.stdout,
      );
      expect(
        buffer.snapshot.visibleEvents.single.metadata['producerId'],
        'shell-manager',
      );
      expect(toolchainEvent.channelId, 'runtime.toolchain');
      expect(toolchainEvent.kind, RuntimeOutputChannelKind.nativeTools);
      expect(toolchainEvent.metadata['producerKind'], 'toolchain-manager');
      expect(agentEvent.channelId, 'runtime.agent');
      expect(agentEvent.kind, RuntimeOutputChannelKind.agent);
      expect(agentEvent.metadata['producerKind'], 'agent');
      expect(adapters.toJson()['adapterCount'], 7);
    },
  );

  test(
    'runtime output producer binding controller manages live producer streams',
    () async {
      final bindingController = RuntimeOutputProducerBindingController(
        adapters: RuntimeOutputProducerAdapterRegistry.defaultAdapters(),
        buffer: RuntimeOutputLiveBuffer(),
      );
      final shellStream = StreamController<RuntimeOutputProducerEmission>();
      addTearDown(shellStream.close);
      addTearDown(bindingController.dispose);

      final active = bindingController.bindProducer(
        producerId: 'shell-manager',
        emissions: shellStream.stream,
      );
      final blocked = bindingController.bindProducer(
        producerId: 'unknown-manager',
        emissions: const Stream<RuntimeOutputProducerEmission>.empty(),
      );

      shellStream.add(
        RuntimeOutputProducerEmission.stdout(
          message: 'shell manager ready',
          timestamp: DateTime.utc(2026, 5, 20, 12),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(active.active, isTrue);
      expect(active.defaultChannelId, 'runtime.shell');
      expect(blocked.status, RuntimeOutputSubscriptionStatus.blocked);
      expect(bindingController.hasActiveBindings, isTrue);
      expect(
        bindingController.lookup('shell-manager')?.managerId,
        'shell-manager',
      );
      expect(bindingController.toJson()['activeBindingCount'], 1);
      expect(await bindingController.unbindProducer('shell-manager'), isTrue);
      expect(
        bindingController.lookup('shell-manager')?.status,
        RuntimeOutputSubscriptionStatus.pending,
      );
    },
  );

  test(
    'runtime output live buffer binds streams and emits snapshots',
    () async {
      final plan = RuntimeOutputStreamSubscriptionPlan.forManager(
        taskId: 'styio-run',
        managerId: 'shell-manager',
        routeKind: 'output-panel',
        channelIds: const <String>['runtime.events'],
        kinds: const <RuntimeOutputChannelKind>[
          RuntimeOutputChannelKind.runtimeEvents,
        ],
        status: RuntimeOutputSubscriptionStatus.active,
        retentionPolicy: const RuntimeOutputRetentionPolicy(
          maxEventsPerChannel: 1,
          persistHistory: true,
          trimEmptyChannels: false,
        ),
      );
      final buffer = RuntimeOutputLiveBuffer(subscriptionPlan: plan);
      final controller = StreamController<RuntimeOutputEvent>();
      final emitted = <RuntimeOutputPanelSnapshot>[];
      final snapshotSubscription = buffer.snapshots.listen(emitted.add);
      final eventSubscription = buffer.bind(controller.stream);
      addTearDown(snapshotSubscription.cancel);
      addTearDown(eventSubscription.cancel);
      addTearDown(controller.close);
      addTearDown(buffer.dispose);

      controller.add(
        RuntimeOutputEvent(
          channelId: 'runtime.events',
          label: 'Runtime Events',
          kind: RuntimeOutputChannelKind.runtimeEvents,
          message: 'run started',
          timestamp: DateTime.utc(2026, 5, 20, 10),
        ),
      );
      controller.add(
        RuntimeOutputEvent(
          channelId: 'runtime.events',
          label: 'Runtime Events',
          kind: RuntimeOutputChannelKind.runtimeEvents,
          message: 'run finished',
          timestamp: DateTime.utc(2026, 5, 20, 10, 1),
        ),
      );
      controller.add(
        RuntimeOutputEvent(
          channelId: 'stderr',
          label: 'Stderr',
          kind: RuntimeOutputChannelKind.stderr,
          message: 'filtered out',
          timestamp: DateTime.utc(2026, 5, 20, 10, 2),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isNotEmpty);
      expect(buffer.snapshot.visibleEvents.single.message, 'run finished');
      expect(
        buffer.snapshot.channelSnapshot.visibleChannels.single.eventCount,
        1,
      );
      expect(
        buffer.snapshot.toJson()['subscriptionPlan'],
        isA<Map<String, Object?>>(),
      );

      buffer.updateFilter(
        const RuntimeOutputChannelFilterState(
          kinds: <RuntimeOutputChannelKind>[RuntimeOutputChannelKind.stderr],
        ),
      );

      expect(buffer.snapshot.visibleEvents, isEmpty);
      expect(emitted.last.visibleEvents, isEmpty);
    },
  );

  test(
    'runtime output channel history persists snapshots through DataStore',
    () async {
      final store = RuntimeOutputChannelHistoryStore.fromDataStore(
        dataStore: await _createDataStore(),
      );
      const snapshot = RuntimeOutputChannelSnapshot(
        channels: <RuntimeOutputChannelSummary>[
          RuntimeOutputChannelSummary(
            id: 'runtime-events',
            label: 'Runtime events',
            kind: RuntimeOutputChannelKind.runtimeEvents,
            eventCount: 2,
            latestMessage: 'run.finished',
          ),
        ],
      );

      await store.appendSnapshot(
        workspaceId: 'demo',
        snapshot: snapshot,
        capturedAt: DateTime.utc(2026, 5, 20),
      );
      final restored = await store.readHistory(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.entries.single.capturedAt, DateTime.utc(2026, 5, 20));
      expect(restored.entries.single.snapshot.totalEventCount, 2);
      expect(
        restored.entries.single.snapshot.visibleChannels.single.id,
        'runtime-events',
      );
      expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
      expect((await store.readHistory(workspaceId: 'demo')).entries, isEmpty);
    },
  );
}

Future<FoundationDataStore> _createDataStore() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_runtime_output_history_test_',
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
