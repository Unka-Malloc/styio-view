import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:styio_ide/src/view_ide/interaction/toolchain_status_surface.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/toolchain_controller.dart';
import 'package:styio_ide/src/view_ide/toolchain/toolchain.dart'
    hide ToolchainRecoveryAction;

void main() {
  test('toolchain selection commands fail closed without a manager', () async {
    final logs = <String>[];
    final controller = ToolchainController(
      managementAdapter: const _UnexpectedToolchainManagementAdapter(),
      projectGraph: _unexpectedProjectGraph,
      refreshProjectGraph: _unexpectedProjectGraphRefresh,
      manager: null,
      statusReport: null,
      log: logs.add,
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    expect(await controller.selectCandidate('clang-18'), isNull);
    expect(await controller.selectClangCppVersion('clang-18'), isNull);
    expect(await controller.clearCandidate(ToolchainKind.compiler), isNull);

    expect(logs, hasLength(3));
    expect(logs[0], contains('no ToolchainManager'));
    expect(logs[1], contains('no ToolchainManager'));
    expect(logs[2], contains('no ToolchainManager'));
    expect(notifications, 3);
  });

  test('toolchain controller retains initial Clang/C++ preference', () {
    const preference = ClangCppVersionPreference(
      versionId: 'clang-18',
      cppStandard: CppLanguageStandard.cpp23,
    );
    final controller = ToolchainController(
      managementAdapter: const _UnexpectedToolchainManagementAdapter(),
      projectGraph: _unexpectedProjectGraph,
      refreshProjectGraph: _unexpectedProjectGraphRefresh,
      manager: null,
      statusReport: null,
      log: (_) {},
      clangCppVersionPreference: preference,
    );
    addTearDown(controller.dispose);

    expect(controller.clangCppVersionPreference?.versionId, 'clang-18');
    expect(
      controller.clangCppVersionPreference?.cppStandard,
      CppLanguageStandard.cpp23,
    );
  });

  test(
    'managed install planning and execution fail closed without manager',
    () async {
      final logs = <String>[];
      final controller = ToolchainController(
        managementAdapter: const _UnexpectedToolchainManagementAdapter(),
        projectGraph: _unexpectedProjectGraph,
        refreshProjectGraph: _unexpectedProjectGraphRefresh,
        manager: null,
        statusReport: null,
        log: logs.add,
      );
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      expect(controller.planManagedInstallation(), isNull);
      expect(await controller.executeLastInstallPlan(), isNull);

      expect(controller.lastInstallPlan, isNull);
      expect(controller.lastInstallExecutionResult, isNull);
      expect(
        logs.singleWhere((entry) => entry.contains('planning')),
        contains('unavailable'),
      );
      expect(
        logs.singleWhere((entry) => entry.contains('execution')),
        contains('unavailable'),
      );
      expect(notifications, 2);
    },
  );

  test('bootstrap summary and actions fail closed without a manager', () async {
    final logs = <String>[];
    final controller = ToolchainController(
      managementAdapter: const _UnexpectedToolchainManagementAdapter(),
      projectGraph: _unexpectedProjectGraph,
      refreshProjectGraph: _unexpectedProjectGraphRefresh,
      manager: null,
      statusReport: null,
      log: logs.add,
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    expect(await controller.refreshBootstrapSummary(), isNull);

    final result = await controller.handleBootstrapAction(
      'open-toolchain-settings',
    );
    expect(result, isNotNull);
    expect(result!.status, ToolchainBootstrapActionDispatchStatus.blocked);
    expect(result.message, contains('no bootstrap summary'));
    expect(controller.bootstrapSummary, isNull);
    expect(controller.lastBootstrapActionDispatch, same(result));
    expect(
      logs.where((entry) => entry.contains('summary unavailable')),
      hasLength(2),
    );
    expect(notifications, 1);
  });

  test(
    'managed compiler success records command and refreshes graph',
    () async {
      final graph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/main.styio',
        title: 'demo',
        notes: const <String>[],
      );
      const commandResult = ToolchainCommandResult(
        command: 'styio tool install',
        status: ToolchainCommandStatus.succeeded,
        statusMessage: 'installed',
        stdout: '',
        stderr: '',
      );
      final adapter = _RecordingToolchainManagementAdapter(commandResult);
      final logs = <String>[];
      final refreshReasons = <String?>[];
      final controller = ToolchainController(
        managementAdapter: adapter,
        projectGraph: () => graph,
        refreshProjectGraph: ({String? reason}) async {
          refreshReasons.add(reason);
        },
        manager: null,
        statusReport: null,
        log: logs.add,
      );
      addTearDown(controller.dispose);

      final result = await controller.installManagedCompiler(
        styioBinaryPath: '/tools/styio',
      );

      expect(result, same(commandResult));
      expect(controller.lastCommand, same(commandResult));
      expect(adapter.lastProjectGraph, same(graph));
      expect(adapter.lastStyioBinaryPath, '/tools/styio');
      expect(refreshReasons, <String?>['tool install completed']);
      expect(logs.single, contains('succeeded: installed'));
    },
  );

  test('recovery retry fails closed when no compiler is resolved', () async {
    final logs = <String>[];
    final controller = ToolchainController(
      managementAdapter: const _UnexpectedToolchainManagementAdapter(),
      projectGraph: () => ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/main.styio',
        title: 'demo',
        notes: const <String>[],
      ),
      refreshProjectGraph: _unexpectedProjectGraphRefresh,
      manager: null,
      statusReport: null,
      log: logs.add,
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications += 1);

    await controller.handleRecoveryAction(
      const ToolchainRecoveryAction(
        id: 'retry-tool-use',
        label: 'Retry',
        description: 'Retry compiler selection.',
      ),
    );

    expect(logs.first, contains('retry-tool-use'));
    expect(logs.last, contains('no active compiler'));
    expect(notifications, 1);
  });
}

ProjectGraphSnapshot _unexpectedProjectGraph() {
  throw StateError('Project graph should not be read by this test.');
}

Future<void> _unexpectedProjectGraphRefresh({String? reason}) async {
  throw StateError('Project graph should not be refreshed by this test.');
}

final class _UnexpectedToolchainManagementAdapter
    implements ToolchainManagementAdapter {
  const _UnexpectedToolchainManagementAdapter();

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) {
    throw StateError('Toolchain management should not run in this test.');
  }

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) {
    throw StateError('Toolchain management should not run in this test.');
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) {
    throw StateError('Toolchain management should not run in this test.');
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) {
    throw StateError('Toolchain management should not run in this test.');
  }
}

final class _RecordingToolchainManagementAdapter
    implements ToolchainManagementAdapter {
  _RecordingToolchainManagementAdapter(this.result);

  final ToolchainCommandResult result;
  ProjectGraphSnapshot? lastProjectGraph;
  String? lastStyioBinaryPath;

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async {
    lastProjectGraph = projectGraph;
    return result;
  }

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async {
    lastProjectGraph = projectGraph;
    lastStyioBinaryPath = styioBinaryPath;
    return result;
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    lastProjectGraph = projectGraph;
    return result;
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    lastProjectGraph = projectGraph;
    return result;
  }
}
