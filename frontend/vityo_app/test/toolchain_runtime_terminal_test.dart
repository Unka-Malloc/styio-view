import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('toolchain runtime blocks unresolved toolchain before process run', () async {
    final processManager = _RecordingProcessManager(
      const ProcessCommandResult(
        status: ProcessCommandStatus.succeeded,
        executablePath: '/bin/unused',
        arguments: <String>[],
        exitCode: 0,
        stdout: '',
        stderr: '',
        duration: Duration.zero,
      ),
    );

    final result = await ToolchainRuntime(
      catalog: ToolchainCatalog(),
      processManager: processManager,
    ).run(kind: ToolchainKind.compiler);

    expect(result.status, ToolchainRuntimeStatus.blocked);
    expect(result.toolchainId, isEmpty);
    expect(result.succeeded, isFalse);
    expect(processManager.requests, isEmpty);
  });

  test('toolchain runtime dispatches command with merged environment', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-compiler',
          kind: ToolchainKind.compiler,
          displayName: 'Styio Compiler',
          executablePath: '/tools/styio',
        ),
        activate: true,
      );
    final processManager = _RecordingProcessManager(
      const ProcessCommandResult(
        status: ProcessCommandStatus.succeeded,
        executablePath: '/tools/styio',
        arguments: <String>['compile', 'main.styio'],
        exitCode: 0,
        stdout: 'compiled',
        stderr: '',
        duration: Duration(milliseconds: 12),
      ),
    );

    final result = await ToolchainRuntime(
      catalog: catalog,
      processManager: processManager,
      environmentBuilder: const ToolchainEnvironmentBuilder(
        inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
      ),
    ).run(
      kind: ToolchainKind.compiler,
      arguments: const <String>['compile', 'main.styio'],
      environment: const <String, String>{'BUILD_ID': 'coverage'},
      environmentOverlays: const <EnvironmentVariableOverlay>[
        EnvironmentVariableOverlay(
          id: 'compiler-env',
          scope: EnvironmentVariableOverlayScope.toolchain,
          target: 'process',
          variables: <String, String?>{'STYIO_CACHE': '/tmp/styio'},
          pathAppend: <String>['/tools/bin'],
        ),
      ],
      workingDirectory: '/workspace',
      timeout: const Duration(seconds: 2),
      standardInput: 'source',
    );

    expect(result.status, ToolchainRuntimeStatus.succeeded);
    expect(result.toolchainId, 'styio-compiler');
    expect(result.stdout, 'compiled');
    expect(processManager.requests, hasLength(1));
    final request = processManager.requests.single;
    expect(request.executablePath, '/tools/styio');
    expect(request.arguments, <String>['compile', 'main.styio']);
    expect(request.environment['BUILD_ID'], 'coverage');
    expect(request.environment['STYIO_CACHE'], '/tmp/styio');
    expect(request.environment['PATH'], '/usr/bin:/tools/bin');
    expect(request.workingDirectory, '/workspace');
    expect(request.timeout, const Duration(seconds: 2));
    expect(request.standardInput, 'source');
  });

  test('toolchain runtime maps failed process result', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-runner',
          kind: ToolchainKind.runner,
          displayName: 'Styio Runner',
          executablePath: '/tools/styio-run',
        ),
        activate: true,
      );

    final result = await ToolchainRuntime(
      catalog: catalog,
      processManager: _RecordingProcessManager(
        const ProcessCommandResult(
          status: ProcessCommandStatus.failed,
          executablePath: '/tools/styio-run',
          arguments: <String>['run'],
          exitCode: 64,
          stdout: '',
          stderr: 'runtime failed',
          duration: Duration(milliseconds: 10),
          message: 'run failed',
        ),
      ),
    ).run(kind: ToolchainKind.runner, arguments: const <String>['run']);

    expect(result.status, ToolchainRuntimeStatus.failed);
    expect(result.succeeded, isFalse);
    expect(result.exitCode, 64);
    expect(result.stderr, 'runtime failed');
    expect(result.toJson()['message'], 'run failed');
  });

  test('terminal runtime starts default profile with layered environment', () async {
    final ptyManager = _RecordingPtyManager();
    final runtime = TerminalRuntime(
      ptyManager: ptyManager,
      shellConfiguration: const ShellConfiguration(
        defaultProfileId: 'bash',
        environmentOverlay: <String, String>{'TERM': 'xterm-256color'},
        profiles: <ShellProfileConfiguration>[
          ShellProfileConfiguration(
            id: 'bash',
            executablePath: '/bin/bash',
            family: ShellFamily.bash,
            arguments: <String>['--login'],
            environment: <String, String>{'SHELL_PROFILE': 'bash'},
          ),
        ],
      ),
      inheritedEnvironment: const <String, String>{'PATH': '/usr/bin'},
    );

    final session = await runtime.start(
      envFileVariables: const <Map<String, String?>>[
        <String, String?>{'FROM_ENV_FILE': 'yes'},
      ],
      environmentOverlays: const <EnvironmentVariableOverlay>[
        EnvironmentVariableOverlay(
          id: 'workspace',
          scope: EnvironmentVariableOverlayScope.workspace,
          target: 'terminal',
          variables: <String, String?>{'WORKSPACE_ID': 'demo'},
          pathPrepend: <String>['/workspace/bin'],
        ),
      ],
      environment: const <String, String>{'RUNTIME_ONLY': '1'},
      workingDirectory: '/workspace',
      rows: 40,
      cols: 120,
    );

    expect(session.id, 'recorded-pty');
    addTearDown(session.close);
    expect(ptyManager.requests, hasLength(1));
    final request = ptyManager.requests.single;
    expect(request.executablePath, '/bin/bash');
    expect(request.arguments, <String>['--login']);
    expect(request.environment['TERM'], 'xterm-256color');
    expect(request.environment['SHELL_PROFILE'], 'bash');
    expect(request.environment['FROM_ENV_FILE'], 'yes');
    expect(request.environment['WORKSPACE_ID'], 'demo');
    expect(request.environment['RUNTIME_ONLY'], '1');
    expect(request.environment['PATH'], '/workspace/bin:/usr/bin');
    expect(request.workingDirectory, '/workspace');
    expect(request.rows, 40);
    expect(request.cols, 120);
  });

  test('terminal runtime delegates unsupported profile selection to pty manager', () async {
    final ptyManager = _RecordingPtyManager();

    final session = await TerminalRuntime(
      ptyManager: ptyManager,
      shellConfiguration: const ShellConfiguration(
        defaultProfileId: 'missing',
        profiles: <ShellProfileConfiguration>[],
      ),
    ).start(workingDirectory: '/workspace');

    addTearDown(session.close);
    expect(ptyManager.requests, hasLength(1));
    expect(ptyManager.requests.single.executablePath, isEmpty);
    expect(ptyManager.requests.single.environment, isEmpty);
    expect(ptyManager.requests.single.workingDirectory, '/workspace');
  });
}

