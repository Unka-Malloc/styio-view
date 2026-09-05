import 'package:flutter/foundation.dart';

import '../../backend_toolchain/backend_toolchain.dart';
import '../../commands/commands.dart';
import '../../../ide/editor/editor.dart';
import '../../interaction/interaction.dart';
import '../../language/language_contract.dart';
import '../../platform/platform.dart';
import '../../toolchain/toolchain.dart';
import '../../services/observable_topology/observable_topology.dart';
import '../../../ide/workspace/workspace.dart';

const int _maxNativeToolResultRecords = 24;

enum NativeToolCommand {
  build(AppCommandId.runBuild),
  formatDocument(AppCommandId.formatActiveDocument),
  staticAnalysis(AppCommandId.runStaticAnalysis),
  tests(AppCommandId.runTests);

  const NativeToolCommand(this.appCommandId);

  final AppCommandId appCommandId;

  static NativeToolCommand fromAppCommandId(AppCommandId commandId) {
    return switch (commandId) {
      AppCommandId.runBuild => NativeToolCommand.build,
      AppCommandId.formatActiveDocument => NativeToolCommand.formatDocument,
      AppCommandId.runStaticAnalysis => NativeToolCommand.staticAnalysis,
      AppCommandId.runTests => NativeToolCommand.tests,
      _ => throw ArgumentError.value(
        commandId,
        'commandId',
        'Command is not a native tool command.',
      ),
    };
  }
}

class NativeToolCommandResult {
  const NativeToolCommandResult({
    required this.applied,
    required this.message,
    this.metadata = const <String, Object?>{},
    this.diagnostics = const <Diagnostic>[],
  });

  final bool applied;
  final String message;
  final Map<String, Object?> metadata;
  final List<Diagnostic> diagnostics;
}

class NativeDocumentFormatResult {
  const NativeDocumentFormatResult({
    required this.commandResult,
    required this.formattedText,
  });

  final NativeToolCommandResult commandResult;
  final String formattedText;

  bool get changed {
    final formatResult = commandResult.metadata['formatResult'];
    return commandResult.applied &&
        formatResult is Map<String, Object?> &&
        formatResult['changed'] == true;
  }
}

class NativeBuildCommandResult {
  const NativeBuildCommandResult({
    required this.commandResult,
    this.generatedArtifactPaths = const <String>[],
  });

  final NativeToolCommandResult commandResult;
  final List<String> generatedArtifactPaths;
}

class NativeToolResultRecord {
  const NativeToolResultRecord({
    required this.command,
    required this.label,
    required this.applied,
    required this.message,
    required this.metadata,
    required this.diagnostics,
    required this.completedAt,
  });

  final AppCommandId command;
  final String label;
  final bool applied;
  final String message;
  final Map<String, Object?> metadata;
  final List<Diagnostic> diagnostics;
  final DateTime completedAt;

  String get commandId => command.name;

  WorkspaceDiagnosticsSnapshot toWorkspaceDiagnosticsSnapshot({
    String fallbackDocumentId = '',
    String providerId = '',
    String source = 'native-tool',
    String Function(Diagnostic diagnostic)? documentIdForDiagnostic,
  }) {
    final resolvedProviderId = providerId.isEmpty
        ? 'native-tool.$commandId'
        : providerId;
    final metadataDocumentId =
        _nativeToolDiagnosticDocumentId(metadata) ?? fallbackDocumentId;
    final workspaceDiagnostics = <WorkspaceDiagnostic>[];
    for (final diagnostic in diagnostics) {
      final explicitDocumentId = documentIdForDiagnostic
          ?.call(diagnostic)
          .trim();
      workspaceDiagnostics.add(
        WorkspaceDiagnostic(
          documentId: explicitDocumentId == null || explicitDocumentId.isEmpty
              ? metadataDocumentId.trim()
              : explicitDocumentId,
          providerId: resolvedProviderId,
          source: source,
          diagnostic: diagnostic,
        ),
      );
    }
    return WorkspaceDiagnosticsSnapshot(
      providerId: resolvedProviderId,
      message: message,
      diagnostics: workspaceDiagnostics,
    );
  }

