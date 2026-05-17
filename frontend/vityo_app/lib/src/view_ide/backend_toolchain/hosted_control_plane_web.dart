// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import '../platform/platform_target.dart';
import 'hosted_control_plane.dart';

void debugOverrideHostedEnvironment(Map<String, String>? environment) {
  // Browser route does not support mutable environment state in-process.
}

HostedControlPlaneConfig? resolveHostedControlPlaneConfig({
  required PlatformTarget platformTarget,
}) {
  if (platformTarget != PlatformTarget.web) {
    return null;
  }
  const configuredUrl = String.fromEnvironment('VITYO_HOSTED_URL');
  const configuredWorkspaceRoot = String.fromEnvironment(
    'VITYO_HOSTED_WORKSPACE_ROOT',
  );
  const configuredManifestPath = String.fromEnvironment(
    'VITYO_HOSTED_MANIFEST_PATH',
  );
  const configuredWorkspaceId = String.fromEnvironment(
    'VITYO_HOSTED_WORKSPACE_ID',
  );
  final baseUrl = configuredUrl.isNotEmpty
      ? configuredUrl
      : '${html.window.location.origin}/api/styio-hosted/v1';
  final workspaceRoot = configuredWorkspaceRoot.isNotEmpty
      ? configuredWorkspaceRoot
      : '/workspace/hosted';
  final manifestPath = configuredManifestPath.isNotEmpty
      ? configuredManifestPath
      : '$workspaceRoot/spio.toml';
  return HostedControlPlaneConfig(
    baseUrl: baseUrl,
    workspaceRoot: workspaceRoot,
    manifestPath: manifestPath,
    workspaceId: configuredWorkspaceId.isNotEmpty
        ? configuredWorkspaceId
        : null,
    forceHostedRoute: true,
  );
}

Future<HostedControlPlaneClient?> createHostedControlPlaneClient({
  required PlatformTarget platformTarget,
}) async {
  final config = resolveHostedControlPlaneConfig(
    platformTarget: platformTarget,
  );
  return config == null ? null : _WebHostedControlPlaneClient(config: config);
}

class _WebHostedControlPlaneClient implements HostedControlPlaneClient {
  _WebHostedControlPlaneClient({required this.config});

  @override
  final HostedControlPlaneConfig config;

  @override
  Future<Map<String, dynamic>> openWorkspace({
    required PlatformTarget platformTarget,
  }) {
    return _post('/workspaces/open', <String, Object?>{
      'workspace_root': config.workspaceRoot,
      if (config.manifestPath != null) 'manifest_path': config.manifestPath,
      'platform': platformTarget.wireValue,
    });
  }

  @override
  Future<Map<String, dynamic>> projectGraph({required String workspaceId}) {
    return _request('GET', '/workspaces/$workspaceId/project-graph');
  }

  @override
  Future<Map<String, dynamic>> loadDocument({
    required String workspaceId,
    required String path,
  }) {
    return _post('/workspaces/$workspaceId/documents/load', <String, Object?>{
      'path': path,
    });
  }

  @override
  Future<Map<String, dynamic>> saveDocument({
    required String workspaceId,
    required String path,
    required String documentText,
    required int revision,
  }) {
    return _post('/workspaces/$workspaceId/documents/save', <String, Object?>{
      'path': path,
      'document_text': documentText,
      'revision': revision,
    });
  }

  @override
  Future<Map<String, dynamic>> toolInstall({
    required String workspaceId,
    required String styioBinaryPath,
  }) {
    return _post('/workspaces/$workspaceId/tool/install', <String, Object?>{
      'styio_binary_path': styioBinaryPath,
    });
  }

  @override
  Future<Map<String, dynamic>> toolUse({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  }) {
    return _post('/workspaces/$workspaceId/tool/use', <String, Object?>{
      'compiler_version': compilerVersion,
      if (channel != null && channel.isNotEmpty) 'channel': channel,
    });
  }

