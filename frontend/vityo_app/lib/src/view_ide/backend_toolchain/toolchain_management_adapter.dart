import '../platform/platform_target.dart';
import 'project_graph_contract.dart';
import 'toolchain_management_adapter_web.dart'
    if (dart.library.io) 'toolchain_management_adapter_io.dart'
    as platform_adapter;

enum ToolchainCommandStatus { blocked, succeeded, failed }

class ToolchainCommandResult {
  const ToolchainCommandResult({
    required this.command,
    required this.status,
    required this.statusMessage,
    required this.stdout,
    required this.stderr,
    this.payload,
    this.errorPayload,
  });

  final String command;
  final ToolchainCommandStatus status;
  final String statusMessage;
  final String stdout;
  final String stderr;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? errorPayload;

  bool get succeeded => status == ToolchainCommandStatus.succeeded;
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

Future<ToolchainManagementAdapter> createToolchainManagementAdapter({
  required PlatformTarget platformTarget,
}) {
  return platform_adapter.createPlatformToolchainManagementAdapter(
    platformTarget: platformTarget,
  );
}
