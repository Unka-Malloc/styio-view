import 'package:flutter/foundation.dart';

import 'observable_snapshot_model.dart';

class ObservableLayoutRequest {
  const ObservableLayoutRequest({
    required this.projection,
    this.maxRenderableNodes = kObservableMaxRenderableNodes,
  });

  final GraphProjection projection;
  final int maxRenderableNodes;
}

Future<ObservableLayoutOutcome> computeObservableGraphLayout(
  ObservableLayoutRequest request,
) {
  return compute(layoutObservableGraph, request);
}

ObservableLayoutOutcome layoutObservableGraph(ObservableLayoutRequest request) {
  final projection = request.projection;
  final nodeCount = projection.nodes.length;
  final edgeCount = projection.edges.length;
  if (nodeCount > request.maxRenderableNodes) {
    return ObservableLayoutOutcome.tooLarge(
      nodeCount: nodeCount,
      edgeCount: edgeCount,
    );
  }
  if (nodeCount == 0) {
    return const ObservableLayoutOutcome.ok(
      ObservableLayoutResult(
        nodeRects: <String, LayoutRect>{},
        groupRects: <String, LayoutRect>{},
        edgePolylines: <LayoutPolyline>[],
        width: 1,
        height: 1,
      ),
    );
  }

  const nodeWidth = 140.0;
  const nodeHeight = 40.0;
  const nodeGapX = 24.0;
  const nodeGapY = 56.0;
  const groupPad = 28.0;
  const groupGapX = 48.0;
  const groupGapY = 36.0;

  final nodes = [...projection.nodes]
    ..sort(
      (left, right) =>
          (left.layoutKey ?? left.id).compareTo(right.layoutKey ?? right.id),
    );
  final edges = [...projection.edges]
    ..sort((left, right) => left.id.compareTo(right.id));

  final nodesById = <String, ProjectedGraphNode>{
    for (final node in nodes) node.id: node,
  };
  final groupOrder = <String>[];
  final groupNodes = <String, List<ProjectedGraphNode>>{};
  for (final node in nodes) {
    groupNodes.putIfAbsent(node.groupKey, () {
      groupOrder.add(node.groupKey);
      return <ProjectedGraphNode>[];
    }).add(node);
  }
  groupOrder.sort();

  final groupEdges = <_Rel>[];
  final seenGroupEdge = <String>{};
  for (final edge in edges) {
    final from = nodesById[edge.from];
    final to = nodesById[edge.to];
    if (from == null || to == null || from.groupKey == to.groupKey) {
      continue;
    }
    final key = '${from.groupKey}\u001f${to.groupKey}';
    if (seenGroupEdge.add(key)) {
      groupEdges.add(_Rel(from.groupKey, to.groupKey));
    }
  }

  final groupLayout = _layeredLayout(
    ids: groupOrder,
    relations: groupEdges,
  );

  final nodeRects = <String, LayoutRect>{};
  final groupRects = <String, LayoutRect>{};
  final groupLayerIds = <int, List<String>>{};
  for (final groupId in groupOrder) {
    groupLayerIds
        .putIfAbsent(groupLayout.layer[groupId]!, () => <String>[])
        .add(groupId);
  }
  final groupLayers = groupLayerIds.keys.toList()..sort();
  for (final layer in groupLayers) {
    groupLayerIds[layer]!.sort();
  }

  final groupInner = <String, Map<String, LayoutRect>>{};
  final groupSize = <String, LayoutPoint>{};
  for (final groupId in groupOrder) {
    final members = groupNodes[groupId]!;
    final memberIds = members.map((node) => node.id).toList()
      ..sort((left, right) {
        final leftKey = nodesById[left]?.layoutKey ?? left;
        final rightKey = nodesById[right]?.layoutKey ?? right;
        return leftKey.compareTo(rightKey);
      });
    final memberIdSet = memberIds.toSet();
    final innerEdges = <_Rel>[
      for (final edge in edges)
        if (memberIdSet.contains(edge.from) && memberIdSet.contains(edge.to))
          _Rel(edge.from, edge.to),
    ];
    String memberKey(String id) => nodesById[id]?.layoutKey ?? id;
    final inner = _layeredLayout(
      ids: memberIds,
      relations: innerEdges,
      sortKey: memberKey,
    );
    final layerIds = <int, List<String>>{};
    for (final id in memberIds) {
      layerIds.putIfAbsent(inner.layer[id]!, () => <String>[]).add(id);
    }
    final layers = layerIds.keys.toList()..sort();
    final innerRects = <String, LayoutRect>{};
    var maxWidth = 0.0;
    var maxHeight = 0.0;
    for (final layer in layers) {
      final ids = layerIds[layer]!
        ..sort((left, right) => memberKey(left).compareTo(memberKey(right)));
      for (var index = 0; index < ids.length; index += 1) {
        final x = layer * (nodeWidth + nodeGapX);
        final y = index * (nodeHeight + nodeGapY);
        innerRects[ids[index]] = LayoutRect(
          x: x,
          y: y,
          width: nodeWidth,
          height: nodeHeight,
        );
        if (x + nodeWidth > maxWidth) {
          maxWidth = x + nodeWidth;
        }
        if (y + nodeHeight > maxHeight) {
          maxHeight = y + nodeHeight;
        }
      }
    }
    groupInner[groupId] = innerRects;
    groupSize[groupId] = LayoutPoint(maxWidth, maxHeight);
  }

  var originX = 0.0;
  for (final layer in groupLayers) {
    final ids = groupLayerIds[layer]!;
    var originY = 0.0;
    var layerWidth = 0.0;
    for (final groupId in ids) {
      final size = groupSize[groupId]!;
      final width = size.x + groupPad * 2;
      final height = size.y + groupPad * 2;
      groupRects[groupId] = LayoutRect(
        x: originX,
        y: originY,
        width: width,
        height: height,
      );
      final inner = groupInner[groupId]!;
      for (final entry in inner.entries) {
        nodeRects[entry.key] = LayoutRect(
          x: originX + groupPad + entry.value.x,
          y: originY + groupPad + entry.value.y,
          width: entry.value.width,
          height: entry.value.height,
        );
      }
      if (width > layerWidth) {
        layerWidth = width;
      }
      originY += height + groupGapY;
    }
    originX += layerWidth + groupGapX;
  }

  final polylines = <LayoutPolyline>[];
  for (final edge in edges) {
    final from = nodeRects[edge.from];
    final to = nodeRects[edge.to];
    if (from == null || to == null) {
      continue;
    }
    final start = LayoutPoint(from.right, from.y + from.height / 2);
    final end = LayoutPoint(to.x, to.y + to.height / 2);
    final midX = (start.x + end.x) / 2;
    polylines.add(
      LayoutPolyline(
        edgeId: edge.id,
        points: <LayoutPoint>[
          start,
          LayoutPoint(midX, start.y),
          LayoutPoint(midX, end.y),
          end,
        ],
      ),
    );
  }
  polylines.sort((left, right) => left.edgeId.compareTo(right.edgeId));

  var width = 1.0;
  var height = 1.0;
  for (final rect in groupRects.values) {
    if (rect.right > width) {
      width = rect.right;
    }
    if (rect.bottom > height) {
      height = rect.bottom;
    }
  }

  return ObservableLayoutOutcome.ok(
    ObservableLayoutResult(
      nodeRects: Map<String, LayoutRect>.unmodifiable(nodeRects),
      groupRects: Map<String, LayoutRect>.unmodifiable(groupRects),
      edgePolylines: List<LayoutPolyline>.unmodifiable(polylines),
      width: width,
      height: height,
    ),
  );
}

