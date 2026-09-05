import 'observable_runtime_model.dart';

class RuntimeOverlayFolder {
  RuntimeOverlayFolder({
    required this.headSnapshotId,
    required Iterable<String> headSiteIds,
    this.capacities = RuntimeOverlayCapacities.defaults,
  }) : _headSites = headSiteIds.toSet();

  final String headSnapshotId;
  final Set<String> _headSites;
  final RuntimeOverlayCapacities capacities;

  RuntimeCapabilityRecord? _capability;
  RuntimeSummaryRecord? _summary;
  var _sawAggregateShard = false;
  var _rejectedRecords = 0;
  var _unknownKinds = 0;
  var _instanceMapEvictions = 0;
  var _openWaitEvictions = 0;
  var _blockedLinkEvictions = 0;
  var _unmatchedWaitEnds = 0;
  var _controllerEvents = 0;
  var _sessionQueuePressure = 0;
  final Map<String, int> _seenEmitted = <String, int>{};
  final Map<String, String> _instanceSites = <String, String>{};
  final Map<String, _OpenWait> _openWaits = <String, _OpenWait>{};
  final Map<String, RuntimeBlockedLink> _blockedLinks =
      <String, RuntimeBlockedLink>{};
  final Map<String, _MutableSite> _sites = <String, _MutableSite>{};
  var _runtimeOnly = 0;
  var _unknownSite = 0;
  var _staleSnapshot = 0;
  final Map<RuntimeWaitReason, int> _runtimeOnlyWaits =
      <RuntimeWaitReason, int>{};
  final List<String> _unknownSiteIds = <String>[];
  final Set<String> _unknownSiteIdSet = <String>{};
  final List<String> _staleSnapshotIds = <String>[];
  final Set<String> _staleSnapshotIdSet = <String>{};
  final List<RuntimeUncorrelatedSample> _samples =
      <RuntimeUncorrelatedSample>[];

  void ingest(RuntimeDecodedRecord record) {
    switch (record) {
      case RuntimeDecodedCapability(:final record):
        _capability = record;
      case RuntimeDecodedSummary(:final record):
        _summary = record;
      case RuntimeDecodedEvent(:final record):
        _ingestEvent(record);
    }
  }

  void ingestStream(RuntimeStreamDecodeResult stream) {
    for (final degradation in stream.degradations) {
      if (degradation.subcode != RuntimeRecordSubcode.unknownEventKind) {
        _rejectedRecords += 1;
      }
    }
    for (final record in stream.records) {
      ingest(record);
    }
  }

  /// Counts one record-level rejection without retaining its detail, so a
  /// streaming intake folds rejections into the bounded counters instead of
  /// accumulating one object per bad line. Unknown-kind records are not
  /// rejections: they are folded and counted by [ingest] itself.
  void noteRecordRejection() {
    _rejectedRecords += 1;
  }

  RuntimeOverlay finish() {
    final activitySource = _sawAggregateShard
        ? RuntimeActivitySource.aggregateShards
        : RuntimeActivitySource.emittedEvents;
    final sites = <String, RuntimeSiteFacts>{};
    var maxActivity = 0;
    for (final siteId in _headSites) {
      final mutable = _sites[siteId];
      final facts = mutable == null
          ? RuntimeSiteFacts(siteId: siteId)
          : mutable.toFacts(siteId);
      sites[siteId] = facts;
      final activity = facts.activity(activitySource);
      if (activity > maxActivity) {
        maxActivity = activity;
      }
    }
    var conservationViolations = 0;
    var emittedMismatches = 0;
    final summary = _summary;
    if (summary != null) {
      for (final entry in summary.families.entries) {
        if (!entry.value.conserves) {
          conservationViolations += 1;
        }
        final seen = _seenEmitted[entry.key] ?? 0;
        if (entry.value.emitted != seen) {
          emittedMismatches += 1;
        }
      }
    }
    final counters = RuntimeOverlayCounters(
      rejectedRecords: _rejectedRecords,
      unknownKinds: _unknownKinds,
      instanceMapEvictions: _instanceMapEvictions,
      openWaitEvictions: _openWaitEvictions,
      blockedLinkEvictions: _blockedLinkEvictions,
      unmatchedWaitEnds: _unmatchedWaitEnds,
      emittedCountMismatches: emittedMismatches,
      conservationViolations: conservationViolations,
      controllerEvents: _controllerEvents,
      sessionQueuePressureEvents: _sessionQueuePressure,
    );
    final presentation = _presentation(
      summary: summary,
      counters: counters,
    );
    return RuntimeOverlay(
      // No fallback to the head identity: a capability record that names no
      // snapshot (null) or another snapshot must never masquerade as the
      // retained head; the controller maps both to fail-closed staleness.
      snapshotId: _capability?.snapshotId,
      executionId: _capability?.executionId ?? '',
      mode: _capability?.mode ?? RuntimeObservationMode.detailed,
      activitySource: activitySource,
      presentation: presentation,
      sites: sites,
      blockedLinks: _blockedLinks.values.toList(growable: false),
      uncorrelated: RuntimeUncorrelatedBuckets(
        runtimeOnly: _runtimeOnly,
        unknownSite: _unknownSite,
        staleSnapshot: _staleSnapshot,
        runtimeOnlyWaits: Map<RuntimeWaitReason, int>.unmodifiable(
          _runtimeOnlyWaits,
        ),
        unknownSiteIds: List<String>.unmodifiable(_unknownSiteIds),
        staleSnapshotIds: List<String>.unmodifiable(_staleSnapshotIds),
        samples: List<RuntimeUncorrelatedSample>.unmodifiable(_samples),
      ),
      counters: counters,
      capability: _capability,
      summary: summary,
      maxActivity: maxActivity,
      summaryMissing: summary == null,
    );
  }
}

