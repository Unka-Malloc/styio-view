import 'dart:convert';

import 'observable_runtime_model.dart';

RuntimeLineDecodeResult decodeRuntimeRecord(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedJson,
        detail: 'empty line',
      ),
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException catch (error) {
    return RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedJson,
        detail: 'malformed json: ${error.message}',
      ),
    );
  }
  if (decoded is! Map) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedJson,
        detail: 'record must be an object',
      ),
    );
  }
  final map = decoded.map(
    (key, value) => MapEntry<String, Object?>(key.toString(), value),
  );
  return decodeRuntimeRecordMap(map);
}

RuntimeLineDecodeResult decodeRuntimeRecordMap(Map<String, Object?> map) {
  final contract = _string(map['contract']);
  if (contract != null && contract != kRuntimeEventsContract) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        streamLevel: true,
        streamSubcode: RuntimeStreamSubcode.unsupportedContract,
        detail: 'unsupported contract',
      ),
    );
  }

  final schemaVersion = _int(map['schema_version']);
  if (schemaVersion == null) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        streamLevel: true,
        streamSubcode: RuntimeStreamSubcode.unsupportedSchemaVersion,
        detail: 'missing schema_version',
      ),
    );
  }
  if (schemaVersion != kRuntimeEventsSchemaVersion) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        streamLevel: true,
        streamSubcode: RuntimeStreamSubcode.unsupportedSchemaVersion,
        detail: 'unsupported schema_version',
      ),
    );
  }

  final eventKind = _string(map['event_kind']);
  if (eventKind == null || eventKind.isEmpty) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.missingField,
        detail: 'missing event_kind',
      ),
    );
  }

  final recordKind = _string(map['record_kind']) ?? eventKind;
  if (eventKind == 'session.capability' ||
      recordKind == 'session.capability') {
    return _decodeCapability(map);
  }
  if (eventKind == 'session.summary' || recordKind == 'session.summary') {
    return _decodeSummary(map);
  }
  if (recordKind != 'event' &&
      recordKind != 'aggregate.shard' &&
      recordKind != eventKind) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.unknownRecordKind,
        detail: 'unknown record_kind',
      ),
    );
  }
  return _decodeEvent(map, eventKind);
}

RuntimeStreamDecodeResult decodeRuntimeStream(Iterable<String> lines) {
  final records = <RuntimeDecodedRecord>[];
  final degradations = <RuntimeRecordDegradation>[];
  var seenCapability = false;
  var firstNonEmpty = true;

  for (final line in lines) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = decodeRuntimeRecord(line);
    final rejection = decoded.rejection;
    if (rejection != null && rejection.streamLevel) {
      return RuntimeStreamDecodeResult.rejected(
        streamSubcode: rejection.streamSubcode!,
        detail: rejection.detail,
        degradations: degradations,
      );
    }
    if (decoded.record is RuntimeDecodedCapability) {
      if (seenCapability) {
        return RuntimeStreamDecodeResult.rejected(
          streamSubcode: RuntimeStreamSubcode.duplicateCapabilityRecord,
          detail: 'duplicate capability record',
          degradations: degradations,
        );
      }
      if (!firstNonEmpty) {
        return RuntimeStreamDecodeResult.rejected(
          streamSubcode: RuntimeStreamSubcode.capabilityRecordNotFirst,
          detail: 'capability record is not first',
          degradations: degradations,
        );
      }
      seenCapability = true;
      firstNonEmpty = false;
      records.add(decoded.record!);
      continue;
    }
    firstNonEmpty = false;
    if (!seenCapability) {
      continue;
    }
    if (rejection != null) {
      degradations.add(
        RuntimeRecordDegradation(
          subcode: rejection.subcode ?? RuntimeRecordSubcode.malformedJson,
          detail: rejection.detail,
        ),
      );
      continue;
    }
    records.add(decoded.record!);
    final event = decoded.record;
    if (event is RuntimeDecodedEvent &&
        event.record.kind == RuntimeEventKind.unknown) {
      degradations.add(
        const RuntimeRecordDegradation(
          subcode: RuntimeRecordSubcode.unknownEventKind,
          detail: 'unknown event_kind',
        ),
      );
    }
  }

  if (!seenCapability) {
    return RuntimeStreamDecodeResult.rejected(
      streamSubcode: RuntimeStreamSubcode.missingCapabilityRecord,
      detail: 'missing capability record',
      degradations: degradations,
    );
  }
  return RuntimeStreamDecodeResult.ok(
    records: records,
    degradations: degradations,
  );
}

