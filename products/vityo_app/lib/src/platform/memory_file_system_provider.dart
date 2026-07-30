import 'dart:async';

import '../view_ide/environment/system_compatibility/file_system/file_system_adapter.dart';
import '../view_ide/environment/system_compatibility/file_system/file_system_facts.dart';
import '../view_ide/environment/system_compatibility/file_system/file_system_manager.dart';
import '../view_ide/foundation/lock_service/lock_service.dart';
import 'file_system_operation_result.dart';
import 'file_system_provider.dart';

/// An in-memory file system provider.
///
/// All data is stored in a [Map] keyed by normalized URI path. Supports the
/// `memory://` scheme. Useful for testing, ephemeral caching, and
/// environments without a local file system.
class MemoryFileSystemProvider implements FileSystemProvider {
  MemoryFileSystemProvider({
    String providerId = 'memory',
    FileSystemFacts? facts,
  }) : _providerId = providerId,
       _facts = facts ?? _defaultFacts(),
       _lockService = FoundationLockService();

  static FileSystemFacts _defaultFacts() {
    return FileSystemFacts(
      targetId: 'memory-fs',
      operatingSystem: 'virtual',
      distributionId: 'virtual',
      distributionName: 'Virtual Memory FS',
      architecture: 'virtual',
      pathStyle: FileSystemPathStyle.posix,
      pathSeparator: '/',
      providerKind: FileSystemProviderKind.virtual,
      watchSupport: FileSystemWatchSupport.polling,
      caseSensitive: true,
      supportsFileUri: false,
      supportsSymbolicLinks: false,
      supportsAtomicWrite: true,
      detectedAt: DateTime.now().toUtc(),
    );
  }

  final String _providerId;
  final FileSystemFacts _facts;
  final FoundationLockService _lockService;

  final FileSystemCompatibility _compatibility = const FileSystemCompatibility(
    targetId: 'memory-fs',
    compatibilityTarget: 'virtual',
    pathStyle: FileSystemPathStyle.posix,
    pathSeparator: '/',
    caseSensitive: true,
    providerKind: FileSystemProviderKind.virtual,
    watchSupport: FileSystemWatchSupport.polling,
    supportsFileUri: false,
    supportsSymbolicLinks: false,
    supportsAtomicWrite: true,
  );

  final Map<String, MemoryFileNode> _nodes = <String, MemoryFileNode>{};
  final StreamController<FileSystemManagerEvent> _eventController =
      StreamController<FileSystemManagerEvent>.broadcast(sync: true);

  @override
  String get providerId => _providerId;

  @override
  Set<String> get supportedSchemes => const <String>{'memory'};

  @override
  FileSystemFacts get facts => _facts;

  @override
  FileSystemCompatibility get compatibility => _compatibility;

  @override
  bool supportsScheme(String scheme) => supportedSchemes.contains(scheme);

  // -- Entry point used by the router to resolve a memory:// URI to a path --
  String _path(Uri uri) {
    // memory://path/to/file => /path/to/file
    var path = uri.path;
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return _compatibility.normalizePath(path);
  }

  String _lockKey(Uri uri) => 'memory:${_path(uri)}';

  // -- Internal helpers --

  MemoryFileNode _ensureDirectory(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    var current = '/';
    for (final part in parts) {
      final child = _nodes['$current$part'];
      if (child == null) {
        final dir = MemoryFileNode(isDirectory: true);
        _nodes['$current$part'] = dir;
        current = '$current$part/';
      } else if (child.isDirectory) {
        current = '$current$part/';
      } else {
        throw FileSystemBoundaryException(
          FileSystemOperationFailure(
            kind: FileSystemFailureKind.conflict,
            operation: 'createDirectory',
            target: path,
            sourceManager: providerId,
            message: 'A file already exists at one of the path segments.',
          ),
        );
      }
    }
    return _nodes[path] ?? MemoryFileNode(isDirectory: true);
  }

