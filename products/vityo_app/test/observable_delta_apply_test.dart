import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  const accepted = <String, String>{
    'unchanged.json': 'child/unchanged.json',
    'field-change.json': 'child/field-change.json',
    'add.json': 'child/add-diagnostic.json',
    'remove.json': 'child/remove.json',
    'rename.json': 'child/rename.json',
    'move.json': 'child/move.json',
    'split.json': 'child/split.json',
    'merge.json': 'child/merge.json',
  };

  List<int> parentBytes() =>
      readObservableTopologyFixtureBytes('parent/complete.json');

  String parentId() => observableSnapshotId(parentBytes());

  ObservableDeltaIntakeResult intake({
    required List<int> childBytes,
    required List<int>? deltaBytes,
    List<int>? headBytes,
    String? headSnapshotId,
    List<ObservableRetainedIdentity> retained = const <ObservableRetainedIdentity>[],
  }) {
    return intakeObservableDelta(
      ObservableDeltaIntakeInput(
        childBytes: childBytes,
        childSnapshotId: observableSnapshotId(childBytes),
        deltaBytes: deltaBytes,
        headBytes: headBytes ?? parentBytes(),
        headSnapshotId: headSnapshotId ?? parentId(),
        retained: retained,
      ),
    );
  }

  test('every accepted delta reconstructs its child bytes and identity', () {
    accepted.forEach((deltaName, childPath) {
      final deltaBytes = readObservableTopologyFixtureBytes('delta/$deltaName');
      final childBytes = readObservableTopologyFixtureBytes(childPath);
      final decoded = decodeObservableDeltaBytes(deltaBytes).envelope!;
      final applied = applyObservableDelta(parentBytes(), decoded);
      expect(applied.isOk, isTrue, reason: deltaName);
      expect(applied.bytes, childBytes, reason: deltaName);
      expect(
        observableSnapshotId(applied.bytes!),
        decoded.targetSnapshotId,
        reason: deltaName,
      );

      final result = intake(childBytes: childBytes, deltaBytes: deltaBytes);
      expect(result.accepted, isTrue, reason: '$deltaName ${result.detail}');
      expect(result.usedDelta, isTrue);
      expect(result.childIdentity!.snapshotId, decoded.targetSnapshotId);
    });
  });

  test('unchanged reconstructs the parent and malformed rejects at apply', () {
    final unchanged = readObservableTopologyFixtureBytes('delta/unchanged.json');
    final result = intake(childBytes: parentBytes(), deltaBytes: unchanged);
    expect(result.accepted, isTrue);
    expect(result.reconstructedBytes, parentBytes());

    final malformed = decodeObservableDeltaBytes(
      readObservableTopologyFixtureBytes('delta/malformed.json'),
    ).envelope!;
    final applied = applyObservableDelta(parentBytes(), malformed);
    expect(applied.isOk, isFalse);
    expect(applied.rejection!.subcode, ObservableDeltaSubcode.missingRecord);
  });

  test('negative deltas yield named reasons and leave the parent untouched', () {
    const cases = <String, (ObservableReasonCode, ObservableDeltaSubcode?)>{
      'vityo/delta/wrong-parent.json': (
        ObservableReasonCode.wrongParent,
        null,
      ),
      'vityo/delta/target-mismatch.json': (
        ObservableReasonCode.invalidDelta,
        ObservableDeltaSubcode.targetMismatch,
      ),
      'vityo/delta/before-mismatch.json': (
        ObservableReasonCode.malformedDelta,
        ObservableDeltaSubcode.beforeMismatch,
      ),
      'vityo/delta/key-mismatch.json': (
        ObservableReasonCode.malformedDelta,
        ObservableDeltaSubcode.keyMismatch,
      ),
      'vityo/delta/duplicate-key.json': (
        ObservableReasonCode.malformedDelta,
        ObservableDeltaSubcode.duplicateKey,
      ),
      'vityo/delta/missing-record.json': (
        ObservableReasonCode.malformedDelta,
        ObservableDeltaSubcode.missingRecord,
      ),
      'vityo/delta/unknown-metadata-field.json': (
        ObservableReasonCode.malformedDelta,
        ObservableDeltaSubcode.unknownMetadataField,
      ),
      'vityo/delta/lineage-prior-unresolved.json': (
        ObservableReasonCode.malformedDelta,
        ObservableDeltaSubcode.lineagePriorUnresolved,
      ),
    };
    cases.forEach((path, expected) {
      final deltaBytes = readObservableTopologyFixtureBytes(path);
      final childBytes = readObservableTopologyFixtureBytes(
        'child/field-change.json',
      );
      final result = intake(childBytes: childBytes, deltaBytes: deltaBytes);
      expect(result.accepted, isFalse, reason: path);
      expect(result.reason, expected.$1, reason: path);
      if (expected.$2 != null) {
        expect(result.subcode, expected.$2, reason: path);
      }
    });

    final unsupported = intake(
      childBytes: readObservableTopologyFixtureBytes('child/field-change.json'),
      deltaBytes: readObservableTopologyFixtureBytes('delta/unsupported.json'),
    );
    expect(unsupported.reason, ObservableReasonCode.unsupportedDelta);
    expect(unsupported.subcode, ObservableDeltaSubcode.majorIncompatible);

    final unknownOp = intake(
      childBytes: readObservableTopologyFixtureBytes('child/field-change.json'),
      deltaBytes: readObservableTopologyFixtureBytes('vityo/delta/unknown-op.json'),
    );
    expect(unknownOp.reason, ObservableReasonCode.malformedDelta);
    expect(unknownOp.subcode, ObservableDeltaSubcode.unknownOp);
  });

  test('duplicate stale and out-of-order classify over the retained window', () {
    final parent = parentBytes();
    final child = readObservableTopologyFixtureBytes('child/field-change.json');
    final delta = readObservableTopologyFixtureBytes('delta/field-change.json');
    final first = intake(childBytes: child, deltaBytes: delta);
    expect(first.accepted, isTrue);
    final childId = first.childIdentity!.snapshotId;
    final retained = <ObservableRetainedIdentity>[
      ObservableRetainedIdentity(
        snapshotId: parentId(),
      ),
      ObservableRetainedIdentity(
        snapshotId: childId,
        parentSnapshotId: parentId(),
      ),
    ];

    final duplicate = intakeObservableDelta(
      ObservableDeltaIntakeInput(
        childBytes: child,
        childSnapshotId: childId,
        deltaBytes: delta,
        headBytes: child,
        headSnapshotId: childId,
        retained: retained,
      ),
    );
    expect(duplicate.reason, ObservableReasonCode.duplicateDelta);

    final stale = intakeObservableDelta(
      ObservableDeltaIntakeInput(
        childBytes: readObservableTopologyFixtureBytes('child/rename.json'),
        childSnapshotId: observableSnapshotId(
          readObservableTopologyFixtureBytes('child/rename.json'),
        ),
        deltaBytes: readObservableTopologyFixtureBytes('delta/rename.json'),
        headBytes: child,
        headSnapshotId: childId,
        retained: retained,
      ),
    );
    expect(stale.reason, ObservableReasonCode.staleDelta);

    final outOfOrder = intakeObservableDelta(
      ObservableDeltaIntakeInput(
        childBytes: parent,
        childSnapshotId: parentId(),
        deltaBytes: readObservableTopologyFixtureBytes('delta/unchanged.json'),
        headBytes: child,
        headSnapshotId: childId,
        retained: retained,
      ),
    );
    expect(outOfOrder.reason, ObservableReasonCode.outOfOrderDelta);

    final unknownParent = intakeObservableDelta(
      ObservableDeltaIntakeInput(
        childBytes: child,
        childSnapshotId: childId,
        deltaBytes: readObservableTopologyFixtureBytes(
          'vityo/delta/wrong-parent.json',
        ),
        headBytes: child,
        headSnapshotId: childId,
        retained: retained,
      ),
    );
    expect(unknownParent.reason, ObservableReasonCode.wrongParent);
  });

  test('published child mismatch yields reconstruction-mismatch', () {
    final delta = readObservableTopologyFixtureBytes('delta/field-change.json');
    final result = intake(
      childBytes: parentBytes(),
      deltaBytes: delta,
    );
    expect(result.reason, ObservableReasonCode.invalidDelta);
    expect(result.subcode, ObservableDeltaSubcode.reconstructionMismatch);
  });

  test('minor-additive empty operations reconstruct the parent', () {
    final delta = readObservableTopologyFixtureBytes(
      'vityo/delta/unsupported-minor-additive.json',
    );
    final result = intake(childBytes: parentBytes(), deltaBytes: delta);
    expect(result.accepted, isTrue, reason: result.detail);
    expect(result.reconstructedBytes, parentBytes());
  });

  test('non-ASCII and control characters round-trip byte-for-byte', () {
    // The producer emits raw UTF-8 for everything except the eight named
    // escapes and control characters, which it writes as lowercase \u00xx.
    // Anchor paths are file paths, so they can carry non-ASCII text. The
    // expected child literal below is written exactly the way the Styio
    // canonical writer would emit it.
    const parentJson =
        r'{"contract":"styio.observable.static-snapshot","schema_version":1,"stability":"incubating","producer":{"name":"styio","version":"0.0.1"},"capabilities":["file-source-anchors","producer-evidence","static-topology-edges","static-topology-facts","static-topology-nodes"],"compilation_unit":{"package_name":"example.app","manifest_path":"Styio.toml","entry_path":"src/main.styio"},"completeness":"complete/validated-topology","root":"n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","nodes":[{"id":"n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","kind":"Program","role":"Program","anchors":["a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"],"evidence":"v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"}],"edges":[],"facts":[{"id":"f1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","subject":"n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","predicate":"note","value":"a\u000bb","evidence":"v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"}],"anchors":[{"ref":"a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","path":"src/mañana.styio","precision":"file"}],"evidence":[{"ref":"v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","producer_rule":"styio.sema.topology.node.Program","rule_version":"1","subjects":["n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"],"prerequisites":[],"anchors":["a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"]}]}';
    const childJson =
        r'{"contract":"styio.observable.static-snapshot","schema_version":1,"stability":"incubating","producer":{"name":"styio","version":"0.0.1"},"capabilities":["file-source-anchors","producer-evidence","static-topology-edges","static-topology-facts","static-topology-nodes"],"compilation_unit":{"package_name":"example.app","manifest_path":"Styio.toml","entry_path":"src/main.styio"},"completeness":"complete/validated-topology","root":"n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","nodes":[{"id":"n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","kind":"Program","role":"Program","anchors":["a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"],"evidence":"v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"}],"edges":[],"facts":[{"id":"f1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","subject":"n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","predicate":"note","value":"a\u000bc","evidence":"v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"}],"anchors":[{"ref":"a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","path":"src/東京.styio","precision":"file"}],"evidence":[{"ref":"v1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","producer_rule":"styio.sema.topology.node.Program","rule_version":"1","subjects":["n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"],"prerequisites":[],"anchors":["a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0"]}]}';
    final parentBytes = utf8.encode('$parentJson\n');
    final childBytes = utf8.encode('$childJson\n');
    final parentId = observableSnapshotId(parentBytes);
    final targetId = observableSnapshotId(childBytes);
    final deltaJson =
        '{"contract":"styio.observable.delta","schema_version":{"major":0,"minor":1},"stability":"incubating","parent_snapshot_id":"$parentId","target_snapshot_id":"$targetId","required_capabilities":["file-source-anchors","producer-evidence","static-topology-edges","static-topology-facts","static-topology-nodes"],"optional_capabilities":["snapshot-delta"],"operations":[{"op":"replace_fields","category":"facts","key":"f1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","fields":[{"name":"value","before":"a\\u000bb","after":"a\\u000bc"}]},{"op":"replace_fields","category":"anchors","key":"a1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0","fields":[{"name":"path","before":"src/mañana.styio","after":"src/東京.styio"}]}]}';

    final delta = decodeObservableDeltaJson(deltaJson).envelope!;
    final applied = applyObservableDelta(parentBytes, delta);
    expect(applied.isOk, isTrue, reason: applied.rejection?.detail);
    expect(applied.bytes, childBytes);
    final decoded = utf8.decode(applied.bytes!);
    expect(decoded, contains('src/東京.styio'));
    expect(decoded, isNot(contains(r'\u6771')));
    expect(decoded, contains(r'"value":"a\u000bc"'));

    final result = intakeObservableDelta(
      ObservableDeltaIntakeInput(
        childBytes: childBytes,
        childSnapshotId: targetId,
        deltaBytes: utf8.encode(deltaJson),
        headBytes: parentBytes,
        headSnapshotId: parentId,
      ),
    );
    expect(result.accepted, isTrue, reason: result.detail);
    expect(result.usedDelta, isTrue);
    expect(result.child!.anchors.first.path, 'src/東京.styio');
  });
}