RuntimeLineDecodeResult _decodeCapability(Map<String, Object?> map) {
  final modeValue = _string(map['mode']);
  final mode = modeValue == null
      ? null
      : RuntimeObservationModeX.tryParse(modeValue);
  if (mode == null) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        streamLevel: true,
        streamSubcode: RuntimeStreamSubcode.unknownMode,
        detail: 'unknown observation mode',
      ),
    );
  }
  final snapshotSchema = _int(map['snapshot_schema']);
  if (snapshotSchema == null ||
      snapshotSchema != kRuntimeEventsSnapshotSchema) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        streamLevel: true,
        streamSubcode: RuntimeStreamSubcode.unsupportedSnapshotSchema,
        detail: 'unsupported snapshot_schema',
      ),
    );
  }
  // `snapshot_id` is `null` when the producer bound no snapshot (disabled
  // mode, or a run that ended before descriptor registration); that shape is
  // legal and must not reject the stream. A present but wrongly prefixed
  // identity is still malformed. The overlay fails closed downstream because
  // a null capability snapshot never equals the retained head.
  final snapshotId = _string(map['snapshot_id']);
  final executionId = _string(map['execution_id']);
  if (executionId == null ||
      !runtimeIdHasPrefix(executionId, kRuntimeExecutionIdPrefix) ||
      (snapshotId != null &&
          !runtimeIdHasPrefix(snapshotId, kRuntimeSnapshotIdPrefix))) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        streamLevel: true,
        streamSubcode: RuntimeStreamSubcode.malformedIdentity,
        detail: 'malformed capability identity',
      ),
    );
  }
  final samplingValue = map['sampling'];
  var sampling = const RuntimeSamplingSpec(
    numerator: 1,
    denominator: 16,
    seed: 0,
  );
  if (samplingValue is Map) {
    sampling = RuntimeSamplingSpec(
      numerator: _int(samplingValue['numerator']) ?? 1,
      denominator: _int(samplingValue['denominator']) ?? 16,
      seed: _int(samplingValue['seed']) ?? 0,
    );
  }
  return RuntimeLineDecodeResult.ok(
    RuntimeDecodedCapability(
      RuntimeCapabilityRecord(
        mode: mode,
        snapshotSchema: snapshotSchema,
        snapshotId: snapshotId,
        executionId: executionId,
        privacyProfile: _string(map['privacy_profile']) ?? '',
        producerLanes: _int(map['producer_lanes']) ?? 0,
        laneCapacity: _int(map['lane_capacity']) ?? 0,
        priorityReserved: _int(map['priority_reserved']) ?? 0,
        drainBatch: _int(map['drain_batch']) ?? 0,
        sampling: sampling,
        clockUnit: _string(map['clock_unit']) ?? kRuntimeEventsClockUnit,
        supportedCapabilities: _stringList(map['supported_capabilities']),
        activeCapabilities: _stringList(map['active_capabilities']),
        unavailableCapabilities: _stringList(map['unavailable_capabilities']),
      ),
    ),
  );
}

