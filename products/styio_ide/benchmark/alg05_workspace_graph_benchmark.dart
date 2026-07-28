/// ALG-05: Workspace Graph Benchmark
///
/// Benchmarks workspace graph operations:
/// - 10/100 packages build
/// - 1000 dependency resolution
/// - Single manifest edit rebuild
/// - Lockfile edit rebuild
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

class PackageNode {
  final String name;
  final String version;
  final List<String> dependencies;
  final String manifestContent;

  const PackageNode({
    required this.name,
    required this.version,
    required this.dependencies,
    required this.manifestContent,
  });
}

class ProjectGraph {
  final Map<String, PackageNode> packages;

  const ProjectGraph({required this.packages});

  List<String> get packageNames => packages.keys.toList();

  /// Check if a package depends on another (transitively).
  bool dependsOn(String pkg, String target, {Set<String>? visited}) {
    visited ??= <String>{};
    if (!visited.add(pkg)) return false;
    final node = packages[pkg];
    if (node == null) return false;
    if (node.dependencies.contains(target)) return true;
    for (final dep in node.dependencies) {
      if (dependsOn(dep, target, visited: visited)) return true;
    }
    return false;
  }

  /// Resolve dependency order (topological sort).
  List<String> resolveDependencyOrder() {
    final visited = <String>{};
    final order = <String>[];

    void visit(String name) {
      if (visited.contains(name)) return;
      visited.add(name);
      final node = packages[name];
      if (node != null) {
        for (final dep in node.dependencies) {
          visit(dep);
        }
      }
      order.add(name);
    }

    for (final name in packages.keys) {
      visit(name);
    }
    return order;
  }

  /// Rebuild after a manifest edit.
  ProjectGraph rebuildAfterManifestEdit(
    String packageName,
    String newManifest,
  ) {
    final oldNode = packages[packageName];
    if (oldNode == null) return this;
    final newNode = PackageNode(
      name: oldNode.name,
      version: oldNode.version,
      dependencies: oldNode.dependencies,
      manifestContent: newManifest,
    );
    final newPackages = Map<String, PackageNode>.from(packages);
    newPackages[packageName] = newNode;
    return ProjectGraph(packages: newPackages);
  }

  /// Rebuild after lockfile edit (version change).
  ProjectGraph rebuildAfterLockfileEdit(String packageName, String newVersion) {
    final oldNode = packages[packageName];
    if (oldNode == null) return this;
    final newNode = PackageNode(
      name: oldNode.name,
      version: newVersion,
      dependencies: oldNode.dependencies,
      manifestContent: oldNode.manifestContent,
    );
    final newPackages = Map<String, PackageNode>.from(packages);
    newPackages[packageName] = newNode;
    return ProjectGraph(packages: newPackages);
  }
}

/// Generate a package graph with [count] packages.
ProjectGraph generatePackageGraph(int count, {int seed = 42}) {
  final rng = Random(seed);
  final packages = <String, PackageNode>{};

  for (var i = 0; i < count; i++) {
    final name = 'pkg_$i';
    final version = '1.${rng.nextInt(20)}.${rng.nextInt(10)}';
    // Each package depends on 0-3 random packages with smaller indices
    final depCount = rng.nextInt(4);
    final deps = <String>[];
    for (var j = 0; j < depCount && i > 0; j++) {
      final depIdx = rng.nextInt(i);
      final depName = 'pkg_$depIdx';
      if (!deps.contains(depName)) {
        deps.add(depName);
      }
    }
    packages[name] = PackageNode(
      name: name,
      version: version,
      dependencies: deps,
      manifestContent:
          'package $name\nversion $version\ndeps: ${deps.join(',')}',
    );
  }
  return ProjectGraph(packages: packages);
}

/// Run all ALG-05 benchmarks.
List<Map<String, dynamic>> runAlg05Benchmarks() {
  final results = <Map<String, dynamic>>[];

  for (final size in [10, 100]) {
    final graph = generatePackageGraph(size);

    // Build packages (just the graph construction)
    final r1 = BenchmarkRunner('build_packages_${size}pkgs').run(200, (
      iteration,
    ) {
      generatePackageGraph(size, seed: size + iteration);
    });
    results.add(r1.toJson());

    // Dependency resolution
    final r2 = BenchmarkRunner('dependency_resolution_${size}pkgs').run(200, (
      _,
    ) {
      graph.resolveDependencyOrder();
    });
    results.add(r2.toJson());
  }

  // 1000 dependency resolution (large graph)
  final largeGraph = generatePackageGraph(1000);
  final r3 = BenchmarkRunner('dependency_resolution_1000pkgs').run(100, (_) {
    largeGraph.resolveDependencyOrder();
  });
  results.add(r3.toJson());

  // Single manifest edit rebuild
  final r4 = BenchmarkRunner('manifest_edit_rebuild_1000pkgs').run(500, (_) {
    largeGraph.rebuildAfterManifestEdit(
      'pkg_0',
      'package pkg_0\nversion 2.0.0',
    );
  });
  results.add(r4.toJson());

  // Lockfile edit rebuild
  final r5 = BenchmarkRunner('lockfile_edit_rebuild_1000pkgs').run(500, (_) {
    largeGraph.rebuildAfterLockfileEdit('pkg_500', '2.0.0');
  });
  results.add(r5.toJson());

  return results;
}

void main() {
  print('=== ALG-05: Workspace Graph Benchmarks ===');
  final results = runAlg05Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
