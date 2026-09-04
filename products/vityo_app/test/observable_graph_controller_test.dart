import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProjectGraphSnapshot graph({
    CompilerHandshakeSnapshot? compiler,
    String? manifestPath = 'Styio.toml',
  }) {
    return ProjectGraphSnapshot(
      id: 'example',
      title: 'example',
      kind: ProjectKind.package,
      workspaceRoot: 'workspace',
      workspaceMembers: const <String>['example.app'],
      packages: const <ProjectPackageSnapshot>[
        ProjectPackageSnapshot(
          packageName: 'example.app',
          version: '0.0.1',
          rootPath: 'workspace',
          manifestPath: 'Styio.toml',
          targets: <ProjectTargetDescriptor>[],
        ),
      ],
      dependencies: const <ProjectDependencySnapshot>[],
      targets: const <ProjectTargetDescriptor>[],
      editorFiles: const <String>[],
      toolchain: const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.environment,
        detail: 'test',
      ),
      lockState: ProjectLockState.fresh,
      vendorState: ProjectVendorState.present,
      notes: const <String>[],
      manifestPath: manifestPath,
      activeCompiler: compiler,
    );
  }

  CompilerHandshakeSnapshot compiler({
    List<int> versions = const <int>[1],
    List<String> capabilities = kObservableRequiredCapabilities,
  }) {
    return CompilerHandshakeSnapshot(
      binaryPath: 'styio',
      tool: 'styio',
      compilerVersion: '0.0.1',
      channel: 'nightly',
      variant: 'full',
      capabilities: const <String>['compile-plan'],
      supportedContractVersions: const <String, List<int>>{
        'compile_plan': <int>[1],
      },
      integrationPhase: 'compile-plan-live',
      observableStaticSnapshotSchemaVersions: versions,
      observableStaticSnapshotCapabilities: capabilities,
    );
  }

  test('coalesced saves yield one run and later events cancel in-flight work', () async {
    final canonical = readObservableFixtureBytes('vityo-authored-canonical.json');
    final edited = readObservableFixtureBytes('edited.json');
    final watch = StreamController<FileSystemManagerEvent>.broadcast();
    addTearDown(watch.close);
    final delays = <Completer<void>>[];
    final publisher = _FakePublisher()
      ..successes.addAll(<List<int>>[canonical, canonical, edited]);
    final controller = ObservableGraphController(
      publisher: publisher,
      projectGraph: () => graph(compiler: compiler()),
      ioPlatform: true,
      watchStream: watch.stream,
      delay: (_) {
        final gate = Completer<void>();
        delays.add(gate);
        return gate.future;
      },
      resolvePafio: () async => 'pafio',
    );
    addTearDown(controller.dispose);

    await controller.start();
    expect(publisher.calls, 1);
    expect(controller.state.availability, ObservableAvailability.fresh);

    watch.add(_event('src/main.styio'));
    watch.add(_event('src/aux.styio'));
    watch.add(_event('src/main.styio'));
    await _flush();
    expect(delays, isNotEmpty);
    delays.last.complete();
    await _flush();
    expect(publisher.calls, 2);

    publisher.hold = Completer<void>();
    watch.add(_event('src/main.styio'));
    await _flush();
    delays.last.complete();
    await _flush();
    expect(publisher.calls, 3);
    watch.add(_event('src/flow.styio'));
    await _flush();
    delays.last.complete();
    await _flush();
    expect(publisher.cancelCount, greaterThan(0));
    expect(
      controller.state.changeSet?.addedNodeIds,
      contains('n1_0100000000000000000000000000000c'),
    );
    expect(
      controller.state.changeSet?.removedNodeIds,
      contains('n1_0100000000000000000000000000000a'),
    );
    expect(
      controller.state.changeSet?.addedEdgeIds,
      contains('e1_0200000000000000000000000000000c'),
    );
    expect(
      controller.state.changeSet?.removedEdgeIds,
      contains('e1_0200000000000000000000000000000a'),
    );

    publisher.failWith = 'check exploded';
    watch.add(_event('src/main.styio'));
    await _flush();
    delays.last.complete();
    await _flush();
    expect(controller.state.availability, ObservableAvailability.stale);
    expect(controller.state.reason, ObservableReasonCode.publicationFailed);
    expect(controller.state.projection, isNotNull);

    publisher.failWith = null;
    publisher.successes.add(edited);
    final identity = controller.state.currentIdentity;
    watch.add(_event('src/main.styio'));
    await _flush();
    delays.last.complete();
    await _flush();
    expect(controller.state.currentIdentity, identity);

    final runs = publisher.calls;
    watch.add(_event('example.observable-static-snapshot.json'));
    if (delays.isNotEmpty && !delays.last.isCompleted) {
      delays.last.complete();
    }
    await _flush();
    expect(publisher.calls, runs);
  });

  test('scalar-noop fixture renders scalar-noop and unsupported toolchains spawn nothing', () async {
    final publisher = _FakePublisher()
      ..successes.add(readObservableFixtureBytes('proven-scalar-noop.json'));
    final watch = StreamController<FileSystemManagerEvent>.broadcast();
    addTearDown(watch.close);
    final ok = ObservableGraphController(
      publisher: publisher,
      projectGraph: () => graph(compiler: compiler()),
      ioPlatform: true,
      watchStream: watch.stream,
      delay: (_) async {},
      resolvePafio: () async => 'pafio',
    );
    addTearDown(ok.dispose);
    await ok.start();
    expect(ok.state.availability, ObservableAvailability.scalarNoop);

    final blockedPublisher = _FakePublisher();
    final blockedWatch = StreamController<FileSystemManagerEvent>.broadcast();
    addTearDown(blockedWatch.close);
    var pafioProbes = 0;
    final blocked = ObservableGraphController(
      publisher: blockedPublisher,
      projectGraph: () => graph(
        compiler: compiler(versions: const <int>[]),
      ),
      ioPlatform: true,
      watchStream: blockedWatch.stream,
      delay: (_) async {},
      resolvePafio: () async {
        pafioProbes += 1;
        return 'pafio';
      },
    );
    addTearDown(blocked.dispose);
    await blocked.start();
    expect(blockedPublisher.calls, 0);
    expect(blocked.watchAttached, isFalse);
    expect(
      pafioProbes,
      0,
      reason:
          'a capability-absent toolchain must not spawn even a pafio probe',
    );
    expect(blocked.state.availability, ObservableAvailability.unsupported);
  });
}

