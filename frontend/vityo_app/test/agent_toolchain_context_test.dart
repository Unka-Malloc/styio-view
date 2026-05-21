import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent_session_context.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test(
    'agent toolchain context groups native C++ tools by capability kind',
    () {
      const snapshot = ToolchainStateSnapshot(
        targetId: 'native-cpp-agent',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'native-cmake-build-tool',
            kind: ToolchainKind.buildTool,
            displayName: 'CMake Build System',
            executablePath: '/usr/bin/cmake',
            active: false,
            metadata: <String, Object?>{'toolRole': 'build-system-generator'},
          ),
          ToolchainStateEntry(
            id: 'native-lldb-debugger',
            kind: ToolchainKind.debugger,
            displayName: 'LLDB Native Debugger',
            executablePath: '/usr/bin/lldb',
            active: false,
            metadata: <String, Object?>{'debuggerKind': 'lldb'},
          ),
          ToolchainStateEntry(
            id: 'native-clang-format-formatter',
            kind: ToolchainKind.formatter,
            displayName: 'clang-format Formatter',
            executablePath: '/usr/bin/clang-format',
            active: false,
            metadata: <String, Object?>{'toolRole': 'formatter'},
          ),
          ToolchainStateEntry(
            id: 'native-clang-tidy-static-analyzer',
            kind: ToolchainKind.staticAnalyzer,
            displayName: 'clang-tidy Static Analyzer',
            executablePath: '/usr/bin/clang-tidy',
            active: false,
            metadata: <String, Object?>{
              'toolRole': 'static-analysis',
              'consumesCompileCommands': true,
            },
          ),
          ToolchainStateEntry(
            id: 'native-ctest-test-runner',
            kind: ToolchainKind.testRunner,
            displayName: 'CTest Test Runner',
            executablePath: '/usr/bin/ctest',
            active: false,
            metadata: <String, Object?>{'toolRole': 'test-runner'},
          ),
          ToolchainStateEntry(
            id: 'native-clangd-language-service',
            kind: ToolchainKind.languageService,
            displayName: 'clangd C/C++ Language Server',
            executablePath: '/usr/bin/clangd',
            active: false,
            metadata: <String, Object?>{
              'toolRole': 'native-language-service',
              'consumesCompileCommands': true,
            },
          ),
        ],
      );

      final context = AgentToolchainContext.fromSnapshot(snapshot);
      final json = context.toJson();
      final nativeTools = json['nativeTools']! as Map<String, Object?>;

      expect(nativeTools['buildToolCount'], 1);
      expect(nativeTools['debuggerCount'], 1);
      expect(nativeTools['formatterCount'], 1);
      expect(nativeTools['staticAnalyzerCount'], 1);
      expect(nativeTools['testRunnerCount'], 1);
      expect(nativeTools['languageServiceCount'], 1);
      expect(nativeTools['hasBuildTool'], isTrue);
      expect(nativeTools['hasDebugger'], isTrue);
      expect(nativeTools['hasFormatter'], isTrue);
      expect(nativeTools['hasStaticAnalyzer'], isTrue);
      expect(nativeTools['hasTestRunner'], isTrue);
      expect(nativeTools['hasLanguageService'], isTrue);
      expect(_singleId(nativeTools['buildTools']), 'native-cmake-build-tool');
      expect(_singleId(nativeTools['debuggers']), 'native-lldb-debugger');
      expect(
        _singleId(nativeTools['formatters']),
        'native-clang-format-formatter',
      );
      expect(
        _singleId(nativeTools['staticAnalyzers']),
        'native-clang-tidy-static-analyzer',
      );
      expect(_singleId(nativeTools['testRunners']), 'native-ctest-test-runner');
      expect(
        _singleId(nativeTools['languageServices']),
        'native-clangd-language-service',
      );
    },
  );

  test('agent toolchain context exposes bootstrap action facts', () {
    const snapshot = ToolchainStateSnapshot(
      targetId: 'agent-bootstrap',
      workspaceId: 'demo',
      entries: <ToolchainStateEntry>[],
    );
    const requirement = ToolchainRequirement(
      kind: ToolchainKind.languageService,
    );
    const summary = ToolchainManagerBootstrapSummary(
      managerReport: ToolchainManagerStatusReport(
        status: ToolchainManagerStatus.unresolved,
        snapshot: snapshot,
        requirement: requirement,
        resolution: ToolchainResolution(
          status: ToolchainResolutionStatus.missingKind,
          requirement: requirement,
          message: 'No language service descriptor.',
        ),
        recoveryState: ToolchainRecoveryState(
          kind: ToolchainRecoveryStateKind.needsSelection,
          actionIds: <String>['select-styio-language-service'],
        ),
      ),
      styioLifecycle: StyioToolchainLifecycleReport(
        state: StyioToolchainLifecycleState.missing,
        requiredRoles: <StyioToolchainRole>[
          StyioToolchainRole.languageService,
        ],
        roles: <StyioToolchainRoleStatus>[
          StyioToolchainRoleStatus(
            role: StyioToolchainRole.languageService,
            state: StyioToolchainRoleState.missing,
            required: true,
            message: 'Missing Styio language service.',
          ),
        ],
        message: 'Missing Styio toolchain.',
      ),
      settingsActionIds: <String>['install-styio-language-service'],
      installerActionIds: <String>['install-managed-styio-toolchain'],
      projectBootstrapActionIds: <String>['bootstrap-styio-toolchain'],
    );
    const dispatch = ToolchainBootstrapActionDispatchResult(
      status: ToolchainBootstrapActionDispatchStatus.missingHandler,
      actionId: 'install-managed-styio-toolchain',
      message: 'No installer handler is registered.',
      todo: 'TODO: bind installer action handler.',
    );

    final context = AgentToolchainContext.fromSnapshot(
      snapshot,
      toolchainBootstrapSummary: summary,
      toolchainBootstrapActionDispatch: dispatch,
    );
    final json = context.toJson();
    final bootstrap = json['bootstrap']! as Map<String, Object?>;
    final executionPlan =
        bootstrap['executionPlan']! as Map<String, Object?>;
    final lastDispatch =
        json['lastBootstrapActionDispatch']! as Map<String, Object?>;
    final suggestedCommandIds =
        json['suggestedCommandIds']! as List<Object?>;

    expect(bootstrap['ready'], isFalse);
    expect(executionPlan['canExecute'], isTrue);
    expect(executionPlan['stepCount'], 3);
    expect(
      suggestedCommandIds,
      containsAll(<String>['bootstrapStyioToolchain', 'openSettings']),
    );
    expect(lastDispatch['status'], 'missing-handler');
    expect(lastDispatch['actionId'], 'install-managed-styio-toolchain');
    expect(lastDispatch['todo'], contains('TODO'));
  });
}

String _singleId(Object? value) {
  final entries = value! as List<Object?>;
  final entry = entries.single! as Map<String, Object?>;
  return entry['id']! as String;
}
