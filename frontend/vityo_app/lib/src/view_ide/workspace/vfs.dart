import 'dart:async';

enum VityoVfsEventKind { created, modified, deleted, moved }

class VityoVirtualFileRef {
  const VityoVirtualFileRef({
    required this.workspaceRoot,
    required this.path,
  });

  final String workspaceRoot;
  final String path;

  String get normalizedWorkspaceRoot => normalizePath(workspaceRoot);
  String get normalizedPath => _resolve(normalizedWorkspaceRoot, path).path;
  bool get hasWorkspaceTraversal {
    return _resolve(normalizedWorkspaceRoot, path).escapedWorkspace;
  }

  bool get isInsideWorkspace {
    final root = normalizedWorkspaceRoot;
    final normalized = normalizedPath;
    return !hasWorkspaceTraversal && containsPath(root, normalized);
  }

  String get workspaceRelativePath {
    if (!isInsideWorkspace) {
      return '';
    }
    return relativePath(normalizedWorkspaceRoot, normalizedPath);
  }

  static String resolvePath(String root, String path) {
    return _resolve(normalizePath(root), path).path;
  }

  static String normalizePath(String path) {
    final raw = path.replaceAll('\\', '/');
    final absolute = raw.startsWith('/');
    final parts = <String>[];
    for (final segment in raw.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (parts.isNotEmpty && parts.last != '..') {
          parts.removeLast();
        } else if (!absolute) {
          parts.add(segment);
        }
        continue;
      }
      parts.add(segment);
    }
    final joined = parts.join('/');
    if (absolute) {
      return joined.isEmpty ? '/' : '/$joined';
    }
    return joined;
  }

  static bool containsPath(String root, String path) {
    final normalizedRoot = normalizePath(root);
    final normalizedPath = normalizePath(path);
    return _containsNormalizedPath(normalizedRoot, normalizedPath);
  }

  static String relativePath(String root, String path) {
    final normalizedRoot = normalizePath(root);
    final normalizedPath = normalizePath(path);
    if (!_containsNormalizedPath(normalizedRoot, normalizedPath)) {
      return '';
    }
    if (normalizedPath == normalizedRoot) {
      return '';
    }
    if (normalizedRoot == '/') {
      return normalizedPath.substring(1);
    }
    if (normalizedRoot.isEmpty) {
      return normalizedPath;
    }
    return normalizedPath.substring(normalizedRoot.length + 1);
  }

  static _VityoPathResolution _resolve(String normalizedRoot, String path) {
    final raw = path.replaceAll('\\', '/');
    if (raw.startsWith('/')) {
      return _resolveAbsolute(normalizedRoot, raw);
    }
    return _resolveRelative(normalizedRoot, raw);
  }

  static _VityoPathResolution _resolveRelative(
    String normalizedRoot,
    String rawPath,
  ) {
    final rootParts = _parts(normalizedRoot);
    final parts = <String>[...rootParts];
    final absolute = normalizedRoot.startsWith('/');
    var escapedWorkspace = false;

    for (final segment in rawPath.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      if (segment == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
          if (parts.length < rootParts.length && normalizedRoot != '/') {
            escapedWorkspace = true;
          }
        } else if (normalizedRoot != '/') {
          escapedWorkspace = true;
          if (!absolute) {
            parts.add(segment);
          }
        }
        continue;
      }
      parts.add(segment);
    }

    return _VityoPathResolution(
      path: _joinParts(parts, absolute: absolute),
      escapedWorkspace: escapedWorkspace,
    );
  }

  static _VityoPathResolution _resolveAbsolute(
    String normalizedRoot,
    String rawPath,
  ) {
    final parts = <String>[];
    var escapedWorkspace = false;

    for (final segment in rawPath.split('/')) {
      if (segment.isEmpty || segment == '.') {
        continue;
      }
      final before = _joinParts(parts, absolute: true);
      final wasInsideWorkspace = _containsNormalizedPath(
        normalizedRoot,
        before,
      );
      if (segment == '..') {
        if (parts.isNotEmpty) {
          parts.removeLast();
        }
      } else {
        parts.add(segment);
      }
      final after = _joinParts(parts, absolute: true);
      if (wasInsideWorkspace &&
          normalizedRoot != '/' &&
          !_containsNormalizedPath(normalizedRoot, after)) {
        escapedWorkspace = true;
      }
    }

    return _VityoPathResolution(
      path: _joinParts(parts, absolute: true),
      escapedWorkspace: escapedWorkspace,
    );
  }

  static bool _containsNormalizedPath(String root, String path) {
    if (root == '/') {
      return path.startsWith('/');
    }
    if (root.isEmpty) {
      return path.isEmpty ||
          (!path.startsWith('/') && path != '..' && !path.startsWith('../'));
    }
    return path == root || path.startsWith('$root/');
  }

  static List<String> _parts(String normalizedPath) {
    return normalizedPath
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
  }

  static String _joinParts(List<String> parts, {required bool absolute}) {
    final joined = parts.join('/');
    if (absolute) {
      return joined.isEmpty ? '/' : '/$joined';
    }
    return joined;
  }
}

