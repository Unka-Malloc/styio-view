import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend_toolchain/pafio_cli_discovery.dart';
import '../../backend_toolchain/project_graph_contract.dart';
import '../../environment/environment.dart';
import 'observable_capability_negotiation.dart';
import 'observable_change_set.dart';
import 'observable_delta_apply.dart';
import 'observable_delta_model.dart';
import 'observable_graph_layout.dart';
import 'observable_lineage_window.dart';
import 'observable_runtime_model.dart';
import 'observable_snapshot_cache.dart';
import 'observable_snapshot_model.dart';

typedef ObservableProjectGraphProvider = ProjectGraphSnapshot Function();
typedef ObservableDelay = Future<void> Function(Duration duration);
typedef ObservablePafioResolver = Future<String?> Function();

class ObservableGraphController extends ChangeNotifier {
  ObservableGraphController({
    required ObservableSnapshotPublisher publisher,
    required ObservableProjectGraphProvider projectGraph,
    required bool ioPlatform,
    PlatformManagerBundle? platformManagers,
    FileSystemManager? fileSystemManager,
    Stream<FileSystemManagerEvent>? watchStream,
    ObservableSnapshotCache? cache,
    ObservableChangeSource? changeSource,
    ObservableDelay? delay,
    DateTime Function()? clock,
    ObservablePafioResolver? resolvePafio,
    ObservableRuntimeIntake? runtimeIntake,
    this.debounce = const Duration(
      milliseconds: kObservableDebounceMilliseconds,
    ),
  }) : _publisher = publisher,
       _projectGraph = projectGraph,
       _ioPlatform = ioPlatform,
       _fileSystemManager = fileSystemManager,
       _injectedWatch = watchStream,
       _cache = cache ?? ObservableSnapshotCache(),
       _changeSource = changeSource ?? const IdSetComparisonChangeSource(),
       _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now,
       _resolvePafio =
           resolvePafio ??
           (platformManagers == null
               ? () async => null
               : () => resolvePafioBinary(platformManagers)),
       _runtimeIntake = runtimeIntake;

  final ObservableSnapshotPublisher _publisher;
  final ObservableProjectGraphProvider _projectGraph;
  final bool _ioPlatform;
  final FileSystemManager? _fileSystemManager;
  final Stream<FileSystemManagerEvent>? _injectedWatch;
  final ObservableSnapshotCache _cache;
  final ObservableChangeSource _changeSource;
  final ObservableDelay _delay;
  final DateTime Function() _clock;
  final ObservablePafioResolver _resolvePafio;
  final ObservableRuntimeIntake? _runtimeIntake;
  final Duration debounce;
  final ObservableLineageWindow _window = ObservableLineageWindow();

  ObservableGraphState _state = ObservableGraphState.initial();
  StreamSubscription<FileSystemManagerEvent>? _watch;
  int _generation = 0;
  int _debounceGeneration = 0;
  int _observationGeneration = 0;
  bool _started = false;
  bool _watchAttached = false;
  bool _disposed = false;
  String? _pafioBinary;
  ObservableSnapshot? _currentSnapshot;
  SnapshotIdentity? _currentIdentity;
  bool _snapshotDeltaAvailable = false;
  bool _deltasDisabled = false;
  bool _forceFullSnapshot = false;
  List<int>? _headBytes;
  String? _headPath;

  ObservableGraphState get state => _state;
  bool get watchAttached => _watchAttached;
  ObservableSnapshotCache get cache => _cache;
  ObservableLineageWindow get lineageWindow => _window;

  Future<void> start() async {
    if (_disposed) {
      return;
    }
    _started = true;
    final accepted = await _negotiate();
    if (!accepted || _disposed) {
      return;
    }
    _attachWatch();
    await refreshNow();
  }

  Future<void> refreshNow() async {
    _debounceGeneration += 1;
    await _run(_generation += 1);
  }

