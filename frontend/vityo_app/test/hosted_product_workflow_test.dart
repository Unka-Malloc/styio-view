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
import 'package:vityo_app/src/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter_io.dart';
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
      'VITYO_HOSTED_URL',
      'VITYO_HOSTED_WORKSPACE_ROOT',
      'VITYO_HOSTED_MANIFEST_PATH',
      'VITYO_PRODUCT_STYIO_BIN',
      'VITYO_PRODUCT_STYIO_ALT_BIN',
    ])
      if (_env(name) == null) name,
  ];
  final workspaceMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_HOSTED_URL',
      'VITYO_HOSTED_WORKSPACE2_ROOT',
      'VITYO_HOSTED_MANIFEST2_PATH',
      'VITYO_PRODUCT_STYIO_BIN',
    ])
      if (_env(name) == null) name,
  ];
  final failureMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_HOSTED_URL',
      'VITYO_HOSTED_WORKSPACE3_ROOT',
      'VITYO_HOSTED_MANIFEST3_PATH',
    ])
      if (_env(name) == null) name,
  ];
  final registryMissingEnv = <String>[
    for (final name in const <String>[
      'VITYO_HOSTED_URL',
      'VITYO_HOSTED_WORKSPACE4_ROOT',
      'VITYO_HOSTED_MANIFEST4_PATH',
      'VITYO_HOSTED_WORKSPACE5_ROOT',
      'VITYO_HOSTED_MANIFEST5_PATH',
      'VITYO_HOSTED_WORKSPACE6_ROOT',
      'VITYO_HOSTED_MANIFEST6_PATH',
      'VITYO_PRODUCT_STYIO_BIN',
      'VITYO_PRODUCT_REGISTRY_ROOT',
    ])
      if (_env(name) == null) name,
  ];

  test(
    'hosted control plane supports environment, dependency, execution, and preflight workflow lanes',
    () async {
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final alternateStyioBinaryPath = _env(
        'VITYO_PRODUCT_STYIO_ALT_BIN',
      )!;

      for (final scenario in const <_HostedScenario>[
        _HostedScenario(
          label: 'iOS cloud-only',
          platformTarget: PlatformTarget.ios,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Web hosted-only',
          platformTarget: PlatformTarget.web,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Android cloud fallback',
          platformTarget: PlatformTarget.android,
          expectCloudPrimary: true,
        ),
      ]) {
        final shell = await _createHostedShell(
          platformTarget: scenario.platformTarget,
        );
        expect(
          shell.workspaceController.activeProject.hasHostedWorkspace,
          isTrue,
          reason: '${scenario.label} should resolve a hosted workspace record.',
        );
        expect(
          shell.blockedReasonForCommand(AppCommandId.fetchDependencies),
          isNull,
          reason: '${scenario.label} should not block hosted dependency fetch.',
        );
        expect(
          shell.blockedReasonForCommand(AppCommandId.preparePublish),
          isNull,
          reason:
              '${scenario.label} should not block hosted deployment preflight.',
        );

        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(
          install.succeeded,
          isTrue,
          reason:
              '${scenario.label} should install the managed compiler through hosted pafio. '
              'status=${install.status.name} message=${install.statusMessage}',
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
        expect(use.succeeded, isTrue, reason: scenario.label);

        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue, reason: scenario.label);
        _expectActiveCompilerVersion(
          shell,
          '0.0.1',
          reason:
              '${scenario.label} should resolve the primary compiler after pin.',
        );

        final installAlternate = await shell.installManagedCompiler(
          styioBinaryPath: alternateStyioBinaryPath,
        );
        expect(
          installAlternate.succeeded,
          isTrue,
          reason:
              '${scenario.label} should install the alternate managed compiler through hosted pafio. '
              'status=${installAlternate.status.name} message=${installAlternate.statusMessage}',
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
          reason:
              '${scenario.label} should retain the alternate compiler after refresh.',
        );
        final alternateCompiler = refreshedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.2',
        );

        final useAlternate = await shell.useManagedCompiler(
          compilerVersion: alternateCompiler.compilerVersion,
          channel: alternateCompiler.channel,
        );
        expect(useAlternate.succeeded, isTrue, reason: scenario.label);
        final pinAlternate = await shell.pinManagedCompiler(
          compilerVersion: alternateCompiler.compilerVersion,
          channel: alternateCompiler.channel,
        );
        expect(pinAlternate.succeeded, isTrue, reason: scenario.label);
        _expectActiveCompilerVersion(
          shell,
          '0.0.2',
          reason:
              '${scenario.label} should switch to the alternate managed compiler.',
        );

        final usePrimaryAgain = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(usePrimaryAgain.succeeded, isTrue, reason: scenario.label);
        final pinPrimaryAgain = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pinPrimaryAgain.succeeded, isTrue, reason: scenario.label);
        _expectActiveCompilerVersion(
          shell,
          '0.0.1',
          reason:
              '${scenario.label} should switch back to the primary managed compiler before workflow execution.',
        );

        final fetch = await shell.fetchDependencies();
        expect(fetch.succeeded, isTrue, reason: scenario.label);

        final vendor = await shell.vendorDependencies();
        expect(vendor.succeeded, isTrue, reason: scenario.label);

        final pack = await shell.packProject();
        expect(pack.succeeded, isTrue, reason: scenario.label);
        _expectArchivePresent(
          pack,
          reason:
              '${scenario.label} should materialize a real hosted source package archive before publish preflight.',
        );

        await _openTarget(shell, ProjectTargetKind.bin);
        await shell.executeCommand(AppCommandId.run);
        expect(shell.lastExecutionSession, isNotNull);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
          reason: '${scenario.label} should run the selected binary target.',
        );
        expect(shell.lastExecutionSession?.kind, 'run');
        expect(shell.lastRuntimeEvents, isNotEmpty);

        await _openTarget(shell, ProjectTargetKind.test);
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
          reason: '${scenario.label} should execute the selected test target.',
        );
        expect(shell.lastExecutionSession?.kind, 'test');
        expect(shell.lastRuntimeEvents, isNotEmpty);

        final preflight = await shell.preparePublish();
        expect(preflight.succeeded, isTrue, reason: scenario.label);
        _expectArchivePresent(
          preflight,
          reason:
              '${scenario.label} should keep the hosted publish preflight archive on disk.',
        );

        await _openTarget(shell, ProjectTargetKind.bin);
        await _loadActiveDocumentText(shell, '>_("broken"\n');
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.failed,
          reason:
              '${scenario.label} should surface hosted compiler diagnostics for invalid source.',
        );
        expect(
          shell.lastExecutionSession?.diagnostics,
          isNotEmpty,
          reason:
              '${scenario.label} should return structured diagnostics for hosted compiler failure.',
        );
        expect(
          shell.lastRuntimeEvents.map((event) => event.eventKind),
          contains('compile.failed'),
          reason:
              '${scenario.label} should publish compile.failed through hosted runtime events.',
        );

        final routeSummary = summarizeExecutionRoute(
          platformTarget: scenario.platformTarget,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSummary.previewOnly, isFalse, reason: scenario.label);
        expect(
          routeSummary.primaryAdapterKind,
          scenario.expectCloudPrimary ? AdapterKind.cloud : AdapterKind.cli,
          reason: scenario.label,
        );
        final routeSelection = selectBackendExecutionRoute(
          platformTarget: scenario.platformTarget,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(
          routeSelection.routeKind,
          scenario.expectCloudPrimary
              ? BackendExecutionRouteKind.hosted
              : BackendExecutionRouteKind.localCli,
          reason: scenario.label,
        );
        expect(routeSelection.allowed, isTrue, reason: scenario.label);
        expect(routeSelection.previewOnly, isFalse, reason: scenario.label);
        _emitHostedScenarioReport(
          scenario: scenario,
          scenarioName: 'hosted-core-workflow',
          workspaceKind: 'single-package',
          toolchainResult: 'switch-and-return-succeeded',
          dependencyResult: 'fetch+vendor-succeeded',
          executionResult: 'run+test-succeeded-then-compile-failed',
          deploymentResult: 'pack+preflight-succeeded',
          artifactPresence: _artifactPresence(
            archive: true,
            diagnostics:
                shell.lastExecutionSession?.diagnostics.isNotEmpty == true,
            runtimeEvents: shell.lastRuntimeEvents.isNotEmpty,
          ),
          failureKinds: const <String>['compile_failure'],
        );
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the live hosted product workflow test.'
        : missingEnv.isNotEmpty
        ? 'Missing required hosted product gate env: ${missingEnv.join(', ')}'
        : false,
  );

  test(
    'hosted control plane supports workspace package routing and publish ambiguity handling',
    () async {
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final hostedEnvironment = _workspaceHostedEnvironment(
        rootEnvName: 'VITYO_HOSTED_WORKSPACE2_ROOT',
        manifestEnvName: 'VITYO_HOSTED_MANIFEST2_PATH',
        workspaceIdEnvName: 'VITYO_HOSTED_WORKSPACE2_ID',
      );

      for (final scenario in const <_HostedScenario>[
        _HostedScenario(
          label: 'iOS cloud-only workspace',
          platformTarget: PlatformTarget.ios,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Web hosted-only workspace',
          platformTarget: PlatformTarget.web,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Android cloud fallback workspace',
          platformTarget: PlatformTarget.android,
          expectCloudPrimary: true,
        ),
      ]) {
        final shell = await _createHostedShell(
          platformTarget: scenario.platformTarget,
          hostedEnvironment: hostedEnvironment,
        );
        expect(
          shell.workspaceController.activeProject.hasHostedWorkspace,
          isTrue,
          reason: '${scenario.label} should resolve a hosted workspace record.',
        );
        expect(
          shell.workspaceController.activeProject.packages.length,
          2,
          reason:
              '${scenario.label} should load a multi-package hosted workspace.',
        );
        expect(
          shell
              .workspaceController
              .activeProject
              .packageDistribution
              ?.publishablePackages,
          2,
          reason:
              '${scenario.label} should expose both publish-ready packages.',
        );

        final install = await shell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(install.succeeded, isTrue, reason: scenario.label);
        final installedToolchains =
            shell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        expect(installedToolchains, isNotEmpty, reason: scenario.label);
        final primaryCompiler = installedToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => installedToolchains.first,
        );

        final use = await shell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(use.succeeded, isTrue, reason: scenario.label);

        final pin = await shell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(pin.succeeded, isTrue, reason: scenario.label);
        _expectActiveCompilerVersion(
          shell,
          '0.0.1',
          reason:
              '${scenario.label} should resolve the primary compiler before workspace execution.',
        );

        final publishBlockedReason = shell.blockedReasonForCommand(
          AppCommandId.preparePublish,
        );
        expect(
          publishBlockedReason,
          contains('Multiple publish-ready packages are available'),
          reason:
              '${scenario.label} should surface publish ambiguity before package selection.',
        );

        final blockedPreflight = await shell.preparePublish();
        expect(
          blockedPreflight.status,
          DeploymentCommandStatus.blocked,
          reason:
              '${scenario.label} should block publish preflight until a package is selected.',
        );
        expect(
          blockedPreflight.statusMessage,
          contains('Multiple publish-ready packages are available'),
          reason: scenario.label,
        );

        final fetch = await shell.fetchDependencies();
        expect(fetch.succeeded, isTrue, reason: scenario.label);

        final vendor = await shell.vendorDependencies();
        expect(vendor.succeeded, isTrue, reason: scenario.label);

        await _openPackageTarget(
          shell,
          packageName: 'acme/tool',
          targetKind: ProjectTargetKind.bin,
        );
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
          reason:
              '${scenario.label} should run the selected workspace package target.',
        );
        expect(shell.lastExecutionSession?.kind, 'run');
        expect(shell.lastRuntimeEvents, isNotEmpty);

        await _openPackageTarget(
          shell,
          packageName: 'acme/tool',
          targetKind: ProjectTargetKind.test,
        );
        await shell.executeCommand(AppCommandId.run);
        expect(
          shell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
          reason:
              '${scenario.label} should test the selected workspace package target.',
        );
        expect(shell.lastExecutionSession?.kind, 'test');
        expect(shell.lastRuntimeEvents, isNotEmpty);

        final explicitPack = await shell.packProject(packageName: 'acme/tool');
        expect(explicitPack.succeeded, isTrue, reason: scenario.label);
        _expectArchivePresent(
          explicitPack,
          reason:
              '${scenario.label} should materialize a package-specific hosted archive for the selected package.',
        );

        final explicitPreflight = await shell.preparePublish(
          packageName: 'acme/tool',
        );
        expect(
          explicitPreflight.succeeded,
          isTrue,
          reason:
              '${scenario.label} should preflight the selected publishable package.',
        );
        _expectArchivePresent(
          explicitPreflight,
          reason:
              '${scenario.label} should keep the explicit hosted package preflight archive on disk.',
        );

        final routeSummary = summarizeExecutionRoute(
          platformTarget: scenario.platformTarget,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSummary.previewOnly, isFalse, reason: scenario.label);
        expect(
          routeSummary.primaryAdapterKind,
          scenario.expectCloudPrimary ? AdapterKind.cloud : AdapterKind.cli,
          reason: scenario.label,
        );
        _emitHostedScenarioReport(
          scenario: scenario,
          scenarioName: 'hosted-multi-package-workflow',
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
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the live hosted product workflow test.'
        : workspaceMissingEnv.isNotEmpty
        ? 'Missing required hosted workspace product gate env: ${workspaceMissingEnv.join(', ')}'
        : false,
  );

  test(
    'hosted control plane surfaces dependency and deployment failures through the product lanes',
    () async {
      final hostedEnvironment = _workspaceHostedEnvironment(
        rootEnvName: 'VITYO_HOSTED_WORKSPACE3_ROOT',
        manifestEnvName: 'VITYO_HOSTED_MANIFEST3_PATH',
        workspaceIdEnvName: 'VITYO_HOSTED_WORKSPACE3_ID',
      );

      for (final scenario in const <_HostedScenario>[
        _HostedScenario(
          label: 'iOS cloud-only dependency failure',
          platformTarget: PlatformTarget.ios,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Web hosted-only dependency failure',
          platformTarget: PlatformTarget.web,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Android cloud fallback dependency failure',
          platformTarget: PlatformTarget.android,
          expectCloudPrimary: true,
        ),
      ]) {
        final shell = await _createHostedShell(
          platformTarget: scenario.platformTarget,
          hostedEnvironment: hostedEnvironment,
        );
        expect(
          shell.blockedReasonForCommand(AppCommandId.fetchDependencies),
          isNull,
          reason:
              '${scenario.label} should attempt hosted dependency fetch instead of blocking locally.',
        );

        final fetch = await shell.fetchDependencies();
        expect(
          fetch.status,
          DependencySourceCommandStatus.failed,
          reason:
              '${scenario.label} should fail hosted dependency fetch for the broken dependency source.',
        );
        expect(fetch.statusMessage, isNotEmpty, reason: scenario.label);
        expect(
          fetch.errorPayload,
          isNotNull,
          reason:
              '${scenario.label} should keep the structured pafio failure payload for dependency fetch errors.',
        );
        expect(
          shell.lastDependencySourceCommand?.status,
          DependencySourceCommandStatus.failed,
          reason:
              '${scenario.label} should retain the failed dependency result in shell state.',
        );

        final preflight = await shell.preparePublish(
          packageName: 'acme/broken-fetch',
        );
        expect(
          preflight.status,
          DeploymentCommandStatus.failed,
          reason:
              '${scenario.label} should fail hosted publish preflight for the non-publishable package.',
        );
        expect(preflight.statusMessage, isNotEmpty, reason: scenario.label);
        expect(
          preflight.errorPayload,
          isNotNull,
          reason:
              '${scenario.label} should keep the structured pafio failure payload for hosted preflight errors.',
        );
        expect(
          shell.lastDeploymentCommand?.status,
          DeploymentCommandStatus.failed,
          reason:
              '${scenario.label} should retain the failed deployment result in shell state.',
        );

        final routeSummary = summarizeExecutionRoute(
          platformTarget: scenario.platformTarget,
          projectGraph: shell.workspaceController.activeProject,
          adapterCapabilities: shell.adapterCapabilities,
        );
        expect(routeSummary.previewOnly, isFalse, reason: scenario.label);
        expect(
          routeSummary.primaryAdapterKind,
          scenario.expectCloudPrimary ? AdapterKind.cloud : AdapterKind.cli,
          reason: scenario.label,
        );
        _emitHostedScenarioReport(
          scenario: scenario,
          scenarioName: 'hosted-failure-matrix',
          workspaceKind: 'single-package',
          toolchainResult: 'not-exercised',
          dependencyResult: 'failed',
          executionResult: 'not-exercised',
          deploymentResult: 'preflight-failed',
          artifactPresence: _artifactPresence(
            archive: false,
            diagnostics: false,
            runtimeEvents: false,
          ),
          failureKinds: const <String>[
            'dependency_fetch_failure',
            'publish_preflight_failure',
          ],
        );
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the live hosted product workflow test.'
        : failureMissingEnv.isNotEmpty
        ? 'Missing required hosted failure-path env: ${failureMissingEnv.join(', ')}'
        : false,
  );

  test(
    'hosted control plane supports registry publish, consume, republish conflict, and missing-version fetch failure',
    () async {
      final styioBinaryPath = _env('VITYO_PRODUCT_STYIO_BIN')!;
      final registryRootBase = _env('VITYO_PRODUCT_REGISTRY_ROOT')!;

      for (final scenario in const <_HostedScenario>[
        _HostedScenario(
          label: 'iOS cloud-only registry distribution',
          platformTarget: PlatformTarget.ios,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Web hosted-only registry distribution',
          platformTarget: PlatformTarget.web,
          expectCloudPrimary: true,
        ),
        _HostedScenario(
          label: 'Android cloud fallback registry distribution',
          platformTarget: PlatformTarget.android,
          expectCloudPrimary: true,
        ),
      ]) {
        final scenarioRegistryRoot = await _createScenarioRegistryRoot(
          registryRootBase,
          scenario.label,
        );
        final scenarioRegistryUri = scenarioRegistryRoot.absolute.uri
            .toString();

        await _rewriteManifestRegistryRoot(
          manifestPath: _env('VITYO_HOSTED_MANIFEST5_PATH')!,
          registryRoot: scenarioRegistryUri,
        );
        await _rewriteManifestRegistryRoot(
          manifestPath: _env('VITYO_HOSTED_MANIFEST6_PATH')!,
          registryRoot: scenarioRegistryUri,
        );

        final publishShell = await _createHostedShell(
          platformTarget: scenario.platformTarget,
          hostedEnvironment: _workspaceHostedEnvironment(
            rootEnvName: 'VITYO_HOSTED_WORKSPACE4_ROOT',
            manifestEnvName: 'VITYO_HOSTED_MANIFEST4_PATH',
            workspaceIdEnvName: 'VITYO_HOSTED_WORKSPACE4_ID',
            includeWorkspaceId: false,
          ),
        );
        expect(
          publishShell.workspaceController.activeProject.hasHostedWorkspace,
          isTrue,
          reason:
              '${scenario.label} should resolve a hosted publish workspace record.',
        );
        final publishInstall = await publishShell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(publishInstall.succeeded, isTrue, reason: scenario.label);
        final publishToolchains =
            publishShell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        expect(publishToolchains, isNotEmpty, reason: scenario.label);
        final primaryCompiler = publishToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => publishToolchains.first,
        );
        final publishUse = await publishShell.useManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(publishUse.succeeded, isTrue, reason: scenario.label);
        final publishPin = await publishShell.pinManagedCompiler(
          compilerVersion: primaryCompiler.compilerVersion,
          channel: primaryCompiler.channel,
        );
        expect(publishPin.succeeded, isTrue, reason: scenario.label);

        await _openTarget(publishShell, ProjectTargetKind.lib);
        await publishShell.executeCommand(AppCommandId.run);
        expect(
          publishShell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
          reason:
              '${scenario.label} should build the hosted registry library package before publish.',
        );
        expect(
          publishShell.lastExecutionSession?.kind,
          'build',
          reason:
              '${scenario.label} should route the library package through a build workflow.',
        );
        expect(
          publishShell.lastRuntimeEvents,
          isNotEmpty,
          reason:
              '${scenario.label} should retain runtime events for the hosted registry library build.',
        );

        final publish = await publishShell.publishToRegistry(
          registryRoot: scenarioRegistryRoot.path,
          packageName: 'acme/registry-feed',
        );
        expect(publish.succeeded, isTrue, reason: scenario.label);
        expect(
          publish.payload?['registry_root'],
          scenarioRegistryRoot.path,
          reason:
              '${scenario.label} should report the hosted filesystem registry root.',
        );
        _expectArchivePresent(
          publish,
          reason:
              '${scenario.label} should keep the hosted registry distribution archive on disk.',
        );

        final republish = await publishShell.publishToRegistry(
          registryRoot: scenarioRegistryRoot.path,
          packageName: 'acme/registry-feed',
        );
        expect(
          republish.status,
          DeploymentCommandStatus.failed,
          reason:
              '${scenario.label} should reject republishing the same hosted package version to the same registry.',
        );
        expect(republish.statusMessage, isNotEmpty, reason: scenario.label);
        expect(republish.errorPayload, isNotNull, reason: scenario.label);
        expect(
          publishShell.lastDeploymentCommand?.status,
          DeploymentCommandStatus.failed,
          reason:
              '${scenario.label} should retain the hosted republish conflict in shell state.',
        );

        final consumeShell = await _createHostedShell(
          platformTarget: scenario.platformTarget,
          hostedEnvironment: _workspaceHostedEnvironment(
            rootEnvName: 'VITYO_HOSTED_WORKSPACE5_ROOT',
            manifestEnvName: 'VITYO_HOSTED_MANIFEST5_PATH',
            workspaceIdEnvName: 'VITYO_HOSTED_WORKSPACE5_ID',
            includeWorkspaceId: false,
          ),
        );
        expect(
          consumeShell.workspaceController.activeProject.hasHostedWorkspace,
          isTrue,
          reason:
              '${scenario.label} should resolve a hosted consumer workspace record.',
        );
        final consumeInstall = await consumeShell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(consumeInstall.succeeded, isTrue, reason: scenario.label);
        final consumeToolchains =
            consumeShell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        expect(consumeToolchains, isNotEmpty, reason: scenario.label);
        final consumeCompiler = consumeToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => consumeToolchains.first,
        );
        final consumeUse = await consumeShell.useManagedCompiler(
          compilerVersion: consumeCompiler.compilerVersion,
          channel: consumeCompiler.channel,
        );
        expect(consumeUse.succeeded, isTrue, reason: scenario.label);
        final consumePin = await consumeShell.pinManagedCompiler(
          compilerVersion: consumeCompiler.compilerVersion,
          channel: consumeCompiler.channel,
        );
        expect(consumePin.succeeded, isTrue, reason: scenario.label);

        final fetch = await consumeShell.fetchDependencies();
        expect(fetch.succeeded, isTrue, reason: scenario.label);
        final acceptedRegistryRoots = <String>{
          scenarioRegistryRoot.path,
          scenarioRegistryUri,
        };
        expect(
          consumeShell.workspaceController.activeProject.dependencies.any(
                (dependency) =>
                    dependency.packageIdentity == 'acme/registry-feed' &&
                    dependency.registryRoot != null &&
                    acceptedRegistryRoots.contains(dependency.registryRoot),
              ) ||
              consumeShell
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
              (consumeShell
                          .workspaceController
                          .activeProject
                          .sourceState
                          ?.declaredRegistryDependencies ??
                      0) >
                  0,
          isTrue,
          reason:
              '${scenario.label} should expose the hosted registry consumer contract after fetch.',
        );

        await _openTarget(consumeShell, ProjectTargetKind.bin);
        await consumeShell.executeCommand(AppCommandId.run);
        expect(
          consumeShell.lastExecutionSession?.status,
          ExecutionSessionStatus.succeeded,
          reason:
              '${scenario.label} should run the hosted registry consumer after fetch.',
        );
        final consumeRouteSummary = summarizeExecutionRoute(
          platformTarget: scenario.platformTarget,
          projectGraph: consumeShell.workspaceController.activeProject,
          adapterCapabilities: consumeShell.adapterCapabilities,
        );
        expect(
          consumeRouteSummary.primaryAdapterKind,
          scenario.expectCloudPrimary ? AdapterKind.cloud : AdapterKind.cli,
          reason: scenario.label,
        );

        final missingShell = await _createHostedShell(
          platformTarget: scenario.platformTarget,
          hostedEnvironment: _workspaceHostedEnvironment(
            rootEnvName: 'VITYO_HOSTED_WORKSPACE6_ROOT',
            manifestEnvName: 'VITYO_HOSTED_MANIFEST6_PATH',
            workspaceIdEnvName: 'VITYO_HOSTED_WORKSPACE6_ID',
            includeWorkspaceId: false,
          ),
        );
        final missingInstall = await missingShell.installManagedCompiler(
          styioBinaryPath: styioBinaryPath,
        );
        expect(missingInstall.succeeded, isTrue, reason: scenario.label);
        final missingToolchains =
            missingShell
                .workspaceController
                .activeProject
                .toolchainEnvironment
                ?.managedToolchains
                .installed ??
            const <ManagedToolchainInstallSnapshot>[];
        expect(missingToolchains, isNotEmpty, reason: scenario.label);
        final missingCompiler = missingToolchains.firstWhere(
          (toolchain) => toolchain.compilerVersion == '0.0.1',
          orElse: () => missingToolchains.first,
        );
        final missingUse = await missingShell.useManagedCompiler(
          compilerVersion: missingCompiler.compilerVersion,
          channel: missingCompiler.channel,
        );
        expect(missingUse.succeeded, isTrue, reason: scenario.label);
        final missingPin = await missingShell.pinManagedCompiler(
          compilerVersion: missingCompiler.compilerVersion,
          channel: missingCompiler.channel,
        );
        expect(missingPin.succeeded, isTrue, reason: scenario.label);

        final missingFetch = await missingShell.fetchDependencies();
        expect(
          missingFetch.status,
          DependencySourceCommandStatus.failed,
          reason:
              '${scenario.label} should fail hosted fetch when the registry requests a missing package version.',
        );
        expect(missingFetch.statusMessage, isNotEmpty, reason: scenario.label);
        expect(
          missingFetch.errorPayload,
          isNotNull,
          reason:
              '${scenario.label} should keep the structured hosted registry fetch failure payload.',
        );
        expect(
          missingShell.lastDependencySourceCommand?.status,
          DependencySourceCommandStatus.failed,
          reason:
              '${scenario.label} should retain the hosted missing-version failure in shell state.',
        );
        _emitHostedScenarioReport(
          scenario: scenario,
          scenarioName: 'hosted-registry-distribution',
          workspaceKind: 'single-package-library',
          toolchainResult: 'pin-succeeded',
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
      }
    },
    skip: !productGateEnabled
        ? 'Set VITYO_PRODUCT_GATE=1 to run the live hosted product workflow test.'
        : registryMissingEnv.isNotEmpty
        ? 'Missing required hosted registry-path env: ${registryMissingEnv.join(', ')}'
        : false,
  );
}

Future<ShellModel> _createHostedShell({
  required PlatformTarget platformTarget,
  Map<String, String>? hostedEnvironment,
}) async {
  if (hostedEnvironment != null) {
    debugOverrideHostedEnvironment(hostedEnvironment);
    debugOverrideProjectGraphEnvironment(hostedEnvironment);
  }
  late final ProjectGraphAdapter projectGraphAdapter;
  late final ProjectGraphSnapshot projectGraph;
  late final ExecutionAdapter executionAdapter;
  late final RuntimeEventAdapter runtimeEventAdapter;
  late final DependencySourceAdapter dependencySourceAdapter;
  late final DeploymentAdapter deploymentAdapter;
  late final ToolchainManagementAdapter toolchainManagementAdapter;
  try {
    projectGraphAdapter = await createProjectGraphAdapter(
      platformTarget: platformTarget,
    );
    projectGraph = await projectGraphAdapter.loadProjectGraph();
    executionAdapter = await createExecutionAdapter(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
    );
    runtimeEventAdapter = createRuntimeEventAdapter(
      platformTarget: platformTarget,
    );
    dependencySourceAdapter = await createDependencySourceAdapter(
      platformTarget: platformTarget,
    );
    deploymentAdapter = await createDeploymentAdapter(
      platformTarget: platformTarget,
    );
    toolchainManagementAdapter = await createToolchainManagementAdapter(
      platformTarget: platformTarget,
    );
  } finally {
    if (hostedEnvironment != null) {
      debugOverrideHostedEnvironment(null);
      debugOverrideProjectGraphEnvironment(null);
    }
  }
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
    platformTarget: platformTarget,
    supplementalAdapterCapabilities: normalizeCapabilitySnapshots(
      <AdapterCapabilitySnapshot>[
        buildCloudAdapterCapability(
          supportsCloudExecution: true,
          supportsHostedProjectGraph: true,
          detail: 'Hosted product workflow route is live for the gate fixture.',
        ),
      ],
    ),
    projectGraphAdapter: projectGraphAdapter,
    workspaceController: workspaceController,
    workspaceDocumentStore: workspaceDocumentStore,
    moduleRegistry: ModuleRegistry(
      platformTarget: platformTarget,
      definitions: const [],
    ),
    nativeModuleLoader: NoopNativeModuleLoader(platformTarget: platformTarget),
    editorController: editorController,
    executionAdapter: executionAdapter,
    executionAdapterFactory: (ProjectGraphSnapshot refreshedProjectGraph) {
      return createExecutionAdapter(
        platformTarget: platformTarget,
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
  await _openResolvedTarget(shell, target);
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

Future<void> _settleAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

String? _env(String name) {
  final value = Platform.environment[name];
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Map<String, String> _workspaceHostedEnvironment({
  required String rootEnvName,
  required String manifestEnvName,
  required String workspaceIdEnvName,
  bool includeWorkspaceId = true,
}) {
  final environment = Map<String, String>.from(Platform.environment);
  environment['VITYO_HOSTED_WORKSPACE_ROOT'] = _env(rootEnvName)!;
  environment['VITYO_HOSTED_MANIFEST_PATH'] = _env(manifestEnvName)!;
  final workspaceId = includeWorkspaceId ? _env(workspaceIdEnvName) : null;
  if (workspaceId == null) {
    environment.remove('VITYO_HOSTED_WORKSPACE_ID');
  } else {
    environment['VITYO_HOSTED_WORKSPACE_ID'] = workspaceId;
  }
  return environment;
}

Future<Directory> _createScenarioRegistryRoot(
  String registryRootBase,
  String scenarioLabel,
) async {
  final baseDirectory = Directory(registryRootBase);
  await baseDirectory.create(recursive: true);
  final scenarioDirectory = Directory(
    '${baseDirectory.absolute.path}/${_scenarioSlug(scenarioLabel)}-${DateTime.now().microsecondsSinceEpoch}',
  );
  await scenarioDirectory.create(recursive: true);
  return scenarioDirectory;
}

Future<void> _rewriteManifestRegistryRoot({
  required String manifestPath,
  required String registryRoot,
}) async {
  final file = File(manifestPath);
  final original = await file.readAsString();
  final rewritten = original.replaceAll(
    RegExp(r'registry = "[^"]*"'),
    'registry = "$registryRoot"',
  );
  if (rewritten == original) {
    throw StateError(
      'Hosted registry scenario expected a registry dependency in $manifestPath.',
    );
  }
  await file.writeAsString(rewritten);
}

String _scenarioSlug(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return normalized.replaceAll(RegExp(r'^-+|-+$'), '');
}

void _emitHostedScenarioReport({
  required _HostedScenario scenario,
  required String scenarioName,
  required String workspaceKind,
  required String toolchainResult,
  required String dependencyResult,
  required String executionResult,
  required String deploymentResult,
  required Map<String, Object?> artifactPresence,
  List<String> failureKinds = const <String>[],
}) {
  _emitScenarioReport(<String, Object?>{
    'scenario': scenarioName,
    'platform': scenario.platformTarget.wireValue,
    'route': 'hosted',
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

class _HostedScenario {
  const _HostedScenario({
    required this.label,
    required this.platformTarget,
    this.expectCloudPrimary = false,
  });

  final String label;
  final PlatformTarget platformTarget;
  final bool expectCloudPrimary;
}
