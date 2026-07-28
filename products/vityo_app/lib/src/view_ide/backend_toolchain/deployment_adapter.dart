import 'project_graph_contract.dart';

enum DeploymentCommandStatus { blocked, succeeded, failed }

class DeploymentCommandResult {
  const DeploymentCommandResult({
    required this.command,
    required this.status,
    required this.statusMessage,
    required this.stdout,
    required this.stderr,
    this.payload,
    this.errorPayload,
  });

  final String command;
  final DeploymentCommandStatus status;
  final String statusMessage;
  final String stdout;
  final String stderr;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? errorPayload;

  bool get succeeded => status == DeploymentCommandStatus.succeeded;
}

abstract class DeploymentAdapter {
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  });

  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  });

  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  });
}
