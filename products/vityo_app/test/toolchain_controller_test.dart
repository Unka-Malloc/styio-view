import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/toolchain_controller.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('generic selection fails closed without a manager', () async {
    final logs = <String>[];
    final controller = _controller(logs.add);
    addTearDown(controller.dispose);

    expect(await controller.selectCandidate('clang-18'), isNull);
    expect(await controller.selectClangCppVersion('clang-18'), isNull);
    expect(await controller.clearCandidate(ToolchainKind.compiler), isNull);
    expect(logs, everyElement(contains('no ToolchainManager')));
  });

  test('generic install and bootstrap fail closed without a manager', () async {
    final logs = <String>[];
    final controller = _controller(logs.add);
    addTearDown(controller.dispose);

    expect(controller.planManagedInstallation(), isNull);
    expect(await controller.executeLastInstallPlan(), isNull);
    expect(await controller.refreshBootstrapSummary(), isNull);

    final result = await controller.handleBootstrapAction(
      'open-toolchain-settings',
    );
    expect(result, isNotNull);
    expect(result!.status, ToolchainBootstrapActionDispatchStatus.blocked);
    expect(result.message, contains('no bootstrap summary'));
  });

  test('controller retains initial Clang/C++ preference', () {
    const preference = ClangCppVersionPreference(
      versionId: 'clang-18',
      cppStandard: CppLanguageStandard.cpp23,
    );
    final controller = ToolchainController(
      projectGraph: _projectGraph,
      manager: null,
      statusReport: null,
      log: (_) {},
      clangCppVersionPreference: preference,
    );
    addTearDown(controller.dispose);

    expect(controller.clangCppVersionPreference, preference);
  });
}

ToolchainController _controller(void Function(String) log) {
  return ToolchainController(
    projectGraph: _projectGraph,
    manager: null,
    statusReport: null,
    log: log,
  );
}

ProjectGraphSnapshot _projectGraph() {
  return ProjectGraphSnapshot.scratch(
    workspaceRoot: '/workspace/demo',
    activeFilePath: '/workspace/demo/main.styio',
    title: 'demo',
    notes: const <String>[],
  );
}
