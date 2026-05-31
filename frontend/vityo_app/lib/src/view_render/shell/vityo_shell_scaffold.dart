import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../editor/editor.dart';
import '../../backend_toolchain/adapter_contracts.dart';
import '../../backend_toolchain/dependency_source_adapter.dart';
import '../../backend_toolchain/deployment_adapter.dart';
import '../../backend_toolchain/execution_adapter.dart';
import '../../backend_toolchain/execution_route_summary.dart';
import '../../backend_toolchain/project_graph_contract.dart';
import '../../backend_toolchain/required_handoff_summary.dart';
import '../../backend_toolchain/toolchain_management_adapter.dart';
import '../../module_host/module_definition.dart';
import '../../module_host/module_manifest.dart';
import '../../platform/platform_target.dart';
import '../../view_ide/workspace/workspace.dart';
import '../platform/platform.dart';
import '../runtime/runtime.dart';
import '../settings/settings_surface.dart';

import '../../app/commands/app_commands.dart';
import 'shell_model.dart';
import 'shell_scope.dart';

class VityoShellScaffold extends StatelessWidget {
  const VityoShellScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final project = shell.workspaceController.activeProject;
    final viewportProfile = resolveViewportProfile(
      platformTarget: shell.platformTarget,
      width: MediaQuery.sizeOf(context).width,
      height: MediaQuery.sizeOf(context).height,
    );

