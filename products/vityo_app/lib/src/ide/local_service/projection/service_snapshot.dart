final class VityodServiceSnapshot {
  const VityodServiceSnapshot({
    required this.eventCursor,
    required this.workspaceRevision,
    required this.capabilities,
    this.blockedReasons = const <String, String>{},
    this.activeTerminalIds = const <String>[],
    this.activeTaskIds = const <String>[],
    this.activeAgentSessionIds = const <String>[],
    this.dirtyBuffers = const <VityodDirtyBufferSnapshot>[],
    this.events = const <VityodServiceEvent>[],
    this.eventDigest = 'cbf29ce484222325',
  });

  final int eventCursor;
  final int workspaceRevision;
  final Set<String> capabilities;
  final Map<String, String> blockedReasons;
  final List<String> activeTerminalIds;
  final List<String> activeTaskIds;
  final List<String> activeAgentSessionIds;
  final List<VityodDirtyBufferSnapshot> dirtyBuffers;
  final List<VityodServiceEvent> events;
  final String eventDigest;
}

final class VityodDirtyBufferSnapshot {
  const VityodDirtyBufferSnapshot({
    required this.documentId,
    required this.revision,
    required this.contents,
  });

  final String documentId;
  final int revision;
  final String contents;
}

final class VityodServiceEvent {
  const VityodServiceEvent({
    required this.cursor,
    required this.kind,
    required this.workspaceRevision,
    required this.payload,
  });

  final int cursor;
  final String kind;
  final int workspaceRevision;
  final List<int> payload;
}
