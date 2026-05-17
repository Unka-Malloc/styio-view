import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../editor/document_state.dart';
import '../editor/editor_controller.dart';
import '../environment/environment.dart';
import 'workspace_document_store_types.dart';

Future<WorkspaceDocumentStore> createPlatformWorkspaceDocumentStore() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final rootDirectory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}vityo_workspace',
  );
  return FileSystemWorkspaceDocumentStore(
    rootDirectory,
    fileSystemManager: await createPlatformFileSystemManager(),
  );
}

class FileSystemWorkspaceDocumentStore
    implements WatchableWorkspaceDocumentStore {
  FileSystemWorkspaceDocumentStore(
    this.rootDirectory, {
    FileSystemManager? fileSystemManager,
  }) : fileSystemManager = fileSystemManager ??
            LocalFileSystemManager(
              facts: FileSystemFacts(
                targetId: 'local',
                operatingSystem: Platform.operatingSystem,
                distributionId: 'unknown',
                distributionName: 'Unknown',
                architecture: 'unknown',
                pathStyle: Platform.isWindows
                    ? FileSystemPathStyle.windows
                    : FileSystemPathStyle.posix,
                pathSeparator: Platform.pathSeparator,
                providerKind: FileSystemProviderKind.local,
                watchSupport: Platform.isLinux
                    ? FileSystemWatchSupport.directory
                    : FileSystemWatchSupport.unknown,
                caseSensitive: Platform.isLinux || Platform.isAndroid,
                supportsFileUri: true,
                supportsSymbolicLinks: Platform.isLinux || Platform.isMacOS,
                supportsAtomicWrite: true,
                detectedAt: DateTime.now().toUtc(),
              ),
            );

  final Directory rootDirectory;
  final FileSystemManager fileSystemManager;

  @override
  Future<DocumentState> loadDocument(String path) async {
    await fileSystemManager.createDirectory(rootDirectory.path, recursive: true);
    if (fileSystemManager.compatibility.isAbsolutePath(path)) {
      if (await fileSystemManager.exists(path)) {
        return DocumentState(
          documentId: path,
          text: await fileSystemManager.readText(path),
          revision: 0,
        );
      }
      return EditorSessionController.seedDocumentForPath(path);
    }
    final sourcePath = _sourcePath(path);
    final metadataPath = _metadataPath(path);

    if (!await fileSystemManager.exists(sourcePath)) {
      return EditorSessionController.seedDocumentForPath(path);
    }

    final text = await fileSystemManager.readText(sourcePath);
    var revision = 0;

    if (await fileSystemManager.exists(metadataPath)) {
      final metadata = jsonDecode(await fileSystemManager.readText(metadataPath));
      if (metadata is Map<String, dynamic>) {
        revision = metadata['revision'] is int
            ? metadata['revision'] as int
            : 0;
      }
    }

    return DocumentState(documentId: path, text: text, revision: revision);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    await fileSystemManager.createDirectory(rootDirectory.path, recursive: true);
    if (fileSystemManager.compatibility.isAbsolutePath(document.documentId)) {
      await fileSystemManager.writeText(document.documentId, document.text);
      return;
    }
    final sourcePath = _sourcePath(document.documentId);
    final metadataPath = _metadataPath(document.documentId);

    await fileSystemManager.writeText(sourcePath, document.text);
    await fileSystemManager.writeText(
      metadataPath,
      jsonEncode(<String, Object>{'revision': document.revision}),
    );
  }

  @override
  String? filePathForDocumentId(String documentId) {
    if (fileSystemManager.compatibility.isAbsolutePath(documentId)) {
      return documentId;
    }
    return _sourcePath(documentId);
  }

  @override
  Stream<DocumentState> watchDocument(String documentId) async* {
    final filePath = filePathForDocumentId(documentId);
    if (filePath == null) {
      return;
    }
    final absoluteDocument =
        fileSystemManager.compatibility.isAbsolutePath(documentId);
    final sourcePath = fileSystemManager.normalizePath(filePath);
    final metadataPath = absoluteDocument
        ? null
        : fileSystemManager.normalizePath(_metadataPath(documentId));
    final watchPath = absoluteDocument ? sourcePath : File(sourcePath).parent.path;

    await for (final event in fileSystemManager.watch(watchPath)) {
      final eventPath = fileSystemManager.normalizePath(event.normalizedPath);
      if (!_isDocumentWatchEvent(
        eventPath,
        sourcePath: sourcePath,
        metadataPath: metadataPath,
      )) {
        continue;
      }
      switch (event.kind) {
        case FileSystemManagerEventKind.created:
        case FileSystemManagerEventKind.modified:
        case FileSystemManagerEventKind.moved:
        case FileSystemManagerEventKind.metadataChanged:
          yield await loadDocument(documentId);
          break;
        case FileSystemManagerEventKind.deleted:
        case FileSystemManagerEventKind.unknown:
          break;
      }
    }
  }

  String _sourcePath(String path) {
    return _resolvePath(path);
  }

  String _metadataPath(String path) {
    return '${_resolvePath(path)}.meta.json';
  }

  String _resolvePath(String documentId) {
    final segments = documentId
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .map(Uri.encodeComponent);
    return fileSystemManager.joinPath(<String>[rootDirectory.path, ...segments]);
  }

  bool _isDocumentWatchEvent(
    String eventPath, {
    required String sourcePath,
    required String? metadataPath,
  }) {
    return eventPath == sourcePath ||
        eventPath.startsWith('$sourcePath.vityo-tmp-') ||
        (metadataPath != null &&
            (eventPath == metadataPath ||
                eventPath.startsWith('$metadataPath.vityo-tmp-')));
  }
}
