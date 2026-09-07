import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

void main() {
  List<String> linesOf(String text) {
    return text.split('\n');
  }

  test('canonical fixture decodes identically on repeated runs', () {
    final text = readObservableRuntimeFixture('canonical.jsonl');
    final first = decodeRuntimeStream(linesOf(text));
    final second = decodeRuntimeStream(linesOf(text));
    expect(first.isOk, isTrue);
    expect(second.records, first.records);
    expect(first.records, hasLength(8));
    expect(first.records.first, isA<RuntimeDecodedCapability>());
    expect(first.records.last, isA<RuntimeDecodedSummary>());
    final created = first.records[1] as RuntimeDecodedEvent;
    expect(created.record.kind, RuntimeEventKind.taskCreated);
    expect(created.record.snapshotId, startsWith(kRuntimeSnapshotIdPrefix));
    expect(created.record.siteId, startsWith(kRuntimeSiteIdPrefix));
  });

  test('additive fields are ignored and repeated decode matches', () {
    final text = readObservableRuntimeFixture('additive-fields.jsonl');
    final first = [
      for (final line in linesOf(text))
        if (line.trim().isNotEmpty) decodeRuntimeRecord(line),
    ];
    final second = [
      for (final line in linesOf(text))
        if (line.trim().isNotEmpty) decodeRuntimeRecord(line),
    ];
    expect(first.every((result) => result.isOk), isTrue);
    expect(
      first.map((result) => result.record),
      second.map((result) => result.record),
    );
    final encoded = first.map((result) => '${result.record}').join();
    expect(encoded.contains('future_hint'), isFalse);
    expect(encoded.contains('consumer_private_tag'), isFalse);
    expect(encoded.contains('extra_wait_note'), isFalse);
    expect(encoded.contains('unknown_sidecar'), isFalse);
  });

  test('stream-level negatives reject with named subcodes and no records', () {
    const cases = <String, RuntimeStreamSubcode>{
      'unsupported-contract.jsonl': RuntimeStreamSubcode.unsupportedContract,
      'unsupported-schema-version.jsonl':
          RuntimeStreamSubcode.unsupportedSchemaVersion,
      'unsupported-snapshot-schema.jsonl':
          RuntimeStreamSubcode.unsupportedSnapshotSchema,
      'missing-capability-record.jsonl':
          RuntimeStreamSubcode.missingCapabilityRecord,
      'capability-not-first.jsonl':
          RuntimeStreamSubcode.capabilityRecordNotFirst,
      'duplicate-capability-record.jsonl':
          RuntimeStreamSubcode.duplicateCapabilityRecord,
      'unknown-mode.jsonl': RuntimeStreamSubcode.unknownMode,
    };
    for (final entry in cases.entries) {
      final result = decodeRuntimeStream(
        linesOf(readObservableRuntimeVityoFixture(entry.key)),
      );
      expect(result.isOk, isFalse, reason: entry.key);
      expect(result.streamSubcode, entry.value, reason: entry.key);
      expect(result.records, isEmpty, reason: entry.key);
    }
  });

  test('record-level negatives count skipped records and keep the rest', () {
    final malformed = decodeRuntimeStream(
      linesOf(readObservableRuntimeVityoFixture('malformed-json-line.jsonl')),
    );
    expect(malformed.isOk, isTrue);
    expect(
      malformed.degradations.any(
        (item) => item.subcode == RuntimeRecordSubcode.malformedJson,
      ),
      isTrue,
    );
    expect(malformed.records.whereType<RuntimeDecodedEvent>(), isNotEmpty);

    final missing = decodeRuntimeStream(
      linesOf(readObservableRuntimeVityoFixture('missing-event-id.jsonl')),
    );
    expect(
      missing.degradations.any(
        (item) => item.subcode == RuntimeRecordSubcode.missingField,
      ),
      isTrue,
    );
    expect(missing.records.whereType<RuntimeDecodedEvent>(), isNotEmpty);

    final identity = decodeRuntimeStream(
      linesOf(readObservableRuntimeVityoFixture('malformed-identity.jsonl')),
    );
    expect(
      identity.degradations.any(
        (item) => item.subcode == RuntimeRecordSubcode.malformedIdentity,
      ),
      isTrue,
    );
    expect(identity.records.whereType<RuntimeDecodedEvent>(), isNotEmpty);
  });

  test('unknown event kinds decode as unknown and are counted', () {
    final result = decodeRuntimeStream(
      linesOf(readObservableRuntimeVityoFixture('unknown-event-kind.jsonl')),
    );
    expect(result.isOk, isTrue);
    final unknown = result.records.whereType<RuntimeDecodedEvent>().where(
      (record) => record.record.kind == RuntimeEventKind.unknown,
    );
    expect(unknown, isNotEmpty);
    expect(
      result.degradations.any(
        (item) => item.subcode == RuntimeRecordSubcode.unknownEventKind,
      ),
      isTrue,
    );
  });

  test('disabled-mode capability with null snapshot_id decodes', () {
    // The producer writes `snapshot_id: null` whenever no snapshot was bound,
    // which is every plain (non-observed) run. Rejecting that shape would
    // drop every controller event from existing execution sessions.
    final result = decodeRuntimeStream(
      linesOf(readObservableRuntimeVityoFixture('disabled-mode.jsonl')),
    );
    expect(result.isOk, isTrue);
    expect(result.degradations, isEmpty);
    expect(result.records, hasLength(5));
    final capability =
        (result.records.first as RuntimeDecodedCapability).record;
    expect(capability.mode, RuntimeObservationMode.disabled);
    expect(capability.snapshotId, isNull);
    expect(capability.executionId, 'x2_0000000000000007');
    final events = result.records.whereType<RuntimeDecodedEvent>().toList();
    expect(
      events.map((event) => event.record.kind),
      <RuntimeEventKind>[
        RuntimeEventKind.compileStarted,
        RuntimeEventKind.transitionFired,
        RuntimeEventKind.compileFinished,
      ],
    );
    expect(
      events.every(
        (event) =>
            event.record.correlationStatus == RuntimeCorrelationStatus.runtimeOnly,
      ),
      isTrue,
    );
    final summary = (result.records.last as RuntimeDecodedSummary).record;
    expect(summary.completeness, RuntimeCompleteness.partialDisabled);
  });

  test('a capability with a wrongly prefixed snapshot_id still rejects', () {
    final lines = linesOf(
      readObservableRuntimeVityoFixture('disabled-mode.jsonl'),
    );
    final tampered = lines.first.replaceAll(
      '"snapshot_id":null',
      '"snapshot_id":"zz_not_a_snapshot"',
    );
    final result = decodeRuntimeStream([tampered, ...lines.skip(1)]);
    expect(result.isOk, isFalse);
    expect(result.streamSubcode, RuntimeStreamSubcode.malformedIdentity);
    expect(result.records, isEmpty);
  });

  test('additive canary strings never appear in decoded values', () {
    final result = decodeRuntimeStream(
      linesOf(readObservableRuntimeVityoFixture('additive-canaries.jsonl')),
    );
    expect(result.isOk, isTrue);
    final dump = result.records.toString();
    expect(dump.contains('vityo-additive-canary'), isFalse);
    expect(dump.contains('future_hint'), isFalse);
    expect(dump.contains('unknown_sidecar'), isFalse);
  });
}
