import 'observable_delta_model.dart';
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
      source: ObservableChangeSetSource.idSetComparison,
      addedNodeIds: _sortedDiff(currentNodes, previousNodes),
      removedNodeIds: _sortedDiff(previousNodes, currentNodes),
      addedEdgeIds: _sortedDiff(currentEdges, previousEdges),
      removedEdgeIds: _sortedDiff(previousEdges, currentEdges),
    );
  }
}

class ObservableDeltaChangeSource implements ObservableChangeSource {
  const ObservableDeltaChangeSource({
    required this.delta,
    required this.lineage,
  });

  final ObservableDeltaEnvelope delta;
  final List<ObservableLineageRecord> lineage;

  @override
  ObservableChangeSet? compare(
    ObservableSnapshot previous,
    ObservableSnapshot current,
  ) {
    if (previous.compilationUnit != current.compilationUnit) {
      return null;
    }
    final addedNodes = <String>{};
    final removedNodes = <String>{};
    final changedNodes = <String>{};
    final addedEdges = <String>{};
    final removedEdges = <String>{};
    final changedEdges = <String>{};
    final metadata = <ObservableMetadataChange>[];

    void tagNode(String id, {required bool added, required bool removed}) {
      if (added) {
        addedNodes.add(id);
        changedNodes.remove(id);
      } else if (removed) {
        removedNodes.add(id);
        changedNodes.remove(id);
      } else if (!addedNodes.contains(id) && !removedNodes.contains(id)) {
        changedNodes.add(id);
      }
    }

    void tagEdge(String id, {required bool added, required bool removed}) {
      if (added) {
        addedEdges.add(id);
        changedEdges.remove(id);
      } else if (removed) {
        removedEdges.add(id);
        changedEdges.remove(id);
      } else if (!addedEdges.contains(id) && !removedEdges.contains(id)) {
        changedEdges.add(id);
      }
    }

    for (final operation in delta.operations) {
      switch (operation.category) {
        case ObservableDeltaCategory.nodes:
          tagNode(
            operation.key,
            added: operation.op == ObservableDeltaOp.add,
            removed: operation.op == ObservableDeltaOp.remove,
          );
        case ObservableDeltaCategory.edges:
          tagEdge(
            operation.key,
            added: operation.op == ObservableDeltaOp.add,
            removed: operation.op == ObservableDeltaOp.remove,
          );
        case ObservableDeltaCategory.facts:
          final String? factSubject;
          if (operation.op == ObservableDeltaOp.remove) {
            factSubject = previous.factById(operation.key)?.subject;
          } else if (operation.op == ObservableDeltaOp.add) {
            final value = operation.record?['subject'];
            factSubject = value is String ? value : null;
          } else {
            factSubject = current.factById(operation.key)?.subject;
          }
          if (factSubject != null) {
            tagNode(factSubject, added: false, removed: false);
          }
        case ObservableDeltaCategory.anchors:
          if (operation.op == ObservableDeltaOp.replaceFields) {
            for (final node in current.nodes) {
              if (node.anchors.contains(operation.key)) {
                tagNode(node.id, added: false, removed: false);
              }
            }
          }
        case ObservableDeltaCategory.evidence:
          if (operation.op == ObservableDeltaOp.replaceFields) {
            final record = current.evidenceByRef(operation.key);
            if (record != null) {
              for (final subject in record.subjects) {
                if (current.nodeIds.contains(subject)) {
                  tagNode(subject, added: false, removed: false);
                } else if (current.edgeIds.contains(subject)) {
                  tagEdge(subject, added: false, removed: false);
                }
              }
            }
          }
        case ObservableDeltaCategory.diagnostics:
          final String? diagnosticSubject;
          if (operation.op == ObservableDeltaOp.remove) {
            diagnosticSubject = previous.diagnosticById(operation.key)?.subject;
          } else if (operation.op == ObservableDeltaOp.add) {
            final value = operation.record?['subject'];
            diagnosticSubject = value is String ? value : null;
          } else {
            diagnosticSubject = current.diagnosticById(operation.key)?.subject;
          }
          if (diagnosticSubject != null) {
            if (current.nodeIds.contains(diagnosticSubject) ||
                previous.nodeIds.contains(diagnosticSubject)) {
              tagNode(diagnosticSubject, added: false, removed: false);
            } else {
              tagEdge(diagnosticSubject, added: false, removed: false);
            }
          }
        case ObservableDeltaCategory.metadata:
          for (final field in operation.fields) {
            metadata.add(
              ObservableMetadataChange(
                field: field.name,
                before: field.before,
                after: field.after,
              ),
            );
          }
        case ObservableDeltaCategory.lineage:
          break;
      }
    }

    return ObservableChangeSet(
      source: ObservableChangeSetSource.producerDelta,
      operations: delta.operations,
      addedNodeIds: _sorted(addedNodes),
      removedNodeIds: _sorted(removedNodes),
      addedEdgeIds: _sorted(addedEdges),
      removedEdgeIds: _sorted(removedEdges),
      changedNodeIds: _sorted(changedNodes),
      changedEdgeIds: _sorted(changedEdges),
      metadataChanges: List<ObservableMetadataChange>.unmodifiable(metadata),
      lineage: List<ObservableLineageRecord>.unmodifiable(lineage),
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
  final changedNodes = <String>{...?changeSet?.changedNodeIds};
  final addedEdges = <String>{...?changeSet?.addedEdgeIds};
  final removedEdges = <String>{...?changeSet?.removedEdgeIds};
  final changedEdges = <String>{...?changeSet?.changedEdgeIds};
  final lineage = changeSet?.lineage ?? current.lineage;
  final suppressedGhosts = <String>{};
  final continuityById = <String, ObservableContinuityMark>{};
  final lineageLinks = <ObservableLineageLink>[];

  for (final record in lineage) {
    final mark = ObservableContinuityMark(
      kind: record.kind,
      lineageId: record.id,
      priorIds: record.prior,
      evidenceRefs: record.evidence,
    );
    final oneToOne =
        (record.kind == ObservableLineageKind.rename ||
            record.kind == ObservableLineageKind.move) &&
        record.prior.length == 1 &&
        record.target.length == 1 &&
        removedNodes.contains(record.prior.single) &&
        addedNodes.contains(record.target.single);
    if (oneToOne) {
      suppressedGhosts.add(record.prior.single);
      continuityById[record.target.single] = mark;
    } else {
      for (final prior in record.prior) {
        continuityById[prior] = mark;
      }
      for (final target in record.target) {
        continuityById[target] = mark;
      }
      for (final prior in record.prior) {
        for (final target in record.target) {
          lineageLinks.add(
            ObservableLineageLink(
              fromId: prior,
              toId: target,
              lineageId: record.id,
              kind: record.kind,
            ),
          );
        }
      }
    }
  }

  GraphItemChangeTag nodeTag(String id) {
    if (addedNodes.contains(id)) {
      return GraphItemChangeTag.added;
    }
    if (removedNodes.contains(id)) {
      return GraphItemChangeTag.removed;
    }
    if (changedNodes.contains(id)) {
      return GraphItemChangeTag.changed;
    }
    return GraphItemChangeTag.unchanged;
  }

  GraphItemChangeTag edgeTag(String id) {
    if (addedEdges.contains(id)) {
      return GraphItemChangeTag.added;
    }
    if (removedEdges.contains(id)) {
      return GraphItemChangeTag.removed;
    }
    if (changedEdges.contains(id)) {
      return GraphItemChangeTag.changed;
    }
    return GraphItemChangeTag.unchanged;
  }

  final nodes = <ProjectedGraphNode>[];
  final currentFacts = _factsBySubject(current);
  for (final node in current.nodes) {
    final mark = continuityById[node.id];
    nodes.add(
      _projectNode(
        snapshot: current,
        factsBySubject: currentFacts,
        node: node,
        tag: nodeTag(node.id),
        continuity: mark,
        layoutKey: mark != null &&
                (mark.kind == ObservableLineageKind.rename ||
                    mark.kind == ObservableLineageKind.move) &&
                mark.priorIds.length == 1
            ? mark.priorIds.single
            : null,
      ),
    );
  }
  if (previous != null) {
    final previousFacts = _factsBySubject(previous);
    for (final node in previous.nodes) {
      if (removedNodes.contains(node.id) && !suppressedGhosts.contains(node.id)) {
        nodes.add(
          _projectNode(
            snapshot: previous,
            factsBySubject: previousFacts,
            node: node,
            tag: GraphItemChangeTag.removed,
            continuity: continuityById[node.id],
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
        changeTag: edgeTag(edge.id),
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
  lineageLinks.sort((left, right) {
    final from = left.fromId.compareTo(right.fromId);
    if (from != 0) {
      return from;
    }
    return left.toId.compareTo(right.toId);
  });
  return GraphProjection(
    nodes: List<ProjectedGraphNode>.unmodifiable(nodes),
    edges: List<ProjectedGraphEdge>.unmodifiable(edges),
    anchors: List<ObservableAnchorRecord>.unmodifiable(anchors),
    evidence: List<ObservableEvidenceRecord>.unmodifiable(evidence),
    compilationUnit: current.compilationUnit,
    root: current.root,
    lineageLinks: List<ObservableLineageLink>.unmodifiable(lineageLinks),
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
  ObservableContinuityMark? continuity,
  String? layoutKey,
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
    continuity: continuity,
    layoutKey: layoutKey,
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
  return _sorted(left.difference(right));
}

List<String> _sorted(Set<String> values) {
  final items = values.toList()..sort();
  return List<String>.unmodifiable(items);
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
