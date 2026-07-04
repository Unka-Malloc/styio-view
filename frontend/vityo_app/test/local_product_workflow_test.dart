import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';
import 'package:vityo_app/src/app/state/shell_model.dart';
import 'package:vityo_app/src/app/state/workspace_controller.dart';
import 'package:vityo_app/src/app/state/workspace_document_store_types.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/execution_route_summary.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/native_module_loader.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  final productGateEnabled =
      Platform.environment['VITYO_PRODUCT_GATE'] == '1';
  final missingEnv = <String>[
    for (final name in const <String>[
      'VITYO_PRODUCT_WORKSPACE_ROOT',
      'VITYO_PRODUCT_MANIFEST_PATH',
      'VITYO_PAFIO_BIN',
      'VITYO_PRODUCT_STYIO_BIN',
      'VITYO_PRODUCT_STYIO_ALT_BIN',
    ])
      if (_env(name) == null) name,
  ];
  final workspaceMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_PRODUCT_WORKSPACE2_ROOT',
      'VITYO_PRODUCT_MANIFEST2_PATH',
      'VITYO_PAFIO_BIN',
      'VITYO_PRODUCT_STYIO_BIN',
    ])
      if (_env(name) == null) name,
  ];
  final failureMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_PRODUCT_WORKSPACE3_ROOT',
      'VITYO_PRODUCT_MANIFEST3_PATH',
      'VITYO_PRODUCT_WORKSPACE_ROOT',
      'VITYO_PRODUCT_MANIFEST_PATH',
      'VITYO_PAFIO_BIN',
      'VITYO_PRODUCT_STYIO_BIN',
    ])
      if (_env(name) == null) name,
  ];
  final registryMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_PRODUCT_WORKSPACE4_ROOT',
      'VITYO_PRODUCT_MANIFEST4_PATH',
      'VITYO_PRODUCT_WORKSPACE5_ROOT',
      'VITYO_PRODUCT_MANIFEST5_PATH',
      'VITYO_PRODUCT_WORKSPACE6_ROOT',
      'VITYO_PRODUCT_MANIFEST6_PATH',
      'VITYO_PRODUCT_REGISTRY_ROOT',
      'VITYO_PAFIO_BIN',
      'VITYO_PRODUCT_STYIO_BIN',
    ])
      if (_env(name) == null) name,
  ];
  final offlineMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_PAFIO_BIN',
      'VITYO_PRODUCT_STYIO_BIN',
      'PAFIO_HOME',
    ])
      if (_env(name) == null) name,
  ];

  test(
    'desktop local product workflow supports environment, dependency, execution, and preflight lanes',
    () async {
      final workspaceRoot = _env('VITYO_PRODUCT_WORKSPACE_ROOT')!;
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final alternateStyioBinaryPath = _env(
        'VITYO_PRODUCT_STYIO_ALT_BIN',
      )!;
      final previousCurrentDirectory = Directory.current;
      Directory.current = workspaceRoot;
      try {
        final shell = await _createLocalShell();
        expect(
          shell.workspaceController.activeProject.hasHostedWorkspace,
          isFalse,
          reason: 'Desktop local workflow should stay on the CLI-owned route.',
        );
        expect(
          shell.blockedReasonForCommand(AppCommandId.fetchDependencies),
          isNull,
          reason: 'Desktop local workflow should not block dependency fetch.',
        );
        expect(
          shell.blockedReasonForCommand(AppCommandId.preparePublish),
          isNull,
          reason:
              'Desktop local workflow should not block deployment preflight.',
        );

        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(
          install.succeeded,
          isTrue,
          reason:
              'Desktop local workflow should install the primary compiler through local pafio.',
        );
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        expect(installedToolchains, isNotEmpty);
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );

        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);

        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);
        _expectActiveCompilerVersion(
          shell,
          '0.0.1',
          reason:
              'Desktop local workflow should resolve the primary compiler after pin.',
        );

        final installAlternate = await shell.installManagedCompiler(
          styioBinaryPath: alternateStyioBinaryPath,
        );
        expect(
          installAlternate.succeeded,
          isTrue,
          reason:
              'Desktop local workflow should install the alternate compiler identity.',
        );
        final refreshedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        expect(
          refreshedToolchains.any(
            (toolchain) => toolchain.compilerVersion == '0.0.2',
          ),
          isTrue,
        );
        final alternateCompiler = refreshedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.2',
        );

        final useAlternate = await shell.useManagedCompiler(
          compilerVersion: alternateCompiler.compilerVersion,
          channel: alternateCompiler.channel,
        );
        expect(useAlternate.succeeded, isTrue);
        final pinAlternate = await shell.pinManagedCompiler(
          compilerVersion: alternateCompiler.compilerVersion,
          channel: alternateCompiler.channel,
        );
        expect(pinAlternate.succeeded, isTrue);
        _expectActiveCompilerVersion(
          shell,
          '0.0.2',
          reason:
              'Desktop local workflow should switch to the alternate compiler.',
        );

        final usePrimaryAgain = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(usePrimaryAgain.succeeded, isTrue);
        final pinPrimaryAgain = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pinPrimaryAgain.succeeded, isTrue);
        _expectActiveCompilerVersion(
          shell,
          '0.0.1',
          reason:
              'Desktop local workflow should switch back to the primary compiler before execution.',
        );

        final fetch = await shell.fetchDependencies();
        expect(fetch.succeeded, isTrue);

        final vendor = await shell.vendorDependencies();
        expect(vendor.succeeded, isTrue);

        final pack = await shell.packProject();
        expect(pack.succeeded, isTrue);
        _expectArchivePresent(
          pack,
          reason:
              'Desktop local workflow should materialize a real source package archive before publish preflight.',
        );

        await _openTarget(shell, ProjectTargetKind.bin);
        await shell.executeCommand(AppCommandId.run);
        expect(shell.lastExecutionSession, isNotNull);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
        );
        expect(shell.lastExecutionSession?.kind, 'run');
        expect(shell.lastRuntimeEvents, isNotEmpty);

        await _openTarget(shell, ProjectTargetKind.test);
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
        );
        expect(shell.lastExecutionSession?.kind, 'test');
        expect(shell.lastRuntimeEvents, isNotEmpty);

        final preflight = await shell.preparePublish();
        expect(preflight.succeeded, isTrue);
        _expectArchivePresent(
          preflight,
          reason:
              'Desktop local workflow should keep the publish preflight archive on disk.',
        );

        final routeSummary = summarizeExecutionRoute(
          platformTarget: PlatformTarget.macos,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSummary.previewOnly, isFalse);
        expect(routeSummary.primaryAdapterKind, AdapterKind.cli);
        final routeSelection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.macos,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSelection.routeKind, BackendExecutionRouteKind.localCli);
        expect(routeSelection.allowed, isTrue);
        expect(routeSelection.previewOnly, isFalse);
        _emitLocalScenarioReport(
          scenario: 'desktop-local-core-workflow',
          workspaceKind: 'single-package',
          toolchainResult: 'switch-and-return-succeeded',
          dependencyResult: 'fetch+vendor-succeeded',
          executionResult: 'run+test-succeeded',
          deploymentResult: 'pack+preflight-succeeded',
          artifactPresence: _artifactPresence(
            archive: true,
            diagnostics: false,
            runtimeEvents: shell.lastRuntimeEvents.isNotEmpty,
          ),
        );
      } finally {
        Directory.current = previousCurrentDirectory;
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the local product workflow test.'
        : missingEnv.isNotEmpty
        ? 'Missing required local product gate env: ${missingEnv.join(', ')}'
        : false,
  );

  test(
    'desktop local product workflow supports workspace package routing and publish ambiguity handling',
    () async {
      final workspaceRoot = _env('VITYO_PRODUCT_WORKSPACE2_ROOT')!;
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final previousCurrentDirectory = Directory.current;
      Directory.current = workspaceRoot;
      try {
        final shell = await _createLocalShell();
        expect(
          shell.workspaceController.activeProject.hasHostedWorkspace,
          isFalse,
        );
        expect(shell.workspaceController.activeProject.packages.length, 2);
        expect(
          shell
              .workspaceController
              .activeProject
              .packageDistribution
              ?.publishablePackages,
          2,
        );

        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );

        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);
        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);

        final publishBlockedReason = shell.blockedReasonForCommand(
          AppCommandId.preparePublish,
        );
        expect(
          publishBlockedReason,
          contains('Multiple publish-ready packages are available'),
        );

        final blockedPreflight = await shell.preparePublish();
        expect(blockedPreflight.status, DeploymentCommandStatus.blocked);
        expect(
          blockedPreflight.statusMessage,
          contains('Multiple publish-ready packages are available'),
        );

        final fetch = await shell.fetchDependencies();
        expect(fetch.succeeded, isTrue);
        final vendor = await shell.vendorDependencies();
        expect(vendor.succeeded, isTrue);

        await _openPackageTarget(
          shell,
          packageName: 'acme/tool',
          targetKind: ProjectTargetKind.bin,
        );
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
        );
        expect(shell.lastExecutionSession?.kind, 'run');

        await _openPackageTarget(
          shell,
          packageName: 'acme/tool',
          targetKind: ProjectTargetKind.test,
        );
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
        );
        expect(shell.lastExecutionSession?.kind, 'test');

        final explicitPack = await shell.packProject(packageName: 'acme/tool');
        expect(explicitPack.succeeded, isTrue);
        _expectArchivePresent(
          explicitPack,
          reason:
              'Desktop local multi-package workflow should materialize a package-specific archive for the selected package.',
        );

        final explicitPreflight = await shell.preparePublish(
          packageName: 'acme/tool',
        );
        expect(explicitPreflight.succeeded, isTrue);
        _expectArchivePresent(
          explicitPreflight,
          reason:
              'Desktop local multi-package workflow should keep the explicit package preflight archive on disk.',
        );

        final routeSummary = summarizeExecutionRoute(
          platformTarget: PlatformTarget.macos,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSummary.previewOnly, isFalse);
        expect(routeSummary.primaryAdapterKind, AdapterKind.cli);
        final routeSelection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.macos,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSelection.routeKind, BackendExecutionRouteKind.localCli);
        expect(routeSelection.allowed, isTrue);
        expect(routeSelection.previewOnly, isFalse);
        _emitLocalScenarioReport(
          scenario: 'desktop-local-multi-package-workflow',
          workspaceKind: 'multi-package',
          toolchainResult: 'pin-succeeded',
          dependencyResult: 'fetch+vendor-succeeded',
          executionResult: 'run+test-succeeded',
          deploymentResult: 'preflight-blocked-then-explicit-package-succeeded',
          artifactPresence: _artifactPresence(
            archive: true,
            diagnostics: false,
            runtimeEvents: shell.lastRuntimeEvents.isNotEmpty,
          ),
          failureKinds: const <String>['package_ambiguity'],
        );
      } finally {
        Directory.current = previousCurrentDirectory;
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the local product workflow test.'
        : workspaceMissingEnv.isNotEmpty
        ? 'Missing required local workspace product gate env: ${workspaceMissingEnv.join(', ')}'
        : false,
  );

  test(
    'desktop local product workflow surfaces compiler, dependency, and deployment failures through the product lanes',
    () async {
      final singleWorkspaceRoot = _env('VITYO_PRODUCT_WORKSPACE_ROOT')!;
      final failingWorkspaceRoot = _env('VITYO_PRODUCT_WORKSPACE3_ROOT')!;
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      var compileFailureHadDiagnostics = false;
      var compileFailureHadRuntimeEvents = false;

      await _runInWorkspace(singleWorkspaceRoot, () async {
        final shell = await _createLocalShell();
        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );
        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);
        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);

        await _openTarget(shell, ProjectTargetKind.bin);
        await _loadActiveDocumentText(shell, '>_("broken"\n');
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.failed,
        );
        expect(shell.lastExecutionSession?.diagnostics, isNotEmpty);
        expect(
          shell.lastRuntimeEvents.map((event) => event.eventKind),
          contains('compile.failed'),
        );
        compileFailureHadDiagnostics =
            shell.lastExecutionSession?.diagnostics.isNotEmpty == true;
        compileFailureHadRuntimeEvents = shell.lastRuntimeEvents.isNotEmpty;
      });

      await _runInWorkspace(failingWorkspaceRoot, () async {
        final shell = await _createLocalShell();
        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );
        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);
        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);

        final fetch = await shell.fetchDependencies();
        expect(fetch.status, DependencySourceCommandStatus.failed);
        expect(fetch.statusMessage, isNotEmpty);
        expect(fetch.errorPayload, isNotNull);
        expect(
          shell.lastDependencySourceCommand?.status,
          DependencySourceCommandStatus.failed,
        );

        final preflight = await shell.preparePublish(
          packageName: 'acme/broken-fetch',
        );
        expect(preflight.status, DeploymentCommandStatus.failed);
        expect(preflight.statusMessage, isNotEmpty);
        expect(preflight.errorPayload, isNotNull);
        expect(
          shell.lastDeploymentCommand?.status,
          DeploymentCommandStatus.failed,
        );
      });
      _emitLocalScenarioReport(
        scenario: 'desktop-local-failure-matrix',
        workspaceKind: 'single-package',
        toolchainResult: 'pin-succeeded',
        dependencyResult: 'failed',
        executionResult: 'compile-failed',
        deploymentResult: 'preflight-failed',
        artifactPresence: _artifactPresence(
          archive: false,
          diagnostics: compileFailureHadDiagnostics,
          runtimeEvents: compileFailureHadRuntimeEvents,
        ),
        failureKinds: const <String>[
          'compile_failure',
          'dependency_fetch_failure',
          'publish_preflight_failure',
        ],
      );
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the local product workflow test.'
        : failureMissingEnv.isNotEmpty
        ? 'Missing required local failure-path env: ${failureMissingEnv.join(', ')}'
        : false,
  );

  test(
    'desktop local product workflow publishes to a local registry and consumes the published package',
    () async {
      final publishWorkspaceRoot = _env('VITYO_PRODUCT_WORKSPACE4_ROOT')!;
      final consumeWorkspaceRoot = _env('VITYO_PRODUCT_WORKSPACE5_ROOT')!;
      final failingConsumeWorkspaceRoot = _env(
        'VITYO_PRODUCT_WORKSPACE6_ROOT',
      )!;
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final registryRoot = _env('VITYO_PRODUCT_REGISTRY_ROOT')!;

      await _runInWorkspace(publishWorkspaceRoot, () async {
        final shell = await _createLocalShell();
        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );
        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);
        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);

        final reopenedBuildShell = await _createLocalShell();
        _expectActiveCompilerVersion(
          reopenedBuildShell,
          '0.0.1',
          reason:
              'Desktop local registry workflow should persist the pinned compiler after reopening the library workspace.',
        );
        await _openTarget(reopenedBuildShell, ProjectTargetKind.lib);
        await reopenedBuildShell.executeCommand(AppCommandId.run);
        expect(
          reopenedBuildShell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
        );
        expect(reopenedBuildShell.lastExecutionSession?.kind, 'build');
        expect(reopenedBuildShell.lastRuntimeEvents, isNotEmpty);

        final publish = await shell.publishToRegistry(
          registryRoot: registryRoot,
          packageName: 'acme/registry-feed',
        );
        expect(publish.succeeded, isTrue);
        expect(publish.payload?['registry_root'], registryRoot);
        _expectArchivePresent(
          publish,
          reason:
              'Desktop local registry publish should keep the archive used for distribution on disk.',
        );

        final republish = await shell.publishToRegistry(
          registryRoot: registryRoot,
          packageName: 'acme/registry-feed',
        );
        expect(republish.status, DeploymentCommandStatus.failed);
        expect(republish.statusMessage, isNotEmpty);
        expect(republish.errorPayload, isNotNull);
        expect(
          shell.lastDeploymentCommand?.status,
          DeploymentCommandStatus.failed,
        );
      });

      await _runInWorkspace(consumeWorkspaceRoot, () async {
        final shell = await _createLocalShell();
        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );
        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);
        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);

        final fetch = await shell.fetchDependencies();
        expect(fetch.succeeded, isTrue);
        final acceptedRegistryRoots = <String>{
          registryRoot,
          Directory(registryRoot).absolute.uri.toString(),
        };
        expect(
          shell.workspaceController.activeProject.dependencies.any(
                (dependency) =>
                    dependency.packageIdentity == 'acme/registry-feed' &&
                    dependency.registryRoot != null &&
                    acceptedRegistryRoots.contains(dependency.registryRoot),
              ) ||
              shell
                      .workspaceController
                      .activeProject
                      .packageDistribution
                      ?.registrySources
                      .any(
                        (registry) =>
                            acceptedRegistryRoots.contains(
                              registry.registryRoot,
                            ) &&
                            registry.packages.contains('acme/registry-client'),
                      ) ==
                  true ||
              (shell
                          .workspaceController
                          .activeProject
                          .sourceState
                          ?.declaredRegistryDependencies ??
                      0) >
                  0,
          isTrue,
        );

        await _openTarget(shell, ProjectTargetKind.bin);
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
        );

        final routeSummary = summarizeExecutionRoute(
          platformTarget: PlatformTarget.macos,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSummary.previewOnly, isFalse);
        expect(routeSummary.primaryAdapterKind, AdapterKind.cli);
      });

      await _runInWorkspace(failingConsumeWorkspaceRoot, () async {
        final shell = await _createLocalShell();
        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );
        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue);
        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue);

        final fetch = await shell.fetchDependencies();
        expect(fetch.status, DependencySourceCommandStatus.failed);
        expect(fetch.statusMessage, isNotEmpty);
        expect(fetch.errorPayload, isNotNull);
        expect(
          shell.lastDependencySourceCommand?.status,
          DependencySourceCommandStatus.failed,
        );
      });
      _emitLocalScenarioReport(
        scenario: 'desktop-local-registry-distribution',
        workspaceKind: 'single-package-library',
        toolchainResult: 'pin-persists-after-reopen',
        dependencyResult: 'registry-fetch-succeeded+missing-version-failed',
        executionResult: 'build+run-succeeded',
        deploymentResult: 'publish-succeeded+republish-failed',
        artifactPresence: _artifactPresence(
          archive: true,
          diagnostics: false,
          runtimeEvents: true,
        ),
        failureKinds: const <String>[
          'republish_conflict',
          'registry_missing_version',
        ],
      );
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the local product workflow test.'
        : registryMissingEnv.isNotEmpty
        ? 'Missing required local registry-path env: ${registryMissingEnv.join(', ')}'
        : false,
  );

  test(
    'desktop local product workflow stays runnable from vendored sources after registry loss in offline mode',
    () async {
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final pafioHome = _env('PAFIO_HOME')!;
      final workspaceRoot = await _createOfflineVendoredWorkspace();

      try {
        await _runInWorkspace(workspaceRoot.path, () async {
          final shell = await _createLocalShell();
          final install = await shell.installManagedCompiler(
            styioBinaryPath: styioBinaryPath,
          );
          expect(install.succeeded, isTrue);
          final installedToolchains =
              shell
                  .workspaceController
                  .activeProject
                  .toolchainEnvironment
                  ?.managedToolchains
                  .installed ??
              const <ManagedToolchainInstallSnapshot>[];
          final primaryCompiler = installedToolchains.firstWhere(
            (toolchain) => toolchain.compilerVersion == '0.0.1',
            orElse: () => installedToolchains.first,
          );
          final use = await shell.useManagedCompiler(
            compilerVersion: primaryCompiler.compilerVersion,
            channel: primaryCompiler.channel,
          );
          expect(use.succeeded, isTrue);
          final pin = await shell.pinManagedCompiler(
            compilerVersion: primaryCompiler.compilerVersion,
            channel: primaryCompiler.channel,
          );
          expect(pin.succeeded, isTrue);

          final fetch = await shell.fetchDependencies();
          expect(fetch.succeeded, isTrue);

          final vendor = await shell.vendorDependencies();
          expect(vendor.succeeded, isTrue);
          final vendorRoot = vendor.payload?['vendor_root'] as String?;
          final metadataPath = vendor.payload?['metadata_path'] as String?;
          expect(vendorRoot, isNotNull);
          expect(vendorRoot, isNotEmpty);
          expect(Directory(vendorRoot!).existsSync(), isTrue);
          expect(metadataPath, isNotNull);
          expect(metadataPath, isNotEmpty);
          expect(File(metadataPath!).existsSync(), isTrue);

          final pafioHomeDirectory = Directory(pafioHome);
          if (pafioHomeDirectory.existsSync()) {
            pafioHomeDirectory.deleteSync(recursive: true);
          }

          final offlineFetch = await shell.fetchDependencies(offline: true);
          expect(offlineFetch.succeeded, isTrue);
          expect(
            shell.lastDependencySourceCommand?.status,
            DependencySourceCommandStatus.succeeded,
          );

          final reinstall = await shell.installManagedCompiler(
            styioBinaryPath: styioBinaryPath,
          );
          expect(reinstall.succeeded, isTrue);
          final refreshedToolchains =
              shell
                  .workspaceController
                  .activeProject
                  .toolchainEnvironment
                  ?.managedToolchains
                  .installed ??
              const <ManagedToolchainInstallSnapshot>[];
          final refreshedPrimaryCompiler = refreshedToolchains.firstWhere(
            (toolchain) => toolchain.compilerVersion == '0.0.1',
            orElse: () => refreshedToolchains.first,
          );
          final reuse = await shell.useManagedCompiler(
            compilerVersion: refreshedPrimaryCompiler.compilerVersion,
            channel: refreshedPrimaryCompiler.channel,
          );
          expect(reuse.succeeded, isTrue);
          final repin = await shell.pinManagedCompiler(
            compilerVersion: refreshedPrimaryCompiler.compilerVersion,
            channel: refreshedPrimaryCompiler.channel,
          );
          expect(repin.succeeded, isTrue);

          final reopenedShell = await _createLocalShell();
          await _openTarget(reopenedShell, ProjectTargetKind.bin);
          await reopenedShell.executeCommand(AppCommandId.run);
          expect(
            reopenedShell.lastExecutionSession?.status,
            ExecutionSessionStatus.succeeded,
          );
          expect(reopenedShell.lastExecutionSession?.kind, 'run');

          final routeSummary = summarizeExecutionRoute(
            platformTarget: PlatformTarget.macos,
            projectGraph: reopenedShell.workspaceController.activeProject,
            adapterCapabilities: reopenedShell.adapterCapabilities,
          );
          expect(routeSummary.previewOnly, isFalse);
          expect(routeSummary.primaryAdapterKind, AdapterKind.cli);
          _emitLocalScenarioReport(
            scenario: 'desktop-local-offline-vendored-recovery',
            workspaceKind: 'single-package',
            toolchainResult: 'install+reinstall+repin-succeeded',
            dependencyResult: 'fetch+vendor+offline-fetch-succeeded',
            executionResult: 'run-succeeded-after-reopen',
            deploymentResult: 'not-exercised',
            artifactPresence: _artifactPresence(
              archive: false,
              diagnostics: false,
              runtimeEvents: reopenedShell.lastRuntimeEvents.isNotEmpty,
            ),
          );
        });
      } finally {
        if (workspaceRoot.existsSync()) {
          workspaceRoot.deleteSync(recursive: true);
        }
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the local product workflow test.'
        : offlineMissingEnv.isNotEmpty
        ? 'Missing required local vendored/offline env: ${offlineMissingEnv.join(', ')}'
        : false,
  );
}

Future<ShellModel> _createLocalShell() async {
  final projectGraphAdapter = await createProjectGraphAdapter(
    platformTarget: PlatformTarget.macos,
  );
  final projectGraph = await projectGraphAdapter.loadProjectGraph();
  final executionAdapter = await createExecutionAdapter(
    platformTarget: PlatformTarget.macos,
    projectGraph: projectGraph,
  );
  final runtimeEventAdapter = createRuntimeEventAdapter(
    platformTarget: PlatformTarget.macos,
  );
  final dependencySourceAdapter = await createDependencySourceAdapter(
    platformTarget: PlatformTarget.macos,
  );
  final deploymentAdapter = await createDeploymentAdapter(
    platformTarget: PlatformTarget.macos,
  );
  final toolchainManagementAdapter = await createToolchainManagementAdapter(
    platformTarget: PlatformTarget.macos,
  );
  final seededDocuments = <String, DocumentState>{};
  for (final path in projectGraph.editorFiles) {
    final file = File(path);
    final text = await file.exists()
        ? await file.readAsString()
        : EditorSessionController.seedDocumentForPath(path).text;
    seededDocuments[path] = DocumentState(
      documentId: path,
      text: text,
      revision: 0,
    );
  }

  final workspaceController = WorkspaceController(
    projectSnapshot: projectGraph,
  );
  final workspaceDocumentStore = InMemoryWorkspaceDocumentStore(
    seededDocuments: seededDocuments,
  );
  final editorController = EditorSessionController(
    initialDocument:
        seededDocuments[workspaceController.activeFilePath] ??
        EditorSessionController.seedDocumentForPath(
          workspaceController.activeFilePath,
        ),
    languageService: const SimpleStyioLanguageService(),
  );

  return ShellModel(
    platformTarget: PlatformTarget.macos,
    supplementalAdapterCapabilities:
        normalizeCapabilitySnapshots(<AdapterCapabilitySnapshot>[
          buildFfiAdapterCapability(
            visible: true,
            executionSlotVisible: true,
            detail: 'Desktop local workflow keeps the native bridge available.',
          ),
          buildCloudAdapterCapability(
            supportsCloudExecution: false,
            supportsHostedProjectGraph: false,
            detail: 'Desktop local workflow stays on the CLI-owned route.',
          ),
        ]),
    projectGraphAdapter: projectGraphAdapter,
    workspaceController: workspaceController,
    workspaceDocumentStore: workspaceDocumentStore,
    moduleRegistry: ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: const [],
    ),
    nativeModuleLoader: const NoopNativeModuleLoader(
      platformTarget: PlatformTarget.macos,
    ),
    editorController: editorController,
    executionAdapter: executionAdapter,
    executionAdapterFactory: (ProjectGraphSnapshot refreshedProjectGraph) {
      return createExecutionAdapter(
        platformTarget: PlatformTarget.macos,
        projectGraph: refreshedProjectGraph,
      );
    },
    runtimeEventAdapter: runtimeEventAdapter,
    dependencySourceAdapter: dependencySourceAdapter,
    deploymentAdapter: deploymentAdapter,
    toolchainManagementAdapter: toolchainManagementAdapter,
  );
}

