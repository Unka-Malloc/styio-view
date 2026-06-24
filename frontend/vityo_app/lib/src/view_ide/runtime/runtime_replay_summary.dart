import '../backend_toolchain/execution_adapter.dart';

enum RuntimeAccent { failed, completed, active, observed, thread, test, log }

const Set<String> _knownRuntimeEventKinds = <String>{
  'compile.started',
  'compile.finished',
  'compile.failed',
  'diagnostic.emitted',
  'log.emitted',
  'run.started',
  'run.finished',
  'run.failed',
  'state.changed',
  'thread.spawned',
  'transition.fired',
  'unit.entered',
  'unit.exited',
  'unit.test.started',
  'unit.test.finished',
};

class RuntimeReplaySummary {
  const RuntimeReplaySummary({
    required this.events,
    required this.families,
    required this.lanes,
    required this.latestEvent,
    required this.windowLabel,
    required this.summarySentence,
  });

  final List<RuntimeEventEnvelope> events;
  final List<String> families;
  final List<RuntimeLaneSummary> lanes;
  final RuntimeEventEnvelope? latestEvent;
  final String windowLabel;
  final String summarySentence;
}

class RuntimeLaneSummary {
  const RuntimeLaneSummary({
    required this.family,
    required this.eventCount,
    required this.latestEventKind,
    required this.statusLabel,
    required this.windowLabel,
    required this.detailLabel,
    required this.accent,
  });

  final String family;
  final int eventCount;
  final String latestEventKind;
  final String statusLabel;
  final String windowLabel;
  final String? detailLabel;
  final RuntimeAccent accent;
}

class RuntimeGraphSummary {
  const RuntimeGraphSummary({
    required this.routeCheckpoints,
    required this.routeNodes,
    required this.nodeDetails,
    required this.transitionEdges,
    required this.edgeDetails,
    required this.observedNodes,
    required this.terminalNode,
    required this.routeTraceLabel,
    required this.observedDigestLabel,
    required this.summarySentence,
  });

  final List<RuntimeGraphCheckpoint> routeCheckpoints;
  final List<String> routeNodes;
  final List<RuntimeGraphNodeDetail> nodeDetails;
  final List<String> transitionEdges;
  final List<RuntimeGraphEdgeDetail> edgeDetails;
  final List<String> observedNodes;
  final String? terminalNode;
  final String? routeTraceLabel;
  final String? observedDigestLabel;
  final String summarySentence;
}

class RuntimeGraphNodeDetail {
  const RuntimeGraphNodeDetail({
    required this.label,
    required this.checkpointCount,
    required this.windowLabel,
    required this.sourceEventKinds,
    required this.detailLabels,
    required this.filterTokens,
    required this.filterLabel,
    required this.timelineLabel,
    required this.timelineCheckpoints,
    required this.inboundEdges,
    required this.outboundEdges,
    required this.relationLabel,
  });

  final String label;
  final int checkpointCount;
  final String windowLabel;
  final List<String> sourceEventKinds;
  final List<String> detailLabels;
  final List<String> filterTokens;
  final String filterLabel;
  final String? timelineLabel;
  final List<RuntimeGraphCheckpoint> timelineCheckpoints;
  final List<String> inboundEdges;
  final List<String> outboundEdges;
  final String? relationLabel;
}

class RuntimeGraphEdgeDetail {
  const RuntimeGraphEdgeDetail({
    required this.label,
    required this.checkpointCount,
    required this.windowLabel,
    required this.filterTokens,
    required this.filterLabel,
    required this.timelineLabel,
    required this.timelineCheckpoints,
  });

  final String label;
  final int checkpointCount;
  final String windowLabel;
  final List<String> filterTokens;
  final String filterLabel;
  final String? timelineLabel;
  final List<RuntimeGraphCheckpoint> timelineCheckpoints;
}

class RuntimeGraphCheckpoint {
  const RuntimeGraphCheckpoint({
    required this.clockLabel,
    required this.label,
    required this.sourceEventKind,
    required this.detailLabel,
  });

  final String clockLabel;
  final String label;
  final String sourceEventKind;
  final String? detailLabel;
}

class RuntimeDebugLaneSummary {
  const RuntimeDebugLaneSummary({
    required this.family,
    required this.title,
    required this.statusLabel,
    required this.eventCount,
    required this.windowLabel,
    required this.latestEventKind,
    required this.detailLabel,
    required this.digestLabel,
    required this.filterTokens,
    required this.filterLabel,
    required this.traceLabel,
    required this.checkpoints,
    required this.accent,
  });

