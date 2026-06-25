import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

const _workspaceRoot = '/workspace/app';

void main() {
  group('VityoRefreshQueue', () {
    test('coalesces canonical duplicate watcher events', () {
      final queue = VityoRefreshQueue();

      expect(
        queue.enqueue(
          _event(VityoVfsEventKind.created, 'src/../src/main.styio', 1),
        ),
        isTrue,
      );
      expect(
        queue.enqueue(_event(VityoVfsEventKind.modified, 'src/main.styio', 2)),
        isTrue,
      );

      final events = queue.drain();
      expect(events, hasLength(1));
      expect(events.single.kind, VityoVfsEventKind.created);
      expect(events.single.ref.normalizedPath, '$_workspaceRoot/src/main.styio');
      expect(events.single.revision, 2);
      expect(queue.pendingCount, 0);
    });

    test('coalesces create-delete and delete-create watcher pairs', () {
      final createDelete = VityoRefreshQueue()
        ..enqueue(_event(VityoVfsEventKind.created, 'tmp/generated.styio', 1))
        ..enqueue(_event(VityoVfsEventKind.deleted, 'tmp/generated.styio', 2));
      final replace = VityoRefreshQueue()
        ..enqueue(_event(VityoVfsEventKind.deleted, 'src/main.styio', 3))
        ..enqueue(_event(VityoVfsEventKind.created, 'src/main.styio', 4));

      final deleted = createDelete.drain();
      final modified = replace.drain();

      expect(deleted, hasLength(1));
      expect(deleted.single.kind, VityoVfsEventKind.deleted);
      expect(deleted.single.revision, 2);

      expect(modified, hasLength(1));
      expect(modified.single.kind, VityoVfsEventKind.modified);
      expect(modified.single.revision, 4);
    });

    test('coalesces a created file moved before drain as created at destination', () {
      final queue = VityoRefreshQueue()
        ..enqueue(_event(VityoVfsEventKind.created, 'src/old.styio', 1))
        ..enqueue(
          VityoVfsEvent(
            kind: VityoVfsEventKind.moved,
            ref: _ref('src/new.styio'),
            previousRef: _ref('src/old.styio'),
            revision: 2,
          ),
        );

      final events = queue.drain();

      expect(events, hasLength(1));
      expect(events.single.kind, VityoVfsEventKind.created);
      expect(
        events.single.ref.normalizedPath,
        '$_workspaceRoot/src/new.styio',
      );
      expect(events.single.revision, 2);
    });

    test('rejects outside, traversal, ignored, and excluded paths', () {
      final queue = VityoRefreshQueue(
        ignoreRules: const VityoVfsIgnoreRules(
          excludedPrefixes: <String>['build', '/workspace/app/.git'],
          excludedSuffixes: <String>['.tmp'],
        ),
      );

      expect(
        queue.enqueue(
          _event(VityoVfsEventKind.modified, '../app/src/main.styio', 1),
        ),
        isFalse,
      );
      expect(
        queue.enqueue(
          _event(
            VityoVfsEventKind.modified,
            '/workspace/app-cache/main.styio',
            2,
          ),
        ),
        isFalse,
      );
      expect(
        queue.enqueue(
          _event(VityoVfsEventKind.modified, 'build/out.styio', 3),
        ),
        isFalse,
      );
      expect(
        queue.enqueue(_event(VityoVfsEventKind.modified, '.git/config', 4)),
        isFalse,
      );
      expect(
        queue.enqueue(_event(VityoVfsEventKind.modified, 'src/cache.tmp', 5)),
        isFalse,
      );
      expect(
        queue.enqueue(
          _event(VityoVfsEventKind.modified, 'build-cache/main.styio', 6),
        ),
        isTrue,
      );

      final events = queue.drain();
      expect(events, hasLength(1));
      expect(events.single.ref.workspaceRelativePath, 'build-cache/main.styio');
    });

    test('uses snapshot symlink guard before accepting refreshes', () {
      final symlink = VityoVfsFileSnapshot(
        ref: _ref('vendor'),
        contentHash: 'hash-vendor',
        modifiedAtRevision: 1,
        isDirectory: true,
        isSymlink: true,
      );
      final queue = VityoRefreshQueue(
        guardSnapshot: VityoVfsSnapshot(
          revision: 1,
          files: <String, VityoVfsFileSnapshot>{
            symlink.ref.normalizedPath: symlink,
          },
        ),
      );

      expect(
        queue.enqueue(
          _event(VityoVfsEventKind.modified, 'vendor/pkg/main.styio', 1),
        ),
        isFalse,
      );
      expect(
        queue.enqueue(_event(VityoVfsEventKind.modified, 'src/main.styio', 2)),
        isTrue,
      );

      final events = queue.drain();
      expect(events, hasLength(1));
      expect(events.single.ref.workspaceRelativePath, 'src/main.styio');
    });

    test('cancels pending events and rejects future enqueue attempts', () {
      final queue = VityoRefreshQueue()
        ..enqueue(_event(VityoVfsEventKind.modified, 'src/main.styio', 1));

      queue.cancel();

      expect(queue.isCancelled, isTrue);
      expect(queue.pendingCount, 0);
      expect(
        queue.enqueue(_event(VityoVfsEventKind.modified, 'src/next.styio', 2)),
        isFalse,
      );
      expect(queue.drain(), isEmpty);
    });
  });
}

VityoVfsEvent _event(VityoVfsEventKind kind, String path, int revision) {
  return VityoVfsEvent(kind: kind, ref: _ref(path), revision: revision);
}

VityoVirtualFileRef _ref(String path) {
  return VityoVirtualFileRef(workspaceRoot: _workspaceRoot, path: path);
}
