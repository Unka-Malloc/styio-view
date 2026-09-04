/// Frozen schema-v1 consumer types for Styio observable static snapshots.
///
/// Isolate-safe and Flutter-free. Unknown node/edge kinds decode to
/// [ObservableNodeKind.unknown]/[ObservableEdgeKind.unknown] with the raw
/// spelling preserved. Unknown object keys are kept in [extensions].
library;

import 'observable_delta_model.dart';

const String kObservableStaticSnapshotContract =
    'styio.observable.static-snapshot';
const int kObservableStaticSnapshotSchemaVersion = 1;
const String kObservableStaticSnapshotStability = 'incubating';
const String kObservableMachineInfoKey = 'observable_static_snapshot';
const String kObservableArtifactSuffix = '.observable-static-snapshot.json';
const String kObservablePafioEmitOption = '--emit-observable-static-snapshot';
const String kObservablePafioCapabilityOption = '--observable-capability';
const String kObservableUnanchoredGroupKey = 'unanchored';
const int kObservableSnapshotCacheDefaultMaxEntries = 8;
const int kObservableMaxRenderableNodes = 10000;
const int kObservableDebounceMilliseconds = 500;

const List<String> kObservableRequiredCapabilities = <String>[
  'file-source-anchors',
  'producer-evidence',
  'static-topology-edges',
  'static-topology-facts',
  'static-topology-nodes',
];

enum ObservableAvailability {
  unavailable,
  unsupported,
  refreshing,
  fresh,
  stale,
  blocked,
  scalarNoop,
}

extension ObservableAvailabilityX on ObservableAvailability {
  String get wireValue {
    return switch (this) {
      ObservableAvailability.unavailable => 'unavailable',
      ObservableAvailability.unsupported => 'unsupported',
      ObservableAvailability.refreshing => 'refreshing',
      ObservableAvailability.fresh => 'fresh',
      ObservableAvailability.stale => 'stale',
      ObservableAvailability.blocked => 'blocked',
      ObservableAvailability.scalarNoop => 'scalar-noop',
    };
  }

  bool get showsTopology {
    return switch (this) {
      ObservableAvailability.fresh ||
      ObservableAvailability.refreshing ||
      ObservableAvailability.stale ||
      ObservableAvailability.scalarNoop => true,
      ObservableAvailability.unavailable ||
      ObservableAvailability.unsupported ||
      ObservableAvailability.blocked => false,
    };
  }
}

enum ObservableReasonCode {
  noToolchain,
  noManifest,
  unsupportedPlatform,
  unsupportedSchemaVersion,
  missingCapability,
  publicationFailed,
  invalidSnapshot,
  snapshotTooLarge,
  workspaceChanged,
  anchorUnresolved,
  cancelled,
  fullSnapshotRequired,
  wrongParent,
  staleDelta,
  duplicateDelta,
  outOfOrderDelta,
  unsupportedDelta,
  malformedDelta,
  invalidDelta,
  deltaTransportUnavailable,
}

extension ObservableReasonCodeX on ObservableReasonCode {
  String get wireValue {
    return switch (this) {
      ObservableReasonCode.noToolchain => 'no-toolchain',
      ObservableReasonCode.noManifest => 'no-manifest',
      ObservableReasonCode.unsupportedPlatform => 'unsupported-platform',
      ObservableReasonCode.unsupportedSchemaVersion =>
        'unsupported-schema-version',
      ObservableReasonCode.missingCapability => 'missing-capability',
      ObservableReasonCode.publicationFailed => 'publication-failed',
      ObservableReasonCode.invalidSnapshot => 'invalid-snapshot',
      ObservableReasonCode.snapshotTooLarge => 'snapshot-too-large',
      ObservableReasonCode.workspaceChanged => 'workspace-changed',
      ObservableReasonCode.anchorUnresolved => 'anchor-unresolved',
      ObservableReasonCode.cancelled => 'cancelled',
      ObservableReasonCode.fullSnapshotRequired => 'full-snapshot-required',
      ObservableReasonCode.wrongParent => 'wrong-parent',
      ObservableReasonCode.staleDelta => 'stale-delta',
      ObservableReasonCode.duplicateDelta => 'duplicate-delta',
      ObservableReasonCode.outOfOrderDelta => 'out-of-order-delta',
      ObservableReasonCode.unsupportedDelta => 'unsupported-delta',
      ObservableReasonCode.malformedDelta => 'malformed-delta',
      ObservableReasonCode.invalidDelta => 'invalid-delta',
      ObservableReasonCode.deltaTransportUnavailable =>
        'delta-transport-unavailable',
    };
  }

