import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('catalog registers, activates, snapshots, and restores descriptors', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-compiler',
          kind: ToolchainKind.compiler,
          displayName: 'Styio Compiler',
          executablePath: '/opt/styio/bin/styio',
          version: '2026.06',
          channel: 'nightly',
          metadata: <String, Object?>{'target': 'linux-arm64'},
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'styio-runner',
          kind: ToolchainKind.runner,
          displayName: 'Styio Runner',
          executablePath: '/opt/styio/bin/styio-run',
        ),
      );

    final restored = ToolchainCatalog()
      ..restore(ToolchainCatalogSnapshot.fromJson(catalog.snapshot().toJson()));

    expect(catalog.list().map((descriptor) => descriptor.id), <String>[
      'styio-compiler',
      'styio-runner',
    ]);
    expect(restored.active(ToolchainKind.compiler)!.version, '2026.06');
    expect(
      restored.lookup('styio-compiler')!.metadata,
      containsPair('target', 'linux-arm64'),
    );
    expect(restored.unregister('styio-compiler'), isTrue);
    expect(restored.active(ToolchainKind.compiler), isNull);
    expect(restored.unregister('missing'), isFalse);
  });

  test('catalog rejects duplicate descriptors and ignores stale active ids', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio',
          kind: ToolchainKind.languageService,
          displayName: 'Styio',
          executablePath: '/bin/styio',
        ),
      );

    expect(
      () => catalog.register(
        const ToolchainDescriptor(
          id: 'styio',
          kind: ToolchainKind.languageService,
          displayName: 'Styio duplicate',
          executablePath: '/other/styio',
        ),
      ),
      throwsStateError,
    );

    final restored = ToolchainCatalog()
      ..restore(
        ToolchainCatalogSnapshot.fromJson(const <String, Object?>{
          'descriptors': <Object?>[
            <String, Object?>{
              'id': 'styio',
              'kind': 'language-service',
              'displayName': 'Styio',
              'executablePath': '/bin/styio',
            },
          ],
          'activeToolchainIds': <String, Object?>{
            'language-service': 'removed-styio',
          },
        }),
      );

    expect(restored.lookup('styio'), isNotNull);
    expect(restored.active(ToolchainKind.languageService), isNull);
  });

  test('resolver prefers active match then falls back to compatible candidate', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'old-runner',
          kind: ToolchainKind.runner,
          displayName: 'Old Runner',
          executablePath: '/tools/old',
          version: '1.0',
          channel: 'stable',
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'nightly-runner',
          kind: ToolchainKind.runner,
          displayName: 'Nightly Runner',
          executablePath: '/tools/nightly',
          version: '2.0',
          channel: 'nightly',
          metadata: <String, Object?>{'arch': 'arm64'},
        ),
      );

    final resolution = const ToolchainResolver().resolve(
      catalog,
      const ToolchainRequirement(
        kind: ToolchainKind.runner,
        version: '2.0',
        channel: 'nightly',
        metadata: <String, Object?>{'arch': 'arm64'},
      ),
    );

    expect(resolution.resolved, isTrue);
    expect(resolution.descriptor!.id, 'nightly-runner');
    expect(resolution.toJson()['resolved'], isTrue);
  });

  test('resolver reports missing id, missing kind, and mismatches', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'compiler',
          kind: ToolchainKind.compiler,
          displayName: 'Compiler',
          executablePath: '/tools/compiler',
          version: '1.0',
          channel: 'stable',
          metadata: <String, Object?>{'os': 'linux'},
        ),
      );
    const resolver = ToolchainResolver();

    expect(
      resolver
          .resolve(
            catalog,
            const ToolchainRequirement(
              kind: ToolchainKind.compiler,
              id: 'missing',
            ),
          )
          .status,
      ToolchainResolutionStatus.missingId,
    );
    expect(
      resolver
          .resolve(
            catalog,
            const ToolchainRequirement(kind: ToolchainKind.packageManager),
          )
          .status,
      ToolchainResolutionStatus.missingKind,
    );
    expect(
      resolver
          .resolve(
            catalog,
            const ToolchainRequirement(
              kind: ToolchainKind.compiler,
              version: '2.0',
            ),
          )
          .status,
      ToolchainResolutionStatus.versionMismatch,
    );
    expect(
      resolver
          .resolve(
            catalog,
            const ToolchainRequirement(
              kind: ToolchainKind.compiler,
              channel: 'beta',
            ),
          )
          .status,
      ToolchainResolutionStatus.channelMismatch,
    );
    expect(
      resolver
          .resolve(
            catalog,
            const ToolchainRequirement(
              kind: ToolchainKind.compiler,
              metadata: <String, Object?>{'os': 'darwin'},
            ),
          )
          .status,
      ToolchainResolutionStatus.metadataMismatch,
    );
  });

  test('health checker returns unresolved report without probing', () async {
    final report = await const ToolchainHealthChecker().check(
      catalog: ToolchainCatalog(),
      processManager: _RecordingProcessManager(
        const ProcessCommandResult(
          status: ProcessCommandStatus.succeeded,
          executablePath: '',
          arguments: <String>[],
          exitCode: 0,
          stdout: '',
          stderr: '',
          duration: Duration.zero,
        ),
      ),
      requirement: const ToolchainRequirement(kind: ToolchainKind.compiler),
      probeArguments: const <String>['--version'],
    );

    expect(report.status, ToolchainHealthStatus.unresolved);
    expect(report.healthy, isFalse);
    expect(report.message, contains('No compiler toolchain'));
  });

  test('health checker builds probe command and environment overlays', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'compiler',
          kind: ToolchainKind.compiler,
          displayName: 'Compiler',
          executablePath: '/tools/compiler',
        ),
        activate: true,
      );
    final processManager = _RecordingProcessManager(
      const ProcessCommandResult(
        status: ProcessCommandStatus.succeeded,
        executablePath: '/tools/compiler',
        arguments: <String>['--version'],
        exitCode: 0,
        stdout: 'compiler 1.0',
        stderr: '',
        duration: Duration(milliseconds: 4),
      ),
    );

    final report = await const ToolchainHealthChecker(
      environmentBuilder: ToolchainEnvironmentBuilder(
        inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
      ),
    ).check(
      catalog: catalog,
      processManager: processManager,
      requirement: const ToolchainRequirement(kind: ToolchainKind.compiler),
      probeArguments: const <String>['--version'],
      environment: const <String, String>{'STYIO_HOME': '/workspace/.styio'},
      environmentOverlays: const <EnvironmentVariableOverlay>[
        EnvironmentVariableOverlay(
          id: 'toolchain',
          scope: EnvironmentVariableOverlayScope.toolchain,
          target: 'process',
          variables: <String, String?>{'STYIO_MODE': 'coverage'},
          pathPrepend: <String>['/tools/bin'],
        ),
      ],
      workingDirectory: '/workspace',
      timeout: const Duration(seconds: 3),
    );

    expect(report.status, ToolchainHealthStatus.healthy);
    expect(report.processResult!.stdout, 'compiler 1.0');
    expect(processManager.requests, hasLength(1));
    expect(processManager.requests.single.executablePath, '/tools/compiler');
    expect(processManager.requests.single.arguments, <String>['--version']);
    expect(processManager.requests.single.workingDirectory, '/workspace');
    expect(processManager.requests.single.timeout, const Duration(seconds: 3));
    expect(processManager.requests.single.environment['STYIO_HOME'], '/workspace/.styio');
    expect(processManager.requests.single.environment['STYIO_MODE'], 'coverage');
    expect(processManager.requests.single.environment['PATH'], '/tools/bin:/usr/bin');
  });

  test('health checker marks failed probes structurally', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'compiler',
          kind: ToolchainKind.compiler,
          displayName: 'Compiler',
          executablePath: '/tools/compiler',
        ),
        activate: true,
      );

    final report = await const ToolchainHealthChecker().check(
      catalog: catalog,
      processManager: _RecordingProcessManager(
        const ProcessCommandResult(
          status: ProcessCommandStatus.failed,
          executablePath: '/tools/compiler',
          arguments: <String>['--version'],
          exitCode: 2,
          stdout: '',
          stderr: 'bad compiler',
          duration: Duration(milliseconds: 5),
          message: 'probe failed',
        ),
      ),
      requirement: const ToolchainRequirement(kind: ToolchainKind.compiler),
      probeArguments: const <String>['--version'],
    );

    expect(report.status, ToolchainHealthStatus.probeFailed);
    expect(report.healthy, isFalse);
    expect(report.message, 'probe failed');
    expect(report.toJson()['healthy'], isFalse);
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
