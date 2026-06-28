import 'dart:async';

import '../view_ide/environment/system_compatibility/file_system/file_system_adapter.dart';
import '../view_ide/environment/system_compatibility/file_system/file_system_facts.dart';
import '../view_ide/environment/system_compatibility/file_system/file_system_manager.dart';
import 'file_system_operation_result.dart';
import 'file_system_provider.dart';

/// Browser virtual file system provider (contract skeleton).
///
/// In a browser environment, direct file system access is unavailable.
/// This provider acts as a contract placeholder for the browser sandbox VFS
/// layer that will be backed by the Origin Private File System (OPFS) or
/// IndexedDB. All mutation operations return unsupported failures to enforce
/// the read-only nature of the contract skeleton.
class BrowserVirtualFileSystemProvider implements FileSystemProvider {
  BrowserVirtualFileSystemProvider({
    String providerId = 'browser-vfs',
    FileSystemFacts? facts,
  }) : _providerId = providerId,
       _facts = facts ?? _defaultFacts();

  static FileSystemFacts _defaultFacts() {
    return FileSystemFacts(
      targetId: 'browser-vfs',
      operatingSystem: 'browser',
      distributionId: 'web',
      distributionName: 'Web Browser',
      architecture: 'wasm',
      pathStyle: FileSystemPathStyle.posix,
      pathSeparator: '/',
      providerKind: FileSystemProviderKind.browserSandbox,
      watchSupport: FileSystemWatchSupport.none,
      caseSensitive: true,
      supportsFileUri: false,
      supportsSymbolicLinks: false,
      supportsAtomicWrite: false,
      detectedAt: DateTime.now().toUtc(),
    );
  }

  final String _providerId;
  final FileSystemFacts _facts;

  final FileSystemCompatibility _compatibility = const FileSystemCompatibility(
    targetId: 'browser-vfs',
    compatibilityTarget: 'browser',
    pathStyle: FileSystemPathStyle.posix,
    pathSeparator: '/',
    caseSensitive: true,
    providerKind: FileSystemProviderKind.browserSandbox,
    watchSupport: FileSystemWatchSupport.none,
    supportsFileUri: false,
    supportsSymbolicLinks: false,
    supportsAtomicWrite: false,
  );

  @override
  String get providerId => _providerId;

  @override
  Set<String> get supportedSchemes => const <String>{'browser-vfs'};

  @override
  FileSystemFacts get facts => _facts;

  @override
  FileSystemCompatibility get compatibility => _compatibility;

  @override
  bool supportsScheme(String scheme) => supportedSchemes.contains(scheme);

  FileSystemOperationFailure _unsupported(String operation, Uri uri) {
    return FileSystemOperationFailure(
      kind: FileSystemFailureKind.unsupportedProvider,
      operation: operation,
      target: uri.toString(),
      sourceManager: providerId,
      message:
          'Browser virtual file system does not support $operation yet. '
          'The contract skeleton is read-only.',
    );
  }

  FileSystemOperationFailure _readOnly(Uri uri) {
    return FileSystemOperationFailure(
      kind: FileSystemFailureKind.readOnlyTarget,
      operation: 'write',
      target: uri.toString(),
      sourceManager: providerId,
      message:
          'Browser virtual file system is read-only in the contract skeleton.',
    );
  }

  @override
  Future<FileSystemOperationResult<FileSystemEntitySnapshot>> stat(Uri uri) async {
    return FileSystemOperationSuccess(
      FileSystemEntitySnapshot(
        path: uri.path,
        normalizedPath: uri.path,
        type: VityoFileSystemEntityType.notFound,
      ),
    );
  }

  @override
  Future<FileSystemOperationResult<String>> readText(Uri uri) async {
    return FileSystemOperationFailureResult(
      _unsupported('readText', uri),
    );
  }

  @override
  Future<FileSystemOperationResult<List<int>>> readBytes(Uri uri) async {
    return FileSystemOperationFailureResult(
      _unsupported('readBytes', uri),
    );
  }

  @override
  Future<FileSystemOperationResult<void>> writeText(
    Uri uri,
    String contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    return FileSystemOperationFailureResult(_readOnly(uri));
  }

  @override
  Future<FileSystemOperationResult<void>> writeBytes(
    Uri uri,
    List<int> contents, {
    bool createParents = true,
    bool atomic = true,
  }) async {
    return FileSystemOperationFailureResult(_readOnly(uri));
  }

  @override
  Future<FileSystemOperationResult<List<FileSystemEntitySnapshot>>> list(
    Uri uri, {
    bool recursive = false,
  }) async {
    return const FileSystemOperationSuccess(<FileSystemEntitySnapshot>[]);
  }

  @override
  Future<FileSystemOperationResult<void>> createDirectory(
    Uri uri, {
    bool recursive = true,
  }) async {
    return FileSystemOperationFailureResult(_readOnly(uri));
  }

  @override
  Future<FileSystemOperationResult<void>> delete(
    Uri uri, {
    bool recursive = false,
  }) async {
    return FileSystemOperationFailureResult(_readOnly(uri));
  }

  @override
  Future<FileSystemOperationResult<void>> copy(
    Uri source,
    Uri target, {
    bool overwrite = false,
  }) async {
    return FileSystemOperationFailureResult(_readOnly(source));
  }

  @override
  Future<FileSystemOperationResult<void>> move(
    Uri source,
    Uri target, {
    bool overwrite = false,
  }) async {
    return FileSystemOperationFailureResult(_readOnly(source));
  }

  @override
  Stream<FileSystemManagerEvent> watch(
    Uri uri, {
    bool recursive = false,
  }) {
    return const Stream<FileSystemManagerEvent>.empty();
  }

  @override
  Future<FileSystemOperationResult<void>> refresh() async {
    return const FileSystemOperationSuccess<void>(null);
  }
}
