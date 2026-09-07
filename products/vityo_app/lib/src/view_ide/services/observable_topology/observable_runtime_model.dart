/// Frozen runtime-events v2 consumer types.
///
/// Isolate-safe and Flutter-free. Spellings match the Styio SSOT. Unknown
/// additive fields are never stored. Unknown non-critical enums decode to
/// `unknown(raw)` variants.
library;

import 'observable_snapshot_model.dart' show ObservableReasonCode;

const String kRuntimeEventsContract = 'styio.observable.runtime-events';
const int kRuntimeEventsSchemaVersion = 2;
const String kRuntimeEventsStability = 'incubating';
const String kRuntimeEventsPrivacyProfile = 'strict';
const String kRuntimeEventsClockUnit = 'ns';
const int kRuntimeEventsSnapshotSchema = 1;
const String kRuntimeEventsMachineInfoKey = 'runtime_events';
const String kRuntimeEventsContractVersionsKey = 'runtime_events';
const String kRuntimeEventsArtifactFileName = 'runtime-events.jsonl';
const String kRuntimeEventsReceiptPathField = 'runtime_events_path';
const String kRuntimePafioEmitOption = '--emit-runtime-observation';
const String kRuntimePafioModeOption = '--runtime-observation-mode';
const String kRuntimePafioCapabilityOption = '--runtime-observation-capability';
const String kRuntimePafioLaneCapacityOption =
    '--runtime-observation-lane-capacity';
const String kRuntimePafioSamplingOption = '--runtime-observation-sampling';

const String kRuntimeInstanceIdPrefix = 'i2_';
const String kRuntimeEventIdPrefix = 'r2_';
const String kRuntimeWaitIdPrefix = 'w2_';
const String kRuntimeExecutionIdPrefix = 'x2_';
const String kRuntimeSnapshotIdPrefix = 's1_';
const String kRuntimeSiteIdPrefix = 'n1_';

const int kRuntimeInstanceSiteMapCapacity = 65536;
const int kRuntimeOpenWaitCapacity = 16384;
const int kRuntimeBlockedLinkCapacity = 4096;
const int kRuntimeSiteEventRingCapacity = 32;
const int kRuntimeUncorrelatedSampleCapacity = 64;
const int kRuntimeUnknownSiteIdCapacity = 64;
const int kRuntimeStaleSnapshotIdCapacity = 16;

const List<String> kRuntimeRequiredCapabilities = <String>[
  'task-lifecycle',
  'loss-accounting',
  'strict-privacy',
];

const List<String> kRuntimeProducerCapabilities = <String>[
  'task-lifecycle',
  'scheduler-queue',
  'wait-runnable',
  'wait-task',
  'wait-backpressure',
  'controller-events',
  'loss-accounting',
  'strict-privacy',
];

const List<String> kRuntimeUnavailableCapabilities = <String>[
  'cancellation',
  'cooperative-suspend',
  'wait-cooperative',
  'wait-io',
  'wait-resource',
  'wait-timer',
];

enum AdapterConstantConfirmation { confirmed, pendingUpstream }

class RuntimeTransportConstant {
  const RuntimeTransportConstant({
    required this.name,
    required this.value,
    required this.confirmation,
    this.source = '',
  });

  final String name;
  final String value;
  final AdapterConstantConfirmation confirmation;
  final String source;
}

/// Transport spellings confirmed against the Styio and Pafio sibling worktrees
/// at implementation time. `pendingUpstream` is unused: every named spelling
/// had landed on the delivering branches.
const List<RuntimeTransportConstant> kRuntimeTransportConstants =
    <RuntimeTransportConstant>[
      RuntimeTransportConstant(
        name: 'machine-info object',
        value: 'runtime_events',
        confirmation: AdapterConstantConfirmation.confirmed,
        source: 'Styio runtime_events_machine_info_json',
      ),
      RuntimeTransportConstant(
        name: 'machine-info schema_versions',
        value: '[2]',
        confirmation: AdapterConstantConfirmation.confirmed,
        source: 'Styio full variant; nano advertises []',
      ),
      RuntimeTransportConstant(
        name: 'machine-info default_mode',
        value: 'aggregate',
        confirmation: AdapterConstantConfirmation.confirmed,
      ),
      RuntimeTransportConstant(
        name: 'supported_contract_versions.runtime_events',
        value: '[2]',
        confirmation: AdapterConstantConfirmation.confirmed,
        source: 'Styio main.cpp; nano []',
      ),
      RuntimeTransportConstant(
        name: 'Pafio emit option',
        value: '--emit-runtime-observation[=<version>]',
        confirmation: AdapterConstantConfirmation.confirmed,
        source: 'Pafio Support.cpp',
      ),
      RuntimeTransportConstant(
        name: 'Pafio mode option',
        value: '--runtime-observation-mode',
        confirmation: AdapterConstantConfirmation.confirmed,
      ),
      RuntimeTransportConstant(
        name: 'Pafio capability option',
        value: '--runtime-observation-capability',
        confirmation: AdapterConstantConfirmation.confirmed,
      ),
      RuntimeTransportConstant(
        name: 'receipt outputs.runtime_events_path',
        value: 'outputs.runtime_events_path',
        confirmation: AdapterConstantConfirmation.confirmed,
        source: 'Styio compile-plan receipt writer',
      ),
      RuntimeTransportConstant(
        name: 'artifact file',
        value: 'runtime-events.jsonl',
        confirmation: AdapterConstantConfirmation.confirmed,
      ),
      RuntimeTransportConstant(
        name: 'producer snapshot_id equals static snapshot identity',
        value: 'fail-closed stale-snapshot when unequal',
        confirmation: AdapterConstantConfirmation.confirmed,
        source:
            'Same compilation unit; overlay joins nothing when identities differ',
      ),
    ];

enum RuntimeObservationMode { disabled, aggregate, sampled, detailed }

extension RuntimeObservationModeX on RuntimeObservationMode {
  String get wireValue {
    return switch (this) {
      RuntimeObservationMode.disabled => 'disabled',
      RuntimeObservationMode.aggregate => 'aggregate',
      RuntimeObservationMode.sampled => 'sampled',
      RuntimeObservationMode.detailed => 'detailed',
    };
  }

  static RuntimeObservationMode? tryParse(String value) {
    return switch (value) {
      'disabled' => RuntimeObservationMode.disabled,
      'aggregate' => RuntimeObservationMode.aggregate,
      'sampled' => RuntimeObservationMode.sampled,
      'detailed' => RuntimeObservationMode.detailed,
      _ => null,
    };
  }
}

enum RuntimeEventKind {
  sessionCapability,
  sessionSummary,
  compileStarted,
  compileFinished,
  compileFailed,
  unitEntered,
  unitExited,
  unitTestStarted,
  unitTestFinished,
  transitionFired,
  stateChanged,
  diagnosticEmitted,
  runStarted,
  runFinished,
  threadSpawned,
  threadExited,
  logEmitted,
  taskCreated,
  taskEnqueued,
  taskDequeued,
  taskStarted,
  taskCompleted,
  taskFailed,
  taskResultConsumed,
  taskReleased,
  queuePressure,
  queueClosed,
  waitBegin,
  waitEnd,
  aggregateShard,
  cancellationRequested,
  cancellationCompleted,
  cooperativeSuspend,
  cooperativeResume,
  unknown,
}

