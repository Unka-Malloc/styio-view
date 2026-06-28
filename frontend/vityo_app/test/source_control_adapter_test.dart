import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/workspace/source_control_adapter.dart';

void main() {
  group('SourceControlSnapshot', () {
    test('none has no provider and no changes', () {
      const snapshot = SourceControlSnapshot.none;
      expect(snapshot.isAvailable, isFalse);
      expect(snapshot.hasChanges, isFalse);
      expect(snapshot.providerKind, SourceControlProviderKind.none);
    });

    test('blocked has reason and is unavailable', () {
      final snapshot = SourceControlSnapshot.blocked('Git not installed');
      expect(snapshot.isAvailable, isFalse);
      expect(snapshot.blockedReason, 'Git not installed');
      expect(snapshot.providerKind, SourceControlProviderKind.unavailable);
    });

    test('hostedBlocked is specific to hosted platforms', () {
      final snapshot = SourceControlSnapshot.hostedBlocked();
      expect(snapshot.isAvailable, isFalse);
      expect(snapshot.blockedReason, contains('hosted-controlled'));
    });

    test('notMounted reports module not mounted', () {
      final snapshot = SourceControlSnapshot.notMounted();
      expect(snapshot.isAvailable, isFalse);
      expect(snapshot.blockedReason, contains('not mounted'));
    });

    test('available snapshot with changes reports correctly', () {
      final snapshot = const SourceControlSnapshot(
        providerKind: SourceControlProviderKind.localGit,
        branchName: 'main',
        changes: [
          SourceControlChange(
            filePath: 'main.styio',
            kind: SourceControlChangeKind.modified,
            staged: false,
          ),
          SourceControlChange(
            filePath: 'new.styio',
            kind: SourceControlChangeKind.added,
            staged: true,
          ),
        ],
      );

      expect(snapshot.isAvailable, isTrue);
      expect(snapshot.hasChanges, isTrue);
      expect(snapshot.stagedCount, 1);
      expect(snapshot.unstagedCount, 1);
      expect(snapshot.changes.length, 2);
    });

    test('serializes to JSON', () {
      final snapshot = const SourceControlSnapshot(
        providerKind: SourceControlProviderKind.localGit,
        branchName: 'feature/test',
        remoteName: 'origin',
        aheadCount: 2,
        behindCount: 0,
        changes: [
          SourceControlChange(
            filePath: 'lib.styio',
            kind: SourceControlChangeKind.modified,
          ),
        ],
      );

      final json = snapshot.toJson();
      expect(json['providerKind'], 'localGit');
      expect(json['branchName'], 'feature/test');
      expect(json['isAvailable'], true);
      expect(json['hasChanges'], true);
      expect(json['stagedCount'], 0);
      expect(json['unstagedCount'], 1);
    });
  });

  group('SourceControlChange', () {
    test('serializes with kind and staged flag', () {
      const change = SourceControlChange(
        filePath: 'src/main.styio',
        kind: SourceControlChangeKind.renamed,
        oldPath: 'src/old.styio',
        staged: true,
      );

      final json = change.toJson();
      expect(json['filePath'], 'src/main.styio');
      expect(json['kind'], 'renamed');
      expect(json['oldPath'], 'src/old.styio');
      expect(json['staged'], true);
    });
  });

  group('LocalHistorySnapshot', () {
    test('empty snapshot is not available', () {
      const snapshot = LocalHistorySnapshot.empty;
      expect(snapshot.isAvailable, isFalse);
      expect(snapshot.entries, isEmpty);
    });

    test('available when persisted', () {
      const snapshot = LocalHistorySnapshot(
        persisted: true,
        entries: [
          LocalHistoryEntry(
            entryId: 'h1',
            filePath: 'main.styio',
            savedAtIso8601: '2026-06-24T00:00:00Z',
            contentHash: 'abc123',
            byteLength: 1024,
          ),
        ],
      );

      expect(snapshot.isAvailable, isTrue);
      expect(snapshot.entries.length, 1);
    });

    test('serializes to JSON', () {
      const snapshot = LocalHistorySnapshot(
        persisted: true,
        maxEntries: 50,
        entries: [],
      );
      final json = snapshot.toJson();
      expect(json['persisted'], true);
      expect(json['maxEntries'], 50);
      expect(json['isAvailable'], true);
    });
  });
}
