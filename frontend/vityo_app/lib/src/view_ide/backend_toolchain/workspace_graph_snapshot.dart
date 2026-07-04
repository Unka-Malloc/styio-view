import 'project_graph_contract.dart';

/// Enum representing the completeness level of a workspace graph.
///
/// A graph can be [full] when all canonical files are available and processed,
/// or [partial] when some data is inferred or missing.
enum GraphCompleteness { full, partial }

/// Holds a hash for a canonical workspace file.
///
/// Each canonical file (pafio.toml, pafio.lock, pafio-toolchain.toml,
/// .pafio/vendor/, .pafio/build/, styio.toml, .styio.toml) is hashed
/// so the builder can detect changes for incremental updates.
class CanonicalFileEntry {
  const CanonicalFileEntry({
    required this.filePath,
    required this.contentHash,
    required this.lastModifiedAt,
  });

  /// Absolute or workspace-relative path to the canonical file.
  final String filePath;

  /// Hex-encoded content hash (e.g. SHA-256) of the file contents.
  final String contentHash;

  /// Timestamp of the last observed modification.
  final DateTime lastModifiedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanonicalFileEntry &&
          runtimeType == other.runtimeType &&
          filePath == other.filePath &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(filePath, contentHash);

  CanonicalFileEntry copyWith({
    String? filePath,
    String? contentHash,
    DateTime? lastModifiedAt,
  }) {
    return CanonicalFileEntry(
      filePath: filePath ?? this.filePath,
      contentHash: contentHash ?? this.contentHash,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
    );
  }
}

/// A diagnostic message associated with the workspace graph.
class GraphDiagnostic {
  const GraphDiagnostic({
    required this.severity,
    required this.message,
    this.source,
    this.code,
  });

  /// Severity level: 'error', 'warning', or 'info'.
  final String severity;

  /// Human-readable diagnostic message.
  final String message;

  /// Optional source component (package, file path, etc.).
  final String? source;

  /// Optional diagnostic code for programmatic handling.
  final String? code;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GraphDiagnostic &&
          runtimeType == other.runtimeType &&
          severity == other.severity &&
          message == other.message &&
          source == other.source &&
          code == other.code;

  @override
  int get hashCode => Object.hash(severity, message, source, code);

  GraphDiagnostic copyWith({
    String? severity,
    String? message,
    String? source,
    String? code,
  }) {
    return GraphDiagnostic(
      severity: severity ?? this.severity,
      message: message ?? this.message,
      source: source ?? this.source,
      code: code ?? this.code,
    );
  }
}

/// Immutable snapshot of the workspace project graph at a point in time.
///
/// This is the primary data structure for representing the full workspace
/// dependency graph. It is built from canonical workspace files and can be
/// incrementally updated when files change.
class WorkspaceGraphSnapshot {
  const WorkspaceGraphSnapshot({
    required this.snapshotId,
    required this.workspaceRootUri,
    required this.graphHash,
    this.canonicalFiles = const <CanonicalFileEntry>[],
    this.packages = const <String, List<String>>{},
    this.dependencies = const <ProjectDependencySnapshot>[],
    this.targets = const <ProjectTargetDescriptor>[],
    required this.toolchain,
    this.hostedWorkspace,
    this.diagnostics = const <GraphDiagnostic>[],
    this.capabilityGaps = const <String>[],
    required this.createdAt,
    this.graphCompleteness = GraphCompleteness.full,
    this.partialReason,
    this.upstreamPayloadMissing,
    this.workspaceMembers = const <String>[],
  });

  // ---------------------------------------------------------------------------
  // Core fields
  // ---------------------------------------------------------------------------

  /// Unique identifier for this snapshot (e.g. UUID or content-addressed).
  final String snapshotId;

  /// The workspace root URI.
  final Uri workspaceRootUri;

  /// Hex-encoded hash that uniquely identifies this graph topology.
  ///
  /// Computed from: canonical file hashes + package ids + dependency ids +
  /// toolchain id + protocol version.
  final String graphHash;

  // ---------------------------------------------------------------------------
  // Canonical files
  // ---------------------------------------------------------------------------

  /// List of canonical file entries with their content hashes.
  final List<CanonicalFileEntry> canonicalFiles;

  /// Package dependency adjacency list.
  ///
  /// Maps each package name to a list of its direct dependency names.
  /// This is the primary DAG representation used for topological sort
  /// and cycle detection.
  final Map<String, List<String>> packages;

  // ---------------------------------------------------------------------------
  // Derived data
  // ---------------------------------------------------------------------------

  /// Flat list of all dependency snapshots across all packages.
  final List<ProjectDependencySnapshot> dependencies;

  /// Flat list of all target descriptors across all packages.
  final List<ProjectTargetDescriptor> targets;

  /// Resolved toolchain status snapshot.
  final ToolchainStatusSnapshot toolchain;

  /// Hosted workspace record, populated only in hosted mode.
  ///
  /// Values for status, retention, export, and closed-at come exclusively
  /// from the hosted payload, never from URL or local time.
  final HostedWorkspaceRecordSnapshot? hostedWorkspace;

  // ---------------------------------------------------------------------------
  // Diagnostics and capability
  // ---------------------------------------------------------------------------

  /// List of graph-level diagnostics (cycles, missing files, etc.).
  final List<GraphDiagnostic> diagnostics;

  /// List of capability gaps that prevent full graph construction.
  final List<String> capabilityGaps;

  /// Timestamp when this snapshot was created.
  final DateTime createdAt;

  // ---------------------------------------------------------------------------
  // Partial / inferred graph state
  // ---------------------------------------------------------------------------

