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
import '../../view_ide/language/language.dart'
    show DiagnosticSeverity, StyioProjectSymbolKind, SymbolKind;
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
      case BottomSurfaceTab.commands:
        return _CommandPaletteSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.navigate:
        return _WorkspaceQuickOpenSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.definitions:
        return _WorkspaceDefinitionSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.rename:
        return _WorkspaceRenameSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.symbols:
        return _WorkspaceSymbolSearchSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.usages:
        return _WorkspaceReferenceSearchSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.calls:
        return _WorkspaceCallHierarchySurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.search:
        return _WorkspaceSearchSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.problems:
        return _WorkspaceProblemsSurface(
          shell: shell,
          viewportProfile: viewportProfile,
        );
      case BottomSurfaceTab.actions:
        return _WorkspaceCodeActionsSurface(
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

class _CommandPaletteSurface extends StatefulWidget {
  const _CommandPaletteSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_CommandPaletteSurface> createState() => _CommandPaletteSurfaceState();
}

class _CommandPaletteSurfaceState extends State<_CommandPaletteSurface> {
  final TextEditingController _queryController = TextEditingController();
  CommandPaletteResult? _result;

  @override
  void initState() {
    super.initState();
    _result = _runCommandPalette();
    _queryController.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  CommandPaletteResult _runCommandPalette() {
    return widget.shell.searchCommandPalette(
      CommandPaletteQuery(pattern: _queryController.text, maxResults: 80),
    );
  }

  void _handleQueryChanged() {
    setState(() {
      _result = _runCommandPalette();
    });
  }

  Future<void> _executeItem(CommandPaletteItem item) async {
    await widget.shell.executeCommandPaletteItem(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = _runCommandPalette();
    });
  }

  CommandPaletteItem? _firstEnabledItem(CommandPaletteResult? result) {
    if (result == null) {
      return null;
    }
    for (final item in result.items) {
      if (item.enabled) {
        return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastCommandPalette;
    final headerChips = <Widget>[
      Chip(label: Text('${widget.shell.recentCommandIds.length} recent')),
      Chip(label: Text('${StyioCommandRegistry.commands.length} commands')),
    ];

    return Card(
      key: const ValueKey('command-palette-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Command Palette',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Command Palette',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('command-palette-query-field'),
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Command name',
                  prefixIcon: Icon(Icons.keyboard_command_key_rounded),
                ),
                onSubmitted: (_) {
                  final firstItem = _firstEnabledItem(result);
                  if (firstItem != null) {
                    _executeItem(firstItem);
                  }
                },
              ),
              const SizedBox(height: 14),
              _CommandPaletteResultView(
                result: result,
                onExecuteItem: _executeItem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandPaletteResultView extends StatelessWidget {
  const _CommandPaletteResultView({
    required this.result,
    required this.onExecuteItem,
  });

  final CommandPaletteResult? result;
  final Future<void> Function(CommandPaletteItem item) onExecuteItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final commandResult = result;
    if (commandResult == null) {
      return Text('No commands indexed yet.', style: theme.textTheme.bodySmall);
    }

    final statusColor = switch (commandResult.status) {
      CommandPaletteStatus.completed => const Color(0xFFE3F1E1),
      CommandPaletteStatus.hitLimit => const Color(0xFFF6E9D7),
      CommandPaletteStatus.noCommands => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (commandResult.status) {
      CommandPaletteStatus.completed => 'ready',
      CommandPaletteStatus.hitLimit => 'limited',
      CommandPaletteStatus.noCommands => 'empty',
    };

    return Column(
      key: const ValueKey('command-palette-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${commandResult.matchCount} matches')),
            Chip(label: Text('${commandResult.commandsSearched} indexed')),
            if (commandResult.blockedCount > 0)
              Chip(label: Text('${commandResult.blockedCount} blocked')),
          ],
        ),
        if (commandResult.items.isEmpty) ...[
          const SizedBox(height: 10),
          Text('No matching commands.', style: theme.textTheme.bodySmall),
        ],
        if (commandResult.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in commandResult.items.take(60)) ...[
            _CommandPaletteItemTile(
              item: item,
              onTap: () {
                onExecuteItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _CommandPaletteItemTile extends StatelessWidget {
  const _CommandPaletteItemTile({required this.item, required this.onTap});

  final CommandPaletteItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = item.enabled
        ? theme.colorScheme.primary
        : theme.disabledColor;
    return InkWell(
      key: ValueKey('command-palette-item-${item.commandId.name}'),
      borderRadius: BorderRadius.circular(12),
      onTap: item.enabled ? onTap : null,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: item.enabled
              ? const Color(0xFFF8F4ED)
              : const Color(0xFFF2EEE8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_commandIcon(item.commandId), size: 18, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      Chip(label: Text(item.category)),
                      Chip(label: Text(item.shortcutHint)),
                      if (item.isRecent)
                        Chip(label: Text('recent ${item.recentRank! + 1}')),
                      if (!item.enabled) const Chip(label: Text('blocked')),
                    ],
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

class _WorkspaceQuickOpenSurface extends StatefulWidget {
  const _WorkspaceQuickOpenSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceQuickOpenSurface> createState() =>
      _WorkspaceQuickOpenSurfaceState();
}

class _WorkspaceQuickOpenSurfaceState
    extends State<_WorkspaceQuickOpenSurface> {
  final TextEditingController _queryController = TextEditingController();
  WorkspaceQuickOpenResult? _result;

  @override
  void initState() {
    super.initState();
    _result = _runQuickOpen();
    _queryController.addListener(_handleQueryChanged);
  }

  @override
  void dispose() {
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  WorkspaceQuickOpenResult _runQuickOpen() {
    return widget.shell.quickOpenWorkspace(
      WorkspaceQuickOpenQuery(pattern: _queryController.text, maxResults: 80),
    );
  }

  void _handleQueryChanged() {
    setState(() {
      _result = _runQuickOpen();
    });
  }

  Future<void> _openItem(WorkspaceQuickOpenItem item) async {
    await widget.shell.openWorkspaceQuickOpenItem(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = _runQuickOpen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceQuickOpen;
    final headerChips = <Widget>[
      Chip(
        label: Text(
          '${widget.shell.workspaceController.recentFiles.length} recent',
        ),
      ),
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
    ];

    return Card(
      key: const ValueKey('workspace-quick-open-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Open',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Quick Open',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-quick-open-query-field'),
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'File name or path',
                  prefixIcon: Icon(Icons.drive_file_move_outline),
                ),
                onSubmitted: (_) {
                  final firstItem =
                      result != null && result.items.isNotEmpty
                      ? result.items.first
                      : null;
                  if (firstItem != null) {
                    _openItem(firstItem);
                  }
                },
              ),
              const SizedBox(height: 14),
              _WorkspaceQuickOpenResultView(
                result: result,
                activeFilePath: widget.shell.workspaceController.activeFilePath,
                onOpenItem: _openItem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceQuickOpenResultView extends StatelessWidget {
  const _WorkspaceQuickOpenResultView({
    required this.result,
    required this.activeFilePath,
    required this.onOpenItem,
  });

  final WorkspaceQuickOpenResult? result;
  final String activeFilePath;
  final Future<void> Function(WorkspaceQuickOpenItem item) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quickOpenResult = result;
    if (quickOpenResult == null) {
      return Text('No files indexed yet.', style: theme.textTheme.bodySmall);
    }

    final statusColor = switch (quickOpenResult.status) {
      WorkspaceQuickOpenStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceQuickOpenStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceQuickOpenStatus.emptyWorkspace => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (quickOpenResult.status) {
      WorkspaceQuickOpenStatus.completed => 'ready',
      WorkspaceQuickOpenStatus.hitLimit => 'limited',
      WorkspaceQuickOpenStatus.emptyWorkspace => 'empty',
    };

    return Column(
      key: const ValueKey('workspace-quick-open-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${quickOpenResult.matchCount} matches')),
            Chip(label: Text('${quickOpenResult.filesSearched} indexed')),
          ],
        ),
        if (quickOpenResult.items.isEmpty) ...[
          const SizedBox(height: 10),
          Text('No matching files.', style: theme.textTheme.bodySmall),
        ],
        if (quickOpenResult.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in quickOpenResult.items.take(60)) ...[
            _WorkspaceQuickOpenItemTile(
              item: item,
              active: item.filePath == activeFilePath,
              onTap: () {
                onOpenItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceQuickOpenItemTile extends StatelessWidget {
  const _WorkspaceQuickOpenItemTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final WorkspaceQuickOpenItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey('workspace-quick-open-item-${item.filePath}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEAF2EA) : const Color(0xFFF8F4ED),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.article_rounded : Icons.article_outlined,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.fileName,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.parentPath.isEmpty ? item.filePath : item.parentPath,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (item.isRecent) ...[
              const SizedBox(width: 8),
              Chip(label: Text('recent ${item.recentRank! + 1}')),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceDefinitionSurface extends StatefulWidget {
  const _WorkspaceDefinitionSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceDefinitionSurface> createState() =>
      _WorkspaceDefinitionSurfaceState();
}

class _WorkspaceDefinitionSurfaceState
    extends State<_WorkspaceDefinitionSurface> {
  late final TextEditingController _queryController;
  WorkspaceDefinitionResult? _result;
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: widget.shell.workspaceDefinitionQuerySeed,
    );
    if (_queryController.text.isNotEmpty) {
      _runSearch();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final generation = _searchGeneration + 1;
    _searchGeneration = generation;
    setState(() {
      _searching = true;
    });
    final result = await widget.shell.findWorkspaceDefinitions(
      WorkspaceDefinitionQuery(
        pattern: _queryController.text,
        maxResults: 80,
      ),
    );
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  Future<void> _openItem(WorkspaceDefinitionItem item) async {
    await widget.shell.openWorkspaceDefinition(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = widget.shell.lastWorkspaceDefinition;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceDefinition;
    final headerChips = <Widget>[
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
      if (_searching) const Chip(label: Text('indexing')),
    ];

    return Card(
      key: const ValueKey('workspace-definition-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Go to Definition',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Go to Definition',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-definition-query-field'),
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Symbol name',
                  prefixIcon: Icon(Icons.subdirectory_arrow_right_rounded),
                ),
                onSubmitted: (_) {
                  _runSearch();
                },
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('workspace-definition-search-run'),
                onPressed: _searching
                    ? null
                    : () {
                        _runSearch();
                      },
                icon: Icon(
                  _searching
                      ? Icons.hourglass_top_rounded
                      : Icons.subdirectory_arrow_right_rounded,
                ),
                label: Text(_searching ? 'Resolving' : 'Resolve'),
              ),
              const SizedBox(height: 14),
              _WorkspaceDefinitionResultView(
                result: result,
                onOpenItem: _openItem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceDefinitionResultView extends StatelessWidget {
  const _WorkspaceDefinitionResultView({
    required this.result,
    required this.onOpenItem,
  });

  final WorkspaceDefinitionResult? result;
  final Future<void> Function(WorkspaceDefinitionItem item) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final definitionResult = result;
    if (definitionResult == null) {
      return Text(
        'No definitions queried yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (definitionResult.status) {
      WorkspaceDefinitionStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceDefinitionStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceDefinitionStatus.emptyPattern => const Color(0xFFEEE9F2),
      WorkspaceDefinitionStatus.emptyWorkspace => const Color(0xFFF5E1DE),
      WorkspaceDefinitionStatus.noDefinitions => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (definitionResult.status) {
      WorkspaceDefinitionStatus.completed => 'completed',
      WorkspaceDefinitionStatus.hitLimit => 'limited',
      WorkspaceDefinitionStatus.emptyPattern => 'empty',
      WorkspaceDefinitionStatus.emptyWorkspace => 'empty',
      WorkspaceDefinitionStatus.noDefinitions => 'no symbol',
    };

    return Column(
      key: const ValueKey('workspace-definition-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${definitionResult.matchCount} definitions')),
            Chip(label: Text('${definitionResult.matchedFileCount} files')),
            Chip(
              label: Text('${definitionResult.definitionsIndexed} indexed'),
            ),
            Chip(label: Text('${definitionResult.filesSearched} files')),
          ],
        ),
        if (definitionResult.message case final message?) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (definitionResult.definitions.isEmpty &&
            definitionResult.message == null) ...[
          const SizedBox(height: 10),
          Text('No matching definitions.', style: theme.textTheme.bodySmall),
        ],
        if (definitionResult.definitions.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in definitionResult.definitions.take(60)) ...[
            _WorkspaceDefinitionItemTile(
              item: item,
              onTap: () {
                onOpenItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceDefinitionItemTile extends StatelessWidget {
  const _WorkspaceDefinitionItemTile({
    required this.item,
    required this.onTap,
  });

  final WorkspaceDefinitionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey(
        'workspace-definition-item-${item.filePath}-${item.range.start}',
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.filePath}:${item.line + 1}:${item.column + 1}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (item.previewText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.previewText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            );
            final badges = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(item.kindLabel)),
                if (item.type case final type?) Chip(label: Text(type)),
              ],
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_workspaceReferenceKindIcon(item.kind), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            details,
                            const SizedBox(height: 8),
                            badges,
                          ],
                        )
                      : details,
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: badges,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceRenameSurface extends StatefulWidget {
  const _WorkspaceRenameSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceRenameSurface> createState() => _WorkspaceRenameSurfaceState();
}

class _WorkspaceRenameSurfaceState extends State<_WorkspaceRenameSurface> {
  late final TextEditingController _nameController;
  WorkspaceRenameResult? _result;
  WorkspaceRenameApplyResult? _applyResult;
  bool _previewing = false;
  bool _applying = false;
  int _previewGeneration = 0;

  @override
  void initState() {
    super.initState();
    final seed = widget.shell.workspaceRenameQuerySeed;
    _nameController = TextEditingController(
      text: seed.isEmpty ? '' : '${seed}_next',
    );
    if (seed.isNotEmpty) {
      _runPreview();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  WorkspaceRenameQuery _query() {
    return WorkspaceRenameQuery(
      targetFilePath: widget.shell.workspaceRenameTargetFilePath,
      targetOffset: widget.shell.workspaceRenameTargetOffset,
      newName: _nameController.text,
    );
  }

  Future<void> _runPreview() async {
    final generation = _previewGeneration + 1;
    _previewGeneration = generation;
    setState(() {
      _previewing = true;
      _applyResult = null;
    });
    final result = await widget.shell.previewWorkspaceRename(_query());
    if (!mounted || generation != _previewGeneration) {
      return;
    }
    setState(() {
      _result = result;
      _previewing = false;
    });
  }

  Future<void> _applyRename() async {
    final preview = _result;
    if (preview == null || !preview.canApply || _applying) {
      return;
    }
    setState(() {
      _applying = true;
    });
    final result = await widget.shell.applyWorkspaceRename(
      preview.query.copyWith(newName: _nameController.text),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result.preview;
      _applyResult = result;
      _applying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result;
    final seed = widget.shell.workspaceRenameQuerySeed;
    final headerChips = <Widget>[
      Chip(label: Text(widget.shell.workspaceRenameTargetFilePath)),
      if (seed.isNotEmpty) Chip(label: Text(seed)),
      if (_previewing) const Chip(label: Text('previewing')),
      if (_applying) const Chip(label: Text('applying')),
    ];

    return Card(
      key: const ValueKey('workspace-rename-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rename Symbol',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Rename Symbol',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-rename-name-field'),
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'New symbol name',
                  prefixIcon: Icon(Icons.drive_file_rename_outline_rounded),
                ),
                onSubmitted: (_) {
                  _runPreview();
                },
                onChanged: (_) {
                  setState(() {
                    _result = null;
                    _applyResult = null;
                  });
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('workspace-rename-preview-run'),
                    onPressed: _previewing || _applying
                        ? null
                        : () {
                            _runPreview();
                          },
                    icon: Icon(
                      _previewing
                          ? Icons.hourglass_top_rounded
                          : Icons.manage_search_rounded,
                    ),
                    label: Text(_previewing ? 'Previewing' : 'Preview'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('workspace-rename-apply-run'),
                    onPressed: result != null &&
                            result.canApply &&
                            !_previewing &&
                            !_applying
                        ? _applyRename
                        : null,
                    icon: Icon(
                      _applying
                          ? Icons.hourglass_top_rounded
                          : Icons.done_rounded,
                    ),
                    label: Text(_applying ? 'Applying' : 'Apply'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WorkspaceRenameResultView(
                result: result,
                applyResult: _applyResult,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceRenameResultView extends StatelessWidget {
  const _WorkspaceRenameResultView({
    required this.result,
    required this.applyResult,
  });

  final WorkspaceRenameResult? result;
  final WorkspaceRenameApplyResult? applyResult;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renameResult = result;
    if (renameResult == null) {
      return Text(
        'No rename preview yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (renameResult.status) {
      WorkspaceRenameStatus.ready => const Color(0xFFE3F1E1),
      WorkspaceRenameStatus.noChanges => const Color(0xFFEEE9F2),
      WorkspaceRenameStatus.emptyWorkspace => const Color(0xFFF5E1DE),
      WorkspaceRenameStatus.noTarget => const Color(0xFFF5E1DE),
      WorkspaceRenameStatus.conflict => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (renameResult.status) {
      WorkspaceRenameStatus.ready => 'ready',
      WorkspaceRenameStatus.noChanges => 'no changes',
      WorkspaceRenameStatus.emptyWorkspace => 'empty',
      WorkspaceRenameStatus.noTarget => 'no symbol',
      WorkspaceRenameStatus.conflict => 'blocked',
    };

    return Column(
      key: const ValueKey('workspace-rename-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${renameResult.editCount} edits')),
            Chip(label: Text('${renameResult.matchedFileCount} files')),
            Chip(label: Text('${renameResult.filesSearched} indexed')),
            if (renameResult.oldName.isNotEmpty)
              Chip(
                label: Text(
                  '${renameResult.oldName} -> ${renameResult.newName}',
                ),
              ),
          ],
        ),
        if (renameResult.message case final message?) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (applyResult?.message case final message?) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (renameResult.edits.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final edit in renameResult.edits.take(80)) ...[
            _WorkspaceRenameEditTile(edit: edit),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceRenameEditTile extends StatelessWidget {
  const _WorkspaceRenameEditTile({required this.edit});

  final WorkspaceRenameEdit edit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Ink(
      key: ValueKey(
        'workspace-rename-edit-${edit.filePath}-${edit.range.start}',
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.drive_file_rename_outline_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${edit.filePath}:${edit.line + 1}:${edit.column + 1}',
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (edit.previewText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    edit.previewText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceSymbolSearchSurface extends StatefulWidget {
  const _WorkspaceSymbolSearchSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceSymbolSearchSurface> createState() =>
      _WorkspaceSymbolSearchSurfaceState();
}

class _WorkspaceSymbolSearchSurfaceState
    extends State<_WorkspaceSymbolSearchSurface> {
  final TextEditingController _queryController = TextEditingController();
  WorkspaceSymbolSearchResult? _result;
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_handleQueryChanged);
    _runSearch();
  }

  @override
  void dispose() {
    _queryController.removeListener(_handleQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _handleQueryChanged() {
    _runSearch();
  }

  Future<void> _runSearch() async {
    final generation = _searchGeneration + 1;
    _searchGeneration = generation;
    setState(() {
      _searching = true;
    });
    final result = await widget.shell.searchWorkspaceSymbols(
      WorkspaceSymbolSearchQuery(
        pattern: _queryController.text,
        maxResults: 100,
      ),
    );
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  Future<void> _openItem(WorkspaceSymbolSearchItem item) async {
    await widget.shell.openWorkspaceSymbol(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = widget.shell.lastWorkspaceSymbolSearch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceSymbolSearch;
    final headerChips = <Widget>[
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
      if (_searching) const Chip(label: Text('indexing')),
    ];

    return Card(
      key: const ValueKey('workspace-symbol-search-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Workspace Symbols',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Workspace Symbols',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-symbol-search-query-field'),
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Symbol name',
                  prefixIcon: Icon(Icons.account_tree_outlined),
                ),
                onSubmitted: (_) {
                  final firstItem =
                      result != null && result.items.isNotEmpty
                      ? result.items.first
                      : null;
                  if (firstItem != null) {
                    _openItem(firstItem);
                  }
                },
              ),
              const SizedBox(height: 14),
              _WorkspaceSymbolSearchResultView(
                result: result,
                onOpenItem: _openItem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceSymbolSearchResultView extends StatelessWidget {
  const _WorkspaceSymbolSearchResultView({
    required this.result,
    required this.onOpenItem,
  });

  final WorkspaceSymbolSearchResult? result;
  final Future<void> Function(WorkspaceSymbolSearchItem item) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbolResult = result;
    if (symbolResult == null) {
      return Text(
        'No symbols indexed yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (symbolResult.status) {
      WorkspaceSymbolSearchStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceSymbolSearchStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceSymbolSearchStatus.emptyWorkspace => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (symbolResult.status) {
      WorkspaceSymbolSearchStatus.completed => 'ready',
      WorkspaceSymbolSearchStatus.hitLimit => 'limited',
      WorkspaceSymbolSearchStatus.emptyWorkspace => 'empty',
    };

    return Column(
      key: const ValueKey('workspace-symbol-search-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${symbolResult.matchCount} matches')),
            Chip(label: Text('${symbolResult.matchedFileCount} files')),
            Chip(label: Text('${symbolResult.symbolsIndexed} symbols')),
            Chip(label: Text('${symbolResult.filesSearched} indexed')),
          ],
        ),
        if (symbolResult.items.isEmpty) ...[
          const SizedBox(height: 10),
          Text('No matching symbols.', style: theme.textTheme.bodySmall),
        ],
        if (symbolResult.items.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in symbolResult.items.take(50)) ...[
            _WorkspaceSymbolSearchItemTile(
              item: item,
              onTap: () {
                onOpenItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceSymbolSearchItemTile extends StatelessWidget {
  const _WorkspaceSymbolSearchItemTile({
    required this.item,
    required this.onTap,
  });

  final WorkspaceSymbolSearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey(
        'workspace-symbol-search-item-${item.filePath}-${item.nameRange.start}',
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
            Icon(_workspaceSymbolIcon(item.kind), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.filePath}:${item.line + 1}:${item.column + 1}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.previewText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.previewText,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Chip(label: Text(item.kindLabel)),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceReferenceSearchSurface extends StatefulWidget {
  const _WorkspaceReferenceSearchSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceReferenceSearchSurface> createState() =>
      _WorkspaceReferenceSearchSurfaceState();
}

class _WorkspaceReferenceSearchSurfaceState
    extends State<_WorkspaceReferenceSearchSurface> {
  final TextEditingController _queryController = TextEditingController();
  WorkspaceReferenceSearchResult? _result;
  bool _includeDefinitions = true;
  bool _searching = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final generation = _searchGeneration + 1;
    _searchGeneration = generation;
    setState(() {
      _searching = true;
    });
    final result = await widget.shell.findWorkspaceReferences(
      WorkspaceReferenceSearchQuery(
        pattern: _queryController.text,
        includeDefinitions: _includeDefinitions,
        maxResults: 120,
      ),
    );
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  Future<void> _openItem(WorkspaceReferenceSearchItem item) async {
    await widget.shell.openWorkspaceReference(item);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = widget.shell.lastWorkspaceReferenceSearch;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceReferenceSearch;
    final headerChips = <Widget>[
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
      if (_searching) const Chip(label: Text('indexing')),
    ];

    return Card(
      key: const ValueKey('workspace-reference-search-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Find Usages', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Find Usages',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-reference-search-query-field'),
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Symbol name',
                  prefixIcon: Icon(Icons.manage_search_rounded),
                ),
                onSubmitted: (_) {
                  _runSearch();
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    key: const ValueKey(
                      'workspace-reference-search-include-definitions',
                    ),
                    selected: _includeDefinitions,
                    label: const Text('Definitions'),
                    onSelected: (selected) {
                      setState(() {
                        _includeDefinitions = selected;
                      });
                      if (result != null) {
                        _runSearch();
                      }
                    },
                  ),
                  FilledButton.icon(
                    key: const ValueKey('workspace-reference-search-run'),
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
                    label: Text(_searching ? 'Finding' : 'Find'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WorkspaceReferenceSearchResultView(
                result: result,
                onOpenItem: _openItem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceReferenceSearchResultView extends StatelessWidget {
  const _WorkspaceReferenceSearchResultView({
    required this.result,
    required this.onOpenItem,
  });

  final WorkspaceReferenceSearchResult? result;
  final Future<void> Function(WorkspaceReferenceSearchItem item) onOpenItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final referenceResult = result;
    if (referenceResult == null) {
      return Text(
        'No usages queried yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (referenceResult.status) {
      WorkspaceReferenceSearchStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceReferenceSearchStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceReferenceSearchStatus.emptyPattern => const Color(0xFFEEE9F2),
      WorkspaceReferenceSearchStatus.emptyWorkspace => const Color(0xFFF5E1DE),
      WorkspaceReferenceSearchStatus.noDefinitions => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (referenceResult.status) {
      WorkspaceReferenceSearchStatus.completed => 'completed',
      WorkspaceReferenceSearchStatus.hitLimit => 'limited',
      WorkspaceReferenceSearchStatus.emptyPattern => 'empty',
      WorkspaceReferenceSearchStatus.emptyWorkspace => 'empty',
      WorkspaceReferenceSearchStatus.noDefinitions => 'no symbol',
    };

    return Column(
      key: const ValueKey('workspace-reference-search-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${referenceResult.matchCount} references')),
            Chip(label: Text('${referenceResult.matchedFileCount} files')),
            Chip(label: Text('${referenceResult.definitions.length} symbols')),
            Chip(label: Text('${referenceResult.filesSearched} indexed')),
          ],
        ),
        if (referenceResult.message case final message?) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (referenceResult.references.isEmpty &&
            referenceResult.message == null) ...[
          const SizedBox(height: 10),
          Text('No matching usages.', style: theme.textTheme.bodySmall),
        ],
        if (referenceResult.references.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final item in referenceResult.references.take(60)) ...[
            _WorkspaceReferenceSearchItemTile(
              item: item,
              onTap: () {
                onOpenItem(item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceReferenceSearchItemTile extends StatelessWidget {
  const _WorkspaceReferenceSearchItemTile({
    required this.item,
    required this.onTap,
  });

  final WorkspaceReferenceSearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey(
        'workspace-reference-search-item-${item.filePath}-${item.range.start}',
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
            Icon(_workspaceReferenceKindIcon(item.kind), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.filePath}:${item.line + 1}:${item.column + 1}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.previewText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.previewText,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(item.isDefinition ? 'definition' : 'usage')),
                Chip(label: Text(item.definition.kindLabel)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceCallHierarchySurface extends StatefulWidget {
  const _WorkspaceCallHierarchySurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceCallHierarchySurface> createState() =>
      _WorkspaceCallHierarchySurfaceState();
}

class _WorkspaceCallHierarchySurfaceState
    extends State<_WorkspaceCallHierarchySurface> {
  final TextEditingController _queryController = TextEditingController();
  WorkspaceCallHierarchyDirection _direction =
      WorkspaceCallHierarchyDirection.incoming;
  WorkspaceCallHierarchyResult? _result;
  bool _loading = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final generation = _searchGeneration + 1;
    _searchGeneration = generation;
    setState(() {
      _loading = true;
    });
    final result = await widget.shell.buildWorkspaceCallHierarchy(
      WorkspaceCallHierarchyQuery(
        pattern: _queryController.text,
        direction: _direction,
        maxResults: 120,
      ),
    );
    if (!mounted || generation != _searchGeneration) {
      return;
    }
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _openCall(WorkspaceCallHierarchyCall call) async {
    if (call.locations.isEmpty) {
      return;
    }
    await widget.shell.openWorkspaceCallHierarchyLocation(call.firstLocation);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = widget.shell.lastWorkspaceCallHierarchy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceCallHierarchy;
    final headerChips = <Widget>[
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
      if (_loading) const Chip(label: Text('indexing')),
    ];

    return Card(
      key: const ValueKey('workspace-call-hierarchy-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Call Hierarchy',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Call Hierarchy',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-call-hierarchy-query-field'),
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Callable symbol',
                  prefixIcon: Icon(Icons.account_tree_rounded),
                ),
                onSubmitted: (_) {
                  _runSearch();
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<WorkspaceCallHierarchyDirection>(
                    key: const ValueKey('workspace-call-hierarchy-direction'),
                    segments:
                        const <ButtonSegment<WorkspaceCallHierarchyDirection>>[
                      ButtonSegment<WorkspaceCallHierarchyDirection>(
                        value: WorkspaceCallHierarchyDirection.incoming,
                        icon: Icon(Icons.call_received_rounded),
                        label: Text('Incoming'),
                      ),
                      ButtonSegment<WorkspaceCallHierarchyDirection>(
                        value: WorkspaceCallHierarchyDirection.outgoing,
                        icon: Icon(Icons.call_made_rounded),
                        label: Text('Outgoing'),
                      ),
                    ],
                    selected: <WorkspaceCallHierarchyDirection>{_direction},
                    onSelectionChanged: (selection) {
                      final nextDirection = selection.first;
                      setState(() {
                        _direction = nextDirection;
                      });
                      if (result != null) {
                        _runSearch();
                      }
                    },
                  ),
                  FilledButton.icon(
                    key: const ValueKey('workspace-call-hierarchy-run'),
                    onPressed: _loading
                        ? null
                        : () {
                            _runSearch();
                          },
                    icon: Icon(
                      _loading
                          ? Icons.hourglass_top_rounded
                          : Icons.account_tree_rounded,
                    ),
                    label: Text(_loading ? 'Building' : 'Build'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WorkspaceCallHierarchyResultView(
                result: result,
                onOpenCall: _openCall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceCallHierarchyResultView extends StatelessWidget {
  const _WorkspaceCallHierarchyResultView({
    required this.result,
    required this.onOpenCall,
  });

  final WorkspaceCallHierarchyResult? result;
  final Future<void> Function(WorkspaceCallHierarchyCall call) onOpenCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hierarchyResult = result;
    if (hierarchyResult == null) {
      return Text(
        'No call hierarchy built yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (hierarchyResult.status) {
      WorkspaceCallHierarchyStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceCallHierarchyStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceCallHierarchyStatus.emptyPattern => const Color(0xFFEEE9F2),
      WorkspaceCallHierarchyStatus.emptyWorkspace => const Color(0xFFF5E1DE),
      WorkspaceCallHierarchyStatus.noDefinitions => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (hierarchyResult.status) {
      WorkspaceCallHierarchyStatus.completed => 'completed',
      WorkspaceCallHierarchyStatus.hitLimit => 'limited',
      WorkspaceCallHierarchyStatus.emptyPattern => 'empty',
      WorkspaceCallHierarchyStatus.emptyWorkspace => 'empty',
      WorkspaceCallHierarchyStatus.noDefinitions => 'no symbol',
    };
    final directionLabel =
        hierarchyResult.query.direction ==
            WorkspaceCallHierarchyDirection.incoming
        ? 'incoming'
        : 'outgoing';

    return Column(
      key: const ValueKey('workspace-call-hierarchy-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${hierarchyResult.callCount} nodes')),
            Chip(label: Text('${hierarchyResult.referenceCount} references')),
            Chip(label: Text('${hierarchyResult.filesSearched} indexed')),
            Chip(label: Text(directionLabel)),
          ],
        ),
        if (hierarchyResult.target case final target?) ...[
          const SizedBox(height: 10),
          _WorkspaceCallHierarchyTargetTile(symbol: target),
        ],
        if (hierarchyResult.message case final message?) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (hierarchyResult.calls.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final call in hierarchyResult.calls.take(60)) ...[
            _WorkspaceCallHierarchyCallTile(
              call: call,
              onTap: () {
                onOpenCall(call);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceCallHierarchyTargetTile extends StatelessWidget {
  const _WorkspaceCallHierarchyTargetTile({required this.symbol});

  final WorkspaceCallHierarchySymbol symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      key: const ValueKey('workspace-call-hierarchy-target'),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(_workspaceCallHierarchyKindIcon(symbol.kind), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbol.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${symbol.filePath}:${symbol.line + 1}:${symbol.column + 1}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Chip(label: Text(symbol.kindLabel)),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceCallHierarchyCallTile extends StatelessWidget {
  const _WorkspaceCallHierarchyCallTile({
    required this.call,
    required this.onTap,
  });

  final WorkspaceCallHierarchyCall call;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = call.firstLocation;
    return InkWell(
      key: ValueKey(
        'workspace-call-hierarchy-item-${call.symbol.filePath}-'
        '${call.symbol.range.start}-${location.range.start}',
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
            Icon(_workspaceCallHierarchyKindIcon(call.symbol.kind), size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    call.symbol.name,
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${location.filePath}:${location.line + 1}:${location.column + 1}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (location.previewText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      location.previewText,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(call.symbol.kindLabel)),
                Chip(label: Text('${call.referenceCount} ref')),
              ],
            ),
          ],
        ),
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

class _WorkspaceProblemsSurface extends StatefulWidget {
  const _WorkspaceProblemsSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceProblemsSurface> createState() =>
      _WorkspaceProblemsSurfaceState();
}

class _WorkspaceProblemsSurfaceState extends State<_WorkspaceProblemsSurface> {
  final TextEditingController _filterController = TextEditingController();
  Set<DiagnosticSeverity> _severities = const <DiagnosticSeverity>{
    DiagnosticSeverity.error,
    DiagnosticSeverity.warning,
    DiagnosticSeverity.hint,
  };
  WorkspaceProblemsResult? _result;
  bool _loading = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _runCollection();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _runCollection() async {
    final generation = _generation + 1;
    _generation = generation;
    setState(() {
      _loading = true;
    });
    final result = await widget.shell.collectWorkspaceProblems(
      WorkspaceProblemsQuery(
        pattern: _filterController.text,
        severities: _severities,
        maxResults: 200,
      ),
    );
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  Future<void> _openProblem(WorkspaceProblemItem problem) async {
    await widget.shell.openWorkspaceProblem(problem);
    if (!mounted) {
      return;
    }
    setState(() {
      _result = widget.shell.lastWorkspaceProblems;
    });
  }

  void _toggleSeverity(DiagnosticSeverity severity, bool selected) {
    final next = <DiagnosticSeverity>{..._severities};
    if (selected) {
      next.add(severity);
    } else {
      next.remove(severity);
    }
    setState(() {
      _severities = next;
    });
    _runCollection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceProblems;
    final headerChips = <Widget>[
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
      if (_loading) const Chip(label: Text('analyzing')),
    ];

    return Card(
      key: const ValueKey('workspace-problems-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Problems', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Problems',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-problems-filter-field'),
                controller: _filterController,
                decoration: const InputDecoration(
                  labelText: 'Filter',
                  prefixIcon: Icon(Icons.filter_list_rounded),
                ),
                onSubmitted: (_) {
                  _runCollection();
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    key: const ValueKey('workspace-problems-errors'),
                    selected: _severities.contains(DiagnosticSeverity.error),
                    label: const Text('Errors'),
                    onSelected: (selected) {
                      _toggleSeverity(DiagnosticSeverity.error, selected);
                    },
                  ),
                  FilterChip(
                    key: const ValueKey('workspace-problems-warnings'),
                    selected: _severities.contains(DiagnosticSeverity.warning),
                    label: const Text('Warnings'),
                    onSelected: (selected) {
                      _toggleSeverity(DiagnosticSeverity.warning, selected);
                    },
                  ),
                  FilterChip(
                    key: const ValueKey('workspace-problems-hints'),
                    selected: _severities.contains(DiagnosticSeverity.hint),
                    label: const Text('Hints'),
                    onSelected: (selected) {
                      _toggleSeverity(DiagnosticSeverity.hint, selected);
                    },
                  ),
                  FilledButton.icon(
                    key: const ValueKey('workspace-problems-refresh'),
                    onPressed: _loading
                        ? null
                        : () {
                            _runCollection();
                          },
                    icon: Icon(
                      _loading
                          ? Icons.hourglass_top_rounded
                          : Icons.refresh_rounded,
                    ),
                    label: Text(_loading ? 'Analyzing' : 'Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WorkspaceProblemsResultView(
                result: result,
                onOpenProblem: _openProblem,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceProblemsResultView extends StatelessWidget {
  const _WorkspaceProblemsResultView({
    required this.result,
    required this.onOpenProblem,
  });

  final WorkspaceProblemsResult? result;
  final Future<void> Function(WorkspaceProblemItem problem) onOpenProblem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final problemsResult = result;
    if (problemsResult == null) {
      return Text(
        'No workspace diagnostics collected yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (problemsResult.status) {
      WorkspaceProblemsStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceProblemsStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceProblemsStatus.emptyWorkspace => const Color(0xFFF5E1DE),
    };
    final statusLabel = switch (problemsResult.status) {
      WorkspaceProblemsStatus.completed => 'completed',
      WorkspaceProblemsStatus.hitLimit => 'limited',
      WorkspaceProblemsStatus.emptyWorkspace => 'empty',
    };

    return Column(
      key: const ValueKey('workspace-problems-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${problemsResult.problemCount} problems')),
            Chip(label: Text('${problemsResult.errorCount} errors')),
            Chip(label: Text('${problemsResult.warningCount} warnings')),
            Chip(label: Text('${problemsResult.hintCount} hints')),
            Chip(label: Text('${problemsResult.matchedFileCount} files')),
            Chip(label: Text('${problemsResult.filesSearched} indexed')),
          ],
        ),
        if (problemsResult.message case final message?) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (problemsResult.problems.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final problem in problemsResult.problems.take(80)) ...[
            _WorkspaceProblemTile(
              problem: problem,
              onTap: () {
                onOpenProblem(problem);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceProblemTile extends StatelessWidget {
  const _WorkspaceProblemTile({
    required this.problem,
    required this.onTap,
  });

  final WorkspaceProblemItem problem;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: ValueKey(
        'workspace-problem-${problem.filePath}-${problem.range.start}',
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  problem.diagnostic.message,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${problem.filePath}:${problem.line + 1}:${problem.column + 1}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (problem.previewText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    problem.previewText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            );
            final badges = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Chip(label: Text(problem.severity.name)),
                Chip(label: Text(problem.diagnostic.code)),
              ],
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _workspaceProblemIcon(problem.severity),
                  color: _workspaceProblemColor(problem.severity),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: compact
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            details,
                            const SizedBox(height: 8),
                            badges,
                          ],
                        )
                      : details,
                ),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: badges,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceCodeActionsSurface extends StatefulWidget {
  const _WorkspaceCodeActionsSurface({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  State<_WorkspaceCodeActionsSurface> createState() =>
      _WorkspaceCodeActionsSurfaceState();
}

class _WorkspaceCodeActionsSurfaceState
    extends State<_WorkspaceCodeActionsSurface> {
  final TextEditingController _filterController = TextEditingController();
  WorkspaceCodeActionsResult? _result;
  WorkspaceCodeActionApplyResult? _applyResult;
  bool _loading = false;
  bool _applying = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _runCollection();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _runCollection() async {
    final generation = _generation + 1;
    _generation = generation;
    setState(() {
      _loading = true;
    });
    final result = await widget.shell.collectWorkspaceCodeActions(
      WorkspaceCodeActionsQuery(
        pattern: _filterController.text,
        maxResults: 50,
      ),
    );
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _result = result;
      _loading = false;
      _applyResult = null;
    });
  }

  Future<void> _applyAction(WorkspaceCodeActionItem action) async {
    if (_applying) {
      return;
    }
    final source = _result ?? widget.shell.lastWorkspaceCodeActions;
    if (source == null) {
      return;
    }
    setState(() {
      _applying = true;
    });
    final result = await widget.shell.applyWorkspaceCodeAction(
      query: source.query,
      actionId: action.id,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _result = result.preview;
      _applyResult = result;
      _applying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = widget.viewportProfile.isMobile;
    final result = _result ?? widget.shell.lastWorkspaceCodeActions;
    final headerChips = <Widget>[
      Chip(
        label: Text('${widget.shell.workspaceController.files.length} files'),
      ),
      if (_loading) const Chip(label: Text('analyzing')),
      if (_applying) const Chip(label: Text('applying')),
    ];

    return Card(
      key: const ValueKey('workspace-code-actions-surface'),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Code Actions', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: headerChips),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Code Actions',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Wrap(spacing: 8, children: headerChips),
                      ],
                    ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('workspace-code-actions-filter-field'),
                controller: _filterController,
                decoration: const InputDecoration(
                  labelText: 'Filter',
                  prefixIcon: Icon(Icons.filter_list_rounded),
                ),
                onSubmitted: (_) {
                  _runCollection();
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('workspace-code-actions-refresh'),
                    onPressed: _loading || _applying
                        ? null
                        : () {
                            _runCollection();
                          },
                    icon: Icon(
                      _loading
                          ? Icons.hourglass_top_rounded
                          : Icons.refresh_rounded,
                    ),
                    label: Text(_loading ? 'Analyzing' : 'Refresh'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _WorkspaceCodeActionsResultView(
                result: result,
                applyResult: _applyResult,
                applying: _applying,
                onApplyAction: _applyAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceCodeActionsResultView extends StatelessWidget {
  const _WorkspaceCodeActionsResultView({
    required this.result,
    required this.applyResult,
    required this.applying,
    required this.onApplyAction,
  });

  final WorkspaceCodeActionsResult? result;
  final WorkspaceCodeActionApplyResult? applyResult;
  final bool applying;
  final Future<void> Function(WorkspaceCodeActionItem action) onApplyAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionsResult = result;
    if (actionsResult == null) {
      return Text(
        'No workspace code actions collected yet.',
        style: theme.textTheme.bodySmall,
      );
    }

    final statusColor = switch (actionsResult.status) {
      WorkspaceCodeActionsStatus.completed => const Color(0xFFE3F1E1),
      WorkspaceCodeActionsStatus.hitLimit => const Color(0xFFF6E9D7),
      WorkspaceCodeActionsStatus.emptyWorkspace => const Color(0xFFF5E1DE),
      WorkspaceCodeActionsStatus.noActions => const Color(0xFFEEE9F2),
    };
    final statusLabel = switch (actionsResult.status) {
      WorkspaceCodeActionsStatus.completed => 'completed',
      WorkspaceCodeActionsStatus.hitLimit => 'limited',
      WorkspaceCodeActionsStatus.emptyWorkspace => 'empty',
      WorkspaceCodeActionsStatus.noActions => 'no actions',
    };
    final message = applyResult?.message ?? actionsResult.message;

    return Column(
      key: const ValueKey('workspace-code-actions-results'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _WorkflowStatusChip(label: statusLabel, color: statusColor),
            Chip(label: Text('${actionsResult.actionCount} actions')),
            Chip(label: Text('${actionsResult.editCount} edits')),
            Chip(label: Text('${actionsResult.matchedFileCount} files')),
            Chip(label: Text('${actionsResult.filesSearched} indexed')),
            Chip(
              label: Text('${actionsResult.diagnosticsScanned} diagnostics'),
            ),
          ],
        ),
        if (message != null) ...[
          const SizedBox(height: 10),
          Text(message, style: theme.textTheme.bodySmall),
        ],
        if (actionsResult.actions.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final action in actionsResult.actions.take(50)) ...[
            _WorkspaceCodeActionTile(
              action: action,
              applying: applying,
              onApply: () {
                onApplyAction(action);
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _WorkspaceCodeActionTile extends StatelessWidget {
  const _WorkspaceCodeActionTile({
    required this.action,
    required this.applying,
    required this.onApply,
  });

  final WorkspaceCodeActionItem action;
  final bool applying;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Ink(
      key: ValueKey('workspace-code-action-${action.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.label,
                style: theme.textTheme.titleSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (action.detail.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  action.detail,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Chip(label: Text('${action.editCount} edits')),
                  Chip(label: Text('${action.changedFileCount} files')),
                  for (final document in action.documents.take(3))
                    Chip(
                      label: Text(
                        '${document.filePath}:${document.line + 1}',
                      ),
                    ),
                ],
              ),
              for (final document in action.documents.take(2)) ...[
                if (document.previewText.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    document.previewText,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ],
          );
          final button = FilledButton.icon(
            key: ValueKey('workspace-code-action-apply-${action.id}'),
            onPressed: applying ? null : onApply,
            icon: Icon(
              applying
                  ? Icons.hourglass_top_rounded
                  : Icons.check_circle_outline_rounded,
            ),
            label: Text(applying ? 'Applying' : 'Apply'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                details,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: theme.colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(child: details),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
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
        label: 'Commands',
        active: shell.activeBottomTab == BottomSurfaceTab.commands,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.commands),
      ),
      _SurfaceTabChip(
        label: 'Navigate',
        active: shell.activeBottomTab == BottomSurfaceTab.navigate,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.navigate),
      ),
      _SurfaceTabChip(
        label: 'Definitions',
        active: shell.activeBottomTab == BottomSurfaceTab.definitions,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.definitions),
      ),
      _SurfaceTabChip(
        label: 'Rename',
        active: shell.activeBottomTab == BottomSurfaceTab.rename,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.rename),
      ),
      _SurfaceTabChip(
        label: 'Symbols',
        active: shell.activeBottomTab == BottomSurfaceTab.symbols,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.symbols),
      ),
      _SurfaceTabChip(
        label: 'Usages',
        active: shell.activeBottomTab == BottomSurfaceTab.usages,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.usages),
      ),
      _SurfaceTabChip(
        label: 'Calls',
        active: shell.activeBottomTab == BottomSurfaceTab.calls,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.calls),
      ),
      _SurfaceTabChip(
        label: 'Search',
        active: shell.activeBottomTab == BottomSurfaceTab.search,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.search),
      ),
      _SurfaceTabChip(
        label: 'Problems',
        active: shell.activeBottomTab == BottomSurfaceTab.problems,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.problems),
      ),
      _SurfaceTabChip(
        label: 'Actions',
        active: shell.activeBottomTab == BottomSurfaceTab.actions,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.actions),
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
            'Mobile shell keeps runtime, commands, navigate, definitions, '
            'rename, symbols, usages, calls, search, problems, actions, '
            'agent, debug, and settings on one vertical route.',
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
    case AppCommandId.commandPalette:
      return Icons.keyboard_command_key_rounded;
    case AppCommandId.quickOpen:
      return Icons.drive_file_move_outline;
    case AppCommandId.goToWorkspaceDefinition:
      return Icons.subdirectory_arrow_right_rounded;
    case AppCommandId.renameWorkspaceSymbol:
      return Icons.drive_file_rename_outline_rounded;
    case AppCommandId.searchWorkspaceSymbols:
      return Icons.account_tree_outlined;
    case AppCommandId.findWorkspaceReferences:
      return Icons.link_rounded;
    case AppCommandId.showWorkspaceCallHierarchy:
      return Icons.account_tree_rounded;
    case AppCommandId.searchWorkspace:
      return Icons.manage_search_rounded;
    case AppCommandId.showWorkspaceProblems:
      return Icons.error_outline_rounded;
    case AppCommandId.showWorkspaceCodeActions:
      return Icons.lightbulb_outline_rounded;
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

IconData _workspaceSymbolIcon(SymbolKind kind) {
  return switch (kind) {
    SymbolKind.function => Icons.functions_rounded,
    SymbolKind.pipeline => Icons.schema_outlined,
    SymbolKind.state => Icons.memory_rounded,
    SymbolKind.resource => Icons.storage_rounded,
    SymbolKind.variable => Icons.data_object_rounded,
    SymbolKind.parameter => Icons.input_rounded,
    SymbolKind.task => Icons.task_alt_rounded,
  };
}

IconData _workspaceReferenceKindIcon(StyioProjectSymbolKind kind) {
  return switch (kind) {
    StyioProjectSymbolKind.function => Icons.functions_rounded,
    StyioProjectSymbolKind.resource => Icons.storage_rounded,
    StyioProjectSymbolKind.task => Icons.task_alt_rounded,
  };
}

IconData _workspaceCallHierarchyKindIcon(
  WorkspaceCallHierarchySymbolKind kind,
) {
  return switch (kind) {
    WorkspaceCallHierarchySymbolKind.function => Icons.functions_rounded,
    WorkspaceCallHierarchySymbolKind.task => Icons.task_alt_rounded,
    WorkspaceCallHierarchySymbolKind.topLevel => Icons.notes_rounded,
  };
}

IconData _workspaceProblemIcon(DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.error => Icons.error_outline_rounded,
    DiagnosticSeverity.warning => Icons.warning_amber_rounded,
    DiagnosticSeverity.hint => Icons.lightbulb_outline_rounded,
  };
}

Color _workspaceProblemColor(DiagnosticSeverity severity) {
  return switch (severity) {
    DiagnosticSeverity.error => const Color(0xFF9F3A35),
    DiagnosticSeverity.warning => const Color(0xFFA36B00),
    DiagnosticSeverity.hint => const Color(0xFF3F6A9A),
  };
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
