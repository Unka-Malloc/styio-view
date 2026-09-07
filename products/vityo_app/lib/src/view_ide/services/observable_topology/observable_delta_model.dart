/// Frozen styio.observable.delta 0.1 types, lineage records, and adapter constants.
///
/// Isolate-safe and Flutter-free. Spellings match the Styio observable SSOT.
library;

const String kObservableDeltaContract = 'styio.observable.delta';
const int kObservableDeltaSchemaMajor = 0;
const int kObservableDeltaSchemaMinor = 1;
const String kObservableDeltaStability = 'incubating';
const String kObservableDeltaCapability = 'snapshot-delta';
const String kObservableLineageCapability = 'producer-lineage';
const String kObservableMachineInfoOptionalCapabilitiesKey =
    'optional_capabilities';
const String kObservableDeltaArtifactSuffix = '.observable-delta.json';
const String kObservablePafioParentSnapshotOption =
    '--observable-parent-snapshot';
const String kObservableCompilePlanParentSnapshotField = 'parent_snapshot_path';
const String kObservableReceiptObservableField = 'observable_static_snapshot';
const String kObservableReceiptDeltaKey = 'delta';
const String kObservableProducerFullSnapshotRequired = 'full_snapshot_required';
const String kObservablePafioUsageErrorCategory = 'UsageError';
const int kObservableLineageWindowGenerations = 8;
const String kObservableSnapshotIdPrefix = 's1_';
const String kObservableLineageIdPrefix = 'l1_';
const String kObservableDiagnosticIdPrefix = 'd1_';
const String kObservableMetadataSnapshotKey = 'snapshot';
const String kObservableDetailNoParent = 'no-parent';
const String kObservableDetailNoDeltaArtifact = 'no-delta-artifact';
const String kObservableDetailProducerFullSnapshotRequired =
    'producer-full-snapshot-required';
const String kObservableDetailPreviousDeltaRejected = 'previous-delta-rejected';
const String kObservableDetailDeltaTransportUnavailable =
    'delta-transport-unavailable';

const List<String> kObservableDeltaClosedCapabilities = <String>[
  'file-source-anchors',
  'producer-evidence',
  'static-topology-edges',
  'static-topology-facts',
  'static-topology-nodes',
  'snapshot-delta',
  'producer-lineage',
  'bounded-query',
];

const List<String> kObservableSnapshotCanonicalKeys = <String>[
  'contract',
  'schema_version',
  'stability',
  'producer',
  'capabilities',
  'compilation_unit',
  'completeness',
  'root',
  'nodes',
  'edges',
  'facts',
  'anchors',
  'evidence',
  'diagnostics',
  'lineage',
  'parent_snapshot_id',
];

const List<String> kObservableAdditiveSnapshotKeys = <String>[
  'diagnostics',
  'lineage',
  'parent_snapshot_id',
];

const List<String> kObservableMetadataFieldNames = <String>[
  'completeness',
  'producer_name',
  'producer_version',
  'root',
  'capabilities',
  'package_name',
  'manifest_path',
  'entry_path',
];

/// Transport spellings confirmed against sibling Styio/Pafio worktrees.
enum ObservableConstantConfirmation { confirmed, pendingUpstream }

extension ObservableConstantConfirmationX on ObservableConstantConfirmation {
  String get wireValue {
    return switch (this) {
      ObservableConstantConfirmation.confirmed => 'confirmed',
      ObservableConstantConfirmation.pendingUpstream => 'pending upstream',
    };
  }
}

class ObservableAdapterConstant {
  const ObservableAdapterConstant({
    required this.name,
    required this.value,
    required this.status,
    required this.note,
  });

  final String name;
  final String value;
  final ObservableConstantConfirmation status;
  final String note;
}

