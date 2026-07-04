import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_file_index.dart';
import 'package:vityo_app/src/view_ide/workspace/vfs.dart';
import 'package:vityo_app/src/view_ide/language/semantic/styio_semantic_core.dart';

void main() {
  group('WorkspaceFileIndexStatus', () {
    test('ready is usable', () {
      expect(WorkspaceFileIndexStatus.ready.isUsable, isTrue);
    });

    test('partial is usable', () {
      expect(WorkspaceFileIndexStatus.partial.isUsable, isTrue);
    });

    test('blocked is not usable', () {
      expect(WorkspaceFileIndexStatus.blocked.isUsable, isFalse);
    });

    test('wireValue returns expected strings', () {
      expect(WorkspaceFileIndexStatus.ready.wireValue, 'ready');
      expect(WorkspaceFileIndexStatus.partial.wireValue, 'partial');
      expect(WorkspaceFileIndexStatus.blocked.wireValue, 'blocked');
    });
  });

  group('WorkspaceFileIndexEntry', () {
    test('isFreshFor returns true when revision matches', () {
      final entry = WorkspaceFileIndexEntry(
        path: 'src/main.sty',
        documentId: 'file:///src/main.sty',
        lastIndexedRevision: 5,
        lastModifiedAt: DateTime(2026, 6, 29),
      );
      expect(entry.isFreshFor(5), isTrue);
      expect(entry.isFreshFor(4), isFalse);
    });

    test('copyWith preserves unset fields', () {
      final entry = WorkspaceFileIndexEntry(
        path: 'src/main.sty',
        documentId: 'file:///src/main.sty',
        lastIndexedRevision: 5,
        lastModifiedAt: DateTime(2026, 6, 29),
        symbolCount: 10,
        referenceCount: 42,
      );
      final updated = entry.copyWith(lastIndexedRevision: 6);
      expect(updated.path, entry.path);
      expect(updated.documentId, entry.documentId);
      expect(updated.lastIndexedRevision, 6);
      expect(updated.symbolCount, 10);
      expect(updated.referenceCount, 42);
    });

    test('copyWith clears semanticCore when requested', () {
      final entry = WorkspaceFileIndexEntry(
        path: 'src/main.sty',
        documentId: 'file:///src/main.sty',
        lastIndexedRevision: 1,
        lastModifiedAt: DateTime(2026, 6, 29),
        semanticCore: StyioSemanticCore.ready(
          keys: const SemanticIndexInvalidationKeys(
            documentId: 'file:///src/main.sty',
            revision: 1,
            workspaceGraphHash: 'abc',
            toolchainId: 'styio-0.9.0',
            providerId: 'styio-service',
            protocolVersion: '1.0',
            semanticPayloadVersion: '2.0',
          ),
        ),
      );
      expect(entry.semanticCore, isNotNull);
      final cleared = entry.copyWith(clearSemanticCore: true);
      expect(cleared.semanticCore, isNull);
    });
  });

  group('WorkspaceFileIndex - empty', () {
    test('empty index is blocked', () {
      const index = WorkspaceFileIndex(workspaceRoot: '/workspace');
      expect(index.isEmpty, isTrue);
      expect(index.status, WorkspaceFileIndexStatus.blocked);
      expect(index.totalFileCount, 0);
      expect(index.totalSymbolCount, 0);
    });
  });

  group('WorkspaceFileIndex - build', () {
    test('builds index from VFS file refs', () {
      final files = [
        const VityoVirtualFileRef(
          workspaceRoot: '/home/project',
          path: '/home/project/src/main.sty',
        ),
        const VityoVirtualFileRef(
          workspaceRoot: '/home/project',
          path: '/home/project/src/utils.sty',
        ),
      ];

      final index = WorkspaceFileIndex.build(
        workspaceRoot: '/home/project',
        files: files,
        workspaceGraphHash: 'abc123',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
      );

      expect(index.status, WorkspaceFileIndexStatus.ready);
      expect(index.totalFileCount, 2);
      expect(index.entryFor('src/main.sty'), isNotNull);
      expect(index.entryFor('src/utils.sty'), isNotNull);
      expect(index.entryFor('nonexistent.sty'), isNull);
    });

    test('build with empty root returns blocked', () {
      final index = WorkspaceFileIndex.build(
        workspaceRoot: '',
        files: [],
        workspaceGraphHash: '',
        toolchainId: '',
        providerId: '',
      );
      expect(index.status, WorkspaceFileIndexStatus.blocked);
      expect(index.blockedReason, isNotEmpty);
    });

    test('build with empty file list returns blocked', () {
      final index = WorkspaceFileIndex.build(
        workspaceRoot: '/workspace',
        files: [],
        workspaceGraphHash: '',
        toolchainId: '',
        providerId: '',
      );
      expect(index.status, WorkspaceFileIndexStatus.blocked);
    });
  });

  group('WorkspaceFileIndex - mutations', () {
    test('indexFile adds or updates an entry', () {
      const empty = WorkspaceFileIndex(workspaceRoot: '/workspace');
      final withFile = empty.indexFile(
        WorkspaceFileIndexEntry(
          path: 'src/main.sty',
          documentId: 'file:///src/main.sty',
          lastIndexedRevision: 1,
          lastModifiedAt: DateTime(2026, 6, 29),
          symbolCount: 15,
          referenceCount: 30,
        ),
      );

      expect(withFile.totalFileCount, 1);
      expect(withFile.totalSymbolCount, 15);
      expect(withFile.totalReferenceCount, 30);
      expect(withFile.status, WorkspaceFileIndexStatus.ready);

      // Update existing
      final updated = withFile.indexFile(
        WorkspaceFileIndexEntry(
          path: 'src/main.sty',
          documentId: 'file:///src/main.sty',
          lastIndexedRevision: 2,
          lastModifiedAt: DateTime(2026, 6, 29),
          symbolCount: 20,
          referenceCount: 40,
          hasErrors: true,
        ),
      );

      expect(updated.totalFileCount, 1);
      expect(updated.totalSymbolCount, 20);
      expect(updated.totalReferenceCount, 40);
      expect(updated.errorFileCount, 1);
    });

    test('removeFile removes entry and updates aggregates', () {
      final index = WorkspaceFileIndex(
        workspaceRoot: '/workspace',
        entries: {
          'a.sty': WorkspaceFileIndexEntry(
            path: 'a.sty',
            documentId: 'file:///a.sty',
            lastIndexedRevision: 1,
            lastModifiedAt: DateTime(2026, 6, 29),
            symbolCount: 5,
          ),
          'b.sty': WorkspaceFileIndexEntry(
            path: 'b.sty',
            documentId: 'file:///b.sty',
            lastIndexedRevision: 1,
            lastModifiedAt: DateTime(2026, 6, 29),
            symbolCount: 10,
          ),
        },
        status: WorkspaceFileIndexStatus.ready,
        totalFileCount: 2,
        totalSymbolCount: 15,
      );

      final afterRemove = index.removeFile('a.sty');
      expect(afterRemove.totalFileCount, 1);
      expect(afterRemove.totalSymbolCount, 10);
      expect(afterRemove.entryFor('b.sty'), isNotNull);
      expect(afterRemove.entryFor('a.sty'), isNull);
    });

    test('invalidateAll clears entries and sets blocked', () {
      final index = WorkspaceFileIndex(
        workspaceRoot: '/workspace',
        entries: {
          'a.sty': WorkspaceFileIndexEntry(
            path: 'a.sty',
            documentId: 'file:///a.sty',
            lastIndexedRevision: 1,
            lastModifiedAt: DateTime(2026, 6, 29),
          ),
        },
        status: WorkspaceFileIndexStatus.ready,
        totalFileCount: 1,
      );

      final cleared = index.invalidateAll();
      expect(cleared.isEmpty, isTrue);
      expect(cleared.status, WorkspaceFileIndexStatus.blocked);
      expect(cleared.blockedReason, contains('invalidated'));
    });
  });

  group('WorkspaceFileIndex - staleness', () {
    test('isStaleFor detects workspace graph hash change', () {
      final index = WorkspaceFileIndex(
        workspaceRoot: '/workspace',
        workspaceGraphHash: 'old-hash',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
        entries: {
          'a.sty': WorkspaceFileIndexEntry(
            path: 'a.sty',
            documentId: 'file:///a.sty',
            lastIndexedRevision: 1,
            lastModifiedAt: DateTime(2026, 6, 29),
          ),
        },
        status: WorkspaceFileIndexStatus.ready,
      );

      expect(
        index.isStaleFor(
          currentWorkspaceGraphHash: 'new-hash',
          currentToolchainId: 'styio-0.9.0',
          currentProviderId: 'styio-service',
        ),
        isTrue,
      );

      expect(
        index.isStaleFor(
          currentWorkspaceGraphHash: 'old-hash',
          currentToolchainId: 'styio-0.9.0',
          currentProviderId: 'styio-service',
        ),
        isFalse,
      );
    });

    test('isStaleFor detects toolchain change', () {
      const index = WorkspaceFileIndex(
        workspaceRoot: '/workspace',
        workspaceGraphHash: 'abc',
        toolchainId: 'old-toolchain',
        providerId: 'styio-service',
        entries: {},
        status: WorkspaceFileIndexStatus.blocked,
      );

      expect(
        index.isStaleFor(
          currentWorkspaceGraphHash: 'abc',
          currentToolchainId: 'new-toolchain',
          currentProviderId: 'styio-service',
        ),
        isTrue,
      );
    });

    test('compositeKey format', () {
      const index = WorkspaceFileIndex(
        workspaceRoot: '/workspace',
        workspaceGraphHash: 'abc',
        toolchainId: 'styio-0.9.0',
        providerId: 'styio-service',
      );
      expect(index.compositeKey, '/workspace:abc:styio-0.9.0:styio-service');
    });
  });
}
