import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';

void main() {
  group('ExecutionSandbox', () {
    test('rejects shell-shaped executable strings but allows argv arguments', () {
      final sandbox = _sandbox();

      final rejected = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: 'bash -lc',
          arguments: <String>['echo safe'],
        ),
      );
      final allowed = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/printf',
          arguments: <String>['%s', r'hello; rm -rf /', r'$HOME'],
        ),
      );
      final nulArgument = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/printf',
          arguments: <String>['ok\u0000bad'],
        ),
      );

      expect(rejected.isAllowed, isFalse);
      expect(
        rejected.failure?.code,
        ExecutionSandboxFailureCode.commandRejected,
      );
      expect(allowed.isAllowed, isTrue);
      expect(allowed.normalizedCwd, '/workspace/project');
      expect(nulArgument.isAllowed, isFalse);
      expect(
        nulArgument.failure?.code,
        ExecutionSandboxFailureCode.commandRejected,
      );
    });

    test('keeps cwd inside workspace and allowed prefixes', () {
      final sandbox = _sandbox(
        allowedCwdPrefixes: const <String>['packages/app'],
      );

      final allowed = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          cwd: 'packages/app',
        ),
      );
      final sibling = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          cwd: 'packages/other',
        ),
      );
      final outside = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          cwd: '/tmp/outside',
        ),
      );

      expect(allowed.isAllowed, isTrue);
      expect(allowed.normalizedCwd, '/workspace/project/packages/app');
      expect(sibling.isAllowed, isFalse);
      expect(
        sibling.failure?.code,
        ExecutionSandboxFailureCode.cwdOutsideWorkspace,
      );
      expect(outside.isAllowed, isFalse);
      expect(
        outside.failure?.code,
        ExecutionSandboxFailureCode.cwdOutsideWorkspace,
      );
    });

    test('blocks path traversal before cwd normalization can hide it', () {
      final sandbox = _sandbox();

      final slashTraversal = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          cwd: 'src/../src',
        ),
      );
      final backslashTraversal = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          cwd: r'src\..\secrets',
        ),
      );

      expect(slashTraversal.isAllowed, isFalse);
      expect(
        slashTraversal.failure?.code,
        ExecutionSandboxFailureCode.pathTraversal,
      );
      expect(backslashTraversal.isAllowed, isFalse);
      expect(
        backslashTraversal.failure?.code,
        ExecutionSandboxFailureCode.pathTraversal,
      );
    });

    test('blocks cwd below configured symlink escape paths', () {
      final sandbox = _sandbox(
        knownSymlinkPaths: const <String>{'vendor/external-link'},
      );

      final decision = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          cwd: 'vendor/external-link/project',
        ),
      );

      expect(decision.isAllowed, isFalse);
      expect(
        decision.failure?.code,
        ExecutionSandboxFailureCode.symlinkEscape,
      );
    });

    test('enforces environment allowlist and redacts allowed secrets', () {
      final sandbox = _sandbox(
        allowedEnvironmentKeys: const <String>{
          'PATH',
          'STYIO_MODE',
          'STYIO_TOKEN',
          'OPENAI_API_KEY',
        },
      );

      final allowed = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          environment: <String, String>{
            'PATH': '/usr/bin',
            'STYIO_MODE': 'nightly',
            'STYIO_TOKEN': 'raw-token',
            'OPENAI_API_KEY': 'raw-key',
          },
        ),
      );
      final rejected = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          environment: <String, String>{'UNLISTED_SECRET': 'raw-secret'},
        ),
      );

      expect(allowed.isAllowed, isTrue);
      expect(allowed.redactedEnvironment['PATH'], '/usr/bin');
      expect(allowed.redactedEnvironment['STYIO_MODE'], 'nightly');
      expect(allowed.redactedEnvironment['STYIO_TOKEN'], '<redacted>');
      expect(allowed.redactedEnvironment['OPENAI_API_KEY'], '<redacted>');
      expect(rejected.isAllowed, isFalse);
      expect(rejected.failure?.code, ExecutionSandboxFailureCode.envRejected);
      expect(rejected.failure?.developerDetail, 'UNLISTED_SECRET');
    });

    test('blocks network tasks when policy denies network access', () {
      final sandbox = _sandbox(networkPolicy: NetworkPolicy.denied);

      final decision = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          requiresNetwork: true,
        ),
      );

      expect(decision.isAllowed, isFalse);
      expect(
        decision.failure?.code,
        ExecutionSandboxFailureCode.networkBlocked,
      );
    });

    test('validates timeout and output limit policy', () {
      final sandbox = _sandbox();
      final invalidTimeout = sandbox.evaluate(
        const ExecutionSandboxRequest(
          executable: '/usr/bin/styio',
          timeout: Duration.zero,
        ),
      );
      final invalidOutputLimit = const ExecutionSandbox(
        policy: ExecutionSandboxPolicy(
          workspaceRoot: '/workspace/project',
          trustState: WorkspaceTrustState.trusted,
          maxStdoutBytes: 0,
        ),
      ).evaluate(
        const ExecutionSandboxRequest(executable: '/usr/bin/styio'),
      );

      expect(invalidTimeout.isAllowed, isFalse);
      expect(
        invalidTimeout.failure?.code,
        ExecutionSandboxFailureCode.timeoutInvalid,
      );
      expect(invalidOutputLimit.isAllowed, isFalse);
      expect(
        invalidOutputLimit.failure?.code,
        ExecutionSandboxFailureCode.outputLimitInvalid,
      );
    });
  });

  group('ExecutionManager sandbox integration', () {
    test('applies sandbox cwd, timeout, and output byte limits', () async {
      final processManager = _RecordingProcessManager(
        const ProcessCommandResult(
          status: ProcessCommandStatus.succeeded,
          executablePath: '/usr/bin/styio',
          arguments: <String>['run'],
          exitCode: 0,
          stdout: 'abcdef',
          stderr: 'wxyz',
          duration: Duration(milliseconds: 1),
        ),
      );
      final manager = ExecutionManager(
        processManager: processManager,
        executionSandbox: const ExecutionSandbox(
          policy: ExecutionSandboxPolicy(
            workspaceRoot: '/workspace/project',
            trustState: WorkspaceTrustState.trusted,
            timeout: Duration(seconds: 2),
            maxStdoutBytes: 3,
            maxStderrBytes: 2,
          ),
        ),
      );

      final result = await manager.run(
        const ExecutionRequest(
          executablePath: '/usr/bin/styio',
          arguments: <String>['run'],
          workingDirectory: 'tools',
        ),
      );

      expect(result.status, ExecutionManagerStatus.succeeded);
      expect(processManager.requests, hasLength(1));
      expect(
        processManager.requests.single.workingDirectory,
        '/workspace/project/tools',
      );
      expect(
        processManager.requests.single.timeout,
        const Duration(seconds: 2),
      );
      expect(result.processResult.stdout, 'abc');
      expect(result.processResult.stderr, 'wx');
      expect(result.processResult.metadata['stdoutTruncated'], isTrue);
      expect(result.processResult.metadata['stderrTruncated'], isTrue);
    });

    test('blocks untrusted workspace write tasks before process run', () async {
      final processManager = _RecordingProcessManager(
        const ProcessCommandResult(
          status: ProcessCommandStatus.succeeded,
          executablePath: '/usr/bin/styio',
          arguments: <String>[],
          exitCode: 0,
          stdout: '',
          stderr: '',
          duration: Duration.zero,
        ),
      );
      final manager = ExecutionManager(
        processManager: processManager,
        executionSandbox: const ExecutionSandbox(
          policy: ExecutionSandboxPolicy(
            workspaceRoot: '/workspace/project',
            trustState: WorkspaceTrustState.restricted,
            approvalPolicy: ApprovalPolicy.workspaceWrite,
          ),
        ),
      );

      final result = await manager.run(
        const ExecutionRequest(
          executablePath: '/usr/bin/styio',
          requiresWorkspaceWrite: true,
          operation: 'task.build',
        ),
      );

      expect(result.status, ExecutionManagerStatus.blocked);
      expect(processManager.requests, isEmpty);
      expect(
        result.processResult.metadata['sandboxFailureCode'],
        ExecutionSandboxFailureCode.untrustedWorkspace.name,
      );
      expect(
        result.processResult.metadata['correlationId'],
        'task.build',
      );
    });
  });
}

ExecutionSandbox _sandbox({
  NetworkPolicy networkPolicy = NetworkPolicy.denied,
  Set<String> allowedEnvironmentKeys = const <String>{},
  List<String> allowedCwdPrefixes = const <String>[],
  Set<String> knownSymlinkPaths = const <String>{},
}) {
  return ExecutionSandbox(
    policy: ExecutionSandboxPolicy(
      workspaceRoot: '/workspace/project',
      trustState: WorkspaceTrustState.trusted,
      networkPolicy: networkPolicy,
      allowedEnvironmentKeys: allowedEnvironmentKeys,
      allowedCwdPrefixes: allowedCwdPrefixes,
      knownSymlinkPaths: knownSymlinkPaths,
    ),
  );
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