  bool get isRendered {
    return this != ObservableReasonCode.cancelled;
  }
}

enum ObservableInvalidSubcode {
  unsupportedContract,
  missingField,
  duplicateId,
  danglingReference,
  evidenceCycle,
  unsupportedCompleteness,
  unsupportedSchemaVersion,
  missingCapability,
  invalidLineage,
}

extension ObservableInvalidSubcodeX on ObservableInvalidSubcode {
  String get wireValue {
    return switch (this) {
      ObservableInvalidSubcode.unsupportedContract => 'unsupported-contract',
      ObservableInvalidSubcode.missingField => 'missing-field',
      ObservableInvalidSubcode.duplicateId => 'duplicate-id',
      ObservableInvalidSubcode.danglingReference => 'dangling-reference',
      ObservableInvalidSubcode.evidenceCycle => 'evidence-cycle',
      ObservableInvalidSubcode.unsupportedCompleteness =>
        'unsupported-completeness',
      ObservableInvalidSubcode.unsupportedSchemaVersion =>
        'unsupported-schema-version',
      ObservableInvalidSubcode.missingCapability => 'missing-capability',
      ObservableInvalidSubcode.invalidLineage => 'invalid-lineage',
    };
  }
}

enum ObservableCompleteness {
  validatedTopology,
  provenScalarNoop,
}

extension ObservableCompletenessX on ObservableCompleteness {
  String get wireValue {
    return switch (this) {
      ObservableCompleteness.validatedTopology => 'complete/validated-topology',
      ObservableCompleteness.provenScalarNoop => 'complete/proven-scalar-noop',
    };
  }

  static ObservableCompleteness? fromWire(String value) {
    return switch (value) {
      'complete/validated-topology' => ObservableCompleteness.validatedTopology,
      'complete/proven-scalar-noop' => ObservableCompleteness.provenScalarNoop,
      _ => null,
    };
  }
}

enum ObservableNodeKind {
  program,
  driverSource,
  handle,
  streamOp,
  stateSlot,
  hiddenLedger,
  sink,
  task,
  failureDomain,
  value,
  unknown,
}

extension ObservableNodeKindX on ObservableNodeKind {
  String get wireValue {
    return switch (this) {
      ObservableNodeKind.program => 'Program',
      ObservableNodeKind.driverSource => 'DriverSource',
      ObservableNodeKind.handle => 'Handle',
      ObservableNodeKind.streamOp => 'StreamOp',
      ObservableNodeKind.stateSlot => 'StateSlot',
      ObservableNodeKind.hiddenLedger => 'HiddenLedger',
      ObservableNodeKind.sink => 'Sink',
      ObservableNodeKind.task => 'Task',
      ObservableNodeKind.failureDomain => 'FailureDomain',
      ObservableNodeKind.value => 'Value',
      ObservableNodeKind.unknown => 'unknown',
    };
  }

  static ObservableNodeKind fromWire(String value) {
    return switch (value) {
      'Program' => ObservableNodeKind.program,
      'DriverSource' => ObservableNodeKind.driverSource,
      'Handle' => ObservableNodeKind.handle,
      'StreamOp' => ObservableNodeKind.streamOp,
      'StateSlot' => ObservableNodeKind.stateSlot,
      'HiddenLedger' => ObservableNodeKind.hiddenLedger,
      'Sink' => ObservableNodeKind.sink,
      'Task' => ObservableNodeKind.task,
      'FailureDomain' => ObservableNodeKind.failureDomain,
      'Value' => ObservableNodeKind.value,
      _ => ObservableNodeKind.unknown,
    };
  }

  static const List<ObservableNodeKind> legendKinds = <ObservableNodeKind>[
    ObservableNodeKind.program,
    ObservableNodeKind.driverSource,
    ObservableNodeKind.handle,
    ObservableNodeKind.streamOp,
    ObservableNodeKind.stateSlot,
    ObservableNodeKind.hiddenLedger,
    ObservableNodeKind.sink,
    ObservableNodeKind.task,
    ObservableNodeKind.failureDomain,
    ObservableNodeKind.value,
  ];
}

enum ObservableEdgeKind {
  flow,
  intent,
  ownership,
  borrow,
  mutation,
  backpressure,
  commit,
  happensBefore,
  failure,
  placement,
  unknown,
}