FileSystemManagerEvent _event(String path) {
  return FileSystemManagerEvent(
    kind: FileSystemManagerEventKind.modified,
    path: path,
    normalizedPath: path,
  );
}

class _FakePublisher implements ObservableSnapshotPublisher {
  final List<List<int>> successes = <List<int>>[];
  Completer<void>? hold;
  String? failWith;
  int calls = 0;
  int cancelCount = 0;
  int _publishToken = 0;
  int _cancelledToken = 0;

  @override
  Future<ObservableSnapshotPublishResult> publish(
    ObservableSnapshotPublishRequest request,
  ) async {
    final token = ++_publishToken;
    calls += 1;
    final pending = hold;
    if (pending != null) {
      await pending.future;
    }
    if (_cancelledToken >= token) {
      return ObservableSnapshotPublishResult.cancelled();
    }
    if (failWith != null) {
      return ObservableSnapshotPublishResult.failed(detail: failWith!);
    }
    final index = token - 1;
    final bytes = successes[index < successes.length ? index : successes.length - 1];
    return ObservableSnapshotPublishResult.succeeded(
      bytes: bytes,
      artifactPath: 'example.observable-static-snapshot.json',
      receipt: null,
    );
  }

  @override
  void cancel() {
    cancelCount += 1;
    _cancelledToken = _publishToken;
    final pending = hold;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
  }
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 20));
}
