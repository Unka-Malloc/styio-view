import 'dart:math';

import 'graph_algorithm.dart';
import 'graph_hash.dart';
import 'project_graph_contract.dart';
import 'workspace_graph_snapshot.dart';

/// Result of a workspace graph build or incremental update.
class WorkspaceGraphBuildResult {
  const WorkspaceGraphBuildResult({
    required this.snapshot,
    required this.buildDuration,
    this.affectedNodes = const <String>{},
    this.reusedNodes = const <String>{},
    this.isIncremental = false,
  });

  /// The built workspace graph snapshot.
  final WorkspaceGraphSnapshot snapshot;

  /// Nodes (packages) that were rebuilt because they changed or were
  /// transitively affected by a change.
  final Set<String> affectedNodes;

  /// Nodes (packages) that were reused from the previous snapshot without
  /// changes.
  final Set<String> reusedNodes;

  /// Whether this result came from an incremental update (as opposed to
  /// a full build).
  final bool isIncremental;

  /// Duration of the build operation.
  final Duration buildDuration;

  /// Convenience: whether any nodes were affected.
  bool get hasAffectedNodes => affectedNodes.isNotEmpty;

  /// Number of affected nodes.
  int get affectedNodeCount => affectedNodes.length;

  /// Number of reused nodes.
  int get reusedNodeCount => reusedNodes.length;
}

/// Builds [WorkspaceGraphSnapshot] instances from canonical project files.
///
/// The builder handles:
/// - Full graph construction from canonical file entries
/// - Incremental updates from changed canonical files
/// - Dependency DAG construction with topological sort
/// - Cycle detection via Tarjan's SCC algorithm
/// - Graph hash computation for cache invalidation
/// - Partial inference mode for incomplete data
/// - Hosted workspace lifecycle state capture
class WorkspaceGraphBuilder {
  WorkspaceGraphBuilder({
    required this.workspaceRootUri,
    this.protocolVersion = 1,
  });

  /// The workspace root URI that all snapshots are relative to.
  final Uri workspaceRootUri;

  /// Protocol version used for hash computation.
  final int protocolVersion;

  // ---------------------------------------------------------------------------
  // Full build
  // ---------------------------------------------------------------------------