Future<void> _openTarget(ShellModel shell, ProjectTargetKind targetKind) async {
  final target = shell.workspaceController.targets.firstWhere(
    (candidate) => candidate.kind == targetKind,
  );
  shell.workspaceController.openTarget(target);
  await _settleAsync();
  final file = File(target.filePath);
  final text = await file.exists()
      ? await file.readAsString()
      : EditorSessionController.seedDocumentForPath(target.filePath).text;
  shell.editorController.loadDocument(
    DocumentState(documentId: target.filePath, text: text, revision: 0),
  );
  await _settleAsync();
}

Future<void> _loadActiveDocumentText(ShellModel shell, String text) async {
  final activePath = shell.workspaceController.activeFilePath;
  shell.editorController.loadDocument(
    DocumentState(
      documentId: activePath,
      text: text,
      revision: shell.editorController.document.revision + 1,
    ),
  );
  await _settleAsync();
}

Future<void> _openPackageTarget(
  ShellModel shell, {
  required String packageName,
  required ProjectTargetKind targetKind,
}) async {
  final target = shell.workspaceController.targets.firstWhere(
    (candidate) =>
        candidate.packageName == packageName && candidate.kind == targetKind,
  );
  await _openResolvedTarget(shell, target);
}

Future<void> _openResolvedTarget(
  ShellModel shell,
  ProjectTargetDescriptor target,
) async {
  shell.workspaceController.openTarget(target);
  await _settleAsync();
  final file = File(target.filePath);
  final text = await file.exists()
      ? await file.readAsString()
      : EditorSessionController.seedDocumentForPath(target.filePath).text;
  shell.editorController.loadDocument(
    DocumentState(documentId: target.filePath, text: text, revision: 0),
  );
  await _settleAsync();
}

