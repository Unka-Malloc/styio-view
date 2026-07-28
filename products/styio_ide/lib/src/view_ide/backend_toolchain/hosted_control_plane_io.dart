import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../platform/platform_target.dart';
import 'hosted_control_plane.dart';

const _hostedUrlEnvName = 'VITYO_HOSTED_URL';
const _hostedTokenEnvName = 'VITYO_HOSTED_TOKEN';
const _hostedWorkspaceRootEnvName = 'VITYO_HOSTED_WORKSPACE_ROOT';
const _hostedManifestPathEnvName = 'VITYO_HOSTED_MANIFEST_PATH';
const _hostedWorkspaceIdEnvName = 'VITYO_HOSTED_WORKSPACE_ID';
const _forceHostedRouteEnvName = 'VITYO_FORCE_HOSTED_ROUTE';
const _hostedTimeoutMsEnvName = 'VITYO_HOSTED_TIMEOUT_MS';
const _hostedMaxResponseBytesEnvName = 'VITYO_HOSTED_MAX_RESPONSE_BYTES';
const _defaultRequestTimeout = Duration(seconds: 15);
const _defaultMaxResponseBytes = 1024 * 1024;

Map<String, String> Function() _hostedEnvironmentProvider = () =>
    Platform.environment;

void debugOverrideHostedEnvironment(Map<String, String>? environment) {
  _hostedEnvironmentProvider = environment == null
      ? () => Platform.environment
      : () => Map<String, String>.unmodifiable(environment);
}

HostedControlPlaneConfig? resolveHostedControlPlaneConfig({
  required PlatformTarget platformTarget,
}) {
  return _resolveHostedControlPlaneRoute(
    env: _hostedEnvironmentProvider(),
    platformTarget: platformTarget,
  )?.config;
}

Future<HostedControlPlaneClient?> createHostedControlPlaneClient({
  required PlatformTarget platformTarget,
}) async {
  final route = _resolveHostedControlPlaneRoute(
    env: _hostedEnvironmentProvider(),
    platformTarget: platformTarget,
  );
  return route == null
      ? null
      : _IoHostedControlPlaneClient(
          config: route.config,
          accessToken: route.accessToken,
          requestTimeout: route.requestTimeout,
          maxResponseBytes: route.maxResponseBytes,
        );
}

class _IoHostedControlPlaneClient implements HostedControlPlaneClient {
  _IoHostedControlPlaneClient({
    required this.config,
    required String accessToken,
    required Duration requestTimeout,
    required int maxResponseBytes,
  }) : _accessToken = accessToken,
       _requestTimeout = requestTimeout,
       _maxResponseBytes = maxResponseBytes,
       _baseUri = Uri.parse(config.baseUrl);

  @override
  final HostedControlPlaneConfig config;
  final String _accessToken;
  final Duration _requestTimeout;
  final int _maxResponseBytes;
  final Uri _baseUri;