RuntimeLineDecodeResult _decodeSummary(Map<String, Object?> map) {
  final eventId = _string(map['event_id']);
  if (eventId != null &&
      !runtimeIdHasPrefix(eventId, kRuntimeEventIdPrefix)) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed event_id',
      ),
    );
  }
  final modeValue = _string(map['mode']) ?? 'detailed';
  final mode =
      RuntimeObservationModeX.tryParse(modeValue) ??
      RuntimeObservationMode.detailed;
  // A missing completeness must never present as complete; fail closed to the
  // unknown variant so the presentation rule reports partial.
  final completenessValue = _string(map['completeness']) ?? 'unknown';
  final families = <String, RuntimeFamilyAccounting>{};
  final familiesValue = map['families'];
  if (familiesValue is Map) {
    for (final entry in familiesValue.entries) {
      final row = entry.value;
      if (row is! Map) {
        continue;
      }
      families[entry.key.toString()] = RuntimeFamilyAccounting(
        observed: _int(row['observed']) ?? 0,
        emitted: _int(row['emitted']) ?? 0,
        aggregated: _int(row['aggregated']) ?? 0,
        sampledOut: _int(row['sampled_out']) ?? 0,
        bufferDropped: _int(row['buffer_dropped']) ?? 0,
        exporterDropped: _int(row['exporter_dropped']) ?? 0,
        summaryUpdates: _int(row['summary_updates']) ?? 0,
      );
    }
  }
  final executionId = _string(map['execution_id']) ?? '';
  if (executionId.isNotEmpty &&
      !runtimeIdHasPrefix(executionId, kRuntimeExecutionIdPrefix)) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed execution_id',
      ),
    );
  }
  return RuntimeLineDecodeResult.ok(
    RuntimeDecodedSummary(
      RuntimeSummaryRecord(
        mode: mode,
        executionId: executionId,
        completeness: RuntimeCompletenessX.fromWire(completenessValue),
        rawCompleteness: completenessValue,
        exporterFailed: map['exporter_failed'] == true,
        laneCapacity: _int(map['lane_capacity']) ?? 0,
        priorityReserved: _int(map['priority_reserved']) ?? 0,
        producerLanes: _int(map['producer_lanes']) ?? 0,
        highWaterOccupancy: _int(map['high_water_occupancy']) ?? 0,
        families: families,
      ),
    ),
  );
}

RuntimeLineDecodeResult _decodeEvent(
  Map<String, Object?> map,
  String eventKind,
) {
  final eventId = _string(map['event_id']);
  if (eventId == null || eventId.isEmpty) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.missingField,
        detail: 'missing event_id',
      ),
    );
  }
  if (!runtimeIdHasPrefix(eventId, kRuntimeEventIdPrefix)) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed event_id',
      ),
    );
  }
  final instanceId = _string(map['instance_id']);
  if (instanceId != null &&
      !runtimeIdHasPrefix(instanceId, kRuntimeInstanceIdPrefix)) {
    return const RuntimeLineDecodeResult.rejected(
      RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed instance_id',
      ),
    );
  }
  final causesResult = _decodeCauses(map['causes']);
  if (causesResult.$2 != null) {
    return RuntimeLineDecodeResult.rejected(causesResult.$2!);
  }
  final waitResult = _decodeWait(map['wait']);
  if (waitResult.$2 != null) {
    return RuntimeLineDecodeResult.rejected(waitResult.$2!);
  }
  final kind = RuntimeEventKindX.fromWire(eventKind);
  final familyValue = _string(map['family']) ?? '';
  final priorityValue = _string(map['priority']) ?? '';
  final roleValue = _string(map['role']) ?? '';
  final correlationValue = _string(map['correlation_status']);
  var correlation =
      correlationValue == null
          ? RuntimeCorrelationStatus.runtimeOnly
          : RuntimeCorrelationStatusX.tryParse(correlationValue);
  correlation ??= RuntimeCorrelationStatus.runtimeOnly;
  final snapshotId = _string(map['snapshot_id']);
  final siteId = _string(map['site_id']);
  if (snapshotId == null || siteId == null) {
    correlation = RuntimeCorrelationStatus.runtimeOnly;
  }
  return RuntimeLineDecodeResult.ok(
    RuntimeDecodedEvent(
      RuntimeEventRecord(
        kind: kind,
        rawKind: eventKind,
        family: RuntimeEventFamilyX.fromWire(familyValue),
        rawFamily: familyValue,
        priority: RuntimeEventPriorityX.fromWire(priorityValue),
        rawPriority: priorityValue,
        correlationStatus: correlation,
        role: RuntimeSiteRoleX.fromWire(roleValue),
        rawRole: roleValue,
        eventId: eventId,
        monotonicNs: _int(map['monotonic_ns']) ?? 0,
        snapshotId: snapshotId,
        siteId: siteId,
        instanceId: instanceId,
        causes: causesResult.$1,
        wait: waitResult.$1,
        unitId: _string(map['unit_id']),
        testName: _string(map['test_name']),
        intent: _string(map['intent']),
        phase: _string(map['phase']),
        operation: _string(map['operation']),
        diagnosticCode: _string(map['diagnostic_code']),
        stream: _string(map['stream']),
        fromPhase: _string(map['from_phase']),
        toPhase: _string(map['to_phase']),
        finalPhase: _string(map['final_phase']),
        success: _bool(map['success']),
        executed: _bool(map['executed']),
        queueDepth: _int(map['queue_depth']),
        queueCapacity: _int(map['queue_capacity']),
        count: _int(map['count']),
        durationNs: _int(map['duration_ns']),
      ),
    ),
  );
}

