import 'observable_snapshot_model.dart';

abstract class ObservableChangeSource {
  ObservableChangeSet? compare(
    ObservableSnapshot previous,
    ObservableSnapshot current,
  );
}

class IdSetComparisonChangeSource implements ObservableChangeSource {
  const IdSetComparisonChangeSource();

  @override
  ObservableChangeSet? compare(
    ObservableSnapshot previous,
    ObservableSnapshot current,
  ) {
    if (previous.compilationUnit != current.compilationUnit) {
      return null;
    }
    final previousNodes = previous.nodeIds;
    final currentNodes = current.nodeIds;
    final previousEdges = previous.edgeIds;
    final currentEdges = current.edgeIds;
    return ObservableChangeSet(
      addedNodeIds: _sortedDiff(currentNodes, previousNodes),
      removedNodeIds: _sortedDiff(previousNodes, currentNodes),
      addedEdgeIds: _sortedDiff(currentEdges, previousEdges),
      removedEdgeIds: _sortedDiff(previousEdges, currentEdges),
    );
  }
}

GraphProjection projectObservableGraph({
  required ObservableSnapshot current,
  ObservableSnapshot? previous,
  ObservableChangeSet? changeSet,
}) {
  final addedNodes = <String>{...?changeSet?.addedNodeIds};
  final removedNodes = <String>{...?changeSet?.removedNodeIds};
  final addedEdges = <String>{...?changeSet?.addedEdgeIds};
  final removedEdges = <String>{...?changeSet?.removedEdgeIds};

  final nodes = <ProjectedGraphNode>[];
  final currentFacts = _factsBySubject(current);
  for (final node in current.nodes) {
    nodes.add(
      _projectNode(
        snapshot: current,
        factsBySubject: currentFacts,
        node: node,
        tag: addedNodes.contains(node.id)
            ? GraphItemChangeTag.added
            : GraphItemChangeTag.unchanged,
      ),
    );
  }
  if (previous != null) {
    final previousFacts = _factsBySubject(previous);
    for (final node in previous.nodes) {
      if (removedNodes.contains(node.id)) {
        nodes.add(
          _projectNode(
            snapshot: previous,
            factsBySubject: previousFacts,
            node: node,
            tag: GraphItemChangeTag.removed,
          ),
        );
      }
    }
  }

  final edges = <ProjectedGraphEdge>[];
  for (final edge in current.edges) {
    edges.add(
      ProjectedGraphEdge(
        id: edge.id,
        kind: edge.kind,
        rawKind: edge.rawKind,
        from: edge.from,
        to: edge.to,
        changeTag: addedEdges.contains(edge.id)
            ? GraphItemChangeTag.added
            : GraphItemChangeTag.unchanged,
        evidenceRef: edge.evidence,
      ),
    );
  }
  if (previous != null) {
    for (final edge in previous.edges) {
      if (removedEdges.contains(edge.id)) {
        edges.add(
          ProjectedGraphEdge(
            id: edge.id,
            kind: edge.kind,
            rawKind: edge.rawKind,
            from: edge.from,
            to: edge.to,
            changeTag: GraphItemChangeTag.removed,
            evidenceRef: edge.evidence,
          ),
        );
      }
    }
  }

  final anchors = <ObservableAnchorRecord>[...current.anchors];
  final evidence = <ObservableEvidenceRecord>[...current.evidence];
  if (previous != null) {
    final anchorRefs = anchors.map((anchor) => anchor.ref).toSet();
    for (final anchor in previous.anchors) {
      if (anchorRefs.add(anchor.ref)) {
        anchors.add(anchor);
      }
    }
    final evidenceRefs = evidence.map((record) => record.ref).toSet();
    for (final record in previous.evidence) {
      if (evidenceRefs.add(record.ref)) {
        evidence.add(record);
      }
    }
  }

  nodes.sort((left, right) => left.id.compareTo(right.id));
  edges.sort((left, right) => left.id.compareTo(right.id));
  return GraphProjection(
    nodes: List<ProjectedGraphNode>.unmodifiable(nodes),
    edges: List<ProjectedGraphEdge>.unmodifiable(edges),
    anchors: List<ObservableAnchorRecord>.unmodifiable(anchors),
    evidence: List<ObservableEvidenceRecord>.unmodifiable(evidence),
    compilationUnit: current.compilationUnit,
    root: current.root,
  );
}

Map<String, List<ObservableFactRecord>> _factsBySubject(
  ObservableSnapshot snapshot,
) {
  final bySubject = <String, List<ObservableFactRecord>>{};
  for (final fact in snapshot.facts) {
    bySubject.putIfAbsent(fact.subject, () => <ObservableFactRecord>[]).add(fact);
  }
  return bySubject;
}

ProjectedGraphNode _projectNode({
  required ObservableSnapshot snapshot,
  required Map<String, List<ObservableFactRecord>> factsBySubject,
  required ObservableNodeRecord node,
  required GraphItemChangeTag tag,
}) {
  return ProjectedGraphNode(
    id: node.id,
    kind: node.kind,
    rawKind: node.rawKind,
    role: node.role,
    groupKey: groupKeyForNode(snapshot, node),
    changeTag: tag,
    anchorRefs: node.anchors,
    facts: factsBySubject[node.id] ?? const <ObservableFactRecord>[],
    evidenceRef: node.evidence,
    sourceSnapshot: snapshot,
  );
}

String groupKeyForNode(ObservableSnapshot snapshot, ObservableNodeRecord node) {
  if (node.anchors.isEmpty) {
    return kObservableUnanchoredGroupKey;
  }
  final anchor = snapshot.anchorByRef(node.anchors.first);
  if (anchor == null || anchor.path.isEmpty) {
    return kObservableUnanchoredGroupKey;
  }
  return anchor.path;
}

List<String> _sortedDiff(Set<String> left, Set<String> right) {
  final diff = left.difference(right).toList()..sort();
  return List<String>.unmodifiable(diff);
}

List<ObservableEvidenceRecord> walkEvidenceChain({
  required GraphProjection projection,
  required String startRef,
}) {
  final seen = <String>{};
  final chain = <ObservableEvidenceRecord>[];
  void visit(String ref) {
    if (!seen.add(ref)) {
      return;
    }
    final record = projection.evidenceByRef(ref);
    if (record == null) {
      return;
    }
    chain.add(record);
    for (final prerequisite in record.prerequisites) {
      visit(prerequisite);
    }
  }

  visit(startRef);
  return chain;
}
