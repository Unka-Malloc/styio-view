import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/document_state.dart';
import 'package:vityo_app/src/ide/local_service/vityod_workspace_search_provider.dart';
import 'package:vityo_app/src/ide/workspace/workspace_document_store_io.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/file_system/file_system.dart';

import '../support/vityod_test_harness.dart';

void main() {
  test(
    'desktop file operations, watch, and paged search stay behind vityod',
    () async {
      final harness = await VityodTestHarness.start(
        clientId: 'file-service-test',
      );
      final root = await Directory.systemTemp.createTemp('vityod-fs-test-');
      final secondRoot = await Directory.systemTemp.createTemp(
        'vityod-fs-second-test-',
      );
      addTearDown(() async {
        await harness.close();
        if (await root.exists()) await root.delete(recursive: true);
        if (await secondRoot.exists()) await secondRoot.delete(recursive: true);
      });
      final manager = await VityodFileSystemManager.open(
        facts: FileSystemFacts.linuxDebianArm(),
        client: harness.client,
        allowedRoots: <String>[root.path],
      );

      final source = manager.joinPath(<String>[root.path, 'src', 'main.styio']);
      final copy = manager.joinPath(<String>[root.path, 'src', 'copy.styio']);
      final moved = manager.joinPath(<String>[root.path, 'src', 'moved.styio']);
      await manager.writeText(source, 'needle\nneedle');
      expect(await manager.readText(source), 'needle\nneedle');
      expect((await manager.stat(source)).isFile, isTrue);
      await manager.copy(source, copy);
      await manager.move(copy, moved);
      expect(await manager.exists(copy), isFalse);
      expect(await manager.exists(moved), isTrue);
      expect(
        (await manager.list(
          root.path,
          recursive: true,
        )).where((entry) => entry.isFile),
        hasLength(2),
      );

      final eventFuture = manager
          .watch(root.path, recursive: true)
          .first
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final watched = manager.joinPath(<String>[root.path, 'watched.styio']);
      await manager.writeText(watched, 'watched');
      final event = await eventFuture;
      expect(event.kind, FileSystemManagerEventKind.created);
      expect(event.normalizedPath, manager.normalizePath(watched));

      final opened = await harness.client.request(
        method: 'workspace.open',
        idempotencyKey: 'workspace-open',
        workspaceId: 'search-workspace',
        params: <String, Object?>{'rootPath': root.path},
      );
      expect(opened.method, 'workspace.open.result');
      final firstPage = await harness.client.request(
        method: 'workspace.search',
        idempotencyKey: 'search-page-1',
        workspaceId: 'search-workspace',
        params: const <String, Object?>{
          'query': 'needle',
          'cursor': 0,
          'limit': 1,
        },
      );
      expect(firstPage.params['matches'], hasLength(1));
      expect(firstPage.params['nextCursor'], 1);
      final secondPage = await harness.client.request(
        method: 'workspace.search',
        idempotencyKey: 'search-page-2',
        workspaceId: 'search-workspace',
        params: const <String, Object?>{
          'query': 'needle',
          'cursor': 1,
          'limit': 1,
        },
      );
      expect(secondPage.params['matches'], hasLength(1));
      final typedSearch = await VityodWorkspaceTextSearchProvider(
        client: harness.client,
      ).search(workspaceId: 'search-workspace', query: 'needle', maxMatches: 2);
      expect(typedSearch.matches, hasLength(2));
      expect(typedSearch.matches.first.documentId, 'src/main.styio');
      expect(typedSearch.matches.first.lineText, 'needle');
      expect(typedSearch.matches.first.range.start, 0);

      final escaped = await harness.client.request(
        method: 'fs.read',
        idempotencyKey: 'escape-rejected',
        params: const <String, Object?>{
          'scopeId': 'search-workspace',
          'relativePath': '../outside',
        },
      );
      expect(escaped.method, 'fs.read.error');
      expect(escaped.params['errorCode'], 'workspace_root_escape');

      final documentStore = VityodWorkspaceDocumentStore(
        client: harness.client,
        workspaceId: 'document-workspace',
        workspaceRoot: root.path,
      );
      await documentStore.open();
      final loaded = await documentStore.loadDocument(source);
      expect(loaded.documentId, 'src/main.styio');
      expect(loaded.text, 'needle\nneedle');
      await documentStore.saveDocument(
        DocumentState(
          documentId: loaded.documentId,
          text: 'saved through workspace transaction',
          revision: loaded.revision + 1,
        ),
      );
      expect(
        await manager.readText(source),
        'saved through workspace transaction',
      );
      final helper = manager.joinPath(<String>[
        root.path,
        'src',
        'helper.styio',
      ]);
      await manager.writeText(helper, 'helper before');
      final currentMain = await documentStore.loadDocument(source);
      final currentHelper = await documentStore.loadDocument(helper);
      final atomicRevisions = await documentStore
          .saveDocumentsAtomically(<DocumentState>[
            DocumentState(
              documentId: currentMain.documentId,
              text: 'main atomic after',
              revision: currentMain.revision + 1,
            ),
            DocumentState(
              documentId: currentHelper.documentId,
              text: 'helper atomic after',
              revision: currentHelper.revision + 1,
            ),
          ]);
      expect(atomicRevisions.keys.toSet(), <String>{
        'src/main.styio',
        'src/helper.styio',
      });
      expect(await manager.readText(source), 'main atomic after');
      expect(await manager.readText(helper), 'helper atomic after');

      final secondSource = File(
        '${secondRoot.path}${Platform.pathSeparator}src'
        '${Platform.pathSeparator}main.styio',
      );
      await secondSource.parent.create(recursive: true);
      await secondSource.writeAsString('second workspace');
      final secondStore = VityodWorkspaceDocumentStore(
        client: harness.client,
        workspaceId: 'second-document-workspace',
        workspaceRoot: secondRoot.path,
      );
      await secondStore.open();
      expect(
        (await secondStore.loadDocument(secondSource.path)).text,
        'second workspace',
      );
      expect(
        (await documentStore.loadDocument(source)).text,
        'main atomic after',
      );

      await manager.delete(moved);
      expect(await manager.exists(moved), isFalse);
    },
    skip: !VityodTestHarness.isSupported
        ? 'Native vityod transport is unavailable.'
        : false,
  );
}
