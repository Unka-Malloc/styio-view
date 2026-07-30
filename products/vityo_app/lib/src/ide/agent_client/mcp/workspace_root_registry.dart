import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
  }) : _resolver = resolver;

  final CanonicalPathResolver _resolver;
  final Map<String, WorkspaceRootSnapshot> _snapshots =
      <String, WorkspaceRootSnapshot>{};
  final Map<String, Future<void>> _lanes = <String, Future<void>>{};
  final StreamController<WorkspaceRootChange> _changes =
      StreamController<WorkspaceRootChange>.broadcast(sync: true);
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
    final completer = Completer<WorkspaceRootSnapshot>();
    final prior = _lanes[sessionId] ?? Future<void>.value();
    final operation = prior.then((_) async {
      try {
        completer.complete(
          await _replaceRoots(
            sessionId: sessionId,
            proposals: proposals,
            consentReceiptId: consentReceiptId,
          ),
        );
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _lanes[sessionId] = operation.then<void>((_) {}, onError: (_, __) {});
    return completer.future;
  }

  Future<RootAuthorization> authorize({
    required String sessionId,
    required String candidate,
  }) async {
    final current = snapshot(sessionId);
    if (current.roots.isEmpty) {
      return RootAuthorization(
        allowed: false,
        code: 'root_revoked',
        rootRevision: current.revision,
      );
    }
    final CanonicalPath resolved;
    try {
      resolved = await _resolver.resolve(candidate);
    } on FileSystemException {
      return RootAuthorization(
        allowed: false,
        code: 'path_unavailable',
        rootRevision: current.revision,
      );
    }
    for (final root in current.roots) {
      if (_contains(root.canonicalPath, resolved.path)) {
        return RootAuthorization(
          allowed: true,
          code: 'allowed',
          rootRevision: current.revision,
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
      rootRevision: current.revision,
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await Future.wait<void>(_lanes.values);
    await _changes.close();
  }

  Future<WorkspaceRootSnapshot> _replaceRoots({
    required String sessionId,
    required List<WorkspaceRootProposal> proposals,
    required String consentReceiptId,
  }) async {
    if (sessionId.trim().isEmpty || consentReceiptId.trim().isEmpty) {
      throw ArgumentError(
        'session and consent receipt identifiers are required',
      );
    }
    final rootsByPath = <String, ApprovedWorkspaceRoot>{};
    for (final proposal in proposals) {
      if (proposal.displayName.trim().isEmpty) {
        throw ArgumentError.value(
          proposal.displayName,
          'displayName',
          'must not be empty',
        );
      }
      final canonical = await _resolver.resolve(proposal.path);
      final comparison = _comparisonPath(canonical.path);
      rootsByPath.putIfAbsent(
        comparison,
        () => ApprovedWorkspaceRoot(
          id: sha256.convert(utf8.encode(comparison)).toString(),
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
