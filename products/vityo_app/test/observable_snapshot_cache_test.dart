import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  test('cache never exceeds the bound and evicts least-recently-used first', () {
    final snapshot = decodeCanonicalFixture();
    final cache = ObservableSnapshotCache(maxEntries: 3);
    final identities = <SnapshotIdentity>[
      for (var i = 0; i < 9; i += 1)
        SnapshotIdentity(
          schemaVersion: 1,
          compilationUnitKey: snapshot.compilationUnit.identityKey,
          producerKey: snapshot.producer.identityKey,
          artifactDigest: 'digest-$i',
        ),
    ];

    for (final identity in identities) {
      cache.put(identity, snapshot);
      expect(cache.length, lessThanOrEqualTo(3));
    }
    expect(cache.length, 3);
    expect(cache.metrics.evictions, 6);
    expect(cache.get(identities[6]), isNotNull);
    expect(cache.get(identities[7]), isNotNull);
    expect(cache.get(identities[8]), isNotNull);
    expect(cache.get(identities[0]), isNull);
  });

  test('identical bytes are a hit and do not decode again', () {
    final bytes = readObservableFixtureBytes('canonical.json');
    var decodeCount = 0;
    final cache = ObservableSnapshotCache(maxEntries: 3);
    ObservableSnapshot decode(List<int> input) {
      decodeCount += 1;
      return decodeObservableSnapshotBytes(input).snapshot!;
    }

    final first = cache.intake(bytes, decode: decode);
    final second = cache.intake(bytes, decode: decode);
    expect(first.hit, isFalse);
    expect(second.hit, isTrue);
    expect(identical(first.snapshot, second.snapshot), isTrue);
    expect(decodeCount, 1);
    expect(cache.metrics.hits, greaterThanOrEqualTo(1));
    expect(cache.length, 1);
  });
}