  /// Whether the graph is fully built from canonical files or partially inferred.
  ///
  /// When [graphCompleteness] is [GraphCompleteness.partial], the snapshot
  /// was built from partial information and the caller should not treat it
  /// as authoritative.
  final GraphCompleteness graphCompleteness;

  /// Human-readable explanation for why the graph is partial.
  ///
  /// Only meaningful when [graphCompleteness] is [GraphCompleteness.partial].
  final String? partialReason;

  /// Whether an upstream payload was missing, causing partial inference.
  ///
  /// Only meaningful when [graphCompleteness] is [GraphCompleteness.partial].
  final bool? upstreamPayloadMissing;

  /// Inferred list of workspace member paths.
  final List<String> workspaceMembers;

  // ---------------------------------------------------------------------------
  // Computed properties
  // ---------------------------------------------------------------------------

  /// Whether this snapshot was built from partial/inferred data.
  bool get isPartial => graphCompleteness == GraphCompleteness.partial;

  /// Whether this snapshot represents a hosted workspace.
  bool get isHosted => hostedWorkspace != null;

  /// Number of packages in the graph.
  int get packageCount => packages.length;

  /// Number of dependencies in the graph.
  int get dependencyCount => dependencies.length;

  /// Number of targets in the graph.
  int get targetCount => targets.length;

  /// Number of diagnostic messages.
  int get diagnosticCount => diagnostics.length;

  /// Number of canonical file entries.
  int get canonicalFileCount => canonicalFiles.length;

  /// Convenience: whether there are any error-level diagnostics.
  bool get hasErrors =>
      diagnostics.any((d) => d.severity == 'error');

  /// Convenience: whether there are any cycle diagnostics.
  bool get hasCycles =>
      diagnostics.any((d) => d.code == 'cycle_detected');

  /// Convenience: returns the list of packages that have no incoming edges
  /// (i.e. top-level packages in the dependency DAG).
  List<String> get rootPackages {
    final allDependents = <String>{};
    for (final deps in packages.values) {
      allDependents.addAll(deps);
    }
    return packages.keys
        .where((pkg) => !allDependents.contains(pkg))
        .toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  WorkspaceGraphSnapshot copyWith({
    String? snapshotId,
    Uri? workspaceRootUri,
    String? graphHash,
    List<CanonicalFileEntry>? canonicalFiles,
    Map<String, List<String>>? packages,
    List<ProjectDependencySnapshot>? dependencies,
    List<ProjectTargetDescriptor>? targets,
    ToolchainStatusSnapshot? toolchain,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
    List<GraphDiagnostic>? diagnostics,
    List<String>? capabilityGaps,
    DateTime? createdAt,
    GraphCompleteness? graphCompleteness,
    String? partialReason,
    bool? upstreamPayloadMissing,
    List<String>? workspaceMembers,
  }) {
    return WorkspaceGraphSnapshot(
      snapshotId: snapshotId ?? this.snapshotId,
      workspaceRootUri: workspaceRootUri ?? this.workspaceRootUri,
      graphHash: graphHash ?? this.graphHash,
      canonicalFiles: canonicalFiles ?? this.canonicalFiles,
      packages: packages ?? this.packages,
      dependencies: dependencies ?? this.dependencies,
      targets: targets ?? this.targets,
      toolchain: toolchain ?? this.toolchain,
      hostedWorkspace: hostedWorkspace ?? this.hostedWorkspace,
      diagnostics: diagnostics ?? this.diagnostics,
      capabilityGaps: capabilityGaps ?? this.capabilityGaps,
      createdAt: createdAt ?? this.createdAt,
      graphCompleteness: graphCompleteness ?? this.graphCompleteness,
      partialReason: partialReason ?? this.partialReason,
      upstreamPayloadMissing: upstreamPayloadMissing ?? this.upstreamPayloadMissing,
      workspaceMembers: workspaceMembers ?? this.workspaceMembers,
    );
  }

  // ---------------------------------------------------------------------------
  // Factory: empty
  // ---------------------------------------------------------------------------

  /// Creates an empty workspace graph snapshot, used as a fallback.
  factory WorkspaceGraphSnapshot.empty({
    required Uri workspaceRootUri,
    required ToolchainStatusSnapshot toolchain,
    String? partialReason,
  }) {
    return WorkspaceGraphSnapshot(
      snapshotId: 'empty:${workspaceRootUri.path.hashCode}',
      workspaceRootUri: workspaceRootUri,
      graphHash: '',
      createdAt: DateTime.now(),
      toolchain: toolchain,
      graphCompleteness: GraphCompleteness.partial,
      partialReason: partialReason ?? 'No canonical files available.',
      upstreamPayloadMissing: true,
      diagnostics: const [
        GraphDiagnostic(
          severity: 'warning',
          message: 'Empty snapshot created; no canonical files were provided.',
          code: 'empty_snapshot',
        ),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkspaceGraphSnapshot &&
          runtimeType == other.runtimeType &&
          snapshotId == other.snapshotId &&
          graphHash == other.graphHash;

  @override
  int get hashCode => Object.hash(snapshotId, graphHash);

  @override
  String toString() =>
      'WorkspaceGraphSnapshot('
      'snapshotId: $snapshotId, '
      'graphHash: ${graphHash.length > 12 ? '${graphHash.substring(0, 12)}...' : graphHash}, '
      'packages: ${packages.length}, '
      'dependencies: ${dependencies.length}, '
      'targets: ${targets.length}, '
      'completeness: $graphCompleteness'
      ')';
}
