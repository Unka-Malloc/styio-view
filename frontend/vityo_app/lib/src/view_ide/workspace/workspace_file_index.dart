import '../language/semantic/styio_semantic_core.dart';
import 'vfs.dart';

/// Describes the health of a file-based workspace index.
enum WorkspaceFileIndexStatus {
  /// The index is built and up-to-date with the workspace graph.
  ready,

  /// The index is built but covers only a subset of workspace files
  /// (e.g. indexing is still in progress or some files could not be parsed).
  partial,

  /// The index cannot be built because workspace root is missing,
  /// VFS is unavailable, or another structural dependency is absent.
  blocked,
}

extension WorkspaceFileIndexStatusX on WorkspaceFileIndexStatus {
  bool get isUsable => switch (this) {
    WorkspaceFileIndexStatus.ready => true,
    WorkspaceFileIndexStatus.partial => true,
    WorkspaceFileIndexStatus.blocked => false,
  };

  String get wireValue => switch (this) {
    WorkspaceFileIndexStatus.ready => 'ready',
    WorkspaceFileIndexStatus.partial => 'partial',
    WorkspaceFileIndexStatus.blocked => 'blocked',
  };
}

/// Metadata for a single file tracked by [WorkspaceFileIndex].
class WorkspaceFileIndexEntry {
  const WorkspaceFileIndexEntry({
    required this.path,
    required this.documentId,
    required this.lastIndexedRevision,
    required this.lastModifiedAt,
    this.symbolCount = 0,
    this.referenceCount = 0,
    this.hasErrors = false,
    this.semanticCore,
  });

  /// Workspace-relative file path (e.g. `"src/main.sty"`).
  final String path;

  /// Canonical document id for this file.
  final String documentId;

  /// Document revision at the time it was last indexed.
  final int lastIndexedRevision;

  /// When this entry was last indexed.
  final DateTime lastModifiedAt;

  /// Number of symbols extracted during the last index pass.
  final int symbolCount;

  /// Number of reference spans extracted during the last index pass.
  final int referenceCount;

  /// Whether the last index pass produced diagnostics with severity error.
  final bool hasErrors;

  /// Optional semantic core for this file, set when a full semantic
  /// analysis was computed.
  final StyioSemanticCore? semanticCore;

  /// True when the entry's revision matches the current document revision.
  bool isFreshFor(int currentRevision) =>
      lastIndexedRevision == currentRevision;

  WorkspaceFileIndexEntry copyWith({
    String? path,
    String? documentId,
    int? lastIndexedRevision,
    DateTime? lastModifiedAt,
    int? symbolCount,
    int? referenceCount,
    bool? hasErrors,
    StyioSemanticCore? semanticCore,
    bool clearSemanticCore = false,
  }) {
    return WorkspaceFileIndexEntry(
      path: path ?? this.path,
      documentId: documentId ?? this.documentId,
      lastIndexedRevision: lastIndexedRevision ?? this.lastIndexedRevision,
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      symbolCount: symbolCount ?? this.symbolCount,
      referenceCount: referenceCount ?? this.referenceCount,
      hasErrors: hasErrors ?? this.hasErrors,
      semanticCore: clearSemanticCore
          ? null
          : (semanticCore ?? this.semanticCore),
    );
  }
}

/// Stateless index of workspace files with invalidation-aware metadata.
///
/// This is the "workspace model lite" from the plan: a lightweight,
/// file-based index that tracks per-file revision, symbol/reference
/// counts, and optionally links to a [StyioSemanticCore] for each file.
///
/// The index itself is immutable; mutations produce a new instance via
/// [indexFile], [removeFile], or [invalidateAll]. This makes it safe
/// for snapshot-based UI consumption without locks.
class WorkspaceFileIndex {
  const WorkspaceFileIndex({
    required this.workspaceRoot,
    this.entries = const {},
    this.status = WorkspaceFileIndexStatus.blocked,
    this.workspaceGraphHash = '',
    this.toolchainId = '',
    this.providerId = '',
    this.indexedAt,
    this.totalSymbolCount = 0,
    this.totalReferenceCount = 0,
    this.totalFileCount = 0,
    this.errorFileCount = 0,
    this.blockedReason = '',
  });

  /// Normalized workspace root path.
  final String workspaceRoot;

  /// Map from workspace-relative path to entry.
  final Map<String, WorkspaceFileIndexEntry> entries;

  /// Overall index status.
  final WorkspaceFileIndexStatus status;

  /// Workspace graph hash at the time of indexing.
  final String workspaceGraphHash;

