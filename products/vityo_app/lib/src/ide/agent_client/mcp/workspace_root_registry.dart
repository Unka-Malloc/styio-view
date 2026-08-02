import 'dart:async';
import 'dart:collection';
import 'dart:io';

final class CanonicalPath {
  const CanonicalPath({required this.path, this.traversedLink = false});

  final String path;
  final bool traversedLink;
}

abstract interface class CanonicalPathResolver {
  Future<CanonicalPath> resolve(String path);
}

final class IoCanonicalPathResolver implements CanonicalPathResolver {
  const IoCanonicalPathResolver();

  @override
  Future<CanonicalPath> resolve(String path) async {
    if (path.trim().isEmpty) {
      throw const FileSystemException('path must not be empty');
    }
    final absolute = File(path).absolute;
    final lexical = absolute.uri.normalizePath().toFilePath();
    final resolved = await absolute.resolveSymbolicLinks();
    return CanonicalPath(
      path: resolved,
      traversedLink: _comparisonPath(lexical) != _comparisonPath(resolved),
    );
  }
}

final class WorkspaceRootProposal {
  const WorkspaceRootProposal({required this.path, required this.displayName});

  final String path;
  final String displayName;
}

final class ApprovedWorkspaceRoot {
  const ApprovedWorkspaceRoot({
    required this.id,
    required this.canonicalPath,
    required this.displayName,
    required this.consentReceiptId,
  });

  final String id;
  final String canonicalPath;
  final String displayName;
  final String consentReceiptId;

  String get resourceUri => 'ide-root://$id';
}

final class WorkspaceRootSnapshot {
  WorkspaceRootSnapshot({
    required this.sessionId,
    required this.revision,
    required Iterable<ApprovedWorkspaceRoot> roots,
  }) : roots = UnmodifiableListView<ApprovedWorkspaceRoot>(
         List<ApprovedWorkspaceRoot>.of(roots),
       );

  final String sessionId;
  final int revision;
  final List<ApprovedWorkspaceRoot> roots;
}

final class WorkspaceRootChange {
  const WorkspaceRootChange({required this.sessionId, required this.revision});

  final String sessionId;
  final int revision;
}

final class RootAuthorization {
  const RootAuthorization({
    required this.allowed,
    required this.code,
    required this.rootRevision,
    this.rootId,
    this.canonicalPath,
  });

  final bool allowed;
  final String code;
  final int rootRevision;
  final String? rootId;
  final String? canonicalPath;
}

final class WorkspaceRootRegistry {
  WorkspaceRootRegistry({
    CanonicalPathResolver resolver = const IoCanonicalPathResolver(),
    this.maxSessions = 64,
    this.maxRootsPerSession = 32,
    this.maxPathCodeUnits = 32768,
    this.maxDisplayNameCodeUnits = 256,
    this.resolutionTimeout = const Duration(seconds: 5),
  }) : _resolver = resolver {
    if (maxSessions <= 0 ||
        maxRootsPerSession <= 0 ||
        maxPathCodeUnits <= 0 ||
        maxDisplayNameCodeUnits <= 0 ||
        resolutionTimeout <= Duration.zero) {
      throw ArgumentError('workspace root limits must be positive');
    }
  }

  final CanonicalPathResolver _resolver;
  final int maxSessions;
  final int maxRootsPerSession;
  final int maxPathCodeUnits;
  final int maxDisplayNameCodeUnits;
  final Duration resolutionTimeout;
  final Map<String, WorkspaceRootSnapshot> _snapshots =
      <String, WorkspaceRootSnapshot>{};
  final Map<String, Future<void>> _lanes = <String, Future<void>>{};
  final StreamController<WorkspaceRootChange> _changes =
      StreamController<WorkspaceRootChange>.broadcast(sync: true);
  int _rootSequence = 0;
  bool _closed = false;

  Stream<WorkspaceRootChange> get changes => _changes.stream;

  WorkspaceRootSnapshot snapshot(String sessionId) =>
      _snapshots[sessionId] ??
      WorkspaceRootSnapshot(
        sessionId: sessionId,
        revision: 0,
        roots: const <ApprovedWorkspaceRoot>[],
      );

