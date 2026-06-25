import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

const _workspaceRoot = '/workspace/app';

void main() {
  group('VityoVirtualFileRef', () {
    test('canonicalizes workspace paths and exposes relative paths', () {
      final ref = _ref(r'.\src\..\src/main.styio');

      expect(ref.normalizedWorkspaceRoot, _workspaceRoot);
      expect(ref.normalizedPath, '$_workspaceRoot/src/main.styio');
      expect(ref.workspaceRelativePath, 'src/main.styio');
      expect(ref.hasWorkspaceTraversal, isFalse);
      expect(ref.isInsideWorkspace, isTrue);
      expect(
        VityoVirtualFileRef.normalizePath(r'..\escape.styio'),
        '../escape.styio',
      );
    });

    test('keeps sibling prefixes outside the workspace', () {
      final sibling = _ref('/workspace/application/main.styio');
      final siblingPrefix = _ref('/workspace/app-cache/main.styio');

      expect(sibling.isInsideWorkspace, isFalse);
      expect(siblingPrefix.isInsideWorkspace, isFalse);
      expect(
        VityoVirtualFileRef.containsPath(
          _workspaceRoot,
          '/workspace/app-cache/main.styio',
        ),
        isFalse,
      );
    });

    test('blocks relative and absolute traversal that escapes then re-enters', () {
      final relativeTraversal = _ref('src/../../app/secret.styio');
      final absoluteTraversal = _ref(
        '/workspace/app/src/../../app/secret.styio',
      );
      final containedParentSegment = _ref('src/../lib/main.styio');

      expect(relativeTraversal.normalizedPath, '$_workspaceRoot/secret.styio');
      expect(relativeTraversal.hasWorkspaceTraversal, isTrue);
      expect(relativeTraversal.isInsideWorkspace, isFalse);
      expect(relativeTraversal.workspaceRelativePath, isEmpty);

      expect(absoluteTraversal.normalizedPath, '$_workspaceRoot/secret.styio');
      expect(absoluteTraversal.hasWorkspaceTraversal, isTrue);
      expect(absoluteTraversal.isInsideWorkspace, isFalse);

      expect(
        containedParentSegment.normalizedPath,
        '$_workspaceRoot/lib/main.styio',
      );
      expect(containedParentSegment.hasWorkspaceTraversal, isFalse);
      expect(containedParentSegment.isInsideWorkspace, isTrue);
    });
  });

  group('VityoVfsSnapshot', () {
    test('looks up files by canonical path and rejects unsafe refs', () {
      final file = VityoVfsFileSnapshot(
        ref: _ref('src/main.styio'),
        contentHash: 'hash-main',
        modifiedAtRevision: 4,
      );
      final snapshot = VityoVfsSnapshot(
        revision: 7,
        files: <String, VityoVfsFileSnapshot>{file.ref.normalizedPath: file},
      );

      expect(snapshot.lookup(_ref('src/../src/main.styio')), same(file));
      expect(snapshot.lookup(_ref('../app/src/main.styio')), isNull);
      expect(
        snapshot.lookup(_ref('/workspace/app-cache/src/main.styio')),
        isNull,
      );
    });

    test('guards symlink entries and descendants', () {
      final symlink = VityoVfsFileSnapshot(
        ref: _ref('vendor'),
        contentHash: 'hash-vendor',
        modifiedAtRevision: 5,
        isDirectory: true,
        isSymlink: true,
      );
      final source = VityoVfsFileSnapshot(
        ref: _ref('src/main.styio'),
        contentHash: 'hash-main',
        modifiedAtRevision: 6,
      );
      final snapshot = VityoVfsSnapshot(
        revision: 8,
        files: <String, VityoVfsFileSnapshot>{
          symlink.ref.normalizedPath: symlink,
          source.ref.normalizedPath: source,
        },
      );

      expect(snapshot.isBlockedBySymlinkGuard(_ref('vendor')), isTrue);
      expect(
        snapshot.isBlockedBySymlinkGuard(_ref('vendor/pkg/main.styio')),
        isTrue,
      );
      expect(
        snapshot.isBlockedBySymlinkGuard(_ref('vendor-cache/main.styio')),
        isFalse,
      );
      expect(snapshot.allowsAccess(_ref('src/main.styio')), isTrue);
      expect(snapshot.allowsAccess(_ref('../app/src/main.styio')), isFalse);
    });
  });
}

VityoVirtualFileRef _ref(String path) {
  return VityoVirtualFileRef(workspaceRoot: _workspaceRoot, path: path);
}
