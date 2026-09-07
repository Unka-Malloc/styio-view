import 'dart:async';
import 'dart:convert';

import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../../../../ide/local_service/vityod_client.dart';
import 'file_system_adapter.dart';
import 'file_system_facts.dart';
import 'file_system_manager.dart';

final class VityodFileSystemException implements Exception {
  const VityodFileSystemException(this.code, this.operation);

  final String code;
  final String operation;

  @override
  String toString() => 'VityodFileSystemException($code, $operation)';
}

final class VityodFileSystemManager implements FileSystemManager {
  VityodFileSystemManager._({
    required int managerId,
    required this.facts,
    required this.compatibility,
    required VityodClient client,
    required List<_VityodFileScope> scopes,
  }) : _client = client,
       _managerId = managerId,
       _scopes = List<_VityodFileScope>.unmodifiable(scopes);

  static Future<VityodFileSystemManager> open({
    required FileSystemFacts facts,
    required VityodClient client,
    required Iterable<String> allowedRoots,
  }) async {
    final compatibility = FileSystemAdapter(facts).adapt();
    final normalizedRoots = <String>[];
    for (final root in allowedRoots) {
      final normalized = compatibility.normalizePath(root);
      if (!compatibility.isAbsolutePath(normalized)) {
        throw ArgumentError.value(
          root,
          'allowedRoots',
          'Roots must be absolute.',
        );
      }
      final duplicate = normalizedRoots.any((existing) {
        if (compatibility.caseSensitive) return existing == normalized;
        return existing.toLowerCase() == normalized.toLowerCase();
      });
      if (!duplicate) normalizedRoots.add(normalized);
    }
    normalizedRoots.sort((left, right) => right.length.compareTo(left.length));
    final managerId = ++_managerSequence;
    final scopes = <_VityodFileScope>[];
    for (var index = 0; index < normalizedRoots.length; index += 1) {
      final scope = _VityodFileScope(
        id: 'desktop-fs-$managerId-$index',
        rootPath: normalizedRoots[index],
      );
      final response = await client.request(
        method: 'fs.scope.open',
        idempotencyKey: 'fs-scope-open-${scope.id}',
        params: <String, Object?>{
          'scopeId': scope.id,
          'rootPath': scope.rootPath,
        },
      );
      _requireSuccess(response, 'fs.scope.open');
      scopes.add(scope);
    }
    if (scopes.isEmpty) {
      throw ArgumentError.value(
        allowedRoots,
        'allowedRoots',
        'At least one root is required.',
      );
    }
    return VityodFileSystemManager._(
      managerId: managerId,
      facts: facts,
      compatibility: compatibility,
      client: client,
      scopes: scopes,
    );
  }

  final VityodClient _client;
  final List<_VityodFileScope> _scopes;
  final int _managerId;
  int _requestSequence = 0;
  int _watchSequence = 0;

  @override
  final FileSystemFacts facts;

  @override
  final FileSystemCompatibility compatibility;

  @override
  String normalizePath(String path) => compatibility.normalizePath(path);

  @override
  String joinPath(Iterable<String> segments) =>
      compatibility.joinPath(segments);

  @override
  Uri toFileUri(String path) => compatibility.toFileUri(path);

  @override
  String pathFromFileUri(Uri uri) => compatibility.pathFromFileUri(uri);

