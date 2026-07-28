import 'dart:async';

import '../view_ide/environment/system_compatibility/file_system/file_system_adapter.dart';
import '../view_ide/environment/system_compatibility/file_system/file_system_facts.dart';
import '../view_ide/environment/system_compatibility/file_system/file_system_manager.dart';
import 'file_system_operation_result.dart';

/// Abstract file system provider contract.
///
/// Implementations back different URI schemes:
///   - `file://`        — local OS file system
///   - `memory://`      — in-memory virtual file system
///   - `browser-vfs://` — browser sandbox file system
///   - `vityo-hosted://` — hosted workspace file system
abstract class FileSystemProvider {
  String get providerId;

  Set<String> get supportedSchemes;

  FileSystemFacts get facts;

  FileSystemCompatibility get compatibility;

  bool supportsScheme(String scheme) => supportedSchemes.contains(scheme);

  Future<FileSystemOperationResult<FileSystemEntitySnapshot>> stat(Uri uri);

  Future<FileSystemOperationResult<String>> readText(Uri uri);

  Future<FileSystemOperationResult<List<int>>> readBytes(Uri uri);

  Future<FileSystemOperationResult<void>> writeText(
    Uri uri,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  });

  Future<FileSystemOperationResult<void>> writeBytes(
    Uri uri,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  });

  Future<FileSystemOperationResult<List<FileSystemEntitySnapshot>>> list(
    Uri uri, {
    bool recursive = false,
  });

  Future<FileSystemOperationResult<void>> createDirectory(
    Uri uri, {
    bool recursive = true,
  });

  Future<FileSystemOperationResult<void>> delete(
    Uri uri, {
    bool recursive = false,
  });

  Future<FileSystemOperationResult<void>> copy(
    Uri source,
    Uri target, {
    bool overwrite = false,
  });

  Future<FileSystemOperationResult<void>> move(
    Uri source,
    Uri target, {
    bool overwrite = false,
  });

  Stream<FileSystemManagerEvent> watch(
    Uri uri, {
    bool recursive = false,
  });

  Future<FileSystemOperationResult<void>> refresh();
}