Future<void> _runInWorkspace(
  String workspaceRoot,
  Future<void> Function() action,
) async {
  final previousCurrentDirectory = Directory.current;
  Directory.current = workspaceRoot;
  try {
    await action();
  } finally {
    Directory.current = previousCurrentDirectory;
  }
}

Future<void> _settleAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<Directory> _createOfflineVendoredWorkspace() async {
  final workspaceRoot = await Directory.systemTemp.createTemp(
    'vityo_local_offline_vendored_',
  );
  final gitRepoRoot = Directory(
    '${workspaceRoot.path}${Platform.pathSeparator}remote-feed',
  );
  final rev = _createWorkspaceGitRepo(gitRepoRoot);
  final manifestPath = File(
    '${workspaceRoot.path}${Platform.pathSeparator}pafio.toml',
  );
  final sourcePath = File(
    '${workspaceRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
  );
  sourcePath.parent.createSync(recursive: true);
  manifestPath.writeAsStringSync(
    '[pafio]\n'
    'manifest-version = 1\n\n'
    '[package]\n'
    'name = "acme/app"\n'
    'version = "0.1.0"\n'
    'edition = "2026"\n'
    'publish = false\n\n'
    '[toolchain]\n'
    'channel = "stable"\n'
    'implicit-std = true\n\n'
    '[[bin]]\n'
    'name = "app"\n'
    'path = "src/main.styio"\n\n'
    '[dependencies]\n'
    'feed = { package = "acme/feed", git = "${gitRepoRoot.absolute.path}", rev = "$rev" }\n',
  );
  sourcePath.writeAsStringSync('>_("app")\n');
  return workspaceRoot;
}

