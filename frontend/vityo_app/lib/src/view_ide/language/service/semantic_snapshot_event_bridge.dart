import '../../runtime/runtime_output_channels.dart';
import '../../foundation/foundation.dart';
import 'semantic_snapshot_provider.dart';

enum SemanticSnapshotTelemetryEventKind {
  renameSafety,
  codeActionDiscovery,
  codeActionApply,
  diagnosticsSnapshot,
  semanticTokens,
}

extension SemanticSnapshotTelemetryEventKindX
    on SemanticSnapshotTelemetryEventKind {
  String get wireValue => switch (this) {
    SemanticSnapshotTelemetryEventKind.renameSafety => 'rename-safety',
    SemanticSnapshotTelemetryEventKind.codeActionDiscovery =>
      'code-action-discovery',
    SemanticSnapshotTelemetryEventKind.codeActionApply => 'code-action-apply',
    SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot =>
      'diagnostics-snapshot',
    SemanticSnapshotTelemetryEventKind.semanticTokens => 'semantic-tokens',
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
    'diagnostics-snapshot' =>
      SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot,
    'semantic-tokens' => SemanticSnapshotTelemetryEventKind.semanticTokens,
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
        SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot,
        SemanticSnapshotTelemetryEventKind.semanticTokens,
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
      SemanticSnapshotTelemetryEventKind.codeActionApply ||
      SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot ||
      SemanticSnapshotTelemetryEventKind.semanticTokens =>
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

class SemanticSnapshotPanelEventViewItem {
  const SemanticSnapshotPanelEventViewItem({
    required this.id,
    required this.target,
    required this.kind,
    required this.documentId,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
    this.actionLabel = '',
    this.payload = const <String, Object?>{},
  });

  factory SemanticSnapshotPanelEventViewItem.fromEvent(
    SemanticSnapshotPanelEvent event,
  ) {
    final title = switch (event.kind) {
      SemanticSnapshotTelemetryEventKind.renameSafety => 'Rename safety',
      SemanticSnapshotTelemetryEventKind.codeActionDiscovery =>
        'Code actions available',
      SemanticSnapshotTelemetryEventKind.codeActionApply =>
        'Code action result',
      SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot =>
        'Diagnostics snapshot',
      SemanticSnapshotTelemetryEventKind.semanticTokens => 'Semantic tokens',
    };
    return SemanticSnapshotPanelEventViewItem(
      id: '${event.target.wireValue}:${event.kind.wireValue}:${event.documentId}:${event.timestamp.toIso8601String()}',
      target: event.target,
      kind: event.kind,
      documentId: event.documentId,
      title: title,
      message: event.message,
      severity: _semanticPanelSeverity(event),
      timestamp: event.timestamp,
      actionLabel: _semanticPanelActionLabel(event),
      payload: event.payload,
    );
  }

  final String id;
  final SemanticSnapshotPanelEventTarget target;
  final SemanticSnapshotTelemetryEventKind kind;
  final String documentId;
  final String title;
  final String message;
  final String severity;
  final DateTime timestamp;
  final String actionLabel;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'target': target.wireValue,
      'kind': kind.wireValue,
      'documentId': documentId,
      'title': title,
      'message': message,
      'severity': severity,
      'timestamp': timestamp.toIso8601String(),
      if (actionLabel.isNotEmpty) 'actionLabel': actionLabel,
      if (payload.isNotEmpty) 'payload': payload,
    };
  }
}

class SemanticSnapshotPanelViewModel {
  const SemanticSnapshotPanelViewModel({
    required this.target,
    required this.title,
    required this.revision,
    required this.items,
    this.updatedAt,
  });

  factory SemanticSnapshotPanelViewModel.fromState(
    SemanticSnapshotPanelEventState state,
  ) {
    final items = state.events
        .map(SemanticSnapshotPanelEventViewItem.fromEvent)
        .toList(growable: false);
    return SemanticSnapshotPanelViewModel(
      target: state.target,
      title: switch (state.target) {
        SemanticSnapshotPanelEventTarget.problems => 'Problems',
        SemanticSnapshotPanelEventTarget.refactor => 'Refactor',
      },
      revision: state.revision,
      items: List.unmodifiable(items),
      updatedAt: state.updatedAt,
    );
  }

  final SemanticSnapshotPanelEventTarget target;
  final String title;
  final int revision;
  final List<SemanticSnapshotPanelEventViewItem> items;
  final DateTime? updatedAt;

