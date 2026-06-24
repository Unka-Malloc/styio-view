import 'project_graph_contract.dart';
import 'workspace_graph_snapshot.dart';

/// Graph algorithms for workspace dependency graph analysis.
///
/// Provides Tarjan's strongly connected components algorithm for cycle
/// detection and Kahn's algorithm for topological sorting. Also includes
/// utilities for building adjacency lists and finding affected nodes
/// during incremental updates.
class GraphAlgorithm {
  // ---------------------------------------------------------------------------
  // Adjacency list construction
  // ---------------------------------------------------------------------------

  /// Builds a package dependency adjacency list from packages and dependencies.
  ///
  /// Returns a map where each key is a package name and the value is a list
  /// of dependency names (the packages it directly depends on).
  static Map<String, List<String>> buildDependencyGraph({
    required List<ProjectPackageSnapshot> packages,
    required List<ProjectDependencySnapshot> dependencies,
  }) {
    final packageNames = packages.map((p) => p.packageName).toSet();
    final graph = <String, List<String>>{};

    // Initialize all packages with empty dependency lists.
    for (final pkg in packages) {
      graph[pkg.packageName] = <String>[];
    }

    // Populate edges for dependencies that reference other packages.
    final dependencyNames = <String>{};
    for (final dep in dependencies) {
      dependencyNames.add(dep.dependencyName);
      // Only add edges to known packages (workspace references).
      if (packageNames.contains(dep.dependencyName)) {
        graph[dep.sourcePackageName] ??= <String>[];
        graph[dep.sourcePackageName]!.add(dep.dependencyName);
      }
    }

    return graph;
  }

  /// Builds a target dependency graph: target -> list of input file paths.
  static Map<String, List<String>> buildTargetInputGraph({
    required List<ProjectTargetDescriptor> targets,
  }) {
    final graph = <String, List<String>>{};
    for (final target in targets) {
      graph[target.id] = <String>[target.filePath];
    }
    return graph;
  }

  /// Builds a mapping from file path to owning package name.
  static Map<String, String> buildFileOwnershipMap({
    required List<ProjectPackageSnapshot> packages,
    required List<ProjectTargetDescriptor> targets,
  }) {
    final ownership = <String, String>{};
    for (final target in targets) {
      ownership[target.filePath] = target.packageName;
    }
    for (final pkg in packages) {
      ownership[pkg.manifestPath] = pkg.packageName;
      for (final target in pkg.targets) {
        ownership[target.filePath] = pkg.packageName;
      }
    }
    return ownership;
  }

  // ---------------------------------------------------------------------------
  // Tarjan's SCC algorithm
  // ---------------------------------------------------------------------------

  /// Finds all strongly connected components (SCCs) using Tarjan's algorithm.
  ///
  /// Each component is a list of node names. Components with more than one
  /// element (or a single element with a self-loop) represent cycles.
  static List<List<String>> findStronglyConnectedComponents(
    Map<String, List<String>> graph,
  ) {
    final components = <List<String>>[];
    final index = <String, int>{};
    final lowLink = <String, int>{};
    final onStack = <String, bool>{};
    final stack = <String>[];
    var currentIndex = 0;

    void strongConnect(String node) {
      index[node] = currentIndex;
      lowLink[node] = currentIndex;
      currentIndex++;
      stack.add(node);
      onStack[node] = true;

      final neighbors = graph[node] ?? <String>[];
      for (final neighbor in neighbors) {
        if (!index.containsKey(neighbor)) {
          // Tree edge.
          strongConnect(neighbor);
          lowLink[node] = lowLink[node]! < lowLink[neighbor]!
              ? lowLink[node]!
              : lowLink[neighbor]!;
        } else if (onStack[neighbor] == true) {
          // Back edge.
          lowLink[node] = lowLink[node]! < index[neighbor]!
              ? lowLink[node]!
              : index[neighbor]!;
        }
      }

      // If node is a root of an SCC, pop the stack.
      if (lowLink[node] == index[node]) {
        final component = <String>[];
        while (true) {
          final popped = stack.removeLast();
          onStack[popped] = false;
          component.add(popped);
          if (popped == node) break;
        }
        components.add(component);
      }
    }

    // Run Tarjan's algorithm on all nodes in the graph.
    for (final node in graph.keys) {
      if (!index.containsKey(node)) {
        strongConnect(node);
      }
    }

    return components;
  }

  /// Returns all cycles in the dependency graph.
  ///
  /// A cycle is any SCC with more than one node, or a single node with a
  /// self-loop (depends on itself).
  static List<List<String>> findCycles(Map<String, List<String>> graph) {
    final sccs = findStronglyConnectedComponents(graph);
    return sccs.where((component) {
      if (component.length > 1) return true;
      // Check for self-loop.
      final node = component.single;
      final neighbors = graph[node] ?? <String>[];
      return neighbors.contains(node);
    }).toList(growable: false);
  }