extension RuntimeEventKindX on RuntimeEventKind {
  String get wireValue {
    return switch (this) {
      RuntimeEventKind.sessionCapability => 'session.capability',
      RuntimeEventKind.sessionSummary => 'session.summary',
      RuntimeEventKind.compileStarted => 'compile.started',
      RuntimeEventKind.compileFinished => 'compile.finished',
      RuntimeEventKind.compileFailed => 'compile.failed',
      RuntimeEventKind.unitEntered => 'unit.entered',
      RuntimeEventKind.unitExited => 'unit.exited',
      RuntimeEventKind.unitTestStarted => 'unit.test.started',
      RuntimeEventKind.unitTestFinished => 'unit.test.finished',
      RuntimeEventKind.transitionFired => 'transition.fired',
      RuntimeEventKind.stateChanged => 'state.changed',
      RuntimeEventKind.diagnosticEmitted => 'diagnostic.emitted',
      RuntimeEventKind.runStarted => 'run.started',
      RuntimeEventKind.runFinished => 'run.finished',
      RuntimeEventKind.threadSpawned => 'thread.spawned',
      RuntimeEventKind.threadExited => 'thread.exited',
      RuntimeEventKind.logEmitted => 'log.emitted',
      RuntimeEventKind.taskCreated => 'task.created',
      RuntimeEventKind.taskEnqueued => 'task.enqueued',
      RuntimeEventKind.taskDequeued => 'task.dequeued',
      RuntimeEventKind.taskStarted => 'task.started',
      RuntimeEventKind.taskCompleted => 'task.completed',
      RuntimeEventKind.taskFailed => 'task.failed',
      RuntimeEventKind.taskResultConsumed => 'task.result_consumed',
      RuntimeEventKind.taskReleased => 'task.released',
      RuntimeEventKind.queuePressure => 'queue.pressure',
      RuntimeEventKind.queueClosed => 'queue.closed',
      RuntimeEventKind.waitBegin => 'wait.begin',
      RuntimeEventKind.waitEnd => 'wait.end',
      RuntimeEventKind.aggregateShard => 'aggregate.shard',
      RuntimeEventKind.cancellationRequested => 'cancellation.requested',
      RuntimeEventKind.cancellationCompleted => 'cancellation.completed',
      RuntimeEventKind.cooperativeSuspend => 'cooperative.suspend',
      RuntimeEventKind.cooperativeResume => 'cooperative.resume',
      RuntimeEventKind.unknown => 'unknown',
    };
  }

  static RuntimeEventKind fromWire(String value) {
    return switch (value) {
      'session.capability' => RuntimeEventKind.sessionCapability,
      'session.summary' => RuntimeEventKind.sessionSummary,
      'compile.started' => RuntimeEventKind.compileStarted,
      'compile.finished' => RuntimeEventKind.compileFinished,
      'compile.failed' => RuntimeEventKind.compileFailed,
      'unit.entered' => RuntimeEventKind.unitEntered,
      'unit.exited' => RuntimeEventKind.unitExited,
      'unit.test.started' => RuntimeEventKind.unitTestStarted,
      'unit.test.finished' => RuntimeEventKind.unitTestFinished,
      'transition.fired' => RuntimeEventKind.transitionFired,
      'state.changed' => RuntimeEventKind.stateChanged,
      'diagnostic.emitted' => RuntimeEventKind.diagnosticEmitted,
      'run.started' => RuntimeEventKind.runStarted,
      'run.finished' => RuntimeEventKind.runFinished,
      'thread.spawned' => RuntimeEventKind.threadSpawned,
      'thread.exited' => RuntimeEventKind.threadExited,
      'log.emitted' => RuntimeEventKind.logEmitted,
      'task.created' => RuntimeEventKind.taskCreated,
      'task.enqueued' => RuntimeEventKind.taskEnqueued,
      'task.dequeued' => RuntimeEventKind.taskDequeued,
      'task.started' => RuntimeEventKind.taskStarted,
      'task.completed' => RuntimeEventKind.taskCompleted,
      'task.failed' => RuntimeEventKind.taskFailed,
      'task.result_consumed' => RuntimeEventKind.taskResultConsumed,
      'task.released' => RuntimeEventKind.taskReleased,
      'queue.pressure' => RuntimeEventKind.queuePressure,
      'queue.closed' => RuntimeEventKind.queueClosed,
      'wait.begin' => RuntimeEventKind.waitBegin,
      'wait.end' => RuntimeEventKind.waitEnd,
      'aggregate.shard' => RuntimeEventKind.aggregateShard,
      'cancellation.requested' => RuntimeEventKind.cancellationRequested,
      'cancellation.completed' => RuntimeEventKind.cancellationCompleted,
      'cooperative.suspend' => RuntimeEventKind.cooperativeSuspend,
      'cooperative.resume' => RuntimeEventKind.cooperativeResume,
      _ => RuntimeEventKind.unknown,
    };
  }

  bool get isTaskLifecycle {
    return switch (this) {
      RuntimeEventKind.taskCreated ||
      RuntimeEventKind.taskEnqueued ||
      RuntimeEventKind.taskDequeued ||
      RuntimeEventKind.taskStarted ||
      RuntimeEventKind.taskCompleted ||
      RuntimeEventKind.taskFailed ||
      RuntimeEventKind.taskResultConsumed ||
      RuntimeEventKind.taskReleased => true,
      _ => false,
    };
  }
}

enum RuntimeEventFamily {
  session,
  controller,
  taskLifecycle,
  queue,
  wait,
  causal,
  aggregate,
  detail,
  unknown,
}

extension RuntimeEventFamilyX on RuntimeEventFamily {
  String get wireValue {
    return switch (this) {
      RuntimeEventFamily.session => 'session',
      RuntimeEventFamily.controller => 'controller',
      RuntimeEventFamily.taskLifecycle => 'task_lifecycle',
      RuntimeEventFamily.queue => 'queue',
      RuntimeEventFamily.wait => 'wait',
      RuntimeEventFamily.causal => 'causal',
      RuntimeEventFamily.aggregate => 'aggregate',
      RuntimeEventFamily.detail => 'detail',
      RuntimeEventFamily.unknown => 'unknown',
    };
  }

  static RuntimeEventFamily fromWire(String value) {
    return switch (value) {
      'session' => RuntimeEventFamily.session,
      'controller' => RuntimeEventFamily.controller,
      'task_lifecycle' => RuntimeEventFamily.taskLifecycle,
      'queue' => RuntimeEventFamily.queue,
      'wait' => RuntimeEventFamily.wait,
      'causal' => RuntimeEventFamily.causal,
      'aggregate' => RuntimeEventFamily.aggregate,
      'detail' => RuntimeEventFamily.detail,
      _ => RuntimeEventFamily.unknown,
    };
  }
}

enum RuntimeEventPriority { lifecycle, detail, unknown }

extension RuntimeEventPriorityX on RuntimeEventPriority {
  String get wireValue {
    return switch (this) {
      RuntimeEventPriority.lifecycle => 'lifecycle',
      RuntimeEventPriority.detail => 'detail',
      RuntimeEventPriority.unknown => 'unknown',
    };
  }

