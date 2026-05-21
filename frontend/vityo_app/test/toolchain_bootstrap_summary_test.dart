import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('toolchain manager exposes bootstrap summary actions', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_bootstrap_summary_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final configurationStore = ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: InMemoryCredentialDataStore(),
    );
    final platformManagers = await createPlatformManagerBundle(
      platformContext: PlatformContextSnapshot.compose(
        targetId: 'toolchain-bootstrap',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-bootstrap',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-bootstrap',
          defaultShellPath: '/bin/sh',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-bootstrap',
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      ),
    );
    final manager = ToolchainManager(
      configurationStore: ToolchainConfigurationStore(
        configurationStore: configurationStore,
      ),
      platformManagers: platformManagers,
      workspaceId: 'demo',
    );

    await manager.registerToolchain(
      const ToolchainDescriptor(
        id: 'styio-service',
        kind: ToolchainKind.languageService,
        displayName: 'Styio Language Service',
        executablePath: '/usr/bin/styio',
        metadata: <String, Object?>{'language': 'styio'},
      ),
      activate: true,
    );
    await manager.registerToolchain(
      const ToolchainDescriptor(
        id: 'styio-compiler',
        kind: ToolchainKind.compiler,
        displayName: 'Styio Compiler',
        executablePath: '/usr/bin/styio',
        metadata: <String, Object?>{'toolFamily': 'styio'},
      ),
    );

    final summary = await manager.bootstrapSummary(
      kind: ToolchainKind.compiler,
      requiredStyioRoles: const <StyioToolchainRole>[
        StyioToolchainRole.languageService,
        StyioToolchainRole.compiler,
      ],
    );
    final executionPlan = summary.executionPlan();
    final json = summary.toJson();

    expect(summary.ready, isFalse);
    expect(summary.managerReport.ready, isTrue);
    expect(
      summary.styioLifecycle.state,
      StyioToolchainLifecycleState.selectable,
    );
    expect(summary.settingsActionIds, contains('select-styio-compiler'));
    expect(
      summary.projectBootstrapActionIds,
      contains('open-toolchain-settings'),
    );
    expect(summary.agentContext['toolchainReady'], isFalse);
    expect(executionPlan.canExecute, isTrue);
    expect(executionPlan.surfaceCounts['settings'], greaterThanOrEqualTo(1));
    expect(
      executionPlan.steps.map((step) => step.actionId),
      contains('select-styio-compiler'),
    );
    expect(
      (json['executionPlan']! as Map<String, Object?>)['canExecute'],
      isTrue,
    );
    expect(json['settingsActionIds'], contains('select-styio-compiler'));
    expect(
      (json['agentContext']! as Map<String, Object?>)['activeToolchains'],
      isNotEmpty,
    );
  });
}
