import 'dart:collection';

/// One immutable half-open text replacement.
final class WorkspaceTextChange {
  const WorkspaceTextChange({
    required this.start,
    required this.end,
    required this.replacement,
  });

  final int start;
  final int end;
  final String replacement;
}

/// All replacements proposed for one resource at one known document revision.
final class WorkspaceResourceChange {
  WorkspaceResourceChange({
    required this.resourceId,
    required this.baseDocumentRevision,
    required Iterable<WorkspaceTextChange> edits,
  }) : edits = UnmodifiableListView<WorkspaceTextChange>(
          List<WorkspaceTextChange>.of(edits),
        );

  final String resourceId;
  final int baseDocumentRevision;
  final List<WorkspaceTextChange> edits;
}

/// A revision-bound, immutable proposal that may span several resources.
final class WorkspaceChangeSet {
  WorkspaceChangeSet({
    required this.id,
    required this.baseWorkspaceRevision,
    required Iterable<WorkspaceResourceChange> resources,
  }) : resources = UnmodifiableListView<WorkspaceResourceChange>(
          List<WorkspaceResourceChange>.of(resources),
        ) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (baseWorkspaceRevision < 0) {
      throw ArgumentError.value(
        baseWorkspaceRevision,
        'baseWorkspaceRevision',
        'must not be negative',
      );
    }
    final resourceIds = <String>{};
    for (final resource in this.resources) {
      if (resource.resourceId.trim().isEmpty) {
        throw ArgumentError.value(
          resource.resourceId,
          'resourceId',
          'must not be empty',
        );
      }
      if (!resourceIds.add(resource.resourceId)) {
        throw ArgumentError.value(
          resource.resourceId,
          'resources',
          'contains a duplicate resource',
        );
      }
    }
  }

  final String id;
  final int baseWorkspaceRevision;
  final List<WorkspaceResourceChange> resources;
}