  Future<WorkspaceRootSnapshot> replaceRoots({
    required String sessionId,
    required List<WorkspaceRootProposal> proposals,
    required String consentReceiptId,
  }) {
    if (_closed) {
      return Future<WorkspaceRootSnapshot>.error(
        StateError('workspace root registry is closed'),
      );
    }
    _validateReplacement(
      sessionId: sessionId,
      proposals: proposals,
      consentReceiptId: consentReceiptId,
    );
    if (!_snapshots.containsKey(sessionId) &&
        !_lanes.containsKey(sessionId) &&
        <String>{..._snapshots.keys, ..._lanes.keys}.length >= maxSessions) {
      return Future<WorkspaceRootSnapshot>.error(
        StateError('workspace root session limit was reached'),
      );
    }
    final frozenProposals = List<WorkspaceRootProposal>.unmodifiable(proposals);
    final completer = Completer<WorkspaceRootSnapshot>();
    final prior = _lanes[sessionId] ?? Future<void>.value();
    final operation = prior.then((_) async {
      try {
        completer.complete(
          await _replaceRoots(
            sessionId: sessionId,
            proposals: frozenProposals,
            consentReceiptId: consentReceiptId,
          ),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    final lane = operation.then<void>((_) {}, onError: (_, __) {});
    _lanes[sessionId] = lane;
    unawaited(
      lane.then((_) {
        if (identical(_lanes[sessionId], lane)) {
          _lanes.remove(sessionId);
        }
      }),
    );
    return completer.future;
  }

  Future<RootAuthorization> authorize({
    required String sessionId,
    required String candidate,
  }) async {
    final current = snapshot(sessionId);
    if (_closed || current.roots.isEmpty) {
      return RootAuthorization(
        allowed: false,
        code: 'root_revoked',
        rootRevision: current.revision,
      );
    }
    if (candidate.trim().isEmpty || candidate.length > maxPathCodeUnits) {
      return RootAuthorization(
        allowed: false,
        code: 'path_unavailable',
        rootRevision: current.revision,
      );
    }
    final CanonicalPath resolved;
    try {
      resolved = await _resolve(candidate);
    } on FileSystemException {
      return RootAuthorization(
        allowed: false,
        code: 'path_unavailable',
        rootRevision: current.revision,
      );
    } on TimeoutException {
      return RootAuthorization(
        allowed: false,
        code: 'path_unavailable',
        rootRevision: current.revision,
      );
    }
    final latest = snapshot(sessionId);
    if (_closed || latest.revision != current.revision) {
      return RootAuthorization(
        allowed: false,
        code: latest.roots.isEmpty ? 'root_revoked' : 'root_revision_changed',
        rootRevision: latest.revision,
      );
    }
    for (final root in latest.roots) {
      if (_contains(root.canonicalPath, resolved.path)) {
        return RootAuthorization(
          allowed: true,
          code: 'allowed',
          rootRevision: latest.revision,
          rootId: root.id,
          canonicalPath: resolved.path,
        );
      }
    }
    return RootAuthorization(
      allowed: false,
      code: resolved.traversedLink
          ? 'symlink_escape_denied'
          : 'root_escape_denied',
      rootRevision: latest.revision,
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await Future.wait<void>(_lanes.values.toList(growable: false));
    _lanes.clear();
    _snapshots.clear();
    await _changes.close();
  }

  Future<WorkspaceRootSnapshot> _replaceRoots({
    required String sessionId,
    required List<WorkspaceRootProposal> proposals,
    required String consentReceiptId,
  }) async {
    final rootsByPath = <String, ApprovedWorkspaceRoot>{};
    for (final proposal in proposals) {
      final canonical = await _resolve(proposal.path);
      if (canonical.path.trim().isEmpty ||
          canonical.path.length > maxPathCodeUnits) {
        throw StateError(
          'canonical workspace path is outside supported bounds',
        );
      }
      final comparison = _comparisonPath(canonical.path);
      rootsByPath.putIfAbsent(
        comparison,
        () => ApprovedWorkspaceRoot(
          id: 'vityo-root-${++_rootSequence}',
          canonicalPath: canonical.path,
          displayName: proposal.displayName,
          consentReceiptId: consentReceiptId,
        ),
      );
    }
    final former = snapshot(sessionId);
    final next = WorkspaceRootSnapshot(
      sessionId: sessionId,
      revision: former.revision + 1,
      roots: rootsByPath.values,
    );
    _snapshots[sessionId] = next;
    _changes.add(
      WorkspaceRootChange(sessionId: sessionId, revision: next.revision),
    );
    return next;
  }

  Future<CanonicalPath> _resolve(String path) =>
      _resolver.resolve(path).timeout(resolutionTimeout);

  void _validateReplacement({
    required String sessionId,
    required List<WorkspaceRootProposal> proposals,
    required String consentReceiptId,
  }) {
    if (sessionId.trim().isEmpty ||
        sessionId.length > 256 ||
        consentReceiptId.trim().isEmpty ||
        consentReceiptId.length > 256) {
      throw ArgumentError(
        'session and consent receipt identifiers must be bounded',
      );
    }
    if (proposals.length > maxRootsPerSession) {
      throw ArgumentError.value(
        proposals.length,
        'proposals',
        'workspace root limit was exceeded',
      );
    }
    for (final proposal in proposals) {
      if (proposal.path.trim().isEmpty ||
          proposal.path.length > maxPathCodeUnits) {
        throw ArgumentError.value(
          proposal.path,
          'path',
          'must be non-empty and bounded',
        );
      }
      if (proposal.displayName.trim().isEmpty ||
          proposal.displayName.length > maxDisplayNameCodeUnits) {
        throw ArgumentError.value(
          proposal.displayName,
          'displayName',
          'must be non-empty and bounded',
        );
      }
    }
  }
}

bool _contains(String root, String candidate) {
  final normalizedRoot = _comparisonPath(root);
  final normalizedCandidate = _comparisonPath(candidate);
  return normalizedCandidate == normalizedRoot ||
      normalizedCandidate.startsWith(
        '$normalizedRoot${Platform.pathSeparator}',
      );
}

String _comparisonPath(String value) {
  final normalized = File(value).absolute.uri.normalizePath().toFilePath();
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
