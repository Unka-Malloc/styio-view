import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  const source = IdSetComparisonChangeSource();

  test('change set is exact and order-independent for one compilation unit', () {
    final previous = decodeAuthoredCanonicalFixture();
    final current = decodeObservableSnapshotJson(
      readObservableFixture('edited.json'),
    ).snapshot!;

    ObservableSnapshot permute(ObservableSnapshot snapshot) {
      return ObservableSnapshot(
        contract: snapshot.contract,
        schemaVersion: snapshot.schemaVersion,
        stability: snapshot.stability,
        producer: snapshot.producer,
        capabilities: snapshot.capabilities,
        compilationUnit: snapshot.compilationUnit,
        completeness: snapshot.completeness,
        root: snapshot.root,
        nodes: [...snapshot.nodes].reversed.toList(),
        edges: [...snapshot.edges].reversed.toList(),
        facts: snapshot.facts,
        anchors: snapshot.anchors,
        evidence: snapshot.evidence,
      );
    }

    final expected = source.compare(previous, current)!;
    final permuted = source.compare(permute(previous), permute(current))!;
    expect(expected.addedNodeIds, <String>['n1_0100000000000000000000000000000c']);
    expect(expected.removedNodeIds, <String>['n1_0100000000000000000000000000000a']);
    expect(expected.addedEdgeIds, <String>['e1_0200000000000000000000000000000c']);
    expect(expected.removedEdgeIds, <String>['e1_0200000000000000000000000000000a']);
    expect(permuted.addedNodeIds, expected.addedNodeIds);
    expect(permuted.removedNodeIds, expected.removedNodeIds);
    expect(permuted.addedEdgeIds, expected.addedEdgeIds);
    expect(permuted.removedEdgeIds, expected.removedEdgeIds);

    final projection = projectObservableGraph(
      current: current,
      previous: previous,
      changeSet: expected,
    );
    expect(
      projection.nodeById('n1_0100000000000000000000000000000c')!.changeTag,
      GraphItemChangeTag.added,
    );
    expect(
      projection.nodeById('n1_0100000000000000000000000000000a')!.changeTag,
      GraphItemChangeTag.removed,
    );
    expect(
      projection.nodeById('n1_01000000000000000000000000000001')!.changeTag,
      GraphItemChangeTag.unchanged,
    );
  });

  test('different compilation units yield no change set', () {
    final previous = decodeAuthoredCanonicalFixture();
    final current = ObservableSnapshot(
      contract: previous.contract,
      schemaVersion: previous.schemaVersion,
      stability: previous.stability,
      producer: previous.producer,
      capabilities: previous.capabilities,
      compilationUnit: const ObservableCompilationUnit(
        packageName: 'other.app',
        manifestPath: 'Styio.toml',
        entryPath: 'src/main.styio',
      ),
      completeness: previous.completeness,
      root: previous.root,
      nodes: previous.nodes,
      edges: previous.edges,
      facts: previous.facts,
      anchors: previous.anchors,
      evidence: previous.evidence,
    );
    expect(source.compare(previous, current), isNull);
  });

  test('producer delta change source matches fixture operations and tags', () {
    final parent = decodeNamedTopologySnapshot('parent/complete.json');

    void check(
      String deltaName,
      String childName,
      void Function(ObservableChangeSet set, GraphProjection projection) assertTags,
    ) {
      final child = decodeNamedTopologySnapshot(childName);
      final delta = decodeNamedTopologyDelta(deltaName);
      final source = ObservableDeltaChangeSource(
        delta: delta,
        lineage: child.lineage,
      );
      final set = source.compare(parent, child)!;
      expect(set.source, ObservableChangeSetSource.producerDelta);
      expect(set.operations.length, delta.operations.length);
      for (var i = 0; i < delta.operations.length; i += 1) {
        expect(set.operations[i].key, delta.operations[i].key);
        expect(set.operations[i].op, delta.operations[i].op);
        expect(set.operations[i].category, delta.operations[i].category);
      }
      final projection = projectObservableGraph(
        current: child,
        previous: parent,
        changeSet: set,
      );
      assertTags(set, projection);
    }

    check('delta/rename.json', 'child/rename.json', (set, projection) {
      expect(set.removedNodeIds, <String>['n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1']);
      expect(set.addedNodeIds, <String>['n1_ccccccccccccccccccccccccccccccc1']);
      expect(set.renamedCount, 1);
      expect(projection.lineageLinks, isEmpty);
      expect(
        projection.nodeById('n1_ccccccccccccccccccccccccccccccc1')!.continuity!.kind,
        ObservableLineageKind.rename,
      );
      expect(
        projection.nodeById('n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1'),
        isNull,
      );
    });
    check('delta/field-change.json', 'child/field-change.json', (set, projection) {
      expect(set.changedNodeIds, <String>['n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1']);
      expect(set.addedNodeIds, isEmpty);
      expect(set.removedNodeIds, isEmpty);
      expect(set.lineage, isEmpty);
      expect(
        projection.nodeById('n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1')!.changeTag,
        GraphItemChangeTag.changed,
      );
    });
    check('delta/split.json', 'child/split.json', (set, projection) {
      expect(set.addedNodeIds.length, 2);
      expect(set.splitCount, 1);
      expect(projection.lineageLinks, isNotEmpty);
    });
    check('delta/merge.json', 'child/merge.json', (set, projection) {
      expect(set.removedNodeIds, contains('n1_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb2'));
      expect(set.mergedCount, 1);
      expect(projection.lineageLinks, isNotEmpty);
    });
    check('delta/add.json', 'child/add-diagnostic.json', (set, projection) {
      expect(set.changedNodeIds, <String>['n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1']);
      expect(
        projection.nodeById('n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa1')!.changeTag,
        GraphItemChangeTag.changed,
      );
    });
    check('delta/unchanged.json', 'child/unchanged.json', (set, projection) {
      expect(set.isEmpty, isTrue);
    });
  });
}