class _VityoPathResolution {
  const _VityoPathResolution({
    required this.path,
    required this.escapedWorkspace,
  });

  final String path;
  final bool escapedWorkspace;
}

class VityoVfsFileSnapshot {
  const VityoVfsFileSnapshot({
    required this.ref,
    required this.contentHash,
    required this.modifiedAtRevision,
    this.isDirectory = false,
    this.isSymlink = false,
  });

  final VityoVirtualFileRef ref;
  final String contentHash;
  final int modifiedAtRevision;
  final bool isDirectory;
  final bool isSymlink;
}

class VityoVfsSnapshot {
  const VityoVfsSnapshot({
    required this.revision,
    required this.files,
  });

  final int revision;
  final Map<String, VityoVfsFileSnapshot> files;

  VityoVfsFileSnapshot? lookup(VityoVirtualFileRef ref) {
    if (!ref.isInsideWorkspace) {
      return null;
    }
    final direct = files[ref.normalizedPath];
    if (direct != null) {
      return direct;
    }
    for (final file in files.values) {
      if (file.ref.normalizedPath == ref.normalizedPath) {
        return file;
      }
    }
    return null;
  }

  bool isBlockedBySymlinkGuard(VityoVirtualFileRef ref) {
    if (!ref.isInsideWorkspace) {
      return false;
    }
    for (final file in files.values) {
      if (!file.isSymlink || !file.ref.isInsideWorkspace) {
        continue;
      }
      if (VityoVirtualFileRef.containsPath(
        file.ref.normalizedPath,
        ref.normalizedPath,
      )) {
        return true;
      }
    }
    return false;
  }

  bool allowsAccess(VityoVirtualFileRef ref) {
    return ref.isInsideWorkspace && !isBlockedBySymlinkGuard(ref);
  }
}

class VityoVfsEvent {
  const VityoVfsEvent({
    required this.kind,
    required this.ref,
    this.previousRef,
    this.revision = 0,
  });

  final VityoVfsEventKind kind;
  final VityoVirtualFileRef ref;
  final VityoVirtualFileRef? previousRef;
  final int revision;
}

class VityoVfsIgnoreRules {
  const VityoVfsIgnoreRules({
    this.excludedPrefixes = const <String>[],
    this.excludedSuffixes = const <String>[],
  });

  final List<String> excludedPrefixes;
  final List<String> excludedSuffixes;

  bool excludes(VityoVirtualFileRef ref) {
    final absolutePath = ref.normalizedPath;
    final relativePath = ref.workspaceRelativePath;
    return excludedPrefixes.any(
          (prefix) => _matchesPrefix(
            absolutePath: absolutePath,
            relativePath: relativePath,
            rawPrefix: prefix,
          ),
        ) ||
        excludedSuffixes.any(
          (suffix) => _matchesSuffix(
            absolutePath: absolutePath,
            relativePath: relativePath,
            rawSuffix: suffix,
          ),
        );
  }