class _Rel {
  const _Rel(this.from, this.to);

  final String from;
  final String to;
}

class _Layered {
  const _Layered(this.layer);

  final Map<String, int> layer;
}

_Layered _layeredLayout({
  required List<String> ids,
  required List<_Rel> relations,
  String Function(String id)? sortKey,
}) {
  String keyOf(String id) => sortKey?.call(id) ?? id;
  final sortedIds = [...ids]..sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  final outgoing = <String, List<String>>{
    for (final id in sortedIds) id: <String>[],
  };
  final incoming = <String, List<String>>{
    for (final id in sortedIds) id: <String>[],
  };
  for (final rel in relations) {
    if (!outgoing.containsKey(rel.from) || !outgoing.containsKey(rel.to)) {
      continue;
    }
    outgoing[rel.from]!.add(rel.to);
    incoming[rel.to]!.add(rel.from);
  }
  for (final id in sortedIds) {
    outgoing[id]!.sort((left, right) => keyOf(left).compareTo(keyOf(right)));
    incoming[id]!.sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  }

  final reversed = <String>{};
  final visiting = <String>{};
  final visited = <String>{};
  void dfs(String id) {
    if (visited.contains(id)) {
      return;
    }
    visiting.add(id);
    for (final next in outgoing[id]!) {
      final key = '$id\u001f$next';
      if (visiting.contains(next)) {
        reversed.add(key);
        continue;
      }
      dfs(next);
    }
    visiting.remove(id);
    visited.add(id);
  }

  for (final id in sortedIds) {
    dfs(id);
  }

  final forwardOut = <String, List<String>>{
    for (final id in sortedIds) id: <String>[],
  };
  final forwardIn = <String, List<String>>{
    for (final id in sortedIds) id: <String>[],
  };
  for (final rel in relations) {
    if (!outgoing.containsKey(rel.from) || !outgoing.containsKey(rel.to)) {
      continue;
    }
    final key = '${rel.from}\u001f${rel.to}';
    if (reversed.contains(key)) {
      forwardOut[rel.to]!.add(rel.from);
      forwardIn[rel.from]!.add(rel.to);
    } else {
      forwardOut[rel.from]!.add(rel.to);
      forwardIn[rel.to]!.add(rel.from);
    }
  }
  for (final id in sortedIds) {
    forwardOut[id]!.sort((left, right) => keyOf(left).compareTo(keyOf(right)));
    forwardIn[id]!.sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  }

  final layer = <String, int>{for (final id in sortedIds) id: 0};
  var changed = true;
  var guard = 0;
  while (changed && guard < sortedIds.length + 2) {
    changed = false;
    guard += 1;
    for (final id in sortedIds) {
      var maxPred = -1;
      for (final pred in forwardIn[id]!) {
        final predLayer = layer[pred]!;
        if (predLayer > maxPred) {
          maxPred = predLayer;
        }
      }
      final nextLayer = maxPred + 1;
      if (nextLayer > layer[id]!) {
        layer[id] = nextLayer;
        changed = true;
      }
    }
  }

  final layerIds = <int, List<String>>{};
  for (final id in sortedIds) {
    layerIds.putIfAbsent(layer[id]!, () => <String>[]).add(id);
  }
  final layers = layerIds.keys.toList()..sort();
  for (final index in layers) {
    layerIds[index]!.sort((left, right) => keyOf(left).compareTo(keyOf(right)));
  }

  List<double> barycenters(
    List<String> current,
    Map<String, List<String>> neighbors,
    Map<String, int> order,
  ) {
    return current.map((id) {
      final connected = neighbors[id]!;
      if (connected.isEmpty) {
        return order[id]!.toDouble();
      }
      var sum = 0.0;
      for (final other in connected) {
        sum += order[other]!.toDouble();
      }
      return sum / connected.length;
    }).toList(growable: false);
  }

  void sweep(bool downward) {
    final sequence = downward ? layers : layers.reversed;
    for (final index in sequence) {
      final current = [...layerIds[index]!];
      final order = <String, int>{};
      for (final otherIndex in layers) {
        final idsAtLayer = layerIds[otherIndex]!;
        for (var i = 0; i < idsAtLayer.length; i += 1) {
          order[idsAtLayer[i]] = i;
        }
      }
      final neighbors = downward ? forwardIn : forwardOut;
      final scores = barycenters(current, neighbors, order);
      final ranked = <int>[for (var i = 0; i < current.length; i += 1) i]
        ..sort((left, right) {
          final compare = scores[left].compareTo(scores[right]);
          if (compare != 0) {
            return compare;
          }
          return keyOf(current[left]).compareTo(keyOf(current[right]));
        });
      layerIds[index] = [for (final i in ranked) current[i]];
    }
  }

  sweep(true);
  sweep(false);
  sweep(true);
  sweep(false);

  for (final index in layers) {
    final current = layerIds[index]!;
    final order = <String, int>{};
    for (final otherIndex in layers) {
      final idsAtLayer = layerIds[otherIndex]!;
      for (var i = 0; i < idsAtLayer.length; i += 1) {
        order[idsAtLayer[i]] = i;
      }
    }
    final medians = <String, double>{};
    for (final id in current) {
      final neighbors = <int>[
        ...forwardIn[id]!.map((other) => order[other]!),
        ...forwardOut[id]!.map((other) => order[other]!),
      ]..sort();
      if (neighbors.isEmpty) {
        medians[id] = order[id]!.toDouble();
      } else {
        medians[id] = neighbors[neighbors.length ~/ 2].toDouble();
      }
    }
    current.sort((left, right) {
      final compare = medians[left]!.compareTo(medians[right]!);
      if (compare != 0) {
        return compare;
      }
      return keyOf(left).compareTo(keyOf(right));
    });
  }

  return _Layered(Map<String, int>.unmodifiable(layer));
}
