import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/configuration.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/platform/platform.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('execution session exposes stable result contract', () {
    const session = ExecutionSession(
      sessionId: 'run-1',
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage: 'Run finished.',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[ExecutionLogEvent(message: 'ok')],
      stderrEvents: <ExecutionLogEvent>[],
      unitRange: SourceRange(start: 1, end: 5),
    );

    final contract = session.toResultContract(
      metadata: const <String, Object?>{'route': 'local'},
    );
    final json = session.toJson();

    expect(contract.source, 'execution-session');
    expect(contract.succeeded, isTrue);
    expect(contract.toJson()['stdoutCount'], 1);
    expect(contract.toJson()['metadata'], <String, Object?>{'route': 'local'});
    expect(json['unitRange'], <String, int>{'start': 1, 'end': 5});
  });

  test('native tool result maps onto execution result contract', () {
    final record = NativeToolResultRecord(
      command: AppCommandId.runBuild,
      label: 'Run Build',
      applied: false,
      message: 'Build failed.',
      metadata: const <String, Object?>{
        'buildResult': <String, Object?>{'status': 'failed'},
      },
      diagnostics: const <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'build.failed',
          message: 'Build failed.',
          range: SourceRange(start: 0, end: 1),
        ),
      ],
      completedAt: DateTime.utc(2026, 5, 20),
    );

    final contract = record.toResultContract();
    final json = record.toJson();

    expect(contract.source, 'native-tool');
    expect(contract.kind, 'runBuild');
    expect(contract.failed, isTrue);
    expect(contract.diagnosticCount, 1);
    expect(json['executionResult'], isA<Map<String, Object?>>());
  });

  test('execution controller bounds native tool result history', () {
    final controller = _createExecutionController();
    addTearDown(controller.dispose);

    for (var index = 0; index < 30; index += 1) {
      controller.recordNativeToolResult(
        command: index.isEven ? AppCommandId.runBuild : AppCommandId.runTests,
        label: 'Result $index',
        applied: true,
        message: 'Completed $index.',
        metadata: <String, Object?>{'index': index},
        diagnostics: const <Diagnostic>[],
        completedAt: DateTime.utc(2026, 5, 20, 0, 0, index),
      );
    }

    expect(controller.nativeToolResults, hasLength(24));
    expect(controller.lastNativeToolResult?.metadata['index'], 29);
    expect(controller.nativeToolResults.last.metadata['index'], 6);
    expect(
      () => controller.nativeToolResults.add(controller.lastNativeToolResult!),
      throwsUnsupportedError,
    );
  });

  test('native tool command boundary accepts only four typed commands', () {
    expect(
      NativeToolCommand.fromAppCommandId(AppCommandId.runBuild),
      NativeToolCommand.build,
    );
    expect(
      NativeToolCommand.fromAppCommandId(AppCommandId.formatActiveDocument),
      NativeToolCommand.formatDocument,
    );
    expect(
      () => NativeToolCommand.fromAppCommandId(AppCommandId.save),
      throwsArgumentError,
    );
  });

  test('native build and test receipts include backend route selection', () {
    final controller = _createExecutionController();
    addTearDown(controller.dispose);
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace',
      activeFilePath: 'src/main.cpp',
      title: 'Demo',
      notes: const <String>[],
    );

    final buildMetadata = controller.nativeToolBackendRouteMetadata(
      command: NativeToolCommand.build,
      platformTarget: PlatformTarget.linux,
      projectGraph: projectGraph,
      adapterCapabilities: const <AdapterCapabilitySnapshot>[],
    );
    final formatMetadata = controller.nativeToolBackendRouteMetadata(
      command: NativeToolCommand.formatDocument,
      platformTarget: PlatformTarget.linux,
      projectGraph: projectGraph,
      adapterCapabilities: const <AdapterCapabilitySnapshot>[],
    );

    expect(buildMetadata, contains('backendRouteSelection'));
    expect(formatMetadata, isEmpty);
  });

  test('execution controller decodes clang diagnostics for active document', () {
    final controller = _createExecutionController();
    addTearDown(controller.dispose);
    const document = DocumentState(
      documentId: 'src/main.cpp',
      text: 'int main() {\n  return missing;\n}\n',
      revision: 0,
    );

    final buildDiagnostics = controller.clangBuildDiagnosticsFromOutput(
      output:
          'C:\\workspace\\src\\main.cpp:2:10: error: use of undeclared identifier missing\n'
          'C:\\workspace\\src\\other.cpp:1:1: warning: ignored',
      activeDocumentPath: 'src/main.cpp',
      document: document,
    );
    final tidyDiagnostics = controller.clangTidyDiagnosticsFromOutput(
      output:
          '/workspace/src/main.cpp:1:1: warning: prefer trailing return type [modernize-use-trailing-return-type]',
      activeDocumentPath: 'src/main.cpp',
      document: document,
    );

    expect(buildDiagnostics, hasLength(1));
    expect(buildDiagnostics.single.code, 'native-build');
    expect(buildDiagnostics.single.severity, DiagnosticSeverity.error);
    expect(buildDiagnostics.single.range.start, 22);
    expect(buildDiagnostics.single.range.end, 23);
    expect(tidyDiagnostics, hasLength(1));
    expect(tidyDiagnostics.single.code, 'modernize-use-trailing-return-type');
    expect(tidyDiagnostics.single.message, 'prefer trailing return type');
  });

  test('execution controller decodes CTest summary and process receipt', () {
    final controller = _createExecutionController();
    addTearDown(controller.dispose);

    final testResult = controller.ctestResultFromOutput(
      '50% tests passed, 1 tests failed out of 2\n'
      '1 - parser_test (Failed)',
      succeeded: false,
    );
    final processMetadata = controller.nativeToolProcessMetadata(
      const ToolchainRuntimeResult(
        status: ToolchainRuntimeStatus.failed,
        toolchainId: 'ctest',
        stdout: 'test output',
        stderr: 'failure output',
        exitCode: 8,
      ),
    );

    expect(testResult['status'], 'failed');
    expect(testResult['totalCount'], 2);
    expect(testResult['passedCount'], 1);
    expect(testResult['failedCount'], 1);
    expect(testResult['failedTests'], <Map<String, Object?>>[
      <String, Object?>{'name': 'parser_test', 'status': 'Failed'},
    ]);
    expect(processMetadata['exitCode'], 8);
    expect(processMetadata['stdoutPreview'], 'test output');
    expect(processMetadata['stderrPreview'], 'failure output');
  });

  test('native build layout normalizes workspace evidence once', () {
    final configured = NativeBuildWorkspaceLayout.fromFiles(const <String>[
      'CMakeLists.txt',
      r'build\compile_commands.json',
      r'build\CTestTestfile.cmake',
      r'build\build.ninja',
    ]);
    final rootNinja = NativeBuildWorkspaceLayout.fromFiles(const <String>[
      'build.ninja',
    ]);

    expect(configured.contains('CMakeLists.txt'), isTrue);
    expect(configured.hasConfiguredCMakeBuild, isTrue);
    expect(configured.hasConfiguredCTestBuild, isTrue);
    expect(configured.hasNinjaBuild, isTrue);
    expect(configured.buildDirectory, 'build');
    expect(configured.ctestDirectory, 'build');
    expect(configured.compilationDatabaseDirectory, 'build');
    expect(rootNinja.hasNinjaBuild, isTrue);
    expect(rootNinja.buildDirectory, '.');
  });

  test(
    'native static analysis fails closed without compile commands',
    () async {
      final controller = _createExecutionController();
      addTearDown(controller.dispose);

      final result = await controller.runNativeStaticAnalysis(
        manager: _UnusedToolchainManager(),
        workspaceLayout: NativeBuildWorkspaceLayout.fromFiles(const <String>[
          'CMakeLists.txt',
          'src/main.cpp',
        ]),
        workspaceRoot: '/workspace',
        activeDocumentPath: 'src/main.cpp',
        document: const DocumentState(
          documentId: 'src/main.cpp',
          text: 'int main() {}\n',
          revision: 0,
        ),
      );

      expect(result.applied, isFalse);
      expect(result.message, contains('run build first'));
      expect(result.metadata['requiredCommand'], 'runBuild');
      expect(
        result.metadata['staticAnalysisResult'],
        containsPair('status', 'blocked'),
      );
    },
  );

  test('native tests fail closed without configured CTest build', () async {
    final controller = _createExecutionController();
    addTearDown(controller.dispose);

    final result = await controller.runNativeTests(
      manager: _UnusedToolchainManager(),
      workspaceLayout: NativeBuildWorkspaceLayout.fromFiles(const <String>[
        'CMakeLists.txt',
        'tests/parser_test.cpp',
      ]),
      workspaceRoot: '/workspace',
    );

    expect(result.applied, isFalse);
    expect(result.message, contains('run build first'));
    expect(result.metadata['requiredCommand'], 'runBuild');
    expect(
      result.metadata['testResult'],
      containsPair('reason', 'missing-ctest-build-directory'),
    );
  });

  test('native document format result exposes explicit changed fact', () {
    const result = NativeDocumentFormatResult(
      commandResult: NativeToolCommandResult(
        applied: true,
        message: 'Format Active Document completed.',
        metadata: <String, Object?>{
          'formatResult': <String, Object?>{
            'runner': 'clang-format',
            'status': 'passed',
            'changed': true,
          },
        },
      ),
      formattedText: 'int main() {}\n',
    );

    expect(result.changed, isTrue);
    expect(result.formattedText, 'int main() {}\n');
  });

  test(
    'native build configures once and returns generated artifacts',
    () async {
      final controller = _createExecutionController();
      addTearDown(controller.dispose);
      final manager = _RecordingToolchainManager(<ToolchainRuntimeResult>[
        const ToolchainRuntimeResult(
          status: ToolchainRuntimeStatus.succeeded,
          toolchainId: 'cmake',
          stdout: 'configured',
          stderr: '',
          exitCode: 0,
        ),
        const ToolchainRuntimeResult(
          status: ToolchainRuntimeStatus.succeeded,
          toolchainId: 'cmake',
          stdout: '',
          stderr: 'src/main.cpp:1:1: warning: build warning',
          exitCode: 0,
        ),
      ]);

      final result = await controller.runNativeBuild(
        manager: manager,
        workspaceLayout: NativeBuildWorkspaceLayout.fromFiles(const <String>[
          'CMakeLists.txt',
          'src/main.cpp',
        ]),
        workspaceRoot: '/workspace',
        activeDocumentPath: 'src/main.cpp',
        document: const DocumentState(
          documentId: 'src/main.cpp',
          text: 'int main() {}\n',
          revision: 0,
        ),
        loadClangCppSelection: () async => null,
      );

      expect(manager.arguments, <List<String>>[
        <String>['-S', '.', '-B', 'build'],
        <String>['--build', 'build'],
      ]);
      expect(result.commandResult.applied, isTrue);
      expect(result.commandResult.diagnostics, hasLength(1));
      expect(result.generatedArtifactPaths, <String>[
        'build/CMakeCache.txt',
        'build/compile_commands.json',
      ]);
      expect(
        result.commandResult.metadata['buildResult'],
        containsPair('configuredBeforeBuild', true),
      );
    },
  );

  test('runtime event envelope serializes event contract', () {
    final event = RuntimeEventEnvelope(
      schemaVersion: 1,
      sessionId: 'run-1',
      sequence: 3,
      timestamp: DateTime.utc(2026, 5, 20, 1, 2, 3),
      eventKind: 'run.finished',
      origin: 'styio.runtime',
      payload: const <String, Object?>{'success': true},
    );

    final json = event.toJson();

    expect(json['sessionId'], 'run-1');
    expect(json['eventKind'], 'run.finished');
    expect(json['timestamp'], '2026-05-20T01:02:03.000Z');
    expect(json['payload'], <String, Object?>{'success': true});
  });
}