  void selectNode(String? nodeId) {
    if (_disposed) {
      return;
    }
    if (nodeId == null) {
      _state = _state.copyWith(clearSelection: true);
      notifyListeners();
      return;
    }
    final resolved = _resolveAnchor(nodeId);
    _state = _state.copyWith(
      selectedNodeId: nodeId,
      selectedAnchorResolved: resolved != null,
      selectedAnchorRelativePath: resolved?.relativePath,
    );
    notifyListeners();
  }

  String? resolvedAnchorPath(String nodeId) => _resolveAnchor(nodeId)?.absolutePath;

  RuntimeObservationDecision get runtimeObservationDecision {
    final graph = _projectGraph();
    return negotiateRuntimeObservation(
      ObservableNegotiationInput(
        ioPlatform: _ioPlatform,
        pafioAvailable: true,
        compiler: graph.activeCompiler,
        manifestPath: graph.manifestPath,
        hosted: graph.isHosted,
      ),
    );
  }

  bool beginObservation(RuntimeObservationMode mode) {
    if (_disposed) {
      return false;
    }
    final phase = _state.runtime.phase;
    if (phase == RuntimeOverlayPhase.observing ||
        phase == RuntimeOverlayPhase.ingesting) {
      _state = _state.copyWith(
        runtime: _state.runtime.copyWith(
          reason: ObservableReasonCode.observationInFlight,
          detail: 'observation-in-flight',
        ),
      );
      notifyListeners();
      return false;
    }
    final decision = runtimeObservationDecision;
    if (!decision.available) {
      _state = _state.copyWith(
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.unsupported,
          reason: decision.reason,
          detail: decision.detail,
          requestedMode: mode,
        ),
      );
      notifyListeners();
      return false;
    }
    if (_currentIdentity == null) {
      _state = _state.copyWith(
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.unsupported,
          reason: ObservableReasonCode.noHeadSnapshot,
          detail: 'no-head-snapshot',
          requestedMode: mode,
        ),
      );
      notifyListeners();
      return false;
    }
    _observationGeneration += 1;
    _state = _state.copyWith(
      runtime: RuntimeOverlayState(
        phase: RuntimeOverlayPhase.observing,
        requestedMode: mode,
      ),
    );
    notifyListeners();
    return true;
  }

  Future<void> completeObservation({
    required bool sessionFailed,
    String? runtimeEventsPath,
  }) async {
    if (_disposed) {
      return;
    }
    final generation = _observationGeneration;
    final requestedMode = _state.runtime.requestedMode;
    _state = _state.copyWith(
      runtime: RuntimeOverlayState(
        phase: RuntimeOverlayPhase.ingesting,
        requestedMode: requestedMode,
      ),
    );
    notifyListeners();

    final identity = _currentIdentity;
    if (identity == null) {
      _applyRuntimeOutcome(
        generation: generation,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.unsupported,
          reason: ObservableReasonCode.noHeadSnapshot,
          detail: 'no-head-snapshot',
          requestedMode: requestedMode,
        ),
      );
      return;
    }
    final path = runtimeEventsPath?.trim();
    if (path == null || path.isEmpty) {
      _applyRuntimeOutcome(
        generation: generation,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.rejected,
          reason: sessionFailed
              ? ObservableReasonCode.runFailed
              : ObservableReasonCode.noRuntimeArtifact,
          detail: sessionFailed ? 'run-failed' : 'no-runtime-artifact',
          requestedMode: requestedMode,
        ),
      );
      return;
    }
    final intake = _runtimeIntake;
    if (intake == null) {
      _applyRuntimeOutcome(
        generation: generation,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.rejected,
          reason: ObservableReasonCode.unsupportedPlatform,
          detail: 'unsupported-platform',
          requestedMode: requestedMode,
        ),
      );
      return;
    }
    final siteIds = [
      for (final node in _state.projection?.nodes ?? const <ProjectedGraphNode>[])
        node.id,
    ];
    final RuntimeIntakeResult result;
    try {
      result = await intake.ingest(
        RuntimeIntakeRequest(
          artifactPath: path,
          headSnapshotId: identity.snapshotId,
          headSiteIds: siteIds,
        ),
      );
    } catch (_) {
      // A failed isolate or read error must still resolve the phase machine;
      // otherwise the controller would wedge in `ingesting`.
      _applyRuntimeOutcome(
        generation: generation,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.rejected,
          reason: ObservableReasonCode.invalidRuntimeStream,
          detail: 'intake-failed',
          requestedMode: requestedMode,
        ),
      );
      return;
    }
    if (generation != _observationGeneration || _disposed) {
      return;
    }
    if (!result.isOk) {
      _applyRuntimeOutcome(
        generation: generation,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.rejected,
          reason: result.reason ?? ObservableReasonCode.invalidRuntimeStream,
          detail: result.streamSubcode?.wireValue ?? result.detail,
          requestedMode: requestedMode,
        ),
      );
      return;
    }
    final overlay = result.overlay!;
    if (overlay.snapshotId != identity.snapshotId) {
      _applyRuntimeOutcome(
        generation: generation,
        runtime: RuntimeOverlayState(
          phase: RuntimeOverlayPhase.staleSnapshot,
          reason: ObservableReasonCode.capabilitySnapshotMismatch,
          detail: 'capability-snapshot-mismatch',
          requestedMode: requestedMode,
          overlay: overlay,
          ingestedAt: _clock(),
        ),
      );
      return;
    }
    _applyRuntimeOutcome(
      generation: generation,
      runtime: RuntimeOverlayState(
        phase: RuntimeOverlayPhase.overlaid,
        requestedMode: requestedMode,
        overlay: overlay,
        ingestedAt: _clock(),
      ),
    );
  }

  void clearObservation() {
    if (_disposed) {
      return;
    }
    _observationGeneration += 1;
    _state = _state.copyWith(runtime: const RuntimeOverlayState.none());
    notifyListeners();
  }

  void _applyRuntimeOutcome({
    required int generation,
    required RuntimeOverlayState runtime,
  }) {
    if (generation != _observationGeneration || _disposed) {
      return;
    }
    _state = _state.copyWith(runtime: runtime);
    notifyListeners();
  }

  RuntimeOverlayState _runtimeForAcceptedHead(SnapshotIdentity identity) {
    final runtime = _state.runtime;
    final overlay = runtime.overlay;
    if (overlay != null && overlay.snapshotId != identity.snapshotId) {
      return RuntimeOverlayState(
        phase: RuntimeOverlayPhase.staleSnapshot,
        reason: ObservableReasonCode.headAdvanced,
        detail: 'head-advanced',
        requestedMode: runtime.requestedMode,
        overlay: overlay,
        ingestedAt: runtime.ingestedAt,
      );
    }
    return runtime;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _generation += 1;
    _debounceGeneration += 1;
    unawaited(_watch?.cancel());
    _watch = null;
    _publisher.cancel();
    super.dispose();
  }

  Future<bool> _negotiate() async {
    final graph = _projectGraph();
    // Phase 1 decides from the already-known compiler handshake alone, so a
    // workspace without the observable capability never spawns a process.
    // Pafio availability is probed (phase 2) only after every other check
    // passes; the reason-code precedence is unchanged because a missing
    // compiler, manifest, schema version, or capability rejects identically
    // regardless of pafio.
    final decision = negotiateObservableCapability(
      ObservableNegotiationInput(
        ioPlatform: _ioPlatform,
        pafioAvailable: true,
        compiler: graph.activeCompiler,
        manifestPath: graph.manifestPath,
        hosted: graph.isHosted,
      ),
    );
    if (!decision.accepted) {
      _applyNegotiationRejection(decision);
      return false;
    }
    final pafio = await _resolvePafio();
    if (pafio == null || pafio.trim().isEmpty) {
      _applyNegotiationRejection(
        ObservableNegotiationDecision.reject(
          availability: ObservableAvailability.unavailable,
          reason: ObservableReasonCode.noToolchain,
          detail: 'No Pafio binary is available.',
        ),
      );
      return false;
    }
    _pafioBinary = pafio;
    _snapshotDeltaAvailable = decision.snapshotDeltaAvailable;
    return true;
  }

  void _applyNegotiationRejection(ObservableNegotiationDecision decision) {
    _watch?.cancel();
    _watch = null;
    _watchAttached = false;
    _state = ObservableGraphState(
      availability: decision.availability,
      reason: decision.reason,
      detail: decision.detail,
      counters: _state.counters,
      runtime: _state.runtime,
    );
    _currentSnapshot = null;
    _currentIdentity = null;
    _headBytes = null;
    _headPath = null;
    notifyListeners();
  }

  void _attachWatch() {
    if (_watchAttached) {
      return;
    }
    final stream =
        _injectedWatch ??
        _fileSystemManager?.watch(
          _projectGraph().workspaceRoot,
          recursive: true,
        );
    if (stream == null) {
      return;
    }
    _watchAttached = true;
    _watch = stream.listen(_handleWatchEvent);
  }

  void _handleWatchEvent(FileSystemManagerEvent event) {
    if (_disposed || !_started) {
      return;
    }
    if (!_shouldRefreshPath(event.path) &&
        !_shouldRefreshPath(event.normalizedPath)) {
      return;
    }
    _scheduleDebouncedRefresh();
  }

  bool _shouldRefreshPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.endsWith(kObservableArtifactSuffix) ||
        normalized.endsWith(kObservableDeltaArtifactSuffix)) {
      return false;
    }
    if (normalized.endsWith('.styio')) {
      return true;
    }
    final slash = normalized.lastIndexOf('/');
    final base = slash == -1 ? normalized : normalized.substring(slash + 1);
    return base == 'pafio.toml';
  }

  void _scheduleDebouncedRefresh() {
    final generation = ++_debounceGeneration;
    unawaited(_debounceThenRun(generation));
  }

  Future<void> _debounceThenRun(int generation) async {
    await _delay(debounce);
    if (_disposed || generation != _debounceGeneration) {
      return;
    }
    await _run(_generation += 1);
  }

  bool _shouldRequestDelta() {
    return _snapshotDeltaAvailable &&
        !_deltasDisabled &&
        !_forceFullSnapshot &&
        _headPath != null;
  }

  Future<void> _run(int generation) async {
    if (_disposed || generation != _generation) {
      return;
    }
    _publisher.cancel();
    final graph = _projectGraph();
    final previousSnapshot = _currentSnapshot;
    final previousIdentity = _currentIdentity;
    final recovering = _forceFullSnapshot;
    if (_state.projection != null) {
      _state = _state.copyWith(
        availability: ObservableAvailability.refreshing,
        reason: ObservableReasonCode.workspaceChanged,
        detail: 'Refreshing observable topology.',
      );
      notifyListeners();
    }

    // Reuse the negotiated pafio binary; probe again only when negotiation
    // never resolved one (e.g. a manual refresh after a missing toolchain).
    final pafio = _pafioBinary ?? await _resolvePafio();
    final compiler = graph.activeCompiler;
    if (generation != _generation || _disposed) {
      return;
    }
    if (pafio == null || compiler == null || graph.manifestPath == null) {
      _failRun(
        generation: generation,
        availability: ObservableAvailability.unavailable,
        reason: ObservableReasonCode.noToolchain,
        detail: 'Observable publication is missing a local toolchain.',
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
      );
      return;
    }

    var requestDelta = _shouldRequestDelta();
    var published = await _publisher.publish(
      ObservableSnapshotPublishRequest(
        workspaceRoot: graph.workspaceRoot,
        manifestPath: graph.manifestPath!,
        pafioBinary: pafio,
        compilerBinary: compiler.binaryPath,
        parentSnapshotPath: requestDelta ? _headPath : null,
        requestDelta: requestDelta,
      ),
    );
    if (generation != _generation || _disposed) {
      return;
    }
    if (published.reason == ObservableReasonCode.deltaTransportUnavailable &&
        requestDelta &&
        !_deltasDisabled) {
      _deltasDisabled = true;
      requestDelta = false;
      published = await _publisher.publish(
        ObservableSnapshotPublishRequest(
          workspaceRoot: graph.workspaceRoot,
          manifestPath: graph.manifestPath!,
          pafioBinary: pafio,
          compilerBinary: compiler.binaryPath,
        ),
      );
      if (generation != _generation || _disposed) {
        return;
      }
    }
    if (published.status == ObservablePublishStatus.cancelled) {
      _state = _state.copyWith(
        counters: _state.counters.copyWith(
          cancelledRuns: _state.counters.cancelledRuns + 1,
        ),
      );
      return;
    }
    if (!published.isSuccess) {
      _failRun(
        generation: generation,
        availability: previousSnapshot == null
            ? ObservableAvailability.blocked
            : ObservableAvailability.stale,
        reason: published.reason ?? ObservableReasonCode.publicationFailed,
        detail: published.detail ?? 'Publication failed.',
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
      );
      return;
    }

    final childBytes = published.bytes!;
    final childSnapshotId = observableSnapshotId(childBytes);
    if (childSnapshotId == _currentIdentity?.snapshotId &&
        _state.projection != null &&
        published.deltaBytes == null &&
        !recovering) {
      return;
    }

    if (_snapshotDeltaAvailable && !_deltasDisabled) {
      await _runDeltaIntake(
        generation: generation,
        published: published,
        childBytes: childBytes,
        childSnapshotId: childSnapshotId,
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
        recovering: recovering,
        requestDelta: requestDelta,
      );
      return;
    }

    await _runSnapshotIntake(
      generation: generation,
      childBytes: childBytes,
      previousSnapshot: previousSnapshot,
      previousIdentity: previousIdentity,
      artifactPath: published.artifactPath,
    );
  }

  Future<void> _runDeltaIntake({
    required int generation,
    required ObservableSnapshotPublishResult published,
    required List<int> childBytes,
    required String childSnapshotId,
    required ObservableSnapshot? previousSnapshot,
    required SnapshotIdentity? previousIdentity,
    required bool recovering,
    required bool requestDelta,
  }) async {
    final deltaBytes = requestDelta ? published.deltaBytes : null;
    final intake = await computeObservableDeltaIntake(
      ObservableDeltaIntakeInput(
        childBytes: childBytes,
        childSnapshotId: childSnapshotId,
        deltaBytes: deltaBytes,
        headBytes: requestDelta ? _headBytes : null,
        headSnapshotId: requestDelta ? _currentIdentity?.snapshotId : null,
        retained: [
          for (final entry in _window.entries)
            ObservableRetainedIdentity(
              snapshotId: entry.snapshotId,
              parentSnapshotId: entry.parentSnapshotId,
            ),
        ],
      ),
    );
    if (generation != _generation || _disposed) {
      return;
    }
    if (!intake.accepted) {
      _forceFullSnapshot = true;
      _failRun(
        generation: generation,
        availability: previousSnapshot == null
            ? ObservableAvailability.blocked
            : ObservableAvailability.stale,
        reason: intake.reason ?? ObservableReasonCode.invalidDelta,
        detail: intake.subcode?.wireValue ?? intake.detail ?? 'delta rejected',
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
        rejectedDelta: true,
      );
      return;
    }
    // A verified no-op changes nothing: identical bytes, or an unchanged
    // delta whose target is the retained head, must not push a window entry,
    // move the counters, or notify — the V1 idempotency rule extended to
    // delta intake. A recovery run is exempt: it re-establishes the fresh
    // full-snapshot state even when the bytes are unchanged.
    if (!recovering &&
        previousIdentity != null &&
        intake.childIdentity?.snapshotId == previousIdentity.snapshotId &&
        _state.projection != null) {
      return;
    }
    final snapshot = intake.child!;
    final identity = intake.childIdentity!;
    final usedDelta = intake.usedDelta && intake.delta != null;
    if (snapshot.completeness == ObservableCompleteness.provenScalarNoop) {
      _acceptScalarNoop(
        snapshot: snapshot,
        identity: identity,
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
        childBytes: childBytes,
        artifactPath: published.artifactPath,
        usedDelta: usedDelta,
      );
      return;
    }

    final unitChanged =
        previousSnapshot != null &&
        previousSnapshot.compilationUnit.identityKey !=
            snapshot.compilationUnit.identityKey;
    if (unitChanged) {
      _window.reset();
    }

    final changeSource = usedDelta
        ? ObservableDeltaChangeSource(
            delta: intake.delta!,
            lineage: snapshot.lineage,
          )
        : _changeSource;
    final changeSet = previousSnapshot == null || unitChanged
        ? null
        : changeSource.compare(previousSnapshot, snapshot);
    await _finishFresh(
      generation: generation,
      snapshot: snapshot,
      identity: identity,
      previousSnapshot: previousSnapshot,
      previousIdentity: previousIdentity,
      changeSet: changeSet,
      artifactPath: published.artifactPath,
      childBytes: childBytes,
      usedDelta: usedDelta,
      recovering: recovering,
      degradation: published.degradation,
    );
  }

  Future<void> _runSnapshotIntake({
    required int generation,
    required List<int> childBytes,
    required ObservableSnapshot? previousSnapshot,
    required SnapshotIdentity? previousIdentity,
    required String? artifactPath,
  }) async {
    final intake = await _cache.intakeAsync(childBytes);
    if (generation != _generation || _disposed) {
      return;
    }
    if (intake.failure != null) {
      _failRun(
        generation: generation,
        availability: previousSnapshot == null
            ? ObservableAvailability.blocked
            : ObservableAvailability.stale,
        reason: ObservableReasonCode.invalidSnapshot,
        detail: intake.failure!.subcode.wireValue,
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
      );
      return;
    }
    if (intake.hit &&
        intake.identity == _currentIdentity &&
        _state.projection != null) {
      return;
    }

    final snapshot = intake.snapshot!;
    final identity = intake.identity!;
    if (snapshot.completeness == ObservableCompleteness.provenScalarNoop) {
      _acceptScalarNoop(
        snapshot: snapshot,
        identity: identity,
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
        childBytes: childBytes,
        artifactPath: artifactPath,
        usedDelta: false,
      );
      return;
    }

    final unitChanged =
        previousSnapshot != null &&
        previousSnapshot.compilationUnit.identityKey !=
            snapshot.compilationUnit.identityKey;
    if (unitChanged) {
      _window.reset();
    }
    final changeSet = previousSnapshot == null || unitChanged
        ? null
        : _changeSource.compare(previousSnapshot, snapshot);
    await _finishFresh(
      generation: generation,
      snapshot: snapshot,
      identity: identity,
      previousSnapshot: previousSnapshot,
      previousIdentity: previousIdentity,
      changeSet: changeSet,
      artifactPath: artifactPath,
      childBytes: childBytes,
      usedDelta: false,
      recovering: false,
      degradation: null,
      alreadyCached: true,
    );
  }

  void _acceptScalarNoop({
    required ObservableSnapshot snapshot,
    required SnapshotIdentity identity,
    required ObservableSnapshot? previousSnapshot,
    required SnapshotIdentity? previousIdentity,
    required List<int> childBytes,
    required String? artifactPath,
    required bool usedDelta,
  }) {
    final unitChanged =
        previousSnapshot != null &&
        previousSnapshot.compilationUnit.identityKey !=
            snapshot.compilationUnit.identityKey;
    if (unitChanged) {
      _window.reset();
    }
    // A scalar-noop artifact is still the published head: retain its bytes
    // and path so the next delta request parents to the snapshot the
    // producer actually published, and push the window entry so duplicate
    // and stale classification stay exact across the transition. This
    // acceptance consumes any pending one-shot full-snapshot flag.
    _window.push(
      ObservableLineageWindowEntry(
        snapshotId: identity.snapshotId,
        parentSnapshotId: previousIdentity?.snapshotId,
        changeSource: ObservableChangeSetSource.idSetComparison,
        changeSet: const ObservableChangeSet(
          addedNodeIds: <String>[],
          removedNodeIds: <String>[],
          addedEdgeIds: <String>[],
          removedEdgeIds: <String>[],
        ),
        lineageRecords: snapshot.lineage,
      ),
    );
    _currentSnapshot = snapshot;
    _currentIdentity = identity;
    _headBytes = childBytes;
    _headPath = artifactPath;
    _forceFullSnapshot = false;
    final fallback = !usedDelta && _snapshotDeltaAvailable;
    _state = ObservableGraphState(
      availability: ObservableAvailability.scalarNoop,
      currentIdentity: identity,
      previousIdentity: previousIdentity,
      projection: projectObservableGraph(current: snapshot),
      lastFreshAt: _clock(),
      snapshot: snapshot,
      lineageHistory: _window.entries,
      counters: _state.counters.copyWith(
        cacheHits: _cache.metrics.hits,
        cacheMisses: _cache.metrics.misses,
        cacheEvictions: _cache.metrics.evictions,
        refreshRuns: _state.counters.refreshRuns + 1,
        retainedGenerations: _window.length,
        evictedGenerations: _window.evicted,
        appliedDeltas: _state.counters.appliedDeltas + (usedDelta ? 1 : 0),
        fullSnapshotFallbacks:
            _state.counters.fullSnapshotFallbacks + (fallback ? 1 : 0),
      ),
      runtime: _runtimeForAcceptedHead(identity),
    );
    notifyListeners();
  }

  Future<void> _finishFresh({
    required int generation,
    required ObservableSnapshot snapshot,
    required SnapshotIdentity identity,
    required ObservableSnapshot? previousSnapshot,
    required SnapshotIdentity? previousIdentity,
    required ObservableChangeSet? changeSet,
    required String? artifactPath,
    required List<int> childBytes,
    required bool usedDelta,
    required bool recovering,
    required String? degradation,
    bool alreadyCached = false,
  }) async {
    final projection = projectObservableGraph(
      current: snapshot,
      previous: changeSet == null ? null : previousSnapshot,
      changeSet: changeSet,
    );
    final layoutOutcome = await computeObservableGraphLayout(
      ObservableLayoutRequest(projection: projection),
    );
    if (generation != _generation || _disposed) {
      return;
    }
    if (!layoutOutcome.isOk) {
      _failRun(
        generation: generation,
        availability: ObservableAvailability.blocked,
        reason: ObservableReasonCode.snapshotTooLarge,
        detail: layoutOutcome.detail ?? 'snapshot-too-large',
        previousSnapshot: previousSnapshot,
        previousIdentity: previousIdentity,
      );
      return;
    }

    if (!alreadyCached) {
      _cache.put(identity, snapshot);
    }
    _window.push(
      ObservableLineageWindowEntry(
        snapshotId: identity.snapshotId,
        parentSnapshotId: previousIdentity?.snapshotId,
        changeSource: changeSet?.source ??
            ObservableChangeSetSource.idSetComparison,
        changeSet: changeSet ??
            const ObservableChangeSet(
              addedNodeIds: <String>[],
              removedNodeIds: <String>[],
              addedEdgeIds: <String>[],
              removedEdgeIds: <String>[],
            ),
        lineageRecords: snapshot.lineage,
      ),
    );
    _currentSnapshot = snapshot;
    _currentIdentity = identity;
    _headBytes = childBytes;
    _headPath = artifactPath;
    if (recovering) {
      _forceFullSnapshot = false;
    }

    // Every negotiated run that did not apply a producer delta took the
    // full-snapshot path; the informational reason is always rendered with
    // the detail naming why no delta was used, including the first run,
    // which has no retained parent.
    final fallback = !usedDelta && _snapshotDeltaAvailable;
    ObservableReasonCode? reason;
    String? detail;
    if (fallback) {
      reason = ObservableReasonCode.fullSnapshotRequired;
      if (_deltasDisabled) {
        detail = kObservableDetailDeltaTransportUnavailable;
      } else if (recovering) {
        detail = kObservableDetailPreviousDeltaRejected;
      } else if (degradation == kObservableProducerFullSnapshotRequired) {
        detail = kObservableDetailProducerFullSnapshotRequired;
      } else if (previousSnapshot == null) {
        detail = kObservableDetailNoParent;
      } else {
        detail = kObservableDetailNoDeltaArtifact;
      }
    }

    _state = ObservableGraphState(
      availability: ObservableAvailability.fresh,
      reason: reason,
      detail: detail,
      currentIdentity: identity,
      previousIdentity: previousIdentity,
      changeSet: changeSet,
      projection: projection,
      layout: layoutOutcome.layout,
      lastFreshAt: _clock(),
      snapshot: snapshot,
      lineageHistory: _window.entries,
      counters: _state.counters.copyWith(
        cacheHits: _cache.metrics.hits,
        cacheMisses: _cache.metrics.misses,
        cacheEvictions: _cache.metrics.evictions,
        refreshRuns: _state.counters.refreshRuns + 1,
        retainedGenerations: _window.length,
        evictedGenerations: _window.evicted,
        appliedDeltas: _state.counters.appliedDeltas + (usedDelta ? 1 : 0),
        fullSnapshotFallbacks:
            _state.counters.fullSnapshotFallbacks + (fallback ? 1 : 0),
      ),
      runtime: _runtimeForAcceptedHead(identity),
    );
    notifyListeners();
  }

  void _failRun({
    required int generation,
    required ObservableAvailability availability,
    required ObservableReasonCode reason,
    required String detail,
    required ObservableSnapshot? previousSnapshot,
    required SnapshotIdentity? previousIdentity,
    bool rejectedDelta = false,
  }) {
    if (generation != _generation || _disposed) {
      return;
    }
    _state = ObservableGraphState(
      availability: availability,
      reason: reason,
      detail: detail,
      currentIdentity: previousIdentity,
      previousIdentity: previousIdentity,
      changeSet: _state.changeSet,
      projection: _state.projection,
      layout: _state.layout,
      lastFreshAt: _state.lastFreshAt,
      snapshot: previousSnapshot,
      lineageHistory: _window.entries,
      counters: _state.counters.copyWith(
        refreshRuns: _state.counters.refreshRuns + 1,
        rejectedDeltas:
            _state.counters.rejectedDeltas + (rejectedDelta ? 1 : 0),
      ),
      runtime: previousIdentity == null
          ? _state.runtime
          : _runtimeForAcceptedHead(previousIdentity),
    );
    notifyListeners();
  }

  _ResolvedAnchor? _resolveAnchor(String nodeId) {
    final projection = _state.projection;
    if (projection == null) {
      return null;
    }
    final node = projection.nodeById(nodeId);
    if (node == null || node.anchorRefs.isEmpty) {
      return null;
    }
    final anchor = projection.anchorByRef(node.anchorRefs.first);
    if (anchor == null) {
      return null;
    }
    final graph = _projectGraph();
    ProjectPackageSnapshot? matched;
    for (final package in graph.packages) {
      if (package.packageName == projection.compilationUnit?.packageName) {
        if (matched != null) {
          return null;
        }
        matched = package;
      }
    }
    if (matched == null) {
      return null;
    }
    final absolute = _fileSystemManager == null
        ? _join(matched.rootPath, anchor.path)
        : _fileSystemManager.joinPath(<String>[matched.rootPath, anchor.path]);
    if (_fileSystemManager != null &&
        !_fileSystemManager.isWithin(absolute, graph.workspaceRoot)) {
      return null;
    }
    return _ResolvedAnchor(relativePath: anchor.path, absolutePath: absolute);
  }
}

class _ResolvedAnchor {
  const _ResolvedAnchor({
    required this.relativePath,
    required this.absolutePath,
  });

  final String relativePath;
  final String absolutePath;
}

String _join(String left, String right) {
  if (left.endsWith('/') || left.endsWith('\\')) {
    return '$left$right';
  }
  return '$left/$right';
}
