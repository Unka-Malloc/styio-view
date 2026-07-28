import 'dart:async';
import 'dart:io';

import 'file_system_adapter.dart';
import 'file_system_facts.dart';
import 'file_system_manager.dart';
import 'file_system_prober.dart';
import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'file_system_prober_io.dart';

Future<FileSystemManager> createPlatformFileSystemManager({
  FileSystemProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.fileSystem ??
      await (prober ?? const LocalFileSystemProber()).probe();
  return LocalFileSystemManager(
    facts: facts,
    adapter: adapter?.fileSystemAdapter,
  );
}

class LocalFileSystemManager implements FileSystemManager {
  LocalFileSystemManager({required this.facts, FileSystemAdapter? adapter})
    : compatibility = (adapter ?? FileSystemAdapter(facts)).adapt();

  factory LocalFileSystemManager.linuxDebianArmForTest() {
    return LocalFileSystemManager(facts: FileSystemFacts.linuxDebianArm());
  }

  factory LocalFileSystemManager.windowsX64ForTest() {
    return LocalFileSystemManager(facts: FileSystemFacts.windowsX64());
  }

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
    await Directory(normalizePath(path)).create(recursive: recursive);
  }

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final normalized = normalizePath(path);
    final type = await FileSystemEntity.type(normalized, followLinks: false);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(normalized).delete(recursive: recursive);
        return;
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        await File(normalized).delete(recursive: recursive);
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
      case FileSystemEntityType.notFound:
        return;
    }
  }

  @override
  Future<void> copy(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    final source = normalizePath(sourcePath);
    final target = normalizePath(targetPath);
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Source file system entity does not exist.',
        source,
        const OSError('No such file or directory', 2),
      );
    }
    await _prepareCopyOrMoveTarget(target, overwrite: overwrite);
    switch (sourceType) {
      case FileSystemEntityType.directory:
        await _copyDirectory(Directory(source), Directory(target));
        return;
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        await File(target).parent.create(recursive: true);
        await File(source).copy(target);
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw FileSystemException(
          'Unsupported file system entity type.',
          source,
        );
      case FileSystemEntityType.notFound:
        return;
    }
  }

  @override
  Future<void> move(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) async {
    final source = normalizePath(sourcePath);
    final target = normalizePath(targetPath);
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    if (sourceType == FileSystemEntityType.notFound) {
      throw FileSystemException(
        'Source file system entity does not exist.',
        source,
        const OSError('No such file or directory', 2),
      );
    }
    await _prepareCopyOrMoveTarget(target, overwrite: overwrite);
    switch (sourceType) {
      case FileSystemEntityType.directory:
        await Directory(target).parent.create(recursive: true);
        await Directory(source).rename(target);
        return;
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        await File(target).parent.create(recursive: true);
        await File(source).rename(target);
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        throw FileSystemException(
          'Unsupported file system entity type.',
          source,
        );
      case FileSystemEntityType.notFound:
        return;
    }
  }

  @override
  Future<void> rename(
    String sourcePath,
    String targetPath, {
    bool overwrite = false,
  }) {
    return move(sourcePath, targetPath, overwrite: overwrite);
  }

  @override
  Future<bool> exists(String path) async {
    return (await stat(path)).exists;
  }

  @override
  Future<bool> isExecutable(String path) async {
    final normalized = normalizePath(path);
    if (Platform.isWindows) {
      return File(normalized).exists();
    }
    final stat = await FileStat.stat(normalized);
    return stat.type == FileSystemEntityType.file && (stat.mode & 0x40) != 0;
  }

  @override
  Future<void> setExecutable(String path, {bool executable = true}) async {
    final normalized = normalizePath(path);
    if (Platform.isWindows) {
      return;
    }
    final result = await Process.run('chmod', <String>[
      executable ? 'u+x' : 'u-x',
      normalized,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'Failed to update executable permission: ${result.stderr}',
        normalized,
      );
    }
  }

  @override
  Future<List<FileSystemEntitySnapshot>> list(
    String path, {
    bool recursive = false,
  }) async {
    final normalized = normalizePath(path);
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      return const <FileSystemEntitySnapshot>[];
    }
    final snapshots = <FileSystemEntitySnapshot>[];
    await for (final entity in directory.list(
      recursive: recursive,
      followLinks: false,
    )) {
      snapshots.add(await stat(entity.path));
    }
    return snapshots;
  }

  @override
  Future<String> readText(String path) async {
    return _readFileWithRetry<String>(
      File(normalizePath(path)),
      (file) => file.readAsString(),
    );
  }

  @override
  Future<List<int>> readBytes(String path) async {
    return _readFileWithRetry<List<int>>(
      File(normalizePath(path)),
      (file) => file.readAsBytes(),
    );
  }

  @override
  Future<FileSystemEntitySnapshot> stat(String path) async {
    final normalized = normalizePath(path);
    final type = await FileSystemEntity.type(normalized, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return FileSystemEntitySnapshot(
        path: path,
        normalizedPath: normalized,
        type: VityoFileSystemEntityType.notFound,
      );
    }
    final stat = await FileStat.stat(normalized);
    return FileSystemEntitySnapshot(
      path: path,
      normalizedPath: normalized,
      type: _mapEntityType(type),
      size: stat.size,
      modifiedAt: stat.modified,
    );
  }

  @override
  Stream<FileSystemManagerEvent> watch(
    String path, {
    bool recursive = false,
  }) async* {
    if (!compatibility.supportsDirectoryWatch) {
      return;
    }
    final normalized = normalizePath(path);
    final snapshot = await stat(normalized);
    final watchRoot = snapshot.isDirectory
        ? normalized
        : File(normalized).parent.path;
    final watchFileOnly = !snapshot.isDirectory;
    final effectiveRecursive =
        recursive && compatibility.supportsRecursiveWatch;

    await for (final event in Directory(
      watchRoot,
    ).watch(recursive: effectiveRecursive)) {
      final eventPath = normalizePath(event.path);
      if (watchFileOnly && eventPath != normalized) {
        continue;
      }
      yield FileSystemManagerEvent(
        kind: _mapEventKind(event),
        path: event.path,
        normalizedPath: eventPath,
        isDirectory: event.isDirectory,
      );
    }
  }

  @override
  FileSystemOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return const FileSystemFailureClassifier(
      sourceManager: 'LocalFileSystemManager',
      platformFailureKindResolver: _localFileSystemFailureKind,
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
    final normalized = normalizePath(path);
    final target = File(normalized);
    if (createParents) {
      await target.parent.create(recursive: true);
    }
    if (atomic && compatibility.supportsAtomicWrite) {
      final temp = File(
        '$normalized.vityo-tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await temp.writeAsString(contents);
        await _renameFileWithRetry(temp, normalized);
      } finally {
        if (await temp.exists()) {
          await temp.delete();
        }
      }
      return;
    }
    await target.writeAsString(contents);
  }

  @override
  Future<void> writeBytes(
    String path,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    final normalized = normalizePath(path);
    final target = File(normalized);
    if (createParents) {
      await target.parent.create(recursive: true);
    }
    if (atomic && compatibility.supportsAtomicWrite) {
      final temp = File(
        '$normalized.vityo-tmp-${DateTime.now().microsecondsSinceEpoch}',
      );
      try {
        await temp.writeAsBytes(contents);
        await _renameFileWithRetry(temp, normalized);
      } finally {
        if (await temp.exists()) {
          await temp.delete();
        }
      }
      return;
    }
    await target.writeAsBytes(contents);
  }

  VityoFileSystemEntityType _mapEntityType(FileSystemEntityType type) {
    return switch (type) {
      FileSystemEntityType.file => VityoFileSystemEntityType.file,
      FileSystemEntityType.directory => VityoFileSystemEntityType.directory,
      FileSystemEntityType.link => VityoFileSystemEntityType.link,
      FileSystemEntityType.pipe ||
      FileSystemEntityType.unixDomainSock => VityoFileSystemEntityType.other,
      FileSystemEntityType.notFound => VityoFileSystemEntityType.notFound,
      _ => VityoFileSystemEntityType.other,
    };
  }

  FileSystemManagerEventKind _mapEventKind(FileSystemEvent event) {
    return switch (event.type) {
      FileSystemEvent.create => FileSystemManagerEventKind.created,
      FileSystemEvent.modify => FileSystemManagerEventKind.modified,
      FileSystemEvent.delete => FileSystemManagerEventKind.deleted,
      FileSystemEvent.move => FileSystemManagerEventKind.moved,
      _ => FileSystemManagerEventKind.unknown,
    };
  }

  Future<void> _prepareCopyOrMoveTarget(
    String target, {
    required bool overwrite,
  }) async {
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    if (targetType == FileSystemEntityType.notFound) {
      return;
    }
    if (!overwrite) {
      throw FileSystemException(
        'Target file system entity already exists.',
        target,
        const OSError('File exists', 17),
      );
    }
    switch (targetType) {
      case FileSystemEntityType.directory:
        await Directory(target).delete(recursive: true);
        return;
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        await File(target).delete();
        return;
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
      case FileSystemEntityType.notFound:
        return;
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: false,
      followLinks: false,
    )) {
      final childTarget = joinPath(<String>[
        target.path,
        entity.path.split(Platform.pathSeparator).last,
      ]);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _copyDirectory(Directory(entity.path), Directory(childTarget));
      } else if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        await File(entity.path).copy(childTarget);
      }
    }
  }
}

