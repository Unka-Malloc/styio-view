import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  const acceptedDeltas = <String>[
    'unchanged.json',
    'field-change.json',
    'add.json',
    'remove.json',
    'rename.json',
    'move.json',
    'split.json',
    'merge.json',
  ];

  test('accepted delta fixtures decode identically twice', () {
    for (final name in acceptedDeltas) {
      final bytes = readObservableTopologyFixtureBytes('delta/$name');
      final first = decodeObservableDeltaBytes(bytes);
      final second = decodeObservableDeltaBytes(bytes);
      expect(first.isOk, isTrue, reason: '$name: ${first.failure?.detail}');
      expect(second.isOk, isTrue);
      expect(first.envelope!.contract, kObservableDeltaContract);
      expect(first.envelope!.schemaMajor, 0);
      expect(first.envelope!.schemaMinor, 1);
      expect(
        first.envelope!.operations.length,
        second.envelope!.operations.length,
      );
    }
  });

  test('unknown optional keys are ignored and malformed still decodes', () {
    final additive = decodeObservableDeltaBytes(
      readObservableTopologyFixtureBytes(
        'vityo/delta/unsupported-minor-additive.json',
      ),
    );
    expect(additive.isOk, isTrue, reason: additive.failure?.detail);
    expect(additive.envelope!.schemaMinor, 2);
    expect(additive.envelope!.extensions.containsKey('future_optional_hint'), isTrue);

    final malformed = decodeObservableDeltaBytes(
      readObservableTopologyFixtureBytes('delta/malformed.json'),
    );
    expect(malformed.isOk, isTrue, reason: malformed.failure?.detail);
  });

  test('unsupported major yields unsupported-delta before unknown capability', () {
    final first = decodeObservableDeltaBytes(
      readObservableTopologyFixtureBytes('delta/unsupported.json'),
    );
    final second = decodeObservableDeltaBytes(
      readObservableTopologyFixtureBytes('delta/unsupported.json'),
    );
    expect(first.isOk, isFalse);
    expect(first.failure!.reason, ObservableReasonCodeWire.unsupportedDelta);
    expect(first.failure!.subcode, ObservableDeltaSubcode.majorIncompatible);
    expect(second.failure!.subcode, ObservableDeltaSubcode.majorIncompatible);
  });

  test('vityo decode negatives yield named subcodes twice', () {
    const cases = <String, ObservableDeltaSubcode>{
      'vityo/delta/unknown-op.json': ObservableDeltaSubcode.unknownOp,
      'vityo/delta/unknown-category.json': ObservableDeltaSubcode.unknownCategory,
    };
    cases.forEach((path, subcode) {
      final first = decodeObservableDeltaBytes(
        readObservableTopologyFixtureBytes(path),
      );
      final second = decodeObservableDeltaBytes(
        readObservableTopologyFixtureBytes(path),
      );
      expect(first.isOk, isFalse, reason: path);
      expect(first.failure!.subcode, subcode, reason: path);
      expect(second.failure!.subcode, subcode);
    });
  });

  test('apply-time vityo negatives still decode', () {
    const paths = <String>[
      'vityo/delta/wrong-parent.json',
      'vityo/delta/target-mismatch.json',
      'vityo/delta/before-mismatch.json',
      'vityo/delta/key-mismatch.json',
      'vityo/delta/duplicate-key.json',
      'vityo/delta/missing-record.json',
      'vityo/delta/unknown-metadata-field.json',
      'vityo/delta/lineage-prior-unresolved.json',
    ];
    for (final path in paths) {
      final decoded = decodeObservableDeltaBytes(
        readObservableTopologyFixtureBytes(path),
      );
      expect(decoded.isOk, isTrue, reason: '$path: ${decoded.failure?.detail}');
    }
  });
}