extension ObservableEdgeKindX on ObservableEdgeKind {
  String get wireValue {
    return switch (this) {
      ObservableEdgeKind.flow => 'Flow',
      ObservableEdgeKind.intent => 'Intent',
      ObservableEdgeKind.ownership => 'Ownership',
      ObservableEdgeKind.borrow => 'Borrow',
      ObservableEdgeKind.mutation => 'Mutation',
      ObservableEdgeKind.backpressure => 'Backpressure',
      ObservableEdgeKind.commit => 'Commit',
      ObservableEdgeKind.happensBefore => 'HappensBefore',
      ObservableEdgeKind.failure => 'Failure',
      ObservableEdgeKind.placement => 'Placement',
      ObservableEdgeKind.unknown => 'unknown',
    };
  }

  static ObservableEdgeKind fromWire(String value) {
    return switch (value) {
      'Flow' => ObservableEdgeKind.flow,
      'Intent' => ObservableEdgeKind.intent,
      'Ownership' => ObservableEdgeKind.ownership,
      'Borrow' => ObservableEdgeKind.borrow,
      'Mutation' => ObservableEdgeKind.mutation,
      'Backpressure' => ObservableEdgeKind.backpressure,
      'Commit' => ObservableEdgeKind.commit,
      'HappensBefore' => ObservableEdgeKind.happensBefore,
      'Failure' => ObservableEdgeKind.failure,
      'Placement' => ObservableEdgeKind.placement,
      _ => ObservableEdgeKind.unknown,
    };
  }

  static const List<ObservableEdgeKind> legendKinds = <ObservableEdgeKind>[
    ObservableEdgeKind.flow,
    ObservableEdgeKind.intent,
    ObservableEdgeKind.ownership,
    ObservableEdgeKind.borrow,
    ObservableEdgeKind.mutation,
    ObservableEdgeKind.backpressure,
    ObservableEdgeKind.commit,
    ObservableEdgeKind.happensBefore,
    ObservableEdgeKind.failure,
    ObservableEdgeKind.placement,
  ];
}

enum GraphItemChangeTag { unchanged, added, removed, changed }

extension GraphItemChangeTagX on GraphItemChangeTag {
  String get wireValue {
    return switch (this) {
      GraphItemChangeTag.unchanged => 'unchanged',
      GraphItemChangeTag.added => 'added',
      GraphItemChangeTag.removed => 'removed',
      GraphItemChangeTag.changed => 'changed',
    };
  }
}

class ObservableProducer {
  const ObservableProducer({required this.name, required this.version});

  final String name;
  final String version;

  String get identityKey => '$name@$version';

  @override
  bool operator ==(Object other) {
    return other is ObservableProducer &&
        other.name == name &&
        other.version == version;
  }

  @override
  int get hashCode => Object.hash(name, version);
}

class ObservableCompilationUnit {
  const ObservableCompilationUnit({
    required this.packageName,
    required this.manifestPath,
    required this.entryPath,
  });

  final String packageName;
  final String manifestPath;
  final String entryPath;

  String get identityKey => '$packageName\u001f$manifestPath\u001f$entryPath';

  @override
  bool operator ==(Object other) {
    return other is ObservableCompilationUnit &&
        other.packageName == packageName &&
        other.manifestPath == manifestPath &&
        other.entryPath == entryPath;
  }

  @override
  int get hashCode => Object.hash(packageName, manifestPath, entryPath);
}

class ObservableAnchorRecord {
  const ObservableAnchorRecord({
    required this.ref,
    required this.path,
    required this.precision,
    this.extensions = const <String, Object?>{},
  });

  final String ref;
  final String path;
  final String precision;
  final Map<String, Object?> extensions;
}

class ObservableEvidenceRecord {
  const ObservableEvidenceRecord({
    required this.ref,
    required this.producerRule,
    required this.ruleVersion,
    required this.subjects,
    required this.prerequisites,
    required this.anchors,
    this.extensions = const <String, Object?>{},
  });

  final String ref;
  final String producerRule;
  final String ruleVersion;
  final List<String> subjects;
  final List<String> prerequisites;
  final List<String> anchors;
  final Map<String, Object?> extensions;
}

class ObservableNodeRecord {
  const ObservableNodeRecord({
    required this.id,
    required this.kind,
    required this.rawKind,
    required this.role,
    required this.anchors,
    required this.evidence,
    this.extensions = const <String, Object?>{},
  });

