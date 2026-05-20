import '../../runtime/runtime_output_channels.dart';
import '../../foundation/foundation.dart';
import 'semantic_snapshot_provider.dart';

enum SemanticSnapshotTelemetryEventKind {
  renameSafety,
  codeActionDiscovery,
  codeActionApply,
}

extension SemanticSnapshotTelemetryEventKindX
    on SemanticSnapshotTelemetryEventKind {
  String get wireValue => switch (this) {
    SemanticSnapshotTelemetryEventKind.renameSafety => 'rename-safety',
    SemanticSnapshotTelemetryEventKind.codeActionDiscovery =>
      'code-action-discovery',
    SemanticSnapshotTelemetryEventKind.codeActionApply => 'code-action-apply',
  };
}

SemanticSnapshotTelemetryEventKind? _semanticSnapshotTelemetryEventKindFromWire(
  Object? value,
) {
  return switch (value) {
    'rename-safety' => SemanticSnapshotTelemetryEventKind.renameSafety,
    'code-action-discovery' =>
      SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
    'code-action-apply' => SemanticSnapshotTelemetryEventKind.codeActionApply,
    _ => null,
  };
}

enum SemanticSnapshotPanelEventTarget { problems, refactor }

extension SemanticSnapshotPanelEventTargetX
    on SemanticSnapshotPanelEventTarget {
  String get wireValue => switch (this) {
    SemanticSnapshotPanelEventTarget.problems => 'problems',
    SemanticSnapshotPanelEventTarget.refactor => 'refactor',
  };
}

SemanticSnapshotPanelEventTarget? _semanticSnapshotPanelEventTargetFromWire(
  Object? value,
) {
  return switch (value) {
    'problems' => SemanticSnapshotPanelEventTarget.problems,
    'refactor' => SemanticSnapshotPanelEventTarget.refactor,
    _ => null,
  };
}

typedef SemanticSnapshotPanelEventHandler =
    void Function(SemanticSnapshotPanelEvent event);

class SemanticSnapshotPanelEvent {
  const SemanticSnapshotPanelEvent({
    required this.target,
    required this.kind,
    required this.documentId,
    required this.message,
    required this.payload,
    required this.timestamp,
  });

  factory SemanticSnapshotPanelEvent.fromJson(Map<String, Object?> json) {
    return SemanticSnapshotPanelEvent(
      target:
          _semanticSnapshotPanelEventTargetFromWire(json['target']) ??
          SemanticSnapshotPanelEventTarget.problems,
      kind:
          _semanticSnapshotTelemetryEventKindFromWire(json['kind']) ??
          SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
      documentId: json['documentId'] as String? ?? '',
      message: json['message'] as String? ?? '',
      payload: _payloadFromJson(json['payload']),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final SemanticSnapshotPanelEventTarget target;
  final SemanticSnapshotTelemetryEventKind kind;
  final String documentId;
  final String message;
  final Map<String, Object?> payload;
  final DateTime timestamp;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'target': target.wireValue,
      'kind': kind.wireValue,
      'documentId': documentId,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      'payload': payload,
    };
  }
}

class SemanticSnapshotPanelEventSink {
  const SemanticSnapshotPanelEventSink({
    required this.id,
    required this.target,
    required this.handle,
    this.acceptedKinds = const <SemanticSnapshotTelemetryEventKind>[],
  });

  factory SemanticSnapshotPanelEventSink.problems({
    required SemanticSnapshotPanelEventHandler handle,
  }) {
    return SemanticSnapshotPanelEventSink(
      id: 'problems-panel',
      target: SemanticSnapshotPanelEventTarget.problems,
      acceptedKinds: const <SemanticSnapshotTelemetryEventKind>[
        SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
        SemanticSnapshotTelemetryEventKind.codeActionApply,
      ],
      handle: handle,
    );
  }

  factory SemanticSnapshotPanelEventSink.refactor({
    required SemanticSnapshotPanelEventHandler handle,
  }) {
    return SemanticSnapshotPanelEventSink(
      id: 'refactor-panel',
      target: SemanticSnapshotPanelEventTarget.refactor,
      acceptedKinds: const <SemanticSnapshotTelemetryEventKind>[
        SemanticSnapshotTelemetryEventKind.renameSafety,
      ],
      handle: handle,
    );
  }

  final String id;
  final SemanticSnapshotPanelEventTarget target;
  final List<SemanticSnapshotTelemetryEventKind> acceptedKinds;
  final SemanticSnapshotPanelEventHandler handle;

  bool accepts(SemanticSnapshotPanelEvent event) {
    return event.target == target &&
        (acceptedKinds.isEmpty || acceptedKinds.contains(event.kind));
  }
}

class SemanticSnapshotEventDispatchResult {
  const SemanticSnapshotEventDispatchResult({
    required this.panelEvents,
    required this.deliveredSinkIds,
    required this.skippedSinkIds,
  });

  final List<SemanticSnapshotPanelEvent> panelEvents;
  final List<String> deliveredSinkIds;
  final List<String> skippedSinkIds;

