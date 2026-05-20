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