class _OpenWait {
  const _OpenWait({
    required this.waiterSite,
    required this.waiterInstance,
    required this.subjectInstance,
    required this.reason,
  });

  final String? waiterSite;
  final String? waiterInstance;
  final String? subjectInstance;
  final RuntimeWaitReason reason;
}

class _MutableSite {
  var instancesCreated = 0;
  var instancesCompleted = 0;
  var instancesFailed = 0;
  var lifecycleEvents = 0;
  var detailEvents = 0;
  var aggregateCount = 0;
  var aggregateDurationNs = 0;
  var queuePressureEvents = 0;
  var maxQueueDepth = 0;
  var queueCapacity = 0;
  var subjectUnresolved = 0;
  final Map<RuntimeWaitReason, RuntimeWaitFacts> waits =
      <RuntimeWaitReason, RuntimeWaitFacts>{};
  final List<RuntimeSiteEvent> recent = <RuntimeSiteEvent>[];

  RuntimeSiteFacts toFacts(String siteId) {
    return RuntimeSiteFacts(
      siteId: siteId,
      instancesCreated: instancesCreated,
      instancesCompleted: instancesCompleted,
      instancesFailed: instancesFailed,
      lifecycleEvents: lifecycleEvents,
      detailEvents: detailEvents,
      aggregateCount: aggregateCount,
      aggregateDurationNs: aggregateDurationNs,
      queuePressureEvents: queuePressureEvents,
      maxQueueDepth: maxQueueDepth,
      queueCapacity: queueCapacity,
      subjectUnresolved: subjectUnresolved,
      waits: Map<RuntimeWaitReason, RuntimeWaitFacts>.unmodifiable(waits),
      recentEvents: List<RuntimeSiteEvent>.unmodifiable(recent),
    );
  }
}