  final String family;
  final String title;
  final String statusLabel;
  final int eventCount;
  final String windowLabel;
  final String latestEventKind;
  final String? detailLabel;
  final String digestLabel;
  final List<String> filterTokens;
  final String filterLabel;
  final String? traceLabel;
  final List<RuntimeDebugLaneCheckpoint> checkpoints;
  final RuntimeAccent accent;
}

class RuntimeDebugLaneCheckpoint {
  const RuntimeDebugLaneCheckpoint({
    required this.clockLabel,
    required this.eventKind,
    required this.detailLabel,
  });

  final String clockLabel;
  final String eventKind;
  final String? detailLabel;
}

String runtimeEventFamily(String eventKind) {
  if (!isKnownRuntimeEventKind(eventKind)) {
    return 'unsupported';
  }
  if (eventKind.startsWith('unit.test.')) {
    return 'unit.test';
  }
  final separator = eventKind.indexOf('.');
  if (separator <= 0) {
    return eventKind;
  }
  return eventKind.substring(0, separator);
}

bool isKnownRuntimeEventKind(String eventKind) {
  return _knownRuntimeEventKinds.contains(eventKind);
}

RuntimeReplaySummary summarizeRuntimeReplay(
  List<RuntimeEventEnvelope> runtimeEvents,
) {
  if (runtimeEvents.isEmpty) {
    return const RuntimeReplaySummary(
      events: <RuntimeEventEnvelope>[],
      families: <String>[],
      lanes: <RuntimeLaneSummary>[],
      latestEvent: null,
      windowLabel: 'No replay window.',
      summarySentence: 'No runtime replay has been published yet.',
    );
  }

  final families = runtimeEvents
      .map((event) => runtimeEventFamily(event.eventKind))
      .toSet()
      .toList(growable: false);
  final lanes = families
      .map(
        (family) => summarizeRuntimeLane(
          family,
          runtimeEvents
              .where((event) => runtimeEventFamily(event.eventKind) == family)
              .toList(growable: false),
        ),
      )
      .toList(growable: false);
  final start = runtimeEvents.first.timestamp;
  final end = runtimeEvents.last.timestamp;
  return RuntimeReplaySummary(
    events: runtimeEvents,
    families: families,
    lanes: lanes,
    latestEvent: runtimeEvents.last,
    windowLabel:
        'Window ${formatRuntimeClock(start)} -> ${formatRuntimeClock(end)}.',
    summarySentence:
        '${lanes.length} active lane(s); latest ${runtimeEvents.last.eventKind} from ${runtimeEvents.last.origin}.',
  );
}

RuntimeLaneSummary summarizeRuntimeLane(
  String family,
  List<RuntimeEventEnvelope> events,
) {
  final latest = events.last;
  final statuses = events
      .map((event) => runtimeEventStatus(event.eventKind))
      .toSet();
  final statusLabel = statuses.contains('failed')
      ? 'failed lane'
      : statuses.contains('finished') || statuses.contains('exited')
      ? 'completed lane'
      : statuses.contains('started') ||
            statuses.contains('entered') ||
            statuses.contains('spawned')
      ? 'active lane'
      : 'observed lane';
  final accent = statuses.contains('failed')
      ? RuntimeAccent.failed
      : statuses.contains('finished') || statuses.contains('exited')
      ? RuntimeAccent.completed
      : statuses.contains('started') ||
            statuses.contains('entered') ||
            statuses.contains('spawned')
      ? RuntimeAccent.active
      : RuntimeAccent.observed;
  return RuntimeLaneSummary(
    family: family,
    eventCount: events.length,
    latestEventKind: latest.eventKind,
    statusLabel: statusLabel,
    windowLabel:
        '${formatRuntimeClock(events.first.timestamp)} -> ${formatRuntimeClock(latest.timestamp)}',
    detailLabel: runtimeEventDetailLabel(latest),
    accent: accent,
  );
}