  bool get empty => items.isEmpty;
  int get itemCount => items.length;

  int get codeActionCount {
    return items
        .where(
          (item) =>
              item.kind == SemanticSnapshotTelemetryEventKind.codeActionApply ||
              item.kind ==
                  SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
        )
        .length;
  }

  int get renameSafetyCount {
    return items
        .where(
          (item) =>
              item.kind == SemanticSnapshotTelemetryEventKind.renameSafety,
        )
        .length;
  }

  int get diagnosticEventCount {
    return items
        .where(
          (item) =>
              item.kind ==
              SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot,
        )
        .length;
  }

  int get semanticTokenEventCount {
    return items
        .where(
          (item) =>
              item.kind == SemanticSnapshotTelemetryEventKind.semanticTokens,
        )
        .length;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'target': target.wireValue,
      'title': title,
      'revision': revision,
      'empty': empty,
      'itemCount': itemCount,
      'codeActionCount': codeActionCount,
      'renameSafetyCount': renameSafetyCount,
      'diagnosticEventCount': diagnosticEventCount,
      'semanticTokenEventCount': semanticTokenEventCount,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }
}

String _semanticPanelSeverity(SemanticSnapshotPanelEvent event) {
  return switch (event.kind) {
    SemanticSnapshotTelemetryEventKind.renameSafety =>
      event.payload['safe'] == false ? 'warning' : 'success',
    SemanticSnapshotTelemetryEventKind.codeActionDiscovery => 'info',
    SemanticSnapshotTelemetryEventKind.codeActionApply =>
      event.payload['status'] == 'applied' ? 'success' : 'warning',
    SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot =>
      event.payload['hasErrors'] == true ||
              ((event.payload['diagnosticCount'] as int? ?? 0) > 0)
          ? 'warning'
          : 'success',
    SemanticSnapshotTelemetryEventKind.semanticTokens =>
      ((event.payload['semanticSpanCount'] as int? ?? 0) > 0)
          ? 'success'
          : 'info',
  };
}

String _semanticPanelActionLabel(SemanticSnapshotPanelEvent event) {
  final label = event.payload['label'];
  if (label is String && label.trim().isNotEmpty) {
    return label.trim();
  }
  final newName = event.payload['newName'];
  if (event.kind == SemanticSnapshotTelemetryEventKind.renameSafety &&
      newName is String &&
      newName.trim().isNotEmpty) {
    return 'Rename to ${newName.trim()}';
  }
  final actionCount = event.payload['actionCount'];
  if (event.kind == SemanticSnapshotTelemetryEventKind.codeActionDiscovery &&
      actionCount is int &&
      actionCount > 0) {
    return '$actionCount code action(s)';
  }
  final diagnosticCount = event.payload['diagnosticCount'];
  if (event.kind == SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot &&
      diagnosticCount is int) {
    return diagnosticCount > 0
        ? '$diagnosticCount diagnostic(s)'
        : 'No diagnostics';
  }
  final semanticSpanCount = event.payload['semanticSpanCount'];
  if (event.kind == SemanticSnapshotTelemetryEventKind.semanticTokens &&
      semanticSpanCount is int) {
    return semanticSpanCount > 0
        ? '$semanticSpanCount semantic token(s)'
        : 'No semantic tokens';
  }
  return '';
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

  void replaceState(SemanticSnapshotPanelEventState state) {
    _states[state.target] = state;
  }

  void replaceStates(Iterable<SemanticSnapshotPanelEventState> states) {
    for (final state in states) {
      replaceState(state);
    }
  }

  SemanticSnapshotPanelEventState recordEvent(
    SemanticSnapshotPanelEvent event, {
    int maxEvents = 50,
  }) {
    final next = stateFor(
      event.target,
    ).record(event, maxEvents: maxEvents, updatedAt: event.timestamp);
    replaceState(next);
    return next;
  }

  void handle(SemanticSnapshotPanelEvent event) {
    recordEvent(event);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      for (final entry in _states.entries)
        entry.key.wireValue: entry.value.toJson(),
    };
  }
}

class SemanticSnapshotPanelEventRetentionPolicy {
  const SemanticSnapshotPanelEventRetentionPolicy({
    this.maxEventsPerTarget = 50,
    this.maxEventAge = const Duration(days: 30),
  });

  final int maxEventsPerTarget;
  final Duration? maxEventAge;

