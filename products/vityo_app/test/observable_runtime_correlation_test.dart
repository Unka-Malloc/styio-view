import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

import 'observable_fixture_support.dart';

const _snapshot = 's1_0123456789abcdef0123456789abcdef';
const _taskSite = 'n1_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _awaitSite = 'n1_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _unknownSite = 'n1_cccccccccccccccccccccccccccccccc';
const _staleSnapshot = 's1_ffffffffffffffffffffffffffffffff';

void main() {
  RuntimeOverlay overlayOf(String fixture, {bool vityo = false}) {
    final text = vityo
        ? readObservableRuntimeVityoFixture(fixture)
        : readObservableRuntimeFixture(fixture);
    final stream = decodeRuntimeStream(text.split('\n'));
    expect(stream.isOk, isTrue, reason: fixture);
    return foldRuntimeOverlay(
      headSnapshotId: _snapshot,
      headSiteIds: const <String>[_taskSite, _awaitSite],
      stream: stream,
    );
  }

  test('canonical fold is complete with exact site facts and runtime-only queue', () {
    final first = overlayOf('canonical.jsonl');
    final second = overlayOf('canonical.jsonl');
    expect(first, second);
    expect(first.presentation.isComplete, isTrue);
    expect(first.activitySource, RuntimeActivitySource.aggregateShards);
    final task = first.sites[_taskSite]!;
    expect(task.instancesCreated, 1);
    expect(task.instancesCompleted, 1);
    expect(task.instancesActive, 0);
    final awaitSite = first.sites[_awaitSite]!;
    final wait = awaitSite.waits[RuntimeWaitReason.task]!;
    expect(wait.open, 0);
    expect(wait.closed, 1);
    expect(wait.totalDurationNs, 60);
    expect(first.blockedLinks, hasLength(1));
    expect(first.blockedLinks.single.fromSite, _awaitSite);
    expect(first.blockedLinks.single.toSite, _taskSite);
    expect(first.blockedLinks.single.reason, RuntimeWaitReason.task);
    expect(first.uncorrelated.runtimeOnly, 1);
    expect(first.sites[_taskSite]!.queuePressureEvents, 0);
    expect(first.counters.sessionQueuePressureEvents, 1);
  });

  test('unknown-site and stale-snapshot never land on a head site', () {
    final unknown = overlayOf('unknown-site.jsonl', vityo: true);
    expect(unknown.uncorrelated.unknownSite, 1);
    expect(unknown.uncorrelated.unknownSiteIds, contains(_unknownSite));
    expect(unknown.sites[_unknownSite], isNull);
    expect(unknown.sites[_taskSite]!.instancesCreated, 1);

    final stale = overlayOf('stale-snapshot.jsonl', vityo: true);
    expect(stale.uncorrelated.staleSnapshot, 1);
    expect(stale.uncorrelated.staleSnapshotIds, contains(_staleSnapshot));
    expect(stale.sites[_taskSite]!.instancesCreated, 1);
  });

  test('runtime-only waits count per reason', () {
    final overlay = overlayOf('runtime-only-waits.jsonl', vityo: true);
    expect(overlay.uncorrelated.runtimeOnly, 3);
    expect(overlay.uncorrelated.runtimeOnlyWaits[RuntimeWaitReason.runnable], 1);
    expect(overlay.uncorrelated.runtimeOnlyWaits[RuntimeWaitReason.task], 1);
    expect(
      overlay.uncorrelated.runtimeOnlyWaits[RuntimeWaitReason.backpressure],
      1,
    );
  });

  test('unmatched wait end is counted', () {
    final overlay = overlayOf('wait-end-without-begin.jsonl', vityo: true);
    expect(overlay.counters.unmatchedWaitEnds, 1);
    expect(overlay.presentation.kind, RuntimePresentationKind.partial);
    expect(overlay.presentation.classes, contains('unmatched_waits'));
  });

  test('aggregate and detailed fixtures yield equal per-site activity', () {
    final aggregate = overlayOf('aggregate-mode.jsonl', vityo: true);
    final detailed = overlayOf('detailed-equivalent.jsonl', vityo: true);
    expect(
      aggregate.sites[_taskSite]!.activity(aggregate.activitySource),
      detailed.sites[_taskSite]!.activity(detailed.activitySource),
    );
    expect(
      aggregate.sites[_awaitSite]!.activity(aggregate.activitySource),
      detailed.sites[_awaitSite]!.activity(detailed.activitySource),
    );
    expect(aggregate.activitySource, RuntimeActivitySource.aggregateShards);
    expect(aggregate.activitySource.legendName, 'aggregate shards');
    expect(aggregate.presentation.classes, contains('aggregation'));
    expect(detailed.activitySource, RuntimeActivitySource.emittedEvents);
  });

  test('sampled mode shows the producer ratio', () {
    final overlay = overlayOf('sampled-mode.jsonl', vityo: true);
    expect(overlay.mode, RuntimeObservationMode.sampled);
    expect(overlay.capability!.sampling.numerator, 1);
    expect(overlay.capability!.sampling.denominator, 16);
    expect(overlay.presentation.classes, contains('sampling'));
  });

  test('failures and queue pressure attribute through lifecycle and causes', () {
    final overlay = overlayOf('failures-and-queue-pressure.jsonl', vityo: true);
    final task = overlay.sites[_taskSite]!;
    expect(task.instancesCreated, 1);
    expect(task.instancesFailed, 1);
    expect(task.instancesActive, 0);
    expect(task.queuePressureEvents, 1);
    expect(task.maxQueueDepth, 8);
    expect(task.queueCapacity, 8);
    expect(overlay.uncorrelated.runtimeOnly, 0);
  });

  test('summary-missing conservation and mismatch yield partial classes', () {
    final missing = overlayOf('summary-missing.jsonl', vityo: true);
    expect(missing.summaryMissing, isTrue);
    expect(missing.presentation.classes, contains('summary_missing'));

    final conservation = overlayOf('conservation-violation.jsonl', vityo: true);
    expect(conservation.counters.conservationViolations, greaterThan(0));
    expect(conservation.presentation.classes, contains('accounting_mismatch'));

    final mismatch = overlayOf('emitted-mismatch.jsonl', vityo: true);
    expect(mismatch.counters.emittedCountMismatches, greaterThan(0));
    expect(mismatch.presentation.classes, contains('accounting_mismatch'));
  });

  test('disabled-mode stream joins nothing and names no snapshot', () {
    final stream = decodeRuntimeStream(
      readObservableRuntimeVityoFixture('disabled-mode.jsonl').split('\n'),
    );
    expect(stream.isOk, isTrue);
    final overlay = foldRuntimeOverlay(
      headSnapshotId: _snapshot,
      headSiteIds: const <String>[_taskSite, _awaitSite],
      stream: stream,
    );
    // A null capability snapshot must survive as null so the controller fails
    // closed to stale-snapshot instead of overlaying the retained head.
    expect(overlay.snapshotId, isNull);
    expect(overlay.mode, RuntimeObservationMode.disabled);
    expect(overlay.counters.controllerEvents, 3);
    expect(overlay.sites[_taskSite]!.lifecycleEvents, 0);
    expect(overlay.sites[_awaitSite]!.lifecycleEvents, 0);
    expect(overlay.blockedLinks, isEmpty);
    expect(overlay.uncorrelated.runtimeOnly, 0);
    expect(overlay.presentation.isComplete, isFalse);
    expect(overlay.presentation.classes, contains('partial/disabled'));
  });

  test('queue records never attribute through their own site id', () {
    String event(String body) =>
        '{"contract":"styio.observable.runtime-events","schema_version":2,'
        '"record_kind":"event",$body}';
    final stream = decodeRuntimeStream(<String>[
      '{"contract":"styio.observable.runtime-events","schema_version":2,'
          '"record_kind":"session.capability","event_kind":"session.capability",'
          '"mode":"detailed","snapshot_schema":1,"snapshot_id":"$_snapshot",'
          '"execution_id":"x2_0000000000000001"}',
      // Registers i2_...aa on the task site of the retained head.
      event('"event_kind":"task.created","family":"task_lifecycle",'
          '"priority":"lifecycle","correlation_status":"correlated","role":"task",'
          '"snapshot_id":"$_snapshot","site_id":"$_taskSite",'
          '"instance_id":"i2_00000000000000aa","event_id":"r2_00000000000000aa",'
          '"monotonic_ns":100,"causes":[],"wait":null'),
      // Stale snapshot whose site id collides with a head site: must stay
      // session-level and land in the stale bucket, never on the head site.
      event('"event_kind":"queue.pressure","family":"queue","priority":"detail",'
          '"correlation_status":"correlated","role":"task",'
          '"snapshot_id":"$_staleSnapshot","site_id":"$_taskSite",'
          '"instance_id":null,"event_id":"r2_00000000000000b1",'
          '"monotonic_ns":110,"causes":[],"wait":null,'
          '"queue_depth":7,"queue_capacity":8'),
      // Correlated to the head but its cause subject never registered through
      // a lifecycle record: session-level, not site-attributed.
      event('"event_kind":"queue.pressure","family":"queue","priority":"detail",'
          '"correlation_status":"correlated","role":"task",'
          '"snapshot_id":"$_snapshot","site_id":"$_taskSite",'
          '"instance_id":null,"event_id":"r2_00000000000000b2",'
          '"monotonic_ns":120,"causes":[{"kind":"backpressure_relief",'
          '"event_id":"r2_00000000000000b2","subject_instance":"i2_00000000000000ff"}],'
          '"wait":null,"queue_depth":6,"queue_capacity":8'),
      // Control: attribution through a registered cause subject still works.
      event('"event_kind":"queue.pressure","family":"queue","priority":"detail",'
          '"correlation_status":"runtime_only","role":"runtime_only",'
          '"snapshot_id":null,"site_id":null,'
          '"instance_id":null,"event_id":"r2_00000000000000b3",'
          '"monotonic_ns":130,"causes":[{"kind":"backpressure_relief",'
          '"event_id":"r2_00000000000000b3","subject_instance":"i2_00000000000000aa"}],'
          '"wait":null,"queue_depth":5,"queue_capacity":8'),
    ]);
    expect(stream.isOk, isTrue);
    final overlay = foldRuntimeOverlay(
      headSnapshotId: _snapshot,
      headSiteIds: const <String>[_taskSite, _awaitSite],
      stream: stream,
    );
    final task = overlay.sites[_taskSite]!;
    expect(task.queuePressureEvents, 1);
    expect(task.maxQueueDepth, 5);
    expect(overlay.counters.sessionQueuePressureEvents, 2);
    expect(overlay.uncorrelated.staleSnapshot, 1);
    expect(overlay.uncorrelated.staleSnapshotIds, contains(_staleSnapshot));
    expect(overlay.uncorrelated.runtimeOnly, 0);
    expect(overlay.uncorrelated.unknownSite, 0);
  });

  test('one million generated records stay within capacities', () {
    const siteCount = 8;
    final sites = <String>[
      for (var i = 0; i < siteCount; i += 1)
        'n1_${i.toRadixString(16).padLeft(32, 'a')}',
    ];
    final folder = RuntimeOverlayFolder(
      headSnapshotId: _snapshot,
      headSiteIds: sites,
    );
    folder.ingest(
      const RuntimeDecodedCapability(
        RuntimeCapabilityRecord(
          mode: RuntimeObservationMode.detailed,
          snapshotSchema: 1,
          snapshotId: _snapshot,
          executionId: 'x2_0000000000000001',
          privacyProfile: 'strict',
          producerLanes: 1,
          laneCapacity: 256,
          priorityReserved: 32,
          drainBatch: 64,
          sampling: RuntimeSamplingSpec(
            numerator: 1,
            denominator: 16,
            seed: 0,
          ),
          clockUnit: 'ns',
          supportedCapabilities: kRuntimeRequiredCapabilities,
          activeCapabilities: kRuntimeRequiredCapabilities,
          unavailableCapabilities: <String>[],
        ),
      ),
    );
    const createdCount = 700000;
    const waitCount = 200000;
    const queueCount = 100000;
    for (var i = 0; i < createdCount; i += 1) {
      final site = sites[i % siteCount];
      final hex = i.toRadixString(16).padLeft(16, '0');
      folder.ingest(
        RuntimeDecodedEvent(
          RuntimeEventRecord(
            kind: RuntimeEventKind.taskCreated,
            rawKind: 'task.created',
            family: RuntimeEventFamily.taskLifecycle,
            rawFamily: 'task_lifecycle',
            priority: RuntimeEventPriority.lifecycle,
            rawPriority: 'lifecycle',
            correlationStatus: RuntimeCorrelationStatus.correlated,
            role: RuntimeSiteRole.task,
            rawRole: 'task',
            eventId: 'r2_$hex',
            monotonicNs: i,
            snapshotId: _snapshot,
            siteId: site,
            instanceId: 'i2_$hex',
          ),
        ),
      );
    }
    for (var i = 0; i < waitCount; i += 1) {
      final site = sites[i % siteCount];
      final hex = (createdCount + i).toRadixString(16).padLeft(16, '0');
      folder.ingest(
        RuntimeDecodedEvent(
          RuntimeEventRecord(
            kind: RuntimeEventKind.waitBegin,
            rawKind: 'wait.begin',
            family: RuntimeEventFamily.wait,
            rawFamily: 'wait',
            priority: RuntimeEventPriority.lifecycle,
            rawPriority: 'lifecycle',
            correlationStatus: RuntimeCorrelationStatus.correlated,
            role: RuntimeSiteRole.awaitSite,
            rawRole: 'await',
            eventId: 'r2_$hex',
            monotonicNs: createdCount + i,
            snapshotId: _snapshot,
            siteId: site,
            instanceId: 'i2_$hex',
            wait: RuntimeWaitFields(
              waitId: 'w2_$hex',
              waiterInstance: 'i2_$hex',
              reason: RuntimeWaitReason.task,
              rawReason: 'task',
            ),
          ),
        ),
      );
    }
    for (var i = 0; i < queueCount; i += 1) {
      folder.ingest(
        RuntimeDecodedEvent(
          RuntimeEventRecord(
            kind: RuntimeEventKind.queuePressure,
            rawKind: 'queue.pressure',
            family: RuntimeEventFamily.queue,
            rawFamily: 'queue',
            priority: RuntimeEventPriority.detail,
            rawPriority: 'detail',
            correlationStatus: RuntimeCorrelationStatus.runtimeOnly,
            role: RuntimeSiteRole.runtimeOnly,
            rawRole: 'runtime_only',
            eventId: 'r2_${(createdCount + waitCount + i).toRadixString(16).padLeft(16, '0')}',
            monotonicNs: createdCount + waitCount + i,
            queueDepth: 1,
            queueCapacity: 8,
          ),
        ),
      );
    }
    final overlay = folder.finish();
    expect(overlay.sites.length, siteCount);
    for (final facts in overlay.sites.values) {
      expect(facts.recentEvents.length, lessThanOrEqualTo(32));
    }
    expect(overlay.counters.instanceMapEvictions, createdCount - 65536);
    expect(overlay.counters.openWaitEvictions, waitCount - 16384);
    expect(overlay.uncorrelated.unknownSiteIds.length, lessThanOrEqualTo(64));
    expect(overlay.uncorrelated.staleSnapshotIds.length, lessThanOrEqualTo(16));
    expect(
      overlay.uncorrelated.samples.length,
      lessThanOrEqualTo(kRuntimeUncorrelatedSampleCapacity),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