  bool get delivered => deliveredSinkIds.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'delivered': delivered,
      'panelEvents': panelEvents
          .map((event) => event.toJson())
          .toList(growable: false),
      'deliveredSinkIds': deliveredSinkIds,
      'skippedSinkIds': skippedSinkIds,
    };
  }
}

class SemanticSnapshotPanelEventDispatcher {
  const SemanticSnapshotPanelEventDispatcher({
    this.sinks = const <SemanticSnapshotPanelEventSink>[],
  });

  final List<SemanticSnapshotPanelEventSink> sinks;

  SemanticSnapshotEventDispatchResult dispatch(RuntimeOutputEvent event) {
    final panelEvent = panelEventFor(event);
    if (panelEvent == null) {
      return const SemanticSnapshotEventDispatchResult(
        panelEvents: <SemanticSnapshotPanelEvent>[],
        deliveredSinkIds: <String>[],
        skippedSinkIds: <String>[],
      );
    }
    final delivered = <String>[];
    final skipped = <String>[];
    for (final sink in sinks) {
      if (sink.accepts(panelEvent)) {
        sink.handle(panelEvent);
        delivered.add(sink.id);
      } else {
        skipped.add(sink.id);
      }
    }
    return SemanticSnapshotEventDispatchResult(
      panelEvents: <SemanticSnapshotPanelEvent>[panelEvent],
      deliveredSinkIds: List.unmodifiable(delivered),
      skippedSinkIds: List.unmodifiable(skipped),
    );
  }

  SemanticSnapshotPanelEvent? panelEventFor(RuntimeOutputEvent event) {
    final kind = _semanticSnapshotTelemetryEventKindFromWire(
      event.metadata['semanticEventKind'],
    );
    if (kind == null) {
      return null;
    }
    final target = switch (kind) {
      SemanticSnapshotTelemetryEventKind.renameSafety =>
        SemanticSnapshotPanelEventTarget.refactor,
      SemanticSnapshotTelemetryEventKind.codeActionDiscovery ||
      SemanticSnapshotTelemetryEventKind.codeActionApply =>
        SemanticSnapshotPanelEventTarget.problems,
    };
    final payload = event.metadata['payload'];
    return SemanticSnapshotPanelEvent(
      target: target,
      kind: kind,
      documentId: event.metadata['documentId'] as String? ?? '',
      message: event.message,
      payload: payload is Map<String, Object?>
          ? payload
          : payload is Map
          ? payload.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
      timestamp: event.timestamp,
    );
  }
}

class SemanticSnapshotPanelEventState {
  const SemanticSnapshotPanelEventState({
    required this.target,
    this.events = const <SemanticSnapshotPanelEvent>[],
    this.revision = 0,
    this.updatedAt,
  });

  factory SemanticSnapshotPanelEventState.empty(
    SemanticSnapshotPanelEventTarget target,
  ) {
    return SemanticSnapshotPanelEventState(target: target);
  }