const List<ObservableAdapterConstant>
kObservableDeltaAdapterConstants = <ObservableAdapterConstant>[
  ObservableAdapterConstant(
    name: 'snapshot-delta',
    value: kObservableDeltaCapability,
    status: ObservableConstantConfirmation.confirmed,
    note:
        'Styio machine-info observable_static_snapshot.optional_capabilities; also accepted in capabilities',
  ),
  ObservableAdapterConstant(
    name: 'producer-lineage',
    value: kObservableLineageCapability,
    status: ObservableConstantConfirmation.confirmed,
    note:
        'Styio machine-info observable_static_snapshot.optional_capabilities; also accepted in capabilities',
  ),
  ObservableAdapterConstant(
    name: 'delta-contract',
    value: kObservableDeltaContract,
    status: ObservableConstantConfirmation.confirmed,
    note: 'Styio delta envelope contract',
  ),
  ObservableAdapterConstant(
    name: 'delta-artifact-suffix',
    value: kObservableDeltaArtifactSuffix,
    status: ObservableConstantConfirmation.confirmed,
    note:
        'Styio DeltaPublication.hpp kDeltaArtifactSuffix; listed in receipt artifacts after the snapshot',
  ),
  ObservableAdapterConstant(
    name: 'pafio-parent-snapshot-option',
    value: kObservablePafioParentSnapshotOption,
    status: ObservableConstantConfirmation.confirmed,
    note:
        'Pafio CLI Support.cpp parses --observable-parent-snapshot and writes emit.observable_static_snapshot.parent_snapshot_path',
  ),
  ObservableAdapterConstant(
    name: 'compile-plan-parent-snapshot-field',
    value: kObservableCompilePlanParentSnapshotField,
    status: ObservableConstantConfirmation.confirmed,
    note: 'emit.observable_static_snapshot.parent_snapshot_path',
  ),
  ObservableAdapterConstant(
    name: 'receipt-delta-field',
    value: '$kObservableReceiptObservableField.$kObservableReceiptDeltaKey',
    status: ObservableConstantConfirmation.confirmed,
    note:
        'Styio receipt observable_static_snapshot.delta is published or full_snapshot_required',
  ),
  ObservableAdapterConstant(
    name: 'producer-full-snapshot-required',
    value: kObservableProducerFullSnapshotRequired,
    status: ObservableConstantConfirmation.confirmed,
    note: 'Styio service degradation reason full_snapshot_required',
  ),
  ObservableAdapterConstant(
    name: 'pafio-usage-error-category',
    value: kObservablePafioUsageErrorCategory,
    status: ObservableConstantConfirmation.confirmed,
    note: 'Pafio CommandError category UsageError',
  ),
];

enum ObservableDeltaOp { add, remove, replaceFields }

extension ObservableDeltaOpX on ObservableDeltaOp {
  String get wireValue {
    return switch (this) {
      ObservableDeltaOp.add => 'add',
      ObservableDeltaOp.remove => 'remove',
      ObservableDeltaOp.replaceFields => 'replace_fields',
    };
  }

  static ObservableDeltaOp? fromWire(String value) {
    return switch (value) {
      'add' => ObservableDeltaOp.add,
      'remove' => ObservableDeltaOp.remove,
      'replace_fields' => ObservableDeltaOp.replaceFields,
      _ => null,
    };
  }
}

enum ObservableDeltaCategory {
  metadata,
  nodes,
  edges,
  facts,
  diagnostics,
  anchors,
  evidence,
  lineage,
}

extension ObservableDeltaCategoryX on ObservableDeltaCategory {
  String get wireValue {
    return switch (this) {
      ObservableDeltaCategory.metadata => 'metadata',
      ObservableDeltaCategory.nodes => 'nodes',
      ObservableDeltaCategory.edges => 'edges',
      ObservableDeltaCategory.facts => 'facts',
      ObservableDeltaCategory.diagnostics => 'diagnostics',
      ObservableDeltaCategory.anchors => 'anchors',
      ObservableDeltaCategory.evidence => 'evidence',
      ObservableDeltaCategory.lineage => 'lineage',
    };
  }

  bool get isAdditiveArray {
    return this == ObservableDeltaCategory.diagnostics ||
        this == ObservableDeltaCategory.lineage;
  }

  String get identityField {
    return switch (this) {
      ObservableDeltaCategory.anchors ||
      ObservableDeltaCategory.evidence => 'ref',
      _ => 'id',
    };
  }

  static ObservableDeltaCategory? fromWire(String value) {
    return switch (value) {
      'metadata' => ObservableDeltaCategory.metadata,
      'nodes' => ObservableDeltaCategory.nodes,
      'edges' => ObservableDeltaCategory.edges,
      'facts' => ObservableDeltaCategory.facts,
      'diagnostics' => ObservableDeltaCategory.diagnostics,
      'anchors' => ObservableDeltaCategory.anchors,
      'evidence' => ObservableDeltaCategory.evidence,
      'lineage' => ObservableDeltaCategory.lineage,
      _ => null,
    };
  }
}

