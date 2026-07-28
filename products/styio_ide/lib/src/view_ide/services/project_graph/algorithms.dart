import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'model.dart';

class StyioProjectGraphAlgorithms {
  const StyioProjectGraphAlgorithms._();

  static List<List<String>> tarjanStronglyConnectedComponents(
    Map<String, List<String>> graph,
  ) {
    final nodes = _allNodes(graph).toList()..sort();
    final indexByNode = <String, int>{};
    final lowLinkByNode = <String, int>{};
    final stack = <String>[];
    final onStack = <String>{};
    final components = <List<String>>[];
    var index = 0;

    void connect(String node) {
      indexByNode[node] = index;
      lowLinkByNode[node] = index;
      index += 1;
      stack.add(node);
      onStack.add(node);

      final neighbors = List<String>.from(graph[node] ?? const <String>[])
        ..sort();
      for (final neighbor in neighbors) {
        if (!indexByNode.containsKey(neighbor)) {
          connect(neighbor);
          lowLinkByNode[node] = _min(
            lowLinkByNode[node]!,
            lowLinkByNode[neighbor]!,
          );
        } else if (onStack.contains(neighbor)) {
          lowLinkByNode[node] = _min(
            lowLinkByNode[node]!,
            indexByNode[neighbor]!,
          );
        }
      }

      if (lowLinkByNode[node] == indexByNode[node]) {
        final component = <String>[];
        while (stack.isNotEmpty) {
          final current = stack.removeLast();
          onStack.remove(current);
          component.add(current);
          if (current == node) {
            break;
          }
        }
        component.sort();
        components.add(component);
      }
    }

    for (final node in nodes) {
      if (!indexByNode.containsKey(node)) {
        connect(node);
      }
    }

    components.sort((left, right) => left.first.compareTo(right.first));
    return components;
  }

  static List<List<String>> cycles(Map<String, List<String>> graph) {
    return tarjanStronglyConnectedComponents(graph).where((component) {
      if (component.length > 1) {
        return true;
      }
      final node = component.single;
      return (graph[node] ?? const <String>[]).contains(node);
    }).toList(growable: false);
  }

  static List<String>? kahnTopologicalSort(Map<String, List<String>> graph) {
    final nodes = _allNodes(graph).toList()..sort();
    final dependencyCount = <String, int>{
      for (final node in nodes) node: 0,
    };
    final dependents = <String, List<String>>{
      for (final node in nodes) node: <String>[],
    };

    for (final node in nodes) {
      final dependencies = (graph[node] ?? const <String>[])
          .where(dependencyCount.containsKey)
          .toSet();
      dependencyCount[node] = dependencies.length;
      for (final dependency in dependencies) {
        dependents[dependency]!.add(node);
      }
    }

    final queue = dependencyCount.entries
        .where((entry) => entry.value == 0)
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final sorted = <String>[];

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      sorted.add(node);

      final nextDependents = dependents[node]!..sort();
      for (final dependent in nextDependents) {
        dependencyCount[dependent] = dependencyCount[dependent]! - 1;
        if (dependencyCount[dependent] == 0) {
          queue.add(dependent);
          queue.sort();
        }
      }
    }