ExecutionController _createExecutionController() {
  return ExecutionController(
    executionAdapter: const _UnusedExecutionAdapter(),
    executionAdapterFactory: (_) async => const _UnusedExecutionAdapter(),
    runtimeEventAdapter: const _UnusedRuntimeEventAdapter(),
    log: (_) {},
    applyDiagnostics: (_) {},
  );
}

const _unusedCapabilitySnapshot = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cli,
  languageService: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not used by result contract tests',
  ),
  projectGraph: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not used by result contract tests',
  ),
  execution: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not used by result contract tests',
  ),
  runtimeEvents: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not used by result contract tests',
  ),
);

class _UnusedExecutionAdapter implements ExecutionAdapter {
  const _UnusedExecutionAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _unusedCapabilitySnapshot;

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) {
    throw UnsupportedError('Execution is not used by result contract tests.');
  }
}

class _UnusedRuntimeEventAdapter implements RuntimeEventAdapter {
  const _UnusedRuntimeEventAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _unusedCapabilitySnapshot;

  @override
  Stream<RuntimeEventEnvelope> sessionEvents(String sessionId) {
    return const Stream<RuntimeEventEnvelope>.empty();
  }
}

class _UnusedToolchainManager implements ToolchainManager {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'Toolchain execution is forbidden by the fail-closed test.',
    );
  }
}

class _RecordingToolchainManager implements ToolchainManager {
  _RecordingToolchainManager(this._results);

  final List<ToolchainRuntimeResult> _results;
  final List<List<String>> arguments = <List<String>>[];

  @override
  Future<ToolchainRuntimeResult> run({
    required ToolchainKind kind,
    ToolchainRequirement? requirement,
    List<String> arguments = const <String>[],
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
    String? standardInput,
  }) async {
    this.arguments.add(List<String>.of(arguments));
    return _results.removeAt(0);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Unexpected ToolchainManager call.');
  }
}
