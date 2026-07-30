import '../platform/platform_target.dart';
import 'hosted_control_plane_web.dart'
    if (dart.library.io) 'hosted_control_plane_io.dart'
    as platform;

class HostedControlPlaneConfig {
  const HostedControlPlaneConfig({
    required this.baseUrl,
    required this.workspaceRoot,
    this.manifestPath,
    this.workspaceId,
    this.forceHostedRoute = false,
  });

  final String baseUrl;
  final String workspaceRoot;
  final String? manifestPath;
  final String? workspaceId;
  final bool forceHostedRoute;
}

abstract class HostedControlPlaneClient {
  HostedControlPlaneConfig get config;

  Future<Map<String, dynamic>> openWorkspace({
    required PlatformTarget platformTarget,
  });

  Future<Map<String, dynamic>> projectGraph({required String workspaceId});

  Future<Map<String, dynamic>> loadDocument({
    required String workspaceId,
    required String path,
  });

  Future<Map<String, dynamic>> saveDocument({
    required String workspaceId,
    required String path,
    required String documentText,
    required int revision,
  });

  Future<Map<String, dynamic>> toolInstall({
    required String workspaceId,
    required String styioBinaryPath,
  });

  Future<Map<String, dynamic>> toolUse({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  });

  Future<Map<String, dynamic>> toolPin({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  });

  Future<Map<String, dynamic>> toolClearPin({required String workspaceId});

  Future<Map<String, dynamic>> fetchDependencies({
    required String workspaceId,
    bool locked = false,
    bool offline = false,
  });

  Future<Map<String, dynamic>> vendorDependencies({
    required String workspaceId,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  });

  Future<Map<String, dynamic>> runWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  });

  Future<Map<String, dynamic>> buildWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  });

  Future<Map<String, dynamic>> testWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  });

  Future<Map<String, dynamic>> packProject({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  });

  Future<Map<String, dynamic>> preparePublish({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  });

  Future<Map<String, dynamic>> publishToRegistry({
    required String workspaceId,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  });
}

HostedControlPlaneConfig? resolveHostedControlPlaneConfig({
  required PlatformTarget platformTarget,
}) {
  return platform.resolveHostedControlPlaneConfig(
    platformTarget: platformTarget,
  );
}

Future<HostedControlPlaneClient?> createHostedControlPlaneClient({
  required PlatformTarget platformTarget,
}) {
  return platform.createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
}

void debugOverrideHostedEnvironment(Map<String, String>? environment) {
  platform.debugOverrideHostedEnvironment(environment);
}