String _createWorkspaceGitRepo(Directory repoRoot) {
  File('${repoRoot.path}${Platform.pathSeparator}pafio.toml')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '[pafio]\n'
      'manifest-version = 1\n\n'
      '[workspace]\n'
      'members = ["packages/feed", "packages/util"]\n'
      'resolver = "1"\n',
    );
  File(
      '${repoRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}feed${Platform.pathSeparator}pafio.toml',
    )
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '[pafio]\n'
      'manifest-version = 1\n\n'
      '[package]\n'
      'name = "acme/feed"\n'
      'version = "1.2.0"\n'
      'edition = "2026"\n\n'
      '[toolchain]\n'
      'channel = "stable"\n'
      'implicit-std = true\n\n'
      '[lib]\n'
      'path = "src/lib.styio"\n\n'
      '[dependencies]\n'
      'util = { package = "acme/util", path = "../util" }\n',
    );
  File(
      '${repoRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}feed${Platform.pathSeparator}src${Platform.pathSeparator}lib.styio',
    )
    ..createSync(recursive: true)
    ..writeAsStringSync('// feed fixture\n');
  File(
      '${repoRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}util${Platform.pathSeparator}pafio.toml',
    )
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '[pafio]\n'
      'manifest-version = 1\n\n'
      '[package]\n'
      'name = "acme/util"\n'
      'version = "0.9.0"\n'
      'edition = "2026"\n\n'
      '[toolchain]\n'
      'channel = "stable"\n'
      'implicit-std = true\n\n'
      '[lib]\n'
      'path = "src/lib.styio"\n',
    );
  File(
      '${repoRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}util${Platform.pathSeparator}src${Platform.pathSeparator}lib.styio',
    )
    ..createSync(recursive: true)
    ..writeAsStringSync('// util fixture\n');

  _runGit(repoRoot, <String>['init', '--initial-branch=main']);
  _runGit(repoRoot, <String>[
    '-c',
    'user.email=Vityo-test@example.com',
    '-c',
    'user.name=Vityo-test',
    'add',
    '.',
  ]);
  _runGit(repoRoot, <String>[
    '-c',
    'user.email=Vityo-test@example.com',
    '-c',
    'user.name=Vityo-test',
    'commit',
    '--quiet',
    '-m',
    'initial',
  ]);
  return _runGit(repoRoot, <String>['rev-parse', 'HEAD']);
}

