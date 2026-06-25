import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/range_index.dart';

void main() {
  test('queries point and overlapping ranges with nested intervals', () {
    final index = RangeIndex<_IndexedRange>.fromValues(
      const <_IndexedRange>[
        _IndexedRange('outer', 0, 20),
        _IndexedRange('nested', 5, 10),
        _IndexedRange('cross', 8, 15),
        _IndexedRange('cursor', 10, 10),
        _IndexedRange('boundary', 20, 20),
      ],
      startOf: (range) => range.start,
      endOf: (range) => range.end,
      revision: 4,
    );

    expect(index.pointQuery(10).map((range) => range.id), [
      'outer',
      'cross',
      'cursor',
    ]);
    expect(index.overlapQuery(start: 9, end: 11).map((range) => range.id), [
      'outer',
      'nested',
      'cross',
      'cursor',
    ]);
    expect(index.overlapQuery(start: 0, end: 20).map((range) => range.id), [
      'outer',
      'nested',
      'cross',
      'cursor',
    ]);
    expect(index.overlapQuery(start: 20, end: 25).map((range) => range.id), [
      'boundary',
    ]);
  });

  test('handles cross-line offsets and layer filtering', () {
    const source = 'one\ntwo\nthree';
    final newline = source.indexOf('\n');
    final index = RangeIndex<_IndexedRange>.fromEntries(
      <RangeIndexEntry<_IndexedRange>>[
        RangeIndexEntry<_IndexedRange>(
          start: newline - 1,
          end: newline + 5,
          value: const _IndexedRange('cross-line', 2, 8),
          layer: 'semantic',
        ),
        const RangeIndexEntry<_IndexedRange>(
          start: 0,
          end: 3,
          value: _IndexedRange('diagnostic', 0, 3),
          layer: 'diagnostics',
        ),
      ],
    );

    expect(index.overlapQuery(start: 4, end: 6), [
      const _IndexedRange('cross-line', 2, 8),
    ]);
    expect(
      index.overlapQuery(start: 0, end: 6, layer: 'diagnostics'),
      [const _IndexedRange('diagnostic', 0, 3)],
    );
  });

  test('reports boolean overlap without allocating query results', () {
    final index = RangeIndex<_IndexedRange>.fromValues(
      const <_IndexedRange>[
        _IndexedRange('a', 3, 3),
        _IndexedRange('b', 5, 9),
      ],
      startOf: (range) => range.start,
      endOf: (range) => range.end,
    );

    expect(index.overlapsPoint(3), isTrue);
    expect(index.overlapsRange(start: 0, end: 3), isFalse);
    expect(index.overlapsRange(start: 3, end: 4), isTrue);
    expect(index.overlapsRange(start: 9, end: 12), isFalse);
  });

  test('preserves input order for equal ranges and priorities', () {
    final index = RangeIndex<_IndexedRange>.fromValues(
      const <_IndexedRange>[
        _IndexedRange('first', 1, 4),
        _IndexedRange('second', 1, 4),
      ],
      startOf: (range) => range.start,
      endOf: (range) => range.end,
    );

    expect(index.overlapQuery(start: 2, end: 3).map((range) => range.id), [
      'first',
      'second',
    ]);
  });

  test('invalidates entries from stale revisions', () {
    final index = RangeIndex<_IndexedRange>.fromEntries(
      const <RangeIndexEntry<_IndexedRange>>[
        RangeIndexEntry<_IndexedRange>(
          start: 0,
          end: 4,
          value: _IndexedRange('stale', 0, 4),
          revision: 1,
        ),
        RangeIndexEntry<_IndexedRange>(
          start: 4,
          end: 8,
          value: _IndexedRange('fresh', 4, 8),
          revision: 2,
        ),
      ],
      revision: 1,
    );

    final current = index.invalidateStale(2);

    expect(current.revision, 2);
    expect(current.overlapQuery(start: 0, end: 10), [
      const _IndexedRange('fresh', 4, 8),
    ]);
  });
}

class _IndexedRange {
  const _IndexedRange(this.id, this.start, this.end);

  final String id;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) {
    return other is _IndexedRange &&
        other.id == id &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(id, start, end);

  @override
  String toString() => '_IndexedRange($id, $start, $end)';
}
