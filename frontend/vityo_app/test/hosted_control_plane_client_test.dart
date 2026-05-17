import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/integration/adapter_contracts.dart';
import 'package:vityo_app/src/integration/dependency_source_adapter.dart';
import 'package:vityo_app/src/integration/deployment_adapter.dart';
import 'package:vityo_app/src/integration/execution_adapter.dart';
import 'package:vityo_app/src/integration/hosted_control_plane.dart';
import 'package:vityo_app/src/integration/project_graph_adapter.dart';
import 'package:vityo_app/src/integration/project_graph_adapter_io.dart'
    show debugOverrideProjectGraphEnvironment;
import 'package:vityo_app/src/integration/project_graph_contract.dart';
import 'package:vityo_app/src/integration/runtime_event_adapter.dart';
import 'package:vityo_app/src/integration/toolchain_management_adapter.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test(
    'hosted adapters consume the frozen hosted control-plane contract end-to-end',
    () async {
      final requestLog = <_LoggedRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close(force: true));

      server.listen((request) async {
        final bodyText = await utf8.decoder.bind(request).join();
        final decodedBody = bodyText.isEmpty
            ? null
            : jsonDecode(bodyText) as Map<String, dynamic>;
        requestLog.add(
          _LoggedRequest(
            method: request.method,
            path: request.uri.path,
            authorization: request.headers.value(
              HttpHeaders.authorizationHeader,
            ),
            accept: request.headers.value(HttpHeaders.acceptHeader),
            body: decodedBody,
          ),
        );
        final responseBody = _responseForRequest(
          request.method,
          request.uri.path,
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(responseBody));
        await request.response.close();
      });

      final hostedEnvironment = <String, String>{
        'VITYO_HOSTED_URL':
            'http://${server.address.address}:${server.port}/api/styio-hosted/v1',
        'VITYO_HOSTED_TOKEN': 'test-hosted-token',
        'VITYO_HOSTED_WORKSPACE_ROOT': '/workspace/demo',
        'VITYO_HOSTED_MANIFEST_PATH': '/workspace/demo/spio.toml',
      };
      debugOverrideHostedEnvironment(hostedEnvironment);
      debugOverrideProjectGraphEnvironment(hostedEnvironment);
      addTearDown(() {
        debugOverrideHostedEnvironment(null);
        debugOverrideProjectGraphEnvironment(null);
      });

      final runtimeAdapter = createRuntimeEventAdapter(
        platformTarget: PlatformTarget.ios,
      );
      expect(
        runtimeAdapter.capabilitySnapshot.languageService.level,
        AdapterCapabilityLevel.unavailable,
      );
      expect(
        runtimeAdapter.capabilitySnapshot.execution.level,
        AdapterCapabilityLevel.available,
      );
      expect(
        runtimeAdapter.capabilitySnapshot.runtimeEvents.level,
        AdapterCapabilityLevel.available,
      );
      final projectGraphAdapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.ios,
      );
      final initialGraph = await projectGraphAdapter.loadProjectGraph();
      expect(initialGraph.hasHostedWorkspace, isTrue);
      expect(initialGraph.hostedWorkspace?.workspaceId, 'demo-workspace');
      expect(initialGraph.packageDistribution?.publishablePackages, 1);

      final refreshedGraph = await projectGraphAdapter.loadProjectGraph();
      expect(refreshedGraph.title, 'demo/app');
      expect(refreshedGraph.targets.map((target) => target.kind).toSet(), {
        ProjectTargetKind.bin,
        ProjectTargetKind.lib,
        ProjectTargetKind.test,
      });

      final toolchainAdapter = await createToolchainManagementAdapter(
        platformTarget: PlatformTarget.ios,
      );
      final install = await toolchainAdapter.installManagedCompiler(
        projectGraph: refreshedGraph,
        styioBinaryPath: '/toolchains/styio-0.0.2/bin/styio',
      );
      final use = await toolchainAdapter.useManagedCompiler(
        projectGraph: refreshedGraph,
        compilerVersion: '0.0.2',
        channel: 'stable',
      );
      final pin = await toolchainAdapter.pinManagedCompiler(
        projectGraph: refreshedGraph,
        compilerVersion: '0.0.2',
        channel: 'stable',
      );
      final clearPin = await toolchainAdapter.clearPinnedCompiler(
        projectGraph: refreshedGraph,
      );
      expect(install.succeeded, isTrue);
      expect(use.succeeded, isTrue);
      expect(pin.succeeded, isTrue);
      expect(clearPin.succeeded, isTrue);
      expect(install.payload?['compiler_version'], '0.0.2');

      final dependencyAdapter = await createDependencySourceAdapter(
        platformTarget: PlatformTarget.ios,
      );
      final fetch = await dependencyAdapter.fetchDependencies(
        projectGraph: refreshedGraph,
        locked: true,
        offline: true,
      );
      final vendor = await dependencyAdapter.vendorDependencies(
        projectGraph: refreshedGraph,
        outputPath: '/workspace/demo/vendor-snapshot',
        locked: true,
        offline: false,
      );
      expect(fetch.succeeded, isTrue);
      expect(vendor.succeeded, isTrue);
      expect(fetch.payload?['locked'], isTrue);
      expect(vendor.payload?['output_path'], '/workspace/demo/vendor-snapshot');

      final deploymentAdapter = await createDeploymentAdapter(
        platformTarget: PlatformTarget.ios,
      );
      final pack = await deploymentAdapter.packProject(
        projectGraph: refreshedGraph,
        packageName: 'demo/app',
        outputPath: '/workspace/demo/dist',
      );
      final preflight = await deploymentAdapter.preparePublish(
        projectGraph: refreshedGraph,
      );
      final publish = await deploymentAdapter.publishToRegistry(
        projectGraph: refreshedGraph,
        registryRoot: '/registry/local',
      );
      expect(pack.succeeded, isTrue);
      expect(preflight.succeeded, isTrue);
      expect(publish.succeeded, isTrue);
      expect(
        pack.payload?['archive_path'],
        '/workspace/demo/dist/demo-app.tar',
      );
      expect(publish.payload?['registry_root'], '/registry/local');

      final executionAdapter = await createExecutionAdapter(
        platformTarget: PlatformTarget.ios,
        projectGraph: refreshedGraph,
      );
      final runSession = await executionAdapter.runActiveDocument(
        platformTarget: PlatformTarget.ios,
        projectGraph: refreshedGraph,
        document: const DocumentState(
          documentId: '/workspace/demo/src/main.styio',
          text: '>_("run")\n',
          revision: 0,
        ),
        activeFilePath: '/workspace/demo/src/main.styio',
      );
      final buildSession = await executionAdapter.runActiveDocument(
        platformTarget: PlatformTarget.ios,
        projectGraph: refreshedGraph,
        document: const DocumentState(
          documentId: '/workspace/demo/src/lib.styio',
          text: 'pub fn demo() {}\n',
          revision: 0,
        ),
        activeFilePath: '/workspace/demo/src/lib.styio',
      );
      final testSession = await executionAdapter.runActiveDocument(
        platformTarget: PlatformTarget.ios,
        projectGraph: refreshedGraph,
        document: const DocumentState(
          documentId: '/workspace/demo/tests/render_test.styio',
          text: 'test "render" {}\n',
          revision: 0,
        ),
        activeFilePath: '/workspace/demo/tests/render_test.styio',
      );

      expect(runSession.status, ExecutionSessionStatus.succeeded);
      expect(buildSession.status, ExecutionSessionStatus.succeeded);
      expect(testSession.status, ExecutionSessionStatus.failed);
      expect(testSession.diagnostics, hasLength(1));
      expect(testSession.diagnostics.single.message, 'assertion failed');
      expect(runSession.kind, 'run');
      expect(buildSession.kind, 'build');
      expect(testSession.kind, 'test');

      final runEvents = await runtimeAdapter
          .sessionEvents(runSession.sessionId)
          .toList();
      final buildEvents = await runtimeAdapter
          .sessionEvents(buildSession.sessionId)
          .toList();
      final testEvents = await runtimeAdapter
          .sessionEvents(testSession.sessionId)
          .toList();
      addTearDown(() {
        clearRuntimeEventsForSession(runSession.sessionId);
        clearRuntimeEventsForSession(buildSession.sessionId);
        clearRuntimeEventsForSession(testSession.sessionId);
      });
      expect(
        runEvents.map((event) => event.eventKind),
        contains('runtime.stdout'),
      );
      expect(
        buildEvents.map((event) => event.eventKind),
        contains('compile.finished'),
      );
      expect(
        testEvents.map((event) => event.eventKind),
        contains('test.failed'),
      );

      final hostedClient = await createHostedControlPlaneClient(
        platformTarget: PlatformTarget.ios,
      );
      final loadedDocument = await hostedClient!.loadDocument(
        workspaceId: 'demo-workspace',
        path: '/workspace/demo/src/main.styio',
      );
      final savedDocument = await hostedClient.saveDocument(
        workspaceId: 'demo-workspace',
        path: '/workspace/demo/src/main.styio',
        documentText: 'remote := true\n',
        revision: 4,
      );
      expect(loadedDocument['payload'], <String, Object?>{
        'path': '/workspace/demo/src/main.styio',
        'document_text': 'remote := true\n',
        'revision': 3,
      });
      expect(savedDocument['payload'], <String, Object?>{
        'path': '/workspace/demo/src/main.styio',
        'revision': 4,
        'saved': true,
      });

      expect(requestLog.map((entry) => '${entry.method} ${entry.path}').toList(), <
        String
      >[
        'POST /api/styio-hosted/v1/workspaces/open',
        'GET /api/styio-hosted/v1/workspaces/demo-workspace/project-graph',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/install',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/use',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/pin',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/clear-pin',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/dependencies/fetch',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/dependencies/vendor',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/deployment/pack',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/deployment/preflight',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/deployment/publish',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/execution/run',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/execution/build',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/execution/test',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/documents/load',
        'POST /api/styio-hosted/v1/workspaces/demo-workspace/documents/save',
      ]);
      expect(requestLog.map((entry) => entry.authorization).toSet(), <String?>{
        'Bearer test-hosted-token',
      });
      expect(requestLog.map((entry) => entry.accept).toSet(), <String?>{
        'application/json',
      });

      expect(requestLog[0].body, <String, dynamic>{
        'workspace_root': '/workspace/demo',
        'manifest_path': '/workspace/demo/spio.toml',
        'platform': 'ios',
      });
      expect(requestLog[2].body, <String, dynamic>{
        'styio_binary_path': '/toolchains/styio-0.0.2/bin/styio',
      });
      expect(requestLog[3].body, <String, dynamic>{
        'compiler_version': '0.0.2',
        'channel': 'stable',
      });
      expect(requestLog[5].body, <String, dynamic>{});
      expect(requestLog[6].body, <String, dynamic>{
        'locked': true,
        'offline': true,
      });
      expect(requestLog[7].body, <String, dynamic>{
        'output_path': '/workspace/demo/vendor-snapshot',
        'locked': true,
        'offline': false,
      });
      expect(requestLog[8].body, <String, dynamic>{
        'package_name': 'demo/app',
        'output_path': '/workspace/demo/dist',
      });
      expect(requestLog[9].body, <String, dynamic>{'package_name': 'demo/app'});
      expect(requestLog[10].body, <String, dynamic>{
        'registry_root': '/registry/local',
        'package_name': 'demo/app',
      });
      expect(requestLog[11].body, <String, dynamic>{
        'active_file_path': '/workspace/demo/src/main.styio',
        'document_text': '>_("run")\n',
        'package_name': 'demo/app',
        'target_name': 'demo',
        'target_kind': 'bin',
      });
      expect(requestLog[12].body, <String, dynamic>{
        'active_file_path': '/workspace/demo/src/lib.styio',
        'document_text': 'pub fn demo() {}\n',
        'package_name': 'demo/app',
        'target_kind': 'lib',
      });
      expect(requestLog[13].body, <String, dynamic>{
        'active_file_path': '/workspace/demo/tests/render_test.styio',
        'document_text': 'test "render" {}\n',
        'package_name': 'demo/app',
        'target_name': 'render',
        'target_kind': 'test',
      });
      expect(requestLog[14].body, <String, dynamic>{
        'path': '/workspace/demo/src/main.styio',
      });
      expect(requestLog[15].body, <String, dynamic>{
        'path': '/workspace/demo/src/main.styio',
        'document_text': 'remote := true\n',
        'revision': 4,
      });
    },
  );

  test(
    'cloud runtime event adapter stays unavailable without hosted route',
    () async {
      debugOverrideHostedEnvironment(null);
      recordRuntimeEventsForSession(
        'unconfigured-cloud-session',
        <RuntimeEventEnvelope>[
          RuntimeEventEnvelope(
            schemaVersion: 1,
            sessionId: 'unconfigured-cloud-session',
            sequence: 1,
            timestamp: DateTime.utc(2026, 4, 21, 0, 0, 0),
            eventKind: 'run.finished',
            origin: 'test',
            payload: const <String, Object?>{'success': true},
          ),
        ],
      );
      addTearDown(() {
        debugOverrideHostedEnvironment(null);
        clearRuntimeEventsForSession('unconfigured-cloud-session');
      });

      final runtimeAdapter = createRuntimeEventAdapter(
        platformTarget: PlatformTarget.ios,
      );

      expect(
        runtimeAdapter.capabilitySnapshot.execution.level,
        AdapterCapabilityLevel.unavailable,
      );
      expect(
        runtimeAdapter.capabilitySnapshot.runtimeEvents.level,
        AdapterCapabilityLevel.unavailable,
      );
      expect(
        await runtimeAdapter
            .sessionEvents('unconfigured-cloud-session')
            .toList(),
        isEmpty,
      );
    },
  );
}