RuntimeGraphSummary summarizeRuntimeGraph(
  List<RuntimeEventEnvelope> runtimeEvents,
) {
  if (runtimeEvents.isEmpty) {
    return const RuntimeGraphSummary(
      routeCheckpoints: <RuntimeGraphCheckpoint>[],
      routeNodes: <String>[],
      nodeDetails: <RuntimeGraphNodeDetail>[],
      transitionEdges: <String>[],
      edgeDetails: <RuntimeGraphEdgeDetail>[],
      observedNodes: <String>[],
      terminalNode: null,
      routeTraceLabel: null,
      observedDigestLabel: null,
      summarySentence: 'No execution graph has been derived yet.',
    );
  }

  final phaseCheckpoints = <RuntimeGraphCheckpoint>[];
  final eventCheckpoints = <RuntimeGraphCheckpoint>[];
  final edgeCheckpoints = <RuntimeGraphCheckpoint>[];
  final phaseRouteNodes = <String>[];
  final eventRouteNodes = <String>[];
  final transitionEdges = <String>[];
  final observedNodes = <String>[];

  void appendUniqueNode(List<String> nodes, String? label) {
    if (label == null || label.isEmpty) {
      return;
    }
    if (nodes.isEmpty || nodes.last != label) {
      nodes.add(label);
    }
  }

  void appendRouteCheckpoint(
    List<RuntimeGraphCheckpoint> checkpoints,
    String? label,
    RuntimeEventEnvelope event, {
    String? detailLabel,
  }) {
    if (label == null || label.isEmpty) {
      return;
    }
    final clockLabel = formatRuntimeClock(event.timestamp);
    final previous = checkpoints.isEmpty ? null : checkpoints.last;
    if (previous != null &&
        previous.label == label &&
        previous.sourceEventKind == event.eventKind) {
      return;
    }
    checkpoints.add(
      RuntimeGraphCheckpoint(
        clockLabel: clockLabel,
        label: label,
        sourceEventKind: event.eventKind,
        detailLabel: detailLabel,
      ),
    );
  }

  void appendObservedNode(String? label) {
    if (label == null || label.isEmpty || observedNodes.contains(label)) {
      return;
    }
    observedNodes.add(label);
  }

  void appendTransitionEdge(String? label) {
    if (label == null || label.isEmpty || transitionEdges.contains(label)) {
      return;
    }
    transitionEdges.add(label);
  }

  for (final event in runtimeEvents) {
    final payload = event.payload;
    if (event.eventKind == 'transition.fired') {
      final from = payload['from'];
      final to = payload['to'];
      final fromLabel = from?.toString();
      final toLabel = to?.toString();
      appendUniqueNode(phaseRouteNodes, fromLabel);
      appendUniqueNode(phaseRouteNodes, toLabel);
      appendRouteCheckpoint(phaseCheckpoints, fromLabel, event);
      appendRouteCheckpoint(phaseCheckpoints, toLabel, event);
      if (fromLabel != null && toLabel != null) {
        final edgeLabel = '$fromLabel -> $toLabel';
        appendTransitionEdge(edgeLabel);
        appendRouteCheckpoint(
          edgeCheckpoints,
          edgeLabel,
          event,
          detailLabel: edgeLabel,
        );
      }
      continue;
    }

    if (event.eventKind == 'state.changed') {
      final phase = payload['phase'];
      final phaseLabel = phase == null ? null : 'phase=$phase';
      appendObservedNode(phaseLabel);
      continue;
    }

    if (event.eventKind == 'unit.entered' ||
        event.eventKind == 'unit.exited' ||
        event.eventKind == 'unit.test.started' ||
        event.eventKind == 'unit.test.finished' ||
        event.eventKind == 'compile.started' ||
        event.eventKind == 'compile.finished' ||
        event.eventKind == 'compile.failed' ||
        event.eventKind == 'run.started' ||
        event.eventKind == 'run.finished' ||
        event.eventKind == 'run.failed') {
      appendUniqueNode(eventRouteNodes, event.eventKind);
      final detailLabel = runtimePayloadSummary(payload);
      appendRouteCheckpoint(
        eventCheckpoints,
        event.eventKind,
        event,
        detailLabel: detailLabel,
      );
      appendObservedNode(detailLabel);
      continue;
    }

    if (event.eventKind == 'thread.spawned') {
      appendObservedNode(runtimePayloadSummary(payload));
      continue;
    }

    if (event.eventKind == 'log.emitted' ||
        event.eventKind == 'diagnostic.emitted') {
      appendObservedNode(runtimePayloadSummary(payload));
      continue;
    }

    appendObservedNode(runtimeEventDetailLabel(event));
  }

  final routeNodes = <String>[
    ...phaseRouteNodes,
    ...eventRouteNodes.where((node) => !phaseRouteNodes.contains(node)),
  ];
  final routeCheckpoints = <RuntimeGraphCheckpoint>[
    ...phaseCheckpoints,
    ...eventCheckpoints,
  ];
  final nodeDetails = routeNodes
      .map(
        (label) => summarizeRuntimeGraphNodeDetail(
          label,
          transitionEdges,
          routeCheckpoints
              .where((checkpoint) => checkpoint.label == label)
              .toList(growable: false),
        ),
      )
      .whereType<RuntimeGraphNodeDetail>()
      .toList(growable: false);
  final edgeDetails = transitionEdges
      .map(
        (label) => summarizeRuntimeGraphEdgeDetail(
          label,
          edgeCheckpoints
              .where((checkpoint) => checkpoint.label == label)
              .toList(growable: false),
        ),
      )
      .whereType<RuntimeGraphEdgeDetail>()
      .toList(growable: false);
  final terminalNode = routeNodes.isNotEmpty
      ? routeNodes.last
      : runtimeEvents.last.eventKind;
  final routeTraceLabel = routeNodes.isEmpty ? null : routeNodes.join(' -> ');
  final observedDigestLabel = observedNodes.isEmpty
      ? null
      : observedNodes.join(' · ');
  return RuntimeGraphSummary(
    routeCheckpoints: routeCheckpoints,
    routeNodes: routeNodes,
    nodeDetails: nodeDetails,
    transitionEdges: transitionEdges,
    edgeDetails: edgeDetails,
    observedNodes: observedNodes,
    terminalNode: terminalNode,
    routeTraceLabel: routeTraceLabel,
    observedDigestLabel: observedDigestLabel,
    summarySentence:
        '${routeNodes.length} node(s) / ${transitionEdges.length} explicit edge(s) derived from ${runtimeEvents.length} runtime event(s). Terminal node $terminalNode.',
  );
}

