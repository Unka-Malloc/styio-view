import 'project_graph_contract.dart';

enum ToolchainCommandStatus { blocked, succeeded, failed }

class ToolchainCommandResult {
  static const int currentSchemaVersion = 1;

  const ToolchainCommandResult({
    required this.command,
    required this.status,
    required this.statusMessage,
    required this.stdout,
    required this.stderr,
    this.schemaVersion = currentSchemaVersion,
    this.payload,
    this.errorPayload,
  });

  final int schemaVersion;
  final String command;
  final ToolchainCommandStatus status;
  final String statusMessage;
  final String stdout;
  final String stderr;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? errorPayload;

  bool get succeeded => status == ToolchainCommandStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'command': command,
      'status': status.name,
      'statusMessage': statusMessage,
      'stdout': stdout,
      'stderr': stderr,
      if (payload != null) 'payload': payload,
      if (errorPayload != null) 'errorPayload': errorPayload,
    };
  }
}

abstract class ToolchainManagementAdapter {
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  });

  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  });

  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  });

  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  });
}