  @override
  Future<Map<String, dynamic>> toolPin({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  }) {
    return _post('/workspaces/$workspaceId/tool/pin', <String, Object?>{
      'compiler_version': compilerVersion,
      if (channel != null && channel.isNotEmpty) 'channel': channel,
    });
  }

  @override
  Future<Map<String, dynamic>> toolClearPin({required String workspaceId}) {
    return _post(
      '/workspaces/$workspaceId/tool/clear-pin',
      const <String, Object?>{},
    );
  }

  @override
  Future<Map<String, dynamic>> fetchDependencies({
    required String workspaceId,
    bool locked = false,
    bool offline = false,
  }) {
    return _post(
      '/workspaces/$workspaceId/dependencies/fetch',
      <String, Object?>{'locked': locked, 'offline': offline},
    );
  }

  @override
  Future<Map<String, dynamic>> vendorDependencies({
    required String workspaceId,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) {
    return _post(
      '/workspaces/$workspaceId/dependencies/vendor',
      <String, Object?>{
        if (outputPath != null && outputPath.isNotEmpty)
          'output_path': outputPath,
        'locked': locked,
        'offline': offline,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> runWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  }) {
    return _post('/workspaces/$workspaceId/execution/run', <String, Object?>{
      'active_file_path': activeFilePath,
      'document_text': documentText,
      if (packageName != null && packageName.isNotEmpty)
        'package_name': packageName,
      if (targetName != null && targetName.isNotEmpty)
        'target_name': targetName,
      if (targetKind != null && targetKind.isNotEmpty)
        'target_kind': targetKind,
    });
  }

  @override
  Future<Map<String, dynamic>> buildWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  }) {
    return _post('/workspaces/$workspaceId/execution/build', <String, Object?>{
      'active_file_path': activeFilePath,
      'document_text': documentText,
      if (packageName != null && packageName.isNotEmpty)
        'package_name': packageName,
      if (targetName != null && targetName.isNotEmpty)
        'target_name': targetName,
      if (targetKind != null && targetKind.isNotEmpty)
        'target_kind': targetKind,
    });
  }

  @override
  Future<Map<String, dynamic>> testWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  }) {
    return _post('/workspaces/$workspaceId/execution/test', <String, Object?>{
      'active_file_path': activeFilePath,
      'document_text': documentText,
      if (packageName != null && packageName.isNotEmpty)
        'package_name': packageName,
      if (targetName != null && targetName.isNotEmpty)
        'target_name': targetName,
      if (targetKind != null && targetKind.isNotEmpty)
        'target_kind': targetKind,
    });
  }

  @override
  Future<Map<String, dynamic>> packProject({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  }) {
    return _post('/workspaces/$workspaceId/deployment/pack', <String, Object?>{
      if (packageName != null && packageName.isNotEmpty)
        'package_name': packageName,
      if (outputPath != null && outputPath.isNotEmpty)
        'output_path': outputPath,
    });
  }

  @override
  Future<Map<String, dynamic>> preparePublish({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  }) {
    return _post(
      '/workspaces/$workspaceId/deployment/preflight',
      <String, Object?>{
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (outputPath != null && outputPath.isNotEmpty)
          'output_path': outputPath,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> publishToRegistry({
    required String workspaceId,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) {
    return _post(
      '/workspaces/$workspaceId/deployment/publish',
      <String, Object?>{
        'registry_root': registryRoot,
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (outputPath != null && outputPath.isNotEmpty)
          'output_path': outputPath,
      },
    );
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body) {
    return _request('POST', path, body: body);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final response = await html.HttpRequest.request(
      '${config.baseUrl}$path',
      method: method,
      sendData: body == null ? null : jsonEncode(body),
      requestHeaders: body == null
          ? const <String, String>{}
          : const <String, String>{'Content-Type': 'application/json'},
    );
    final decoded = jsonDecode(response.responseText ?? '');
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Hosted control plane did not return a JSON object.');
    }
    return decoded;
  }
}