(List<RuntimeCausalEdge>, RuntimeRecordRejection?) _decodeCauses(
  Object? raw,
) {
  if (raw == null) {
    return (const <RuntimeCausalEdge>[], null);
  }
  if (raw is! List) {
    return (const <RuntimeCausalEdge>[], null);
  }
  final causes = <RuntimeCausalEdge>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final kindValue = _string(item['kind']) ?? '';
    final eventId = _string(item['event_id']);
    if (eventId == null ||
        !runtimeIdHasPrefix(eventId, kRuntimeEventIdPrefix)) {
      return (
        const <RuntimeCausalEdge>[],
        const RuntimeRecordRejection(
          subcode: RuntimeRecordSubcode.malformedIdentity,
          detail: 'malformed cause event_id',
        ),
      );
    }
    final subject = _string(item['subject_instance']);
    if (subject != null &&
        !runtimeIdHasPrefix(subject, kRuntimeInstanceIdPrefix)) {
      return (
        const <RuntimeCausalEdge>[],
        const RuntimeRecordRejection(
          subcode: RuntimeRecordSubcode.malformedIdentity,
          detail: 'malformed cause subject_instance',
        ),
      );
    }
    causes.add(
      RuntimeCausalEdge(
        kind: RuntimeCausalKindX.fromWire(kindValue),
        rawKind: kindValue,
        eventId: eventId,
        subjectInstance: subject,
      ),
    );
  }
  return (causes, null);
}

(RuntimeWaitFields?, RuntimeRecordRejection?) _decodeWait(Object? raw) {
  if (raw == null) {
    return (null, null);
  }
  if (raw is! Map) {
    return (null, null);
  }
  final waitId = _string(raw['wait_id']);
  if (waitId == null || waitId.isEmpty) {
    return (null, null);
  }
  if (!runtimeIdHasPrefix(waitId, kRuntimeWaitIdPrefix)) {
    return (
      null,
      const RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed wait_id',
      ),
    );
  }
  final waiter = _string(raw['waiter_instance']);
  if (waiter != null &&
      !runtimeIdHasPrefix(waiter, kRuntimeInstanceIdPrefix)) {
    return (
      null,
      const RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed waiter_instance',
      ),
    );
  }
  final subject = _string(raw['subject_instance']);
  if (subject != null &&
      !runtimeIdHasPrefix(subject, kRuntimeInstanceIdPrefix)) {
    return (
      null,
      const RuntimeRecordRejection(
        subcode: RuntimeRecordSubcode.malformedIdentity,
        detail: 'malformed wait subject_instance',
      ),
    );
  }
  final reasonValue = _string(raw['reason']) ?? 'unknown';
  final resolutionValue = _string(raw['resolution']);
  return (
    RuntimeWaitFields(
      waitId: waitId,
      waiterInstance: waiter,
      subjectInstance: subject,
      reason: RuntimeWaitReasonX.fromWire(reasonValue),
      rawReason: reasonValue,
      resolution: resolutionValue == null
          ? null
          : RuntimeWaitResolutionX.fromWire(resolutionValue),
      rawResolution: resolutionValue,
      durationNs: _int(raw['duration_ns']),
    ),
    null,
  );
}