  @override
  bool isWithin(String childPath, String parentPath) =>
      compatibility.isWithin(childPath, parentPath);

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    final target = _target(path);
    await _request('fs.createDirectory', <String, Object?>{
      ...target.params,
      'recursive': recursive,
    });
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final target = _target(path);
    await _request('fs.delete', <String, Object?>{
      ...target.params,
      'recursive': recursive,
    });
  }

  @override
  Future<void> copy(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    await _transfer('fs.copy', sourcePath, targetPath, overwrite: overwrite);
  }

  @override
  Future<void> move(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    await _transfer('fs.move', sourcePath, targetPath, overwrite: overwrite);
  }

  @override
  Future<void> rename(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) => move(sourcePath, targetPath, overwrite: overwrite);

  @override
  Future<bool> exists(String path) async => (await stat(path)).exists;

  @override
  Future<bool> isExecutable(String path) async {
    final response = await _request('fs.isExecutable', _target(path).params);
    return _requiredBool(response.params, 'executable');
  }

  @override
  Future<void> setExecutable(String path, {bool executable = true}) async {
    final target = _target(path);
    await _request('fs.setExecutable', <String, Object?>{
      ...target.params,
      'executable': executable,
    });
  }

  @override
  Future<List<FileSystemEntitySnapshot>> list(
    String path, {
    bool recursive = false,
  }) async {
    final target = _target(path);
    final entries = <FileSystemEntitySnapshot>[];
    var cursor = 0;
    while (true) {
      final response = await _request('fs.list', <String, Object?>{
        ...target.params,
        'recursive': recursive,
        'cursor': cursor,
        'limit': 1000,
      });
      final page = response.params['entries'];
      if (page is! List) {
        throw const VityodFileSystemException(
          'invalid_file_response',
          'fs.list',
        );
      }
      for (final value in page) {
        if (value is! Map) {
          throw const VityodFileSystemException(
            'invalid_file_response',
            'fs.list',
          );
        }
        entries.add(_snapshot(target.scope, Map<String, Object?>.from(value)));
      }
      final next = response.params['nextCursor'];
      if (next == null) break;
      if (next is! int || next <= cursor) {
        throw const VityodFileSystemException(
          'invalid_file_response',
          'fs.list',
        );
      }
      cursor = next;
    }
    return List<FileSystemEntitySnapshot>.unmodifiable(entries);
  }

  @override
  Future<String> readText(String path) async =>
      utf8.decode(await readBytes(path));

  @override
  Future<List<int>> readBytes(String path) async {
    final response = await _request('fs.read', _target(path).params);
    final encoded = response.params['contentsBase64'];
    if (encoded is! String) {
      throw const VityodFileSystemException('invalid_file_response', 'fs.read');
    }
    try {
      return base64Decode(encoded);
    } on FormatException {
      throw const VityodFileSystemException('invalid_file_response', 'fs.read');
    }
  }

  @override
  Future<FileSystemEntitySnapshot> stat(String path) async {
    final target = _target(path);
    final response = await _request('fs.stat', target.params);
    final entry = response.params['entry'];
    if (entry is! Map) {
      throw const VityodFileSystemException('invalid_file_response', 'fs.stat');
    }
    return _snapshot(
      target.scope,
      Map<String, Object?>.from(entry),
      originalPath: path,
    );
  }

  @override
  Stream<FileSystemManagerEvent> watch(
    String path, {
    bool recursive = false,
  }) async* {
    final target = _target(path);
    final watchId = 'client-watch-$_managerId-${++_watchSequence}';
    await _request('fs.watch.start', <String, Object?>{
      ...target.params,
      'watchId': watchId,
      'recursive': recursive,
    });
    try {
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final response = await _request('fs.watch.poll', <String, Object?>{
          'watchId': watchId,
        });
        if (response.params['overflowed'] == true) {
          throw const VityodFileSystemException(
            'file_watch_overflow',
            'fs.watch.poll',
          );
        }
        final events = response.params['events'];
        if (events is! List) {
          throw const VityodFileSystemException(
            'invalid_file_response',
            'fs.watch.poll',
          );
        }
        for (final value in events) {
          if (value is! Map) {
            throw const VityodFileSystemException(
              'invalid_file_response',
              'fs.watch.poll',
            );
          }
          final event = Map<String, Object?>.from(value);
          final relativePath = _requiredString(event, 'relativePath');
          final absolutePath = joinPath(<String>[
            target.scope.rootPath,
            relativePath,
          ]);
          yield FileSystemManagerEvent(
            kind: _eventKind(_requiredString(event, 'kind')),
            path: absolutePath,
            normalizedPath: normalizePath(absolutePath),
            isDirectory: event['isDirectory'] == true,
          );
        }
      }
    } finally {
      if (_client.state.canDispatch) {
        try {
          await _request('fs.watch.stop', <String, Object?>{
            'watchId': watchId,
          });
        } on Object {
          // The service may have disconnected while the stream was canceled.
        }
      }
    }
  }

  @override
  FileSystemOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    final kind = error is VityodFileSystemException
        ? _failureKind(error.code)
        : FileSystemFailureKind.unknownFailure;
    return FileSystemOperationFailure(
      kind: kind,
      operation: operation,
      target: target,
      sourceManager: 'VityodFileSystemManager',
      message: error.toString(),
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<void> writeText(
    String path,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  }) => writeBytes(
    path,
    utf8.encode(contents),
    createParents: createParents,
    atomic: atomic,
  );

  @override
  Future<void> writeBytes(
    String path,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    final target = _target(path);
    await _request('fs.write', <String, Object?>{
      ...target.params,
      'contentsBase64': base64Encode(contents),
      'createParents': createParents,
      'atomic': atomic,
    });
  }

  Future<void> _transfer(
    String method,
    String sourcePath,
    String targetPath, {
    required bool overwrite,
  }) async {
    final source = _target(sourcePath);
    final target = _target(targetPath);
    if (source.scope.id != target.scope.id) {
      throw VityodFileSystemException('cross_scope_move_unsupported', method);
    }
    await _request(method, <String, Object?>{
      'scopeId': source.scope.id,
      'sourceRelativePath': source.relativePath,
      'targetRelativePath': target.relativePath,
      'overwrite': overwrite,
    });
  }

  Future<VityodControlEnvelope> _request(
    String method,
    Map<String, Object?> params,
  ) async {
    final response = await _client.request(
      method: method,
      idempotencyKey: '$method-$_managerId-${++_requestSequence}',
      params: params,
    );
    _requireSuccess(response, method);
    return response;
  }

  _VityodFileTarget _target(String path) {
    final normalized = normalizePath(path);
    for (final scope in _scopes) {
      if (!isWithin(normalized, scope.rootPath)) continue;
      if (_equalPath(normalized, scope.rootPath)) {
        return _VityodFileTarget(scope: scope, relativePath: '.');
      }
      final prefix = scope.rootPath.endsWith(compatibility.pathSeparator)
          ? scope.rootPath
          : '${scope.rootPath}${compatibility.pathSeparator}';
      return _VityodFileTarget(
        scope: scope,
        relativePath: normalized.substring(prefix.length),
      );
    }
    throw const VityodFileSystemException(
      'path_outside_registered_scope',
      'route',
    );
  }

  bool _equalPath(String left, String right) {
    if (compatibility.caseSensitive) return left == right;
    return left.toLowerCase() == right.toLowerCase();
  }

  FileSystemEntitySnapshot _snapshot(
    _VityodFileScope scope,
    Map<String, Object?> entry, {
    String? originalPath,
  }) {
    final relativePath = _requiredString(entry, 'relativePath');
    final normalizedPath = relativePath == '.'
        ? scope.rootPath
        : joinPath(<String>[scope.rootPath, relativePath]);
    final modified = entry['modifiedUnixMillis'];
    return FileSystemEntitySnapshot(
      path: originalPath ?? normalizedPath,
      normalizedPath: normalizedPath,
      type: _entityType(_requiredString(entry, 'kind')),
      size: entry['size'] is int ? entry['size'] as int : null,
      modifiedAt: modified is int
          ? DateTime.fromMillisecondsSinceEpoch(modified)
          : null,
    );
  }
}