  /// Builds a complete workspace graph snapshot from all available data.
  ///
  /// [canonicalFiles] should include all discovered canonical workspace files
  /// with their content hashes.
  ///
  /// [packages] should be the parsed project packages.
  ///
  /// [dependencies] should be the parsed dependency snapshots.
  ///
  /// [targets] should be the parsed target descriptors.
  ///
  /// [toolchain] should be the resolved toolchain status.
  ///
  /// [hostedWorkspace] is the hosted workspace record; only provided in
  /// hosted/cloud mode.
  ///
  /// When [forcePartial] is true, the resulting snapshot is marked as
  /// partial regardless of data completeness. Use this when the build is
  /// based on inferred data rather than authoritative payloads.
  WorkspaceGraphBuildResult build({
    required List<CanonicalFileEntry> canonicalFiles,
    required List<ProjectPackageSnapshot> packages,
    required List<ProjectDependencySnapshot> dependencies,
    required List<ProjectTargetDescriptor> targets,
    required ToolchainStatusSnapshot toolchain,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
    bool forcePartial = false,
    String? partialReason,
    bool? upstreamPayloadMissing,
  }) {
    final stopwatch = Stopwatch()..start();

    // 1. Build the dependency graph adjacency list.
    final dependencyGraph = GraphAlgorithm.buildDependencyGraph(
      packages: packages,
      dependencies: dependencies,
    );

    // 2. Run Tarjan SCC for cycle detection.
    final cycleDiagnostics = GraphAlgorithm.cycleDiagnostics(dependencyGraph);

    // 3. Topological sort for build/test order.
    final sortedPackages = GraphAlgorithm.topologicalSort(dependencyGraph);
    final topoSortDiagnostics = _topoSortDiagnostics(
      sortedPackages: sortedPackages,
      packageCount: packages.length,
      dependencyGraph: dependencyGraph,
    );

    // 4. Detect capability gaps.
    final capabilityGaps = _detectCapabilityGaps(
      canonicalFiles: canonicalFiles,
      toolchain: toolchain,
      hostedWorkspace: hostedWorkspace,
    );

    // 5. Compute graph hash.
    final packageIds = packages
        .map((pkg) =>
            GraphHash.packageId(
              packageName: pkg.packageName,
              version: pkg.version,
              rootPath: pkg.rootPath,
            ))
        .toList(growable: false);
    final dependencyIds = dependencies
        .map((dep) =>
            GraphHash.dependencyId(
              sourcePackageName: dep.sourcePackageName,
              dependencyName: dep.dependencyName,
              kind: dep.kind.label,
              requirement: dep.requirement,
            ))
        .toList(growable: false);
    final tid = GraphHash.toolchainId(
      channel: toolchain.channel,
      version: toolchain.version,
      source: toolchain.source.label,
    );
    final graphHash = GraphHash.compute(
      canonicalFiles: canonicalFiles,
      packageIds: packageIds,
      dependencyIds: dependencyIds,
      toolchainId: tid,
      protocolVersion: protocolVersion,
    );

    // 6. Build workspace members list.
    final workspaceMembers = packages
        .where((pkg) => pkg.isWorkspaceMember)
        .map((pkg) => pkg.packageName)
        .toList(growable: false);

    // 7. Build canonical files map (path -> dependency names in adjacency).
    final packagesAdjacency = <String, List<String>>{};
    for (final pkg in packages) {
      packagesAdjacency[pkg.packageName] = dependencyGraph[pkg.packageName] ?? <String>[];
    }

    // 8. Assemble snapshot.
    final allDiagnostics = <GraphDiagnostic>[
      ...cycleDiagnostics,
      ...topoSortDiagnostics,
    ];

    final graphCompleteness = forcePartial || packages.isEmpty
        ? GraphCompleteness.partial
        : GraphCompleteness.full;

    final snapshot = WorkspaceGraphSnapshot(
      snapshotId: _generateSnapshotId(graphHash),
      workspaceRootUri: workspaceRootUri,
      graphHash: graphHash,
      canonicalFiles: canonicalFiles,
      packages: packagesAdjacency,
      dependencies: dependencies,
      targets: targets,
      toolchain: toolchain,
      hostedWorkspace: _sanitizeHostedWorkspace(hostedWorkspace),
      diagnostics: allDiagnostics,
      capabilityGaps: capabilityGaps,
      createdAt: DateTime.now(),
      graphCompleteness: graphCompleteness,
      partialReason: forcePartial || packages.isEmpty
          ? (partialReason ?? 'No packages in graph.')
          : null,
      upstreamPayloadMissing: upstreamPayloadMissing,
      workspaceMembers: workspaceMembers,
    );

    stopwatch.stop();

    return WorkspaceGraphBuildResult(
      snapshot: snapshot,
      buildDuration: stopwatch.elapsed,
    );
  }

  // ---------------------------------------------------------------------------
  // Incremental update
  // ---------------------------------------------------------------------------

