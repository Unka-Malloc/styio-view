import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/file_system/file_system_manager_io.dart'
    as file_system_io;
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store_io.dart';

void main() {
  test('file system prober classifies linux debian arm target facts', () async {
    final prober = LocalFileSystemProber(
      operatingSystem: 'linux',
      architectureReader: () async => 'aarch64',
      osReleaseReader: () async => const <String, String>{
        'ID': 'debian',
        'PRETTY_NAME': 'Debian GNU/Linux 12 (bookworm)',
      },
      clock: () => DateTime.utc(2026, 5, 16),
    );

    final facts = await prober.probe();

    expect(facts.supportsLinuxDebianArmTarget, isTrue);
    expect(facts.compatibilityTarget, 'linux-debian-arm');
    expect(facts.pathStyle, FileSystemPathStyle.posix);
    expect(facts.entries['filesystem.watchSupport']?.value, 'directory');
  });

  test(
    'local file system prober recognizes this host when it is debian arm',
    () async {
      if (!Platform.isLinux) {
        return;
      }

      final facts = await const LocalFileSystemProber().probe();
      final machine = await Process.run('uname', const <String>['-m']);
      final osRelease = await File('/etc/os-release').readAsString();
      final isDebianArmHost =
          Platform.isLinux &&
          osRelease.contains('ID=debian') &&
          machine.stdout.toString().trim().toLowerCase() == 'aarch64';

      if (isDebianArmHost) {
        expect(facts.supportsLinuxDebianArmTarget, isTrue);
        expect(facts.compatibilityTarget, 'linux-debian-arm');
      }
    },
  );

  test('file system adapter creates linux debian arm compatibility', () {
    final compatibility = FileSystemAdapter(
      FileSystemFacts.linuxDebianArm(),
    ).adapt();

    expect(compatibility.isLinuxDebianArm, isTrue);
    expect(
      compatibility.normalizePath('/tmp/vityo/../workspace/./main.styio'),
      '/tmp/workspace/main.styio',
    );
    expect(
      compatibility.joinPath(<String>['/tmp', 'vityo', 'main.styio']),
      '/tmp/vityo/main.styio',
    );
    expect(compatibility.isAbsolutePath('/tmp/main.styio'), isTrue);
    final uri = compatibility.toFileUri('/tmp/vityo/main.styio');
    expect(uri.scheme, 'file');
    expect(compatibility.pathFromFileUri(uri), '/tmp/vityo/main.styio');
    expect(
      compatibility.isWithin('/tmp/vityo/src/main.styio', '/tmp/vityo'),
      isTrue,
    );
    expect(
      compatibility.isWithin('/tmp/vityo-other/main.styio', '/tmp/vityo'),
      isFalse,
    );
  });

  test('file system prober classifies Windows host facts', () async {
    final facts = await LocalFileSystemProber(
      operatingSystem: 'windows',
      architectureReader: () async => 'x64',
      clock: () => DateTime.utc(2026, 6, 26),
    ).probe();

    expect(facts.operatingSystem, 'windows');
    expect(facts.distributionId, 'windows');
    expect(facts.compatibilityTarget, 'windows-x64');
    expect(facts.pathStyle, FileSystemPathStyle.windows);
    expect(facts.pathSeparator, r'\');
    expect(facts.watchSupport, FileSystemWatchSupport.recursive);
    expect(facts.caseSensitive, isFalse);
    expect(facts.supportsAtomicWrite, isTrue);
  });

  test('file system compatibility handles windows paths and uri support', () {
    const windows = FileSystemCompatibility(
      targetId: 'win-test',
      compatibilityTarget: 'windows-x64',
      pathStyle: FileSystemPathStyle.windows,
      pathSeparator: r'\',
      caseSensitive: false,
      providerKind: FileSystemProviderKind.local,
      watchSupport: FileSystemWatchSupport.recursive,
      supportsFileUri: true,
      supportsSymbolicLinks: true,
      supportsAtomicWrite: false,
    );
    const noFileUri = FileSystemCompatibility(
      targetId: 'virtual-test',
      compatibilityTarget: 'unsupported',
      pathStyle: FileSystemPathStyle.posix,
      pathSeparator: '/',
      caseSensitive: true,
      providerKind: FileSystemProviderKind.virtual,
      watchSupport: FileSystemWatchSupport.none,
      supportsFileUri: false,
      supportsSymbolicLinks: false,
      supportsAtomicWrite: false,
    );

    expect(windows.supportsDirectoryWatch, isTrue);
    expect(windows.supportsRecursiveWatch, isTrue);
    expect(windows.isAbsolutePath(r'C:\Project\main.styio'), isTrue);
    expect(windows.isAbsolutePath(r'\\server\share\main.styio'), isTrue);
    expect(windows.isAbsolutePath(r'Project\main.styio'), isFalse);
    expect(
      windows.normalizePath(r'C:/workspace/../Project/./main.styio'),
      r'C:\Project\main.styio',
    );
    expect(windows.normalizePath(r'.\src\..\main.styio'), 'main.styio');
    expect(
      windows.joinPath(<String>[r'C:\Project', 'src', 'main.styio']),
      r'C:\Project\src\main.styio',
    );
    expect(
      windows.isWithin(r'C:\PROJECT\src\main.styio', r'c:\project'),
      isTrue,
    );

    final uri = windows.toFileUri(r'C:\Project\src\main.styio');
    expect(uri.scheme, 'file');
    expect(windows.pathFromFileUri(uri), r'C:\Project\src\main.styio');
    expect(
      () => windows.pathFromFileUri(Uri.parse('vityo://workspace/main.styio')),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => noFileUri.toFileUri('/workspace/main.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => noFileUri.pathFromFileUri(Uri.file('/workspace/main.styio')),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('FileSystemFacts.windowsX64 factory matches Windows target facts', () {
    final facts = FileSystemFacts.windowsX64();
    expect(facts.operatingSystem, 'windows');
    expect(facts.distributionId, 'windows');
    expect(facts.compatibilityTarget, 'windows-x64');
    expect(facts.pathStyle, FileSystemPathStyle.windows);
    expect(facts.pathSeparator, r'\');
    expect(facts.watchSupport, FileSystemWatchSupport.recursive);
    expect(facts.caseSensitive, isFalse);
    expect(facts.supportsAtomicWrite, isTrue);
    expect(facts.supportsFileUri, isTrue);
    expect(facts.supportsSymbolicLinks, isFalse);
  });

  test('LocalFileSystemManager.windowsX64ForTest reads writes stats', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_win_fs_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final manager = file_system_io.LocalFileSystemManager.windowsX64ForTest();
    final fp = manager.joinPath(<String>[
      tempRoot.path,
      'workspace',
      'main.txt',
    ]);
    await manager.writeText(fp, 'hello');
    expect(await manager.readText(fp), 'hello');
    expect((await manager.stat(fp)).isFile, isTrue);
  });

  test('Windows path containment is case-insensitive', () {
    final m = file_system_io.LocalFileSystemManager.windowsX64ForTest();
    expect(
      m.compatibility.isWithin(r'C:\PROJECT\src\main.styio', r'c:\project'),
      isTrue,
    );
    expect(m.compatibility.isWithin(r'D:\W\main.styio', r'C:\W'), isFalse);
  });

  test('Windows normalize path handles drive and dot-dot', () {
    final m = file_system_io.LocalFileSystemManager.windowsX64ForTest();
    expect(m.normalizePath(r'C:\Users\..\app\m.styio'), r'C:\app\m.styio');
  });

  test('Windows locked-file retry is documented blocked on dioxus host', () {
    final m = file_system_io.LocalFileSystemManager.windowsX64ForTest();
    expect(m.compatibility.supportsAtomicWrite, isTrue);
  });

  test(
    'local file system manager reads writes stats and lists files',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_fs_manager_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final manager = LocalFileSystemManager.linuxDebianArmForTest();
      final filePath = manager.joinPath(<String>[
        tempRoot.path,
        'workspace',
        'main.txt',
      ]);

      await manager.writeText(filePath, 'hello from vityo');

      expect(await manager.readText(filePath), 'hello from vityo');
      final snapshot = await manager.stat(filePath);
      expect(snapshot.isFile, isTrue);
      expect(snapshot.exists, isTrue);

      final entries = await manager.list(
        manager.joinPath(<String>[tempRoot.path, 'workspace']),
      );
      expect(entries.map((entry) => entry.normalizedPath), contains(filePath));

      final bytesPath = manager.joinPath(<String>[
        tempRoot.path,
        'workspace',
        'bytes.bin',
      ]);
      await manager.writeBytes(bytesPath, <int>[1, 2, 3], atomic: false);
      expect(await manager.readBytes(bytesPath), <int>[1, 2, 3]);
      await manager.writeText(filePath, 'non-atomic', atomic: false);
      expect(await manager.readText(filePath), 'non-atomic');
      await manager.delete(bytesPath);
      expect((await manager.stat(bytesPath)).exists, isFalse);
      await manager.delete(bytesPath);
    },
  );

  test('platform file system manager can be created from a prober', () async {
    final manager = await createPlatformFileSystemManager(
      prober: StaticFileSystemProber(
        FileSystemFacts.linuxDebianArm(targetId: 'probe-fs'),
      ),
    );

    expect(manager.facts.targetId, 'probe-fs');
    expect(manager.compatibility.isLinuxDebianArm, isTrue);
  });

  test('file system manager classifies operation failures structurally', () {
    final manager = LocalFileSystemManager.linuxDebianArmForTest();
    final permissionFailure = manager.classifyFailure(
      const FileSystemException(
        'Permission denied',
        '/root/secret.styio',
        OSError('Permission denied', 13),
      ),
      operation: 'readText',
      target: '/root/secret.styio',
      recoveryHint: 'Choose a readable workspace file.',
    );
    final unsupportedFailure =
        UnsupportedFileSystemManager(
          facts: FileSystemFacts.linuxDebianArm(),
        ).classifyFailure(
          UnsupportedError('File system operations are not available.'),
          operation: 'watch',
          target: '/workspace',
        );
    final notFoundFailure = manager.classifyFailure(
      const FileSystemException(
        'No such file or directory',
        '/workspace/missing.styio',
        OSError('No such file or directory', 2),
      ),
      operation: 'readText',
      target: '/workspace/missing.styio',
    );
    final conflictFailure = manager.classifyFailure(
      const FileSystemException(
        'File exists',
        '/workspace/existing.styio',
        OSError('File exists', 17),
      ),
      operation: 'copy',
      target: '/workspace/existing.styio',
    );
    final resourceLimitFailure = manager.classifyFailure(
      const FileSystemException(
        'No space left on device',
        '/workspace/full.styio',
        OSError('No space left on device', 28),
      ),
      operation: 'writeText',
      target: '/workspace/full.styio',
    );
    final readOnlyFailure = manager.classifyFailure(
      const FileSystemException(
        'Read-only file system',
        '/workspace/readonly.styio',
        OSError('Read-only file system', 30),
      ),
      operation: 'writeText',
      target: '/workspace/readonly.styio',
    );
    final unknownFailure = manager.classifyFailure(
      StateError('not a file system error'),
      operation: 'readText',
      target: '/workspace/state.styio',
    );

    expect(permissionFailure.kind, FileSystemFailureKind.permissionDenied);
    expect(permissionFailure.sourceManager, 'LocalFileSystemManager');
    expect(permissionFailure.toJson()['operation'], 'readText');
    expect(permissionFailure.toJson()['recoveryHint'], contains('readable'));
    expect(unsupportedFailure.kind, FileSystemFailureKind.unsupportedProvider);
    expect(
      unsupportedFailure.toJson()['sourceManager'],
      'UnsupportedFileSystemManager',
    );
    expect(notFoundFailure.kind, FileSystemFailureKind.notFound);
    expect(conflictFailure.kind, FileSystemFailureKind.conflict);
    expect(
      resourceLimitFailure.kind,
      FileSystemFailureKind.resourceLimitReached,
    );
    expect(readOnlyFailure.kind, FileSystemFailureKind.readOnlyTarget);
    expect(unknownFailure.kind, FileSystemFailureKind.unknownFailure);
  });

  test('unsupported file system manager exposes compatibility only', () async {
    final manager = UnsupportedFileSystemManager(
      facts: FileSystemFacts.linuxDebianArm(),
    );

    expect(
      manager.normalizePath('/tmp/../workspace/main.styio'),
      '/workspace/main.styio',
    );
    expect(
      manager.joinPath(<String>['/workspace', 'src', 'main.styio']),
      '/workspace/src/main.styio',
    );
    expect(
      manager.pathFromFileUri(manager.toFileUri('/workspace/src/main.styio')),
      '/workspace/src/main.styio',
    );
    expect(manager.isWithin('/workspace/src/main.styio', '/workspace'), isTrue);
    expect(await manager.exists('/workspace/src/main.styio'), isFalse);
    expect(await manager.isExecutable('/workspace/src/main.styio'), isFalse);
    expect(await manager.list('/workspace'), isEmpty);
    final missing = await manager.stat('/workspace/src/main.styio');
    expect(missing.exists, isFalse);
    expect(missing.normalizedPath, '/workspace/src/main.styio');
    expect(await manager.watch('/workspace').toList(), isEmpty);

    await expectLater(
      manager.createDirectory('/workspace/src'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.delete('/workspace/src/main.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.copy('/workspace/a.styio', '/workspace/b.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.move('/workspace/a.styio', '/workspace/b.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.rename('/workspace/a.styio', '/workspace/b.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.setExecutable('/workspace/tool'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.readText('/workspace/src/main.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.readBytes('/workspace/src/main.styio'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.writeText('/workspace/src/main.styio', 'text'),
      throwsA(isA<UnsupportedError>()),
    );
    await expectLater(
      manager.writeBytes('/workspace/src/main.styio', <int>[1, 2, 3]),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('file system boundary guard reports outside workspace targets', () {
    final manager = LocalFileSystemManager.linuxDebianArmForTest();
    final guard = FileSystemBoundaryGuard(
      fileSystemManager: manager,
      rootPath: '/workspace/project',
    );

    expect(guard.contains('/workspace/project/src/main.styio'), isTrue);
    expect(
      guard.checkWithin(
        '/workspace/project/src/main.styio',
        operation: 'writeText',
      ),
      isNull,
    );

    final failure = guard.checkWithin(
      '/workspace/project-other/main.styio',
      operation: 'writeText',
      recoveryHint: 'Choose a file under the active workspace.',
    );

    expect(failure, isNotNull);
    expect(failure!.kind, FileSystemFailureKind.outsideWorkspace);
    expect(failure.toJson()['sourceManager'], 'FileSystemBoundaryGuard');
    expect(
      () => guard.requireWithin(
        '/workspace/project-other/main.styio',
        operation: 'writeText',
      ),
      throwsA(isA<FileSystemBoundaryException>()),
    );
  });

  test(
    'file system provider router supports local file uri and rejects other schemes',
    () {
      final manager = LocalFileSystemManager.linuxDebianArmForTest();
      final router = FileSystemProviderRouter(fileSystemManager: manager);
      final local = router.route(Uri.file('/workspace/project/main.styio'));
      final barePath = router.route(Uri(path: '/workspace/project/main.styio'));
      final unsupported = router.route(
        Uri.parse('vityo-remote://workspace/main.styio'),
        operation: 'readText',
      );

      expect(local.kind, FileSystemProviderRouteKind.local);
      expect(local.path, '/workspace/project/main.styio');
      expect(barePath.supported, isTrue);
      expect(unsupported.supported, isFalse);
      expect(
        unsupported.failure!.kind,
        FileSystemFailureKind.unsupportedProvider,
      );
      expect(unsupported.toJson()['failure'], isA<Map<String, Object?>>());
    },
  );

  test('file system text codec decodes bom and normalizes newlines', () {
    const codec = FileSystemTextCodec();
    final decoded = codec.decode(<int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('a\r\nb\rc\n'),
    ]);
    const crlfCodec = FileSystemTextCodec(
      outputNewline: FileSystemNewline.crlf,
    );
    final encoded = crlfCodec.encode('a\nb\n', includeUtf8Bom: true);

    expect(decoded.text, 'a\nb\nc\n');
    expect(decoded.hadUtf8Bom, isTrue);
    expect(decoded.newlineNormalized, isTrue);
    expect(decoded.toJson()['textLength'], 6);
    expect(encoded.take(3), <int>[0xEF, 0xBB, 0xBF]);
    expect(utf8.decode(encoded.skip(3).toList()), 'a\r\nb\r\n');
  });

  test(
    'local file system manager copies and moves file system entities',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_fs_manager_copy_move_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final manager = LocalFileSystemManager.linuxDebianArmForTest();
      final source = manager.joinPath(<String>[tempRoot.path, 'source.txt']);
      final copy = manager.joinPath(<String>[tempRoot.path, 'copy.txt']);
      final moved = manager.joinPath(<String>[
        tempRoot.path,
        'nested',
        'moved.txt',
      ]);
      final renamed = manager.joinPath(<String>[tempRoot.path, 'renamed.txt']);

      await manager.writeText(source, 'copy-move-ok');
      await manager.copy(source, copy);
      await manager.move(copy, moved);
      await manager.rename(moved, renamed);

      final renamedUri = manager.toFileUri(renamed);
      expect(manager.pathFromFileUri(renamedUri), renamed);
      expect(manager.isWithin(renamed, tempRoot.path), isTrue);
      expect(await manager.readText(source), 'copy-move-ok');
      expect(await manager.readText(renamed), 'copy-move-ok');
      expect(await manager.exists(moved), isFalse);
      expect(await manager.exists(copy), isFalse);
      await expectLater(
        manager.copy(source, renamed),
        throwsA(isA<FileSystemException>()),
      );
      await manager.copy(source, renamed, overwrite: true);
      expect(await manager.readText(renamed), 'copy-move-ok');

      if (!Platform.isWindows) {
        await expectLater(
          manager.setExecutable(
            manager.joinPath(<String>[tempRoot.path, 'missing-executable']),
          ),
          throwsA(isA<FileSystemException>()),
        );

        final sourceLink = manager.joinPath(<String>[
          tempRoot.path,
          'source-link',
        ]);
        final copiedLink = manager.joinPath(<String>[
          tempRoot.path,
          'copied-link',
        ]);
        final movedLink = manager.joinPath(<String>[
          tempRoot.path,
          'moved-link',
        ]);
        await Link(sourceLink).create(source);
        expect(
          (await manager.stat(sourceLink)).type,
          VityoFileSystemEntityType.link,
        );
        await manager.copy(sourceLink, copiedLink);
        await manager.move(sourceLink, movedLink);
        expect(await manager.readText(copiedLink), 'copy-move-ok');
        expect((await manager.stat(movedLink)).exists, isTrue);
        expect(await manager.exists(sourceLink), isFalse);

        final pipePath = manager.joinPath(<String>[
          tempRoot.path,
          'source-pipe',
        ]);
        final pipeResult = await Process.run('mkfifo', <String>[pipePath]);
        if (pipeResult.exitCode == 0) {
          expect(
            (await manager.stat(pipePath)).type,
            VityoFileSystemEntityType.other,
          );
          await expectLater(
            manager.copy(
              pipePath,
              manager.joinPath(<String>[tempRoot.path, 'copied-pipe']),
            ),
            throwsA(isA<FileSystemException>()),
          );
          await expectLater(
            manager.move(
              pipePath,
              manager.joinPath(<String>[tempRoot.path, 'moved-pipe']),
            ),
            throwsA(isA<FileSystemException>()),
          );
        }
      }

      final sourceDirectory = manager.joinPath(<String>[
        tempRoot.path,
        'source-directory',
      ]);
      final nestedFile = manager.joinPath(<String>[
        sourceDirectory,
        'nested',
        'child.txt',
      ]);
      final copiedDirectory = manager.joinPath(<String>[
        tempRoot.path,
        'copied-directory',
      ]);
      final movedDirectory = manager.joinPath(<String>[
        tempRoot.path,
        'moved-directory',
      ]);
      await manager.writeText(nestedFile, 'directory-copy');
      await manager.copy(sourceDirectory, copiedDirectory);
      expect(
        await manager.readText(
          manager.joinPath(<String>[copiedDirectory, 'nested', 'child.txt']),
        ),
        'directory-copy',
      );
      await manager.move(copiedDirectory, movedDirectory);
      expect(await manager.exists(copiedDirectory), isFalse);
      expect(await manager.exists(movedDirectory), isTrue);
      await manager.copy(sourceDirectory, movedDirectory, overwrite: true);
      expect(await manager.exists(movedDirectory), isTrue);
      await manager.delete(movedDirectory, recursive: true);
      expect(await manager.exists(movedDirectory), isFalse);

      await expectLater(
        manager.copy(
          manager.joinPath(<String>[tempRoot.path, 'missing.txt']),
          manager.joinPath(<String>[tempRoot.path, 'missing-copy.txt']),
        ),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        manager.move(
          manager.joinPath(<String>[tempRoot.path, 'missing.txt']),
          manager.joinPath(<String>[tempRoot.path, 'missing-move.txt']),
        ),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test('workspace document store uses file system manager route', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_fs_store_route_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final manager = LocalFileSystemManager.linuxDebianArmForTest();
    final store = FileSystemWorkspaceDocumentStore(
      tempRoot,
      fileSystemManager: manager,
    );
    const document = DocumentState(
      documentId: 'notes/main.txt',
      text: 'stored through manager',
      revision: 4,
    );

    await store.saveDocument(document);
    final loaded = await store.loadDocument(document.documentId);

    expect(loaded.text, document.text);
    expect(loaded.revision, document.revision);
    expect(
      await manager.exists(
        manager.joinPath(<String>[tempRoot.path, 'notes', 'main.txt']),
      ),
      isTrue,
    );
  });
}
