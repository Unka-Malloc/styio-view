import '../platform/platform_target.dart';
import 'dependency_source_adapter_web.dart'
    if (dart.library.io) 'dependency_source_adapter_io.dart'
    as platform_adapter;
import 'project_graph_contract.dart';

enum DependencySourceCommandStatus { blocked, succeeded, failed }

class DependencySourceCommandResult {
  const DependencySourceCommandResult({
    required this.command,
    required this.status,
    required this.statusMessage,
    required this.stdout,
    required this.stderr,
    this.payload,
    this.errorPayload,
  });

  final String command;
  final DependencySourceCommandStatus status;
  final String statusMessage;
  final String stdout;
  final String stderr;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic>? errorPayload;

  bool get succeeded => status == DependencySourceCommandStatus.succeeded;
}

String? blockedDependencySourceCommandReason({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
  required String command,
}) {
  if (platformTarget == PlatformTarget.ios ||
      platformTarget == PlatformTarget.web) {
    if (projectGraph.hasHostedWorkspace) {
      final manifestPath = projectGraph.manifestPath;
      if (manifestPath == null || manifestPath.isEmpty) {
        return '$command requires a resolved spio manifest path.';
      }
      return null;
    }
    return '${platformTarget.label} does not expose local spio dependency materialization commands.';
  }

  final manifestPath = projectGraph.manifestPath;
  if (manifestPath == null || manifestPath.isEmpty) {
    return '$command requires a resolved spio manifest path.';
  }

  return null;
}

abstract class DependencySourceAdapter {
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  });

  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  });
}

Future<DependencySourceAdapter> createDependencySourceAdapter({
  required PlatformTarget platformTarget,
}) {
  return platform_adapter.createPlatformDependencySourceAdapter(
    platformTarget: platformTarget,
  );
}