  SemanticSnapshotPanelEventState apply(
    SemanticSnapshotPanelEventState state, {
    DateTime? now,
    int? maxEventsOverride,
  }) {
    final maxEvents = maxEventsOverride ?? maxEventsPerTarget;
    final normalizedMaxEvents = maxEvents <= 0 ? 50 : maxEvents;
    final cutoff = maxEventAge == null
        ? null
        : (now ?? DateTime.now().toUtc()).subtract(maxEventAge!);
    final retainedEvents = state.events
        .where((event) => cutoff == null || !event.timestamp.isBefore(cutoff))
        .take(normalizedMaxEvents)
        .toList(growable: false);
    return SemanticSnapshotPanelEventState(
      target: state.target,
      events: List.unmodifiable(retainedEvents),
      revision: state.revision,
      updatedAt: state.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxEventsPerTarget': maxEventsPerTarget,
      if (maxEventAge != null) 'maxEventAgeDays': maxEventAge!.inDays,
    };
  }
}

class SemanticSnapshotPanelEventStore {
  SemanticSnapshotPanelEventStore.fromDataStore({
    required FoundationDataStore dataStore,
    SemanticSnapshotPanelEventRetentionPolicy retentionPolicy =
        const SemanticSnapshotPanelEventRetentionPolicy(),
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
         retentionPolicy: retentionPolicy,
       );

  const SemanticSnapshotPanelEventStore({
    required FoundationDataStoreOwner owner,
    this.retentionPolicy = const SemanticSnapshotPanelEventRetentionPolicy(),
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'service.semantic-snapshot.panel-events';

  final FoundationDataStoreOwner _owner;
  final SemanticSnapshotPanelEventRetentionPolicy retentionPolicy;

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
    final normalizedState = state.target == target
        ? state
        : SemanticSnapshotPanelEventState(
            target: target,
            events: state.events,
            revision: state.revision,
            updatedAt: state.updatedAt,
          );
    return retentionPolicy.apply(normalizedState);
  }

  Future<SemanticSnapshotPanelEventState> recordEvent({
    required String workspaceId,
    required SemanticSnapshotPanelEvent event,
    int? maxEvents,
  }) async {
    final effectiveMaxEvents = maxEvents ?? retentionPolicy.maxEventsPerTarget;
    final recorded = (await readState(
      workspaceId: workspaceId,
      target: event.target,
    )).record(event, maxEvents: effectiveMaxEvents, updatedAt: event.timestamp);
    final next = retentionPolicy.apply(
      recorded,
      now: event.timestamp,
      maxEventsOverride: effectiveMaxEvents,
    );
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

  RuntimeOutputEvent diagnosticsSnapshotEvent({
    required String documentId,
    required String providerId,
    required int diagnosticCount,
    required bool hasErrors,
    required Map<String, int> severityCounts,
    required int documentCount,
    required int sourceCount,
    required DateTime timestamp,
    String message = '',
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    final normalizedMessage = message.trim().isNotEmpty
        ? message.trim()
        : 'Workspace diagnostics snapshot contains $diagnosticCount diagnostic(s).';
    return _event(
      kind: SemanticSnapshotTelemetryEventKind.diagnosticsSnapshot,
      documentId: documentId,
      timestamp: timestamp,
      message: normalizedMessage,
      payload: <String, Object?>{
        'providerId': providerId,
        'diagnosticCount': diagnosticCount,
        'hasErrors': hasErrors,
        'severityCounts': Map<String, int>.unmodifiable(severityCounts),
        'documentCount': documentCount,
        'sourceCount': sourceCount,
        ...payload,
      },
    );
  }

  RuntimeOutputEvent semanticTokensEvent({
    required String documentId,
    required int semanticSpanCount,
    required int semanticBlockCount,
    required int documentSymbolCount,
    required int inlayHintCount,
    required int diagnosticCount,
    required DateTime timestamp,
    String message = '',
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    final normalizedMessage = message.trim().isNotEmpty
        ? message.trim()
        : 'Semantic token snapshot contains $semanticSpanCount span(s).';
    return _event(
      kind: SemanticSnapshotTelemetryEventKind.semanticTokens,
      documentId: documentId,
      timestamp: timestamp,
      message: normalizedMessage,
      payload: <String, Object?>{
        'semanticSpanCount': semanticSpanCount,
        'semanticBlockCount': semanticBlockCount,
        'documentSymbolCount': documentSymbolCount,
        'inlayHintCount': inlayHintCount,
        'diagnosticCount': diagnosticCount,
        ...payload,
      },
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