extension on RuntimeOverlayFolder {
  void _ingestEvent(RuntimeEventRecord record) {
    if (record.kind == RuntimeEventKind.unknown) {
      _unknownKinds += 1;
      return;
    }
    if (record.kind != RuntimeEventKind.aggregateShard &&
        record.family != RuntimeEventFamily.unknown) {
      final family = record.rawFamily.isEmpty
          ? record.family.wireValue
          : record.rawFamily;
      _seenEmitted[family] = (_seenEmitted[family] ?? 0) + 1;
    }
    if (record.family == RuntimeEventFamily.controller) {
      _controllerEvents += 1;
      return;
    }
    if (record.kind == RuntimeEventKind.aggregateShard) {
      _sawAggregateShard = true;
    }
    if (record.kind == RuntimeEventKind.queuePressure ||
        record.kind == RuntimeEventKind.queueClosed) {
      if (_tryAttributeQueue(record)) {
        return;
      }
      _sessionQueuePressure += 1;
      final queueClass = _classify(record);
      if (queueClass == RuntimeCorrelationClass.runtimeOnly) {
        _runtimeOnly += 1;
        _sample(queueClass, record);
      } else if (queueClass == RuntimeCorrelationClass.unknownSite) {
        _unknownSite += 1;
        _rememberId(
          record.siteId,
          _unknownSiteIds,
          _unknownSiteIdSet,
          capacities.unknownSiteIds,
        );
        _sample(queueClass, record);
      } else if (queueClass == RuntimeCorrelationClass.staleSnapshot) {
        _staleSnapshot += 1;
        _rememberId(
          record.snapshotId,
          _staleSnapshotIds,
          _staleSnapshotIdSet,
          capacities.staleSnapshotIds,
        );
        _sample(queueClass, record);
      }
      return;
    }

    final classification = _classify(record);
    switch (classification) {
      case RuntimeCorrelationClass.runtimeOnly:
        _runtimeOnly += 1;
        _noteWaitReason(record);
        _sample(classification, record);
      case RuntimeCorrelationClass.unknownSite:
        _unknownSite += 1;
        _rememberId(
          record.siteId,
          _unknownSiteIds,
          _unknownSiteIdSet,
          capacities.unknownSiteIds,
        );
        _sample(classification, record);
      case RuntimeCorrelationClass.staleSnapshot:
        _staleSnapshot += 1;
        _rememberId(
          record.snapshotId,
          _staleSnapshotIds,
          _staleSnapshotIdSet,
          capacities.staleSnapshotIds,
        );
        _sample(classification, record);
      case RuntimeCorrelationClass.correlatedSite:
        _ingestCorrelated(record);
    }
  }

  RuntimeCorrelationClass _classify(RuntimeEventRecord record) {
    if (record.correlationStatus != RuntimeCorrelationStatus.correlated ||
        record.snapshotId == null ||
        record.siteId == null) {
      return RuntimeCorrelationClass.runtimeOnly;
    }
    if (record.snapshotId != headSnapshotId) {
      return RuntimeCorrelationClass.staleSnapshot;
    }
    if (!_headSites.contains(record.siteId)) {
      return RuntimeCorrelationClass.unknownSite;
    }
    return RuntimeCorrelationClass.correlatedSite;
  }

  void _ingestCorrelated(RuntimeEventRecord record) {
    final siteId = record.siteId!;
    final site = _sites.putIfAbsent(siteId, _MutableSite.new);
    if (record.kind.isTaskLifecycle && record.instanceId != null) {
      _putInstance(record.instanceId!, siteId);
    }
    switch (record.kind) {
      case RuntimeEventKind.taskCreated:
        site.instancesCreated += 1;
        site.lifecycleEvents += 1;
      case RuntimeEventKind.taskCompleted:
        site.instancesCompleted += 1;
        site.lifecycleEvents += 1;
      case RuntimeEventKind.taskFailed:
        site.instancesFailed += 1;
        site.lifecycleEvents += 1;
      case RuntimeEventKind.taskEnqueued:
      case RuntimeEventKind.taskDequeued:
      case RuntimeEventKind.taskStarted:
      case RuntimeEventKind.taskResultConsumed:
      case RuntimeEventKind.taskReleased:
        site.lifecycleEvents += 1;
      case RuntimeEventKind.aggregateShard:
        site.aggregateCount += record.count ?? 0;
        site.aggregateDurationNs += record.durationNs ?? 0;
      case RuntimeEventKind.queuePressure:
      case RuntimeEventKind.queueClosed:
        _tryAttributeQueue(record);
      case RuntimeEventKind.waitBegin:
        site.lifecycleEvents += 1;
        _beginWait(record, site);
      case RuntimeEventKind.waitEnd:
        site.lifecycleEvents += 1;
        _endWait(record, site);
      default:
        if (record.priority == RuntimeEventPriority.lifecycle) {
          site.lifecycleEvents += 1;
        } else {
          site.detailEvents += 1;
        }
    }
    if (record.kind != RuntimeEventKind.aggregateShard) {
      _pushRing(
        site.recent,
        RuntimeSiteEvent(
          kind: record.kind,
          rawKind: record.rawKind,
          instanceId: record.instanceId,
          eventId: record.eventId,
          monotonicNs: record.monotonicNs,
          causes: record.causes,
        ),
        capacities.siteEventRing,
      );
    }
  }

  void _putInstance(String instanceId, String siteId) {
    if (_instanceSites.containsKey(instanceId)) {
      _instanceSites.remove(instanceId);
    } else if (_instanceSites.length >= capacities.instanceSiteMap) {
      _instanceSites.remove(_instanceSites.keys.first);
      _instanceMapEvictions += 1;
    }
    _instanceSites[instanceId] = siteId;
  }