  static RuntimeEventPriority fromWire(String value) {
    return switch (value) {
      'lifecycle' => RuntimeEventPriority.lifecycle,
      'detail' => RuntimeEventPriority.detail,
      _ => RuntimeEventPriority.unknown,
    };
  }
}

enum RuntimeCorrelationStatus { correlated, runtimeOnly, unavailable }

extension RuntimeCorrelationStatusX on RuntimeCorrelationStatus {
  String get wireValue {
    return switch (this) {
      RuntimeCorrelationStatus.correlated => 'correlated',
      RuntimeCorrelationStatus.runtimeOnly => 'runtime_only',
      RuntimeCorrelationStatus.unavailable => 'unavailable',
    };
  }

  static RuntimeCorrelationStatus? tryParse(String value) {
    return switch (value) {
      'correlated' => RuntimeCorrelationStatus.correlated,
      'runtime_only' => RuntimeCorrelationStatus.runtimeOnly,
      'unavailable' => RuntimeCorrelationStatus.unavailable,
      _ => null,
    };
  }
}

enum RuntimeSiteRole { task, awaitSite, runtimeOnly, unknown }

extension RuntimeSiteRoleX on RuntimeSiteRole {
  String get wireValue {
    return switch (this) {
      RuntimeSiteRole.task => 'task',
      RuntimeSiteRole.awaitSite => 'await',
      RuntimeSiteRole.runtimeOnly => 'runtime_only',
      RuntimeSiteRole.unknown => 'unknown',
    };
  }

  static RuntimeSiteRole fromWire(String value) {
    return switch (value) {
      'task' => RuntimeSiteRole.task,
      'await' => RuntimeSiteRole.awaitSite,
      'runtime_only' => RuntimeSiteRole.runtimeOnly,
      _ => RuntimeSiteRole.unknown,
    };
  }
}

enum RuntimeCausalKind {
  spawn,
  enqueue,
  dispatch,
  completion,
  wake,
  failure,
  cancellation,
  backpressureRelief,
  unknown,
}

extension RuntimeCausalKindX on RuntimeCausalKind {
  String get wireValue {
    return switch (this) {
      RuntimeCausalKind.spawn => 'spawn',
      RuntimeCausalKind.enqueue => 'enqueue',
      RuntimeCausalKind.dispatch => 'dispatch',
      RuntimeCausalKind.completion => 'completion',
      RuntimeCausalKind.wake => 'wake',
      RuntimeCausalKind.failure => 'failure',
      RuntimeCausalKind.cancellation => 'cancellation',
      RuntimeCausalKind.backpressureRelief => 'backpressure_relief',
      RuntimeCausalKind.unknown => 'unknown',
    };
  }

  static RuntimeCausalKind fromWire(String value) {
    return switch (value) {
      'spawn' => RuntimeCausalKind.spawn,
      'enqueue' => RuntimeCausalKind.enqueue,
      'dispatch' => RuntimeCausalKind.dispatch,
      'completion' => RuntimeCausalKind.completion,
      'wake' => RuntimeCausalKind.wake,
      'failure' => RuntimeCausalKind.failure,
      'cancellation' => RuntimeCausalKind.cancellation,
      'backpressure_relief' => RuntimeCausalKind.backpressureRelief,
      _ => RuntimeCausalKind.unknown,
    };
  }
}

enum RuntimeWaitReason {
  runnable,
  cooperative,
  io,
  resource,
  task,
  backpressure,
  timer,
  cancellation,
  unknown,
}

extension RuntimeWaitReasonX on RuntimeWaitReason {
  String get wireValue {
    return switch (this) {
      RuntimeWaitReason.runnable => 'runnable',
      RuntimeWaitReason.cooperative => 'cooperative',
      RuntimeWaitReason.io => 'io',
      RuntimeWaitReason.resource => 'resource',
      RuntimeWaitReason.task => 'task',
      RuntimeWaitReason.backpressure => 'backpressure',
      RuntimeWaitReason.timer => 'timer',
      RuntimeWaitReason.cancellation => 'cancellation',
      RuntimeWaitReason.unknown => 'unknown',
    };
  }

  static RuntimeWaitReason fromWire(String value) {
    return switch (value) {
      'runnable' => RuntimeWaitReason.runnable,
      'cooperative' => RuntimeWaitReason.cooperative,
      'io' => RuntimeWaitReason.io,
      'resource' => RuntimeWaitReason.resource,
      'task' => RuntimeWaitReason.task,
      'backpressure' => RuntimeWaitReason.backpressure,
      'timer' => RuntimeWaitReason.timer,
      'cancellation' => RuntimeWaitReason.cancellation,
      _ => RuntimeWaitReason.unknown,
    };
  }
}

enum RuntimeWaitResolution {
  ready,
  completed,
  failed,
  cancelled,
  timedOut,
  closed,
  unknown,
}

extension RuntimeWaitResolutionX on RuntimeWaitResolution {
  String get wireValue {
    return switch (this) {
      RuntimeWaitResolution.ready => 'ready',
      RuntimeWaitResolution.completed => 'completed',
      RuntimeWaitResolution.failed => 'failed',
      RuntimeWaitResolution.cancelled => 'cancelled',
      RuntimeWaitResolution.timedOut => 'timed_out',
      RuntimeWaitResolution.closed => 'closed',
      RuntimeWaitResolution.unknown => 'unknown',
    };
  }

  static RuntimeWaitResolution fromWire(String value) {
    return switch (value) {
      'ready' => RuntimeWaitResolution.ready,
      'completed' => RuntimeWaitResolution.completed,
      'failed' => RuntimeWaitResolution.failed,
      'cancelled' => RuntimeWaitResolution.cancelled,
      'timed_out' => RuntimeWaitResolution.timedOut,
      'closed' => RuntimeWaitResolution.closed,
      _ => RuntimeWaitResolution.unknown,
    };
  }
}

enum RuntimeCompleteness {
  complete,
  partialSampling,
  partialAggregation,
  partialBufferLoss,
  partialExportLoss,
  partialUnresolved,
  partialDisabled,
  partialExporterFailure,
  unknown,
}

extension RuntimeCompletenessX on RuntimeCompleteness {
  String get wireValue {
    return switch (this) {
      RuntimeCompleteness.complete => 'complete',
      RuntimeCompleteness.partialSampling => 'partial/sampling',
      RuntimeCompleteness.partialAggregation => 'partial/aggregation',
      RuntimeCompleteness.partialBufferLoss => 'partial/buffer_loss',
      RuntimeCompleteness.partialExportLoss => 'partial/export_loss',
      RuntimeCompleteness.partialUnresolved => 'partial/unresolved',
      RuntimeCompleteness.partialDisabled => 'partial/disabled',
      RuntimeCompleteness.partialExporterFailure => 'partial/exporter_failure',
      RuntimeCompleteness.unknown => 'unknown',
    };
  }

  static RuntimeCompleteness fromWire(String value) {
    return switch (value) {
      'complete' => RuntimeCompleteness.complete,
      'partial/sampling' => RuntimeCompleteness.partialSampling,
      'partial/aggregation' => RuntimeCompleteness.partialAggregation,
      'partial/buffer_loss' => RuntimeCompleteness.partialBufferLoss,
      'partial/export_loss' => RuntimeCompleteness.partialExportLoss,
      'partial/unresolved' => RuntimeCompleteness.partialUnresolved,
      'partial/disabled' => RuntimeCompleteness.partialDisabled,
      'partial/exporter_failure' => RuntimeCompleteness.partialExporterFailure,
      _ => RuntimeCompleteness.unknown,
    };
  }

