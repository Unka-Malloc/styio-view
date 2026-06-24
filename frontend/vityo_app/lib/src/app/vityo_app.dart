import 'dart:async';

import 'package:flutter/material.dart';

import 'layout/vityo_shell_scaffold.dart';
import '../view_render/theme/theme.dart';
import 'app_bootstrap.dart';
import 'state/shell_model.dart';
import 'state/shell_scope.dart';

class VityoApp extends StatefulWidget {
  const VityoApp({super.key, required this.bootstrap, this.initialPath});

  final AppBootstrap bootstrap;
  final String? initialPath;

  @override
  State<VityoApp> createState() => _VityoAppState();
}

class _VityoAppState extends State<VityoApp> {
  late final ShellModel _shellModel;

  @override
  void initState() {
    super.initState();
    _shellModel = ShellModel(
      platformTarget: widget.bootstrap.platformTarget,
      supplementalAdapterCapabilities:
          widget.bootstrap.supplementalAdapterCapabilities,
      projectGraphAdapter: widget.bootstrap.projectGraphAdapter,
      workspaceController: widget.bootstrap.workspaceController,
      workspaceDocumentStore: widget.bootstrap.workspaceDocumentStore,
      moduleRegistry: widget.bootstrap.moduleRegistry,
      nativeModuleLoader: widget.bootstrap.nativeModuleLoader,
      editorController: widget.bootstrap.editorController,
      executionAdapter: widget.bootstrap.executionAdapter,
      executionAdapterFactory: widget.bootstrap.executionAdapterFactory,
      runtimeEventAdapter: widget.bootstrap.runtimeEventAdapter,
      dependencySourceAdapter: widget.bootstrap.dependencySourceAdapter,
      deploymentAdapter: widget.bootstrap.deploymentAdapter,
      toolchainManagementAdapter: widget.bootstrap.toolchainManagementAdapter,
      agentCodingController: widget.bootstrap.agentCodingController,
      agentExtensionToolExecutionRegistry:
          widget.bootstrap.agentExtensionToolExecutionRegistry,
      runtimeOutputBuffer: widget.bootstrap.runtimeOutputBuffer,
      agentProviderConfigurator: widget.bootstrap.agentProviderConfigurator,
      refreshActiveLanguageService:
          widget.bootstrap.refreshActiveLanguageService,
      styioServiceSubscriptionController:
          widget.bootstrap.styioServiceSubscriptionController,
      toolchainManager: widget.bootstrap.toolchainManager,
      languageServiceStatus: widget.bootstrap.languageServiceStatus,
      toolchainStatusReport: widget.bootstrap.toolchainStatusReport,
      clangCppVersionPreference: widget.bootstrap.clangCppVersionPreference,
      themeOverrideStore: widget.bootstrap.themeOverrideStore,
      commandPalettePreferencesStore:
          widget.bootstrap.commandPalettePreferencesStore,
      workspaceDiagnosticsController:
          widget.bootstrap.workspaceDiagnosticsController,
      testingSessionController: widget.bootstrap.testingSessionController,
      sourceControlStatusController:
          widget.bootstrap.sourceControlStatusController,
      projectLanguageService: widget.bootstrap.projectLanguageService,
    );
    unawaited(_shellModel.loadThemeOverride());
    unawaited(
      _shellModel.loadCommandPalettePreferences(
        workspaceId: widget.bootstrap.workspaceController.activeProject.id,
      ),
    );
  }

  @override
  void dispose() {
    _shellModel.dispose();
    widget.bootstrap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shellModel,
      builder: (context, _) {
        return ShellScope(
          model: _shellModel,
          child: MaterialApp(
            title: 'Vityo',
            debugShowCheckedModeBanner: false,
            theme: VityoTheme.light(overrides: _shellModel.themeOverride),
            initialRoute: _editorInitialRoute(widget.initialPath),
            onGenerateInitialRoutes: (initialRoute) => <Route<dynamic>>[
              _editorRoute(initialRoute),
            ],
            onGenerateRoute: (settings) => _editorRoute(settings.name),
            onUnknownRoute: (settings) => _editorRoute(settings.name),
          ),
        );
      },
    );
  }
}

String _editorInitialRoute(String? path) {
  if (path == null || path.trim().isEmpty) {
    return '/editor';
  }
  return '/editor';
}

Route<dynamic> _editorRoute(String? _) {
  return MaterialPageRoute<void>(
    settings: const RouteSettings(name: '/editor'),
    builder: (_) => const VityoShellScaffold(),
  );
}
