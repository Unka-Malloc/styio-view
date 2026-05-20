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
