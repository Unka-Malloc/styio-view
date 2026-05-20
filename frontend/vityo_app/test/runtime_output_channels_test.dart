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
