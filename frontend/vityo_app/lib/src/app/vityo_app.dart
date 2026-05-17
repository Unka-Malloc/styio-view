import 'package:flutter/material.dart';

import '../view_render/theme/theme.dart';
import 'app_bootstrap.dart';
import 'layout/vityo_shell_scaffold.dart';
import 'state/shell_model.dart';
import 'state/shell_scope.dart';

class VityoApp extends StatefulWidget {
  const VityoApp({super.key, required this.bootstrap});

  final AppBootstrap bootstrap;

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
      toolchainManager: widget.bootstrap.toolchainManager,
      languageServiceStatus: widget.bootstrap.languageServiceStatus,
      toolchainStatusReport: widget.bootstrap.toolchainStatusReport,
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
    return ShellScope(
      model: _shellModel,
      child: MaterialApp(
        title: 'Vityo',
        debugShowCheckedModeBanner: false,
        theme: VityoTheme.light(),
        home: const VityoShellScaffold(),
      ),
    );
  }
}