  MemoryFileNode? _parentDirectory(String path) {
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash <= 0) {
      return _nodes['/'];
    }
    return _nodes[path.substring(0, lastSlash)];
  }

  FileSystemEntitySnapshot _snapshot(String path) {
    final normalized = _compatibility.normalizePath(path);
    final node = _nodes[normalized];
    if (node == null) {
      return FileSystemEntitySnapshot(
        path: path,
        normalizedPath: normalized,
        type: VityoFileSystemEntityType.notFound,
      );
    }
    return FileSystemEntitySnapshot(
      path: path,
      normalizedPath: normalized,
      type: node.isDirectory
          ? VityoFileSystemEntityType.directory
          : VityoFileSystemEntityType.file,
      size: node.isDirectory ? null : node.bytes?.length ?? 0,
      modifiedAt: node.modifiedAt,
    );
  }

  void _emitEvent(
    FileSystemManagerEventKind kind,
    String path, {
    bool isDirectory = false,
  }) {
    if (_eventController.isClosed) {
      return;
    }
    final normalized = _compatibility.normalizePath(path);
    _eventController.add(
      FileSystemManagerEvent(
        kind: kind,
        path: path,
        normalizedPath: normalized,
        isDirectory: isDirectory,
      ),
    );
  }

  // -- FileSystemProvider implementation --

  @override
  Future<FileSystemOperationResult<FileSystemEntitySnapshot>> stat(
    Uri uri,
  ) async {
    final path = _path(uri);
    final node = _nodes[path];
    if (node == null) {
      return FileSystemOperationSuccess(
        FileSystemEntitySnapshot(
          path: path,
          normalizedPath: path,
          type: VityoFileSystemEntityType.notFound,
        ),
      );
    }
    return FileSystemOperationSuccess(_snapshot(path));
  }

  @override
  Future<FileSystemOperationResult<String>> readText(Uri uri) async {
    final path = _path(uri);
    final node = _nodes[path];
    if (node == null) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.notFound,
          operation: 'readText',
          target: path,
          sourceManager: providerId,
          message: 'File not found: $path',
        ),
      );
    }
    if (node.isDirectory) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.invalidPath,
          operation: 'readText',
          target: path,
          sourceManager: providerId,
          message: 'Cannot read text from a directory.',
        ),
      );
    }
    return FileSystemOperationSuccess(
      node.text ?? String.fromCharCodes(node.bytes ?? <int>[]),
    );
  }

  @override
  Future<FileSystemOperationResult<List<int>>> readBytes(Uri uri) async {
    final path = _path(uri);
    final node = _nodes[path];
    if (node == null) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.notFound,
          operation: 'readBytes',
          target: path,
          sourceManager: providerId,
          message: 'File not found: $path',
        ),
      );
    }
    if (node.isDirectory) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.invalidPath,
          operation: 'readBytes',
          target: path,
          sourceManager: providerId,
          message: 'Cannot read bytes from a directory.',
        ),
      );
    }
    return FileSystemOperationSuccess(
      node.bytes ?? (node.text != null ? _codeUnits(node.text!) : <int>[]),
    );
  }

  List<int> _codeUnits(String text) {
    return text.codeUnits;
  }

  @override
  Future<FileSystemOperationResult<void>> writeText(
    Uri uri,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    return _lockService.runExclusive(_lockKey(uri), (_) async {
      final path = _path(uri);
      if (createParents) {
        _ensureParentDirectory(path);
      }
      if (_nodes[path]?.isDirectory == true) {
        return FileSystemOperationFailureResult(
          FileSystemOperationFailure(
            kind: FileSystemFailureKind.conflict,
            operation: 'writeText',
            target: path,
            sourceManager: providerId,
            message: 'Cannot write text: path is a directory.',
          ),
        );
      }
      final node = MemoryFileNode(text: contents);
      _nodes[path] = node;
      _emitEvent(FileSystemManagerEventKind.modified, path);
      return const FileSystemOperationSuccess<void>(null);
    });
  }

  @override
  Future<FileSystemOperationResult<void>> writeBytes(
    Uri uri,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    return _lockService.runExclusive(_lockKey(uri), (_) async {
      final path = _path(uri);
      if (createParents) {
        _ensureParentDirectory(path);
      }
      if (_nodes[path]?.isDirectory == true) {
        return FileSystemOperationFailureResult(
          FileSystemOperationFailure(
            kind: FileSystemFailureKind.conflict,
            operation: 'writeBytes',
            target: path,
            sourceManager: providerId,
            message: 'Cannot write bytes: path is a directory.',
          ),
        );
      }
      final node = MemoryFileNode(bytes: List<int>.from(contents));
      _nodes[path] = node;
      _emitEvent(FileSystemManagerEventKind.modified, path);
      return const FileSystemOperationSuccess<void>(null);
    });
  }

  Future<FileSystemOperationResult<void>> writeTextSync(
    String path,
    String contents, {
    bool createParents = true,
  }) async {
    // Not needed for memory provider; delegate to writeText.
    return writeText(
      Uri.parse('memory://$path'),
      contents,
      createParents: createParents,
    );
  }

  @override
  Future<FileSystemOperationResult<List<FileSystemEntitySnapshot>>> list(
    Uri uri, {
    bool recursive = false,
  }) async {
    final path = _path(uri);
    final node = _nodes[path];
    if (node == null) {
      return const FileSystemOperationSuccess(<FileSystemEntitySnapshot>[]);
    }
    if (!node.isDirectory) {
      return FileSystemOperationSuccess(<FileSystemEntitySnapshot>[
        _snapshot(path),
      ]);
    }

    final prefix = path.endsWith('/') ? path : '$path/';
    final results = <FileSystemEntitySnapshot>[];
    for (final entry in _nodes.keys) {
      if (entry == path || !entry.startsWith(prefix)) {
        continue;
      }
      final suffix = entry.substring(prefix.length);
      if (!recursive && suffix.contains('/')) {
        continue;
      }
      results.add(_snapshot(entry));
    }
    results.sort((a, b) => a.normalizedPath.compareTo(b.normalizedPath));
    return FileSystemOperationSuccess(results);
  }

  @override
  Future<FileSystemOperationResult<void>> createDirectory(
    Uri uri, {
    bool recursive = true,
  }) async {
    final path = _path(uri);
    final existing = _nodes[path];
    if (existing != null) {
      if (existing.isDirectory) {
        return const FileSystemOperationSuccess<void>(null);
      }
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.conflict,
          operation: 'createDirectory',
          target: path,
          sourceManager: providerId,
          message: 'A file already exists at this path.',
        ),
      );
    }
    if (recursive) {
      _ensureDirectory(path);
    } else {
      final parent = _parentDirectory(path);
      if (parent == null) {
        return FileSystemOperationFailureResult(
          FileSystemOperationFailure(
            kind: FileSystemFailureKind.notFound,
            operation: 'createDirectory',
            target: path,
            sourceManager: providerId,
            message: 'Parent directory does not exist.',
          ),
        );
      }
      _nodes[path] = MemoryFileNode(isDirectory: true);
    }
    _emitEvent(FileSystemManagerEventKind.created, path, isDirectory: true);
    return const FileSystemOperationSuccess<void>(null);
  }

  @override
  Future<FileSystemOperationResult<void>> delete(
    Uri uri, {
    bool recursive = false,
  }) async {
    final path = _path(uri);
    final node = _nodes[path];
    if (node == null) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.notFound,
          operation: 'delete',
          target: path,
          sourceManager: providerId,
          message: 'Path not found: $path',
        ),
      );
    }
    if (node.isDirectory && !recursive) {
      // Check if directory is empty
      final prefix = path.endsWith('/') ? path : '$path/';
      final hasChildren = _nodes.keys.any(
        (key) => key != path && key.startsWith(prefix),
      );
      if (hasChildren) {
        return FileSystemOperationFailureResult(
          FileSystemOperationFailure(
            kind: FileSystemFailureKind.conflict,
            operation: 'delete',
            target: path,
            sourceManager: providerId,
            message: 'Directory is not empty.',
          ),
        );
      }
    }
    if (node.isDirectory && recursive) {
      final prefix = path.endsWith('/') ? path : '$path/';
      _nodes.removeWhere((key, _) => key == path || key.startsWith(prefix));
    } else {
      _nodes.remove(path);
    }
    _emitEvent(
      FileSystemManagerEventKind.deleted,
      path,
      isDirectory: node.isDirectory,
    );
    return const FileSystemOperationSuccess<void>(null);
  }

  @override
  Future<FileSystemOperationResult<void>> copy(
    Uri source,
    Uri target, {
    bool overwrite = false,
  }) async {
    final srcPath = _path(source);
    final tgtPath = _path(target);
    final srcNode = _nodes[srcPath];
    if (srcNode == null) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.notFound,
          operation: 'copy',
          target: srcPath,
          sourceManager: providerId,
          message: 'Source not found.',
        ),
      );
    }
    final existing = _nodes[tgtPath];
    if (existing != null && !overwrite) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.conflict,
          operation: 'copy',
          target: tgtPath,
          sourceManager: providerId,
          message: 'Target already exists and overwrite is false.',
        ),
      );
    }
    if (srcNode.isDirectory) {
      _copyTree(srcPath, tgtPath);
    } else {
      _nodes[tgtPath] = srcNode.copy();
    }
    _emitEvent(FileSystemManagerEventKind.created, tgtPath);
    return const FileSystemOperationSuccess<void>(null);
  }

  void _copyTree(String srcPrefix, String tgtPrefix) {
    final srcPrefixNorm = srcPrefix.endsWith('/') ? srcPrefix : '$srcPrefix/';
    final tgtPrefixNorm = tgtPrefix.endsWith('/') ? tgtPrefix : '$tgtPrefix/';
    for (final entry in _nodes.keys.toList()) {
      if (entry == srcPrefix || entry.startsWith(srcPrefixNorm)) {
        final relative = entry == srcPrefix
            ? ''
            : entry.substring(srcPrefixNorm.length - 1);
        final newKey = entry == srcPrefix
            ? tgtPrefix
            : '$tgtPrefixNorm$relative';
        _nodes[newKey] = _nodes[entry]!.copy();
      }
    }
  }

  @override
  Future<FileSystemOperationResult<void>> move(
    Uri source,
    Uri target, {
    bool overwrite = false,
  }) async {
    final srcPath = _path(source);
    final tgtPath = _path(target);
    final srcNode = _nodes[srcPath];
    if (srcNode == null) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.notFound,
          operation: 'move',
          target: srcPath,
          sourceManager: providerId,
          message: 'Source not found.',
        ),
      );
    }
    final existing = _nodes[tgtPath];
    if (existing != null && !overwrite) {
      return FileSystemOperationFailureResult(
        FileSystemOperationFailure(
          kind: FileSystemFailureKind.conflict,
          operation: 'move',
          target: tgtPath,
          sourceManager: providerId,
          message: 'Target already exists and overwrite is false.',
        ),
      );
    }
    if (srcNode.isDirectory) {
      _copyTree(srcPath, tgtPath);
      _deleteTree(srcPath);
    } else {
      _nodes[tgtPath] = srcNode;
      _nodes.remove(srcPath);
    }
    _emitEvent(
      FileSystemManagerEventKind.deleted,
      srcPath,
      isDirectory: srcNode.isDirectory,
    );
    _emitEvent(
      FileSystemManagerEventKind.created,
      tgtPath,
      isDirectory: srcNode.isDirectory,
    );
    return const FileSystemOperationSuccess<void>(null);
  }

  void _deleteTree(String path) {
    final prefix = path.endsWith('/') ? path : '$path/';
    _nodes.removeWhere((key, _) => key == path || key.startsWith(prefix));
  }

  @override
  Stream<FileSystemManagerEvent> watch(Uri uri, {bool recursive = false}) {
    final path = _path(uri);
    return _eventController.stream.where((event) {
      if (event.normalizedPath == path) {
        return true;
      }
      if (recursive && event.normalizedPath.startsWith('$path/')) {
        return true;
      }
      return false;
    });
  }

  @override
  Future<FileSystemOperationResult<void>> refresh() async {
    // In-memory provider is always current.
    return const FileSystemOperationSuccess<void>(null);
  }

  void _ensureParentDirectory(String path) {
    final lastSlash = path.lastIndexOf('/');
    if (lastSlash > 0) {
      _ensureDirectory(path.substring(0, lastSlash));
    }
  }
}

/// A node in the in-memory file tree.
class MemoryFileNode {
  MemoryFileNode({
    this.isDirectory = false,
    this.text,
    List<int>? bytes,
    DateTime? modifiedAt,
  }) : _bytes = bytes,
       modifiedAt = modifiedAt ?? DateTime.now().toUtc();

  final bool isDirectory;
  final String? text;
  final List<int>? _bytes;

  List<int>? get bytes {
    if (_bytes != null) return _bytes;
    if (text != null) return text!.codeUnits.toList();
    return null;
  }

  DateTime modifiedAt;

  MemoryFileNode copy() {
    return MemoryFileNode(
      isDirectory: isDirectory,
      text: text,
      bytes: _bytes != null ? List<int>.from(_bytes) : null,
      modifiedAt: modifiedAt,
    );
  }
}
