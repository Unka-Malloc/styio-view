import 'package:flutter_test/flutter_test.dart';
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
}