class _LoggedRequest {
  const _LoggedRequest({
    required this.method,
    required this.path,
    required this.authorization,
    required this.accept,
    required this.body,
  });

  final String method;
  final String path;
  final String? authorization;
  final String? accept;
  final Map<String, dynamic>? body;
}

Map<String, dynamic> _responseForRequest(String method, String path) {
  return switch ('$method $path') {
    'POST /api/styio-hosted/v1/workspaces/open' => _openWorkspaceResponse(
      message: 'opened hosted workspace',
    ),
    'GET /api/styio-hosted/v1/workspaces/demo-workspace/project-graph' =>
      _projectGraphResponse(),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/install' =>
      _hostedCommandResponse(
        message: 'installed managed compiler',
        payload: <String, Object?>{
          'compiler_version': '0.0.2',
          'channel': 'stable',
          'install_root': '/workspace/demo/.spio/tools/styio/0.0.2',
          'install_binary_path':
              '/workspace/demo/.spio/tools/styio/0.0.2/bin/styio',
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/use' =>
      _hostedCommandResponse(
        message: 'activated managed compiler',
        payload: <String, Object?>{
          'compiler_version': '0.0.2',
          'channel': 'stable',
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/pin' =>
      _hostedCommandResponse(
        message: 'pinned managed compiler',
        payload: <String, Object?>{
          'compiler_version': '0.0.2',
          'channel': 'stable',
          'pin_path': '/workspace/demo/spio-toolchain.toml',
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/tool/clear-pin' =>
      _hostedCommandResponse(
        message: 'cleared managed compiler pin',
        payload: <String, Object?>{'pin_cleared': true},
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/dependencies/fetch' =>
      _hostedCommandResponse(
        message: 'fetched dependencies',
        payload: <String, Object?>{
          'packages': 3,
          'git_packages': 1,
          'registry_packages': 2,
          'locked': true,
          'offline': true,
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/dependencies/vendor' =>
      _hostedCommandResponse(
        message: 'vendored dependencies',
        payload: <String, Object?>{
          'packages': 3,
          'output_path': '/workspace/demo/vendor-snapshot',
          'locked': true,
          'offline': false,
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/deployment/pack' =>
      _hostedCommandResponse(
        message: 'packed project archive',
        payload: <String, Object?>{
          'package': 'demo/app',
          'archive_path': '/workspace/demo/dist/demo-app.tar',
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/deployment/preflight' =>
      _hostedCommandResponse(
        message: 'prepared publish candidate',
        payload: <String, Object?>{
          'package': 'demo/app',
          'archive_path': '/workspace/demo/dist/demo-app.tar',
          'mode': 'dry-run',
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/deployment/publish' =>
      _hostedCommandResponse(
        message: 'published package to registry',
        payload: <String, Object?>{
          'package': 'demo/app',
          'archive_path': '/workspace/demo/dist/demo-app.tar',
          'registry_root': '/registry/local',
          'mode': 'publish',
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/execution/run' =>
      _executionResponse(
        message: 'Project binary run completed through spio.',
        sessionId: 'hosted-run-session',
        returncode: 0,
        eventKind: 'runtime.stdout',
        origin: 'styio.runtime',
        payload: <String, Object?>{
          'stdout': 'demo run ok\n',
          'runtime_events': <Map<String, Object?>>[
            <String, Object?>{
              'schema_version': 1,
              'session_id': 'hosted-run-session',
              'sequence': 1,
              'timestamp': '2026-04-21T00:00:20Z',
              'eventKind': 'runtime.stdout',
              'origin': 'styio.runtime',
              'payload': <String, Object?>{'line': 'demo run ok'},
            },
          ],
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/execution/build' =>
      _executionResponse(
        message: 'Project library build completed through spio.',
        sessionId: 'hosted-build-session',
        returncode: 0,
        eventKind: 'compile.finished',
        origin: 'styio.compile-plan',
        payload: <String, Object?>{
          'stdout': 'build ok\n',
          'runtime_events': <Map<String, Object?>>[
            <String, Object?>{
              'schema_version': 1,
              'session_id': 'hosted-build-session',
              'sequence': 1,
              'timestamp': '2026-04-21T00:00:30Z',
              'eventKind': 'compile.finished',
              'origin': 'styio.compile-plan',
              'payload': <String, Object?>{'intent': 'build'},
            },
          ],
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/execution/test' =>
      _executionFailureResponse(),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/documents/load' =>
      _hostedCommandResponse(
        message: 'loaded hosted document',
        payload: <String, Object?>{
          'path': '/workspace/demo/src/main.styio',
          'document_text': 'remote := true\n',
          'revision': 3,
        },
      ),
    'POST /api/styio-hosted/v1/workspaces/demo-workspace/documents/save' =>
      _hostedCommandResponse(
        message: 'saved hosted document',
        payload: <String, Object?>{
          'path': '/workspace/demo/src/main.styio',
          'revision': 4,
          'saved': true,
        },
      ),
    _ => <String, Object?>{
      'returncode': 1,
      'message': 'unexpected route',
      'stdout': '',
      'stderr': 'unexpected route',
      'error_payload': <String, Object?>{
        'code': 'test.unexpected_route',
        'reason': path,
        'retryable': false,
        'details': <String, Object?>{'method': method},
      },
    },
  };
}

Map<String, dynamic> _openWorkspaceResponse({required String message}) {
  return <String, dynamic>{
    'returncode': 0,
    'message': message,
    'stdout': '',
    'stderr': '',
    'payload': _projectGraphPayload(),
    'workspace': _hostedWorkspaceRecord(),
  };
}

Map<String, dynamic> _projectGraphResponse() {
  return <String, dynamic>{
    'returncode': 0,
    'message': 'refreshed hosted project graph',
    'stdout': '',
    'stderr': '',
    'payload': _projectGraphPayload(),
    'workspace': _hostedWorkspaceRecord(),
  };
}

Map<String, dynamic> _hostedCommandResponse({
  required String message,
  required Map<String, Object?> payload,
}) {
  return <String, dynamic>{
    'returncode': 0,
    'message': message,
    'stdout': '',
    'stderr': '',
    'payload': payload,
  };
}

Map<String, dynamic> _executionResponse({
  required String message,
  required String sessionId,
  required int returncode,
  required String eventKind,
  required String origin,
  required Map<String, Object?> payload,
}) {
  return <String, dynamic>{
    'returncode': returncode,
    'message': message,
    'stdout': payload['stdout'] ?? '',
    'stderr': '',
    'payload': <String, Object?>{
      'session_id': sessionId,
      'runtime_events': payload['runtime_events'],
      'stdout': payload['stdout'],
    },
  };
}

Map<String, dynamic> _executionFailureResponse() {
  return <String, dynamic>{
    'returncode': 1,
    'message': 'Project test target failed through spio.',
    'stdout': '',
    'stderr': 'assertion failed',
    'error_payload': <String, Object?>{
      'session_id': 'hosted-test-session',
      'diagnostics': <Map<String, Object?>>[
        <String, Object?>{
          'category': 'test',
          'severity': 'error',
          'file': '/workspace/demo/tests/render_test.styio',
          'message': 'assertion failed',
          'range': <String, Object?>{'start': 5, 'end': 12},
        },
      ],
      'runtime_events': <Map<String, Object?>>[
        <String, Object?>{
          'schema_version': 1,
          'session_id': 'hosted-test-session',
          'sequence': 1,
          'timestamp': '2026-04-21T00:00:40Z',
          'eventKind': 'test.failed',
          'origin': 'styio.test',
          'payload': <String, Object?>{'suite': 'render'},
        },
      ],
    },
  };
}

Map<String, dynamic> _hostedWorkspaceRecord() {
  return <String, dynamic>{
    'workspaceId': 'demo-workspace',
    'schemaVersion': '1',
    'ownerRef': 'Vityo',
    'status': 'active',
    'entryUrl': 'https://hosted.example.test/workspaces/demo-workspace',
    'createdAt': '2026-04-21T00:00:00Z',
    'lastActiveAt': '2026-04-21T00:00:10Z',
    'retentionDays': 7,
    'exportState': 'not_requested',
  };
}

Map<String, dynamic> _projectGraphPayload() {
  return <String, dynamic>{
    'id': '/workspace/demo/spio.toml',
    'title': 'demo/app',
    'kind': 'hosted',
    'workspace_root': '/workspace/demo',
    'workspace_members': const <String>[],
    'manifest_path': '/workspace/demo/spio.toml',
    'lockfile_path': '/workspace/demo/spio.lock',
    'toolchain_pin_path': '/workspace/demo/spio-toolchain.toml',
    'styio_config_path': '/workspace/demo/styio.toml',
    'vendor_root': '/workspace/demo/.spio/vendor',
    'build_root': '/workspace/demo/.spio/build',
    'packages': <Map<String, Object?>>[
      <String, Object?>{
        'package_name': 'demo/app',
        'version': '0.1.0',
        'root_path': '/workspace/demo',
        'manifest_path': '/workspace/demo/spio.toml',
        'targets': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'demo/app:bin:demo',
            'package_name': 'demo/app',
            'kind': 'bin',
            'name': 'demo',
            'file_path': '/workspace/demo/src/main.styio',
          },
          <String, Object?>{
            'id': 'demo/app:lib',
            'package_name': 'demo/app',
            'kind': 'lib',
            'name': 'demo',
            'file_path': '/workspace/demo/src/lib.styio',
          },
          <String, Object?>{
            'id': 'demo/app:test:render',
            'package_name': 'demo/app',
            'kind': 'test',
            'name': 'render',
            'file_path': '/workspace/demo/tests/render_test.styio',
          },
        ],
        'dependencies': <Map<String, Object?>>[
          <String, Object?>{
            'source_package_name': 'demo/app',
            'dependency_name': 'palette',
            'kind': 'runtime',
            'requirement': 'registry:https://packages.example.test@1.0.0',
            'source_kind': 'registry',
            'registry': 'https://packages.example.test',
            'package': 'palette',
            'version': '1.0.0',
            'publish_blocking': false,
          },
        ],
        'is_workspace_member': false,
        'publish_enabled': true,
      },
    ],
    'dependencies': <Map<String, Object?>>[
      <String, Object?>{
        'source_package_name': 'demo/app',
        'dependency_name': 'palette',
        'kind': 'runtime',
        'requirement': 'registry:https://packages.example.test@1.0.0',
        'source_kind': 'registry',
        'registry': 'https://packages.example.test',
        'package': 'palette',
        'version': '1.0.0',
        'publish_blocking': false,
      },
    ],
    'targets': <Map<String, Object?>>[
      <String, Object?>{
        'id': 'demo/app:bin:demo',
        'package_name': 'demo/app',
        'kind': 'bin',
        'name': 'demo',
        'file_path': '/workspace/demo/src/main.styio',
      },
      <String, Object?>{
        'id': 'demo/app:lib',
        'package_name': 'demo/app',
        'kind': 'lib',
        'name': 'demo',
        'file_path': '/workspace/demo/src/lib.styio',
      },
      <String, Object?>{
        'id': 'demo/app:test:render',
        'package_name': 'demo/app',
        'kind': 'test',
        'name': 'render',
        'file_path': '/workspace/demo/tests/render_test.styio',
      },
    ],
    'editor_files': <String>[
      '/workspace/demo/src/main.styio',
      '/workspace/demo/src/lib.styio',
      '/workspace/demo/tests/render_test.styio',
    ],
    'toolchain': <String, Object?>{
      'source': 'project-pin',
      'detail': 'Pinned compiler is active.',
      'pin_path': '/workspace/demo/spio-toolchain.toml',
      'channel': 'stable',
      'version': '0.0.1',
    },
    'lock_state': 'fresh',
    'vendor_state': 'present',
    'active_compiler': <String, Object?>{
      'binary_path': '/workspace/demo/.spio/tools/styio/current/bin/styio',
      'tool': 'styio',
      'compiler_version': '0.0.1',
      'channel': 'stable',
      'variant': 'full',
      'capabilities': <String>['machine_info_json', 'compile_plan'],
      'supported_contract_versions': <String, Object?>{
        'compile_plan': <int>[1],
        'runtime_events': <int>[1],
      },
      'integration_phase': 'hosted-product',
      'supported_adapter_modes': <String>['cloud', 'cli'],
      'feature_flags': <String, Object?>{'runtime_events': true},
    },
    'managed_toolchains': <String, Object?>{
      'spio_home': '/workspace/demo/.spio',
      'current_binary': '/workspace/demo/.spio/tools/styio/current/bin/styio',
      'current_metadata_path':
          '/workspace/demo/.spio/tools/styio/current/metadata.json',
      'installed': <Map<String, Object?>>[
        <String, Object?>{
          'channel': 'stable',
          'compiler_version': '0.0.1',
          'install_root': '/workspace/demo/.spio/tools/styio/0.0.1',
          'install_binary_path':
              '/workspace/demo/.spio/tools/styio/0.0.1/bin/styio',
          'install_metadata_path':
              '/workspace/demo/.spio/tools/styio/0.0.1/metadata.json',
        },
      ],
    },
    'package_distribution': <String, Object?>{
      'schema_version': 1,
      'packages': <Map<String, Object?>>[
        <String, Object?>{
          'package_name': 'demo/app',
          'manifest_path': '/workspace/demo/spio.toml',
          'publish_enabled': true,
          'publish_ready': true,
          'blocking_reasons': const <String>[],
          'runtime_registry_dependencies': 1,
          'runtime_path_dependencies': 0,
          'runtime_git_dependencies': 0,
          'dev_registry_dependencies': 0,
          'dev_path_dependencies': 0,
          'dev_git_dependencies': 0,
        },
      ],
      'registry_sources': <Map<String, Object?>>[
        <String, Object?>{
          'registry_root': 'https://packages.example.test',
          'transport': 'https',
          'dependency_refs': 1,
          'packages': <String>['palette'],
        },
      ],
      'publishable_packages': 1,
      'blocked_packages': 0,
    },
    'source_state': <String, Object?>{
      'schema_version': 1,
      'spio_home': '/workspace/demo/.spio',
      'declared_git_dependencies': 0,
      'declared_registry_dependencies': 1,
      'git_cache': <String, Object?>{
        'repos_root': '/workspace/demo/.spio/git/repos',
        'checkouts_root': '/workspace/demo/.spio/git/checkouts',
        'repos_present': true,
        'checkouts_present': true,
      },
      'registry_cache': <String, Object?>{
        'cache_root': '/workspace/demo/.spio/registry',
        'index_root': '/workspace/demo/.spio/registry/index',
        'blob_root': '/workspace/demo/.spio/registry/blobs',
        'checkout_root': '/workspace/demo/.spio/registry/checkouts',
        'index_present': true,
        'blobs_present': true,
        'checkouts_present': true,
      },
      'vendor': <String, Object?>{
        'vendor_root': '/workspace/demo/.spio/vendor',
        'metadata_path': '/workspace/demo/.spio/vendor/vendor.json',
        'vendor_present': true,
        'metadata_present': true,
        'git_snapshots': 0,
      },
    },
    'notes': <String>['Hosted project graph ready.'],
  };
}