  ExecutionResultContract toResultContract() {
    return ExecutionResultContract(
      source: 'native-tool',
      id: commandId,
      kind: commandId,
      status: applied
          ? ExecutionSessionStatus.succeeded.name
          : ExecutionSessionStatus.failed.name,
      message: message,
      diagnosticCount: diagnostics.length,
      stdoutCount: 0,
      stderrCount: 0,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId,
      'label': label,
      'applied': applied,
      'message': message,
      'metadata': metadata,
      'diagnosticCount': diagnostics.length,
      'completedAt': completedAt.toIso8601String(),
      'executionResult': toResultContract().toJson(),
    };
  }
}

String? _nativeToolDiagnosticDocumentId(Map<String, Object?> metadata) {
  for (final key in <String>[
    'documentId',
    'activeDocumentId',
    'filePath',
    'path',
  ]) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  final workspaceDiagnostics = metadata['workspaceDiagnostics'];
  if (workspaceDiagnostics is Map<String, Object?>) {
    for (final key in <String>['documentId', 'activeDocumentId']) {
      final value = workspaceDiagnostics[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }
  return null;
}

/// Normalized workspace evidence used to select native build and test routes.
final class NativeBuildWorkspaceLayout {
  NativeBuildWorkspaceLayout.fromFiles(Iterable<String> files)
    : _files = Set<String>.unmodifiable(
        files.map((path) => path.replaceAll('\\', '/')),
      );

  final Set<String> _files;

  bool contains(String filePath) => _files.contains(filePath);

  bool get hasConfiguredCMakeBuild =>
      contains('build/compile_commands.json') ||
      contains('build/CMakeCache.txt');

  bool get hasNinjaBuild =>
      contains('build/build.ninja') || contains('build.ninja');

  bool get hasConfiguredCTestBuild =>
      contains('build/CTestTestfile.cmake') || contains('build/CMakeCache.txt');

  String get buildDirectory =>
      hasConfiguredCMakeBuild || contains('build/build.ninja') ? 'build' : '.';

  String get ctestDirectory => hasConfiguredCTestBuild ? 'build' : '.';

  String get compilationDatabaseDirectory =>
      contains('build/compile_commands.json') ? 'build' : '.';
}

/// Owns execution adapter state, receipts, and typed runtime events.
final class ExecutionController extends ChangeNotifier {
  ExecutionController({
    required ExecutionAdapter executionAdapter,
    required ExecutionAdapterFactory executionAdapterFactory,
    required this.runtimeEventAdapter,
    required this.log,
    required this.applyDiagnostics,
  }) : _executionAdapter = executionAdapter,
       _executionAdapterFactory = executionAdapterFactory;

  final ExecutionAdapterFactory _executionAdapterFactory;
  final RuntimeEventAdapter runtimeEventAdapter;
  final void Function(String message) log;
  final void Function(List<Diagnostic> diagnostics) applyDiagnostics;

  ExecutionAdapter _executionAdapter;
  ExecutionSession? _lastExecutionSession;
  List<RuntimeEventEnvelope> _lastRuntimeEvents =
      const <RuntimeEventEnvelope>[];
  final List<NativeToolResultRecord> _nativeToolResults =
      <NativeToolResultRecord>[];

  ExecutionAdapter get executionAdapter => _executionAdapter;
  ExecutionSession? get lastExecutionSession => _lastExecutionSession;
  List<RuntimeEventEnvelope> get lastRuntimeEvents =>
      List<RuntimeEventEnvelope>.unmodifiable(_lastRuntimeEvents);
  List<NativeToolResultRecord> get nativeToolResults =>
      List<NativeToolResultRecord>.unmodifiable(_nativeToolResults);
  NativeToolResultRecord? get lastNativeToolResult =>
      _nativeToolResults.isEmpty ? null : _nativeToolResults.first;

  NativeToolResultRecord recordNativeToolResult({
    required AppCommandId command,
    required String label,
    required bool applied,
    required String message,
    required Map<String, Object?> metadata,
    required List<Diagnostic> diagnostics,
    DateTime? completedAt,
  }) {
    final record = NativeToolResultRecord(
      command: command,
      label: label,
      applied: applied,
      message: message,
      metadata: metadata,
      diagnostics: List<Diagnostic>.unmodifiable(diagnostics),
      completedAt: (completedAt ?? DateTime.now()).toUtc(),
    );
    _nativeToolResults.insert(0, record);
    if (_nativeToolResults.length > _maxNativeToolResultRecords) {
      _nativeToolResults.removeRange(
        _maxNativeToolResultRecords,
        _nativeToolResults.length,
      );
    }
    return record;
  }

  Map<String, Object?> nativeToolBackendRouteMetadata({
    required NativeToolCommand command,
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required List<AdapterCapabilitySnapshot> adapterCapabilities,
  }) {
    return switch (command) {
      NativeToolCommand.build || NativeToolCommand.tests => <String, Object?>{
        'backendRouteSelection': selectBackendExecutionRoute(
          platformTarget: platformTarget,
          projectGraph: projectGraph,
          adapterCapabilities: adapterCapabilities,
        ).toJson(),
      },
      NativeToolCommand.formatDocument ||
      NativeToolCommand.staticAnalysis => const <String, Object?>{},
    };
  }

  Map<String, Object?> nativeToolProcessMetadata(
    ToolchainRuntimeResult result,
  ) {
    return <String, Object?>{
      if (result.exitCode != null) 'exitCode': result.exitCode,
      'stdoutLength': result.stdout.length,
      'stderrLength': result.stderr.length,
      if (result.stdout.trim().isNotEmpty)
        'stdoutPreview': _nativeToolOutputPreview(result.stdout),
      if (result.stderr.trim().isNotEmpty)
        'stderrPreview': _nativeToolOutputPreview(result.stderr),
    };
  }

  List<Diagnostic> clangBuildDiagnosticsFromOutput({
    required String output,
    required String activeDocumentPath,
    required DocumentState document,
  }) {
    return _clangDiagnosticsFromOutput(
      output: output,
      activeDocumentPath: activeDocumentPath,
      document: document,
      pattern: RegExp(
        r'^(.+?):(\d+):(\d+):\s*(warning|error|fatal error|note):\s*(.+)$',
      ),
      severityFor: _clangBuildSeverity,
      codeAndMessageFor: (rawMessage) => ('native-build', rawMessage.trim()),
    );
  }

  List<Diagnostic> clangTidyDiagnosticsFromOutput({
    required String output,
    required String activeDocumentPath,
    required DocumentState document,
  }) {
    return _clangDiagnosticsFromOutput(
      output: output,
      activeDocumentPath: activeDocumentPath,
      document: document,
      pattern: RegExp(r'^(.+?):(\d+):(\d+):\s*(warning|error|note):\s*(.+)$'),
      severityFor: _clangTidySeverity,
      codeAndMessageFor: (rawMessage) {
        final checkMatch = RegExp(
          r'\s+\[([^\]]+)\]\s*$',
        ).firstMatch(rawMessage);
        final code = checkMatch?.group(1) ?? 'clang-tidy';
        final message = checkMatch == null
            ? rawMessage.trim()
            : rawMessage.substring(0, checkMatch.start).trim();
        return (code, message.isEmpty ? 'clang-tidy diagnostic' : message);
      },
    );
  }

  Map<String, Object?> ctestResultFromOutput(
    String output, {
    required bool succeeded,
  }) {
    int? totalCount;
    int? failedCount;
    int? passedCount;
    final failedTests = <Map<String, Object?>>[];
    final summaryPattern = RegExp(
      r'(\d+)% tests passed,\s*(\d+) tests failed out of\s*(\d+)',
    );
    final failedTestPattern = RegExp(r'^\s*\d+\s+-\s+(.+?)\s+\((.+)\)\s*$');
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final summary = summaryPattern.firstMatch(line);
      if (summary != null) {
        failedCount = int.tryParse(summary.group(2) ?? '');
        totalCount = int.tryParse(summary.group(3) ?? '');
        if (totalCount != null && failedCount != null) {
          passedCount = totalCount - failedCount;
        }
        continue;
      }
      final failedTest = failedTestPattern.firstMatch(line);
      if (failedTest != null) {
        failedTests.add(<String, Object?>{
          'name': failedTest.group(1)?.trim() ?? '',
          'status': failedTest.group(2)?.trim() ?? 'failed',
        });
      }
    }
    return <String, Object?>{
      'runner': 'ctest',
      'status': succeeded && (failedCount ?? 0) == 0 ? 'passed' : 'failed',
      if (totalCount != null) 'totalCount': totalCount,
      if (passedCount != null) 'passedCount': passedCount,
      if (failedCount != null) 'failedCount': failedCount,
      if (failedTests.isNotEmpty) 'failedTests': failedTests,
    };
  }

  Future<NativeToolCommandResult> runNativeStaticAnalysis({
    required ToolchainManager manager,
    required NativeBuildWorkspaceLayout workspaceLayout,
    required String workspaceRoot,
    required String activeDocumentPath,
    required DocumentState document,
  }) async {
    final compilationDatabase = workspaceLayout.compilationDatabaseDirectory;
    if (compilationDatabase == '.' &&
        workspaceLayout.contains('CMakeLists.txt') &&
        !workspaceLayout.hasConfiguredCMakeBuild) {
      return const NativeToolCommandResult(
        applied: false,
        message:
            'Run Static Analysis blocked: run build first to generate compile_commands.json.',
        metadata: <String, Object?>{
          'requiredCommand': 'runBuild',
          'staticAnalysisResult': <String, Object?>{
            'runner': 'clang-tidy',
            'status': 'blocked',
            'reason': 'missing-compile-commands',
            'requiredCommand': 'runBuild',
          },
        },
      );
    }
    final arguments = <String>[
      if (compilationDatabase != '.') ...<String>['-p', compilationDatabase],
      activeDocumentPath,
    ];
    final result = await manager.run(
      kind: ToolchainKind.staticAnalyzer,
      requirement: const ToolchainRequirement(
        kind: ToolchainKind.staticAnalyzer,
        metadata: <String, Object?>{'toolFamily': 'clang-tidy'},
      ),
      arguments: arguments,
      workingDirectory: workspaceRoot,
      timeout: const Duration(seconds: 45),
    );
    final diagnostics = clangTidyDiagnosticsFromOutput(
      output: '${result.stdout}\n${result.stderr}',
      activeDocumentPath: activeDocumentPath,
      document: document,
    );
    final detail = result.message?.trim();
    final message = result.succeeded
        ? 'Run Static Analysis completed.'
        : 'Run Static Analysis failed${detail == null || detail.isEmpty ? '' : ': $detail'}.';
    return NativeToolCommandResult(
      applied: result.succeeded,
      message: message,
      metadata: <String, Object?>{
        'staticAnalysisResult': <String, Object?>{
          'runner': 'clang-tidy',
          'status': result.succeeded ? 'passed' : 'failed',
          'compilationDatabase': compilationDatabase,
          'arguments': arguments,
          'diagnosticCount': diagnostics.length,
          ...nativeToolProcessMetadata(result),
        },
      },
      diagnostics: diagnostics,
    );
  }

  Future<NativeToolCommandResult> runNativeTests({
    required ToolchainManager manager,
    required NativeBuildWorkspaceLayout workspaceLayout,
    required String workspaceRoot,
  }) async {
    final testDirectory = workspaceLayout.ctestDirectory;
    if (testDirectory == '.' &&
        workspaceLayout.contains('CMakeLists.txt') &&
        !workspaceLayout.hasConfiguredCTestBuild) {
      return const NativeToolCommandResult(
        applied: false,
        message:
            'Run Tests blocked: run build first to generate the CTest build directory.',
        metadata: <String, Object?>{
          'requiredCommand': 'runBuild',
          'testResult': <String, Object?>{
            'runner': 'ctest',
            'status': 'blocked',
            'reason': 'missing-ctest-build-directory',
            'requiredCommand': 'runBuild',
          },
        },
      );
    }
    final arguments = <String>[
      if (testDirectory != '.') ...<String>['--test-dir', testDirectory],
      '--output-on-failure',
    ];
    final result = await manager.run(
      kind: ToolchainKind.testRunner,
      requirement: const ToolchainRequirement(
        kind: ToolchainKind.testRunner,
        metadata: <String, Object?>{'toolFamily': 'ctest'},
      ),
      arguments: arguments,
      workingDirectory: workspaceRoot,
      timeout: const Duration(seconds: 120),
    );
    final testResult = <String, Object?>{
      ...ctestResultFromOutput(
        '${result.stdout}\n${result.stderr}',
        succeeded: result.succeeded,
      ),
      'testDirectory': testDirectory,
      'arguments': arguments,
      ...nativeToolProcessMetadata(result),
    };
    final detail = result.message?.trim();
    return NativeToolCommandResult(
      applied: result.succeeded,
      message: result.succeeded
          ? 'Run Tests completed.'
          : 'Run Tests failed${detail == null || detail.isEmpty ? '' : ': $detail'}.',
      metadata: <String, Object?>{'testResult': testResult},
    );
  }

  Future<NativeDocumentFormatResult> formatNativeDocument({
    required ToolchainManager manager,
    required String activeDocumentPath,
    required DocumentState document,
  }) async {
    final result = await manager.run(
      kind: ToolchainKind.formatter,
      requirement: const ToolchainRequirement(
        kind: ToolchainKind.formatter,
        metadata: <String, Object?>{'toolFamily': 'clang-format'},
      ),
      arguments: <String>['--assume-filename=$activeDocumentPath'],
      standardInput: document.text,
      timeout: const Duration(seconds: 20),
    );
    if (!result.succeeded) {
      final detail = result.message?.trim();
      return NativeDocumentFormatResult(
        commandResult: NativeToolCommandResult(
          applied: false,
          message:
              'Format Active Document failed${detail == null || detail.isEmpty ? '' : ': $detail'}.',
          metadata: <String, Object?>{
            'formatResult': <String, Object?>{
              'runner': 'clang-format',
              'status': 'failed',
              'changed': false,
              'outputLength': result.stdout.length,
              ...nativeToolProcessMetadata(result),
            },
          },
        ),
        formattedText: result.stdout,
      );
    }
    final changed = result.stdout.isNotEmpty && result.stdout != document.text;
    return NativeDocumentFormatResult(
      commandResult: NativeToolCommandResult(
        applied: true,
        message: result.stdout.isEmpty
            ? 'Format Active Document completed with empty formatter output.'
            : 'Format Active Document completed.',
        metadata: <String, Object?>{
          'formatResult': <String, Object?>{
            'runner': 'clang-format',
            'status': 'passed',
            'changed': changed,
            'outputLength': result.stdout.length,
            ...nativeToolProcessMetadata(result),
          },
        },
      ),
      formattedText: result.stdout,
    );
  }

  Future<NativeBuildCommandResult> runNativeBuild({
    required ToolchainManager manager,
    required NativeBuildWorkspaceLayout workspaceLayout,
    required String workspaceRoot,
    required String activeDocumentPath,
    required DocumentState document,
    required Future<ClangCppVersionSelection?> Function() loadClangCppSelection,
  }) async {
    final needsConfigure =
        workspaceLayout.contains('CMakeLists.txt') &&
        !workspaceLayout.hasConfiguredCMakeBuild;
    final buildDirectory = needsConfigure
        ? 'build'
        : workspaceLayout.buildDirectory;
    if (!needsConfigure &&
        workspaceLayout.hasNinjaBuild &&
        !await _hasBuildToolFamily(manager, 'cmake')) {
      final arguments = buildDirectory == '.'
          ? const <String>[]
          : <String>['-C', buildDirectory];
      final result = await manager.run(
        kind: ToolchainKind.buildTool,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.buildTool,
          metadata: <String, Object?>{'toolFamily': 'ninja'},
        ),
        arguments: arguments,
        workingDirectory: workspaceRoot,
        timeout: const Duration(minutes: 5),
      );
      return NativeBuildCommandResult(
        commandResult: _nativeBuildCommandResult(
          result: result,
          runner: 'ninja',
          buildDirectory: buildDirectory,
          arguments: arguments,
          configuredBeforeBuild: false,
          activeDocumentPath: activeDocumentPath,
          document: document,
        ),
      );
    }

    Map<String, Object?>? configureResult;
    final generatedArtifacts = <String>[];
    if (needsConfigure) {
      final selection = await loadClangCppSelection();
      final configureArguments = <String>[
        '-S',
        '.',
        '-B',
        buildDirectory,
        ...?selection?.cmakeNinjaConfigureArguments,
      ];
      final configure = await manager.run(
        kind: ToolchainKind.buildTool,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.buildTool,
          metadata: <String, Object?>{'toolFamily': 'cmake'},
        ),
        arguments: configureArguments,
        workingDirectory: workspaceRoot,
        timeout: const Duration(minutes: 5),
      );
      configureResult = <String, Object?>{
        'runner': 'cmake',
        'status': configure.succeeded ? 'passed' : 'failed',
        'arguments': configureArguments,
        ...nativeToolProcessMetadata(configure),
      };
      if (!configure.succeeded) {
        return NativeBuildCommandResult(
          commandResult: NativeToolCommandResult(
            applied: false,
            message: _nativeToolFailureMessage('Run Build', configure.message),
            metadata: <String, Object?>{
              'buildResult': <String, Object?>{
                'runner': 'cmake',
                'status': 'failed',
                'buildDirectory': buildDirectory,
                'configuredBeforeBuild': true,
                'configureResult': configureResult,
                'diagnosticCount': 0,
              },
            },
          ),
        );
      }
      generatedArtifacts.addAll(<String>[
        '$buildDirectory/CMakeCache.txt',
        '$buildDirectory/compile_commands.json',
        if (configureArguments.contains('Ninja')) '$buildDirectory/build.ninja',
      ]);
    }

    final arguments = <String>['--build', buildDirectory];
    final result = await manager.run(
      kind: ToolchainKind.buildTool,
      requirement: const ToolchainRequirement(
        kind: ToolchainKind.buildTool,
        metadata: <String, Object?>{'toolFamily': 'cmake'},
      ),
      arguments: arguments,
      workingDirectory: workspaceRoot,
      timeout: const Duration(minutes: 5),
    );
    return NativeBuildCommandResult(
      commandResult: _nativeBuildCommandResult(
        result: result,
        runner: 'cmake',
        buildDirectory: buildDirectory,
        arguments: arguments,
        configuredBeforeBuild: configureResult != null,
        configureResult: configureResult,
        activeDocumentPath: activeDocumentPath,
        document: document,
      ),
      generatedArtifactPaths: List<String>.unmodifiable(generatedArtifacts),
    );
  }

  Future<bool> _hasBuildToolFamily(
    ToolchainManager manager,
    String toolFamily,
  ) async {
    final catalog = await manager.loadCatalog();
    return catalog
        .list(kind: ToolchainKind.buildTool)
        .any((descriptor) => descriptor.metadata['toolFamily'] == toolFamily);
  }

  NativeToolCommandResult _nativeBuildCommandResult({
    required ToolchainRuntimeResult result,
    required String runner,
    required String buildDirectory,
    required List<String> arguments,
    required bool configuredBeforeBuild,
    required String activeDocumentPath,
    required DocumentState document,
    Map<String, Object?>? configureResult,
  }) {
    final diagnostics = clangBuildDiagnosticsFromOutput(
      output: '${result.stdout}\n${result.stderr}',
      activeDocumentPath: activeDocumentPath,
      document: document,
    );
    return NativeToolCommandResult(
      applied: result.succeeded,
      message: result.succeeded
          ? 'Run Build completed.'
          : _nativeToolFailureMessage('Run Build', result.message),
      metadata: <String, Object?>{
        'buildResult': <String, Object?>{
          'runner': runner,
          'status': result.succeeded ? 'passed' : 'failed',
          'buildDirectory': buildDirectory,
          'configuredBeforeBuild': configuredBeforeBuild,
          if (configureResult != null) 'configureResult': configureResult,
          'arguments': arguments,
          'diagnosticCount': diagnostics.length,
          ...nativeToolProcessMetadata(result),
        },
      },
      diagnostics: diagnostics,
    );
  }

  String _nativeToolFailureMessage(String label, String? detail) {
    final normalizedDetail = detail?.trim();
    return '$label failed${normalizedDetail == null || normalizedDetail.isEmpty ? '' : ': $normalizedDetail'}.';
  }

  List<Diagnostic> _clangDiagnosticsFromOutput({
    required String output,
    required String activeDocumentPath,
    required DocumentState document,
    required RegExp pattern,
    required DiagnosticSeverity Function(String severity) severityFor,
    required (String, String) Function(String rawMessage) codeAndMessageFor,
  }) {
    final diagnostics = <Diagnostic>[];
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = pattern.firstMatch(line.trim());
      if (match == null ||
          !_isActiveDocumentPath(
            match.group(1) ?? '',
            activeDocumentPath: activeDocumentPath,
            documentId: document.documentId,
          )) {
        continue;
      }
      final lineNumber = int.tryParse(match.group(2) ?? '');
      final columnNumber = int.tryParse(match.group(3) ?? '');
      if (lineNumber == null || columnNumber == null) {
        continue;
      }
      final start = _offsetForLineColumn(
        document.text,
        lineNumber,
        columnNumber,
      );
      if (start == null) {
        continue;
      }
      final (code, message) = codeAndMessageFor(match.group(5) ?? '');
      diagnostics.add(
        Diagnostic(
          severity: severityFor(match.group(4) ?? ''),
          code: code,
          message: message,
          range: SourceRange(
            start: start,
            end: start < document.length ? start + 1 : start,
          ),
        ),
      );
    }
    return diagnostics;
  }

  String _nativeToolOutputPreview(String output, {int limit = 4000}) {
    final normalized = output.trim();
    if (normalized.length <= limit) {
      return normalized;
    }
    return '${normalized.substring(0, limit)}...';
  }

  bool _isActiveDocumentPath(
    String path, {
    required String activeDocumentPath,
    required String documentId,
  }) {
    final normalized = path.replaceAll('\\', '/');
    final active = activeDocumentPath.replaceAll('\\', '/');
    final normalizedDocumentId = documentId.replaceAll('\\', '/');
    return normalized == active ||
        normalized == normalizedDocumentId ||
        normalized.endsWith('/$active') ||
        normalized.endsWith('/$normalizedDocumentId');
  }

  int? _offsetForLineColumn(String text, int lineNumber, int columnNumber) {
    if (lineNumber < 1 || columnNumber < 1) {
      return null;
    }
    var line = 1;
    var lineStart = 0;
    while (line < lineNumber) {
      final nextBreak = text.indexOf('\n', lineStart);
      if (nextBreak < 0) {
        return null;
      }
      lineStart = nextBreak + 1;
      line += 1;
    }
    final lineEnd = text.indexOf('\n', lineStart);
    final end = lineEnd < 0 ? text.length : lineEnd;
    final offset = lineStart + columnNumber - 1;
    if (offset < lineStart) {
      return lineStart;
    }
    if (offset > end) {
      return end;
    }
    return offset;
  }

  DiagnosticSeverity _clangTidySeverity(String severity) {
    return switch (severity) {
      'error' => DiagnosticSeverity.error,
      'note' => DiagnosticSeverity.hint,
      _ => DiagnosticSeverity.warning,
    };
  }

  DiagnosticSeverity _clangBuildSeverity(String severity) {
    return switch (severity) {
      'error' || 'fatal error' => DiagnosticSeverity.error,
      'note' => DiagnosticSeverity.hint,
      _ => DiagnosticSeverity.warning,
    };
  }

  Future<void> refreshAdapter(ProjectGraphSnapshot projectGraph) async {
    _executionAdapter = await _executionAdapterFactory(projectGraph);
  }

  Future<void> run({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required List<AdapterCapabilitySnapshot> adapterCapabilities,
    required DocumentState document,
    required SelectionState selection,
    required String activeFilePath,
  }) async {
    final routeSelection = selectBackendExecutionRoute(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      adapterCapabilities: adapterCapabilities,
    );
    if (!routeSelection.allowed) {
      _lastExecutionSession = ExecutionSession(
        sessionId: 'route-gate:${projectGraph.id}',
        kind: 'run',
        status: ExecutionSessionStatus.blocked,
        statusMessage:
            routeSelection.blockedReason ?? 'Execution route blocked.',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: const <ExecutionLogEvent>[],
        stderrEvents: const <ExecutionLogEvent>[],
      );
      _lastRuntimeEvents = const <RuntimeEventEnvelope>[];
      log(
        'Run blocked by backend route selection '
        '(${routeSelection.routeKind.wireValue}/'
        '${routeSelection.adapterKind.wireValue}): '
        '${_lastExecutionSession!.statusMessage}',
      );
      notifyListeners();
      return;
    }
    log(
      'Run route selected: ${routeSelection.routeKind.wireValue} '
      'via ${routeSelection.adapterKind.wireValue}.',
    );
    final runUnit = selectRunUnitForEditor(
      document: document,
      selection: selection,
    );
    final session = await _executionAdapter.runActiveDocument(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      document: document,
      activeFilePath: activeFilePath,
    );
    final rangedSession = _sessionWithRunUnit(session, runUnit);
    _lastExecutionSession = rangedSession;
    _lastRuntimeEvents = await runtimeEventAdapter
        .sessionEvents(rangedSession.sessionId)
        .toList();
    log(
      'Run unit ${runUnit.kind.name}: '
      '${runUnit.range.start}-${runUnit.range.end}.',
    );
    log('Run ${rangedSession.status.name}: ${rangedSession.statusMessage}');
    for (final event in rangedSession.stdoutEvents.take(3)) {
      log('stdout: ${event.message}');
    }
    for (final event in rangedSession.stderrEvents.take(3)) {
      log('stderr: ${event.message}');
    }
    if (rangedSession.diagnostics.isNotEmpty) {
      applyDiagnostics(rangedSession.diagnostics);
      log(
        'diagnostics: ${rangedSession.diagnostics.length} issue(s) returned by the execution route.',
      );
    }
    if (_lastRuntimeEvents.isNotEmpty) {
      log(
        'runtime events: ${_lastRuntimeEvents.length} event(s) for session ${rangedSession.sessionId}.',
      );
      for (final event in _lastRuntimeEvents.take(4)) {
        log('runtime: ${event.eventKind}');
      }
    }
    notifyListeners();
  }

  Future<ObservedExecutionRun> runObserved({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required List<AdapterCapabilitySnapshot> adapterCapabilities,
    required DocumentState document,
    required SelectionState selection,
    required String activeFilePath,
    required RuntimeObservationRequest observation,
  }) async {
    final routeSelection = selectBackendExecutionRoute(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      adapterCapabilities: adapterCapabilities,
    );
    if (!routeSelection.allowed) {
      final session = ExecutionSession(
        sessionId: 'route-gate:${projectGraph.id}',
        kind: 'run',
        status: ExecutionSessionStatus.blocked,
        statusMessage:
            routeSelection.blockedReason ?? 'Execution route blocked.',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: const <ExecutionLogEvent>[],
        stderrEvents: const <ExecutionLogEvent>[],
      );
      _lastExecutionSession = session;
      _lastRuntimeEvents = const <RuntimeEventEnvelope>[];
      log(
        'Observed run blocked by backend route selection '
        '(${routeSelection.routeKind.wireValue}/'
        '${routeSelection.adapterKind.wireValue}): '
        '${session.statusMessage}',
      );
      notifyListeners();
      return ObservedExecutionRun(
        session: session,
        unavailableReason: ObservableReasonCode.unsupportedPlatform,
      );
    }
    log(
      'Observed run route selected: ${routeSelection.routeKind.wireValue} '
      'via ${routeSelection.adapterKind.wireValue}.',
    );
    final runUnit = selectRunUnitForEditor(
      document: document,
      selection: selection,
    );
    final adapter = _executionAdapter;
    if (adapter is! ObservedExecutionAdapter) {
      final session = ExecutionSession(
        sessionId: 'observed-unsupported:${projectGraph.id}',
        kind: 'run',
        status: ExecutionSessionStatus.blocked,
        statusMessage: 'Observed runs require a local execution adapter.',
        diagnostics: const <Diagnostic>[],
        stdoutEvents: const <ExecutionLogEvent>[],
        stderrEvents: const <ExecutionLogEvent>[],
      );
      _lastExecutionSession = session;
      _lastRuntimeEvents = const <RuntimeEventEnvelope>[];
      notifyListeners();
      return ObservedExecutionRun(
        session: session,
        unavailableReason: ObservableReasonCode.unsupportedPlatform,
      );
    }
    final observedAdapter = adapter as ObservedExecutionAdapter;
    final run = await observedAdapter.runActiveDocumentObserved(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      document: document,
      activeFilePath: activeFilePath,
      observation: observation,
    );
    final rangedSession = _sessionWithRunUnit(run.session, runUnit);
    _lastExecutionSession = rangedSession;
    _lastRuntimeEvents = await runtimeEventAdapter
        .sessionEvents(rangedSession.sessionId)
        .toList();
    log(
      'Observed run unit ${runUnit.kind.name}: '
      '${runUnit.range.start}-${runUnit.range.end}.',
    );
    log('Observed run ${rangedSession.status.name}: ${rangedSession.statusMessage}');
    notifyListeners();
    return ObservedExecutionRun(
      session: rangedSession,
      runtimeEventsPath: run.runtimeEventsPath,
      unavailableReason: run.unavailableReason,
      release: run.release,
    );
  }

  ExecutionSession _sessionWithRunUnit(
    ExecutionSession session,
    RunUnitSelection runUnit,
  ) {
    return ExecutionSession(
      sessionId: session.sessionId,
      kind: session.kind,
      status: session.status,
      statusMessage: session.statusMessage,
      diagnostics: session.diagnostics,
      stdoutEvents: session.stdoutEvents,
      stderrEvents: session.stderrEvents,
      unitRange: runUnit.range,
      receipt: session.receipt,
    );
  }
}
