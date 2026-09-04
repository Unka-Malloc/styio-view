import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  Map<String, ObservableInvalidSubcode> invalidSubcodes() {
    return const <String, ObservableInvalidSubcode>{
      'unsupported-contract.json': ObservableInvalidSubcode.unsupportedContract,
      'unsupported-schema.json': ObservableInvalidSubcode.unsupportedSchemaVersion,
      'missing-field.json': ObservableInvalidSubcode.missingField,
      'duplicate-id.json': ObservableInvalidSubcode.duplicateId,
      'dangling-reference.json': ObservableInvalidSubcode.danglingReference,
      'cyclic-evidence.json': ObservableInvalidSubcode.evidenceCycle,
      'unsupported-completeness.json':
          ObservableInvalidSubcode.unsupportedCompleteness,
      'missing-capability.json': ObservableInvalidSubcode.missingCapability,
    };
  }

  test('canonical and additive fixtures decode identically twice', () {
    for (final name in <String>['canonical.json', 'additive-field.json']) {
      final first = decodeObservableSnapshotJson(readObservableFixture(name));
      final second = decodeObservableSnapshotJson(readObservableFixture(name));
      expect(first.isOk, isTrue, reason: '$name: ${first.failure?.detail}');
      expect(second.isOk, isTrue);
      expect(first.snapshot!.nodes.length, second.snapshot!.nodes.length);
      expect(first.snapshot!.edges.length, second.snapshot!.edges.length);
      expect(first.snapshot!.root, 'n1_2eb67a1f3dc860ba2e80cda57f70c729');
    }

    final canonical = decodeObservableSnapshotJson(
      readObservableFixture('canonical.json'),
    ).snapshot!;
    final additive = decodeObservableSnapshotJson(
      readObservableFixture('additive-field.json'),
    ).snapshot!;
    expect(canonical.nodes.length, additive.nodes.length);
    expect(
      canonical.edges.map((edge) => edge.id).toList(),
      additive.edges.map((edge) => edge.id).toList(),
    );
    expect(additive.extensions.containsKey('consumer_note'), isTrue);
    expect(canonical.extensions.containsKey('consumer_note'), isFalse);

    final authoredAdditive = decodeObservableSnapshotJson(
      readObservableFixture('additive-fields.json'),
    );
    expect(authoredAdditive.isOk, isTrue);
    expect(
      authoredAdditive.snapshot!.extensions.containsKey('future_consumer_hint'),
      isTrue,
    );
  });

  test('scalar-noop fixture decodes with a null root and empty collections', () {
    final first = decodeObservableSnapshotJson(
      readObservableFixture('proven-scalar-noop.json'),
    );
    final second = decodeObservableSnapshotJson(
      readObservableFixture('proven-scalar-noop.json'),
    );
    expect(first.isOk, isTrue, reason: first.failure?.detail);
    expect(second.isOk, isTrue);
    expect(first.snapshot!.completeness, ObservableCompleteness.provenScalarNoop);
    expect(first.snapshot!.root, isNull);
    expect(first.snapshot!.nodes, isEmpty);
  });

  test('every invalid fixture yields invalid-snapshot with its subcode twice', () {
    invalidSubcodes().forEach((name, subcode) {
      final first = decodeObservableSnapshotJson(readObservableFixture(name));
      final second = decodeObservableSnapshotJson(readObservableFixture(name));
      expect(first.isOk, isFalse, reason: name);
      expect(first.failure!.reason, ObservableReasonCode.invalidSnapshot);
      expect(first.failure!.subcode, subcode, reason: name);
      expect(second.failure!.subcode, subcode);
    });
  });

  test('child fixtures decode typed lineage and diagnostics', () {
    const children = <String>[
      'unchanged.json',
      'field-change.json',
      'add-diagnostic.json',
      'remove.json',
      'rename.json',
      'move.json',
      'split.json',
      'merge.json',
    ];
    for (final name in children) {
      final first = decodeObservableSnapshotBytes(
        readObservableTopologyFixtureBytes('child/$name'),
      );
      final second = decodeObservableSnapshotBytes(
        readObservableTopologyFixtureBytes('child/$name'),
      );
      expect(first.isOk, isTrue, reason: '$name: ${first.failure?.detail}');
      expect(second.isOk, isTrue);
      expect(first.snapshot!.lineage.length, second.snapshot!.lineage.length);
    }
    final add = decodeNamedTopologySnapshot('child/add-diagnostic.json');
    expect(add.diagnostics, isNotEmpty);
    final rename = decodeNamedTopologySnapshot('child/rename.json');
    expect(rename.lineage, isNotEmpty);
    expect(rename.lineage.first.kind, ObservableLineageKind.rename);
  });

  test('invalid lineage and dangling subjects fail closed', () {
    final cardinality = decodeObservableSnapshotBytes(
      readObservableTopologyFixtureBytes(
        'vityo/child/invalid-lineage-cardinality.json',
      ),
    );
    expect(cardinality.isOk, isFalse);
    expect(
      cardinality.failure!.subcode,
      ObservableInvalidSubcode.invalidLineage,
    );

    final danglingTarget = decodeObservableSnapshotBytes(
      readObservableTopologyFixtureBytes(
        'vityo/child/lineage-dangling-target.json',
      ),
    );
    expect(danglingTarget.failure!.subcode, ObservableInvalidSubcode.danglingReference);

    final danglingSubject = decodeObservableSnapshotBytes(
      readObservableTopologyFixtureBytes(
        'vityo/child/diagnostic-dangling-subject.json',
      ),
    );
    expect(
      danglingSubject.failure!.subcode,
      ObservableInvalidSubcode.danglingReference,
    );
  });
}