Future<File> _renameFileWithRetry(File source, String target) async {
  for (var attempt = 0; attempt < 6; attempt += 1) {
    try {
      return await source.rename(target);
    } on FileSystemException {
      if (!Platform.isWindows || attempt == 5) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 25 * (1 << attempt)));
    }
  }
  return source.rename(target);
}

Future<T> _readFileWithRetry<T>(
  File file,
  Future<T> Function(File file) read,
) async {
  for (var attempt = 0; attempt < 6; attempt += 1) {
    try {
      return await read(file);
    } on FileSystemException catch (error) {
      if (!_isTransientWindowsFileLock(error) || attempt == 5) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 25 * (1 << attempt)));
    }
  }
  return read(file);
}

bool _isTransientWindowsFileLock(FileSystemException error) {
  if (!Platform.isWindows) {
    return false;
  }
  return switch (error.osError?.errorCode) {
    32 || 33 => true,
    _ => false,
  };
}

FileSystemFailureKind? _localFileSystemFailureKind(Object error) {
  if (error is! FileSystemException) {
    return null;
  }
  return switch (error.osError?.errorCode) {
    2 => FileSystemFailureKind.notFound,
    13 => FileSystemFailureKind.permissionDenied,
    17 => FileSystemFailureKind.conflict,
    28 => FileSystemFailureKind.resourceLimitReached,
    30 => FileSystemFailureKind.readOnlyTarget,
    _ => null,
  };
}