  bool _matchesPrefix({
    required String absolutePath,
    required String relativePath,
    required String rawPrefix,
  }) {
    final normalizedPrefix = VityoVirtualFileRef.normalizePath(rawPrefix);
    if (normalizedPrefix.isEmpty) {
      return false;
    }
    if (rawPrefix.replaceAll('\\', '/').startsWith('/')) {
      return VityoVirtualFileRef.containsPath(normalizedPrefix, absolutePath);
    }
    return VityoVirtualFileRef.containsPath(normalizedPrefix, relativePath);
  }

  bool _matchesSuffix({
    required String absolutePath,
    required String relativePath,
    required String rawSuffix,
  }) {
    final normalizedSuffix = VityoVirtualFileRef.normalizePath(rawSuffix);
    if (normalizedSuffix.isEmpty) {
      return false;
    }
    return absolutePath.endsWith(normalizedSuffix) ||
        relativePath.endsWith(normalizedSuffix);
  }
}

class VityoRefreshQueue {
  VityoRefreshQueue({
    this.ignoreRules = const VityoVfsIgnoreRules(),
    this.maxQueuedEvents = 4096,
    this.guardSnapshot,
  });

  final VityoVfsIgnoreRules ignoreRules;
  final int maxQueuedEvents;
  final VityoVfsSnapshot? guardSnapshot;
  final Map<String, VityoVfsEvent> _pending = <String, VityoVfsEvent>{};
  bool _cancelled = false;

  bool get isCancelled => _cancelled;
  int get pendingCount => _pending.length;

  void cancel() {
    _cancelled = true;
    _pending.clear();
  }

  bool enqueue(VityoVfsEvent event) {
    if (_cancelled ||
        !event.ref.isInsideWorkspace ||
        ignoreRules.excludes(event.ref) ||
        (guardSnapshot?.isBlockedBySymlinkGuard(event.ref) ?? false)) {
      return false;
    }
    final queuedEvent = _prepareForQueue(event);
    if (_pending.length >= maxQueuedEvents &&
        !_pending.containsKey(queuedEvent.ref.normalizedPath)) {
      return false;
    }
    _pending[queuedEvent.ref.normalizedPath] = _coalesce(
      _pending[queuedEvent.ref.normalizedPath],
      queuedEvent,
    );
    return true;
  }

  List<VityoVfsEvent> drain() {
    final events = _pending.values.toList(growable: false)
      ..sort(
        (left, right) => left.ref.normalizedPath.compareTo(
          right.ref.normalizedPath,
        ),
      );
    _pending.clear();
    return events;
  }

  VityoVfsEvent _prepareForQueue(VityoVfsEvent event) {
    final previousRef = event.previousRef;
    if (event.kind != VityoVfsEventKind.moved ||
        previousRef == null ||
        previousRef.normalizedPath == event.ref.normalizedPath) {
      return event;
    }
    final previousEvent = _pending.remove(previousRef.normalizedPath);
    if (previousEvent?.kind == VityoVfsEventKind.created) {
      return VityoVfsEvent(
        kind: VityoVfsEventKind.created,
        ref: event.ref,
        revision: event.revision,
      );
    }
    return event;
  }

  VityoVfsEvent _coalesce(VityoVfsEvent? previous, VityoVfsEvent next) {
    if (previous == null) {
      return next;
    }
    if (previous.kind == VityoVfsEventKind.created &&
        next.kind == VityoVfsEventKind.modified) {
      return VityoVfsEvent(
        kind: VityoVfsEventKind.created,
        ref: next.ref,
        revision: next.revision,
      );
    }
    if (previous.kind == VityoVfsEventKind.created &&
        next.kind == VityoVfsEventKind.deleted) {
      return next;
    }
    if (previous.kind == VityoVfsEventKind.deleted &&
        next.kind == VityoVfsEventKind.created) {
      return VityoVfsEvent(
        kind: VityoVfsEventKind.modified,
        ref: next.ref,
        revision: next.revision,
      );
    }
    return next;
  }
}

abstract class VityoFileWatcher {
  Stream<VityoVfsEvent> get events;
  Future<void> start();
  Future<void> stop();
}
