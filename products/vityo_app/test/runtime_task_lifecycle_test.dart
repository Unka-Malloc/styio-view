import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('runtime task definition round trips command metadata', () {
    const definition = RuntimeTaskDefinition(
      id: 'styio-build',
      label: 'Build Styio',
      kind: RuntimeTaskKind.build,
      command: 'cmake',
      arguments: <String>['--build', 'build'],
      workingDirectory: '/workspace/styio',
      environment: <String, String>{'CC': 'clang'},
      dependsOn: <String>['configure'],
      group: 'build',
      terminalProfileId: 'bash',
      metadata: <String, Object?>{'owner': 'toolchain'},
    );

    final restored = RuntimeTaskDefinition.fromJson(definition.toJson());

    expect(restored.id, 'styio-build');
    expect(restored.kind, RuntimeTaskKind.build);
    expect(restored.arguments, <String>['--build', 'build']);
    expect(restored.environment, <String, String>{'CC': 'clang'});
    expect(restored.dependsOn, <String>['configure']);
    expect(restored.terminalProfileId, 'bash');
    expect(restored.runnable, isTrue);
    expect(restored.toJson()['kind'], 'build');
  });

  test('runtime task lifecycle controller records transitions', () {
    final timestamps = <DateTime>[
      DateTime.utc(2026, 5, 20, 1),
      DateTime.utc(2026, 5, 20, 1, 0, 1),
      DateTime.utc(2026, 5, 20, 1, 0, 3),
      DateTime.utc(2026, 5, 20, 1, 0, 4),
      DateTime.utc(2026, 5, 20, 1, 0, 5),
    ];
    var index = 0;
    final controller = RuntimeTaskLifecycleController(
      clock: () => timestamps[index++],
    );
    const definition = RuntimeTaskDefinition(
      id: 'styio-test',
      label: 'Run Styio tests',
      kind: RuntimeTaskKind.test,
      command: 'ctest',
    );

    final registered = controller.register(definition);
    final running = controller.start('styio-test');
    final completed = controller.complete('styio-test');
    final restored = RuntimeTaskSnapshot.fromJson(completed.toJson());

    expect(registered.status, RuntimeTaskStatus.queued);
    expect(running.status, RuntimeTaskStatus.running);
    expect(running.active, isTrue);
    expect(completed.status, RuntimeTaskStatus.succeeded);
    expect(completed.terminal, isTrue);
    expect(completed.durationMs, 3000);
    expect(completed.events.map((event) => event.sequence), <int>[1, 2, 3]);
    expect(restored.status, RuntimeTaskStatus.succeeded);
    expect(restored.definition.kind, RuntimeTaskKind.test);
    expect(restored.toJson()['eventCount'], 3);
  });

  test('runtime task lifecycle controller blocks unrunnable task', () {
    final controller = RuntimeTaskLifecycleController(
      clock: () => DateTime.utc(2026, 5, 20),
    );
    const definition = RuntimeTaskDefinition(
      id: 'missing-command',
      label: 'Missing command',
      kind: RuntimeTaskKind.shell,
      command: '',
    );

    controller.register(definition);
    final blocked = controller.block(
      'missing-command',
      message: 'Task missing-command has no command.',
      metadata: const <String, Object?>{'reason': 'missing-command'},
    );

    expect(blocked.status, RuntimeTaskStatus.blocked);
    expect(blocked.definition.runnable, isFalse);
    expect(blocked.events.last.metadata['reason'], 'missing-command');
    expect(controller.snapshotFor('missing-command')!.terminal, isTrue);
  });
}