  String? get presentationClass {
    return switch (this) {
      RuntimeCompleteness.partialSampling => 'sampling',
      RuntimeCompleteness.partialAggregation => 'aggregation',
      RuntimeCompleteness.partialBufferLoss => 'buffer_loss',
      RuntimeCompleteness.partialExportLoss => 'export_loss',
      RuntimeCompleteness.partialExporterFailure => 'exporter_failure',
      RuntimeCompleteness.complete ||
      RuntimeCompleteness.partialUnresolved ||
      RuntimeCompleteness.partialDisabled ||
      RuntimeCompleteness.unknown => null,
    };
  }
}

enum RuntimeStreamSubcode {
  unsupportedContract,
  unsupportedSchemaVersion,
  missingCapabilityRecord,
  capabilityRecordNotFirst,
  duplicateCapabilityRecord,
  unknownMode,
  unsupportedSnapshotSchema,
  malformedIdentity,
}

extension RuntimeStreamSubcodeX on RuntimeStreamSubcode {
  String get wireValue {
    return switch (this) {
      RuntimeStreamSubcode.unsupportedContract => 'unsupported-contract',
      RuntimeStreamSubcode.unsupportedSchemaVersion =>
        'unsupported-schema-version',
      RuntimeStreamSubcode.missingCapabilityRecord =>
        'missing-capability-record',
      RuntimeStreamSubcode.capabilityRecordNotFirst =>
        'capability-record-not-first',
      RuntimeStreamSubcode.duplicateCapabilityRecord =>
        'duplicate-capability-record',
      RuntimeStreamSubcode.unknownMode => 'unknown-mode',
      RuntimeStreamSubcode.unsupportedSnapshotSchema =>
        'unsupported-snapshot-schema',
      RuntimeStreamSubcode.malformedIdentity => 'malformed-identity',
    };
  }
}

enum RuntimeRecordSubcode {
  malformedJson,
  missingField,
  malformedIdentity,
  unknownEventKind,
  unknownRecordKind,
}

extension RuntimeRecordSubcodeX on RuntimeRecordSubcode {
  String get wireValue {
    return switch (this) {
      RuntimeRecordSubcode.malformedJson => 'malformed-json',
      RuntimeRecordSubcode.missingField => 'missing-field',
      RuntimeRecordSubcode.malformedIdentity => 'malformed-identity',
      RuntimeRecordSubcode.unknownEventKind => 'unknown-event-kind',
      RuntimeRecordSubcode.unknownRecordKind => 'unknown-record-kind',
    };
  }
}

enum RuntimeOverlayPhase {
  none,
  unsupported,
  observing,
  ingesting,
  overlaid,
  rejected,
  staleSnapshot,
}

extension RuntimeOverlayPhaseX on RuntimeOverlayPhase {
  String get wireValue {
    return switch (this) {
      RuntimeOverlayPhase.none => 'none',
      RuntimeOverlayPhase.unsupported => 'unsupported',
      RuntimeOverlayPhase.observing => 'observing',
      RuntimeOverlayPhase.ingesting => 'ingesting',
      RuntimeOverlayPhase.overlaid => 'overlaid',
      RuntimeOverlayPhase.rejected => 'rejected',
      RuntimeOverlayPhase.staleSnapshot => 'stale-snapshot',
    };
  }
}

enum RuntimeCorrelationClass {
  correlatedSite,
  unknownSite,
  staleSnapshot,
  runtimeOnly,
}

enum RuntimeActivitySource { aggregateShards, emittedEvents }

extension RuntimeActivitySourceX on RuntimeActivitySource {
  String get legendName {
    return switch (this) {
      RuntimeActivitySource.aggregateShards => 'aggregate shards',
      RuntimeActivitySource.emittedEvents => 'emitted events',
    };
  }
}

enum RuntimePresentationKind { complete, partial }

class RuntimeSamplingSpec {
  const RuntimeSamplingSpec({
    required this.numerator,
    required this.denominator,
    required this.seed,
  });

  final int numerator;
  final int denominator;
  final int seed;

  @override
  bool operator ==(Object other) {
    return other is RuntimeSamplingSpec &&
        other.numerator == numerator &&
        other.denominator == denominator &&
        other.seed == seed;
  }

  @override
  int get hashCode => Object.hash(numerator, denominator, seed);
}

class RuntimeCausalEdge {
  const RuntimeCausalEdge({
    required this.kind,
    required this.rawKind,
    required this.eventId,
    this.subjectInstance,
  });

  final RuntimeCausalKind kind;
  final String rawKind;
  final String eventId;
  final String? subjectInstance;

  @override
  bool operator ==(Object other) {
    return other is RuntimeCausalEdge &&
        other.kind == kind &&
        other.rawKind == rawKind &&
        other.eventId == eventId &&
        other.subjectInstance == subjectInstance;
  }

  @override
  int get hashCode => Object.hash(kind, rawKind, eventId, subjectInstance);
}

class RuntimeWaitFields {
  const RuntimeWaitFields({
    required this.waitId,
    this.waiterInstance,
    this.subjectInstance,
    required this.reason,
    required this.rawReason,
    this.resolution,
    this.rawResolution,
    this.durationNs,
  });

  final String waitId;
  final String? waiterInstance;
  final String? subjectInstance;
  final RuntimeWaitReason reason;
  final String rawReason;
  final RuntimeWaitResolution? resolution;
  final String? rawResolution;
  final int? durationNs;

  @override
  bool operator ==(Object other) {
    return other is RuntimeWaitFields &&
        other.waitId == waitId &&
        other.waiterInstance == waiterInstance &&
        other.subjectInstance == subjectInstance &&
        other.reason == reason &&
        other.rawReason == rawReason &&
        other.resolution == resolution &&
        other.rawResolution == rawResolution &&
        other.durationNs == durationNs;
  }

  @override
  int get hashCode => Object.hash(
    waitId,
    waiterInstance,
    subjectInstance,
    reason,
    rawReason,
    resolution,
    rawResolution,
    durationNs,
  );
}

class RuntimeFamilyAccounting {
  const RuntimeFamilyAccounting({
    required this.observed,
    required this.emitted,
    required this.aggregated,
    required this.sampledOut,
    required this.bufferDropped,
    required this.exporterDropped,
    required this.summaryUpdates,
  });

  final int observed;
  final int emitted;
  final int aggregated;
  final int sampledOut;
  final int bufferDropped;
  final int exporterDropped;
  final int summaryUpdates;

  bool get conserves {
    return observed ==
        emitted + aggregated + sampledOut + bufferDropped + exporterDropped;
  }

  @override
  bool operator ==(Object other) {
    return other is RuntimeFamilyAccounting &&
        other.observed == observed &&
        other.emitted == emitted &&
        other.aggregated == aggregated &&
        other.sampledOut == sampledOut &&
        other.bufferDropped == bufferDropped &&
        other.exporterDropped == exporterDropped &&
        other.summaryUpdates == summaryUpdates;
  }

