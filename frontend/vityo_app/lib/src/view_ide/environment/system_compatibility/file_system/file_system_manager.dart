import 'dart:async';
import 'dart:convert';

import 'file_system_adapter.dart';
import 'file_system_facts.dart';

enum VityoFileSystemEntityType { file, directory, link, notFound, other }

enum FileSystemManagerEventKind {
  created,
  modified,
  deleted,
  moved,
  metadataChanged,
  unknown,
}

enum FileSystemFailureKind {
  unsupportedProvider,
  invalidPath,
  outsideWorkspace,
  permissionDenied,
  readOnlyTarget,
  policyBlocked,
  resourceLimitReached,
  notFound,
  conflict,
  staleTarget,
  unknownFailure,
}

enum FileSystemNewline { lf, crlf, cr }

extension FileSystemNewlineX on FileSystemNewline {
  String get sequence {
    return switch (this) {
      FileSystemNewline.lf => '\n',
      FileSystemNewline.crlf => '\r\n',
      FileSystemNewline.cr => '\r',
    };
  }
}

class FileSystemTextDecodeResult {
  const FileSystemTextDecodeResult({
    required this.text,
    required this.hadUtf8Bom,
    required this.newlineNormalized,
  });

  final String text;
  final bool hadUtf8Bom;
  final bool newlineNormalized;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'textLength': text.length,
      'hadUtf8Bom': hadUtf8Bom,
      'newlineNormalized': newlineNormalized,
    };
  }
}

class FileSystemTextCodec {
  const FileSystemTextCodec({
    this.stripUtf8Bom = true,
    this.normalizeNewlines = true,
    this.outputNewline = FileSystemNewline.lf,
  });

  final bool stripUtf8Bom;
  final bool normalizeNewlines;
  final FileSystemNewline outputNewline;

  FileSystemTextDecodeResult decode(List<int> bytes) {
    final hadUtf8Bom =
        bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF;
    final contentBytes = hadUtf8Bom && stripUtf8Bom ? bytes.sublist(3) : bytes;
    final decoded = utf8.decode(contentBytes);
    final normalized = normalizeNewlines
        ? decoded.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
        : decoded;
    return FileSystemTextDecodeResult(
      text: normalized,
      hadUtf8Bom: hadUtf8Bom,
      newlineNormalized: decoded != normalized,
    );
  }

  List<int> encode(String text, {bool includeUtf8Bom = false}) {
    final newlineText = outputNewline == FileSystemNewline.lf
        ? text
        : text.replaceAll('\n', outputNewline.sequence);
    final encoded = utf8.encode(newlineText);
    if (!includeUtf8Bom) {
      return encoded;
    }
    return <int>[0xEF, 0xBB, 0xBF, ...encoded];
  }
}

class FileSystemOperationFailure {
  const FileSystemOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final FileSystemFailureKind kind;
  final String operation;
  final String target;
  final String sourceManager;
  final String message;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'target': target,
      'sourceManager': sourceManager,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

typedef FileSystemPlatformFailureKindResolver =
    FileSystemFailureKind? Function(Object error);

class FileSystemFailureClassifier {
  const FileSystemFailureClassifier({
    required this.sourceManager,
    this.platformFailureKindResolver,
  });

  final String sourceManager;
  final FileSystemPlatformFailureKindResolver? platformFailureKindResolver;

  FileSystemOperationFailure classify(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return FileSystemOperationFailure(
      kind: _kindFor(error),
      operation: operation,
      target: target,
      sourceManager: sourceManager,
      message: error.toString(),
      recoveryHint: recoveryHint,
    );
  }

  FileSystemFailureKind _kindFor(Object error) {
    if (error is UnsupportedError) {
      return FileSystemFailureKind.unsupportedProvider;
    }
    if (error is FormatException || error is ArgumentError) {
      return FileSystemFailureKind.invalidPath;
    }
    final platformKind = platformFailureKindResolver?.call(error);
    if (platformKind != null) {
      return platformKind;
    }
    return FileSystemFailureKind.unknownFailure;
  }
}

class FileSystemBoundaryException implements Exception {
  const FileSystemBoundaryException(this.failure);

  final FileSystemOperationFailure failure;

  @override
  String toString() {
    return failure.message;
  }
}

class FileSystemEntitySnapshot {
  const FileSystemEntitySnapshot({
    required this.path,
    required this.normalizedPath,
    required this.type,
    this.size,
    this.modifiedAt,
  });

  final String path;
  final String normalizedPath;
  final VityoFileSystemEntityType type;
  final int? size;
  final DateTime? modifiedAt;

  bool get exists => type != VityoFileSystemEntityType.notFound;

  bool get isFile => type == VityoFileSystemEntityType.file;

  bool get isDirectory => type == VityoFileSystemEntityType.directory;
}

class FileSystemManagerEvent {
  const FileSystemManagerEvent({
    required this.kind,
    required this.path,
    required this.normalizedPath,
    this.isDirectory = false,
  });

  final FileSystemManagerEventKind kind;
  final String path;
  final String normalizedPath;
  final bool isDirectory;
}

abstract class FileSystemManager {
  FileSystemFacts get facts;

  FileSystemCompatibility get compatibility;

  String normalizePath(String path);

  String joinPath(Iterable<String> segments);

  Uri toFileUri(String path);

  String pathFromFileUri(Uri uri);

  bool isWithin(String childPath, String parentPath);

  Future<FileSystemEntitySnapshot> stat(String path);

  Future<bool> exists(String path);

  Future<bool> isExecutable(String path);

  Future<void> setExecutable(String path, {bool executable = true});

  Future<String> readText(String path);

  Future<List<int>> readBytes(String path);

