import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  GraphProjection projectionFrom(ObservableSnapshot snapshot) {
    return projectObservableGraph(current: snapshot);
  }

  GraphProjection permute(GraphProjection projection) {
    return GraphProjection(
      nodes: [...projection.nodes].reversed.toList(),
      edges: [...projection.edges].reversed.toList(),
      anchors: projection.anchors,
      evidence: projection.evidence,
      compilationUnit: projection.compilationUnit,
      root: projection.root,
    );
  }

  test('canonical and permuted projections produce identical layout', () async {
    final snapshot = decodeCanonicalFixture();
    final projection = projectionFrom(snapshot);
    final first = await computeObservableGraphLayout(
      ObservableLayoutRequest(projection: projection),
    );
    final second = await computeObservableGraphLayout(
      ObservableLayoutRequest(projection: permute(projection)),
    );
    expect(first.isOk, isTrue);
    expect(second.isOk, isTrue);
    expect(first.layout!.fingerprint(), second.layout!.fingerprint());
    for (final node in projection.nodes) {
      final rect = first.layout!.nodeRects[node.id]!;
      final group = first.layout!.groupRects[node.groupKey]!;
      expect(group.containsRect(rect), isTrue, reason: node.id);
    }
    final groups = first.layout!.groupRects.values.toList();
    for (var i = 0; i < groups.length; i += 1) {
      for (var j = i + 1; j < groups.length; j += 1) {
        expect(groups[i].intersects(groups[j]), isFalse);
      }
    }
  });

  test('large cyclic graph is deterministic and respects the node bound', () async {
    final kinds = ObservableNodeKindX.legendKinds;
    final edgeKinds = ObservableEdgeKindX.legendKinds;
    final nodes = <ProjectedGraphNode>[
      for (var i = 0; i < 3000; i += 1)
        ProjectedGraphNode(
          id: 'n${i.toString().padLeft(5, '0')}',
          kind: kinds[i % kinds.length],
          rawKind: kinds[i % kinds.length].wireValue,
          role: kinds[i % kinds.length].wireValue,
          groupKey: 'g${(i ~/ 50).toString().padLeft(3, '0')}',
          changeTag: GraphItemChangeTag.unchanged,
          anchorRefs: const <String>[],
          facts: const <ObservableFactRecord>[],
          evidenceRef: 'v',
        ),
    ];
    final edges = <ProjectedGraphEdge>[
      for (var i = 0; i < 3000; i += 1)
        ProjectedGraphEdge(
          id: 'e${i.toString().padLeft(5, '0')}',
          kind: i.isEven ? ObservableEdgeKind.mutation : ObservableEdgeKind.backpressure,
          rawKind: (i.isEven ? ObservableEdgeKind.mutation : ObservableEdgeKind.backpressure)
              .wireValue,
          from: nodes[i].id,
          to: nodes[(i + 17) % nodes.length].id,
          changeTag: GraphItemChangeTag.unchanged,
          evidenceRef: 'v',
        ),
      for (var i = 0; i < 200; i += 1)
        ProjectedGraphEdge(
          id: 'f${i.toString().padLeft(5, '0')}',
          kind: edgeKinds[i % edgeKinds.length],
          rawKind: edgeKinds[i % edgeKinds.length].wireValue,
          from: nodes[i].id,
          to: nodes[i + 1].id,
          changeTag: GraphItemChangeTag.unchanged,
          evidenceRef: 'v',
        ),
    ];
    final large = GraphProjection(
      nodes: nodes,
      edges: edges,
      anchors: const <ObservableAnchorRecord>[],
      evidence: const <ObservableEvidenceRecord>[],
    );
    final first = await computeObservableGraphLayout(
      ObservableLayoutRequest(projection: large),
    );
    final second = await computeObservableGraphLayout(
      ObservableLayoutRequest(projection: large),
    );
    expect(first.isOk, isTrue);
    expect(first.layout!.fingerprint(), second.layout!.fingerprint());

    final over = GraphProjection(
      nodes: [
        for (var i = 0; i < kObservableMaxRenderableNodes + 1; i += 1)
          ProjectedGraphNode(
            id: 'x$i',
            kind: ObservableNodeKind.value,
            rawKind: 'Value',
            role: 'Value',
            groupKey: kObservableUnanchoredGroupKey,
            changeTag: GraphItemChangeTag.unchanged,
            anchorRefs: const <String>[],
            facts: const <ObservableFactRecord>[],
            evidenceRef: 'v',
          ),
      ],
      edges: const <ProjectedGraphEdge>[],
      anchors: const <ObservableAnchorRecord>[],
      evidence: const <ObservableEvidenceRecord>[],
    );
    final bounded = layoutObservableGraph(ObservableLayoutRequest(projection: over));
    expect(bounded.isOk, isFalse);
    expect(bounded.reason, ObservableReasonCode.snapshotTooLarge);
    expect(bounded.nodeCount, kObservableMaxRenderableNodes + 1);
    expect(bounded.detail, contains('nodes='));
    expect(bounded.detail, contains('edges='));
  });
}
