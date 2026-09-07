import 'dart:async';
import 'dart:io';

import 'package:vityo_app/src/view_ide/environment/environment.dart';

/// Test-only host filesystem fixture.
///
/// Production desktop code must use [VityodFileSystemManager]. Keeping host
/// I/O in this test library lets unit tests exercise stores without restoring
/// a direct Dart filesystem implementation to the application import graph.
class TestFileSystemManager implements FileSystemManager {
  TestFileSystemManager({required this.facts})
    : compatibility = FileSystemAdapter(facts).adapt();

  factory TestFileSystemManager.linuxDebianArm() =>
      TestFileSystemManager(facts: FileSystemFacts.linuxDebianArm());

  factory TestFileSystemManager.windowsX64() =>
      TestFileSystemManager(facts: FileSystemFacts.windowsX64());

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
  Future<void> createDirectory(String path, {bool recursive = true}) =>
      Directory(normalizePath(path)).create(recursive: recursive);

  @override
  Future<void> delete(String path, {bool recursive = false}) async {
    final target = normalizePath(path);
    switch (await FileSystemEntity.type(target, followLinks: false)) {
      case FileSystemEntityType.directory:
        await Directory(target).delete(recursive: recursive);
        return;
      case FileSystemEntityType.file:
      case FileSystemEntityType.link:
        await File(target).delete(recursive: recursive);
        return;
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
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
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Source does not exist.', source);
    }
    await _prepareTarget(target, overwrite: overwrite);
    switch (type) {
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
        throw FileSystemException('Unsupported entity type.', source);
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
    final type = await FileSystemEntity.type(source, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Source does not exist.', source);
    }
    await _prepareTarget(target, overwrite: overwrite);
    switch (type) {
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
        throw FileSystemException('Unsupported entity type.', source);
      case FileSystemEntityType.notFound:
        return;
    }
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
    final target = normalizePath(path);
    if (Platform.isWindows) return File(target).exists();
    final value = await FileStat.stat(target);
    return value.type == FileSystemEntityType.file && (value.mode & 0x40) != 0;
  }

  @override
  Future<void> setExecutable(String path, {bool executable = true}) async {
    final target = normalizePath(path);
    if (!await File(target).exists()) {
      throw FileSystemException('Executable does not exist.', target);
    }
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', <String>[
      executable ? 'u+x' : 'u-x',
      target,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('Unable to change executable mode.', target);
    }
  }

  @override
  Future<List<FileSystemEntitySnapshot>> list(
    String path, {
    bool recursive = false,
  }) async {
    final root = Directory(normalizePath(path));
    if (!await root.exists()) return const <FileSystemEntitySnapshot>[];
    final result = <FileSystemEntitySnapshot>[];
    await for (final entity in root.list(
      recursive: recursive,
      followLinks: false,
    )) {
      result.add(await stat(entity.path));
    }
    return result;
  }

  @override
  Future<String> readText(String path) =>
      File(normalizePath(path)).readAsString();

  @override
  Future<List<int>> readBytes(String path) =>
      File(normalizePath(path)).readAsBytes();

  @override
  Future<FileSystemEntitySnapshot> stat(String path) async {
    final target = normalizePath(path);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return FileSystemEntitySnapshot(
        path: path,
        normalizedPath: target,
        type: VityoFileSystemEntityType.notFound,
      );
    }
    final value = await FileStat.stat(target);
    return FileSystemEntitySnapshot(
      path: path,
      normalizedPath: target,
      type: _entityType(type),
      size: value.size,
      modifiedAt: value.modified,
    );
  }

  @override
  Stream<FileSystemManagerEvent> watch(
    String path, {
    bool recursive = false,
  }) async* {
    final target = normalizePath(path);
    final snapshot = await stat(target);
    final root = snapshot.isDirectory ? target : File(target).parent.path;
    await for (final event in Directory(
      root,
    ).watch(recursive: recursive && compatibility.supportsRecursiveWatch)) {
      yield FileSystemManagerEvent(
        kind: _eventKind(event.type),
        path: event.path,
        normalizedPath: normalizePath(event.path),
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
  }) =>
      const FileSystemFailureClassifier(
        sourceManager: 'TestFileSystemManager',
        platformFailureKindResolver: _failureKind,
      ).classify(
        error,
        operation: operation,
        target: target,
        recoveryHint: recoveryHint,
      );

  @override
  Future<void> writeText(
    String path,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    await _write(
      path,
      createParents: createParents,
      atomic: atomic,
      write: (file) => file.writeAsString(contents),
    );
  }

  @override
  Future<void> writeBytes(
    String path,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    await _write(
      path,
      createParents: createParents,
      atomic: atomic,
      write: (file) => file.writeAsBytes(contents),
    );
  }

  Future<void> _write(
    String path, {
    required bool createParents,
    required bool atomic,
    required Future<File> Function(File file) write,
  }) async {
    final target = File(normalizePath(path));
    if (createParents) await target.parent.create(recursive: true);
    if (!atomic) {
      await write(target);
      return;
    }
    final temporary = File(
      '${target.path}.test-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await write(temporary);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _prepareTarget(String target, {required bool overwrite}) async {
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (!overwrite) throw FileSystemException('Target exists.', target);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else {
      await File(target).delete();
    }
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final name = entity.path.split(Platform.pathSeparator).last;
      final child = joinPath(<String>[target.path, name]);
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _copyDirectory(Directory(entity.path), Directory(child));
      } else if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.link) {
        await File(entity.path).copy(child);
      }
    }
  }
}

VityoFileSystemEntityType _entityType(FileSystemEntityType type) =>
    switch (type) {
      FileSystemEntityType.file => VityoFileSystemEntityType.file,
      FileSystemEntityType.directory => VityoFileSystemEntityType.directory,
      FileSystemEntityType.link => VityoFileSystemEntityType.link,
      FileSystemEntityType.notFound => VityoFileSystemEntityType.notFound,
      _ => VityoFileSystemEntityType.other,
    };

FileSystemManagerEventKind _eventKind(int type) => switch (type) {
  FileSystemEvent.create => FileSystemManagerEventKind.created,
  FileSystemEvent.modify => FileSystemManagerEventKind.modified,
  FileSystemEvent.delete => FileSystemManagerEventKind.deleted,
  FileSystemEvent.move => FileSystemManagerEventKind.moved,
  _ => FileSystemManagerEventKind.unknown,
};

FileSystemFailureKind? _failureKind(Object error) {
  if (error is! FileSystemException) return null;
  return switch (error.osError?.errorCode) {
    2 => FileSystemFailureKind.notFound,
    13 => FileSystemFailureKind.permissionDenied,
    17 => FileSystemFailureKind.conflict,
    28 => FileSystemFailureKind.resourceLimitReached,
    30 => FileSystemFailureKind.readOnlyTarget,
    _ => null,
  };
}
