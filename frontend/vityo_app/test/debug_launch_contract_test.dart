import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';

void main() {
  test(
    'debug launch contract builds DAP launch configuration from toolchain',
    () {
      final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
        debugger: const ToolchainDescriptor(
          id: 'lldb-dap',
          kind: ToolchainKind.debugger,
          displayName: 'LLDB DAP',
          executablePath: '/usr/bin/lldb-dap',
          metadata: <String, Object?>{
            'adapterProtocol': 'dap',
            'programPath': 'build/vityo',
            'cwd': 'build',
            'debugAdapterArguments': <String>['--stdio'],
            'arguments': <String>['--smoke'],
            'environment': <String, Object?>{'VITYO_ENV': 'test'},
            'stopOnEntry': true,
          },
        ),
        workspaceRoot: '/workspace/vityo',
        breakpoints: const <DebugLaunchBreakpoint>[
          DebugLaunchBreakpoint(filePath: 'src/main.cc', line: 2),
        ],
      );

      final json = launch.toJson();

      expect(launch.ready, isTrue);
      expect(json['readiness'], 'ready');
      expect(json['adapterProtocol'], 'dap');
      expect(json['programPath'], '/workspace/vityo/build/vityo');
      expect(json['cwd'], '/workspace/vityo/build');
      expect(json['debuggerArguments'], <String>['--stdio']);
      expect(json['arguments'], <String>['--smoke']);
      expect(json['environment'], <String, String>{'VITYO_ENV': 'test'});
      expect(json['stopOnEntry'], isTrue);
      expect(json['breakpointCount'], 1);
    },
  );

  test('debug launch contract blocks debugger without launch program', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'lldb-dap',
        kind: ToolchainKind.debugger,
        displayName: 'LLDB DAP',
        executablePath: '/usr/bin/lldb-dap',
        metadata: <String, Object?>{'adapterProtocol': 'dap'},
      ),
      workspaceRoot: '/workspace/vityo',
    );

    expect(launch.ready, isFalse);
    expect(launch.readiness, DebugLaunchReadiness.missingProgram);
    expect(launch.reason, contains('metadata.programPath'));
  });

  test('debug launch contract blocks unsupported adapter protocol', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'custom-debugger',
        kind: ToolchainKind.debugger,
        displayName: 'Custom Debugger',
        executablePath: '/usr/bin/custom-debugger',
        metadata: <String, Object?>{
          'adapterProtocol': 'custom',
          'programPath': '/tmp/app',
        },
      ),
      workspaceRoot: '/workspace/vityo',
    );

    expect(launch.ready, isFalse);
    expect(launch.readiness, DebugLaunchReadiness.unsupportedProtocol);
    expect(launch.reason, contains('unsupported protocol custom'));
  });

  test('debug launch route plan exposes failure navigation actions', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'custom-debugger',
        kind: ToolchainKind.debugger,
        displayName: 'Custom Debugger',
        executablePath: '/usr/bin/custom-debugger',
        metadata: <String, Object?>{
          'adapterProtocol': 'custom',
          'programPath': '/tmp/app',
        },
      ),
      workspaceRoot: '/workspace/vityo',
    );

    final routePlan = launch.toRoutePlan(
      profileId: 'custom-debug',
      target: RuntimeExecutionHandoffTarget.terminalRuntime,
    );

    expect(routePlan.ready, isFalse);
    expect(routePlan.status, DebugLaunchRouteStatus.blocked);
    expect(routePlan.handoff.ready, isFalse);
    expect(
      routePlan.failureNavigationActions.map((action) => action.kind),
      <DebugLaunchFailureNavigationKind>[
        DebugLaunchFailureNavigationKind.selectAdapter,
        DebugLaunchFailureNavigationKind.changeProtocol,
      ],
    );
    expect(
      routePlan.toJson()['failureNavigationActions'],
      isA<List<Object?>>(),
    );
  });

  test(
    'debug launch contract projects launch into runtime task definition',
    () {
      final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
        debugger: const ToolchainDescriptor(
          id: 'lldb-dap',
          kind: ToolchainKind.debugger,
          displayName: 'LLDB DAP',
          executablePath: '/usr/bin/lldb-dap',
          metadata: <String, Object?>{
            'adapterProtocol': 'dap',
            'programPath': 'build/vityo',
            'debugAdapterArguments': <String>['--stdio'],
          },
        ),
        workspaceRoot: '/workspace/vityo',
      );

      final task = launch.toRuntimeTaskDefinition(
        taskId: 'debug.current',
        metadata: const <String, Object?>{'owner': 'debugger'},
      );

      expect(task.id, 'debug.current');
      expect(task.kind, RuntimeTaskKind.debug);
      expect(task.command, '/usr/bin/lldb-dap');
      expect(task.arguments, <String>[
        '--stdio',
        '/workspace/vityo/build/vityo',
      ]);
      expect(task.workingDirectory, '/workspace/vityo');
      expect(task.runnable, isTrue);
      expect(
        (task.metadata['launch']! as Map<String, Object?>)['ready'],
        isTrue,
      );
    },
  );

  test('debug launch contract creates runtime execution handoff', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'lldb-dap',
        kind: ToolchainKind.debugger,
        displayName: 'LLDB DAP',
        executablePath: '/usr/bin/lldb-dap',
        metadata: <String, Object?>{
          'adapterProtocol': 'dap',
          'programPath': 'build/vityo',
          'debugAdapterArguments': <String>['--stdio'],
        },
      ),
      workspaceRoot: '/workspace/vityo',
    );

    final handoff = launch.toRuntimeExecutionHandoff(
      taskId: 'debug.current',
      target: RuntimeExecutionHandoffTarget.terminalRuntime,
    );
    final restored = RuntimeExecutionHandoff.fromJson(handoff.toJson());

    expect(handoff.ready, isTrue);
    expect(handoff.taskId, 'debug.current');
    expect(handoff.target, RuntimeExecutionHandoffTarget.terminalRuntime);
    expect(handoff.command, '/usr/bin/lldb-dap');
    expect(handoff.arguments, <String>[
      '--stdio',
      '/workspace/vityo/build/vityo',
    ]);
    expect(handoff.outputChannelId, 'debug.lldb-dap.console');
    expect(handoff.metadata['adapterProtocol'], 'dap');
    expect(handoff.metadata['debugLaunchReadiness'], 'ready');
    expect(restored.ready, isTrue);
    expect(restored.plan.definition.kind, RuntimeTaskKind.debug);
  });

  test('debug launch handoff preserves blocked readiness', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'lldb-dap',
        kind: ToolchainKind.debugger,
        displayName: 'LLDB DAP',
        executablePath: '/usr/bin/lldb-dap',
        metadata: <String, Object?>{'adapterProtocol': 'dap'},
      ),
      workspaceRoot: '/workspace/vityo',
    );

    final handoff = launch.toRuntimeExecutionHandoff(taskId: 'debug.current');

    expect(handoff.ready, isFalse);
    expect(handoff.status, RuntimeExecutionHandoffStatus.blocked);
    expect(handoff.metadata['debugLaunchReadiness'], 'missing-program');
    expect(handoff.plan.message, contains('metadata.programPath'));
  });

  test('debug launch profile set selects default and round trips JSON', () {
    final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
      debugger: const ToolchainDescriptor(
        id: 'styio-lldb-dap',
        kind: ToolchainKind.debugger,
        displayName: 'Styio LLDB DAP',
        executablePath: '/usr/bin/lldb-dap',
        metadata: <String, Object?>{
          'adapterProtocol': 'dap',
          'programPath': 'build/styio',
          'debuggerArguments': <String>['--stdio'],
        },
      ),
      workspaceRoot: '/workspace/vityo',
    );
    final profile = DebugLaunchProfile.fromConfiguration(
      id: 'debug-styio',
      displayName: 'Debug Styio',
      configuration: launch,
      isDefault: true,
      preLaunchTaskId: 'build-styio',
      metadata: const <String, Object?>{'source': 'workspace'},
    );
    final set = const DebugLaunchConfigurationSet(
      workspaceId: 'demo',
    ).upsertProfile(profile);
    final restored = DebugLaunchConfigurationSet.fromJson(set.toJson());

    expect(restored.workspaceId, 'demo');
    expect(restored.selectedProfile!.id, 'debug-styio');
    expect(restored.selectedProfile!.configuration.ready, isTrue);
    expect(restored.selectedProfile!.configuration.debuggerArguments, <String>[
      '--stdio',
    ]);
    expect(restored.selectedProfile!.preLaunchTaskId, 'build-styio');
    expect(restored.hasRunnableProfile, isTrue);
    expect(restored.toJson()['selectedProfileReady'], isTrue);
  });

  test(
    'debug launch configuration store persists workspace profiles',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_debug_launch_store_test_',
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
      final store = DebugLaunchConfigurationStore.fromDataStore(
        dataStore: dataStore,
      );
      final launch = DebugLaunchConfiguration.fromToolchainDescriptor(
        debugger: const ToolchainDescriptor(
          id: 'lldb-dap',
          kind: ToolchainKind.debugger,
          displayName: 'LLDB DAP',
          executablePath: '/usr/bin/lldb-dap',
          metadata: <String, Object?>{
            'adapterProtocol': 'dap',
            'programPath': 'build/vityo',
          },
        ),
        workspaceRoot: '/workspace/vityo',
      );
      final set = const DebugLaunchConfigurationSet(workspaceId: 'demo')
          .upsertProfile(
            DebugLaunchProfile.fromConfiguration(
              id: 'default',
              displayName: 'Debug current workspace',
              configuration: launch,
              isDefault: true,
            ),
          );

      await store.saveConfigurationSet(set);
      final restored = await store.loadConfigurationSet(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.selectedProfile!.id, 'default');
      expect(
        restored.selectedProfile!.configuration.programPath,
        endsWith('vityo'),
      );
      expect(restored.updatedAt, isNotNull);

      final deleted = await store.deleteConfigurationSet(workspaceId: 'demo');
      expect(deleted, isTrue);
      expect(
        (await store.loadConfigurationSet(workspaceId: 'demo')).profiles,
        isEmpty,
      );
    },
  );
}