  @override
  int get hashCode => Object.hash(
    observed,
    emitted,
    aggregated,
    sampledOut,
    bufferDropped,
    exporterDropped,
    summaryUpdates,
  );
}

class RuntimeCapabilityRecord {
  const RuntimeCapabilityRecord({
    required this.mode,
    required this.snapshotSchema,
    required this.snapshotId,
    required this.executionId,
    required this.privacyProfile,
    required this.producerLanes,
    required this.laneCapacity,
    required this.priorityReserved,
    required this.drainBatch,
    required this.sampling,
    required this.clockUnit,
    required this.supportedCapabilities,
    required this.activeCapabilities,
    required this.unavailableCapabilities,
  });

  final RuntimeObservationMode mode;
  final int snapshotSchema;

  /// Null when the producer bound no snapshot (disabled mode, or a run that
  /// ended before descriptor registration); the upstream contract serializes
  /// that as `snapshot_id: null`. A null identity never joins the head.
  final String? snapshotId;
  final String executionId;
  final String privacyProfile;
  final int producerLanes;
  final int laneCapacity;
  final int priorityReserved;
  final int drainBatch;
  final RuntimeSamplingSpec sampling;
  final String clockUnit;
  final List<String> supportedCapabilities;
  final List<String> activeCapabilities;
  final List<String> unavailableCapabilities;

  @override
  bool operator ==(Object other) {
    return other is RuntimeCapabilityRecord &&
        other.mode == mode &&
        other.snapshotSchema == snapshotSchema &&
        other.snapshotId == snapshotId &&
        other.executionId == executionId &&
        other.privacyProfile == privacyProfile &&
        other.producerLanes == producerLanes &&
        other.laneCapacity == laneCapacity &&
        other.priorityReserved == priorityReserved &&
        other.drainBatch == drainBatch &&
        other.sampling == sampling &&
        other.clockUnit == clockUnit &&
        _listEquals(other.supportedCapabilities, supportedCapabilities) &&
        _listEquals(other.activeCapabilities, activeCapabilities) &&
        _listEquals(other.unavailableCapabilities, unavailableCapabilities);
  }

  @override
  int get hashCode => Object.hash(
    mode,
    snapshotSchema,
    snapshotId,
    executionId,
    privacyProfile,
    producerLanes,
    laneCapacity,
    priorityReserved,
    drainBatch,
    sampling,
    clockUnit,
    Object.hashAll(supportedCapabilities),
    Object.hashAll(activeCapabilities),
    Object.hashAll(unavailableCapabilities),
  );
}

class RuntimeSummaryRecord {
  const RuntimeSummaryRecord({
    required this.mode,
    required this.executionId,
    required this.completeness,
    required this.rawCompleteness,
    required this.exporterFailed,
    required this.laneCapacity,
    required this.priorityReserved,
    required this.producerLanes,
    required this.highWaterOccupancy,
    required this.families,
  });

  final RuntimeObservationMode mode;
  final String executionId;
  final RuntimeCompleteness completeness;
  final String rawCompleteness;
  final bool exporterFailed;
  final int laneCapacity;
  final int priorityReserved;
  final int producerLanes;
  final int highWaterOccupancy;
  final Map<String, RuntimeFamilyAccounting> families;

  @override
  bool operator ==(Object other) {
    return other is RuntimeSummaryRecord &&
        other.mode == mode &&
        other.executionId == executionId &&
        other.completeness == completeness &&
        other.rawCompleteness == rawCompleteness &&
        other.exporterFailed == exporterFailed &&
        other.laneCapacity == laneCapacity &&
        other.priorityReserved == priorityReserved &&
        other.producerLanes == producerLanes &&
        other.highWaterOccupancy == highWaterOccupancy &&
        _mapEquals(other.families, families);
  }