  final String id;
  final ObservableNodeKind kind;
  final String rawKind;
  final String role;
  final List<String> anchors;
  final String evidence;
  final Map<String, Object?> extensions;
}

class ObservableEdgeRecord {
  const ObservableEdgeRecord({
    required this.id,
    required this.kind,
    required this.rawKind,
    required this.from,
    required this.to,
    required this.evidence,
    this.extensions = const <String, Object?>{},
  });

  final String id;
  final ObservableEdgeKind kind;
  final String rawKind;
  final String from;
  final String to;
  final String evidence;
  final Map<String, Object?> extensions;
}

class ObservableFactRecord {
  const ObservableFactRecord({
    required this.id,
    required this.subject,
    required this.predicate,
    required this.canonicalValue,
    required this.evidence,
    this.extensions = const <String, Object?>{},
  });

  final String id;
  final String subject;
  final String predicate;
  final String canonicalValue;
  final String evidence;
  final Map<String, Object?> extensions;
}

class ObservableSnapshot {
  const ObservableSnapshot({
    required this.contract,
    required this.schemaVersion,
    required this.stability,
    required this.producer,
    required this.capabilities,
    required this.compilationUnit,
    required this.completeness,
    required this.root,
    required this.nodes,
    required this.edges,
    required this.facts,
    required this.anchors,
    required this.evidence,
    this.diagnostics = const <ObservableDiagnosticRecord>[],
    this.lineage = const <ObservableLineageRecord>[],
    this.parentSnapshotId,
    this.extensions = const <String, Object?>{},
  });

  final String contract;
  final int schemaVersion;
  final String stability;
  final ObservableProducer producer;
  final List<String> capabilities;
  final ObservableCompilationUnit compilationUnit;
  final ObservableCompleteness completeness;
  final String? root;
  final List<ObservableNodeRecord> nodes;
  final List<ObservableEdgeRecord> edges;
  final List<ObservableFactRecord> facts;
  final List<ObservableAnchorRecord> anchors;
  final List<ObservableEvidenceRecord> evidence;
  final List<ObservableDiagnosticRecord> diagnostics;
  final List<ObservableLineageRecord> lineage;
  final String? parentSnapshotId;
  final Map<String, Object?> extensions;

  ObservableNodeRecord? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  ObservableEdgeRecord? edgeById(String id) {
    for (final edge in edges) {
      if (edge.id == id) {
        return edge;
      }
    }
    return null;
  }

  ObservableAnchorRecord? anchorByRef(String ref) {
    for (final anchor in anchors) {
      if (anchor.ref == ref) {
        return anchor;
      }
    }
    return null;
  }

  ObservableEvidenceRecord? evidenceByRef(String ref) {
    for (final record in evidence) {
      if (record.ref == ref) {
        return record;
      }
    }
    return null;
  }

  ObservableDiagnosticRecord? diagnosticById(String id) {
    for (final record in diagnostics) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  ObservableFactRecord? factById(String id) {
    for (final fact in facts) {
      if (fact.id == id) {
        return fact;
      }
    }
    return null;
  }

  List<ObservableFactRecord> factsForSubject(String nodeId) {
    return facts
        .where((fact) => fact.subject == nodeId)
        .toList(growable: false);
  }

  Set<String> get nodeIds =>
      nodes.map((node) => node.id).toSet();

  Set<String> get edgeIds =>
      edges.map((edge) => edge.id).toSet();
}

class SnapshotIdentity {
  const SnapshotIdentity({
    required this.snapshotId,
    required this.compilationUnitKey,
  });

  factory SnapshotIdentity.fromSnapshot({
    required ObservableSnapshot snapshot,
    required String snapshotId,
  }) {
    return SnapshotIdentity(
      snapshotId: snapshotId,
      compilationUnitKey: snapshot.compilationUnit.identityKey,
    );
  }

  final String snapshotId;
  final String compilationUnitKey;

  @override
  bool operator ==(Object other) {
    return other is SnapshotIdentity && other.snapshotId == snapshotId;
  }

  @override
  int get hashCode => snapshotId.hashCode;
}

class ObservableDecodeFailure {
  const ObservableDecodeFailure({
    required this.subcode,
    required this.detail,
  });

  final ObservableInvalidSubcode subcode;
  final String detail;

  ObservableReasonCode get reason => ObservableReasonCode.invalidSnapshot;
}

class ObservableDecodeResult {
  const ObservableDecodeResult.ok(this.snapshot) : failure = null;