enum ObservableLineageKind { rename, move, split, merge }

extension ObservableLineageKindX on ObservableLineageKind {
  String get wireValue {
    return switch (this) {
      ObservableLineageKind.rename => 'rename',
      ObservableLineageKind.move => 'move',
      ObservableLineageKind.split => 'split',
      ObservableLineageKind.merge => 'merge',
    };
  }

  static ObservableLineageKind? fromWire(String value) {
    return switch (value) {
      'rename' => ObservableLineageKind.rename,
      'move' => ObservableLineageKind.move,
      'split' => ObservableLineageKind.split,
      'merge' => ObservableLineageKind.merge,
      _ => null,
    };
  }

  bool validCardinality({required int priorCount, required int targetCount}) {
    return switch (this) {
      ObservableLineageKind.rename ||
      ObservableLineageKind.move => priorCount == 1 && targetCount == 1,
      ObservableLineageKind.split => priorCount == 1 && targetCount >= 2,
      ObservableLineageKind.merge => priorCount >= 2 && targetCount == 1,
    };
  }
}

enum ObservableChangeSetSource { producerDelta, idSetComparison }

extension ObservableChangeSetSourceX on ObservableChangeSetSource {
  String get wireValue {
    return switch (this) {
      ObservableChangeSetSource.producerDelta => 'producer-delta',
      ObservableChangeSetSource.idSetComparison => 'id-set-comparison',
    };
  }
}

enum ObservableDeltaSubcode {
  majorIncompatible,
  unknownRequiredCapability,
  unsupportedContract,
  missingField,
  malformedIdentity,
  unknownOp,
  unknownCategory,
  keyMismatch,
  duplicateKey,
  missingRecord,
  beforeMismatch,
  unknownMetadataField,
  lineagePriorUnresolved,
  targetMismatch,
  reconstructionMismatch,
  noParent,
  noDeltaArtifact,
  producerFullSnapshotRequired,
  previousDeltaRejected,
  deltaTransportUnavailable,
}

extension ObservableDeltaSubcodeX on ObservableDeltaSubcode {
  String get wireValue {
    return switch (this) {
      ObservableDeltaSubcode.majorIncompatible => 'major-incompatible',
      ObservableDeltaSubcode.unknownRequiredCapability =>
        'unknown-required-capability',
      ObservableDeltaSubcode.unsupportedContract => 'unsupported-contract',
      ObservableDeltaSubcode.missingField => 'missing-field',
      ObservableDeltaSubcode.malformedIdentity => 'malformed-identity',
      ObservableDeltaSubcode.unknownOp => 'unknown-op',
      ObservableDeltaSubcode.unknownCategory => 'unknown-category',
      ObservableDeltaSubcode.keyMismatch => 'key-mismatch',
      ObservableDeltaSubcode.duplicateKey => 'duplicate-key',
      ObservableDeltaSubcode.missingRecord => 'missing-record',
      ObservableDeltaSubcode.beforeMismatch => 'before-mismatch',
      ObservableDeltaSubcode.unknownMetadataField => 'unknown-metadata-field',
      ObservableDeltaSubcode.lineagePriorUnresolved =>
        'lineage-prior-unresolved',
      ObservableDeltaSubcode.targetMismatch => 'target-mismatch',
      ObservableDeltaSubcode.reconstructionMismatch =>
        'reconstruction-mismatch',
      ObservableDeltaSubcode.noParent => 'no-parent',
      ObservableDeltaSubcode.noDeltaArtifact => 'no-delta-artifact',
      ObservableDeltaSubcode.producerFullSnapshotRequired =>
        'producer-full-snapshot-required',
      ObservableDeltaSubcode.previousDeltaRejected => 'previous-delta-rejected',
      ObservableDeltaSubcode.deltaTransportUnavailable =>
        'delta-transport-unavailable',
    };
  }
}

class ObservableFieldReplacement {
  const ObservableFieldReplacement({
    required this.name,
    required this.before,
    required this.after,
  });

  final String name;
  final Object? before;
  final Object? after;
}

class ObservableDeltaOperation {
  const ObservableDeltaOperation({
    required this.op,
    required this.category,
    required this.key,
    this.record,
    this.fields = const <ObservableFieldReplacement>[],
  });

  final ObservableDeltaOp op;
  final ObservableDeltaCategory category;
  final String key;
  final Map<String, Object?>? record;
  final List<ObservableFieldReplacement> fields;
}