String? _string(Object? value) {
  if (value is String) {
    return value;
  }
  return null;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

bool? _bool(Object? value) {
  if (value is bool) {
    return value;
  }
  return null;
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}

Map<String, Object?> runtimeRecordEnvelopePayload(RuntimeDecodedRecord record) {
  return switch (record) {
    RuntimeDecodedCapability(:final record) => <String, Object?>{
      'event_kind': 'session.capability',
      'mode': record.mode.wireValue,
      'snapshot_schema': record.snapshotSchema,
      'snapshot_id': record.snapshotId,
      'execution_id': record.executionId,
      'privacy_profile': record.privacyProfile,
      'producer_lanes': record.producerLanes,
      'lane_capacity': record.laneCapacity,
      'priority_reserved': record.priorityReserved,
      'drain_batch': record.drainBatch,
      'sampling': <String, Object?>{
        'numerator': record.sampling.numerator,
        'denominator': record.sampling.denominator,
        'seed': record.sampling.seed,
      },
      'clock_unit': record.clockUnit,
      'supported_capabilities': record.supportedCapabilities,
      'active_capabilities': record.activeCapabilities,
      'unavailable_capabilities': record.unavailableCapabilities,
    },
    RuntimeDecodedSummary(:final record) => <String, Object?>{
      'event_kind': 'session.summary',
      'mode': record.mode.wireValue,
      'execution_id': record.executionId,
      'completeness': record.rawCompleteness,
      'exporter_failed': record.exporterFailed,
      'lane_capacity': record.laneCapacity,
      'priority_reserved': record.priorityReserved,
      'producer_lanes': record.producerLanes,
      'high_water_occupancy': record.highWaterOccupancy,
      'families': <String, Object?>{
        for (final entry in record.families.entries)
          entry.key: <String, Object?>{
            'observed': entry.value.observed,
            'emitted': entry.value.emitted,
            'aggregated': entry.value.aggregated,
            'sampled_out': entry.value.sampledOut,
            'buffer_dropped': entry.value.bufferDropped,
            'exporter_dropped': entry.value.exporterDropped,
            'summary_updates': entry.value.summaryUpdates,
          },
      },
    },
    RuntimeDecodedEvent(:final record) => <String, Object?>{
      'family': record.rawFamily,
      'priority': record.rawPriority,
      'correlation_status': record.correlationStatus.wireValue,
      'role': record.rawRole,
      'snapshot_id': record.snapshotId,
      'site_id': record.siteId,
      'instance_id': record.instanceId,
      'event_id': record.eventId,
      'monotonic_ns': record.monotonicNs,
      'causes': <Object?>[
        for (final cause in record.causes)
          <String, Object?>{
            'kind': cause.rawKind,
            'event_id': cause.eventId,
            'subject_instance': cause.subjectInstance,
          },
      ],
      'wait': record.wait == null
          ? null
          : <String, Object?>{
              'wait_id': record.wait!.waitId,
              'waiter_instance': record.wait!.waiterInstance,
              'subject_instance': record.wait!.subjectInstance,
              'reason': record.wait!.rawReason,
              'resolution': record.wait!.rawResolution,
              'duration_ns': record.wait!.durationNs,
            },
      if (record.unitId != null) 'unit_id': record.unitId,
      if (record.testName != null) 'test_name': record.testName,
      if (record.intent != null) 'intent': record.intent,
      if (record.phase != null) 'phase': record.phase,
      if (record.operation != null) 'operation': record.operation,
      if (record.diagnosticCode != null)
        'diagnostic_code': record.diagnosticCode,
      if (record.stream != null) 'stream': record.stream,
      if (record.fromPhase != null) 'from_phase': record.fromPhase,
      if (record.toPhase != null) 'to_phase': record.toPhase,
      if (record.finalPhase != null) 'final_phase': record.finalPhase,
      if (record.success != null) 'success': record.success,
      if (record.executed != null) 'executed': record.executed,
      if (record.queueDepth != null) 'queue_depth': record.queueDepth,
      if (record.queueCapacity != null) 'queue_capacity': record.queueCapacity,
      if (record.count != null) 'count': record.count,
      if (record.durationNs != null) 'duration_ns': record.durationNs,
    },
  };
}

String runtimeRecordEventKind(RuntimeDecodedRecord record) {
  return switch (record) {
    RuntimeDecodedCapability() => 'session.capability',
    RuntimeDecodedSummary() => 'session.summary',
    RuntimeDecodedEvent(:final record) => record.rawKind,
  };
}

int runtimeRecordMonotonicNs(RuntimeDecodedRecord record) {
  return switch (record) {
    RuntimeDecodedEvent(:final record) => record.monotonicNs,
    _ => 0,
  };
}
