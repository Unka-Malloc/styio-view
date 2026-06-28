import 'graph_hash.dart';
import 'project_graph_adapter.dart';
import 'project_graph_contract.dart';
import 'workspace_graph_builder.dart';
import 'workspace_graph_snapshot.dart';

/// Event emitted after a workspace graph is built or updated.
class WorkspaceGraphEvent {
  const WorkspaceGraphEvent({
    required this.snapshot,
    required this.result,
    this.previousSnapshotHash,
  });

  /// The new snapshot after the build/update.
  final WorkspaceGraphSnapshot snapshot;

  /// The build result metadata.
  final WorkspaceGraphBuildResult result;

  /// Hash of the previous snapshot (null for first build).
  final String? previousSnapshotHash;

  /// Whether the graph hash changed from the previous snapshot.
  bool get graphHashChanged =>
      previousSnapshotHash != null &&
      previousSnapshotHash != snapshot.graphHash;
}

/// Workspace-level project graph adapter.
///
/// Wraps the lower-level [ProjectGraphAdapter] and builds
/// [WorkspaceGraphSnapshot] instances using [WorkspaceGraphBuilder].
/// This is the primary entry point for IDE features that need the
/// workspace-level dependency graph.
class WorkspaceGraphAdapter {
  WorkspaceGraphAdapter({
    required ProjectGraphAdapter projectGraphAdapter,
    required Uri workspaceRootUri,
    WorkspaceGraphBuilder? builder,
  }) : _projectGraphAdapter = projectGraphAdapter,
       _builder =
           builder ?? WorkspaceGraphBuilder(workspaceRootUri: workspaceRootUri);

  final ProjectGraphAdapter _projectGraphAdapter;
  final WorkspaceGraphBuilder _builder;

  WorkspaceGraphSnapshot? _lastSnapshot;

  /// The last built snapshot, or null if no build has occurred.
  WorkspaceGraphSnapshot? get lastSnapshot => _lastSnapshot;

  /// Loads and builds a workspace graph from the underlying project graph.
  ///
  /// This is a convenience method that wraps [loadProjectGraph] and builds
  /// a [WorkspaceGraphSnapshot] from the result.
  Future<WorkspaceGraphEvent> loadWorkspaceGraph({
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
  }) async {
    final projectSnapshot = await _projectGraphAdapter.loadProjectGraph();

    final canonicalFiles = _canonicalFilesFromProjectSnapshot(projectSnapshot);
    final result = _builder.build(
      canonicalFiles: canonicalFiles,
      packages: projectSnapshot.packages,
      dependencies: projectSnapshot.dependencies,
      targets: projectSnapshot.targets,
      toolchain: projectSnapshot.toolchain,
      hostedWorkspace: hostedWorkspace ?? projectSnapshot.hostedWorkspace,
      forcePartial:
          projectSnapshot.hasProjectGraphPayloadFailure == true ||
          projectSnapshot.kind == ProjectKind.scratch,
      partialReason: _partialReasonFromProjectSnapshot(projectSnapshot),
      upstreamPayloadMissing:
          projectSnapshot.hasProjectGraphPayloadFailure == true,
    );

    final previousHash = _lastSnapshot?.graphHash;
    _lastSnapshot = result.snapshot;

    return WorkspaceGraphEvent(
      snapshot: result.snapshot,
      result: result,
      previousSnapshotHash: previousHash,
    );
  }

  /// Performs an incremental update of the workspace graph.
  ///
  /// Use this when a subset of canonical files have changed (e.g. file watcher).
  Future<WorkspaceGraphEvent> updateWorkspaceGraphFromChangedFiles({
    required List<CanonicalFileEntry> newCanonicalFiles,
    required List<ProjectPackageSnapshot> packages,
    required List<ProjectDependencySnapshot> dependencies,
    required List<ProjectTargetDescriptor> targets,
    required ToolchainStatusSnapshot toolchain,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
  }) async {
    final previousSnapshot = _lastSnapshot;
    if (previousSnapshot == null) {
      // No previous snapshot; do a full build.
      final result = _builder.build(
        canonicalFiles: newCanonicalFiles,
        packages: packages,
        dependencies: dependencies,
        targets: targets,
        toolchain: toolchain,
        hostedWorkspace: hostedWorkspace,
      );
      _lastSnapshot = result.snapshot;
      return WorkspaceGraphEvent(snapshot: result.snapshot, result: result);
    }

    final result = _builder.incrementalUpdate(
      previousSnapshot: previousSnapshot,
      newCanonicalFiles: newCanonicalFiles,
      packages: packages,
      dependencies: dependencies,
      targets: targets,
      toolchain: toolchain,
      hostedWorkspace: hostedWorkspace,
    );

    final previousHash = _lastSnapshot?.graphHash;
    _lastSnapshot = result.snapshot;

    return WorkspaceGraphEvent(
      snapshot: result.snapshot,
      result: result,
      previousSnapshotHash: previousHash,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Extracts canonical file entries from a [ProjectGraphSnapshot].
  List<CanonicalFileEntry> _canonicalFilesFromProjectSnapshot(
    ProjectGraphSnapshot snapshot,
  ) {
    final entries = <CanonicalFileEntry>[];
    final now = DateTime.now();

    void add(String? path) {
      if (path == null || path.isEmpty) return;
      entries.add(
        CanonicalFileEntry(
          filePath: path,
          contentHash: hashString(path),
          lastModifiedAt: now,
        ),
      );
    }

    add(snapshot.manifestPath);
    add(snapshot.lockfilePath);
    add(snapshot.toolchainPinPath);
    add(snapshot.styioConfigPath);
    add(snapshot.vendorRoot);
    add(snapshot.buildRoot);

    return entries;
  }

  /// Derives a partial reason from the project snapshot state.
  String? _partialReasonFromProjectSnapshot(ProjectGraphSnapshot snapshot) {
    if (snapshot.hasProjectGraphPayloadFailure) {
      return 'Published project graph payload failed to load; using inferred data.';
    }
    if (snapshot.kind == ProjectKind.scratch) {
      return 'Running in scratch mode; no manifest available.';
    }
    if (snapshot.packages.isEmpty && snapshot.workspaceMembers.isNotEmpty) {
      return 'Workspace has members but none contain a valid package.';
    }
    return null;
  }
}