  @override
  Future<Map<String, dynamic>> openWorkspace({
    required PlatformTarget platformTarget,
  }) {
    return _post(
      const <String>['workspaces', 'open'],
      <String, Object?>{
        'workspace_root': config.workspaceRoot,
        if (config.manifestPath != null) 'manifest_path': config.manifestPath,
        'platform': platformTarget.wireValue,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> projectGraph({required String workspaceId}) {
    return _get(<String>['workspaces', workspaceId, 'project-graph']);
  }

  @override
  Future<Map<String, dynamic>> loadDocument({
    required String workspaceId,
    required String path,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'documents', 'load'],
      <String, Object?>{'path': path},
    );
  }

  @override
  Future<Map<String, dynamic>> saveDocument({
    required String workspaceId,
    required String path,
    required String documentText,
    required int revision,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'documents', 'save'],
      <String, Object?>{
        'path': path,
        'document_text': documentText,
        'revision': revision,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> toolInstall({
    required String workspaceId,
    required String styioBinaryPath,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'tool', 'install'],
      <String, Object?>{'styio_binary_path': styioBinaryPath},
    );
  }

  @override
  Future<Map<String, dynamic>> toolUse({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'tool', 'use'],
      <String, Object?>{
        'compiler_version': compilerVersion,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> toolPin({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'tool', 'pin'],
      <String, Object?>{
        'compiler_version': compilerVersion,
        if (channel != null && channel.isNotEmpty) 'channel': channel,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> toolClearPin({required String workspaceId}) {
    return _post(<String>[
      'workspaces',
      workspaceId,
      'tool',
      'clear-pin',
    ], const <String, Object?>{});
  }

  @override
  Future<Map<String, dynamic>> fetchDependencies({
    required String workspaceId,
    bool locked = false,
    bool offline = false,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'dependencies', 'fetch'],
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
      <String>['workspaces', workspaceId, 'dependencies', 'vendor'],
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
    return _post(
      <String>['workspaces', workspaceId, 'execution', 'run'],
      <String, Object?>{
        'active_file_path': activeFilePath,
        'document_text': documentText,
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (targetName != null && targetName.isNotEmpty)
          'target_name': targetName,
        if (targetKind != null && targetKind.isNotEmpty)
          'target_kind': targetKind,
      },
    );
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
    return _post(
      <String>['workspaces', workspaceId, 'execution', 'build'],
      <String, Object?>{
        'active_file_path': activeFilePath,
        'document_text': documentText,
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (targetName != null && targetName.isNotEmpty)
          'target_name': targetName,
        if (targetKind != null && targetKind.isNotEmpty)
          'target_kind': targetKind,
      },
    );
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
    return _post(
      <String>['workspaces', workspaceId, 'execution', 'test'],
      <String, Object?>{
        'active_file_path': activeFilePath,
        'document_text': documentText,
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (targetName != null && targetName.isNotEmpty)
          'target_name': targetName,
        if (targetKind != null && targetKind.isNotEmpty)
          'target_kind': targetKind,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> packProject({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'deployment', 'pack'],
      <String, Object?>{
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (outputPath != null && outputPath.isNotEmpty)
          'output_path': outputPath,
      },
    );
  }

  @override
  Future<Map<String, dynamic>> preparePublish({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  }) {
    return _post(
      <String>['workspaces', workspaceId, 'deployment', 'preflight'],
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
      <String>['workspaces', workspaceId, 'deployment', 'publish'],
      <String, Object?>{
        'registry_root': registryRoot,
        if (packageName != null && packageName.isNotEmpty)
          'package_name': packageName,
        if (outputPath != null && outputPath.isNotEmpty)
          'output_path': outputPath,
      },
    );
  }

  Future<Map<String, dynamic>> _get(List<String> pathSegments) async {
    final uri = _uriFor(pathSegments);
    final client = HttpClient();
    client.connectionTimeout = _requestTimeout;
    try {
      return await _withTimeout(uri, () async {
        final request = await client.getUrl(uri);
        _prepareRequest(request);
        final response = await request.close();
        return _decodeResponse(uri, response);
      });
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _post(
    List<String> pathSegments,
    Map<String, Object?> body,
  ) async {
    final uri = _uriFor(pathSegments);
    final client = HttpClient();
    client.connectionTimeout = _requestTimeout;
    try {
      return await _withTimeout(uri, () async {
        final encoded = utf8.encode(jsonEncode(body));
        final request = await client.postUrl(uri);
        _prepareRequest(request);
        request.headers.contentType = ContentType.json;
        request.contentLength = encoded.length;
        request.add(encoded);
        final response = await request.close();
        return _decodeResponse(uri, response);
      });
    } finally {
      client.close(force: true);
    }
  }

  Uri _uriFor(List<String> routeSegments) {
    final safeRouteSegments = _validateRouteSegments(routeSegments);
    final basePathSegments = _baseUri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return _baseUri.replace(
      pathSegments: <String>[...basePathSegments, ...safeRouteSegments],
      queryParameters: null,
      fragment: null,
    );
  }

  void _prepareRequest(HttpClientRequest request) {
    request.followRedirects = false;
    request.headers.set(HttpHeaders.acceptHeader, ContentType.json.mimeType);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $_accessToken',
    );
  }

  Future<T> _withTimeout<T>(Uri uri, Future<T> Function() runRequest) async {
    try {
      return await runRequest().timeout(_requestTimeout);
    } on TimeoutException catch (error) {
      throw TimeoutException(
        'Hosted control plane request to $uri timed out after '
        '${_requestTimeout.inMilliseconds} ms.',
        error.duration ?? _requestTimeout,
      );
    }
  }

  Future<Map<String, dynamic>> _decodeResponse(
    Uri uri,
    HttpClientResponse response,
  ) async {
    final text = await _readResponseBody(uri, response);
    final failedStatus =
        response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices;
    if (failedStatus) {
      final decoded = _tryDecodeJson(text);
      throw StateError(_responseFailureMessage(uri, response, decoded));
    }
    if (!_isJsonResponse(response)) {
      throw StateError(
        'Hosted control plane at $uri did not return application/json.',
      );
    }
    final decoded = _tryDecodeJson(text);
    if (decoded == null) {
      throw StateError('Hosted control plane at $uri returned malformed JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw StateError(
        'Hosted control plane at $uri did not return a JSON object.',
      );
    }
    _validateResponseEnvelope(uri, decoded);
    return decoded;
  }

  Future<String> _readResponseBody(Uri uri, HttpClientResponse response) async {
    final contentLength = response.contentLength;
    if (contentLength > _maxResponseBytes) {
      throw StateError(
        'Hosted control plane response from $uri exceeded '
        '$_maxResponseBytes bytes.',
      );
    }
    final builder = BytesBuilder(copy: false);
    var totalBytes = 0;
    await for (final chunk in response) {
      totalBytes += chunk.length;
      if (totalBytes > _maxResponseBytes) {
        throw StateError(
          'Hosted control plane response from $uri exceeded '
          '$_maxResponseBytes bytes.',
        );
      }
      builder.add(chunk);
    }
    return utf8.decode(builder.takeBytes());
  }
}

typedef _HostedControlPlaneRoute = ({
  HostedControlPlaneConfig config,
  String accessToken,
  Duration requestTimeout,
  int maxResponseBytes,
});

_HostedControlPlaneRoute? _resolveHostedControlPlaneRoute({
  required Map<String, String> env,
  required PlatformTarget platformTarget,
}) {
  final baseUrl = _envValue(env, _hostedUrlEnvName);
  final workspaceRoot = _envValue(env, _hostedWorkspaceRootEnvName);
  final manifestPath = _envValue(env, _hostedManifestPathEnvName);
  final workspaceId = _envValue(env, _hostedWorkspaceIdEnvName);
  final forceHosted = _envValue(env, _forceHostedRouteEnvName) == '1';
  if (baseUrl == null || workspaceRoot == null) {
    return null;
  }
  if (platformTarget != PlatformTarget.ios &&
      platformTarget != PlatformTarget.web &&
      !(platformTarget == PlatformTarget.android && forceHosted)) {
    return null;
  }
  final accessToken = _envValue(env, _hostedTokenEnvName);
  if (accessToken == null) {
    throw StateError(
      '$_hostedTokenEnvName is required when $_hostedUrlEnvName is set.',
    );
  }
  return (
    config: HostedControlPlaneConfig(
      baseUrl: _normalizeHostedBaseUrl(baseUrl),
      workspaceRoot: workspaceRoot,
      manifestPath: manifestPath,
      workspaceId: workspaceId,
      forceHostedRoute: forceHosted,
    ),
    accessToken: accessToken,
    requestTimeout: _requestTimeoutFromEnvironment(env),
    maxResponseBytes: _maxResponseBytesFromEnvironment(env),
  );
}

String? _envValue(Map<String, String> env, String name) {
  final value = env[name];
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String _normalizeHostedBaseUrl(String rawBaseUrl) {
  final uri = Uri.tryParse(rawBaseUrl);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      (uri.scheme != 'https' &&
          !(uri.scheme == 'http' && _isLoopbackHost(uri.host)))) {
    throw StateError(
      '$_hostedUrlEnvName must be an absolute https URL, or an http '
      'loopback URL for local development.',
    );
  }
  if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw StateError(
      '$_hostedUrlEnvName must not include credentials, query, or fragment.',
    );
  }
  final basePathSegments = _validateBasePathSegments(
    uri.pathSegments.where((segment) => segment.isNotEmpty),
  );
  final normalized = uri.replace(
    pathSegments: basePathSegments,
    queryParameters: null,
    fragment: null,
  );
  final normalizedText = normalized.toString();
  return normalizedText.endsWith('/')
      ? normalizedText.substring(0, normalizedText.length - 1)
      : normalizedText;
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost') {
    return true;
  }
  return InternetAddress.tryParse(host)?.isLoopback ?? false;
}

Duration _requestTimeoutFromEnvironment(Map<String, String> env) {
  final timeoutMs = _positiveIntFromEnvironment(env, _hostedTimeoutMsEnvName);
  return timeoutMs == null
      ? _defaultRequestTimeout
      : Duration(milliseconds: timeoutMs);
}

int _maxResponseBytesFromEnvironment(Map<String, String> env) {
  return _positiveIntFromEnvironment(env, _hostedMaxResponseBytesEnvName) ??
      _defaultMaxResponseBytes;
}

int? _positiveIntFromEnvironment(Map<String, String> env, String name) {
  final value = _envValue(env, name);
  if (value == null) {
    return null;
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    throw StateError('$name must be a positive integer.');
  }
  return parsed;
}

List<String> _validateBasePathSegments(Iterable<String> segments) {
  return segments
      .map((segment) {
        if (segment == '.' || segment == '..') {
          throw StateError(
            '$_hostedUrlEnvName must not include relative path segments.',
          );
        }
        return segment;
      })
      .toList(growable: false);
}

List<String> _validateRouteSegments(List<String> segments) {
  return segments
      .map((segment) {
        if (segment.isEmpty ||
            segment == '.' ||
            segment == '..' ||
            segment.contains('/') ||
            segment.contains(r'\')) {
          throw ArgumentError.value(
            segment,
            'route segment',
            'Hosted control plane route segments must be single path segments.',
          );
        }
        return segment;
      })
      .toList(growable: false);
}

Object? _tryDecodeJson(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

bool _isJsonResponse(HttpClientResponse response) {
  return response.headers.contentType?.mimeType == ContentType.json.mimeType;
}

String _responseFailureMessage(
  Uri uri,
  HttpClientResponse response,
  Object? decoded,
) {
  if (decoded is Map<String, dynamic>) {
    final message = decoded['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message;
    }
  }
  return 'Hosted control plane request to $uri failed with HTTP '
      '${response.statusCode}.';
}

void _validateResponseEnvelope(Uri uri, Map<String, dynamic> decoded) {
  _validateOptionalValue<String>(uri, decoded, 'message', 'a string');
  _validateOptionalValue<int>(uri, decoded, 'returncode', 'an integer');
  _validateOptionalValue<String>(uri, decoded, 'stdout', 'a string');
  _validateOptionalValue<String>(uri, decoded, 'stderr', 'a string');
  _validateOptionalValue<Map<String, dynamic>>(
    uri,
    decoded,
    'payload',
    'a JSON object',
  );
  _validateOptionalValue<Map<String, dynamic>>(
    uri,
    decoded,
    'error_payload',
    'a JSON object',
  );
  _validateOptionalValue<Map<String, dynamic>>(
    uri,
    decoded,
    'workspace',
    'a JSON object',
  );
}

void _validateOptionalValue<T>(
  Uri uri,
  Map<String, dynamic> decoded,
  String field,
  String expectedType,
) {
  if (decoded.containsKey(field) && decoded[field] is! T) {
    throw StateError(
      'Hosted control plane at $uri returned malformed "$field"; '
      'expected $expectedType.',
    );
  }
}