  const ObservableDecodeResult.invalid(this.failure) : snapshot = null;

  final ObservableSnapshot? snapshot;
  final ObservableDecodeFailure? failure;

  bool get isOk => snapshot != null;
}

class ObservableChangeSet {
  const ObservableChangeSet({
    required this.addedNodeIds,
    required this.removedNodeIds,
    required this.addedEdgeIds,
    required this.removedEdgeIds,
    this.changedNodeIds = const <String>[],
    this.changedEdgeIds = const <String>[],
    this.source = ObservableChangeSetSource.idSetComparison,
    this.operations = const <ObservableDeltaOperation>[],
    this.metadataChanges = const <ObservableMetadataChange>[],
    this.lineage = const <ObservableLineageRecord>[],
  });

  final List<String> addedNodeIds;
  final List<String> removedNodeIds;
  final List<String> addedEdgeIds;
  final List<String> removedEdgeIds;
  final List<String> changedNodeIds;
  final List<String> changedEdgeIds;
  final ObservableChangeSetSource source;
  final List<ObservableDeltaOperation> operations;
  final List<ObservableMetadataChange> metadataChanges;
  final List<ObservableLineageRecord> lineage;

  int get addedCount => addedNodeIds.length + addedEdgeIds.length;

  int get removedCount => removedNodeIds.length + removedEdgeIds.length;

  int get changedCount => changedNodeIds.length + changedEdgeIds.length;

  int get renamedCount => _lineageCount(ObservableLineageKind.rename);

  int get movedCount => _lineageCount(ObservableLineageKind.move);

  int get splitCount => _lineageCount(ObservableLineageKind.split);

  int get mergedCount => _lineageCount(ObservableLineageKind.merge);

  int _lineageCount(ObservableLineageKind kind) {
    var count = 0;
    for (final record in lineage) {
      if (record.kind == kind) {
        count += 1;
      }
    }
    return count;
  }

  bool get isEmpty =>
      addedCount == 0 &&
      removedCount == 0 &&
      changedCount == 0 &&
      lineage.isEmpty;
}

class ObservableLineageWindowEntry {
  const ObservableLineageWindowEntry({
    required this.snapshotId,
    this.parentSnapshotId,
    required this.changeSource,
    required this.changeSet,
    required this.lineageRecords,
  });

  final String snapshotId;
  final String? parentSnapshotId;
  final ObservableChangeSetSource changeSource;
  final ObservableChangeSet changeSet;
  final List<ObservableLineageRecord> lineageRecords;
}

class ProjectedGraphNode {
  const ProjectedGraphNode({
    required this.id,
    required this.kind,
    required this.rawKind,
    required this.role,
    required this.groupKey,
    required this.changeTag,
    required this.anchorRefs,
    required this.facts,
    required this.evidenceRef,
    this.sourceSnapshot,
    this.continuity,
    this.layoutKey,
  });

  final String id;
  final ObservableNodeKind kind;
  final String rawKind;
  final String role;
  final String groupKey;
  final GraphItemChangeTag changeTag;
  final List<String> anchorRefs;
  final List<ObservableFactRecord> facts;
  final String evidenceRef;
  final ObservableSnapshot? sourceSnapshot;
  final ObservableContinuityMark? continuity;
  final String? layoutKey;
}

class ProjectedGraphEdge {
  const ProjectedGraphEdge({
    required this.id,
    required this.kind,
    required this.rawKind,
    required this.from,
    required this.to,
    required this.changeTag,
    required this.evidenceRef,
  });

  final String id;
  final ObservableEdgeKind kind;
  final String rawKind;
  final String from;
  final String to;
  final GraphItemChangeTag changeTag;
  final String evidenceRef;
}

class GraphProjection {
  const GraphProjection({
    required this.nodes,
    required this.edges,
    required this.anchors,
    required this.evidence,
    this.compilationUnit,
    this.root,
    this.lineageLinks = const <ObservableLineageLink>[],
  });

  final List<ProjectedGraphNode> nodes;
  final List<ProjectedGraphEdge> edges;
  final List<ObservableAnchorRecord> anchors;
  final List<ObservableEvidenceRecord> evidence;
  final ObservableCompilationUnit? compilationUnit;
  final String? root;
  final List<ObservableLineageLink> lineageLinks;

  ProjectedGraphNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  ObservableAnchorRecord? anchorByRef(String ref) {
    for (final anchor in anchors) {
      if (anchor.ref == ref) {
        return anchor;
      }
    }
    return null;
  }

  ObservableEvidenceRecord? evidenceByRef(String ref) {
    for (final record in evidence) {
      if (record.ref == ref) {
        return record;
      }
    }
    return null;
  }
}

class LayoutRect {
  const LayoutRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  bool containsPoint(double px, double py) {
    return px >= x && px <= right && py >= y && py <= bottom;
  }

  bool intersects(LayoutRect other) {
    return x < other.right &&
        right > other.x &&
        y < other.bottom &&
        bottom > other.y;
  }

  bool containsRect(LayoutRect other) {
    return other.x >= x &&
        other.y >= y &&
        other.right <= right &&
        other.bottom <= bottom;
  }
}

class LayoutPoint {
  const LayoutPoint(this.x, this.y);

  final double x;
  final double y;
}

class LayoutPolyline {
  const LayoutPolyline({required this.edgeId, required this.points});

  final String edgeId;
  final List<LayoutPoint> points;
}

class ObservableLayoutResult {
  const ObservableLayoutResult({
    required this.nodeRects,
    required this.groupRects,
    required this.edgePolylines,
    required this.width,
    required this.height,
  });

  final Map<String, LayoutRect> nodeRects;
  final Map<String, LayoutRect> groupRects;
  final List<LayoutPolyline> edgePolylines;
  final double width;
  final double height;

  String fingerprint() {
    final nodeKeys = nodeRects.keys.toList()..sort();
    final groupKeys = groupRects.keys.toList()..sort();
    final edgeKeys = edgePolylines.map((line) => line.edgeId).toList()..sort();
    final buffer = StringBuffer();
    for (final key in nodeKeys) {
      final rect = nodeRects[key]!;
      buffer.write(
        'n:$key:${rect.x.toStringAsFixed(3)},${rect.y.toStringAsFixed(3)},'
        '${rect.width.toStringAsFixed(3)},${rect.height.toStringAsFixed(3)};',
      );
    }
    for (final key in groupKeys) {
      final rect = groupRects[key]!;
      buffer.write(
        'g:$key:${rect.x.toStringAsFixed(3)},${rect.y.toStringAsFixed(3)},'
        '${rect.width.toStringAsFixed(3)},${rect.height.toStringAsFixed(3)};',
      );
    }
    for (final edgeId in edgeKeys) {
      final line = edgePolylines.firstWhere((item) => item.edgeId == edgeId);
      buffer.write('e:$edgeId:');
      for (final point in line.points) {
        buffer.write(
          '${point.x.toStringAsFixed(3)},${point.y.toStringAsFixed(3)}/',
        );
      }
      buffer.write(';');
    }
    return buffer.toString();
  }
}

class ObservableLayoutOutcome {
  const ObservableLayoutOutcome.ok(this.layout)
    : reason = null,
      detail = null,
      nodeCount = 0,
      edgeCount = 0;

  factory ObservableLayoutOutcome.tooLarge({
    required int nodeCount,
    required int edgeCount,
  }) {
    return ObservableLayoutOutcome._tooLarge(
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      detail: 'nodes=$nodeCount edges=$edgeCount',
    );
  }

  const ObservableLayoutOutcome._tooLarge({
    required this.nodeCount,
    required this.edgeCount,
    required this.detail,
  }) : layout = null,
       reason = ObservableReasonCode.snapshotTooLarge;

  final ObservableLayoutResult? layout;
  final ObservableReasonCode? reason;
  final String? detail;
  final int nodeCount;
  final int edgeCount;

  bool get isOk => layout != null;
}

class ObservableGraphCounters {
  const ObservableGraphCounters({
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.cacheEvictions = 0,
    this.refreshRuns = 0,
    this.cancelledRuns = 0,
    this.retainedGenerations = 0,
    this.evictedGenerations = 0,
    this.appliedDeltas = 0,
    this.rejectedDeltas = 0,
    this.fullSnapshotFallbacks = 0,
  });

  final int cacheHits;
  final int cacheMisses;
  final int cacheEvictions;
  final int refreshRuns;
  final int cancelledRuns;
  final int retainedGenerations;
  final int evictedGenerations;
  final int appliedDeltas;
  final int rejectedDeltas;
  final int fullSnapshotFallbacks;