class _RecordingProcessManager implements ProcessManager {
  _RecordingProcessManager(this._result);

  final ProcessCommandResult _result;
  final List<ProcessCommandRequest> requests = <ProcessCommandRequest>[];

  @override
  ProcessCompatibility get compatibility => ProcessAdapter(facts).adapt();

  @override
  ProcessFacts get facts => ProcessFacts.linuxDebianArm();

  @override
  ProcessOperationFailure? failureFor(
    ProcessCommandResult result, {
    String operation = 'process.spawn',
    String? recoveryHint,
  }) {
    return const ProcessFailureClassifier(
      sourceManager: '_RecordingProcessManager',
    ).classify(
      result,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<ProcessCommandResult> run(ProcessCommandRequest request) async {
    requests.add(request);
    return _result;
  }
}

class _RecordingPtyManager implements PtyManager {
  final List<PtySessionRequest> requests = <PtySessionRequest>[];

  @override
  PtyCompatibility get compatibility => PtyAdapter(facts).adapt();

  @override
  PtyFacts get facts => PtyFacts.linuxDebianArm();

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) {
    return const PtyFailureClassifier(
      sourceManager: '_RecordingPtyManager',
    ).classifyResize(
      result,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }

  @override
  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) {
    return const PtyFailureClassifier(
      sourceManager: '_RecordingPtyManager',
    ).classifySession(
      session,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<PtySession> start(PtySessionRequest request) async {
    requests.add(request);
    return _RecordedPtySession();
  }
}

class _RecordedPtySession implements PtySession {
  final StreamController<String> _output = StreamController<String>.broadcast();

  @override
  String get id => 'recorded-pty';

  @override
  PtySessionState get state => PtySessionState.running;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int?> close({bool force = false}) async {
    await _output.close();
    return 0;
  }

  @override
  Future<int?> get exitCode async => 0;

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    return PtyResizeResult(
      status: PtyResizeStatus.applied,
      rows: rows,
      cols: cols,
    );
  }

  @override
  Future<void> write(String input) async {
    _output.add(input);
  }

  @override
  Future<PtySignalResult> sendSignal(PtySignal signal) async {
    return PtySignalResult(
      signal: signal,
      status: PtySignalStatus.sent,
    );
  }
}