    return Shortcuts(
      shortcuts: AppCommandShortcutRegistry.shortcutIntents,
      child: Actions(
        actions: <Type, Action<Intent>>{
          AppCommandIntent: CallbackAction<AppCommandIntent>(
            onInvoke: (intent) {
              shell.executeCommand(intent.commandId);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _TopBar(
                      platformTarget: shell.platformTarget,
                      activeProjectTitle: project.title,
                      viewportProfile: viewportProfile,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final layoutViewport = resolveViewportProfile(
                            platformTarget: shell.platformTarget,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          );

                          if (layoutViewport.isMobile) {
                            return _MobileShellBody(
                              shell: shell,
                              viewportProfile: layoutViewport,
                              bottomSurface: _buildBottomSurface(
                                shell,
                                layoutViewport,
                              ),
                            );
                          }

                          return _DesktopShellBody(
                            shell: shell,
                            viewportProfile: layoutViewport,
                            bottomSurface: _buildBottomSurface(
                              shell,
                              layoutViewport,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ShellStatusBar(
                      platformTarget: shell.platformTarget,
                      viewportProfile: viewportProfile,
                      mountedModuleCount: shell.mountedModules.length,
                      visibleModuleCount: shell.visibleModules.length,
                      projectTitle: project.title,
                      activeFilePath: shell.workspaceController.activeFilePath,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSurface(
    ShellModel shell,
    ViewportProfile viewportProfile,
  ) {
    switch (shell.activeBottomTab) {
      case BottomSurfaceTab.runtime:
        return RuntimeSurface(
          platformTarget: shell.platformTarget,
          viewportProfile: viewportProfile,
          projectGraph: shell.workspaceController.activeProject,
          toolchainStatus: shell.toolchainStatusSurface,
          onToolchainRecoveryAction: shell.handleToolchainRecoveryAction,
          mountedModules: shell.mountedModules,
          adapterCapabilities: shell.adapterCapabilities,
          executionSession: shell.lastExecutionSession,
          runtimeEvents: shell.lastRuntimeEvents,
        );
      case BottomSurfaceTab.search:
        return _WorkspaceSearchSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.agent:
        return AgentSurface(
          platformTarget: shell.platformTarget,
          viewportProfile: viewportProfile,
          visibleModules: shell.visibleModules,
          adapterCapabilities: shell.adapterCapabilities,
        );
      case BottomSurfaceTab.debug:
        return DebugConsoleSurface(
          viewportProfile: viewportProfile,
          entries: shell.debugLog,
          runtimeEvents: shell.lastRuntimeEvents,
        );
      case BottomSurfaceTab.settings:
        return SettingsSurface(
          viewportProfile: viewportProfile,
          toolchainStatus: shell.toolchainStatusSurface,
          toolchainSettings: shell.toolchainSettingsSurface,
          toolchainInstallPlan: shell.toolchainInstallPlanSurface,
          toolchainInstallExecution: shell.toolchainInstallExecutionSurface,
          onToolchainRecoveryAction: shell.handleToolchainRecoveryAction,
          onSelectToolchain: shell.selectToolchainCandidate,
          onClearToolchain: shell.clearToolchainCandidate,
          onExecuteToolchainInstallPlan: shell.executeLastToolchainInstallPlan,
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.platformTarget,
    required this.activeProjectTitle,
    required this.viewportProfile,
  });

  final PlatformTarget platformTarget;
  final String activeProjectTitle;
  final ViewportProfile viewportProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              viewportProfile.isMobile || constraints.maxWidth < 900;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vityo Integration Shell',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Product-owned adapters, project graph, and execution routes across Web, desktop, and mobile shells.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          Chip(label: Text(platformTarget.label)),
                          Chip(label: Text(viewportProfile.label)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        activeProjectTitle,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vityo Integration Shell',
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Product-owned adapters, project graph, and execution routes across Web, desktop, and mobile shells.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Chip(label: Text(platformTarget.label)),
                          const SizedBox(height: 8),
                          Chip(label: Text(viewportProfile.label)),
                          const SizedBox(height: 8),
                          Text(
                            activeProjectTitle,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ShellStatusBar extends StatelessWidget {
  const _ShellStatusBar({
    required this.platformTarget,
    required this.viewportProfile,
    required this.mountedModuleCount,
    required this.visibleModuleCount,
    required this.projectTitle,
    required this.activeFilePath,
  });

  final PlatformTarget platformTarget;
  final ViewportProfile viewportProfile;
  final int mountedModuleCount;
  final int visibleModuleCount;
  final String projectTitle;
  final String activeFilePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: viewportProfile.isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Platform ${platformTarget.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Viewport ${viewportProfile.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Mounted $mountedModuleCount/$visibleModuleCount modules',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Project $projectTitle · $activeFilePath',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
            : Row(
                children: [
                  Text(
                    'Platform ${platformTarget.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Viewport ${viewportProfile.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Mounted $mountedModuleCount/$visibleModuleCount modules',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Project $projectTitle · $activeFilePath',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DesktopShellBody extends StatelessWidget {
  const _DesktopShellBody({
    required this.shell,
    required this.viewportProfile,
    required this.bottomSurface,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;
  final Widget bottomSurface;

  @override
  Widget build(BuildContext context) {
    final denseDesktop = viewportProfile.width < 1440;
    final workspaceWidth = denseDesktop ? 252.0 : 288.0;
    final moduleWidth = denseDesktop ? 320.0 : 348.0;
    final bottomSurfaceHeight = viewportProfile.height >= 840
        ? 250.0
        : viewportProfile.height >= 680
        ? 200.0
        : 160.0;

    return KeyedSubtree(
      key: const ValueKey('shell-viewport-desktop'),
      child: Row(
        children: [
          SizedBox(
            width: workspaceWidth,
            child: _WorkspaceSidebar(shell: shell),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: denseDesktop ? 6 : 5,
                        child: EditorSurface(
                          controller: shell.editorController,
                          viewportProfile: viewportProfile,
                          languageServiceStatus:
                              shell.languageServiceStatus.value,
                          fileBindingSnapshot: shell.editorFileBindingSnapshot,
                          onAcceptExternalChange:
                              shell.acceptEditorExternalChange,
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: moduleWidth,
                        child: _ModuleSidebar(shell: shell),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _BottomSurfaceTabs(
                  shell: shell,
                  viewportProfile: viewportProfile,
                ),
                const SizedBox(height: 10),
                SizedBox(height: bottomSurfaceHeight, child: bottomSurface),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShellBody extends StatelessWidget {
  const _MobileShellBody({
    required this.shell,
    required this.viewportProfile,
    required this.bottomSurface,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;
  final Widget bottomSurface;

  @override
  Widget build(BuildContext context) {
    final editorHeight = viewportProfile.height >= 820 ? 460.0 : 400.0;
    final workspaceHeight = viewportProfile.height >= 820 ? 320.0 : 280.0;
    final moduleHeight = viewportProfile.height >= 820 ? 320.0 : 280.0;
    final bottomSurfaceHeight = viewportProfile.height >= 820 ? 220.0 : 180.0;

    return KeyedSubtree(
      key: const ValueKey('shell-viewport-mobile'),
      child: ListView(
        children: [
          SizedBox(
            height: editorHeight,
            child: EditorSurface(
              controller: shell.editorController,
              viewportProfile: viewportProfile,
              languageServiceStatus: shell.languageServiceStatus.value,
              fileBindingSnapshot: shell.editorFileBindingSnapshot,
              onAcceptExternalChange: shell.acceptEditorExternalChange,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: workspaceHeight,
            child: _WorkspaceSidebar(shell: shell),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: moduleHeight,
            child: _ModuleSidebar(shell: shell),
          ),
          const SizedBox(height: 16),
          _BottomSurfaceTabs(shell: shell, viewportProfile: viewportProfile),
          const SizedBox(height: 10),
          SizedBox(height: bottomSurfaceHeight, child: bottomSurface),
        ],
      ),
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({required this.shell});

  final ShellModel shell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = shell.workspaceController.activeProject;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          key: const ValueKey('workspace-sidebar-scroll'),
          children: [
            Text('Project Graph', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _ProjectSummaryCard(project: project),
            const SizedBox(height: 12),
            _ProjectWorkflowCard(
              platformTarget: shell.platformTarget,
              project: project,
              adapterCapabilities: shell.adapterCapabilities,
            ),
            const SizedBox(height: 12),
            _CompilerHandshakeCard(project: project),
            const SizedBox(height: 12),
            _ProjectOperationsCard(shell: shell),
            const SizedBox(height: 12),
            _RequiredHandoffsCard(
              platformTarget: shell.platformTarget,
              project: project,
              adapterCapabilities: shell.adapterCapabilities,
            ),
            if (project.workspaceMembers.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Workspace Members', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final member in project.workspaceMembers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WorkspaceMemberTile(memberPath: member),
                ),
            ],
            if (project.packages.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Packages', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final package in project.packages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProjectPackageTile(package: package),
                ),
            ],
            if (project.dependencies.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Dependencies', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final dependency in project.dependencies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProjectDependencyTile(dependency: dependency),
                ),
            ],
            if (shell.workspaceController.targets.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Targets', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final target in shell.workspaceController.targets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProjectTargetTile(
                    target: target,
                    active:
                        target.filePath ==
                        shell.workspaceController.activeFilePath,
                    onTap: () => shell.workspaceController.openTarget(target),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            Text('Files', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final file in shell.workspaceController.files)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WorkspaceFileTile(
                  file: file,
                  active: file == shell.workspaceController.activeFilePath,
                  onTap: () => shell.workspaceController.openFile(file),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({required this.project});

  final ProjectGraphSnapshot project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECE3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(project.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(project.workspaceRoot, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(project.kind.label)),
                Chip(label: Text('lock ${project.lockState.label}')),
                Chip(label: Text('vendor ${project.vendorState.label}')),
                Chip(label: Text('${project.packageCount} package')),
                Chip(label: Text('${project.workspaceMemberCount} member')),
                Chip(label: Text('${project.dependencyCount} dependency')),
                Chip(label: Text('${project.targetCount} target')),
                Chip(label: Text('${project.editorFileCount} file')),
              ],
            ),
            const SizedBox(height: 10),
            Text(project.toolchain.detail, style: theme.textTheme.bodySmall),
            if (project.manifestPath != null) ...[
              const SizedBox(height: 6),
              Text(
                'manifest ${project.manifestPath}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (project.toolchainPinPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'toolchain ${project.toolchainPinPath}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (project.styioConfigPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'styio ${project.styioConfigPath}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (project.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(project.notes.first, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectWorkflowCard extends StatelessWidget {
  const _ProjectWorkflowCard({
    required this.platformTarget,
    required this.project,
    required this.adapterCapabilities,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot project;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = summarizeExecutionRoute(
      platformTarget: platformTarget,
      projectGraph: project,
      adapterCapabilities: adapterCapabilities,
    );

    return DecoratedBox(
      key: const ValueKey('project-workflow-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project Workflow', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(summary.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(summary.body, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(summary.primaryAdapterKind.label)),
                Chip(
                  label: Text(
                    summary.previewOnly ? 'preview-only' : 'live-capable',
                  ),
                ),
                if (project.compilePlanConsumerAdvertised)
                  const Chip(label: Text('compile-plan detected')),
                Chip(
                  label: Text(
                    summary.jitRoute.blocked ? 'JIT blocked' : 'JIT live',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompilerHandshakeCard extends StatelessWidget {
  const _CompilerHandshakeCard({required this.project});

  final ProjectGraphSnapshot project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compiler = project.activeCompiler;

    return DecoratedBox(
      key: const ValueKey('compiler-handshake-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compiler Handshake', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            if (compiler == null)
              Text(
                'No local styio machine-info handshake has been resolved yet.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${compiler.tool} ${compiler.compilerVersion} · ${compiler.channel}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'variant ${compiler.variant} · phase ${compiler.integrationPhase}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(compiler.contractSummary, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                compiler.capabilitySummary,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(project.toolchain.source.label)),
                if (project.toolchain.channel != null)
                  Chip(label: Text('channel ${project.toolchain.channel}')),
                if (compiler != null &&
                    compiler.supportsContract('compile_plan'))
                  const Chip(label: Text('compile-plan ready')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequiredHandoffsCard extends StatelessWidget {
  const _RequiredHandoffsCard({
    required this.platformTarget,
    required this.project,
    required this.adapterCapabilities,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot project;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: platformTarget,
      projectGraph: project,
      adapterCapabilities: adapterCapabilities,
    );
    final blockingCount = handoffs.where((handoff) => handoff.blocking).length;
    final styioCount = handoffs
        .where((handoff) => handoff.owner == HandoffOwner.styio)
        .length;
    final spioCount = handoffs
        .where((handoff) => handoff.owner == HandoffOwner.spio)
        .length;

    return DecoratedBox(
      key: const ValueKey('required-handoffs-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFF3ECE7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Required Handoffs', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This card only states what `Vityo` still needs from upstream machine contracts. It does not prescribe upstream internals.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('$blockingCount blocking')),
                Chip(label: Text('$styioCount styio')),
                Chip(label: Text('$spioCount spio')),
              ],
            ),
            const SizedBox(height: 10),
            if (handoffs.isEmpty)
              Text(
                'No product-side handoffs are currently outstanding for this route.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (var index = 0; index < handoffs.length; index += 1) ...[
                if (index > 0) const SizedBox(height: 10),
                _RequiredHandoffTile(handoff: handoffs[index]),
              ],
          ],
        ),
      ),
    );
  }
}

class _ProjectOperationsCard extends StatelessWidget {
  const _ProjectOperationsCard({required this.shell});

  final ShellModel shell;

  String? _stringPayload(Map<String, dynamic>? payload, String key) {
    final value = payload?[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  List<String> _blockedWorkflowPreview() {
    return StyioCommandRegistry.workflowCommands
        .map((command) {
          final reason = shell.blockedReasonForCommand(command.id);
          if (reason == null) {
            return null;
          }
          return '${command.label}: $reason';
        })
        .whereType<String>()
        .take(3)
        .toList(growable: false);
  }

  Color _laneColor(BuildContext context, String status) {
    switch (status) {
      case 'succeeded':
      case 'resolved':
      case 'ready':
        return const Color(0xFFE3F1E1);
      case 'failed':
        return const Color(0xFFF5E1DE);
      case 'blocked':
        return const Color(0xFFF6E9D7);
      case 'running':
        return const Color(0xFFE3ECF6);
      case 'idle':
      case 'pending':
        return const Color(0xFFEEE9F2);
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  String _executionStatusLabel(ExecutionSession? session) {
    if (session == null) {
      return 'idle';
    }
    return switch (session.status) {
      ExecutionSessionStatus.succeeded => 'succeeded',
      ExecutionSessionStatus.failed => 'failed',
      ExecutionSessionStatus.blocked => 'blocked',
      ExecutionSessionStatus.running => 'running',
    };
  }

  String _dependencyStatusLabel(DependencySourceCommandResult? result) {
    if (result == null) {
      return 'idle';
    }
    return switch (result.status) {
      DependencySourceCommandStatus.succeeded => 'succeeded',
      DependencySourceCommandStatus.failed => 'failed',
      DependencySourceCommandStatus.blocked => 'blocked',
    };
  }

  String _toolchainStatusLabel(ToolchainCommandResult? result) {
    if (result == null) {
      return 'resolved';
    }
    return switch (result.status) {
      ToolchainCommandStatus.succeeded => 'succeeded',
      ToolchainCommandStatus.failed => 'failed',
      ToolchainCommandStatus.blocked => 'blocked',
    };
  }

  String _deploymentStatusLabel(DeploymentCommandResult? result) {
    if (result == null) {
      return 'ready';
    }
    return switch (result.status) {
      DeploymentCommandStatus.succeeded => 'succeeded',
      DeploymentCommandStatus.failed => 'failed',
      DeploymentCommandStatus.blocked => 'blocked',
    };
  }

  Widget _buildCommandChip(
    BuildContext context,
    ThemeData theme,
    AppCommandDescriptor command,
  ) {
    final blockedReason = shell.blockedReasonForCommand(command.id);
    return Tooltip(
      message: blockedReason ?? command.description,
      child: ActionChip(
        key: ValueKey('project-operation-${command.id.name}'),
        onPressed: blockedReason == null
            ? () => shell.executeCommand(command.id)
            : null,
        avatar: Icon(
          _commandIcon(command.id),
          size: 18,
          color: blockedReason == null
              ? theme.colorScheme.primary
              : theme.disabledColor,
        ),
        label: Text(command.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = shell.workspaceController.activeProject;
    final activeCompiler = project.activeCompiler;
    final distribution = project.packageDistribution;
    final publishablePackages = distribution?.publishablePackages ?? 0;
    final blockedPackages = distribution?.blockedPackages ?? 0;
    final blockedWorkflowPreview = _blockedWorkflowPreview();
    final lastToolchain = shell.lastToolchainCommand;
    final lastDeployment = shell.lastDeploymentCommand;
    final lastExecution = shell.lastExecutionSession;
    final lastDependency = shell.lastDependencySourceCommand;
    final executionStatus = _executionStatusLabel(lastExecution);
    final dependencyStatus = _dependencyStatusLabel(lastDependency);
    final toolchainStatus = _toolchainStatusLabel(lastToolchain);
    final deploymentStatus = _deploymentStatusLabel(lastDeployment);
    final deploymentPackage = _stringPayload(
      lastDeployment?.payload,
      'package',
    );
    final deploymentArchive = _stringPayload(
      lastDeployment?.payload,
      'archive_path',
    );
    final vendorMetadata = _stringPayload(
      lastDependency?.payload,
      'metadata_path',
    );
    final vendorRoot = _stringPayload(lastDependency?.payload, 'vendor_root');
    final dependencyPackages = lastDependency?.payload?['packages'];
    final managedInstalls =
        project.toolchainEnvironment?.managedToolchains.installed.length ?? 0;

    return DecoratedBox(
      key: const ValueKey('project-operations-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7F0),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project Workflow', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'One shell-owned surface for execution, dependency materialization, toolchain routing, and deployment preflight.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WorkflowStatusChip(
                  label: 'execution $executionStatus',
                  color: _laneColor(context, executionStatus),
                ),
                _WorkflowStatusChip(
                  label: 'dependencies $dependencyStatus',
                  color: _laneColor(context, dependencyStatus),
                ),
                _WorkflowStatusChip(
                  label: 'environment $toolchainStatus',
                  color: _laneColor(context, toolchainStatus),
                ),
                _WorkflowStatusChip(
                  label: 'deployment $deploymentStatus',
                  color: _laneColor(context, deploymentStatus),
                ),
                Chip(
                  label: Text(
                    activeCompiler == null
                        ? 'compiler unresolved'
                        : 'compiler ${activeCompiler.compilerVersion}',
                  ),
                ),
                Chip(
                  label: Text(
                    project.toolchainPinPath == null
                        ? 'pin unresolved'
                        : 'pin active',
                  ),
                ),
                Chip(label: Text('publishable $publishablePackages')),
                Chip(label: Text('blocked $blockedPackages')),
                Chip(
                  label: Text(
                    'workflow blockers ${StyioCommandRegistry.workflowCommands.where((command) => shell.blockedReasonForCommand(command.id) != null).length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (blockedWorkflowPreview.isNotEmpty) ...[
              Text('Current Blockers', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final blocker in blockedWorkflowPreview) ...[
                Text(blocker, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: 8),
            ],
            _WorkflowLanePanel(
              title: 'Execution',
              statusLabel: executionStatus,
              statusColor: _laneColor(context, executionStatus),
              detail: lastExecution == null
                  ? 'Run has not been routed through the active project shell yet.'
                  : '${lastExecution.kind} ${lastExecution.status.name}: ${lastExecution.statusMessage}',
              metaLabels: [
                'runtime ${shell.lastRuntimeEvents.length}',
                if (lastExecution != null) ...[
                  'diagnostics ${lastExecution.diagnostics.length}',
                  'stdout ${lastExecution.stdoutEvents.length}',
                  'stderr ${lastExecution.stderrEvents.length}',
                ],
              ],
              actions: StyioCommandRegistry.executionCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _WorkflowLanePanel(
              title: 'Dependencies',
              statusLabel: dependencyStatus,
              statusColor: _laneColor(context, dependencyStatus),
              detail: lastDependency == null
                  ? 'Fetch/vendor has not been materialized in this shell session yet.'
                  : '${lastDependency.command} ${lastDependency.status.name}: ${lastDependency.statusMessage}',
              metaLabels: [
                'git ${project.sourceState?.declaredGitDependencies ?? 0}',
                'registry ${project.sourceState?.declaredRegistryDependencies ?? 0}',
                'vendor ${project.vendorState.label}',
                if (dependencyPackages is num)
                  'packages ${dependencyPackages.toInt()}',
                if (vendorRoot != null) 'vendor root',
                if (vendorMetadata != null) 'vendor metadata',
              ],
              actions: StyioCommandRegistry.dependencyCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _WorkflowLanePanel(
              title: 'Environment',
              statusLabel: toolchainStatus,
              statusColor: _laneColor(context, toolchainStatus),
              detail: lastToolchain == null
                  ? project.toolchain.detail
                  : '${lastToolchain.command} ${lastToolchain.status.name}: ${lastToolchain.statusMessage}',
              metaLabels: [
                'source ${project.toolchain.source.label}',
                'managed $managedInstalls',
                if (activeCompiler != null) 'channel ${activeCompiler.channel}',
                if (project.toolchainPinPath != null) 'pin present',
              ],
              actions: StyioCommandRegistry.toolchainCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _WorkflowLanePanel(
              title: 'Deployment',
              statusLabel: deploymentStatus,
              statusColor: _laneColor(context, deploymentStatus),
              detail: lastDeployment == null
                  ? 'Pack and publish preflight are ready to route through the active project shell.'
                  : '${lastDeployment.command} ${lastDeployment.status.name}: ${lastDeployment.statusMessage}',
              metaLabels: [
                'packages ${distribution?.packages.length ?? 0}',
                'publishable $publishablePackages',
                'blocked $blockedPackages',
                if (deploymentPackage != null) 'package $deploymentPackage',
                if (deploymentArchive != null) 'archive ready',
              ],
              actions: StyioCommandRegistry.deploymentCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowLanePanel extends StatelessWidget {
  const _WorkflowLanePanel({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.detail,
    required this.metaLabels,
    required this.actions,
  });

  final String title;
  final String statusLabel;
  final Color statusColor;
  final String detail;
  final List<String> metaLabels;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                _WorkflowStatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(detail, style: theme.textTheme.bodySmall),
            if (metaLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metaLabels
                    .map((label) => Chip(label: Text(label)))
                    .toList(growable: false),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowStatusChip extends StatelessWidget {
  const _WorkflowStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

class _WorkspaceSearchSurface extends StatefulWidget {
  const _WorkspaceSearchSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceSearchSurface> createState() =>
      _WorkspaceSearchSurfaceState();
}

class _WorkspaceSearchSurfaceState extends State<_WorkspaceSearchSurface> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _includeController = TextEditingController(
    text: '**/*.styio',
  );
  final TextEditingController _excludeController = TextEditingController();
  bool _literal = true;
  bool _caseSensitive = false;
  bool _searching = false;

  @override
  void dispose() {
    _queryController.dispose();
    _includeController.dispose();
    _excludeController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    if (_searching) {
      return;
    }
    setState(() {
      _searching = true;
    });
    await widget.shell.searchWorkspaceText(
      WorkspaceTextSearchQuery(
        pattern: _queryController.text,
        literal: _literal,
        caseSensitive: _caseSensitive,
        includeGlobs: _splitGlobs(_includeController.text),
        excludeGlobs: _splitGlobs(_excludeController.text),
        maxResults: 100,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _searching = false;
    });
  }

  List<String> _splitGlobs(String value) {
    return value
        .split(RegExp(r'[,\n]'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.shell.lastWorkspaceSearch;
    final compact = widget.viewportProfile.isMobile;

    return Card(
      key: const ValueKey('workspace-search-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Find in Files',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Chip(
                    label: Text(
                      '${widget.shell.workspaceController.files.length} files',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              compact
                  ? Column(
                      children: _searchInputs(compact: true),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _searchInputs(compact: false),
                    ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    key: const ValueKey('workspace-search-literal-mode'),
                    selected: _literal,
                    label: const Text('Literal'),
                    onSelected: (selected) {
                      setState(() {
                        _literal = selected || !_literal;
                      });
                    },
                  ),
                  FilterChip(
                    key: const ValueKey('workspace-search-regex-mode'),
                    selected: !_literal,
                    label: const Text('Regex'),
                    onSelected: (selected) {
                      setState(() {
                        _literal = !selected;
                      });
                    },
                  ),
                  FilterChip(
                    key: const ValueKey('workspace-search-case-sensitive'),
                    selected: _caseSensitive,
                    label: const Text('Match case'),
                    onSelected: (selected) {
                      setState(() {
                        _caseSensitive = selected;
                      });
                    },
                  ),
                  FilledButton.icon(
                    key: const ValueKey('workspace-search-run'),
                    onPressed: _searching
                        ? null
                        : () {
                            _runSearch();
                          },
                    icon: Icon(
                      _searching
                          ? Icons.hourglass_top_rounded
                          : Icons.manage_search_rounded,
                    ),
                    label: Text(_searching ? 'Searching' : 'Search'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WorkspaceSearchResultView(
                result: result,
                onOpenMatch: widget.shell.openWorkspaceSearchMatch,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _searchInputs({required bool compact}) {
    final queryField = TextField(
      key: const ValueKey('workspace-search-query-field'),
      controller: _queryController,
      decoration: const InputDecoration(
        labelText: 'Search',
        prefixIcon: Icon(Icons.search_rounded),
      ),
      onSubmitted: (_) {
        _runSearch();
      },
    );
    final includeField = TextField(
      key: const ValueKey('workspace-search-include-field'),
      controller: _includeController,
      decoration: const InputDecoration(labelText: 'Include'),
      onSubmitted: (_) {
        _runSearch();
      },
    );
    final excludeField = TextField(
      key: const ValueKey('workspace-search-exclude-field'),
      controller: _excludeController,
      decoration: const InputDecoration(labelText: 'Exclude'),
      onSubmitted: (_) {
        _runSearch();
      },
    );

    if (compact) {
      return [
        queryField,
        const SizedBox(height: 10),
        includeField,
        const SizedBox(height: 10),
        excludeField,
      ];
    }

    return [
      Expanded(flex: 3, child: queryField),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: includeField),
      const SizedBox(width: 10),
      Expanded(flex: 2, child: excludeField),
    ];
  }
}

class _WorkspaceSearchResultView extends StatelessWidget {
  const _WorkspaceSearchResultView({
    required this.result,
    required this.onOpenMatch,
  });

  final WorkspaceTextSearchResult? result;
  final Future<void> Function(WorkspaceTextSearchMatch match) onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchResult = result;
    if (searchResult == null) {
      return Text(
        'No search results yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (searchResult.status) {
      WorkspaceTextSearchStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceTextSearchStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceTextSearchStatus.emptyPattern => const Color(0xFFEEE9F2),
      WorkspaceTextSearchStatus.invalidPattern => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (searchResult.status) {
      WorkspaceTextSearchStatus.completed => 'completed',
      WorkspaceTextSearchStatus.hitLimit => 'limited',
      WorkspaceTextSearchStatus.emptyPattern => 'empty',
      WorkspaceTextSearchStatus.invalidPattern => 'invalid',
    };

    return Column(
      key: const ValueKey('workspace-search-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${searchResult.matchCount} matches')),
            Chip(label: Text('${searchResult.matchedFileCount} files')),
            Chip(label: Text('${searchResult.filesSearched} scanned')),
          ],
        ),
        if (searchResult.message != null) ...[
          const SizedBox(height: 8),
          Text(searchResult.message!, style: theme.textTheme.bodySmall),
        ],
        if (searchResult.matches.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final match in searchResult.matches.take(40)) ...[
            _WorkspaceSearchMatchTile(
              match: match,
              onTap: () {
                onOpenMatch(match);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceSearchMatchTile extends StatelessWidget {
  const _WorkspaceSearchMatchTile({
    required this.match,
    required this.onTap,
  });

  final WorkspaceTextSearchMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey(
        'workspace-search-match-${match.filePath}-${match.range.start}',
      ),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F4ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.manage_search_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${match.filePath}:${match.line + 1}:${match.column + 1}',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    match.previewText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequiredHandoffTile extends StatelessWidget {
  const _RequiredHandoffTile({required this.handoff});

  final RequiredHandoff handoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(handoff.owner.label)),
                Chip(label: Text(handoff.blocking ? 'blocking' : 'follow-up')),
              ],
            ),
            const SizedBox(height: 8),
            Text(handoff.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(handoff.detail, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(handoff.docPath, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceFileTile extends StatelessWidget {
  const _WorkspaceFileTile({
    required this.file,
    required this.active,
    required this.onTap,
  });

  final String file;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF1ECE3) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.article_rounded : Icons.article_outlined,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(file, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _ProjectTargetTile extends StatelessWidget {
  const _ProjectTargetTile({
    required this.target,
    required this.active,
    required this.onTap,
  });

  final ProjectTargetDescriptor target;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF1ECE3) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.track_changes_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${target.kind.name} ${target.name}'),
                  Text(target.packageName, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectPackageTile extends StatelessWidget {
  const _ProjectPackageTile({required this.package});

  final ProjectPackageSnapshot package;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.packageName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Chip(label: Text(package.version)),
              ],
            ),
            const SizedBox(height: 6),
            Text(package.rootPath, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${package.targets.length} target')),
                Chip(label: Text('${package.dependencies.length} dependency')),
                Chip(
                  label: Text(
                    package.isWorkspaceMember
                        ? 'workspace member'
                        : 'root package',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceMemberTile extends StatelessWidget {
  const _WorkspaceMemberTile({required this.memberPath});

  final String memberPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3EA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.folder_open_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(memberPath, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectDependencyTile extends StatelessWidget {
  const _ProjectDependencyTile({required this.dependency});

  final ProjectDependencySnapshot dependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(dependency.kind.label)),
                if (dependency.isWorkspaceReference)
                  const Chip(label: Text('workspace ref')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${dependency.sourcePackageName} -> ${dependency.dependencyName}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(dependency.requirement, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ModuleSidebar extends StatelessWidget {
  const _ModuleSidebar({required this.shell});

  final ShellModel shell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            Text('Adapter Routes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Product-owned capability surface across CLI, FFI, and Cloud adapters.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final capability in shell.adapterCapabilities)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AdapterCapabilityTile(capability: capability),
              ),
            const SizedBox(height: 8),
            Text('Module Host', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Capability matrix filtered for ${shell.platformTarget.label}.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < shell.visibleModules.length; index += 1)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == shell.visibleModules.length - 1 ? 0 : 10,
                ),
                child: _ModuleTile(
                  module: shell.visibleModules[index],
                  mounted: shell.visibleModules[index].isMountedOn(
                    shell.platformTarget,
                  ),
                  platformTarget: shell.platformTarget,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdapterCapabilityTile extends StatelessWidget {
  const _AdapterCapabilityTile({required this.capability});

  final AdapterCapabilitySnapshot capability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              capability.adapterKind.label,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'language ${capability.languageService.level.label} · project ${capability.projectGraph.level.label}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'execution ${capability.execution.level.label} · runtime ${capability.runtimeEvents.level.label}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(capability.execution.detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BottomSurfaceTabs extends StatelessWidget {
  const _BottomSurfaceTabs({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <Widget>[
      _SurfaceTabChip(
        label: 'Runtime',
        active: shell.activeBottomTab == BottomSurfaceTab.runtime,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.runtime),
      ),
      _SurfaceTabChip(
        label: 'Search',
        active: shell.activeBottomTab == BottomSurfaceTab.search,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.search),
      ),
      _SurfaceTabChip(
        label: 'Agent',
        active: shell.activeBottomTab == BottomSurfaceTab.agent,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.agent),
      ),
      _SurfaceTabChip(
        label: 'Debug',
        active: shell.activeBottomTab == BottomSurfaceTab.debug,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.debug),
      ),
      if (viewportProfile.isMobile)
        _SurfaceTabChip(
          label: 'Settings',
          active: shell.activeBottomTab == BottomSurfaceTab.settings,
          onTap: () => shell.selectBottomTab(BottomSurfaceTab.settings),
        ),
    ];

    if (viewportProfile.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 10, runSpacing: 10, children: tabs),
          const SizedBox(height: 8),
          Text(
            'Mobile shell keeps runtime, search, agent, debug, and settings on one vertical route.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 10),
            tabs[index],
          ],
          const SizedBox(width: 16),
          for (final command in StyioCommandRegistry.primaryCommands)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message:
                    shell.blockedReasonForCommand(command.id) ??
                    '${command.description} (${command.shortcutHint})',
                child: ActionChip(
                  key: ValueKey('command-strip-${command.id.name}'),
                  onPressed: shell.blockedReasonForCommand(command.id) == null
                      ? () => shell.executeCommand(command.id)
                      : null,
                  avatar: Icon(
                    _commandIcon(command.id),
                    size: 18,
                    color: shell.blockedReasonForCommand(command.id) == null
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                  ),
                  label: Text('${command.label} · ${command.shortcutHint}'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: 'Open settings and profile routes. (Cmd/Ctrl+,)',
              child: ActionChip(
                key: const ValueKey('command-strip-openSettings'),
                onPressed: () =>
                    shell.executeCommand(AppCommandId.openSettings),
                avatar: Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                label: const Text('Settings · Cmd/Ctrl+,'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _commandIcon(AppCommandId commandId) {
  switch (commandId) {
    case AppCommandId.run:
      return Icons.play_arrow_rounded;
    case AppCommandId.searchWorkspace:
      return Icons.manage_search_rounded;
    case AppCommandId.fetchDependencies:
      return Icons.cloud_download_rounded;
    case AppCommandId.vendorDependencies:
      return Icons.inventory_2_rounded;
    case AppCommandId.useActiveCompiler:
      return Icons.sync_alt_rounded;
    case AppCommandId.pinActiveCompiler:
      return Icons.push_pin_outlined;
    case AppCommandId.clearPinnedCompiler:
      return Icons.push_pin_rounded;
    case AppCommandId.packProject:
      return Icons.archive_rounded;
    case AppCommandId.preparePublish:
      return Icons.publish_rounded;
    case AppCommandId.refreshModules:
      return Icons.refresh_rounded;
    case AppCommandId.save:
      return Icons.save_rounded;
    case AppCommandId.showRuntime:
      return Icons.terminal_rounded;
    case AppCommandId.showAgent:
      return Icons.smart_toy_outlined;
    case AppCommandId.showDebug:
      return Icons.bug_report_outlined;
    case AppCommandId.openSettings:
      return Icons.settings_outlined;
  }
}

class _SurfaceTabChip extends StatelessWidget {
  const _SurfaceTabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFE7DA) : const Color(0xFFF7F2E9),
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(label),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.mounted,
    required this.platformTarget,
  });

  final ModuleDefinition module;
  final bool mounted;
  final PlatformTarget platformTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rule = module.ruleFor(platformTarget);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: mounted ? const Color(0xFFF3ECDD) : const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    module.manifest.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(mounted ? 'Mounted' : 'Visible')),
              ],
            ),
            const SizedBox(height: 8),
            Text(module.manifest.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(module.manifest.kind.wireValue)),
                Chip(label: Text(module.manifest.slot.wireValue)),
                Chip(label: Text(rule.distributionChannel)),
              ],
            ),
            const SizedBox(height: 10),
            Text(rule.note, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