  ObservableGraphCounters copyWith({
    int? cacheHits,
    int? cacheMisses,
    int? cacheEvictions,
    int? refreshRuns,
    int? cancelledRuns,
    int? retainedGenerations,
    int? evictedGenerations,
    int? appliedDeltas,
    int? rejectedDeltas,
    int? fullSnapshotFallbacks,
  }) {
    return ObservableGraphCounters(
      cacheHits: cacheHits ?? this.cacheHits,
      cacheMisses: cacheMisses ?? this.cacheMisses,
      cacheEvictions: cacheEvictions ?? this.cacheEvictions,
      refreshRuns: refreshRuns ?? this.refreshRuns,
      cancelledRuns: cancelledRuns ?? this.cancelledRuns,
      retainedGenerations: retainedGenerations ?? this.retainedGenerations,
      evictedGenerations: evictedGenerations ?? this.evictedGenerations,
      appliedDeltas: appliedDeltas ?? this.appliedDeltas,
      rejectedDeltas: rejectedDeltas ?? this.rejectedDeltas,
      fullSnapshotFallbacks: fullSnapshotFallbacks ?? this.fullSnapshotFallbacks,
    );
  }
}

class ObservableGraphState {
  const ObservableGraphState({
    required this.availability,
    this.reason,
    this.detail,
    this.currentIdentity,
    this.previousIdentity,
    this.changeSet,
    this.projection,
    this.layout,
    this.lastFreshAt,
    this.selectedNodeId,
    this.selectedAnchorResolved = false,
    this.selectedAnchorRelativePath,
    this.snapshot,
    this.lineageHistory = const <ObservableLineageWindowEntry>[],
    this.counters = const ObservableGraphCounters(),
  });

  factory ObservableGraphState.initial() {
    return const ObservableGraphState(
      availability: ObservableAvailability.unavailable,
      reason: ObservableReasonCode.noToolchain,
      detail: 'Observable topology has not been negotiated yet.',
    );
  }

  final ObservableAvailability availability;
  final ObservableReasonCode? reason;
  final String? detail;
  final SnapshotIdentity? currentIdentity;
  final SnapshotIdentity? previousIdentity;
  final ObservableChangeSet? changeSet;
  final GraphProjection? projection;
  final ObservableLayoutResult? layout;
  final DateTime? lastFreshAt;
  final String? selectedNodeId;
  final bool selectedAnchorResolved;
  final String? selectedAnchorRelativePath;
  final ObservableSnapshot? snapshot;
  final List<ObservableLineageWindowEntry> lineageHistory;
  final ObservableGraphCounters counters;

  ObservableGraphState copyWith({
    ObservableAvailability? availability,
    ObservableReasonCode? reason,
    String? detail,
    SnapshotIdentity? currentIdentity,
    SnapshotIdentity? previousIdentity,
    ObservableChangeSet? changeSet,
    GraphProjection? projection,
    ObservableLayoutResult? layout,
    DateTime? lastFreshAt,
    String? selectedNodeId,
    bool? selectedAnchorResolved,
    String? selectedAnchorRelativePath,
    ObservableSnapshot? snapshot,
    List<ObservableLineageWindowEntry>? lineageHistory,
    ObservableGraphCounters? counters,
    bool clearReason = false,
    bool clearSelection = false,
    bool clearChangeSet = false,
  }) {
    return ObservableGraphState(
      availability: availability ?? this.availability,
      reason: clearReason ? null : (reason ?? this.reason),
      detail: detail ?? this.detail,
      currentIdentity: currentIdentity ?? this.currentIdentity,
      previousIdentity: previousIdentity ?? this.previousIdentity,
      changeSet: clearChangeSet ? null : (changeSet ?? this.changeSet),
      projection: projection ?? this.projection,
      layout: layout ?? this.layout,
      lastFreshAt: lastFreshAt ?? this.lastFreshAt,
      selectedNodeId: clearSelection
          ? null
          : (selectedNodeId ?? this.selectedNodeId),
      selectedAnchorResolved: clearSelection
          ? false
          : (selectedAnchorResolved ?? this.selectedAnchorResolved),
      selectedAnchorRelativePath: clearSelection
          ? null
          : (selectedAnchorRelativePath ?? this.selectedAnchorRelativePath),
      snapshot: snapshot ?? this.snapshot,
      lineageHistory: lineageHistory ?? this.lineageHistory,
      counters: counters ?? this.counters,
    );
  }
}

class ObservableSnapshotPublishRequest {
  const ObservableSnapshotPublishRequest({
    required this.workspaceRoot,
    required this.manifestPath,
    required this.pafioBinary,
    required this.compilerBinary,
    this.schemaVersion = kObservableStaticSnapshotSchemaVersion,
    this.requiredCapabilities = kObservableRequiredCapabilities,
    this.outputTree,
    this.parentSnapshotPath,
    this.requestDelta = false,
  });

