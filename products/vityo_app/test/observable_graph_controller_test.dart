import 'dart:async';
import 'dart:convert';

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
    List<String> optionalCapabilities = const <String>[],
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
      observableStaticSnapshotOptionalCapabilities: optionalCapabilities,
    );
  }

  test(
    'coalesced saves yield one run and later events cancel in-flight work',
    () async {
      final canonical = readObservableFixtureBytes(
        'vityo-authored-canonical.json',
      );
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
    },
  );

  test(
    'scalar-noop fixture renders scalar-noop and unsupported toolchains spawn nothing',
    () async {
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
        projectGraph: () => graph(compiler: compiler(versions: const <int>[])),
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
    },
  );

  test(
    'advertised toolchain applies producer deltas and recovers from rejection',
    () async {
      final parent = readObservableTopologyFixtureBytes('parent/complete.json');
      final fieldChild = readObservableTopologyFixtureBytes(
        'child/field-change.json',
      );
      final fieldDelta = readObservableTopologyFixtureBytes(
        'delta/field-change.json',
      );
      final wrongParent = readObservableTopologyFixtureBytes(
        'vityo/delta/wrong-parent.json',
      );
      final publisher = _FakePublisher()
        ..successes.addAll(<List<int>>[
          parent,
          fieldChild,
          fieldChild,
          fieldChild,
          fieldChild,
        ])
        ..deltas.addAll(<List<int>?>[
          null,
          fieldDelta,
          wrongParent,
          null,
          fieldDelta,
        ]);
      final watch = StreamController<FileSystemManagerEvent>.broadcast();
      addTearDown(watch.close);
      final controller = ObservableGraphController(
        publisher: publisher,
        projectGraph: () => graph(
          compiler: compiler(
            optionalCapabilities: const <String>[
              kObservableDeltaCapability,
              kObservableLineageCapability,
            ],
          ),
        ),
        ioPlatform: true,
        watchStream: watch.stream,
        delay: (_) async {},
        resolvePafio: () async => 'pafio',
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(publisher.parentPaths.first, isEmpty);
      expect(controller.state.availability, ObservableAvailability.fresh);
      expect(controller.state.changeSet, isNull);
      expect(
        controller.state.reason,
        ObservableReasonCode.fullSnapshotRequired,
      );
      expect(controller.state.detail, kObservableDetailNoParent);

      await controller.refreshNow();
      expect(publisher.parentPaths[1], isNotEmpty);
      expect(controller.state.availability, ObservableAvailability.fresh);
      expect(
        controller.state.changeSet?.source,
        ObservableChangeSetSource.producerDelta,
      );
      expect(controller.state.changeSet?.changedNodeIds, <String>[
        'n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1',
      ]);
      expect(controller.state.reason, isNull);

      await controller.refreshNow();
      expect(controller.state.availability, ObservableAvailability.stale);
      expect(controller.state.reason, ObservableReasonCode.wrongParent);
      expect(controller.state.projection, isNotNull);

      await controller.refreshNow();
      expect(publisher.parentPaths[3], isEmpty);
      expect(controller.state.availability, ObservableAvailability.fresh);
      expect(
        controller.state.reason,
        ObservableReasonCode.fullSnapshotRequired,
      );
      expect(controller.state.detail, kObservableDetailPreviousDeltaRejected);
    },
  );

  test(
    'missing delta and transport failure degrade without dropping the graph',
    () async {
      final parent = readObservableTopologyFixtureBytes('parent/complete.json');
      final child = readObservableTopologyFixtureBytes(
        'child/field-change.json',
      );
      final rename = readObservableTopologyFixtureBytes('child/rename.json');
      final publisher = _FakePublisher()
        ..successes.addAll(<List<int>>[parent, child, rename])
        ..deltas.addAll(<List<int>?>[null, null])
        ..degradations.addAll(<String?>[
          null,
          kObservableProducerFullSnapshotRequired,
        ]);
      final watch = StreamController<FileSystemManagerEvent>.broadcast();
      addTearDown(watch.close);
      final controller = ObservableGraphController(
        publisher: publisher,
        projectGraph: () => graph(
          compiler: compiler(
            optionalCapabilities: const <String>[kObservableDeltaCapability],
          ),
        ),
        ioPlatform: true,
        watchStream: watch.stream,
        delay: (_) async {},
        resolvePafio: () async => 'pafio',
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.refreshNow();
      expect(
        controller.state.reason,
        ObservableReasonCode.fullSnapshotRequired,
      );
      expect(
        controller.state.detail,
        kObservableDetailProducerFullSnapshotRequired,
      );
      expect(
        controller.state.changeSet?.source,
        ObservableChangeSetSource.idSetComparison,
      );

      publisher.usageErrorOnParent = true;
      await controller.refreshNow();
      expect(publisher.calls, greaterThan(2));
      expect(publisher.parentPaths.last, isEmpty);
      expect(controller.state.availability, ObservableAvailability.fresh);
      expect(
        controller.state.detail,
        kObservableDetailDeltaTransportUnavailable,
      );
    },
  );

  test(
    'identical bytes leave state unchanged and window stays bounded',
    () async {
      final parent = readObservableTopologyFixtureBytes('parent/complete.json');
      final publisher = _FakePublisher()
        ..successes.addAll(<List<int>>[parent, parent]);
      final identicalController = ObservableGraphController(
        publisher: publisher,
        projectGraph: () => graph(
          compiler: compiler(
            optionalCapabilities: const <String>[kObservableDeltaCapability],
          ),
        ),
        ioPlatform: true,
        watchStream: const Stream<FileSystemManagerEvent>.empty(),
        delay: (_) async {},
        resolvePafio: () async => 'pafio',
      );
      addTearDown(identicalController.dispose);
      await identicalController.start();
      final identity = identicalController.state.currentIdentity;
      final runs = identicalController.state.counters.refreshRuns;
      await identicalController.refreshNow();
      expect(identicalController.state.currentIdentity, identity);
      expect(identicalController.state.counters.refreshRuns, runs);

      final snapshots = <List<int>>[
        parent,
        readObservableTopologyFixtureBytes('child/field-change.json'),
        readObservableTopologyFixtureBytes('child/add-diagnostic.json'),
        readObservableTopologyFixtureBytes('child/remove.json'),
        readObservableTopologyFixtureBytes('child/rename.json'),
        readObservableTopologyFixtureBytes('child/move.json'),
        readObservableTopologyFixtureBytes('child/split.json'),
        readObservableTopologyFixtureBytes('child/merge.json'),
        readObservableFixtureBytes('canonical.json'),
      ];
      final boundPublisher = _FakePublisher()..successes.addAll(snapshots);
      final controller = ObservableGraphController(
        publisher: boundPublisher,
        projectGraph: () => graph(
          compiler: compiler(
            optionalCapabilities: const <String>[kObservableDeltaCapability],
          ),
        ),
        ioPlatform: true,
        watchStream: const Stream<FileSystemManagerEvent>.empty(),
        delay: (_) async {},
        resolvePafio: () async => 'pafio',
      );
      addTearDown(controller.dispose);
      await controller.start();
      for (var i = 1; i < snapshots.length; i += 1) {
        await controller.refreshNow();
      }
      expect(controller.lineageWindow.length, lessThanOrEqualTo(8));
      expect(controller.cache.length, lessThanOrEqualTo(8));
      expect(
        controller.state.counters.retainedGenerations,
        lessThanOrEqualTo(8),
      );
    },
  );

  test('unadvertised toolchain never passes a parent reference', () async {
    final canonical = readObservableFixtureBytes(
      'vityo-authored-canonical.json',
    );
    final edited = readObservableFixtureBytes('edited.json');
    final publisher = _FakePublisher()
      ..successes.addAll(<List<int>>[canonical, edited]);
    final controller = ObservableGraphController(
      publisher: publisher,
      projectGraph: () => graph(compiler: compiler()),
      ioPlatform: true,
      watchStream: const Stream<FileSystemManagerEvent>.empty(),
      delay: (_) async {},
      resolvePafio: () async => 'pafio',
    );
    addTearDown(controller.dispose);
    await controller.start();
    await controller.refreshNow();
    expect(publisher.parentPaths, everyElement(isEmpty));
    expect(
      controller.state.changeSet?.source,
      ObservableChangeSetSource.idSetComparison,
    );
  });

  test(
    'an unchanged delta is a verified no-op and redelivery stays duplicate',
    () async {
      final parent = readObservableTopologyFixtureBytes('parent/complete.json');
      final child = readObservableTopologyFixtureBytes(
        'child/field-change.json',
      );
      final delta = readObservableTopologyFixtureBytes(
        'delta/field-change.json',
      );
      final childId = observableSnapshotId(child);
      final unchangedDelta = utf8.encode(
        '{"contract":"styio.observable.delta","schema_version":{"major":0,"minor":1},'
        '"stability":"incubating","parent_snapshot_id":"$childId",'
        '"target_snapshot_id":"$childId",'
        '"required_capabilities":["file-source-anchors","producer-evidence",'
        '"static-topology-edges","static-topology-facts","static-topology-nodes"],'
        '"optional_capabilities":["snapshot-delta"],"operations":[]}',
      );
      final publisher = _FakePublisher()
        ..successes.addAll(<List<int>>[parent, child, child, child])
        ..deltas.addAll(<List<int>?>[null, delta, unchangedDelta, delta]);
      final controller = ObservableGraphController(
        publisher: publisher,
        projectGraph: () => graph(
          compiler: compiler(
            optionalCapabilities: const <String>[kObservableDeltaCapability],
          ),
        ),
        ioPlatform: true,
        watchStream: const Stream<FileSystemManagerEvent>.empty(),
        delay: (_) async {},
        resolvePafio: () async => 'pafio',
      );
      addTearDown(controller.dispose);

      await controller.start();
      await controller.refreshNow();
      expect(
        controller.state.changeSet?.source,
        ObservableChangeSetSource.producerDelta,
      );
      final identity = controller.state.currentIdentity;
      final runs = controller.state.counters.refreshRuns;
      final applied = controller.state.counters.appliedDeltas;
      final retained = controller.lineageWindow.length;

      await controller.refreshNow();
      expect(controller.state.currentIdentity, identity);
      expect(controller.state.counters.refreshRuns, runs);
      expect(controller.state.counters.appliedDeltas, applied);
      expect(controller.lineageWindow.length, retained);

      await controller.refreshNow();
      expect(controller.state.availability, ObservableAvailability.stale);
      expect(controller.state.reason, ObservableReasonCode.duplicateDelta);
    },
  );

  test(
    'a scalar-noop acceptance retains the head base for the next delta request',
    () async {
      final parent = readObservableTopologyFixtureBytes('parent/complete.json');
      final scalarNoop = readObservableFixtureBytes('proven-scalar-noop.json');
      final publisher = _FakePublisher()
        ..successes.addAll(<List<int>>[parent, scalarNoop, parent])
        ..artifactPaths.addAll(<String>[
          'one.observable-static-snapshot.json',
          'two.observable-static-snapshot.json',
          'three.observable-static-snapshot.json',
        ]);
      final controller = ObservableGraphController(
        publisher: publisher,
        projectGraph: () => graph(
          compiler: compiler(
            optionalCapabilities: const <String>[kObservableDeltaCapability],
          ),
        ),
        ioPlatform: true,
        watchStream: const Stream<FileSystemManagerEvent>.empty(),
        delay: (_) async {},
        resolvePafio: () async => 'pafio',
      );
      addTearDown(controller.dispose);

      await controller.start();
      expect(controller.state.availability, ObservableAvailability.fresh);
      expect(publisher.parentPaths.first, isEmpty);

      await controller.refreshNow();
      expect(controller.state.availability, ObservableAvailability.scalarNoop);
      expect(
        controller.lineageWindow.head!.snapshotId,
        observableSnapshotId(scalarNoop),
      );

      await controller.refreshNow();
      expect(
        publisher.parentPaths[2],
        'two.observable-static-snapshot.json',
        reason:
            'the delta request must parent to the published scalar-noop head',
      );
      expect(controller.state.availability, ObservableAvailability.fresh);
      expect(
        controller.state.reason,
        ObservableReasonCode.fullSnapshotRequired,
      );
      expect(controller.state.detail, kObservableDetailNoDeltaArtifact);
    },
  );
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
  final List<List<int>?> deltas = <List<int>?>[];
  final List<String?> degradations = <String?>[];
  final List<String> artifactPaths = <String>[];
  final List<String> parentPaths = <String>[];
  Completer<void>? hold;
  String? failWith;
  bool usageErrorOnParent = false;
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
    parentPaths.add(request.parentSnapshotPath ?? '');
    final pending = hold;
    if (pending != null) {
      await pending.future;
    }
    if (_cancelledToken >= token) {
      return ObservableSnapshotPublishResult.cancelled();
    }
    if (usageErrorOnParent &&
        request.parentSnapshotPath != null &&
        request.parentSnapshotPath!.isNotEmpty) {
      return ObservableSnapshotPublishResult.failed(
        reason: ObservableReasonCode.deltaTransportUnavailable,
        detail: 'unknown option',
      );
    }
    if (failWith != null) {
      return ObservableSnapshotPublishResult.failed(detail: failWith!);
    }
    final index = token - 1;
    final bytes =
        successes[index < successes.length ? index : successes.length - 1];
    final delta = index < deltas.length ? deltas[index] : null;
    final degradation = index < degradations.length
        ? degradations[index]
        : null;
    return ObservableSnapshotPublishResult.succeeded(
      bytes: bytes,
      artifactPath: index < artifactPaths.length
          ? artifactPaths[index]
          : 'example.observable-static-snapshot.json',
      receipt: null,
      deltaBytes: delta,
      degradation: degradation,
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