  @override
  int get hashCode => Object.hash(
    mode,
    executionId,
    completeness,
    rawCompleteness,
    exporterFailed,
    laneCapacity,
    priorityReserved,
    producerLanes,
    highWaterOccupancy,
    Object.hashAll(
      families.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

class RuntimeEventRecord {
  const RuntimeEventRecord({
    required this.kind,
    required this.rawKind,
    required this.family,
    required this.rawFamily,
    required this.priority,
    required this.rawPriority,
    required this.correlationStatus,
    required this.role,
    required this.rawRole,
    required this.eventId,
    required this.monotonicNs,
    this.snapshotId,
    this.siteId,
    this.instanceId,
    this.causes = const <RuntimeCausalEdge>[],
    this.wait,
    this.unitId,
    this.testName,
    this.intent,
    this.phase,
    this.operation,
    this.diagnosticCode,
    this.stream,
    this.fromPhase,
    this.toPhase,
    this.finalPhase,
    this.success,
    this.executed,
    this.queueDepth,
    this.queueCapacity,
    this.count,
    this.durationNs,
  });

  final RuntimeEventKind kind;
  final String rawKind;
  final RuntimeEventFamily family;
  final String rawFamily;
  final RuntimeEventPriority priority;
  final String rawPriority;
  final RuntimeCorrelationStatus correlationStatus;
  final RuntimeSiteRole role;
  final String rawRole;
  final String eventId;
  final int monotonicNs;
  final String? snapshotId;
  final String? siteId;
  final String? instanceId;
  final List<RuntimeCausalEdge> causes;
  final RuntimeWaitFields? wait;
  final String? unitId;
  final String? testName;
  final String? intent;
  final String? phase;
  final String? operation;
  final String? diagnosticCode;
  final String? stream;
  final String? fromPhase;
  final String? toPhase;
  final String? finalPhase;
  final bool? success;
  final bool? executed;
  final int? queueDepth;
  final int? queueCapacity;
  final int? count;
  final int? durationNs;

  @override
  bool operator ==(Object other) {
    return other is RuntimeEventRecord &&
        other.kind == kind &&
        other.rawKind == rawKind &&
        other.family == family &&
        other.rawFamily == rawFamily &&
        other.priority == priority &&
        other.rawPriority == rawPriority &&
        other.correlationStatus == correlationStatus &&
        other.role == role &&
        other.rawRole == rawRole &&
        other.eventId == eventId &&
        other.monotonicNs == monotonicNs &&
        other.snapshotId == snapshotId &&
        other.siteId == siteId &&
        other.instanceId == instanceId &&
        _listEquals(other.causes, causes) &&
        other.wait == wait &&
        other.unitId == unitId &&
        other.testName == testName &&
        other.intent == intent &&
        other.phase == phase &&
        other.operation == operation &&
        other.diagnosticCode == diagnosticCode &&
        other.stream == stream &&
        other.fromPhase == fromPhase &&
        other.toPhase == toPhase &&
        other.finalPhase == finalPhase &&
        other.success == success &&
        other.executed == executed &&
        other.queueDepth == queueDepth &&
        other.queueCapacity == queueCapacity &&
        other.count == count &&
        other.durationNs == durationNs;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    kind,
    rawKind,
    family,
    rawFamily,
    priority,
    rawPriority,
    correlationStatus,
    role,
    rawRole,
    eventId,
    monotonicNs,
    snapshotId,
    siteId,
    instanceId,
    Object.hashAll(causes),
    wait,
    unitId,
    testName,
    intent,
    phase,
    operation,
    diagnosticCode,
    stream,
    fromPhase,
    toPhase,
    finalPhase,
    success,
    executed,
    queueDepth,
    queueCapacity,
    count,
    durationNs,
  ]);
}

sealed class RuntimeDecodedRecord {
  const RuntimeDecodedRecord();
}

class RuntimeDecodedCapability extends RuntimeDecodedRecord {
  const RuntimeDecodedCapability(this.record);

  final RuntimeCapabilityRecord record;

  @override
  bool operator ==(Object other) {
    return other is RuntimeDecodedCapability && other.record == record;
  }

  @override
  int get hashCode => record.hashCode;
}

class RuntimeDecodedEvent extends RuntimeDecodedRecord {
  const RuntimeDecodedEvent(this.record);

  final RuntimeEventRecord record;

  @override
  bool operator ==(Object other) {
    return other is RuntimeDecodedEvent && other.record == record;
  }

  @override
  int get hashCode => record.hashCode;
}

class RuntimeDecodedSummary extends RuntimeDecodedRecord {
  const RuntimeDecodedSummary(this.record);

  final RuntimeSummaryRecord record;

  @override
  bool operator ==(Object other) {
    return other is RuntimeDecodedSummary && other.record == record;
  }

  @override
  int get hashCode => record.hashCode;
}

class RuntimeRecordRejection {
  const RuntimeRecordRejection({
    this.subcode,
    required this.detail,
    this.streamLevel = false,
    this.streamSubcode,
  });

  final RuntimeRecordSubcode? subcode;
  final RuntimeStreamSubcode? streamSubcode;
  final bool streamLevel;
  final String detail;
}

class RuntimeLineDecodeResult {
  const RuntimeLineDecodeResult.ok(this.record) : rejection = null;

  const RuntimeLineDecodeResult.rejected(this.rejection) : record = null;

  final RuntimeDecodedRecord? record;
  final RuntimeRecordRejection? rejection;

  bool get isOk => record != null;
}

class RuntimeRecordDegradation {
  const RuntimeRecordDegradation({required this.subcode, required this.detail});

  final RuntimeRecordSubcode subcode;
  final String detail;
}

class RuntimeStreamDecodeResult {
  const RuntimeStreamDecodeResult.ok({
    required this.records,
    this.degradations = const <RuntimeRecordDegradation>[],
  }) : streamSubcode = null,
       detail = null;

  const RuntimeStreamDecodeResult.rejected({
    required this.streamSubcode,
    required this.detail,
    this.degradations = const <RuntimeRecordDegradation>[],
  }) : records = const <RuntimeDecodedRecord>[];

  final List<RuntimeDecodedRecord> records;
  final List<RuntimeRecordDegradation> degradations;
  final RuntimeStreamSubcode? streamSubcode;
  final String? detail;

  bool get isOk => streamSubcode == null;
}

class RuntimeSiteEvent {
  const RuntimeSiteEvent({
    required this.kind,
    required this.rawKind,
    this.instanceId,
    required this.eventId,
    required this.monotonicNs,
    this.causes = const <RuntimeCausalEdge>[],
  });

  final RuntimeEventKind kind;
  final String rawKind;
  final String? instanceId;
  final String eventId;
  final int monotonicNs;
  final List<RuntimeCausalEdge> causes;

  @override
  bool operator ==(Object other) {
    return other is RuntimeSiteEvent &&
        other.kind == kind &&
        other.rawKind == rawKind &&
        other.instanceId == instanceId &&
        other.eventId == eventId &&
        other.monotonicNs == monotonicNs &&
        _listEquals(other.causes, causes);
  }

  @override
  int get hashCode => Object.hash(
    kind,
    rawKind,
    instanceId,
    eventId,
    monotonicNs,
    Object.hashAll(causes),
  );
}

class RuntimeWaitFacts {
  const RuntimeWaitFacts({
    this.open = 0,
    this.closed = 0,
    this.unmatchedEnds = 0,
    this.totalDurationNs = 0,
    this.maxDurationNs = 0,
    this.durationSamples = 0,
  });

  final int open;
  final int closed;
  final int unmatchedEnds;
  final int totalDurationNs;
  final int maxDurationNs;
  final int durationSamples;

  RuntimeWaitFacts copyWith({
    int? open,
    int? closed,
    int? unmatchedEnds,
    int? totalDurationNs,
    int? maxDurationNs,
    int? durationSamples,
  }) {
    return RuntimeWaitFacts(
      open: open ?? this.open,
      closed: closed ?? this.closed,
      unmatchedEnds: unmatchedEnds ?? this.unmatchedEnds,
      totalDurationNs: totalDurationNs ?? this.totalDurationNs,
      maxDurationNs: maxDurationNs ?? this.maxDurationNs,
      durationSamples: durationSamples ?? this.durationSamples,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RuntimeWaitFacts &&
        other.open == open &&
        other.closed == closed &&
        other.unmatchedEnds == unmatchedEnds &&
        other.totalDurationNs == totalDurationNs &&
        other.maxDurationNs == maxDurationNs &&
        other.durationSamples == durationSamples;
  }

  @override
  int get hashCode => Object.hash(
    open,
    closed,
    unmatchedEnds,
    totalDurationNs,
    maxDurationNs,
    durationSamples,
  );
}

class RuntimeSiteFacts {
  const RuntimeSiteFacts({
    required this.siteId,
    this.instancesCreated = 0,
    this.instancesCompleted = 0,
    this.instancesFailed = 0,
    this.lifecycleEvents = 0,
    this.detailEvents = 0,
    this.aggregateCount = 0,
    this.aggregateDurationNs = 0,
    this.queuePressureEvents = 0,
    this.maxQueueDepth = 0,
    this.queueCapacity = 0,
    this.subjectUnresolved = 0,
    this.waits = const <RuntimeWaitReason, RuntimeWaitFacts>{},
    this.recentEvents = const <RuntimeSiteEvent>[],
  });

  final String siteId;
  final int instancesCreated;
  final int instancesCompleted;
  final int instancesFailed;
  final int lifecycleEvents;
  final int detailEvents;
  final int aggregateCount;
  final int aggregateDurationNs;
  final int queuePressureEvents;
  final int maxQueueDepth;
  final int queueCapacity;
  final int subjectUnresolved;
  final Map<RuntimeWaitReason, RuntimeWaitFacts> waits;
  final List<RuntimeSiteEvent> recentEvents;

  int get instancesActive {
    final active = instancesCreated - instancesCompleted - instancesFailed;
    return active < 0 ? 0 : active;
  }

  int activity(RuntimeActivitySource source) {
    return switch (source) {
      RuntimeActivitySource.aggregateShards => aggregateCount,
      RuntimeActivitySource.emittedEvents => lifecycleEvents + detailEvents,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is RuntimeSiteFacts &&
        other.siteId == siteId &&
        other.instancesCreated == instancesCreated &&
        other.instancesCompleted == instancesCompleted &&
        other.instancesFailed == instancesFailed &&
        other.lifecycleEvents == lifecycleEvents &&
        other.detailEvents == detailEvents &&
        other.aggregateCount == aggregateCount &&
        other.aggregateDurationNs == aggregateDurationNs &&
        other.queuePressureEvents == queuePressureEvents &&
        other.maxQueueDepth == maxQueueDepth &&
        other.queueCapacity == queueCapacity &&
        other.subjectUnresolved == subjectUnresolved &&
        _mapEquals(other.waits, waits) &&
        _listEquals(other.recentEvents, recentEvents);
  }

  @override
  int get hashCode => Object.hash(
    siteId,
    instancesCreated,
    instancesCompleted,
    instancesFailed,
    lifecycleEvents,
    detailEvents,
    aggregateCount,
    aggregateDurationNs,
    queuePressureEvents,
    maxQueueDepth,
    queueCapacity,
    subjectUnresolved,
    Object.hashAll(
      waits.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(recentEvents),
  );
}

class RuntimeBlockedLink {
  const RuntimeBlockedLink({
    required this.fromSite,
    required this.toSite,
    required this.reason,
    this.open = 0,
    this.closed = 0,
    this.totalDurationNs = 0,
  });

  final String fromSite;
  final String toSite;
  final RuntimeWaitReason reason;
  final int open;
  final int closed;
  final int totalDurationNs;

  String get key => '$fromSite\u001f$toSite\u001f${reason.wireValue}';

  RuntimeBlockedLink copyWith({
    int? open,
    int? closed,
    int? totalDurationNs,
  }) {
    return RuntimeBlockedLink(
      fromSite: fromSite,
      toSite: toSite,
      reason: reason,
      open: open ?? this.open,
      closed: closed ?? this.closed,
      totalDurationNs: totalDurationNs ?? this.totalDurationNs,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RuntimeBlockedLink &&
        other.fromSite == fromSite &&
        other.toSite == toSite &&
        other.reason == reason &&
        other.open == open &&
        other.closed == closed &&
        other.totalDurationNs == totalDurationNs;
  }

  @override
  int get hashCode =>
      Object.hash(fromSite, toSite, reason, open, closed, totalDurationNs);
}

class RuntimeUncorrelatedSample {
  const RuntimeUncorrelatedSample({
    required this.classification,
    required this.eventId,
    required this.rawKind,
    this.snapshotId,
    this.siteId,
  });

  final RuntimeCorrelationClass classification;
  final String eventId;
  final String rawKind;
  final String? snapshotId;
  final String? siteId;

  @override
  bool operator ==(Object other) {
    return other is RuntimeUncorrelatedSample &&
        other.classification == classification &&
        other.eventId == eventId &&
        other.rawKind == rawKind &&
        other.snapshotId == snapshotId &&
        other.siteId == siteId;
  }

  @override
  int get hashCode =>
      Object.hash(classification, eventId, rawKind, snapshotId, siteId);
}

class RuntimeUncorrelatedBuckets {
  const RuntimeUncorrelatedBuckets({
    this.runtimeOnly = 0,
    this.unknownSite = 0,
    this.staleSnapshot = 0,
    this.runtimeOnlyWaits = const <RuntimeWaitReason, int>{},
    this.unknownSiteIds = const <String>[],
    this.staleSnapshotIds = const <String>[],
    this.samples = const <RuntimeUncorrelatedSample>[],
  });

  final int runtimeOnly;
  final int unknownSite;
  final int staleSnapshot;
  final Map<RuntimeWaitReason, int> runtimeOnlyWaits;
  final List<String> unknownSiteIds;
  final List<String> staleSnapshotIds;
  final List<RuntimeUncorrelatedSample> samples;

  @override
  bool operator ==(Object other) {
    return other is RuntimeUncorrelatedBuckets &&
        other.runtimeOnly == runtimeOnly &&
        other.unknownSite == unknownSite &&
        other.staleSnapshot == staleSnapshot &&
        _mapEquals(other.runtimeOnlyWaits, runtimeOnlyWaits) &&
        _listEquals(other.unknownSiteIds, unknownSiteIds) &&
        _listEquals(other.staleSnapshotIds, staleSnapshotIds) &&
        _listEquals(other.samples, samples);
  }

  @override
  int get hashCode => Object.hash(
    runtimeOnly,
    unknownSite,
    staleSnapshot,
    Object.hashAll(
      runtimeOnlyWaits.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
    Object.hashAll(unknownSiteIds),
    Object.hashAll(staleSnapshotIds),
    Object.hashAll(samples),
  );
}

class RuntimeOverlayCounters {
  const RuntimeOverlayCounters({
    this.rejectedRecords = 0,
    this.unknownKinds = 0,
    this.instanceMapEvictions = 0,
    this.openWaitEvictions = 0,
    this.blockedLinkEvictions = 0,
    this.unmatchedWaitEnds = 0,
    this.emittedCountMismatches = 0,
    this.conservationViolations = 0,
    this.controllerEvents = 0,
    this.sessionQueuePressureEvents = 0,
  });

  final int rejectedRecords;
  final int unknownKinds;
  final int instanceMapEvictions;
  final int openWaitEvictions;
  final int blockedLinkEvictions;
  final int unmatchedWaitEnds;
  final int emittedCountMismatches;
  final int conservationViolations;
  final int controllerEvents;
  final int sessionQueuePressureEvents;

  int get totalEvictions =>
      instanceMapEvictions + openWaitEvictions + blockedLinkEvictions;

  @override
  bool operator ==(Object other) {
    return other is RuntimeOverlayCounters &&
        other.rejectedRecords == rejectedRecords &&
        other.unknownKinds == unknownKinds &&
        other.instanceMapEvictions == instanceMapEvictions &&
        other.openWaitEvictions == openWaitEvictions &&
        other.blockedLinkEvictions == blockedLinkEvictions &&
        other.unmatchedWaitEnds == unmatchedWaitEnds &&
        other.emittedCountMismatches == emittedCountMismatches &&
        other.conservationViolations == conservationViolations &&
        other.controllerEvents == controllerEvents &&
        other.sessionQueuePressureEvents == sessionQueuePressureEvents;
  }

  @override
  int get hashCode => Object.hash(
    rejectedRecords,
    unknownKinds,
    instanceMapEvictions,
    openWaitEvictions,
    blockedLinkEvictions,
    unmatchedWaitEnds,
    emittedCountMismatches,
    conservationViolations,
    controllerEvents,
    sessionQueuePressureEvents,
  );
}

class RuntimeOverlayPresentation {
  const RuntimeOverlayPresentation({
    required this.kind,
    this.classes = const <String>[],
  });

  final RuntimePresentationKind kind;
  final List<String> classes;

  bool get isComplete => kind == RuntimePresentationKind.complete;

  String get label {
    if (kind == RuntimePresentationKind.complete) {
      return 'complete';
    }
    return 'partial: ${classes.join(', ')}';
  }

  @override
  bool operator ==(Object other) {
    return other is RuntimeOverlayPresentation &&
        other.kind == kind &&
        _listEquals(other.classes, classes);
  }

  @override
  int get hashCode => Object.hash(kind, Object.hashAll(classes));
}

class RuntimeOverlay {
  const RuntimeOverlay({
    required this.snapshotId,
    required this.executionId,
    required this.mode,
    required this.activitySource,
    required this.presentation,
    required this.sites,
    required this.blockedLinks,
    required this.uncorrelated,
    required this.counters,
    this.capability,
    this.summary,
    this.maxActivity = 0,
    this.summaryMissing = false,
  });

  /// Capability `snapshot_id`; null when the producer bound no snapshot, which
  /// never equals a retained head and therefore fails closed to
  /// `stale-snapshot` at the controller.
  final String? snapshotId;
  final String executionId;
  final RuntimeObservationMode mode;
  final RuntimeActivitySource activitySource;
  final RuntimeOverlayPresentation presentation;
  final Map<String, RuntimeSiteFacts> sites;
  final List<RuntimeBlockedLink> blockedLinks;
  final RuntimeUncorrelatedBuckets uncorrelated;
  final RuntimeOverlayCounters counters;
  final RuntimeCapabilityRecord? capability;
  final RuntimeSummaryRecord? summary;
  final int maxActivity;
  final bool summaryMissing;

  double intensityFor(String siteId) {
    if (maxActivity <= 0) {
      return 0;
    }
    final facts = sites[siteId];
    if (facts == null) {
      return 0;
    }
    return facts.activity(activitySource) / maxActivity;
  }

  @override
  bool operator ==(Object other) {
    return other is RuntimeOverlay &&
        other.snapshotId == snapshotId &&
        other.executionId == executionId &&
        other.mode == mode &&
        other.activitySource == activitySource &&
        other.presentation == presentation &&
        _mapEquals(other.sites, sites) &&
        _listEquals(other.blockedLinks, blockedLinks) &&
        other.uncorrelated == uncorrelated &&
        other.counters == counters &&
        other.capability == capability &&
        other.summary == summary &&
        other.maxActivity == maxActivity &&
        other.summaryMissing == summaryMissing;
  }

  @override
  int get hashCode => Object.hash(
    snapshotId,
    executionId,
    mode,
    activitySource,
    presentation,
    Object.hashAll(
      sites.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
    Object.hashAll(blockedLinks),
    uncorrelated,
    counters,
    capability,
    summary,
    maxActivity,
    summaryMissing,
  );
}

class RuntimeOverlayCapacities {
  const RuntimeOverlayCapacities({
    this.instanceSiteMap = kRuntimeInstanceSiteMapCapacity,
    this.openWait = kRuntimeOpenWaitCapacity,
    this.blockedLink = kRuntimeBlockedLinkCapacity,
    this.siteEventRing = kRuntimeSiteEventRingCapacity,
    this.uncorrelatedSample = kRuntimeUncorrelatedSampleCapacity,
    this.unknownSiteIds = kRuntimeUnknownSiteIdCapacity,
    this.staleSnapshotIds = kRuntimeStaleSnapshotIdCapacity,
  });

  static const RuntimeOverlayCapacities defaults = RuntimeOverlayCapacities();

  final int instanceSiteMap;
  final int openWait;
  final int blockedLink;
  final int siteEventRing;
  final int uncorrelatedSample;
  final int unknownSiteIds;
  final int staleSnapshotIds;
}

class RuntimeObservationRequest {
  const RuntimeObservationRequest({
    this.mode = RuntimeObservationMode.aggregate,
    this.requiredCapabilities = kRuntimeRequiredCapabilities,
  });

  final RuntimeObservationMode mode;
  final List<String> requiredCapabilities;
}

class RuntimeIntakeRequest {
  const RuntimeIntakeRequest({
    required this.artifactPath,
    required this.headSnapshotId,
    required this.headSiteIds,
    this.capacities = RuntimeOverlayCapacities.defaults,
  });

  final String artifactPath;
  final String headSnapshotId;
  final List<String> headSiteIds;
  final RuntimeOverlayCapacities capacities;
}

class RuntimeIntakeResult {
  const RuntimeIntakeResult.ok(this.overlay)
    : reason = null,
      streamSubcode = null,
      detail = null;

  const RuntimeIntakeResult.rejected({
    required this.reason,
    this.streamSubcode,
    this.detail,
  }) : overlay = null;

  final RuntimeOverlay? overlay;
  final ObservableReasonCode? reason;
  final RuntimeStreamSubcode? streamSubcode;
  final String? detail;

  bool get isOk => overlay != null;
}

abstract class ObservableRuntimeIntake {
  Future<RuntimeIntakeResult> ingest(RuntimeIntakeRequest request);
}

class RuntimeObservationDecision {
  const RuntimeObservationDecision({
    required this.available,
    this.reason,
    this.detail,
    this.defaultMode = RuntimeObservationMode.aggregate,
    this.supportedCapabilities = const <String>[],
    this.unavailableCapabilities = const <String>[],
  });

  factory RuntimeObservationDecision.ok({
    RuntimeObservationMode defaultMode = RuntimeObservationMode.aggregate,
    List<String> supportedCapabilities = const <String>[],
    List<String> unavailableCapabilities = const <String>[],
  }) {
    return RuntimeObservationDecision(
      available: true,
      defaultMode: defaultMode,
      supportedCapabilities: supportedCapabilities,
      unavailableCapabilities: unavailableCapabilities,
    );
  }

  factory RuntimeObservationDecision.unsupported({
    required ObservableReasonCode reason,
    required String detail,
  }) {
    return RuntimeObservationDecision(
      available: false,
      reason: reason,
      detail: detail,
    );
  }

  final bool available;
  final ObservableReasonCode? reason;
  final String? detail;
  final RuntimeObservationMode defaultMode;
  final List<String> supportedCapabilities;
  final List<String> unavailableCapabilities;
}

class RuntimeOverlayState {
  const RuntimeOverlayState({
    required this.phase,
    this.reason,
    this.detail,
    this.requestedMode,
    this.overlay,
    this.ingestedAt,
  });

  const RuntimeOverlayState.none()
    : phase = RuntimeOverlayPhase.none,
      reason = null,
      detail = null,
      requestedMode = null,
      overlay = null,
      ingestedAt = null;

  final RuntimeOverlayPhase phase;
  final ObservableReasonCode? reason;
  final String? detail;
  final RuntimeObservationMode? requestedMode;
  final RuntimeOverlay? overlay;
  final DateTime? ingestedAt;

  bool get drawsOnGraph {
    return phase == RuntimeOverlayPhase.overlaid && overlay != null;
  }

  bool marksCurrentHead(String? snapshotId) {
    return drawsOnGraph &&
        snapshotId != null &&
        overlay!.snapshotId != null &&
        overlay!.snapshotId == snapshotId;
  }

  bool get showsRuntimeChrome {
    return phase != RuntimeOverlayPhase.none;
  }

  RuntimeOverlayState copyWith({
    RuntimeOverlayPhase? phase,
    ObservableReasonCode? reason,
    String? detail,
    RuntimeObservationMode? requestedMode,
    RuntimeOverlay? overlay,
    DateTime? ingestedAt,
    bool clearReason = false,
    bool clearOverlay = false,
  }) {
    return RuntimeOverlayState(
      phase: phase ?? this.phase,
      reason: clearReason ? null : (reason ?? this.reason),
      detail: detail ?? this.detail,
      requestedMode: requestedMode ?? this.requestedMode,
      overlay: clearOverlay ? null : (overlay ?? this.overlay),
      ingestedAt: ingestedAt ?? this.ingestedAt,
    );
  }
}

bool runtimeIdHasPrefix(String value, String prefix) {
  return value.startsWith(prefix) && value.length > prefix.length;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals<K, V>(Map<K, V> left, Map<K, V> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (final entry in left.entries) {
    if (right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}