  final String workspaceRoot;
  final String manifestPath;
  final String pafioBinary;
  final String compilerBinary;
  final int schemaVersion;
  final List<String> requiredCapabilities;
  final String? outputTree;
  final String? parentSnapshotPath;
  final bool requestDelta;
}

class ObservableSnapshotPublishResult {
  const ObservableSnapshotPublishResult({
    required this.status,
    this.bytes,
    this.artifactPath,
    this.receipt,
    this.detail,
    this.reason,
    this.deltaBytes,
    this.degradation,
  });

  factory ObservableSnapshotPublishResult.succeeded({
    required List<int> bytes,
    required String artifactPath,
    Object? receipt,
    List<int>? deltaBytes,
    String? degradation,
  }) {
    return ObservableSnapshotPublishResult(
      status: ObservablePublishStatus.succeeded,
      bytes: bytes,
      artifactPath: artifactPath,
      receipt: receipt,
      deltaBytes: deltaBytes,
      degradation: degradation,
    );
  }

  factory ObservableSnapshotPublishResult.failed({
    required String detail,
    ObservableReasonCode reason = ObservableReasonCode.publicationFailed,
  }) {
    return ObservableSnapshotPublishResult(
      status: ObservablePublishStatus.failed,
      reason: reason,
      detail: detail,
    );
  }

  factory ObservableSnapshotPublishResult.cancelled() {
    return const ObservableSnapshotPublishResult(
      status: ObservablePublishStatus.cancelled,
      reason: ObservableReasonCode.cancelled,
      detail: 'Publication was cancelled.',
    );
  }

  factory ObservableSnapshotPublishResult.unsupported({
    required String detail,
  }) {
    return ObservableSnapshotPublishResult(
      status: ObservablePublishStatus.unsupported,
      reason: ObservableReasonCode.unsupportedPlatform,
      detail: detail,
    );
  }

  final ObservablePublishStatus status;
  final List<int>? bytes;
  final String? artifactPath;
  final Object? receipt;
  final String? detail;
  final ObservableReasonCode? reason;
  final List<int>? deltaBytes;
  final String? degradation;

  bool get isSuccess =>
      status == ObservablePublishStatus.succeeded && bytes != null;
}

enum ObservablePublishStatus { succeeded, failed, cancelled, unsupported }

abstract class ObservableSnapshotPublisher {
  Future<ObservableSnapshotPublishResult> publish(
    ObservableSnapshotPublishRequest request,
  );

  void cancel();
}

class ObservableCacheMetrics {
  const ObservableCacheMetrics({
    this.hits = 0,
    this.misses = 0,
    this.evictions = 0,
  });

  final int hits;
  final int misses;
  final int evictions;

  ObservableCacheMetrics copyWith({int? hits, int? misses, int? evictions}) {
    return ObservableCacheMetrics(
      hits: hits ?? this.hits,
      misses: misses ?? this.misses,
      evictions: evictions ?? this.evictions,
    );
  }
}

class ObservableNegotiationDecision {
  const ObservableNegotiationDecision({
    required this.accepted,
    required this.availability,
    this.reason,
    this.detail,
    this.snapshotDeltaAvailable = false,
    this.producerLineageAvailable = false,
  });

  factory ObservableNegotiationDecision.ok({
    bool snapshotDeltaAvailable = false,
    bool producerLineageAvailable = false,
  }) {
    return ObservableNegotiationDecision(
      accepted: true,
      availability: ObservableAvailability.refreshing,
      snapshotDeltaAvailable: snapshotDeltaAvailable,
      producerLineageAvailable: producerLineageAvailable,
    );
  }

  factory ObservableNegotiationDecision.reject({
    required ObservableAvailability availability,
    required ObservableReasonCode reason,
    required String detail,
  }) {
    return ObservableNegotiationDecision(
      accepted: false,
      availability: availability,
      reason: reason,
      detail: detail,
    );
  }

  final bool accepted;
  final ObservableAvailability availability;
  final ObservableReasonCode? reason;
  final String? detail;
  final bool snapshotDeltaAvailable;
  final bool producerLineageAvailable;
}
