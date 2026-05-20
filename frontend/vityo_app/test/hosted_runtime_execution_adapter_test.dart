import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test(
    'hosted runtime execution adapter runs workflow into live output',
    () async {
      final client = _RecordingHostedControlPlaneClient();
      const definition = RuntimeTaskDefinition(
        id: 'hosted-run',
        label: 'Hosted run',
        kind: RuntimeTaskKind.run,
        command: 'hosted',
      );
      final binding = const RuntimeExecutionPlanner()
          .plan(definition: definition)
          .createHandoff(
            target: RuntimeExecutionHandoffTarget.hostedExecutor,
            outputChannelId: 'hosted.runtime',
          )
          .bind();
      final buffer = RuntimeOutputLiveBuffer();
      addTearDown(buffer.dispose);
      final adapter = HostedRuntimeExecutionAdapter(
        client: client,
        clock: () => DateTime.utc(2026, 5, 20, 13),
      );

      final result = await adapter.executeHandoff(
        binding: binding,
        buffer: buffer,
        activeFilePath: '/workspace/src/main.styio',
        documentText: '>_("demo")\n',
        packageName: 'demo/app',
        targetName: 'demo',
        targetKind: 'bin',
      );

      expect(client.runCount, 1);
      expect(client.lastWorkspaceId, 'hosted-workspace');
      expect(client.lastPackageName, 'demo/app');
      expect(result.executed, isTrue);
      expect(result.succeeded, isTrue);
      expect(result.session?.sessionId, 'hosted-session-1');
      expect(result.runtimeEvents.single.eventKind, 'run.finished');
      expect(result.toJson()['succeeded'], isTrue);
      expect(
        buffer.snapshot.visibleEvents.map((event) => event.message),
        containsAll(<String>[
          'hosted run ok',
          'hosted stdout',
          'run.finished from styio.hosted',
        ]),
      );
      expect(
        buffer
            .snapshot
            .visibleEvents
            .first
            .metadata['hostedRuntimeExecutionStatus'],
        'executed',
      );
    },
  );

  test('hosted runtime execution adapter rejects wrong route', () async {
    final client = _RecordingHostedControlPlaneClient();
    const definition = RuntimeTaskDefinition(
      id: 'shell-run',
      label: 'Shell run',
      kind: RuntimeTaskKind.shell,
      command: 'printf',
    );
    final binding = const RuntimeExecutionPlanner()
        .plan(definition: definition)
        .createHandoff(target: RuntimeExecutionHandoffTarget.shellManager)
        .bind();
    final buffer = RuntimeOutputLiveBuffer();
    addTearDown(buffer.dispose);
    final adapter = HostedRuntimeExecutionAdapter(
      client: client,
      clock: () => DateTime.utc(2026, 5, 20, 13),
    );

    final result = await adapter.executeHandoff(
      binding: binding,
      buffer: buffer,
      activeFilePath: '/workspace/src/main.styio',
      documentText: '>_("demo")\n',
    );

    expect(result.status, HostedRuntimeExecutionStatus.wrongRoute);
    expect(client.runCount, 0);
    expect(buffer.snapshot.visibleEvents.single.message, contains('ignored'));
    expect(
      buffer
          .snapshot
          .visibleEvents
          .single
          .metadata['hostedRuntimeExecutionStatus'],
      'wrong-route',
    );
  });
}

class _RecordingHostedControlPlaneClient implements HostedControlPlaneClient {
  int runCount = 0;
  String? lastWorkspaceId;
  String? lastPackageName;

  @override
  HostedControlPlaneConfig get config => const HostedControlPlaneConfig(
    baseUrl: 'https://hosted.example.test',
    workspaceRoot: '/workspace',
    workspaceId: 'hosted-workspace',
    forceHostedRoute: true,
  );

  @override
  Future<Map<String, dynamic>> runWorkflow({
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  }) async {
    runCount += 1;
    lastWorkspaceId = workspaceId;
    lastPackageName = packageName;
    return <String, dynamic>{
      'returncode': 0,
      'message': 'hosted run ok',
      'payload': <String, dynamic>{
        'session_id': 'hosted-session-1',
        'stdout': 'hosted stdout\n',
        'runtime_events': <Map<String, dynamic>>[
          <String, dynamic>{
            'schema_version': 1,
            'session_id': 'hosted-session-1',
            'sequence': 1,
            'timestamp': '2026-05-20T13:00:00Z',
            'event_kind': 'run.finished',
            'origin': 'styio.hosted',
            'payload': <String, Object?>{'success': true},
          },
        ],
      },
    };
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
    throw UnimplementedError();
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
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> fetchDependencies({
    required String workspaceId,
    bool locked = false,
    bool offline = false,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> loadDocument({
    required String workspaceId,
    required String path,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> openWorkspace({
    required PlatformTarget platformTarget,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> packProject({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> preparePublish({
    required String workspaceId,
    String? packageName,
    String? outputPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> projectGraph({required String workspaceId}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> publishToRegistry({
    required String workspaceId,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> saveDocument({
    required String workspaceId,
    required String path,
    required String documentText,
    required int revision,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> toolClearPin({required String workspaceId}) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> toolInstall({
    required String workspaceId,
    required String styioBinaryPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> toolPin({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> toolUse({
    required String workspaceId,
    required String compilerVersion,
    String? channel,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, dynamic>> vendorDependencies({
    required String workspaceId,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) {
    throw UnimplementedError();
  }
}