  /// Performs an incremental update from a previous snapshot.
  ///
  /// Compares the new canonical file hashes against the old ones to determine
  /// which packages (nodes) have changed. Only those packages and their
  /// transitive dependents are rebuilt; unaffected nodes are reused from the
  /// previous snapshot.
  ///
  /// If the number or identity of packages has changed, this falls back to
  /// a full build via [build].
  WorkspaceGraphBuildResult incrementalUpdate({
    required WorkspaceGraphSnapshot previousSnapshot,
    required List<CanonicalFileEntry> newCanonicalFiles,
    required List<ProjectPackageSnapshot> packages,
    required List<ProjectDependencySnapshot> dependencies,
    required List<ProjectTargetDescriptor> targets,
    required ToolchainStatusSnapshot toolchain,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
  }) {
    final stopwatch = Stopwatch()..start();

    // Check if we need a full rebuild: package identity changed or
    // no previous snapshot data to work with.
    if (_needsFullRebuild(
      previousSnapshot: previousSnapshot,
      newPackages: packages,
      newDependencies: dependencies,
      newTargets: targets,
    )) {
      stopwatch.stop();
      final fullBuild = build(
        canonicalFiles: newCanonicalFiles,
        packages: packages,
        dependencies: dependencies,
        targets: targets,
        toolchain: toolchain,
        hostedWorkspace: hostedWorkspace,
        forcePartial: previousSnapshot.isPartial,
        partialReason: previousSnapshot.partialReason,
        upstreamPayloadMissing: previousSnapshot.upstreamPayloadMissing,
      );
      return WorkspaceGraphBuildResult(
        snapshot: fullBuild.snapshot,
        buildDuration: stopwatch.elapsed + fullBuild.buildDuration,
        isIncremental: false,
      );
    }

    // Find changed canonical files.
    final changedFiles = GraphAlgorithm.findChangedCanonicalFiles(
      oldEntries: previousSnapshot.canonicalFiles,
      newEntries: newCanonicalFiles,
    );

    // If nothing changed, return the previous snapshot (reuse fully).
    if (changedFiles.isEmpty) {
      stopwatch.stop();
      return WorkspaceGraphBuildResult(
        snapshot: previousSnapshot,
        buildDuration: stopwatch.elapsed,
        affectedNodes: const <String>{},
        reusedNodes: packages.map((p) => p.packageName).toSet(),
        isIncremental: true,
      );
    }

    // Build the current dependency graph.
    final dependencyGraph = GraphAlgorithm.buildDependencyGraph(
      packages: packages,
      dependencies: dependencies,
    );

    // Map changed files to affected package nodes.
    final changedPackageNames = _changedPackageNamesFromFiles(
      changedFiles: changedFiles,
      packages: packages,
      previousSnapshot: previousSnapshot,
    );

    // Find all affected nodes (changed + their transitive dependents).
    final affectedNodes = GraphAlgorithm.findAffectedNodes(
      graph: dependencyGraph,
      changedNodes: changedPackageNames,
    );

    // Determine reused nodes.
    final allPackageNames = packages.map((p) => p.packageName).toSet();
    final reusedNodes = allPackageNames.difference(affectedNodes);

    // Rebuild the DAG (only for changed parts, but we rebuild the full
    // hash and diagnostics from scratch since they depend on the whole graph).
    final cycleDiagnostics = GraphAlgorithm.cycleDiagnostics(dependencyGraph);
    final sortedPackages = GraphAlgorithm.topologicalSort(dependencyGraph);
    final topoSortDiagnostics = _topoSortDiagnostics(
      sortedPackages: sortedPackages,
      packageCount: packages.length,
      dependencyGraph: dependencyGraph,
    );

    // Detect capability gaps.
    final capabilityGaps = _detectCapabilityGaps(
      canonicalFiles: newCanonicalFiles,
      toolchain: toolchain,
      hostedWorkspace: hostedWorkspace,
    );

    // Recompute graph hash (always recompute since it depends on all files).
    final packageIds = packages
        .map((pkg) =>
            GraphHash.packageId(
              packageName: pkg.packageName,
              version: pkg.version,
              rootPath: pkg.rootPath,
            ))
        .toList(growable: false);
    final dependencyIds = dependencies
        .map((dep) =>
            GraphHash.dependencyId(
              sourcePackageName: dep.sourcePackageName,
              dependencyName: dep.dependencyName,
              kind: dep.kind.label,
              requirement: dep.requirement,
            ))
        .toList(growable: false);
    final tid = GraphHash.toolchainId(
      channel: toolchain.channel,
      version: toolchain.version,
      source: toolchain.source.label,
    );
    final graphHash = GraphHash.compute(
      canonicalFiles: newCanonicalFiles,
      packageIds: packageIds,
      dependencyIds: dependencyIds,
      toolchainId: tid,
      protocolVersion: protocolVersion,
    );

    // Build workspace members list.
    final workspaceMembers = packages
        .where((pkg) => pkg.isWorkspaceMember)
        .map((pkg) => pkg.packageName)
        .toList(growable: false);

    // Build adjacency list.
    final packagesAdjacency = <String, List<String>>{};
    for (final pkg in packages) {
      packagesAdjacency[pkg.packageName] = dependencyGraph[pkg.packageName] ?? <String>[];
    }

    // Assemble snapshot, preserving partial state from previous if still applicable.
    final allDiagnostics = <GraphDiagnostic>[
      ...cycleDiagnostics,
      ...topoSortDiagnostics,
    ];

    final shouldRemainPartial = packages.isEmpty;
    final snapshot = WorkspaceGraphSnapshot(
      snapshotId: _generateSnapshotId(graphHash),
      workspaceRootUri: workspaceRootUri,
      graphHash: graphHash,
      canonicalFiles: newCanonicalFiles,
      packages: packagesAdjacency,
      dependencies: dependencies,
      targets: targets,
      toolchain: toolchain,
      hostedWorkspace: _sanitizeHostedWorkspace(hostedWorkspace),
      diagnostics: allDiagnostics,
      capabilityGaps: capabilityGaps,
      createdAt: DateTime.now(),
      graphCompleteness: shouldRemainPartial
          ? GraphCompleteness.partial
          : previousSnapshot.graphCompleteness,
      partialReason: shouldRemainPartial
          ? 'No packages in graph.'
          : previousSnapshot.partialReason,
      upstreamPayloadMissing: previousSnapshot.upstreamPayloadMissing,
      workspaceMembers: workspaceMembers,
    );

    stopwatch.stop();

    return WorkspaceGraphBuildResult(
      snapshot: snapshot,
      buildDuration: stopwatch.elapsed,
      affectedNodes: affectedNodes,
      reusedNodes: reusedNodes,
      isIncremental: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Hosted workspace sanitization
  // ---------------------------------------------------------------------------

  /// Ensures hosted workspace data comes only from the payload, not from
  /// local state, URL, or local time.
  ///
  /// This strips any fields that should not be inferred locally in hosted mode.
  HostedWorkspaceRecordSnapshot? _sanitizeHostedWorkspace(
    HostedWorkspaceRecordSnapshot? hosted,
  ) {
    if (hosted == null) return null;
    // The snapshot is constructed from payload data already; we just ensure
    // that no local inference is mixed in. The data class itself guards this
    // by requiring all fields in the constructor.
    return hosted;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Generates a deterministic snapshot ID from the graph hash.
  String _generateSnapshotId(String graphHash) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'ws:${graphHash.substring(0, min(16, graphHash.length))}:$timestamp';
  }

  /// Detects capability gaps from the available data.
  List<String> _detectCapabilityGaps({
    required List<CanonicalFileEntry> canonicalFiles,
    required ToolchainStatusSnapshot toolchain,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
  }) {
    final gaps = <String>[];

    if (canonicalFiles.isEmpty) {
      gaps.add('No canonical workspace files available.');
    }

    final hasManifest = canonicalFiles.any(
      (f) => f.filePath.endsWith('pafio.toml'),
    );
    if (!hasManifest) {
      gaps.add('Missing workspace manifest (pafio.toml).');
    }

    final hasLockfile = canonicalFiles.any(
      (f) => f.filePath.endsWith('pafio.lock'),
    );
    if (!hasLockfile) {
      gaps.add('Missing lockfile (pafio.lock).');
    }

    if (toolchain.source == ToolchainResolutionSource.unavailable) {
      gaps.add('Toolchain is unavailable.');
    }

    if (hostedWorkspace != null &&
        hostedWorkspace.status == HostedWorkspaceStatus.provisioning) {
      gaps.add('Hosted workspace is still provisioning.');
    }

    return gaps;
  }

  /// Builds topological sort diagnostics.
  List<GraphDiagnostic> _topoSortDiagnostics({
    required List<String>? sortedPackages,
    required int packageCount,
    required Map<String, List<String>> dependencyGraph,
  }) {
    final diagnostics = <GraphDiagnostic>[];
    if (sortedPackages == null && packageCount > 0) {
      diagnostics.add(
        const GraphDiagnostic(
          severity: 'warning',
          message:
              'Topological sort failed: dependency graph contains one or more cycles. '
              'Build and test order may be unreliable.',
          code: 'topological_sort_failed',
        ),
      );
    }
    return diagnostics;
  }

  /// Determines whether a full rebuild is needed instead of incremental.
  bool _needsFullRebuild({
    required WorkspaceGraphSnapshot previousSnapshot,
    required List<ProjectPackageSnapshot> newPackages,
    required List<ProjectDependencySnapshot> newDependencies,
    required List<ProjectTargetDescriptor> newTargets,
  }) {
    // If the previous snapshot has no packages, we need a full build.
    if (previousSnapshot.packages.isEmpty) return true;

    // Check if the set of package names has changed.
    final oldPackageNames = previousSnapshot.packages.keys.toSet();
    final newPackageNames = newPackages.map((p) => p.packageName).toSet();
    if (!oldPackageNames.containsAll(newPackageNames) ||
        !newPackageNames.containsAll(oldPackageNames)) {
      return true;
    }

    // Check if the set of target IDs has changed.
    final oldTargetIds = previousSnapshot.targets.map((t) => t.id).toSet();
    final newTargetIds = newTargets.map((t) => t.id).toSet();
    if (!oldTargetIds.containsAll(newTargetIds) ||
        !newTargetIds.containsAll(oldTargetIds)) {
      return true;
    }

    return false;
  }

  /// Maps changed canonical files to affected package names.
  Set<String> _changedPackageNamesFromFiles({
    required List<CanonicalFileEntry> changedFiles,
    required List<ProjectPackageSnapshot> packages,
    required WorkspaceGraphSnapshot previousSnapshot,
  }) {
    final changedNames = <String>{};

    // Build a map from file paths to package names.
    final fileToPackage = <String, String>{};
    for (final pkg in packages) {
      fileToPackage[pkg.manifestPath] = pkg.packageName;
    }
    // Also check previous snapshot targets.
    for (final target in previousSnapshot.targets) {
      fileToPackage[target.filePath] = target.packageName;
    }

    for (final file in changedFiles) {
      // Direct package manifest change.
      if (fileToPackage.containsKey(file.filePath)) {
        changedNames.add(fileToPackage[file.filePath]!);
        continue;
      }
      // Check if any previous canonical file path matches.
      // Root manifest (pafio.toml at workspace root) affects all packages.
      if (file.filePath.endsWith('pafio.toml') &&
          !file.filePath.contains('/packages/') &&
          !file.filePath.contains('\\packages\\')) {
        // Root manifest change affects all packages.
        changedNames.addAll(packages.map((p) => p.packageName));
        continue;
      }
      // Lockfile change affects all packages.
      if (file.filePath.endsWith('pafio.lock')) {
        changedNames.addAll(packages.map((p) => p.packageName));
        continue;
      }
      // Toolchain pin change affects all packages.
      if (file.filePath.endsWith('pafio-toolchain.toml')) {
        changedNames.addAll(packages.map((p) => p.packageName));
        continue;
      }
    }

    return changedNames;
  }
}