  factory SemanticSnapshotPanelEventState.fromJson(Map<String, Object?> json) {
    final target =
        _semanticSnapshotPanelEventTargetFromWire(json['target']) ??
        SemanticSnapshotPanelEventTarget.problems;
    final events = <SemanticSnapshotPanelEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is List) {
      for (final rawEvent in rawEvents) {
        if (rawEvent is Map) {
          events.add(
            SemanticSnapshotPanelEvent.fromJson(
              Map<String, Object?>.from(rawEvent),
            ),
          );
        }
      }
    }
    return SemanticSnapshotPanelEventState(
      target: target,
      events: List.unmodifiable(events),
      revision: json['revision'] as int? ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final SemanticSnapshotPanelEventTarget target;
  final List<SemanticSnapshotPanelEvent> events;
  final int revision;
  final DateTime? updatedAt;

  SemanticSnapshotPanelEventState record(
    SemanticSnapshotPanelEvent event, {
    int maxEvents = 50,
    DateTime? updatedAt,
  }) {
    return SemanticSnapshotPanelEventState(
      target: target,
      events: <SemanticSnapshotPanelEvent>[
        event,
        ...events.where(
          (candidate) =>
              candidate.documentId != event.documentId ||
              candidate.kind != event.kind ||
              candidate.timestamp != event.timestamp,
        ),
      ].take(maxEvents).toList(growable: false),
      revision: revision + 1,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'target': target.wireValue,
      'revision': revision,
      'events': events.map((event) => event.toJson()).toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class SemanticSnapshotPanelEventStateController {
  SemanticSnapshotPanelEventStateController({
    Iterable<SemanticSnapshotPanelEventTarget> targets =
        SemanticSnapshotPanelEventTarget.values,
  }) : _states =
           <SemanticSnapshotPanelEventTarget, SemanticSnapshotPanelEventState>{
             for (final target in targets)
               target: SemanticSnapshotPanelEventState.empty(target),
           };

  final Map<SemanticSnapshotPanelEventTarget, SemanticSnapshotPanelEventState>
  _states;

  SemanticSnapshotPanelEventState stateFor(
    SemanticSnapshotPanelEventTarget target,
  ) {
    return _states[target] ?? SemanticSnapshotPanelEventState.empty(target);
  }

  SemanticSnapshotPanelEventSink sinkFor(
    SemanticSnapshotPanelEventTarget target,
  ) {
    return SemanticSnapshotPanelEventSink(
      id: '${target.wireValue}-state-store',
      target: target,
      handle: handle,
    );
  }

  void handle(SemanticSnapshotPanelEvent event) {
    _states[event.target] = stateFor(event.target).record(event);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      for (final entry in _states.entries)
        entry.key.wireValue: entry.value.toJson(),
    };
  }
}

class SemanticSnapshotPanelEventStore {
  SemanticSnapshotPanelEventStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'service.semantic-snapshot.panel-events',
             layer: 'service',
             stateFamily: 'semantic-snapshot-panel-events',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const SemanticSnapshotPanelEventStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'service.semantic-snapshot.panel-events';

  final FoundationDataStoreOwner _owner;

  Future<SemanticSnapshotPanelEventState> readState({
    required String workspaceId,
    required SemanticSnapshotPanelEventTarget target,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _keyFor(target),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return SemanticSnapshotPanelEventState.empty(target);
    }
    final state = SemanticSnapshotPanelEventState.fromJson(value);
    return state.target == target
        ? state
        : SemanticSnapshotPanelEventState(
            target: target,
            events: state.events,
            revision: state.revision,
            updatedAt: state.updatedAt,
          );
  }

  Future<SemanticSnapshotPanelEventState> recordEvent({
    required String workspaceId,
    required SemanticSnapshotPanelEvent event,
    int maxEvents = 50,
  }) async {
    final next = (await readState(
      workspaceId: workspaceId,
      target: event.target,
    )).record(event, maxEvents: maxEvents, updatedAt: event.timestamp);
    await saveState(workspaceId: workspaceId, state: next);
    return next;
  }

  Future<SemanticSnapshotPanelEventState> saveState({
    required String workspaceId,
    required SemanticSnapshotPanelEventState state,
  }) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _keyFor(state.target),
      value: state.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    return state;
  }

  Future<bool> clearState({
    required String workspaceId,
    required SemanticSnapshotPanelEventTarget target,
  }) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _keyFor(target),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  String _keyFor(SemanticSnapshotPanelEventTarget target) {
    return 'panel-events-${target.wireValue}';
  }
}

class SemanticSnapshotEventBridge {
  const SemanticSnapshotEventBridge({
    this.channelId = 'language.semantic',
    this.label = 'Language Semantic Events',
  });

  final String channelId;
  final String label;

  RuntimeOutputEvent renameSafetyEvent({
    required String documentId,
    required SemanticSnapshotRenameSafetyResult result,
    required DateTime timestamp,
  }) {
    return _event(
      kind: SemanticSnapshotTelemetryEventKind.renameSafety,
      documentId: documentId,
      timestamp: timestamp,
      message: result.safe
          ? 'Rename ${result.targetName} to ${result.newName} is safe.'
          : 'Rename ${result.targetName} to ${result.newName} is blocked.',
      payload: result.toJson(),
    );
  }

  RuntimeOutputEvent codeActionDiscoveryEvent({
    required String documentId,
    required SemanticSnapshotCodeActionResult result,
    required DateTime timestamp,
  }) {
    return _event(
      kind: SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
      documentId: documentId,
      timestamp: timestamp,
      message: result.available
          ? 'Discovered ${result.actions.length} code action fact(s) for ${result.diagnosticCode}.'
          : 'No code action facts are available for ${result.diagnosticCode}.',
      payload: result.toJson(),
    );
  }

  RuntimeOutputEvent codeActionApplyEvent({
    required String documentId,
    required SemanticSnapshotCodeActionApplyResult result,
    required DateTime timestamp,
  }) {
    return _event(
      kind: SemanticSnapshotTelemetryEventKind.codeActionApply,
      documentId: documentId,
      timestamp: timestamp,
      message: result.successful
          ? 'Applied code action ${result.actionId}.'
          : 'Code action ${result.actionId} finished with ${result.status.wireValue}.',
      payload: result.toJson(),
    );
  }

  RuntimeOutputEvent _event({
    required SemanticSnapshotTelemetryEventKind kind,
    required String documentId,
    required DateTime timestamp,
    required String message,
    required Map<String, Object?> payload,
  }) {
    return RuntimeOutputEvent(
      channelId: channelId,
      label: label,
      kind: RuntimeOutputChannelKind.languageService,
      message: message,
      timestamp: timestamp.toUtc(),
      metadata: <String, Object?>{
        'semanticEventKind': kind.wireValue,
        'documentId': documentId,
        'payload': payload,
      },
    );
  }
}

Map<String, Object?> _payloadFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }
  return const <String, Object?>{};
}
