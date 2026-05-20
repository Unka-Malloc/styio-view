import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test(
    'terminal interaction controller records output input and resize',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_terminal_runtime_history_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final historyStore = RuntimeTaskHistoryStore.fromDataStore(
        dataStore: dataStore,
      );
      final session = _FakePtySession();
      final taskController = RuntimeTaskLifecycleController(
        clock: () => DateTime.utc(2026, 5, 20),
      );
      final runtime = TerminalRuntime(
        ptyManager: _FakePtyManager(session),
        taskLifecycleController: taskController,
        taskHistoryStore: historyStore,
        taskHistoryWorkspaceId: 'demo',
        shellConfiguration: const ShellConfiguration(
          defaultProfileId: 'sh',
          profiles: <ShellProfileConfiguration>[
            ShellProfileConfiguration(
              id: 'sh',
              executablePath: '/bin/sh',
              family: ShellFamily.sh,
            ),
          ],
        ),
      );
      var tick = 0;
      final controller = TerminalInteractionController(
        runtime: runtime,
        clock: () => DateTime.utc(2026, 5, 20, 8, 0, tick++),
      );
      addTearDown(controller.dispose);
      final liveBuffer = RuntimeOutputLiveBuffer(
        subscriptionPlan: RuntimeOutputStreamSubscriptionPlan.forManager(
          taskId: 'terminal.sh',
          managerId: 'terminal-runtime',
          routeKind: 'terminal-task',
          channelIds: const <String>['terminal.fake-pty'],
          kinds: const <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.runtimeEvents,
            RuntimeOutputChannelKind.stdout,
          ],
          status: RuntimeOutputSubscriptionStatus.active,
        ),
      );
      final liveSubscription = controller.bindRuntimeOutputBuffer(liveBuffer);
      addTearDown(liveSubscription.cancel);
      addTearDown(liveBuffer.dispose);

      final started = await controller.start(
        rows: 30,
        cols: 100,
        taskId: 'terminal.sh',
        taskLabel: 'Shell terminal',
      );
      session.emit('hello\n');
      await Future<void>.delayed(Duration.zero);
      await controller.sendInput('echo ok\n');
      final resize = await controller.resize(rows: 40, cols: 120);
      final exitCode = await controller.close();

      expect(started.sessionId, 'fake-pty');
      expect(started.taskSnapshot?.status, RuntimeTaskStatus.running);
      expect(started.taskSnapshot?.definition.command, '/bin/sh');
      expect(controller.snapshot?.state, PtySessionState.running);
      expect(controller.snapshot?.outputLines, <String>['hello\n']);
      expect(controller.snapshot?.lastInput, 'echo ok\n');
      expect(session.writes, <String>['echo ok\n']);
      expect(resize?.applied, isTrue);
      expect(controller.snapshot?.lastResize?.cols, 120);
      expect(exitCode, 0);
      expect(
        controller.snapshot?.taskSnapshot?.status,
        RuntimeTaskStatus.succeeded,
      );
      expect(
        controller.snapshot?.events.map((event) => event.kind).toList(),
        <TerminalInteractionEventKind>[
          TerminalInteractionEventKind.started,
          TerminalInteractionEventKind.output,
          TerminalInteractionEventKind.input,
          TerminalInteractionEventKind.resized,
          TerminalInteractionEventKind.closed,
        ],
      );
      expect(controller.snapshot?.events.last.exitCode, 0);
      expect(
        controller.snapshot?.taskSnapshot?.definition.metadata['taskHistory'],
        'enabled',
      );
      expect(
        taskController.snapshotFor('terminal.sh')?.status,
        RuntimeTaskStatus.succeeded,
      );
      expect(controller.snapshot?.toJson()['state'], 'running');
      expect(
        (controller.snapshot?.toJson()['task']!
            as Map<String, Object?>)['status'],
        'succeeded',
      );
      expect(
        ((controller.snapshot?.toJson()['events']! as List<Object?>).last!
            as Map<String, Object?>)['kind'],
        'closed',
      );
      final runtimeEvents = controller.snapshot!.runtimeOutputEvents(
        channelId: 'terminal.fake-pty',
        label: 'Fake Terminal',
      );
      final outputPanelSnapshot = controller.snapshot!.outputPanelSnapshot(
        channelId: 'terminal.fake-pty',
        label: 'Fake Terminal',
      );
      expect(runtimeEvents, hasLength(5));
      expect(runtimeEvents[1].kind, RuntimeOutputChannelKind.stdout);
      expect(runtimeEvents.last.metadata['terminalEventKind'], 'closed');
      expect(outputPanelSnapshot.visibleEvents, hasLength(5));
      expect(liveBuffer.snapshot.visibleEvents, hasLength(5));
      expect(liveBuffer.snapshot.visibleEvents[1].message, 'hello\n');
      expect(
        liveBuffer.snapshot.visibleEvents.last.metadata['terminalEventKind'],
        'closed',
      );
      final history = await historyStore.readHistory(workspaceId: 'demo');
      expect(history.tasks.single.definition.id, 'terminal.sh');
      expect(history.tasks.single.status, RuntimeTaskStatus.succeeded);
    },
  );

  test('terminal shell command output binding exposes runtime events', () {
    const result = ShellCommandResult(
      status: ShellCommandStatus.failed,
      command: 'styio',
      executablePath: '/usr/bin/styio',
      arguments: <String>['test'],
      exitCode: 1,
      stdout: 'running tests\n',
      stderr: 'test failed\n',
      duration: Duration(milliseconds: 42),
      message: 'Shell command failed.',
    );
    final binding = TerminalShellCommandOutputBinding(
      result: result,
      channelId: 'shell.styio-test',
      label: 'Styio Test Shell',
      timestamp: DateTime.utc(2026, 5, 20, 9),
    );
    final panelSnapshot = binding.outputPanelSnapshot();

    expect(binding.events, hasLength(3));
    expect(
      binding.events.map((event) => event.kind),
      <RuntimeOutputChannelKind>[
        RuntimeOutputChannelKind.runtimeEvents,
        RuntimeOutputChannelKind.stdout,
        RuntimeOutputChannelKind.stderr,
      ],
    );
    expect(binding.events.last.metadata['exitCode'], 1);
    expect(panelSnapshot.eventCountsByKind['stderr'], 1);
    expect(binding.toJson()['eventCount'], 3);
  });
}

class _FakePtyManager implements PtyManager {
  const _FakePtyManager(this.session);

  final _FakePtySession session;

  @override
  PtyCompatibility get compatibility => PtyAdapter(facts).adapt();

  @override
  PtyFacts get facts => PtyFacts.linuxDebianArm(scriptUtilityPath: '/script');

  @override
  Future<PtySession> start(PtySessionRequest request) async => session;

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) {
    return null;
  }

  @override
  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) {
    return null;
  }
}

class _FakePtySession implements PtySession {
  final StreamController<String> _output = StreamController<String>.broadcast();
  final List<String> writes = <String>[];

  void emit(String value) {
    _output.add(value);
  }

  @override
  String get id => 'fake-pty';

  @override
  PtySessionState get state => PtySessionState.running;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int?> get exitCode async => null;

  @override
  Future<void> write(String input) async {
    writes.add(input);
  }

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    return PtyResizeResult(
      status: PtyResizeStatus.applied,
      rows: rows,
      cols: cols,
    );
  }

  @override
  Future<int?> close({bool force = false}) async {
    await _output.close();
    return 0;
  }
}