int _managerSequence = 0;

final class _VityodFileScope {
  const _VityodFileScope({required this.id, required this.rootPath});

  final String id;
  final String rootPath;
}

final class _VityodFileTarget {
  const _VityodFileTarget({required this.scope, required this.relativePath});

  final _VityodFileScope scope;
  final String relativePath;

  Map<String, Object?> get params => <String, Object?>{
    'scopeId': scope.id,
    'relativePath': relativePath,
  };
}

void _requireSuccess(VityodControlEnvelope response, String operation) {
  final method = response.method;
  if (method == '$operation.result') return;
  final code = response.params['errorCode'];
  throw VityodFileSystemException(
    code is String ? code : 'file_service_failed',
    operation,
  );
}

String _requiredString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is String) return value;
  throw const VityodFileSystemException('invalid_file_response', 'decode');
}

bool _requiredBool(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is bool) return value;
  throw const VityodFileSystemException('invalid_file_response', 'decode');
}

VityoFileSystemEntityType _entityType(String value) => switch (value) {
  'file' => VityoFileSystemEntityType.file,
  'directory' => VityoFileSystemEntityType.directory,
  'link' => VityoFileSystemEntityType.link,
  'notFound' => VityoFileSystemEntityType.notFound,
  _ => VityoFileSystemEntityType.other,
};

FileSystemManagerEventKind _eventKind(String value) => switch (value) {
  'created' => FileSystemManagerEventKind.created,
  'modified' => FileSystemManagerEventKind.modified,
  'deleted' => FileSystemManagerEventKind.deleted,
  _ => FileSystemManagerEventKind.unknown,
};

FileSystemFailureKind _failureKind(String code) => switch (code) {
  'workspace_root_escape' ||
  'path_outside_registered_scope' => FileSystemFailureKind.outsideWorkspace,
  'invalid_file_request' => FileSystemFailureKind.invalidPath,
  'file_not_found' => FileSystemFailureKind.notFound,
  'file_conflict' => FileSystemFailureKind.conflict,
  'file_capacity_exceeded' => FileSystemFailureKind.resourceLimitReached,
  'file_operation_unsupported' ||
  'cross_scope_move_unsupported' => FileSystemFailureKind.unsupportedProvider,
  _ => FileSystemFailureKind.unknownFailure,
};