  void _beginWait(RuntimeEventRecord record, _MutableSite site) {
    final wait = record.wait;
    if (wait == null) {
      return;
    }
    final current = site.waits[wait.reason] ?? const RuntimeWaitFacts();
    site.waits[wait.reason] = current.copyWith(open: current.open + 1);
    if (_openWaits.length >= capacities.openWait &&
        !_openWaits.containsKey(wait.waitId)) {
      _openWaits.remove(_openWaits.keys.first);
      _openWaitEvictions += 1;
    }
    _openWaits[wait.waitId] = _OpenWait(
      waiterSite: record.siteId,
      waiterInstance: wait.waiterInstance ?? record.instanceId,
      subjectInstance: wait.subjectInstance,
      reason: wait.reason,
    );
    _resolveLink(
      waiterSite: record.siteId,
      subjectInstance: wait.subjectInstance,
      reason: wait.reason,
      opening: true,
      durationNs: null,
      site: site,
    );
  }

  void _endWait(RuntimeEventRecord record, _MutableSite site) {
    final wait = record.wait;
    if (wait == null) {
      return;
    }
    final opened = _openWaits.remove(wait.waitId);
    final current = site.waits[wait.reason] ?? const RuntimeWaitFacts();
    if (opened == null) {
      site.waits[wait.reason] = current.copyWith(
        unmatchedEnds: current.unmatchedEnds + 1,
      );
      _unmatchedWaitEnds += 1;
      return;
    }
    var next = current.copyWith(
      open: current.open > 0 ? current.open - 1 : 0,
      closed: current.closed + 1,
    );
    final duration = wait.durationNs;
    if (duration != null) {
      next = next.copyWith(
        totalDurationNs: next.totalDurationNs + duration,
        maxDurationNs: duration > next.maxDurationNs
            ? duration
            : next.maxDurationNs,
        durationSamples: next.durationSamples + 1,
      );
    }
    site.waits[wait.reason] = next;
    _resolveLink(
      waiterSite: opened.waiterSite ?? record.siteId,
      subjectInstance: wait.subjectInstance ?? opened.subjectInstance,
      reason: wait.reason,
      opening: false,
      durationNs: duration,
      site: site,
    );
  }

  void _resolveLink({
    required String? waiterSite,
    required String? subjectInstance,
    required RuntimeWaitReason reason,
    required bool opening,
    required int? durationNs,
    required _MutableSite site,
  }) {
    if (waiterSite == null) {
      return;
    }
    if (subjectInstance == null) {
      site.subjectUnresolved += 1;
      return;
    }
    final subjectSite = _instanceSites[subjectInstance];
    if (subjectSite == null) {
      site.subjectUnresolved += 1;
      return;
    }
    final key = '$waiterSite\u001f$subjectSite\u001f${reason.wireValue}';
    var link = _blockedLinks[key];
    if (link == null) {
      if (_blockedLinks.length >= capacities.blockedLink) {
        _blockedLinks.remove(_blockedLinks.keys.first);
        _blockedLinkEvictions += 1;
      }
      link = RuntimeBlockedLink(
        fromSite: waiterSite,
        toSite: subjectSite,
        reason: reason,
      );
    }
    if (opening) {
      link = link.copyWith(open: link.open + 1);
    } else {
      link = link.copyWith(
        open: link.open > 0 ? link.open - 1 : 0,
        closed: link.closed + 1,
        totalDurationNs: durationNs == null
            ? link.totalDurationNs
            : link.totalDurationNs + durationNs,
      );
    }
    _blockedLinks[key] = link;
  }