  /// Toolchain id at the time of indexing.
  final String toolchainId;

  /// Provider id at the time of indexing.
  final String providerId;

  /// When this index was last built.
  final DateTime? indexedAt;

  /// Aggregate symbol count across all indexed files.
  final int totalSymbolCount;

  /// Aggregate reference count across all indexed files.
  final int totalReferenceCount;

  /// Number of files tracked by this index.
  final int totalFileCount;

  /// Number of files with errors.
  final int errorFileCount;

  /// Reason when [status] is [WorkspaceFileIndexStatus.blocked].
  final String blockedReason;

  WorkspaceFileIndexEntry? entryFor(String path) => entries[path];

  bool get isEmpty => entries.isEmpty;

  /// Produce a new index with [file] added or updated.
  WorkspaceFileIndex indexFile(WorkspaceFileIndexEntry file) {
    final updated = Map<String, WorkspaceFileIndexEntry>.from(entries);
    updated[file.path] = file;
    return _recompute(updated);
  }

  /// Produce a new index with [path] removed.
  WorkspaceFileIndex removeFile(String path) {
    final updated = Map<String, WorkspaceFileIndexEntry>.from(entries);
    updated.remove(path);
    return _recompute(updated);
  }

  /// Produce a new index with all entries cleared.
  WorkspaceFileIndex invalidateAll() {
    return WorkspaceFileIndex(
      workspaceRoot: workspaceRoot,
      status: WorkspaceFileIndexStatus.blocked,
      workspaceGraphHash: workspaceGraphHash,
      toolchainId: toolchainId,
      providerId: providerId,
      blockedReason: 'Index was explicitly invalidated.',
    );
  }

  /// Composite invalidation key for this index.
  String get compositeKey =>
      '$workspaceRoot:$workspaceGraphHash:$toolchainId:$providerId';

  /// True when this index is stale relative to the given workspace facts.
  bool isStaleFor({
    required String currentWorkspaceGraphHash,
    required String currentToolchainId,
    required String currentProviderId,
  }) {
    return workspaceGraphHash != currentWorkspaceGraphHash ||
        toolchainId != currentToolchainId ||
        providerId != currentProviderId;
  }

  /// Factory to build an index from a list of VFS file refs.
  factory WorkspaceFileIndex.build({
    required String workspaceRoot,
    required List<VityoVirtualFileRef> files,
    required String workspaceGraphHash,
    required String toolchainId,
    required String providerId,
    String? blockedReason,
  }) {
    if (workspaceRoot.isEmpty) {
      return WorkspaceFileIndex(
        workspaceRoot: workspaceRoot,
        status: WorkspaceFileIndexStatus.blocked,
        blockedReason: blockedReason ?? 'Workspace root is empty.',
      );
    }

    final entries = <String, WorkspaceFileIndexEntry>{};
    for (final file in files) {
      final relativePath = file.workspaceRelativePath;
      if (relativePath.isEmpty) continue;
      entries[relativePath] = WorkspaceFileIndexEntry(
        path: relativePath,
        documentId: 'file:///$relativePath',
        lastIndexedRevision: 0,
        lastModifiedAt: DateTime.now(),
      );
    }

    return WorkspaceFileIndex(
      workspaceRoot: workspaceRoot,
      entries: entries,
      status: entries.isEmpty
          ? WorkspaceFileIndexStatus.blocked
          : WorkspaceFileIndexStatus.ready,
      workspaceGraphHash: workspaceGraphHash,
      toolchainId: toolchainId,
      providerId: providerId,
      indexedAt: DateTime.now(),
      totalFileCount: entries.length,
    );
  }

  WorkspaceFileIndex _recompute(Map<String, WorkspaceFileIndexEntry> updated) {
    var totalSymbols = 0;
    var totalReferences = 0;
    var errorFiles = 0;
    for (final entry in updated.values) {
      totalSymbols += entry.symbolCount;
      totalReferences += entry.referenceCount;
      if (entry.hasErrors) {
        errorFiles += 1;
      }
    }
    return WorkspaceFileIndex(
      workspaceRoot: workspaceRoot,
      entries: updated,
      status: updated.isEmpty
          ? WorkspaceFileIndexStatus.blocked
          : WorkspaceFileIndexStatus.ready,
      workspaceGraphHash: workspaceGraphHash,
      toolchainId: toolchainId,
      providerId: providerId,
      indexedAt: DateTime.now(),
      totalSymbolCount: totalSymbols,
      totalReferenceCount: totalReferences,
      totalFileCount: updated.length,
      errorFileCount: errorFiles,
    );
  }
}
