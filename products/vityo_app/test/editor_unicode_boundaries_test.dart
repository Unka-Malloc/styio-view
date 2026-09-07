import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/input/editor_composition.dart';
import 'package:vityo_app/src/ide/editor/input/unicode_boundary_index.dart';

void main() {
  setUp(UnicodeBoundaryIndex.clearCache);

  group('UnicodeBoundaryIndex', () {
    test('navigates extended clusters with sorted UTF-16 boundaries', () {
      const text = 'Ae\u0301👨‍👩‍👧‍👦👩🏽‍💻Z';
      final combiningStart = text.indexOf('e');
      final familyStart = text.indexOf('👨');
      final technologistStart = text.indexOf('👩🏽‍💻');
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: 'unicode',
        revision: 1,
        text: text,
        anchorOffset: familyStart,
        maxCodeUnits: text.length,
      );

      expect(
        index.nextBoundary(combiningStart, documentRevision: 1),
        familyStart,
      );
      expect(
        index.nextBoundary(familyStart, documentRevision: 1),
        technologistStart,
      );
      expect(
        index.previousBoundary(technologistStart, documentRevision: 1),
        familyStart,
      );
      expect(
        index.boundaries,
        orderedEquals(index.boundaries.toList()..sort()),
      );
    });

    test('clamps and deletes an entire cluster from an interior offset', () {
      const cluster = '👩🏽‍💻';
      const text = 'a${cluster}b';
      const start = 1;
      final end = start + cluster.length;
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: 'unicode',
        revision: 2,
        text: text,
        anchorOffset: start,
        maxCodeUnits: text.length,
      );

      expect(
        index.clampBoundary(
          start + 2,
          bias: UnicodeBoundaryBias.backward,
          documentRevision: 2,
        ),
        start,
      );
      expect(
        index.clampBoundary(
          start + 2,
          bias: UnicodeBoundaryBias.forward,
          documentRevision: 2,
        ),
        end,
      );
      expect(
        index.deletionRange(start + 2, forward: false, documentRevision: 2),
        EditorInputRange(start: start, end: end),
      );
    });

    test('rejects queries from another document revision', () {
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: 'unicode',
        revision: 7,
        text: 'abc',
        anchorOffset: 1,
        maxCodeUnits: 3,
      );
      expect(() => index.isBoundary(1, documentRevision: 8), throwsStateError);
    });

    test('retains only a bounded slice of a large document', () {
      final text =
          '${List<String>.filled(10000, 'a').join()}👨‍👩‍👧‍👦'
          '${List<String>.filled(10000, 'b').join()}';
      final anchor = text.indexOf('👨');
      final index = UnicodeBoundaryIndex.forTextWindow(
        documentId: 'large',
        revision: 1,
        text: text,
        anchorOffset: anchor,
        maxCodeUnits: 128,
      );

      expect(index.indexedCodeUnitCount, lessThanOrEqualTo(128));
      expect(index.windowStart, greaterThan(0));
      expect(index.windowEnd, lessThan(text.length));
      expect(index.windowText.length, index.indexedCodeUnitCount);
    });

    test('LRU cache obeys entry and aggregate code-unit caps', () {
      for (var entry = 0; entry < 140; entry += 1) {
        UnicodeBoundaryIndex.forTextWindow(
          documentId: 'document-$entry',
          revision: 1,
          text: List<String>.filled(600, 'x').join(),
          anchorOffset: 300,
          maxCodeUnits: 600,
        );
      }
      expect(
        UnicodeBoundaryIndex.cachedEntryCount,
        lessThanOrEqualTo(UnicodeBoundaryIndex.maximumEntryCount),
      );
      expect(
        UnicodeBoundaryIndex.cachedCodeUnitCount,
        lessThanOrEqualTo(UnicodeBoundaryIndex.maximumCachedCodeUnits),
      );
    });

    test('new document revision evicts its stale cached windows', () {
      UnicodeBoundaryIndex.forTextWindow(
        documentId: 'same',
        revision: 1,
        text: 'first',
        anchorOffset: 2,
        maxCodeUnits: 5,
      );
      UnicodeBoundaryIndex.forTextWindow(
        documentId: 'same',
        revision: 2,
        text: 'second',
        anchorOffset: 2,
        maxCodeUnits: 6,
      );
      expect(UnicodeBoundaryIndex.cachedEntryCount, 1);
      expect(UnicodeBoundaryIndex.cachedCodeUnitCount, 6);
    });
  });
}