class ObservableDeltaEnvelope {
  const ObservableDeltaEnvelope({
    required this.contract,
    required this.schemaMajor,
    required this.schemaMinor,
    required this.stability,
    required this.parentSnapshotId,
    required this.targetSnapshotId,
    required this.requiredCapabilities,
    required this.optionalCapabilities,
    required this.operations,
    this.extensions = const <String, Object?>{},
  });

  final String contract;
  final int schemaMajor;
  final int schemaMinor;
  final String stability;
  final String parentSnapshotId;
  final String targetSnapshotId;
  final List<String> requiredCapabilities;
  final List<String> optionalCapabilities;
  final List<ObservableDeltaOperation> operations;
  final Map<String, Object?> extensions;
}

class ObservableLineageRecord {
  const ObservableLineageRecord({
    required this.id,
    required this.kind,
    required this.prior,
    required this.target,
    required this.producerRule,
    required this.ruleVersion,
    required this.evidence,
    required this.completeness,
    this.extensions = const <String, Object?>{},
  });

  final String id;
  final ObservableLineageKind kind;
  final List<String> prior;
  final List<String> target;
  final String producerRule;
  final String ruleVersion;
  final List<String> evidence;
  final String completeness;
  final Map<String, Object?> extensions;

  bool mentions(String identity) {
    return prior.contains(identity) || target.contains(identity);
  }
}

class ObservableDiagnosticRecord {
  const ObservableDiagnosticRecord({
    required this.id,
    required this.code,
    required this.severity,
    required this.subject,
    required this.evidence,
    this.extensions = const <String, Object?>{},
  });

  final String id;
  final String code;
  final String severity;
  final String subject;
  final String evidence;
  final Map<String, Object?> extensions;
}

class ObservableContinuityMark {
  const ObservableContinuityMark({
    required this.kind,
    required this.lineageId,
    required this.priorIds,
    required this.evidenceRefs,
  });

  final ObservableLineageKind kind;
  final String lineageId;
  final List<String> priorIds;
  final List<String> evidenceRefs;
}

class ObservableLineageLink {
  const ObservableLineageLink({
    required this.fromId,
    required this.toId,
    required this.lineageId,
    required this.kind,
  });

  final String fromId;
  final String toId;
  final String lineageId;
  final ObservableLineageKind kind;
}

class ObservableMetadataChange {
  const ObservableMetadataChange({
    required this.field,
    required this.before,
    required this.after,
  });

  final String field;
  final Object? before;
  final Object? after;
}

class ObservableDeltaDecodeFailure {
  const ObservableDeltaDecodeFailure({
    required this.reason,
    required this.subcode,
    required this.detail,
  });

  final String reason;
  final ObservableDeltaSubcode subcode;
  final String detail;
}

class ObservableDeltaDecodeResult {
  const ObservableDeltaDecodeResult.ok(this.envelope) : failure = null;

  const ObservableDeltaDecodeResult.invalid(this.failure) : envelope = null;

  final ObservableDeltaEnvelope? envelope;
  final ObservableDeltaDecodeFailure? failure;

  bool get isOk => envelope != null;
}

class ObservableDeltaApplyRejection {
  const ObservableDeltaApplyRejection({
    required this.reason,
    required this.subcode,
    required this.detail,
  });

  final String reason;
  final ObservableDeltaSubcode subcode;
  final String detail;
}

class ObservableDeltaApplyResult {
  const ObservableDeltaApplyResult.ok(this.bytes) : rejection = null;

  const ObservableDeltaApplyResult.rejected(this.rejection) : bytes = null;

  final List<int>? bytes;
  final ObservableDeltaApplyRejection? rejection;

  bool get isOk => bytes != null;
}

bool isObservablePrefixedIdentity(String value, String prefix) {
  if (!value.startsWith(prefix)) {
    return false;
  }
  if (value.length != prefix.length + 32) {
    return false;
  }
  for (var i = prefix.length; i < value.length; i += 1) {
    final code = value.codeUnitAt(i);
    final hex = (code >= 48 && code <= 57) || (code >= 97 && code <= 102);
    if (!hex) {
      return false;
    }
  }
  return true;
}

bool isObservableSnapshotIdentity(String value) {
  return isObservablePrefixedIdentity(value, kObservableSnapshotIdPrefix);
}