RuntimeGraphNodeDetail? summarizeRuntimeGraphNodeDetail(
  String label,
  List<String> transitionEdges,
  List<RuntimeGraphCheckpoint> checkpoints,
) {
  if (label.isEmpty || checkpoints.isEmpty) {
    return null;
  }
  final sourceEventKinds = checkpoints
      .map((checkpoint) => checkpoint.sourceEventKind)
      .toList(growable: false);
  final uniqueSourceEventKinds = sourceEventKinds.toSet().toList(
    growable: false,
  );
  final detailLabels = checkpoints
      .map((checkpoint) => checkpoint.detailLabel)
      .whereType<String>()
      .toSet()
      .toList(growable: false);
  final timelineParts = <String>[];
  for (final eventKind in sourceEventKinds) {
    if (timelineParts.isEmpty || timelineParts.last != eventKind) {
      timelineParts.add(eventKind);
    }
  }
  final filterTokens = <String>[
    'node=$label',
    ...uniqueSourceEventKinds.map((eventKind) => 'event=$eventKind'),
    ...detailLabels.take(2).map((detailLabel) => 'detail=$detailLabel'),
  ];
  final inboundEdges = transitionEdges
      .where((edge) => edge.endsWith(' -> $label'))
      .toList(growable: false);
  final outboundEdges = transitionEdges
      .where((edge) => edge.startsWith('$label -> '))
      .toList(growable: false);
  final relationParts = <String>[
    if (inboundEdges.isNotEmpty) 'in ${inboundEdges.join(', ')}',
    if (outboundEdges.isNotEmpty) 'out ${outboundEdges.join(', ')}',
  ];
  return RuntimeGraphNodeDetail(
    label: label,
    checkpointCount: checkpoints.length,
    windowLabel:
        '${checkpoints.first.clockLabel} -> ${checkpoints.last.clockLabel}',
    sourceEventKinds: uniqueSourceEventKinds,
    detailLabels: detailLabels,
    filterTokens: filterTokens,
    filterLabel: filterTokens.join(' · '),
    timelineLabel: timelineParts.isEmpty ? null : timelineParts.join(' -> '),
    timelineCheckpoints: checkpoints,
    inboundEdges: inboundEdges,
    outboundEdges: outboundEdges,
    relationLabel: relationParts.isEmpty ? null : relationParts.join(' · '),
  );
}

