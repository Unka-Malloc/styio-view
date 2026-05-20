import '../../runtime/runtime_output_channels.dart';
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