    if (sorted.length != nodes.length) {
      return null;
    }
    return sorted;
  }

  static Set<String> affectedSet({
    required Map<String, List<String>> graph,
    required Set<String> changedNodes,
  }) {
    final nodes = _allNodes(graph);
    final reverse = <String, Set<String>>{
      for (final node in nodes) node: <String>{},
    };
    for (final entry in graph.entries) {
      for (final dependency in entry.value) {
        reverse.putIfAbsent(dependency, () => <String>{}).add(entry.key);
      }
    }

    final affected = <String>{};
    final queue = changedNodes.toList()..sort();
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (!affected.add(node)) {
        continue;
      }
      final dependents = reverse[node]?.toList() ?? const <String>[];
      for (final dependent in dependents) {
        if (!affected.contains(dependent)) {
          queue.add(dependent);
        }
      }
      queue.sort();
    }
    return affected;
  }

  static String stableGraphHash(StyioProjectGraph graph) {
    return crypto.sha256
        .convert(utf8.encode(styioStableJson(graph.toStableJson())))
        .toString();
  }

  static StyioProjectGraphDiff diff(
    StyioProjectGraph previous,
    StyioProjectGraph next,
  ) {
    final previousHash = stableGraphHash(previous);
    final nextHash = stableGraphHash(next);
    final previousNodes = previous.nodes;
    final nextNodes = next.nodes;
    final addedNodes = <StyioProjectNode>[];
    final removedNodes = <StyioProjectNode>[];
    final changedNodes = <StyioProjectNode>[];

    for (final id in nextNodes.keys) {
      if (!previousNodes.containsKey(id)) {
        addedNodes.add(nextNodes[id]!);
      } else if (previousNodes[id]!.signature != nextNodes[id]!.signature) {
        changedNodes.add(nextNodes[id]!);
      }
    }
    for (final id in previousNodes.keys) {
      if (!nextNodes.containsKey(id)) {
        removedNodes.add(previousNodes[id]!);
      }
    }

    final previousEdges = {
      for (final edge in previous.edges) edge.identityKey: edge,
    };
    final nextEdges = {
      for (final edge in next.edges) edge.identityKey: edge,
    };
    final addedEdges = <StyioProjectEdge>[];
    final removedEdges = <StyioProjectEdge>[];
    final changedEdges = <StyioProjectEdge>[];

    for (final key in nextEdges.keys) {
      if (!previousEdges.containsKey(key)) {
        addedEdges.add(nextEdges[key]!);
      } else if (previousEdges[key]!.signature != nextEdges[key]!.signature) {
        changedEdges.add(nextEdges[key]!);
      }
    }
    for (final key in previousEdges.keys) {
      if (!nextEdges.containsKey(key)) {
        removedEdges.add(previousEdges[key]!);
      }
    }

    final previousFiles = {
      for (final file in previous.canonicalFiles) file.normalizedPath: file,
    };
    final nextFiles = {
      for (final file in next.canonicalFiles) file.normalizedPath: file,
    };
    final addedCanonicalFiles = <StyioCanonicalProjectFile>[];
    final removedCanonicalFiles = <StyioCanonicalProjectFile>[];
    final changedCanonicalFiles = <StyioCanonicalProjectFile>[];
    for (final file in nextFiles.values) {
      final previousFile = previousFiles[file.normalizedPath];
      if (previousFile == null) {
        addedCanonicalFiles.add(file);
      } else if (previousFile.contentHash != file.contentHash ||
          previousFile.kind != file.kind) {
        changedCanonicalFiles.add(file);
      }
    }
    for (final file in previousFiles.values) {
      if (!nextFiles.containsKey(file.normalizedPath)) {
        removedCanonicalFiles.add(file);
      }
    }

    int compareNode(StyioProjectNode left, StyioProjectNode right) =>
        left.id.compareTo(right.id);
    int compareEdge(StyioProjectEdge left, StyioProjectEdge right) =>
        left.identityKey.compareTo(right.identityKey);
    int compareFile(
      StyioCanonicalProjectFile left,
      StyioCanonicalProjectFile right,
    ) =>
        left.normalizedPath.compareTo(right.normalizedPath);

    return StyioProjectGraphDiff(
      previousHash: previousHash,
      nextHash: nextHash,
      addedNodes: addedNodes..sort(compareNode),
      removedNodes: removedNodes..sort(compareNode),
      changedNodes: changedNodes..sort(compareNode),
      addedEdges: addedEdges..sort(compareEdge),
      removedEdges: removedEdges..sort(compareEdge),
      changedEdges: changedEdges..sort(compareEdge),
      addedCanonicalFiles: addedCanonicalFiles..sort(compareFile),
      removedCanonicalFiles: removedCanonicalFiles..sort(compareFile),
      changedCanonicalFiles: changedCanonicalFiles..sort(compareFile),
    );
  }

  static List<StyioGraphDiagnostic> cycleDiagnostics(
    Map<String, List<String>> graph,
  ) {
    return cycles(graph)
        .map(
          (cycle) => StyioGraphDiagnostic(
            severity: StyioGraphDiagnosticSeverity.error,
            code: StyioGraphDiagnosticCode.dependencyCycle,
            message: 'Dependency cycle detected: ${cycle.join(' -> ')}.',
            source: cycle.first,
          ),
        )
        .toList(growable: false);
  }

  static Set<String> _allNodes(Map<String, List<String>> graph) {
    return <String>{
      ...graph.keys,
      for (final dependencies in graph.values) ...dependencies,
    };
  }

  static int _min(int left, int right) => left < right ? left : right;
}

extension StyioProjectGraphAlgorithmX on StyioProjectGraph {
  String get stableHash => StyioProjectGraphAlgorithms.stableGraphHash(this);

  List<List<String>> get stronglyConnectedComponents =>
      StyioProjectGraphAlgorithms.tarjanStronglyConnectedComponents(
        moduleDependencyGraph(),
      );

  List<String>? get topologicalOrder =>
      StyioProjectGraphAlgorithms.kahnTopologicalSort(moduleDependencyGraph());

  Set<String> affectedSet(Set<String> changedNodes) {
    return StyioProjectGraphAlgorithms.affectedSet(
      graph: moduleDependencyGraph(),
      changedNodes: changedNodes,
    );
  }

  StyioProjectGraphDiff diff(StyioProjectGraph next) =>
      StyioProjectGraphAlgorithms.diff(this, next);
}