RuntimeGraphEdgeDetail? summarizeRuntimeGraphEdgeDetail(
  String label,
  List<RuntimeGraphCheckpoint> checkpoints,
) {
  if (label.isEmpty || checkpoints.isEmpty) {
    return null;
  }
  final sourceEventKinds = checkpoints
      .map((checkpoint) => checkpoint.sourceEventKind)
      .toList(growable: false);
  final timelineParts = <String>[];
  for (final eventKind in sourceEventKinds) {
    if (timelineParts.isEmpty || timelineParts.last != eventKind) {
      timelineParts.add(eventKind);
    }
  }
  final filterTokens = <String>[
    'edge=$label',
    ...sourceEventKinds.toSet().map((eventKind) => 'event=$eventKind'),
  ];
  return RuntimeGraphEdgeDetail(
    label: label,
    checkpointCount: checkpoints.length,
    windowLabel:
        '${checkpoints.first.clockLabel} -> ${checkpoints.last.clockLabel}',
    filterTokens: filterTokens,
    filterLabel: filterTokens.join(' · '),
    timelineLabel: timelineParts.isEmpty ? null : timelineParts.join(' -> '),
    timelineCheckpoints: checkpoints,
  );
}

List<RuntimeDebugLaneSummary> summarizeRuntimeDebugLanes(
  List<RuntimeEventEnvelope> runtimeEvents,
) {
  final debugFamilies = <String>['thread', 'unit.test', 'log'];
  return debugFamilies
      .map(
        (family) => summarizeRuntimeDebugLane(
          family,
          runtimeEvents
              .where((event) => runtimeEventFamily(event.eventKind) == family)
              .toList(growable: false),
        ),
      )
      .whereType<RuntimeDebugLaneSummary>()
      .toList(growable: false);
}

