import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test(
    'navigation history snapshot reports back/forward from current index',
    () {
      const snapshot = WorkspaceNavigationHistorySnapshot(
        entries: <WorkspaceNavigationLocation>[
          WorkspaceNavigationLocation(
            filePath: 'src/a.styio',
            range: SourceRange(start: 0, end: 5),
            line: 0,
            column: 0,
            previewText: 'fn a',
            label: 'A',
            kind: WorkspaceNavigationLocationKind.symbol,
          ),
          WorkspaceNavigationLocation(
            filePath: 'src/b.styio',
            range: SourceRange(start: 10, end: 15),
            line: 1,
            column: 2,
            previewText: 'fn b',
            label: 'B',
            kind: WorkspaceNavigationLocationKind.file,
          ),
          WorkspaceNavigationLocation(
            filePath: 'src/c.styio',
            range: SourceRange(start: 20, end: 25),
            line: 2,
            column: 4,
            previewText: 'fn c',
            label: 'C',
            kind: WorkspaceNavigationLocationKind.search,
          ),
        ],
        currentIndex: 1,
      );

      expect(snapshot.canGoBack, isTrue);
      expect(snapshot.canGoForward, isTrue);
      expect(snapshot.currentLocation?.filePath, 'src/b.styio');
      expect(snapshot.currentLocation?.displayLocation, 'src/b.styio:2:3');
      expect(snapshot.currentLocation?.label, 'B');
      expect(
        snapshot.currentLocation?.kind,
        WorkspaceNavigationLocationKind.file,
      );

      final backSnapshot = WorkspaceNavigationHistorySnapshot(
        entries: snapshot.entries,
        currentIndex: 0,
      );
      expect(backSnapshot.canGoBack, isFalse);
      expect(backSnapshot.canGoForward, isTrue);
      expect(backSnapshot.currentLocation?.filePath, 'src/a.styio');

      final forwardSnapshot = WorkspaceNavigationHistorySnapshot(
        entries: snapshot.entries,
        currentIndex: 2,
      );
      expect(forwardSnapshot.canGoBack, isTrue);
      expect(forwardSnapshot.canGoForward, isFalse);
      expect(forwardSnapshot.currentLocation?.filePath, 'src/c.styio');
    },
  );

  test('navigation history snapshot returns null for empty entries', () {
    const empty = WorkspaceNavigationHistorySnapshot(
      entries: <WorkspaceNavigationLocation>[],
      currentIndex: 0,
    );

    expect(empty.canGoBack, isFalse);
    expect(empty.canGoForward, isFalse);
    expect(empty.currentLocation, isNull);
  });

  test('sameTarget detects duplicate locations', () {
    const first = WorkspaceNavigationLocation(
      filePath: 'src/a.styio',
      range: SourceRange(start: 0, end: 5),
      line: 0,
      column: 0,
      previewText: 'fn a',
      label: 'A',
    );
    const same = WorkspaceNavigationLocation(
      filePath: 'src/a.styio',
      range: SourceRange(start: 0, end: 5),
      line: 0,
      column: 0,
      previewText: 'fn a',
      label: 'A',
    );
    const different = WorkspaceNavigationLocation(
      filePath: 'src/a.styio',
      range: SourceRange(start: 10, end: 15),
      line: 1,
      column: 2,
      previewText: 'fn a',
      label: 'A',
    );

    expect(first.sameTarget(same), isTrue);
    expect(first.sameTarget(different), isFalse);
  });

  test('recentLocations deduplicates by filePath+range', () {
    const snapshot = WorkspaceNavigationHistorySnapshot(
      entries: <WorkspaceNavigationLocation>[
        WorkspaceNavigationLocation(
          filePath: 'src/a.styio',
          range: SourceRange(start: 0, end: 5),
          line: 0,
          column: 0,
          previewText: 'fn a',
          label: 'A',
          kind: WorkspaceNavigationLocationKind.symbol,
        ),
        WorkspaceNavigationLocation(
          filePath: 'src/b.styio',
          range: SourceRange(start: 10, end: 15),
          line: 1,
          column: 2,
          previewText: 'fn b',
          label: 'B',
          kind: WorkspaceNavigationLocationKind.file,
        ),
        // Duplicate of first entry but with different label
        WorkspaceNavigationLocation(
          filePath: 'src/a.styio',
          range: SourceRange(start: 0, end: 5),
          line: 0,
          column: 0,
          previewText: 'fn a',
          label: 'A again',
          kind: WorkspaceNavigationLocationKind.symbol,
        ),
        WorkspaceNavigationLocation(
          filePath: 'src/c.styio',
          range: SourceRange(start: 20, end: 25),
          line: 2,
          column: 4,
          previewText: 'fn c',
          label: 'C',
          kind: WorkspaceNavigationLocationKind.search,
        ),
      ],
      currentIndex: 3,
    );

    final recent = snapshot.recentLocations;
    // 4 entries, but src/a.styio:0-5 appears twice -> 3 unique
    expect(recent, hasLength(3));
    // Most recent first (reversed order), skipping duplicate
    expect(recent[0].filePath, 'src/c.styio');
    expect(recent[1].filePath, 'src/a.styio');
    expect(recent[2].filePath, 'src/b.styio');
  });
}