  /// Queue records attribute to a site only through the cause
  /// `subject_instance` resolved by the instance map (which correlated
  /// task-lifecycle records of the retained head registered). The record's
  /// own `site_id` is never used: a stale-snapshot or otherwise uncorrelated
  /// record must not paint on the current head. Unattributed records stay
  /// session-level and are bucketed by their correlation class.
  bool _tryAttributeQueue(RuntimeEventRecord record) {
    String? siteId;
    for (final cause in record.causes) {
      final subject = cause.subjectInstance;
      if (subject != null && _instanceSites.containsKey(subject)) {
        siteId = _instanceSites[subject];
        break;
      }
    }
    if (siteId == null || !_headSites.contains(siteId)) {
      return false;
    }
    final site = _sites.putIfAbsent(siteId, _MutableSite.new);
    site.queuePressureEvents += 1;
    final depth = record.queueDepth ?? 0;
    if (depth > site.maxQueueDepth) {
      site.maxQueueDepth = depth;
    }
    if (record.queueCapacity != null) {
      site.queueCapacity = record.queueCapacity!;
    }
    if (record.kind != RuntimeEventKind.aggregateShard) {
      _pushRing(
        site.recent,
        RuntimeSiteEvent(
          kind: record.kind,
          rawKind: record.rawKind,
          instanceId: record.instanceId,
          eventId: record.eventId,
          monotonicNs: record.monotonicNs,
          causes: record.causes,
        ),
        capacities.siteEventRing,
      );
    }
    return true;
  }

  void _noteWaitReason(RuntimeEventRecord record) {
    final wait = record.wait;
    if (wait == null) {
      return;
    }
    if (record.kind == RuntimeEventKind.waitBegin ||
        record.kind == RuntimeEventKind.waitEnd) {
      _runtimeOnlyWaits[wait.reason] =
          (_runtimeOnlyWaits[wait.reason] ?? 0) + 1;
    }
  }

  void _sample(
    RuntimeCorrelationClass classification,
    RuntimeEventRecord record,
  ) {
    if (_samples.length >= capacities.uncorrelatedSample) {
      _samples.removeAt(0);
    }
    _samples.add(
      RuntimeUncorrelatedSample(
        classification: classification,
        eventId: record.eventId,
        rawKind: record.rawKind,
        snapshotId: record.snapshotId,
        siteId: record.siteId,
      ),
    );
  }

  void _rememberId(
    String? id,
    List<String> ids,
    Set<String> seen,
    int capacity,
  ) {
    if (id == null || seen.contains(id)) {
      return;
    }
    if (ids.length >= capacity) {
      return;
    }
    seen.add(id);
    ids.add(id);
  }

  void _pushRing(List<RuntimeSiteEvent> ring, RuntimeSiteEvent event, int cap) {
    if (ring.length >= cap) {
      ring.removeAt(0);
    }
    ring.add(event);
  }

  RuntimeOverlayPresentation _presentation({
    required RuntimeSummaryRecord? summary,
    required RuntimeOverlayCounters counters,
  }) {
    final classes = <String>[];
    if (summary == null) {
      classes.add('summary_missing');
    } else {
      if (summary.completeness != RuntimeCompleteness.complete) {
        classes.add(summary.rawCompleteness);
        final mapped = summary.completeness.presentationClass;
        if (mapped != null && !classes.contains(mapped)) {
          classes.add(mapped);
        }
      }
      if (summary.exporterFailed) {
        classes.add('exporter_failure');
      }
    }
    if (counters.rejectedRecords > 0) {
      classes.add('records_rejected');
    }
    if (counters.unknownKinds > 0) {
      classes.add('unknown_kinds');
    }
    if (counters.totalEvictions > 0) {
      classes.add('evictions');
    }
    if (counters.unmatchedWaitEnds > 0) {
      classes.add('unmatched_waits');
    }
    if (counters.emittedCountMismatches > 0 ||
        counters.conservationViolations > 0) {
      classes.add('accounting_mismatch');
    }
    final complete =
        summary != null &&
        summary.completeness == RuntimeCompleteness.complete &&
        !summary.exporterFailed &&
        counters.rejectedRecords == 0 &&
        counters.unknownKinds == 0 &&
        counters.totalEvictions == 0 &&
        counters.unmatchedWaitEnds == 0 &&
        counters.emittedCountMismatches == 0 &&
        counters.conservationViolations == 0;
    return RuntimeOverlayPresentation(
      kind: complete
          ? RuntimePresentationKind.complete
          : RuntimePresentationKind.partial,
      classes: classes,
    );
  }
}

RuntimeOverlay foldRuntimeOverlay({
  required String headSnapshotId,
  required Iterable<String> headSiteIds,
  required RuntimeStreamDecodeResult stream,
  RuntimeOverlayCapacities capacities = RuntimeOverlayCapacities.defaults,
}) {
  final folder = RuntimeOverlayFolder(
    headSnapshotId: headSnapshotId,
    headSiteIds: headSiteIds,
    capacities: capacities,
  );
  folder.ingestStream(stream);
  return folder.finish();
}