  Future<void> writeText(
    String path,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  });

  Future<void> writeBytes(
    String path,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  });

  Future<void> createDirectory(String path, {bool recursive = true});

  Future<void> delete(String path, {bool recursive = false});

  Future<void> copy(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  });

  Future<void> move(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  });

  Future<void> rename(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  });

  Future<List<FileSystemEntitySnapshot>> list(
    String path, {
    bool recursive = false,
  });

  Stream<FileSystemManagerEvent> watch(String path, {bool recursive = false});

  FileSystemOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  });
}

class FileSystemBoundaryGuard {
  const FileSystemBoundaryGuard({
    required FileSystemManager fileSystemManager,
    required this.rootPath,
    this.sourceManager = 'FileSystemBoundaryGuard',
  }) : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;
  final String rootPath;
  final String sourceManager;

  bool contains(String targetPath) {
    return _fileSystemManager.isWithin(targetPath, rootPath);
  }

  FileSystemOperationFailure? checkWithin(
    String targetPath, {
    required String operation,
    String? recoveryHint,
  }) {
    if (contains(targetPath)) {
      return null;
    }
    return FileSystemOperationFailure(
      kind: FileSystemFailureKind.outsideWorkspace,
      operation: operation,
      target: targetPath,
      sourceManager: sourceManager,
      message: 'File system operation target is outside the allowed root.',
      recoveryHint: recoveryHint,
    );
  }

  void requireWithin(
    String targetPath, {
    required String operation,
    String? recoveryHint,
  }) {
    final failure = checkWithin(
      targetPath,
      operation: operation,
      recoveryHint: recoveryHint,
    );
    if (failure != null) {
      throw FileSystemBoundaryException(failure);
    }
  }
}

enum FileSystemProviderRouteKind { local, unsupported }

class FileSystemProviderRoute {
  const FileSystemProviderRoute({
    required this.kind,
    required this.uri,
    this.path,
    this.failure,
  });

  final FileSystemProviderRouteKind kind;
  final Uri uri;
  final String? path;
  final FileSystemOperationFailure? failure;

  bool get supported => kind != FileSystemProviderRouteKind.unsupported;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'uri': uri.toString(),
      if (path != null) 'path': path,
      if (failure != null) 'failure': failure!.toJson(),
      'supported': supported,
    };
  }
}

class FileSystemProviderRouter {
  const FileSystemProviderRouter({
    required FileSystemManager fileSystemManager,
    this.sourceManager = 'FileSystemProviderRouter',
  }) : _fileSystemManager = fileSystemManager;

  final FileSystemManager _fileSystemManager;
  final String sourceManager;

  FileSystemProviderRoute route(Uri uri, {String operation = 'route'}) {
    if (!uri.hasScheme) {
      return FileSystemProviderRoute(
        kind: FileSystemProviderRouteKind.local,
        uri: uri,
        path: _fileSystemManager.normalizePath(uri.toString()),
      );
    }
    if (uri.scheme == 'file') {
      return FileSystemProviderRoute(
        kind: FileSystemProviderRouteKind.local,
        uri: uri,
        path: _fileSystemManager.pathFromFileUri(uri),
      );
    }
    return FileSystemProviderRoute(
      kind: FileSystemProviderRouteKind.unsupported,
      uri: uri,
      failure: FileSystemOperationFailure(
        kind: FileSystemFailureKind.unsupportedProvider,
        operation: operation,
        target: uri.toString(),
        sourceManager: sourceManager,
        message: 'Unsupported file system provider scheme ${uri.scheme}.',
      ),
    );
  }
}

class UnsupportedFileSystemManager implements FileSystemManager {
  UnsupportedFileSystemManager({required this.facts})
    : compatibility = FileSystemAdapter(facts).adapt();

  @override
  final FileSystemFacts facts;

  @override
  final FileSystemCompatibility compatibility;

  @override
  String normalizePath(String path) {
    return compatibility.normalizePath(path);
  }

  @override
  String joinPath(Iterable<String> segments) {
    return compatibility.joinPath(segments);
  }

  @override
  Uri toFileUri(String path) {
    return compatibility.toFileUri(path);
  }

  @override
  String pathFromFileUri(Uri uri) {
    return compatibility.pathFromFileUri(uri);
  }

  @override
  bool isWithin(String childPath, String parentPath) {
    return compatibility.isWithin(childPath, parentPath);
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<void> copy(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<void> move(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<void> rename(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<bool> exists(String path) async {
    return false;
  }

  @override
  Future<bool> isExecutable(String path) async {
    return false;
  }

  @override
  Future<void> setExecutable(String path, {bool executable = true}) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<List<FileSystemEntitySnapshot>> list(
    String path, {
    bool recursive = false,
  }) async {
    return const <FileSystemEntitySnapshot>[];
  }

  @override
  Future<String> readText(String path) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<List<int>> readBytes(String path) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<FileSystemEntitySnapshot> stat(String path) async {
    final normalized = normalizePath(path);
    return FileSystemEntitySnapshot(
      path: path,
      normalizedPath: normalized,
      type: VityoFileSystemEntityType.notFound,
    );
  }

  @override
  Stream<FileSystemManagerEvent> watch(String path, {bool recursive = false}) {
    return const Stream<FileSystemManagerEvent>.empty();
  }

  @override
  FileSystemOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return const FileSystemFailureClassifier(
      sourceManager: 'UnsupportedFileSystemManager',
    ).classify(
      error,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<void> writeText(
    String path,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    throw UnsupportedError('File system operations are not available.');
  }

  @override
  Future<void> writeBytes(
    String path,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    throw UnsupportedError('File system operations are not available.');
  }
}