  /// Returns whether the graph contains any cycles.
  static bool hasCycle(Map<String, List<String>> graph) {
    return findCycles(graph).isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Topological sort (Kahn's algorithm)
  // ---------------------------------------------------------------------------

  /// Performs a topological sort of the dependency graph.
  ///
  /// Returns packages in build/test order (dependencies before dependents).
  /// If the graph contains cycles, returns null and the caller should check
  /// [hasCycle] or [findCycles] for diagnostics.
  static List<String>? topologicalSort(Map<String, List<String>> graph) {
    // Compute in-degree for each node.
    final inDegree = <String, int>{};
    for (final node in graph.keys) {
      inDegree[node] = 0;
    }
    for (final entry in graph.entries) {
      for (final neighbor in entry.value) {
        if (inDegree.containsKey(neighbor)) {
          inDegree[neighbor] = inDegree[neighbor]! + 1;
        }
      }
    }

    // Queue nodes with in-degree 0.
    final queue = <String>[];
    for (final entry in inDegree.entries) {
      if (entry.value == 0) {
        queue.add(entry.key);
      }
    }

    final sorted = <String>[];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      sorted.add(node);

      for (final neighbor in graph[node] ?? <String>[]) {
        if (inDegree.containsKey(neighbor)) {
          inDegree[neighbor] = inDegree[neighbor]! - 1;
          if (inDegree[neighbor] == 0) {
            queue.add(neighbor);
          }
        }
      }
    }

    // If not all nodes were visited, a cycle exists.
    if (sorted.length != graph.length) {
      return null;
    }

    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Build / test order
  // ---------------------------------------------------------------------------

  /// Returns targets in build order based on the topological sort of packages.
  ///
  /// Targets from dependency packages come before targets from dependent packages.
  static List<ProjectTargetDescriptor> buildOrder({
    required List<ProjectTargetDescriptor> targets,
    required List<String> packageBuildOrder,
  }) {
    final packageRank = <String, int>{};
    for (var i = 0; i < packageBuildOrder.length; i++) {
      packageRank[packageBuildOrder[i]] = i;
    }

    final sorted = List<ProjectTargetDescriptor>.from(targets);
    sorted.sort((a, b) {
      final rankA = packageRank[a.packageName] ?? packageRank.length;
      final rankB = packageRank[b.packageName] ?? packageRank.length;
      return rankA.compareTo(rankB);
    });
    return sorted;
  }

  // ---------------------------------------------------------------------------
  // Incremental update helpers
  // ---------------------------------------------------------------------------

  /// Finds nodes (packages) affected by changed canonical files.
  ///
  /// Given the current dependency graph and a set of directly changed nodes,
  /// returns all nodes that need to be re-processed (changed nodes plus their
  /// transitive dependents).
  static Set<String> findAffectedNodes({
    required Map<String, List<String>> graph,
    required Set<String> changedNodes,
  }) {
    final affected = <String>{};
    final visited = <String>{};

    void traverse(String node) {
      if (visited.contains(node)) return;
      visited.add(node);
      affected.add(node);

      // Follow reverse edges: find packages that depend on this node.
      for (final entry in graph.entries) {
        if (entry.value.contains(node)) {
          traverse(entry.key);
        }
      }
    }

    for (final changed in changedNodes) {
      traverse(changed);
    }

    return affected;
  }

  /// Determines which canonical files have changed between two snapshots.
  ///
  /// Returns a list of [CanonicalFileEntry] that have a different hash between
  /// the old snapshot and the new entries.
  static List<CanonicalFileEntry> findChangedCanonicalFiles({
    required List<CanonicalFileEntry> oldEntries,
    required List<CanonicalFileEntry> newEntries,
  }) {
    final oldByPath = <String, CanonicalFileEntry>{};
    for (final entry in oldEntries) {
      oldByPath[entry.filePath] = entry;
    }

    final changed = <CanonicalFileEntry>[];
    for (final entry in newEntries) {
      final old = oldByPath[entry.filePath];
      if (old == null || old.contentHash != entry.contentHash) {
        changed.add(entry);
      }
    }

    return changed;
  }

  // ---------------------------------------------------------------------------
  // Diagnostics helpers
  // ---------------------------------------------------------------------------

  /// Creates diagnostic entries for any cycles found in the graph.
  static List<GraphDiagnostic> cycleDiagnostics(
    Map<String, List<String>> graph,
  ) {
    final cycles = findCycles(graph);
    return cycles.map((cycle) {
      final cycleDescription = cycle.join(' -> ');
      return GraphDiagnostic(
        severity: 'error',
        message: 'Dependency cycle detected: $cycleDescription',
        code: 'cycle_detected',
        source: cycle.first,
      );
    }).toList(growable: false);
  }
}
