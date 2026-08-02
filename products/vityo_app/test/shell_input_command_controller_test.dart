import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/workspace/workspace_controller.dart';
import 'package:vityo_app/src/ide/workspace/workspace_document_store.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/shell_input_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_file_command_controller.dart';

void main() {
  test(
    'typed command input reaches each standalone IDE domain route',
    () async {
      final calls = <String, Object?>{};
      final logs = <String>[];
      final controller = _controller(
        calls: calls,
        logs: logs,
        testConfigurationExists: true,
      );

      await controller.execute(
        AppCommandId.previewWorkspaceReplace,
        'old name -> new name',
      );
      await controller.execute(AppCommandId.renameSymbol, 'renamed');
      await controller.execute(
        AppCommandId.previewSourceControlDiff,
        'src/main.styio',
      );
      await controller.execute(
        AppCommandId.stageSourceControl,
        'src/a.styio, src/b.styio\nsrc/c.styio',
      );
      await controller.execute(
        AppCommandId.unstageSourceControl,
        'src/d.styio',
      );
      await controller.execute(
        AppCommandId.planSourceControlBranchSwitch,
        'nightly',
      );
      await controller.execute(
        AppCommandId.planSourceControlCommitDraft,
        'Fix routes -> src/a.styio, src/b.styio',
      );
      await controller.execute(
        AppCommandId.selectClangCppVersion,
        'clang-18 c++23',
      );
      await controller.execute(AppCommandId.selectDebugThread, '7');
      await controller.execute(AppCommandId.selectDebugStackFrame, 'frame-2');
      await controller.execute(AppCommandId.runTestConfiguration, 'unit');
      await controller.execute(AppCommandId.debugTestConfiguration, 'unit');

      expect(calls['replace'], <String>['old name', 'new name']);
      expect(calls['rename'], 'renamed');
      expect(calls['diff'], 'src/main.styio');
      expect(calls['stage'], <String>[
        'src/a.styio',
        'src/b.styio',
        'src/c.styio',
      ]);
      expect(calls['unstage'], <String>['src/d.styio']);
      expect(calls['branch'], 'nightly');
      expect(calls['commit'], <String>[
        'Fix routes',
        'src/a.styio',
        'src/b.styio',
      ]);
      expect(calls['clang'], <String>['clang-18', 'c++23']);
      expect(calls['debugThread'], '7');
      expect(calls['debugFrame'], 'frame-2');
      expect(calls['tests'], <String>['run:unit', 'debug:unit']);
      expect(logs, isEmpty);
    },
  );

  test('malformed or unavailable typed input fails closed', () async {
    final calls = <String, Object?>{};
    final logs = <String>[];
    final controller = _controller(
      calls: calls,
      logs: logs,
      testConfigurationExists: false,
    );

    await controller.execute(AppCommandId.previewWorkspaceReplace, 'missing');
    await controller.execute(AppCommandId.stageSourceControl, '  ');
    await controller.execute(AppCommandId.planSourceControlCommitDraft, ' -> ');
    await controller.execute(AppCommandId.selectClangCppVersion, '  ');
    await controller.execute(AppCommandId.runTestConfiguration, 'unknown');

    expect(calls, isEmpty);
    expect(logs, hasLength(5));
    expect(logs.every((message) => message.contains('skipped')), isTrue);
  });
}

ShellInputCommandController _controller({
  required Map<String, Object?> calls,
  required List<String> logs,
  required bool testConfigurationExists,
}) {
  final graph = ProjectGraphSnapshot.scratch(
    workspaceRoot: '/workspace',
    activeFilePath: 'src/main.styio',
    title: 'Workspace',
    notes: const <String>[],
  );
  final workspaceController = WorkspaceController(projectSnapshot: graph);
  final documentStore = InMemoryWorkspaceDocumentStore();
  return ShellInputCommandController(
    workspaceFileCommands: WorkspaceFileCommandController(
      workspaceController: workspaceController,
      documentStore: documentStore,
      openWorkspaceFile: (_) async => false,
      reloadActiveDocument: () async {},
    ),
    blockedReasonForCommand: (_) => null,
    executeCommand: (_) async {},
    searchWorkspace: (_) async => true,
    openWorkspaceFile: (_) async => true,
    previewWorkspaceReplace:
        ({required String query, required String replacement}) async {
          calls['replace'] = <String>[query, replacement];
        },
    renameSymbol: (newName) async {
      calls['rename'] = newName;
    },
    previewSourceControlDiff: (path) async {
      calls['diff'] = path;
    },
    stageSourceControlPaths: (paths) async {
      calls['stage'] = paths;
    },
    unstageSourceControlPaths: (paths) async {
      calls['unstage'] = paths;
    },
    planSourceControlBranchSwitch: (targetBranch) async {
      calls['branch'] = targetBranch;
    },
    planSourceControlCommitDraft:
        ({required String message, List<String>? selectedPaths}) {
          calls['commit'] = <String>[message, ...?selectedPaths];
        },
    selectClangCppVersion: (versionId, {String? cppStandard}) async {
      calls['clang'] = <String>[
        versionId,
        if (cppStandard != null) cppStandard,
      ];
    },
    selectDebugThread: (threadId) async {
      calls['debugThread'] = threadId;
    },
    selectDebugStackFrame: (frameId) async {
      calls['debugFrame'] = frameId;
    },
    runTestConfiguration: (configurationId, {required bool debug}) async {
      if (!testConfigurationExists) {
        return false;
      }
      final tests =
          calls.putIfAbsent('tests', () => <String>[]) as List<String>;
      tests.add('${debug ? 'debug' : 'run'}:$configurationId');
      return true;
    },
    log: logs.add,
    notify: () {},
  );
}
