import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../backend_toolchain/pafio_cli_discovery.dart';
import '../../backend_toolchain/project_graph_contract.dart';
import '../../environment/environment.dart';
import 'observable_capability_negotiation.dart';
import 'observable_change_set.dart';
import 'observable_graph_layout.dart';
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
    FileSystemManager? fileSystemManager,
    Stream<FileSystemManagerEvent>? watchStream,
    ObservableSnapshotCache? cache,
    ObservableChangeSource? changeSource,
    ObservableDelay? delay,
    DateTime Function()? clock,
    ObservablePafioResolver? resolvePafio,
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
       _resolvePafio = resolvePafio ?? resolvePafioBinary;

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
  final Duration debounce;

  ObservableGraphState _state = ObservableGraphState.initial();
  StreamSubscription<FileSystemManagerEvent>? _watch;
  int _generation = 0;
  int _debounceGeneration = 0;
  bool _started = false;
  bool _watchAttached = false;
  bool _disposed = false;
  String? _pafioBinary;
  ObservableSnapshot? _currentSnapshot;
  SnapshotIdentity? _currentIdentity;

  ObservableGraphState get state => _state;
  bool get watchAttached => _watchAttached;
  ObservableSnapshotCache get cache => _cache;

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
    );
    _currentSnapshot = null;
    _currentIdentity = null;
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
    if (normalized.endsWith(kObservableArtifactSuffix)) {
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
    final token = ++_debounceGeneration;
    unawaited(_debounceThenRun(token));
  }

  Future<void> _debounceThenRun(int token) async {
    await _delay(debounce);
    if (_disposed || token != _debounceGeneration) {
      return;
    }
    await _run(_generation += 1);
  }

  Future<void> _run(int generation) async {
    if (_disposed || generation != _generation) {
      return;
    }
    _publisher.cancel();
    final graph = _projectGraph();
    final previousSnapshot = _currentSnapshot;
    final previousIdentity = _currentIdentity;
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

    final published = await _publisher.publish(
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

    final intake = await _cache.intakeAsync(published.bytes!);
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
      _currentSnapshot = snapshot;
      _currentIdentity = identity;
      _state = ObservableGraphState(
        availability: ObservableAvailability.scalarNoop,
        currentIdentity: identity,
        previousIdentity: previousIdentity,
        projection: projectObservableGraph(current: snapshot),
        lastFreshAt: _clock(),
        snapshot: snapshot,
        counters: _state.counters.copyWith(
          cacheHits: _cache.metrics.hits,
          cacheMisses: _cache.metrics.misses,
          cacheEvictions: _cache.metrics.evictions,
          refreshRuns: _state.counters.refreshRuns + 1,
        ),
      );
      notifyListeners();
      return;
    }

    final changeSet = previousSnapshot == null
        ? null
        : _changeSource.compare(previousSnapshot, snapshot);
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

    _currentSnapshot = snapshot;
    _currentIdentity = identity;
    _state = ObservableGraphState(
      availability: ObservableAvailability.fresh,
      currentIdentity: identity,
      previousIdentity: previousIdentity,
      changeSet: changeSet,
      projection: projection,
      layout: layoutOutcome.layout,
      lastFreshAt: _clock(),
      snapshot: snapshot,
      counters: _state.counters.copyWith(
        cacheHits: _cache.metrics.hits,
        cacheMisses: _cache.metrics.misses,
        cacheEvictions: _cache.metrics.evictions,
        refreshRuns: _state.counters.refreshRuns + 1,
      ),
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
      counters: _state.counters.copyWith(
        refreshRuns: _state.counters.refreshRuns + 1,
      ),
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