String _runGit(Directory repoRoot, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: repoRoot.path);
  expect(
    result.exitCode,
    0,
    reason:
        'git ${args.join(' ')} should succeed for the local vendored/offline fixture.',
  );
  return '${result.stdout}'.trim();
}

String? _env(String name) {
  final value = Platform.environment[name];
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

void _emitLocalScenarioReport({
  required String scenario,
  required String workspaceKind,
  required String toolchainResult,
  required String dependencyResult,
  required String executionResult,
  required String deploymentResult,
  required Map<String, Object?> artifactPresence,
  List<String> failureKinds = const <String>[],
}) {
  _emitScenarioReport(<String, Object?>{
    'scenario': scenario,
    'platform': 'desktop',
    'route': 'local',
    'workspace_kind': workspaceKind,
    'toolchain_result': toolchainResult,
    'dependency_result': dependencyResult,
    'execution_result': executionResult,
    'deployment_result': deploymentResult,
    'artifact_presence': artifactPresence,
    'failure_kinds': failureKinds,
  });
}

void _emitScenarioReport(Map<String, Object?> report) {
  developer.log(
    'VITYO_PRODUCT_REPORT ${jsonEncode(report)}',
    name: 'styio.view.product_gate',
  );
}

Map<String, Object?> _artifactPresence({
  required bool archive,
  required bool diagnostics,
  required bool runtimeEvents,
}) {
  return <String, Object?>{
    'archive': archive,
    'diagnostics': diagnostics,
    'runtime_events': runtimeEvents,
  };
}

void _expectActiveCompilerVersion(
  ShellModel shell,
  String compilerVersion, {
  required String reason,
}) {
  expect(
    shell.workspaceController.activeProject.activeCompiler?.compilerVersion,
    compilerVersion,
    reason: reason,
  );
}

void _expectArchivePresent(
  DeploymentCommandResult result, {
  required String reason,
}) {
  final archivePath = result.payload?['archive_path'] as String?;
  expect(archivePath, isNotNull, reason: reason);
  expect(archivePath, isNotEmpty, reason: reason);
  expect(File(archivePath!).existsSync(), isTrue, reason: reason);
}
