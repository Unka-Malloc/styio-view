import 'package:flutter/foundation.dart';

import '../../backend_toolchain/backend_toolchain.dart';

/// Owns deployment command execution and the latest deployment result.
final class DeploymentController extends ChangeNotifier {
  DeploymentController({
    required this.adapter,
    required this.projectGraph,
    required this.log,
  });

  final DeploymentAdapter adapter;
  final ProjectGraphSnapshot Function() projectGraph;
  final void Function(String message) log;

  DeploymentCommandResult? _lastCommand;

  DeploymentCommandResult? get lastCommand => _lastCommand;

  Future<DeploymentCommandResult> packProject({
    String? packageName,
    String? outputPath,
  }) async {
    final result = await adapter.packProject(
      projectGraph: projectGraph(),
      packageName: packageName,
      outputPath: outputPath,
    );
    return _complete(result);
  }

  Future<DeploymentCommandResult> preparePublish({
    String? packageName,
    String? outputPath,
  }) async {
    final result = await adapter.preparePublish(
      projectGraph: projectGraph(),
      packageName: packageName,
      outputPath: outputPath,
    );
    return _complete(result);
  }

  Future<DeploymentCommandResult> publishToRegistry({
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    final result = await adapter.publishToRegistry(
      projectGraph: projectGraph(),
      registryRoot: registryRoot,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _complete(result);
  }

  DeploymentCommandResult _complete(DeploymentCommandResult result) {
    _lastCommand = result;
    log('${result.command} ${result.status.name}: ${result.statusMessage}');
    if (result.payload case final payload?) {
      final packageName = payload['package'] as String?;
      final archivePath = payload['archive_path'] as String?;
      if (packageName != null && packageName.isNotEmpty) {
        log('deploy package: $packageName');
      }
      if (archivePath != null && archivePath.isNotEmpty) {
        log('deploy archive: $archivePath');
      }
    }
    notifyListeners();
    return result;
  }
}
