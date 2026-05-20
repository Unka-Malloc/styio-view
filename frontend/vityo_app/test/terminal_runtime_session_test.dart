import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('terminal runtime exposes a serializable PTY start plan', () async {
    final session = _FakePtySession();
    addTearDown(() async {
      await session.close();
    });
    final runtime = TerminalRuntime(
      ptyManager: _FakePtyManager(session),
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

    final plan = runtime.planStart(
      workingDirectory: '/workspace/vityo',
      rows: 30,
      cols: 100,
    );

    expect(plan.profileId, 'sh');
    expect(plan.executablePath, '/bin/sh');
    expect(plan.workingDirectory, '/workspace/vityo');
    expect(plan.rows, 30);
    expect(plan.cols, 100);
    expect(plan.supported, isTrue);
    expect(plan.backendExecutablePath, '/script');
    expect(
      plan.backendArguments.any((argument) => argument.contains('/bin/sh')),
      isTrue,
    );
    expect(plan.toJson()['providerKind'], plan.providerKind);
    expect(plan.toJson()['supported'], isTrue);
  });

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
      final producerBuffer = RuntimeOutputLiveBuffer(
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
      final terminalAdapter =
          RuntimeOutputProducerAdapterRegistry.defaultAdapters().lookup(
            'terminal-runtime',
          )!;
      final producerSubscription = controller.bindRuntimeOutputProducerAdapter(
        terminalAdapter,
        producerBuffer,
      );
      addTearDown(producerSubscription.cancel);
      addTearDown(producerBuffer.dispose);

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
      final producerEmissions = controller.snapshot!
          .runtimeOutputProducerEmissions(
            channelId: 'terminal.fake-pty',
            label: 'Fake Terminal',
          );
      expect(runtimeEvents, hasLength(5));
      expect(runtimeEvents[1].kind, RuntimeOutputChannelKind.stdout);
      expect(runtimeEvents.last.metadata['terminalEventKind'], 'closed');
      expect(producerEmissions, hasLength(5));
      expect(producerEmissions[1].kind, RuntimeOutputChannelKind.stdout);
      expect(outputPanelSnapshot.visibleEvents, hasLength(5));
      expect(liveBuffer.snapshot.visibleEvents, hasLength(5));
      expect(liveBuffer.snapshot.visibleEvents[1].message, 'hello\n');
      expect(producerBuffer.snapshot.visibleEvents, hasLength(5));
      expect(
        producerBuffer.snapshot.visibleEvents.first.metadata['producerId'],
        'terminal-runtime',
      );
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

  test('terminal shell command output binding splits stream chunks', () {
    const result = ShellCommandResult(
      status: ShellCommandStatus.failed,
      command: 'styio',
      executablePath: '/usr/bin/styio',
      arguments: <String>['test'],
      exitCode: 1,
      stdout: 'one\ntwo\n',
      stderr: 'err-one\nerr-two\n',
      duration: Duration(milliseconds: 42),
      message: 'Shell command failed.',
    );
    final binding = TerminalShellCommandOutputBinding(
      result: result,
      channelId: 'shell.styio-test',
      label: 'Styio Test Shell',
      timestamp: DateTime.utc(2026, 5, 20, 9),
    );

    expect(binding.events, hasLength(5));
    expect(binding.events.map((event) => event.message), <String>[
      'Shell command failed.',
      'one',
      'two',
      'err-one',
      'err-two',
    ]);
    expect(binding.events[1].metadata['chunkIndex'], 0);
    expect(binding.events[2].metadata['chunkIndex'], 1);
    expect(binding.events[3].metadata['chunkCount'], 2);
  });

  test(
    'shell manager runtime output adapter binds command result to buffer',
    () async {
      final buffer = RuntimeOutputLiveBuffer(
        subscriptionPlan: RuntimeOutputStreamSubscriptionPlan.forManager(
          taskId: 'shell.echo',
          managerId: 'shell-manager',
          routeKind: 'shell-task',
          channelIds: const <String>['shell.echo', 'shell.echo.stdout'],
          kinds: const <RuntimeOutputChannelKind>[
            RuntimeOutputChannelKind.runtimeEvents,
            RuntimeOutputChannelKind.stdout,
          ],
          status: RuntimeOutputSubscriptionStatus.active,
        ),
      );
      addTearDown(buffer.dispose);
      final adapter = ShellManagerRuntimeOutputAdapter(
        shellManager: LocalShellManager.linuxDebianArmForTest(
          shellPath: '/bin/sh',
        ),
        clock: () => DateTime.utc(2026, 5, 20, 10),
      );

      final execution = await adapter.runAndBind(
        request: const ShellCommandRequest(command: 'printf adapter-ok'),
        buffer: buffer,
        channelId: 'shell.echo',
        label: 'Shell Echo',
      );

      expect(execution.succeeded, isTrue);
      expect(execution.eventCount, 2);
      expect(
        buffer.snapshot.visibleEvents.map((event) => event.message),
        <String>['Shell command printf adapter-ok completed.', 'adapter-ok'],
      );
      expect(execution.toJson()['eventCount'], 2);
    },
  );

  test(
    'shell manager runtime execution adapter runs handoff into live output',
    () async {
      const definition = RuntimeTaskDefinition(
        id: 'shell-run',
        label: 'Shell run',
        kind: RuntimeTaskKind.shell,
        command: 'printf',
        arguments: <String>['handoff-ok'],
      );
      final binding = const RuntimeExecutionPlanner()
          .plan(definition: definition)
          .createHandoff(
            target: RuntimeExecutionHandoffTarget.shellManager,
            outputChannelId: 'shell.runtime',
          )
          .bind();
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final adapter = ShellManagerRuntimeExecutionAdapter(
        shellManager: LocalShellManager.linuxDebianArmForTest(
          shellPath: '/bin/sh',
        ),
        clock: () => DateTime.utc(2026, 5, 20, 11),
      );

      final result = await adapter.executeHandoff(
        binding: binding,
        buffer: buffer,
      );

      expect(result.executed, isTrue);
      expect(result.succeeded, isTrue);
      expect(result.execution?.eventCount, 2);
      expect(result.toJson()['succeeded'], isTrue);
      expect(
        buffer.snapshot.visibleEvents.map((event) => event.message),
        containsAll(<String>[
          'Shell command printf completed.',
          'handoff-ok',
          'Runtime shell handoff shell-run completed.',
        ]),
      );
      expect(
        buffer
            .snapshot
            .visibleEvents
            .last
            .metadata['runtimeShellExecutionStatus'],
        'executed',
      );
    },
  );

  test('shell manager runtime execution adapter rejects wrong route', () async {
    const definition = RuntimeTaskDefinition(
      id: 'tool-run',
      label: 'Tool run',
      kind: RuntimeTaskKind.build,
      command: 'printf',
    );
    final binding = const RuntimeExecutionPlanner()
        .plan(definition: definition)
        .createHandoff(target: RuntimeExecutionHandoffTarget.toolchainManager)
        .bind();
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    final adapter = ShellManagerRuntimeExecutionAdapter(
      shellManager: LocalShellManager.linuxDebianArmForTest(
        shellPath: '/bin/sh',
      ),
      clock: () => DateTime.utc(2026, 5, 20, 11),
    );

    final result = await adapter.executeHandoff(
      binding: binding,
      buffer: buffer,
    );

    expect(result.status, ShellManagerRuntimeExecutionStatus.wrongRoute);
    expect(result.succeeded, isFalse);
    expect(buffer.snapshot.visibleEvents.single.message, contains('ignored'));
    expect(
      buffer
          .snapshot
          .visibleEvents
          .single
          .metadata['runtimeShellExecutionStatus'],
      'wrong-route',
    );
  });

  test(
    'toolchain manager runtime execution adapter runs handoff into live output',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_runtime_handoff_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final manager = await _createToolchainManager(tempRoot);
      final registration = await manager.registerToolchain(
        const ToolchainDescriptor(
          id: 'sh-test-runner',
          kind: ToolchainKind.testRunner,
          displayName: 'Shell Test Runner',
          executablePath: '/bin/sh',
        ),
        activate: true,
      );
      const definition = RuntimeTaskDefinition(
        id: 'tool-test',
        label: 'Tool test',
        kind: RuntimeTaskKind.test,
        command: 'test-runner',
        arguments: <String>['-c', 'printf toolchain-ok'],
        metadata: <String, Object?>{'toolchainKind': 'test-runner'},
      );
      final binding = const RuntimeExecutionPlanner()
          .plan(definition: definition)
          .createHandoff(
            target: RuntimeExecutionHandoffTarget.toolchainManager,
            outputChannelId: 'toolchain.runtime',
          )
          .bind();
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final adapter = ToolchainManagerRuntimeExecutionAdapter(
        toolchainManager: manager,
        clock: () => DateTime.utc(2026, 5, 20, 12),
      );

      final result = await adapter.executeHandoff(
        binding: binding,
        buffer: buffer,
      );

      expect(registration.succeeded, isTrue);
      expect(result.executed, isTrue);
      expect(result.succeeded, isTrue);
      expect(result.runtimeResult?.toolchainId, 'sh-test-runner');
      expect(result.toJson()['succeeded'], isTrue);
      expect(
        buffer.snapshot.visibleEvents.map((event) => event.message),
        containsAll(<String>[
          'Runtime toolchain handoff tool-test completed.',
          'toolchain-ok',
        ]),
      );
      expect(
        buffer.snapshot.visibleEvents.first.metadata['toolchainRuntimeStatus'],
        'succeeded',
      );
      expect(buffer.snapshot.visibleEvents.last.metadata['stream'], 'stdout');
    },
  );

  test(
    'toolchain manager runtime execution adapter rejects wrong route',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_runtime_wrong_route_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final manager = await _createToolchainManager(tempRoot);
      const definition = RuntimeTaskDefinition(
        id: 'shell-run',
        label: 'Shell run',
        kind: RuntimeTaskKind.shell,
        command: 'printf',
      );
      final binding = const RuntimeExecutionPlanner()
          .plan(definition: definition)
          .createHandoff(target: RuntimeExecutionHandoffTarget.shellManager)
          .bind();
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final adapter = ToolchainManagerRuntimeExecutionAdapter(
        toolchainManager: manager,
        clock: () => DateTime.utc(2026, 5, 20, 12),
      );

      final result = await adapter.executeHandoff(
        binding: binding,
        buffer: buffer,
      );

      expect(result.status, ToolchainManagerRuntimeExecutionStatus.wrongRoute);
      expect(result.succeeded, isFalse);
      expect(buffer.snapshot.visibleEvents.single.message, contains('ignored'));
      expect(
        buffer
            .snapshot
            .visibleEvents
            .single
            .metadata['runtimeToolchainExecutionStatus'],
        'wrong-route',
      );
    },
  );
}

Future<ToolchainManager> _createToolchainManager(Directory root) async {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  final configurationStore = ConfigurationStore(
    dataStore: FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    ),
    credentialDataStore: InMemoryCredentialDataStore(),
  );
  final platformManagers = await createPlatformManagerBundle(
    platformContext: PlatformContextSnapshot.compose(
      targetId: 'toolchain-runtime-test',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'toolchain-runtime-test',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'toolchain-runtime-test',
        defaultShellPath: '/bin/sh',
      ),
    ),
  );
  return ToolchainManager(
    configurationStore: ToolchainConfigurationStore(
      configurationStore: configurationStore,
    ),
    platformManagers: platformManagers,
    workspaceId: 'demo',
  );
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