RuntimeDebugLaneSummary? summarizeRuntimeDebugLane(
  String family,
  List<RuntimeEventEnvelope> events,
) {
  if (events.isEmpty) {
    return null;
  }
  final latest = events.last;
  final start = events.first.timestamp;
  final end = latest.timestamp;
  final checkpoints = events
      .map(
        (event) => RuntimeDebugLaneCheckpoint(
          clockLabel: formatRuntimeClock(event.timestamp),
          eventKind: event.eventKind,
          detailLabel: runtimePayloadSummary(event.payload),
        ),
      )
      .toList(growable: false);
  final traceParts = <String>[];
  for (final checkpoint in checkpoints) {
    if (traceParts.isEmpty || traceParts.last != checkpoint.eventKind) {
      traceParts.add(checkpoint.eventKind);
    }
  }
  final traceLabel = traceParts.isEmpty ? null : traceParts.join(' -> ');

  switch (family) {
    case 'thread':
      final threadIds = events
          .map((event) => event.payload['thread_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      final filterTokens = <String>[
        'family=thread',
        ...threadIds.map((threadId) => 'thread_id=$threadId'),
      ];
      return RuntimeDebugLaneSummary(
        family: family,
        title: 'Thread Lane',
        statusLabel: 'spawned thread lane',
        eventCount: events.length,
        windowLabel:
            '${formatRuntimeClock(start)} -> ${formatRuntimeClock(end)}',
        latestEventKind: latest.eventKind,
        detailLabel: threadIds.isEmpty ? null : threadIds.join(', '),
        digestLabel: threadIds.isEmpty
            ? 'threads ${events.length} event(s)'
            : 'threads ${threadIds.join(', ')}',
        filterTokens: filterTokens,
        filterLabel: filterTokens.join(' · '),
        traceLabel: traceLabel,
        checkpoints: checkpoints,
        accent: RuntimeAccent.thread,
      );
    case 'unit.test':
      final testNames = events
          .map((event) => event.payload['test_name']?.toString())
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      final latestStatus = runtimeEventStatus(latest.eventKind);
      final statusLabel = latestStatus == 'finished'
          ? 'completed test lane'
          : latestStatus == 'started'
          ? 'active test lane'
          : 'observed test lane';
      final filterTokens = <String>[
        'family=unit.test',
        ...testNames.map((testName) => 'test_name=$testName'),
      ];
      return RuntimeDebugLaneSummary(
        family: family,
        title: 'Test Lane',
        statusLabel: statusLabel,
        eventCount: events.length,
        windowLabel:
            '${formatRuntimeClock(start)} -> ${formatRuntimeClock(end)}',
        latestEventKind: latest.eventKind,
        detailLabel: testNames.isEmpty ? null : testNames.join(', '),
        digestLabel: testNames.isEmpty
            ? 'tests ${events.length} event(s)'
            : 'tests ${testNames.join(', ')}',
        filterTokens: filterTokens,
        filterLabel: filterTokens.join(' · '),
        traceLabel: traceLabel,
        checkpoints: checkpoints,
        accent: RuntimeAccent.test,
      );
    case 'log':
      final streams = events
          .map((event) => event.payload['stream']?.toString())
          .whereType<String>()
          .toSet()
          .toList(growable: false);
      final latestMessage = latest.payload['message']?.toString();
      final detailLabel = [
        if (streams.isNotEmpty) streams.join(', '),
        if (latestMessage != null && latestMessage.isNotEmpty) latestMessage,
      ].join(' · ');
      final filterTokens = <String>[
        'family=log',
        ...streams.map((stream) => 'stream=$stream'),
      ];
      return RuntimeDebugLaneSummary(
        family: family,
        title: 'Log Lane',
        statusLabel: 'streaming log lane',
        eventCount: events.length,
        windowLabel:
            '${formatRuntimeClock(start)} -> ${formatRuntimeClock(end)}',
        latestEventKind: latest.eventKind,
        detailLabel: detailLabel.isEmpty ? null : detailLabel,
        digestLabel: streams.isEmpty
            ? 'logs ${events.length} event(s)'
            : 'logs ${streams.join(', ')}',
        filterTokens: filterTokens,
        filterLabel: filterTokens.join(' · '),
        traceLabel: traceLabel,
        checkpoints: checkpoints,
        accent: RuntimeAccent.log,
      );
    default:
      return null;
  }
}

String? summarizeRuntimeDebugDigest(List<RuntimeDebugLaneSummary> debugLanes) {
  if (debugLanes.isEmpty) {
    return null;
  }
  return debugLanes.map((lane) => lane.digestLabel).join(' · ');
}

String formatRuntimeClock(DateTime timestamp) {
  final utc = timestamp.toUtc();
  final hours = utc.hour.toString().padLeft(2, '0');
  final minutes = utc.minute.toString().padLeft(2, '0');
  final seconds = utc.second.toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String formatRuntimeEvent(RuntimeEventEnvelope event) {
  final detailLabel = runtimeEventDetailLabel(event);
  final suffix = detailLabel == null ? '' : ' · $detailLabel';
  return '[runtime #${event.sequence}] ${formatRuntimeClock(event.timestamp)} ${event.eventKind} · ${event.origin}$suffix';
}

String? runtimeEventDetailLabel(RuntimeEventEnvelope event) {
  final payloadSummary = runtimePayloadSummary(event.payload);
  if (isKnownRuntimeEventKind(event.eventKind)) {
    return payloadSummary;
  }
  final unsupported = 'unsupported event kind ${event.eventKind}';
  if (payloadSummary == null || payloadSummary.isEmpty) {
    return unsupported;
  }
  return '$unsupported · $payloadSummary';
}

String runtimePayloadSuffix(Map<String, Object?> payload) {
  final summary = runtimePayloadSummary(payload);
  if (summary == null || summary.isEmpty) {
    return '';
  }
  return ' · $summary';
}

String? runtimePayloadSummary(Map<String, Object?> payload) {
  if (payload.isEmpty) {
    return null;
  }
  if (payload case {'test_name': final Object? testName}) {
    return 'test_name=$testName';
  }
  if (payload case {'unit_id': final Object? unitId}) {
    return 'unit_id=$unitId';
  }
  if (payload case {'thread_id': final Object? threadId}) {
    return 'thread_id=$threadId';
  }
  if (payload case {'from': final Object? from, 'to': final Object? to}) {
    return '$from -> $to';
  }
  if (payload case {'phase': final Object? phase}) {
    return 'phase=$phase';
  }
  if (payload case {'stream': final Object? stream}) {
    return 'stream=$stream';
  }
  if (payload case {'success': final bool success}) {
    return success ? 'success' : 'failure';
  }
  if (payload case {'intent': final String intent}) {
    return 'intent=$intent';
  }
  if (payload case {'code': final Object? code}) {
    return 'code=$code';
  }
  final firstEntry = payload.entries.first;
  return '${firstEntry.key}=${firstEntry.value}';
}

String runtimeEventStatus(String eventKind) {
  final separator = eventKind.lastIndexOf('.');
  if (separator <= 0 || separator == eventKind.length - 1) {
    return 'observed';
  }
  return eventKind.substring(separator + 1);
}
