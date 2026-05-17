import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('hosted control-plane IO route requires bearer token', () {
    debugOverrideHostedEnvironment(const <String, String>{
      'VITYO_HOSTED_URL': 'https://control.example.com/api/styio/v1',
      'VITYO_HOSTED_WORKSPACE_ROOT': '/workspace/demo',
    });
    addTearDown(() => debugOverrideHostedEnvironment(null));

    expect(
      () => resolveHostedControlPlaneConfig(platformTarget: PlatformTarget.ios),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('VITYO_HOSTED_TOKEN'),
        ),
      ),
    );
  });

  test(
    'hosted control-plane IO sends bearer auth and normalized URL',
    () async {
      final requests = <_LoggedRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));
      server.listen((request) async {
        requests.add(
          _LoggedRequest(
            path: request.uri.path,
            authorization: request.headers.value(
              HttpHeaders.authorizationHeader,
            ),
            accept: request.headers.value(HttpHeaders.acceptHeader),
          ),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(<String, Object?>{'message': 'ok'}));
        await request.response.close();
      });
      debugOverrideHostedEnvironment(
        _hostedEnvironmentForServer(server, basePath: '/api/styio-hosted/v1/'),
      );
      addTearDown(() => debugOverrideHostedEnvironment(null));

      final client = await createHostedControlPlaneClient(
        platformTarget: PlatformTarget.ios,
      );
      await client!.projectGraph(workspaceId: 'demo-workspace');

      expect(requests, hasLength(1));
      expect(
        requests.single.path,
        '/api/styio-hosted/v1/workspaces/demo-workspace/project-graph',
      );
      expect(requests.single.authorization, 'Bearer test-hosted-token');
      expect(requests.single.accept, 'application/json');
    },
  );

  test('hosted control-plane IO rejects non-2xx responses', () async {
    final server = await _serve((request) async {
      request.response.statusCode = HttpStatus.badGateway;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{'message': 'upstream unavailable'}),
      );
    });
    addTearDown(() async => server.close(force: true));
    debugOverrideHostedEnvironment(_hostedEnvironmentForServer(server));
    addTearDown(() => debugOverrideHostedEnvironment(null));

    final client = await createHostedControlPlaneClient(
      platformTarget: PlatformTarget.ios,
    );

    await expectLater(
      client!.openWorkspace(platformTarget: PlatformTarget.ios),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('upstream unavailable'),
        ),
      ),
    );
  });

  test('hosted control-plane IO times out slow responses', () async {
    final server = await _serve((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, Object?>{'message': 'late'}));
    });
    addTearDown(() async => server.close(force: true));
    debugOverrideHostedEnvironment(
      _hostedEnvironmentForServer(
        server,
        overrides: const <String, String>{'VITYO_HOSTED_TIMEOUT_MS': '20'},
      ),
    );
    addTearDown(() => debugOverrideHostedEnvironment(null));

    final client = await createHostedControlPlaneClient(
      platformTarget: PlatformTarget.ios,
    );

    await expectLater(
      client!.openWorkspace(platformTarget: PlatformTarget.ios),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('hosted control-plane IO bounds response body reads', () async {
    final server = await _serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode(<String, Object?>{
          'message': 'oversized',
          'payload': <String, Object?>{'blob': 'x' * 128},
        }),
      );
    });
    addTearDown(() async => server.close(force: true));
    debugOverrideHostedEnvironment(
      _hostedEnvironmentForServer(
        server,
        overrides: const <String, String>{
          'VITYO_HOSTED_MAX_RESPONSE_BYTES': '64',
        },
      ),
    );
    addTearDown(() => debugOverrideHostedEnvironment(null));

    final client = await createHostedControlPlaneClient(
      platformTarget: PlatformTarget.ios,
    );

    await expectLater(
      client!.openWorkspace(platformTarget: PlatformTarget.ios),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('exceeded 64 bytes'),
        ),
      ),
    );
  });

  test('hosted control-plane IO rejects non-object response bodies', () async {
    final server = await _serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String>['not-an-envelope']));
    });
    addTearDown(() async => server.close(force: true));
    debugOverrideHostedEnvironment(_hostedEnvironmentForServer(server));
    addTearDown(() => debugOverrideHostedEnvironment(null));

    final client = await createHostedControlPlaneClient(
      platformTarget: PlatformTarget.ios,
    );

    await expectLater(
      client!.openWorkspace(platformTarget: PlatformTarget.ios),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('JSON object'),
        ),
      ),
    );
  });

  test('hosted control-plane IO rejects non-JSON success bodies', () async {
    final server = await _serve((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.write(jsonEncode(<String, Object?>{'message': 'ok'}));
    });
    addTearDown(() async => server.close(force: true));
    debugOverrideHostedEnvironment(_hostedEnvironmentForServer(server));
    addTearDown(() => debugOverrideHostedEnvironment(null));

    final client = await createHostedControlPlaneClient(
      platformTarget: PlatformTarget.ios,
    );

    await expectLater(
      client!.openWorkspace(platformTarget: PlatformTarget.ios),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('application/json'),
        ),
      ),
    );
  });

  test('hosted control-plane IO rejects malformed envelope fields', () async {
    final server = await _serve((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, Object?>{'returncode': '0'}));
    });
    addTearDown(() async => server.close(force: true));
    debugOverrideHostedEnvironment(_hostedEnvironmentForServer(server));
    addTearDown(() => debugOverrideHostedEnvironment(null));

    final client = await createHostedControlPlaneClient(
      platformTarget: PlatformTarget.ios,
    );

    await expectLater(
      client!.toolClearPin(workspaceId: 'demo-workspace'),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('malformed "returncode"'),
        ),
      ),
    );
  });
}

class _LoggedRequest {
  const _LoggedRequest({
    required this.path,
    required this.authorization,
    required this.accept,
  });

  final String path;
  final String? authorization;
  final String? accept;
}

Future<HttpServer> _serve(
  Future<void> Function(HttpRequest request) handleRequest,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    try {
      await handleRequest(request);
      await request.response.close();
    } catch (_) {
      await request.response.close().catchError((Object _) {});
    }
  });
  return server;
}

Map<String, String> _hostedEnvironmentForServer(
  HttpServer server, {
  String basePath = '/api/styio-hosted/v1',
  Map<String, String> overrides = const <String, String>{},
}) {
  return <String, String>{
    'VITYO_HOSTED_URL':
        'http://${server.address.address}:${server.port}$basePath',
    'VITYO_HOSTED_TOKEN': 'test-hosted-token',
    'VITYO_HOSTED_WORKSPACE_ROOT': '/workspace/demo',
    'VITYO_HOSTED_MANIFEST_PATH': '/workspace/demo/spio.toml',
    ...overrides,
  };
}
