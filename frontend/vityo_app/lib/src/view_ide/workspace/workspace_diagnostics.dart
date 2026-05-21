import '../foundation/foundation.dart';
import '../editor/document_state.dart';
import '../language/language_contract.dart';
import '../runtime/runtime.dart';
import '../toolchain/toolchain.dart';
import 'workspace_edit.dart';

class WorkspaceDiagnosticsRequest {
  const WorkspaceDiagnosticsRequest({
    required this.documentIds,
    this.activeDocumentId = '',
    this.documents = const <DocumentState>[],
  });

  final List<String> documentIds;
  final String activeDocumentId;
  final List<DocumentState> documents;
}

class WorkspaceDiagnosticsProducerExecutionPlan {
  const WorkspaceDiagnosticsProducerExecutionPlan({
    required this.providerId,
    required this.request,
    required this.definition,
    required this.executionPlan,
    required this.handoff,
    required this.binding,
  });

  factory WorkspaceDiagnosticsProducerExecutionPlan.nativeTool({
    required String providerId,
    required WorkspaceDiagnosticsRequest request,
    required String command,
    List<String> arguments = const <String>[],
    String? workingDirectory,
    String outputChannelId = '',
  }) {
    final definition = RuntimeTaskDefinition(
      id: 'diagnostics.$providerId',
      label: 'Diagnostics $providerId',
      kind: RuntimeTaskKind.toolchain,
      command: command,
      arguments: arguments,
      workingDirectory: workingDirectory,
      metadata: <String, Object?>{
        'diagnosticsProducer': true,
        'diagnosticsProviderId': providerId,
        'activeDocumentId': request.activeDocumentId,
        'documentIds': request.documentIds,
        'toolchainKind': ToolchainKind.staticAnalyzer.wireValue,
      },
    );
    final executionPlan = const RuntimeExecutionPlanner().plan(
      definition: definition,
    );
    final handoff = executionPlan.createHandoff(
      target: RuntimeExecutionHandoffTarget.toolchainManager,
      outputChannelId: outputChannelId.trim().isEmpty
          ? 'diagnostics.$providerId'
          : outputChannelId.trim(),
      metadata: <String, Object?>{
        'diagnosticsProducer': true,
        'diagnosticsProviderId': providerId,
      },
    );
    final binding = handoff.bind(
      outputKind: RuntimeOutputChannelKind.nativeTools,
      metadata: <String, Object?>{
        'diagnosticsProducer': true,
        'diagnosticsProviderId': providerId,
      },
    );
    return WorkspaceDiagnosticsProducerExecutionPlan(
      providerId: providerId,
      request: request,
      definition: definition,
      executionPlan: executionPlan,
      handoff: handoff,
      binding: binding,
    );
  }

  final String providerId;
  final WorkspaceDiagnosticsRequest request;
  final RuntimeTaskDefinition definition;
  final RuntimeExecutionPlan executionPlan;
  final RuntimeExecutionHandoff handoff;
  final RuntimeExecutionHandoffBinding binding;

  bool get ready => executionPlan.ready && handoff.ready && binding.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'ready': ready,
      'documentIds': request.documentIds,
      'activeDocumentId': request.activeDocumentId,
      'definition': definition.toJson(),
      'executionPlan': executionPlan.toJson(),
      'handoff': handoff.toJson(),
      'binding': binding.toJson(),
    };
  }
}

class WorkspaceDiagnosticsProducerLifecycleSnapshot {
  const WorkspaceDiagnosticsProducerLifecycleSnapshot({
    required this.providerId,
    required this.taskSnapshot,
    this.progress,
    this.cancellationRequested = false,
    this.message = '',
  });

  factory WorkspaceDiagnosticsProducerLifecycleSnapshot.fromTask({
    required String providerId,
    required RuntimeTaskSnapshot taskSnapshot,
    double? progress,
    bool cancellationRequested = false,
    String message = '',
  }) {
    final normalizedMessage = message.trim();
    return WorkspaceDiagnosticsProducerLifecycleSnapshot(
      providerId: providerId,
      taskSnapshot: taskSnapshot,
      progress: _normalizeDiagnosticsProducerProgress(progress),
      cancellationRequested: cancellationRequested,
      message: normalizedMessage.isEmpty
          ? taskSnapshot.statusMessage
          : normalizedMessage,
    );
  }

  final String providerId;
  final RuntimeTaskSnapshot taskSnapshot;
  final double? progress;
  final bool cancellationRequested;
  final String message;

  String get taskId => taskSnapshot.definition.id;
  RuntimeTaskStatus get status => taskSnapshot.status;
  bool get active => taskSnapshot.active;
  bool get terminal => taskSnapshot.terminal;
  bool get canCancel => active && !cancellationRequested;
  bool get hasProgress => progress != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'taskId': taskId,
      'status': status.wireValue,
      'active': active,
      'terminal': terminal,
      'canCancel': canCancel,
      'cancellationRequested': cancellationRequested,
      if (hasProgress) 'progress': progress,
      if (message.isNotEmpty) 'message': message,
      'task': taskSnapshot.toJson(),
    };
  }
}

class WorkspaceDiagnosticsProducerCancellationResult {
  const WorkspaceDiagnosticsProducerCancellationResult({
    required this.accepted,
    required this.processTerminated,
    required this.message,
    this.metadata = const <String, Object?>{},
  });

  const WorkspaceDiagnosticsProducerCancellationResult.accepted({
    bool processTerminated = false,
    String message = 'Diagnostics producer cancellation requested.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: true,
         processTerminated: processTerminated,
         message: message,
         metadata: metadata,
       );

  const WorkspaceDiagnosticsProducerCancellationResult.rejected({
    String message = 'Diagnostics producer cancellation was rejected.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         accepted: false,
         processTerminated: false,
         message: message,
         metadata: metadata,
       );

  final bool accepted;
  final bool processTerminated;
  final String message;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'accepted': accepted,
      'processTerminated': processTerminated,
      'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class WorkspaceDiagnosticsProducerCancellationRoute {
  const WorkspaceDiagnosticsProducerCancellationRoute({
    required this.providerId,
    required this.taskId,
    required this.managerId,
    required this.routeKind,
    required this.canCancel,
    required this.processHandleBound,
    required this.message,
    this.processHandleId = '',
    this.reason = '',
  });

  factory WorkspaceDiagnosticsProducerCancellationRoute.fromPlan({
    required WorkspaceDiagnosticsProducerExecutionPlan plan,
    required WorkspaceDiagnosticsProducerLifecycleSnapshot current,
    String processHandleId = '',
    String reason = '',
  }) {
    final handleId = processHandleId.trim();
    final routeKind = handleId.isEmpty ? 'lifecycle' : 'process-handle';
    return WorkspaceDiagnosticsProducerCancellationRoute(
      providerId: plan.providerId,
      taskId: current.taskId,
      managerId: plan.binding.managerId,
      routeKind: routeKind,
      canCancel: current.canCancel,
      processHandleBound: handleId.isNotEmpty,
      processHandleId: handleId,
      reason: reason.trim(),
      message: current.canCancel
          ? 'Diagnostics producer ${plan.providerId} can be cancelled through $routeKind.'
          : 'Diagnostics producer ${plan.providerId} cannot be cancelled in its current state.',
    );
  }

  final String providerId;
  final String taskId;
  final String managerId;
  final String routeKind;
  final bool canCancel;
  final bool processHandleBound;
  final String processHandleId;
  final String reason;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'taskId': taskId,
      'managerId': managerId,
      'routeKind': routeKind,
      'canCancel': canCancel,
      'processHandleBound': processHandleBound,
      'message': message,
      if (processHandleId.isNotEmpty) 'processHandleId': processHandleId,
      if (reason.isNotEmpty) 'reason': reason,
    };
  }
}

typedef WorkspaceDiagnosticsProducerCancellationHandler =
    Future<WorkspaceDiagnosticsProducerCancellationResult> Function({
      required WorkspaceDiagnosticsProducerExecutionPlan plan,
      required WorkspaceDiagnosticsProducerLifecycleSnapshot current,
      required String reason,
    });

typedef WorkspaceDiagnosticsProducerTerminator =
    Future<WorkspaceDiagnosticsProducerCancellationResult> Function(
      WorkspaceDiagnosticsProducerTerminationRequest request,
    );

class WorkspaceDiagnosticsProducerTerminationRequest {
  const WorkspaceDiagnosticsProducerTerminationRequest({
    required this.plan,
    required this.current,
    required this.reason,
    required this.processHandleId,
    required this.managerId,
    required this.routeKind,
  });

  final WorkspaceDiagnosticsProducerExecutionPlan plan;
  final WorkspaceDiagnosticsProducerLifecycleSnapshot current;
  final String reason;
  final String processHandleId;
  final String managerId;
  final String routeKind;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': plan.providerId,
      'taskId': current.taskId,
      'reason': reason,
      'processHandleId': processHandleId,
      'managerId': managerId,
      'routeKind': routeKind,
    };
  }
}

abstract class WorkspaceDiagnosticsProcessCancellationHandle {
  const WorkspaceDiagnosticsProcessCancellationHandle();

  String get handleId;

  Future<WorkspaceDiagnosticsProducerCancellationResult>
  cancelDiagnosticsProducer({
    required WorkspaceDiagnosticsProducerExecutionPlan plan,
    required WorkspaceDiagnosticsProducerLifecycleSnapshot current,
    required String reason,
  });
}

class WorkspaceDiagnosticsRuntimeProcessCancellationHandle
    extends WorkspaceDiagnosticsProcessCancellationHandle {
  const WorkspaceDiagnosticsRuntimeProcessCancellationHandle({
    required this.handleId,
    required this.managerId,
    required this.routeKind,
    required WorkspaceDiagnosticsProducerTerminator terminate,
  }) : _terminate = terminate;

  @override
  final String handleId;
  final String managerId;
  final String routeKind;
  final WorkspaceDiagnosticsProducerTerminator _terminate;

  @override
  Future<WorkspaceDiagnosticsProducerCancellationResult>
  cancelDiagnosticsProducer({
    required WorkspaceDiagnosticsProducerExecutionPlan plan,
    required WorkspaceDiagnosticsProducerLifecycleSnapshot current,
    required String reason,
  }) {
    return _terminate(
      WorkspaceDiagnosticsProducerTerminationRequest(
        plan: plan,
        current: current,
        reason: reason,
        processHandleId: handleId,
        managerId: managerId,
        routeKind: routeKind,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'processHandleId': handleId,
      'managerId': managerId,
      'routeKind': routeKind,
    };
  }
}

class WorkspaceDiagnosticsProducerCancellationAdapter {
  const WorkspaceDiagnosticsProducerCancellationAdapter({
    required WorkspaceDiagnosticsProducerCancellationHandler cancel,
  }) : _cancel = cancel;

  factory WorkspaceDiagnosticsProducerCancellationAdapter.processHandle(
    WorkspaceDiagnosticsProcessCancellationHandle handle,
  ) {
    return WorkspaceDiagnosticsProducerCancellationAdapter(
      cancel: ({required plan, required current, required reason}) async {
        final result = await handle.cancelDiagnosticsProducer(
          plan: plan,
          current: current,
          reason: reason,
        );
        return WorkspaceDiagnosticsProducerCancellationResult(
          accepted: result.accepted,
          processTerminated: result.processTerminated,
          message: result.message,
          metadata: <String, Object?>{
            ...result.metadata,
            'processHandleId': handle.handleId,
          },
        );
      },
    );
  }

  final WorkspaceDiagnosticsProducerCancellationHandler _cancel;

  Future<WorkspaceDiagnosticsProducerCancellationResult> cancel({
    required WorkspaceDiagnosticsProducerExecutionPlan plan,
    required WorkspaceDiagnosticsProducerLifecycleSnapshot current,
    required String reason,
  }) {
    return _cancel(plan: plan, current: current, reason: reason);
  }
}

enum WorkspaceDiagnosticsProducerProcessHandleBindingStatus {
  registered,
  missingHandle,
  skipped,
}

class WorkspaceDiagnosticsProducerProcessHandleBindingResult {
  const WorkspaceDiagnosticsProducerProcessHandleBindingResult({
    required this.status,
    required this.message,
    this.providerId = '',
    this.processHandleId = '',
    this.metadata = const <String, Object?>{},
  });

  const WorkspaceDiagnosticsProducerProcessHandleBindingResult.registered({
    required String providerId,
    required String processHandleId,
    String message = 'Diagnostics producer process handle registered.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status:
             WorkspaceDiagnosticsProducerProcessHandleBindingStatus.registered,
         providerId: providerId,
         processHandleId: processHandleId,
         message: message,
         metadata: metadata,
       );

  const WorkspaceDiagnosticsProducerProcessHandleBindingResult.missingHandle({
    String message =
        'Diagnostics producer dispatch did not expose a process handle.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: WorkspaceDiagnosticsProducerProcessHandleBindingStatus
             .missingHandle,
         message: message,
         metadata: metadata,
       );

  const WorkspaceDiagnosticsProducerProcessHandleBindingResult.skipped({
    String message =
        'Diagnostics producer dispatch was not eligible for handle binding.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         status: WorkspaceDiagnosticsProducerProcessHandleBindingStatus.skipped,
         message: message,
         metadata: metadata,
       );

  final WorkspaceDiagnosticsProducerProcessHandleBindingStatus status;
  final String message;
  final String providerId;
  final String processHandleId;
  final Map<String, Object?> metadata;

  bool get registered =>
      status ==
      WorkspaceDiagnosticsProducerProcessHandleBindingStatus.registered;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'registered': registered,
      'message': message,
      if (providerId.isNotEmpty) 'providerId': providerId,
      if (processHandleId.isNotEmpty) 'processHandleId': processHandleId,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class WorkspaceDiagnosticsProducerProcessHandleBinder {
  const WorkspaceDiagnosticsProducerProcessHandleBinder({
    this.handleIdKeys = const <String>[
      'processHandleId',
      'processId',
      'pid',
      'diagnosticsProcessHandleId',
    ],
  });

  final List<String> handleIdKeys;

  WorkspaceDiagnosticsProducerProcessHandleBindingResult bind({
    required WorkspaceDiagnosticsProducerExecutionPlan plan,
    required RuntimeExecutionDispatchResult result,
    required WorkspaceDiagnosticsProducerProcessHandleRegistry registry,
    required WorkspaceDiagnosticsProducerTerminator terminate,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (!result.dispatched) {
      return WorkspaceDiagnosticsProducerProcessHandleBindingResult.skipped(
        message:
            'Diagnostics producer ${plan.providerId} was not dispatched; no process handle was bound.',
        metadata: metadata,
      );
    }
    final processHandle = result.processHandle;
    final handleId =
        _handleIdFromProcessHandle(processHandle) ??
        _handleIdFromResult(result);
    if (handleId == null) {
      return WorkspaceDiagnosticsProducerProcessHandleBindingResult.missingHandle(
        message:
            'Diagnostics producer ${plan.providerId} dispatch did not expose a process handle.',
        metadata: metadata,
      );
    }
    registry.register(
      providerId: plan.providerId,
      handle: WorkspaceDiagnosticsRuntimeProcessCancellationHandle(
        handleId: handleId,
        managerId: result.binding.managerId,
        routeKind: result.binding.routeKind,
        terminate: terminate,
      ),
    );
    return WorkspaceDiagnosticsProducerProcessHandleBindingResult.registered(
      providerId: plan.providerId,
      processHandleId: handleId,
      message:
          'Diagnostics producer ${plan.providerId} process handle $handleId registered.',
      metadata: <String, Object?>{
        'source': 'runtime-dispatch-result',
        'managerId': result.binding.managerId,
        'routeKind': result.binding.routeKind,
        if (processHandle != null) 'processHandle': processHandle.toJson(),
        ...metadata,
      },
    );
  }

  String? _handleIdFromProcessHandle(RuntimeProcessHandleIdentity? handle) {
    if (handle == null || !handle.available) {
      return null;
    }
    if (handle.processHandleId.isNotEmpty) {
      return handle.processHandleId;
    }
    final pid = handle.pid;
    return pid == null ? null : '$pid';
  }

  String? _handleIdFromResult(RuntimeExecutionDispatchResult result) {
    for (final source in <Map<String, Object?>>[
      result.metadata,
      result.outputEvent.metadata,
      result.binding.metadata,
      result.binding.handoff.metadata,
      result.binding.handoff.plan.metadata,
    ]) {
      final handleId = _handleIdFromMetadata(source);
      if (handleId != null) {
        return handleId;
      }
    }
    return null;
  }

  String? _handleIdFromMetadata(Map<String, Object?> metadata) {
    for (final key in handleIdKeys) {
      final value = metadata[key];
      if (value == null) {
        continue;
      }
      final handleId = '$value'.trim();
      if (handleId.isNotEmpty) {
        return handleId;
      }
    }
    return null;
  }
}

class WorkspaceDiagnosticsProducerProcessHandleRegistry {
  WorkspaceDiagnosticsProducerProcessHandleRegistry({
    Map<String, WorkspaceDiagnosticsProcessCancellationHandle> handles =
        const <String, WorkspaceDiagnosticsProcessCancellationHandle>{},
  }) : _handlesByProvider =
           Map<String, WorkspaceDiagnosticsProcessCancellationHandle>.of(
             handles,
           );

  final Map<String, WorkspaceDiagnosticsProcessCancellationHandle>
  _handlesByProvider;

  bool get isEmpty => _handlesByProvider.isEmpty;
  bool get isNotEmpty => _handlesByProvider.isNotEmpty;

  Iterable<String> get providerIds => _handlesByProvider.keys;

  void register({
    required String providerId,
    required WorkspaceDiagnosticsProcessCancellationHandle handle,
  }) {
    final normalizedProviderId = providerId.trim();
    if (normalizedProviderId.isEmpty) {
      return;
    }
    _handlesByProvider[normalizedProviderId] = handle;
  }

  WorkspaceDiagnosticsProcessCancellationHandle? unregister(String providerId) {
    return _handlesByProvider.remove(providerId.trim());
  }

  WorkspaceDiagnosticsProcessCancellationHandle? handleForProvider(
    String providerId,
  ) {
    return _handlesByProvider[providerId.trim()];
  }

  WorkspaceDiagnosticsProducerCancellationAdapter? adapterForProvider(
    String providerId,
  ) {
    final handle = handleForProvider(providerId);
    if (handle == null) {
      return null;
    }
    return WorkspaceDiagnosticsProducerCancellationAdapter.processHandle(
      handle,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerCount': _handlesByProvider.length,
      'providers': <Map<String, Object?>>[
        for (final entry in _handlesByProvider.entries)
          <String, Object?>{
            'providerId': entry.key,
            'processHandleId': entry.value.handleId,
          },
      ],
    };
  }
}

class WorkspaceDiagnosticsProducerLifecycleController {
  WorkspaceDiagnosticsProducerLifecycleController({
    RuntimeTaskLifecycleController? taskLifecycleController,
  }) : _taskLifecycleController =
           taskLifecycleController ?? RuntimeTaskLifecycleController();

  final RuntimeTaskLifecycleController _taskLifecycleController;
  final Map<String, WorkspaceDiagnosticsProducerLifecycleSnapshot>
  _snapshotsByProvider =
      <String, WorkspaceDiagnosticsProducerLifecycleSnapshot>{};
  final Map<String, WorkspaceDiagnosticsProducerExecutionPlan>
  _plansByProvider = <String, WorkspaceDiagnosticsProducerExecutionPlan>{};

  List<WorkspaceDiagnosticsProducerLifecycleSnapshot> get snapshots {
    return List<WorkspaceDiagnosticsProducerLifecycleSnapshot>.unmodifiable(
      _snapshotsByProvider.values,
    );
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot? snapshotForProvider(
    String providerId,
  ) {
    return _snapshotsByProvider[providerId];
  }

  WorkspaceDiagnosticsProducerExecutionPlan? planForProvider(
    String providerId,
  ) {
    return _plansByProvider[providerId];
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot register(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    String message = '',
  }) {
    _plansByProvider[plan.providerId] = plan;
    final task = plan.executionPlan.applyTo(_taskLifecycleController);
    return _record(plan, task, message: message);
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot start(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    String message = '',
  }) {
    _ensureRegistered(plan);
    final task = _taskLifecycleController.start(
      plan.definition.id,
      message: message.trim().isEmpty ? null : message.trim(),
    );
    return _record(plan, task, message: message);
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot reportProgress(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    double? progress,
    String message = '',
  }) {
    final current = _ensureRegistered(plan);
    return _record(
      plan,
      current.taskSnapshot,
      progress: progress,
      cancellationRequested: current.cancellationRequested,
      message: message,
    );
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot complete(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    int exitCode = 0,
    String message = '',
  }) {
    final current = _ensureRegistered(plan);
    final task = _taskLifecycleController.complete(
      plan.definition.id,
      exitCode: exitCode,
      message: message.trim().isEmpty ? null : message.trim(),
    );
    return _record(
      plan,
      task,
      progress: exitCode == 0 ? 1 : current.progress,
      cancellationRequested: current.cancellationRequested,
      message: message,
    );
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot requestCancellation(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    String reason = '',
  }) {
    final current = _ensureRegistered(plan);
    final task = _taskLifecycleController.cancel(
      plan.definition.id,
      message: reason.trim().isEmpty ? null : reason.trim(),
    );
    return _record(
      plan,
      task,
      progress: current.progress,
      cancellationRequested: true,
      message: reason,
    );
  }

  WorkspaceDiagnosticsProducerCancellationRoute cancellationRouteFor(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    String processHandleId = '',
    String reason = '',
  }) {
    final current = _ensureRegistered(plan);
    return WorkspaceDiagnosticsProducerCancellationRoute.fromPlan(
      plan: plan,
      current: current,
      processHandleId: processHandleId,
      reason: reason,
    );
  }

  Future<WorkspaceDiagnosticsProducerLifecycleSnapshot>
  requestProcessCancellation(
    WorkspaceDiagnosticsProducerExecutionPlan plan, {
    required WorkspaceDiagnosticsProducerCancellationAdapter adapter,
    String reason = '',
  }) async {
    final current = _ensureRegistered(plan);
    final result = await adapter.cancel(
      plan: plan,
      current: current,
      reason: reason,
    );
    if (!result.accepted) {
      return _record(
        plan,
        current.taskSnapshot,
        progress: current.progress,
        cancellationRequested: current.cancellationRequested,
        message: result.message,
      );
    }
    final message = result.message.trim().isEmpty ? reason : result.message;
    final task = _taskLifecycleController.cancel(
      plan.definition.id,
      message: message.trim().isEmpty ? null : message.trim(),
      metadata: <String, Object?>{
        'diagnosticsProducerCancellation': result.toJson(),
      },
    );
    return _record(
      plan,
      task,
      progress: current.progress,
      cancellationRequested: true,
      message: message,
    );
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot _ensureRegistered(
    WorkspaceDiagnosticsProducerExecutionPlan plan,
  ) {
    final existing = _snapshotsByProvider[plan.providerId];
    if (existing != null) {
      return existing;
    }
    return register(plan);
  }

  WorkspaceDiagnosticsProducerLifecycleSnapshot _record(
    WorkspaceDiagnosticsProducerExecutionPlan plan,
    RuntimeTaskSnapshot task, {
    double? progress,
    bool cancellationRequested = false,
    String message = '',
  }) {
    final snapshot = WorkspaceDiagnosticsProducerLifecycleSnapshot.fromTask(
      providerId: plan.providerId,
      taskSnapshot: task,
      progress: progress,
      cancellationRequested: cancellationRequested,
      message: message,
    );
    _snapshotsByProvider[plan.providerId] = snapshot;
    return snapshot;
  }
}

double? _normalizeDiagnosticsProducerProgress(double? value) {
  if (value == null) {
    return null;
  }
  if (value <= 0) {
    return 0;
  }
  if (value >= 1) {
    return 1;
  }
  return value;
}

class WorkspaceDiagnostic {
  const WorkspaceDiagnostic({
    required this.documentId,
    required this.diagnostic,
    this.providerId = '',
    this.source = 'language',
    this.quickFixes = const <DiagnosticQuickFix>[],
  });

  final String documentId;
  final Diagnostic diagnostic;
  final String providerId;
  final String source;
  final List<DiagnosticQuickFix> quickFixes;

  bool get hasQuickFixes => quickFixes.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      if (providerId.isNotEmpty) 'providerId': providerId,
      'source': source,
      'hasQuickFixes': hasQuickFixes,
      'quickFixCount': quickFixes.length,
      'severity': diagnostic.severity.name,
      'code': diagnostic.code,
      'message': diagnostic.message,
      'range': <String, int>{
        'start': diagnostic.range.start,
        'end': diagnostic.range.end,
      },
      if (quickFixes.isNotEmpty)
        'quickFixes': quickFixes
            .map(_diagnosticQuickFixToJson)
            .toList(growable: false),
    };
  }
}

class WorkspaceDiagnosticsDocumentGroup {
  const WorkspaceDiagnosticsDocumentGroup({
    required this.documentId,
    required this.diagnostics,
  });

  final String documentId;
  final List<WorkspaceDiagnostic> diagnostics;

  bool get hasErrors {
    return diagnostics.any(
      (entry) => entry.diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  int get totalCount => diagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'totalCount': totalCount,
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
    };
  }
}

class WorkspaceDiagnosticsSourceGroup {
  const WorkspaceDiagnosticsSourceGroup({
    required this.source,
    required this.diagnostics,
  });

  final String source;
  final List<WorkspaceDiagnostic> diagnostics;

  bool get hasErrors {
    return diagnostics.any(
      (entry) => entry.diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  int get totalCount => diagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source,
      'totalCount': totalCount,
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
    };
  }
}

class WorkspaceDiagnosticsSnapshot {
  const WorkspaceDiagnosticsSnapshot({
    required this.providerId,
    required this.diagnostics,
    this.message = '',
  });

  final String providerId;
  final List<WorkspaceDiagnostic> diagnostics;
  final String message;

  bool get hasErrors {
    return diagnostics.any(
      (entry) => entry.diagnostic.severity == DiagnosticSeverity.error,
    );
  }

  int get totalCount => diagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  List<String> get documentIds {
    final ids = diagnostics.map((entry) => entry.documentId).toSet().toList();
    ids.sort();
    return ids;
  }

  List<WorkspaceDiagnosticsDocumentGroup> get documentGroups {
    final groups = <String, List<WorkspaceDiagnostic>>{};
    for (final diagnostic in diagnostics) {
      groups.putIfAbsent(diagnostic.documentId, () => <WorkspaceDiagnostic>[]);
      groups[diagnostic.documentId]!.add(diagnostic);
    }
    final result = groups.entries
        .map(
          (entry) => WorkspaceDiagnosticsDocumentGroup(
            documentId: entry.key,
            diagnostics: List<WorkspaceDiagnostic>.unmodifiable(entry.value),
          ),
        )
        .toList(growable: false);
    result.sort((left, right) {
      final byErrors = right.hasErrors.toString().compareTo(
        left.hasErrors.toString(),
      );
      if (byErrors != 0) {
        return byErrors;
      }
      return left.documentId.compareTo(right.documentId);
    });
    return List<WorkspaceDiagnosticsDocumentGroup>.unmodifiable(result);
  }

  List<WorkspaceDiagnosticsSourceGroup> get sourceGroups {
    return groupWorkspaceDiagnosticsBySource(diagnostics);
  }

  WorkspaceDiagnosticStreamSnapshot get streamSnapshot {
    return WorkspaceDiagnosticStreamSnapshot.fromDiagnostics(
      providerId: providerId,
      diagnostics: diagnostics,
      message: message,
    );
  }

  List<WorkspaceDiagnostic> diagnosticsFor(String documentId) {
    return diagnostics
        .where((entry) => entry.documentId == documentId)
        .toList(growable: false);
  }

  List<WorkspaceDiagnostic> diagnosticsForSeverity(
    DiagnosticSeverity severity,
  ) {
    return diagnostics
        .where((entry) => entry.diagnostic.severity == severity)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'totalCount': totalCount,
      'documentIds': documentIds,
      'documentGroups': documentGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'sourceGroups': sourceGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'streamSnapshot': streamSnapshot.toJson(),
      'severityCounts': severityCounts,
      'hasErrors': hasErrors,
      if (message.isNotEmpty) 'message': message,
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
    };
  }
}

enum WorkspaceDiagnosticStreamSourceKind {
  styioProject,
  nativeTool,
  quickFix,
  external,
}

extension WorkspaceDiagnosticStreamSourceKindX
    on WorkspaceDiagnosticStreamSourceKind {
  String get wireValue => switch (this) {
    WorkspaceDiagnosticStreamSourceKind.styioProject => 'styio-project',
    WorkspaceDiagnosticStreamSourceKind.nativeTool => 'native-tool',
    WorkspaceDiagnosticStreamSourceKind.quickFix => 'quick-fix',
    WorkspaceDiagnosticStreamSourceKind.external => 'external',
  };
}

class WorkspaceDiagnosticStreamEntry {
  const WorkspaceDiagnosticStreamEntry({
    required this.diagnostic,
    required this.sourceKind,
  });

  factory WorkspaceDiagnosticStreamEntry.fromDiagnostic(
    WorkspaceDiagnostic diagnostic,
  ) {
    return WorkspaceDiagnosticStreamEntry(
      diagnostic: diagnostic,
      sourceKind: _streamSourceKindForDiagnostic(diagnostic),
    );
  }

  final WorkspaceDiagnostic diagnostic;
  final WorkspaceDiagnosticStreamSourceKind sourceKind;

  bool get hasQuickFixes => diagnostic.hasQuickFixes;
  String get documentId => diagnostic.documentId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sourceKind': sourceKind.wireValue,
      'documentId': documentId,
      'source': diagnostic.source,
      'providerId': diagnostic.providerId,
      'severity': diagnostic.diagnostic.severity.name,
      'code': diagnostic.diagnostic.code,
      'message': diagnostic.diagnostic.message,
      'hasQuickFixes': hasQuickFixes,
      'quickFixCount': diagnostic.quickFixes.length,
      if (diagnostic.quickFixes.isNotEmpty)
        'quickFixLabels': diagnostic.quickFixes
            .map((fix) => fix.label)
            .toList(growable: false),
    };
  }
}

class WorkspaceDiagnosticStreamSnapshot {
  const WorkspaceDiagnosticStreamSnapshot({
    required this.providerId,
    required this.entries,
    this.message = '',
  });

  factory WorkspaceDiagnosticStreamSnapshot.fromDiagnostics({
    required String providerId,
    required List<WorkspaceDiagnostic> diagnostics,
    String message = '',
  }) {
    return WorkspaceDiagnosticStreamSnapshot(
      providerId: providerId,
      entries: diagnostics
          .map(WorkspaceDiagnosticStreamEntry.fromDiagnostic)
          .toList(growable: false),
      message: message,
    );
  }

  final String providerId;
  final List<WorkspaceDiagnosticStreamEntry> entries;
  final String message;

  int get totalCount => entries.length;
  int get quickFixReadyCount {
    return entries.where((entry) => entry.hasQuickFixes).length;
  }

  Map<String, int> get sourceKindCounts {
    return <String, int>{
      for (final kind in WorkspaceDiagnosticStreamSourceKind.values)
        kind.wireValue: entries
            .where((entry) => entry.sourceKind == kind)
            .length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'totalCount': totalCount,
      'quickFixReadyCount': quickFixReadyCount,
      'sourceKindCounts': sourceKindCounts,
      if (message.isNotEmpty) 'message': message,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class WorkspaceDiagnosticsRuntimeOutputBinding {
  const WorkspaceDiagnosticsRuntimeOutputBinding({
    required this.snapshot,
    this.quickFixTelemetry,
  });

  final WorkspaceDiagnosticsSnapshot snapshot;
  final WorkspaceQuickFixTelemetrySnapshot? quickFixTelemetry;

  List<RuntimeOutputEvent> runtimeOutputEvents({
    DateTime? timestamp,
    String? channelId,
    String label = 'Workspace Diagnostics',
  }) {
    final resolvedTimestamp = timestamp ?? DateTime.now().toUtc();
    final baseChannelId = channelId ?? 'diagnostics.${snapshot.providerId}';
    return <RuntimeOutputEvent>[
      RuntimeOutputEvent(
        channelId: baseChannelId,
        label: label,
        kind: RuntimeOutputChannelKind.runtimeEvents,
        message: snapshot.message.isEmpty
            ? '${snapshot.totalCount} workspace diagnostic(s) from ${snapshot.providerId}.'
            : snapshot.message,
        timestamp: resolvedTimestamp,
        metadata: <String, Object?>{
          'providerId': snapshot.providerId,
          'diagnosticCount': snapshot.totalCount,
          'hasErrors': snapshot.hasErrors,
          'quickFixReadyCount': snapshot.streamSnapshot.quickFixReadyCount,
        },
      ),
      for (final diagnostic in snapshot.diagnostics)
        RuntimeOutputEvent(
          channelId: '$baseChannelId.${diagnostic.documentId}',
          label: '$label ${diagnostic.documentId}',
          kind: _runtimeOutputKindForDiagnostic(diagnostic),
          message:
              '${diagnostic.diagnostic.severity.name} ${diagnostic.documentId}: ${diagnostic.diagnostic.message}',
          timestamp: resolvedTimestamp,
          metadata: <String, Object?>{
            'providerId': diagnostic.providerId,
            'source': diagnostic.source,
            'documentId': diagnostic.documentId,
            'severity': diagnostic.diagnostic.severity.name,
            'code': diagnostic.diagnostic.code,
            'rangeStart': diagnostic.diagnostic.range.start,
            'rangeEnd': diagnostic.diagnostic.range.end,
            'hasQuickFixes': diagnostic.hasQuickFixes,
            'quickFixCount': diagnostic.quickFixes.length,
          },
        ),
      for (final outcome
          in quickFixTelemetry?.outcomes ??
              const <WorkspaceQuickFixReviewOutcome>[])
        RuntimeOutputEvent(
          channelId: '$baseChannelId.quick-fix',
          label: '$label Quick Fix',
          kind: RuntimeOutputChannelKind.runtimeEvents,
          message:
              '${outcome.outcomeKind.wireValue} ${outcome.documentId}:${outcome.diagnosticCode} ${outcome.message}',
          timestamp: outcome.timestamp,
          metadata: <String, Object?>{
            'workspaceId': outcome.workspaceId,
            'producerId': outcome.producerId,
            'documentId': outcome.documentId,
            'diagnosticCode': outcome.diagnosticCode,
            'quickFixIndex': outcome.quickFixIndex,
            'planId': outcome.planId,
            'outcomeKind': outcome.outcomeKind.wireValue,
            'confirmationStatus': outcome.confirmationStatus.wireValue,
            'ready': outcome.ready,
            'applied': outcome.applied,
            'blocked': outcome.blocked,
          },
        ),
    ];
  }

  RuntimeOutputPanelSnapshot outputPanelSnapshot({
    DateTime? timestamp,
    String? channelId,
    String label = 'Workspace Diagnostics',
    RuntimeOutputChannelFilterState filter =
        const RuntimeOutputChannelFilterState(),
  }) {
    return RuntimeOutputPanelSnapshot(
      events: runtimeOutputEvents(
        timestamp: timestamp,
        channelId: channelId,
        label: label,
      ),
      filter: filter,
    );
  }

  Map<String, Object?> toJson() {
    final outputSnapshot = outputPanelSnapshot();
    return <String, Object?>{
      'providerId': snapshot.providerId,
      'diagnosticCount': snapshot.totalCount,
      'quickFixOutcomeCount': quickFixTelemetry?.outcomes.length ?? 0,
      'outputEventCount': outputSnapshot.events.length,
      'outputSnapshot': outputSnapshot.toJson(),
    };
  }
}

class WorkspaceDiagnosticsFilterState {
  const WorkspaceDiagnosticsFilterState({
    this.severities = const <DiagnosticSeverity>[],
    this.documentQuery = '',
    this.sources = const <String>[],
  });

  final List<DiagnosticSeverity> severities;
  final String documentQuery;
  final List<String> sources;

  bool get active {
    return severities.isNotEmpty ||
        documentQuery.trim().isNotEmpty ||
        sources.isNotEmpty;
  }

  String get summary {
    final parts = <String>[
      if (severities.isNotEmpty)
        severities.map((severity) => severity.name).join(','),
      if (documentQuery.trim().isNotEmpty) 'document ${documentQuery.trim()}',
      if (sources.isNotEmpty) 'source ${sources.join(',')}',
    ];
    return parts.join(' · ');
  }

  bool matches(WorkspaceDiagnostic diagnostic) {
    if (severities.isNotEmpty &&
        !severities.contains(diagnostic.diagnostic.severity)) {
      return false;
    }
    final normalizedDocumentQuery = documentQuery.trim().toLowerCase();
    if (normalizedDocumentQuery.isNotEmpty &&
        !diagnostic.documentId.toLowerCase().contains(
          normalizedDocumentQuery,
        )) {
      return false;
    }
    if (sources.isNotEmpty && !sources.contains(diagnostic.source)) {
      return false;
    }
    return true;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'severities': severities.map((severity) => severity.name).toList(),
      if (documentQuery.trim().isNotEmpty)
        'documentQuery': documentQuery.trim(),
      if (sources.isNotEmpty) 'sources': sources,
      'active': active,
      if (summary.isNotEmpty) 'summary': summary,
    };
  }

  factory WorkspaceDiagnosticsFilterState.fromJson(Map<String, Object?> json) {
    final severities = json['severities'];
    final sources = json['sources'];
    return WorkspaceDiagnosticsFilterState(
      severities: severities is List
          ? severities
                .map((severity) => _diagnosticSeverityFromName('$severity'))
                .whereType<DiagnosticSeverity>()
                .toList(growable: false)
          : const <DiagnosticSeverity>[],
      documentQuery: json['documentQuery'] as String? ?? '',
      sources: sources is List
          ? sources.map((source) => '$source').toList(growable: false)
          : const <String>[],
    );
  }
}

class WorkspaceDiagnosticsView {
  const WorkspaceDiagnosticsView({
    required this.providerId,
    required this.filter,
    required this.diagnostics,
    required this.visibleDiagnostics,
  });

  final String providerId;
  final WorkspaceDiagnosticsFilterState filter;
  final List<WorkspaceDiagnostic> diagnostics;
  final List<WorkspaceDiagnostic> visibleDiagnostics;

  factory WorkspaceDiagnosticsView.fromSnapshot(
    WorkspaceDiagnosticsSnapshot snapshot, {
    WorkspaceDiagnosticsFilterState filter =
        const WorkspaceDiagnosticsFilterState(),
  }) {
    return WorkspaceDiagnosticsView.fromDiagnostics(
      providerId: snapshot.providerId,
      diagnostics: snapshot.diagnostics,
      filter: filter,
    );
  }

  factory WorkspaceDiagnosticsView.fromDiagnostics({
    required String providerId,
    required List<WorkspaceDiagnostic> diagnostics,
    WorkspaceDiagnosticsFilterState filter =
        const WorkspaceDiagnosticsFilterState(),
  }) {
    return WorkspaceDiagnosticsView(
      providerId: providerId,
      filter: filter,
      diagnostics: List<WorkspaceDiagnostic>.unmodifiable(diagnostics),
      visibleDiagnostics: List<WorkspaceDiagnostic>.unmodifiable(
        diagnostics.where(filter.matches),
      ),
    );
  }

  int get totalCount => diagnostics.length;
  int get visibleCount => visibleDiagnostics.length;

  Map<String, int> get severityCounts {
    return <String, int>{
      for (final severity in DiagnosticSeverity.values)
        severity.name: diagnostics
            .where((entry) => entry.diagnostic.severity == severity)
            .length,
    };
  }

  List<WorkspaceDiagnosticsDocumentGroup> get documentGroups {
    return groupWorkspaceDiagnostics(visibleDiagnostics);
  }

  List<WorkspaceDiagnosticsSourceGroup> get sourceGroups {
    return groupWorkspaceDiagnosticsBySource(visibleDiagnostics);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'filter': filter.toJson(),
      'totalCount': totalCount,
      'visibleCount': visibleCount,
      'severityCounts': severityCounts,
      'documentGroups': documentGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'sourceGroups': sourceGroups
          .map((group) => group.toJson())
          .toList(growable: false),
      'diagnostics': visibleDiagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
    };
  }
}

enum WorkspaceQuickFixConfirmationStatus {
  ready,
  blockedMissingDocuments,
  blockedNoPreview,
}

extension WorkspaceQuickFixConfirmationStatusX
    on WorkspaceQuickFixConfirmationStatus {
  String get wireValue => switch (this) {
    WorkspaceQuickFixConfirmationStatus.ready => 'ready',
    WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments =>
      'blocked-missing-documents',
    WorkspaceQuickFixConfirmationStatus.blockedNoPreview =>
      'blocked-no-preview',
  };
}

class WorkspaceQuickFixConfirmationPlan {
  const WorkspaceQuickFixConfirmationPlan({
    required this.planId,
    required this.status,
    required this.message,
    this.summary = '',
    this.affectedDocumentIds = const <String>[],
    this.missingDocumentIds = const <String>[],
    this.todo = '',
  });

  factory WorkspaceQuickFixConfirmationPlan.fromPreview(
    WorkspaceEditPreview? preview,
  ) {
    if (preview == null) {
      return const WorkspaceQuickFixConfirmationPlan(
        planId: '',
        status: WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
        message: 'Workspace quick fix has no preview to confirm.',
      );
    }
    if (preview.missingDocumentIds.isNotEmpty) {
      return WorkspaceQuickFixConfirmationPlan(
        planId: preview.planId,
        status: WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments,
        summary: preview.summary,
        affectedDocumentIds: _sortedStrings(
          preview.documents.map((document) => document.documentId),
        ),
        missingDocumentIds: _sortedStrings(preview.missingDocumentIds),
        message:
            'Workspace quick fix is blocked until missing documents are loaded.',
      );
    }
    return WorkspaceQuickFixConfirmationPlan(
      planId: preview.planId,
      status: WorkspaceQuickFixConfirmationStatus.ready,
      summary: preview.summary,
      affectedDocumentIds: _sortedStrings(
        preview.documents.map((document) => document.documentId),
      ),
      message: 'Workspace quick fix is ready for user confirmation.',
      todo:
          'TODO: bind this confirmation plan to a diff preview and explicit apply confirmation UI.',
    );
  }

  final String planId;
  final WorkspaceQuickFixConfirmationStatus status;
  final String message;
  final String summary;
  final List<String> affectedDocumentIds;
  final List<String> missingDocumentIds;
  final String todo;

  bool get ready => status == WorkspaceQuickFixConfirmationStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'status': status.wireValue,
      'ready': ready,
      'message': message,
      if (summary.isNotEmpty) 'summary': summary,
      'affectedDocumentIds': affectedDocumentIds,
      'missingDocumentIds': missingDocumentIds,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class WorkspaceQuickFixReviewPlan {
  const WorkspaceQuickFixReviewPlan({
    required this.diagnostic,
    required this.quickFixIndex,
    required this.confirmationPlan,
    this.plan,
    this.preview,
    this.controls,
  });

  factory WorkspaceQuickFixReviewPlan.fromDiagnostic({
    required WorkspaceDiagnostic diagnostic,
    required List<DocumentState> documents,
    int quickFixIndex = 0,
  }) {
    if (quickFixIndex < 0 || quickFixIndex >= diagnostic.quickFixes.length) {
      return WorkspaceQuickFixReviewPlan(
        diagnostic: diagnostic,
        quickFixIndex: quickFixIndex,
        confirmationPlan: const WorkspaceQuickFixConfirmationPlan(
          planId: '',
          status: WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
          message: 'Workspace diagnostic has no quick fix at this index.',
        ),
      );
    }
    final quickFix = diagnostic.quickFixes[quickFixIndex];
    final plan = WorkspaceEditPlan.fromQuickFix(
      id: 'quick-fix.${diagnostic.documentId}.${diagnostic.diagnostic.code}.$quickFixIndex',
      documentId: diagnostic.documentId,
      quickFix: quickFix,
    );
    final preview = plan.preview(documents);
    return WorkspaceQuickFixReviewPlan(
      diagnostic: diagnostic,
      quickFixIndex: quickFixIndex,
      plan: plan,
      preview: preview,
      confirmationPlan: WorkspaceQuickFixConfirmationPlan.fromPreview(preview),
      controls: WorkspaceEditReviewControls.fromPreview(preview),
    );
  }

  final WorkspaceDiagnostic diagnostic;
  final int quickFixIndex;
  final WorkspaceEditPlan? plan;
  final WorkspaceEditPreview? preview;
  final WorkspaceQuickFixConfirmationPlan confirmationPlan;
  final WorkspaceEditReviewControls? controls;

  bool get ready => confirmationPlan.ready && (controls?.canApply ?? false);

  WorkspaceEditDiffWindow? diffWindow({
    int documentOffset = 0,
    int documentLimit = 20,
    int fileOperationOffset = 0,
    int fileOperationLimit = 20,
  }) {
    return preview?.diffWindow(
      documentOffset: documentOffset,
      documentLimit: documentLimit,
      fileOperationOffset: fileOperationOffset,
      fileOperationLimit: fileOperationLimit,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': diagnostic.documentId,
      'diagnosticCode': diagnostic.diagnostic.code,
      'quickFixIndex': quickFixIndex,
      'ready': ready,
      'confirmationPlan': confirmationPlan.toJson(),
      if (plan != null) 'plan': plan!.toJson(),
      if (preview != null) 'preview': preview!.toJson(),
      if (controls != null) 'controls': controls!.toJson(),
      'todo':
          'TODO: attach quick-fix review outcomes to native diagnostic producer telemetry.',
    };
  }
}

enum WorkspaceQuickFixReviewOutcomeKind { previewed, applied, blocked, failed }

extension WorkspaceQuickFixReviewOutcomeKindX
    on WorkspaceQuickFixReviewOutcomeKind {
  String get wireValue => switch (this) {
    WorkspaceQuickFixReviewOutcomeKind.previewed => 'previewed',
    WorkspaceQuickFixReviewOutcomeKind.applied => 'applied',
    WorkspaceQuickFixReviewOutcomeKind.blocked => 'blocked',
    WorkspaceQuickFixReviewOutcomeKind.failed => 'failed',
  };
}

class WorkspaceQuickFixReviewOutcome {
  const WorkspaceQuickFixReviewOutcome({
    required this.workspaceId,
    required this.producerId,
    required this.documentId,
    required this.diagnosticCode,
    required this.quickFixIndex,
    required this.planId,
    required this.outcomeKind,
    required this.confirmationStatus,
    required this.ready,
    required this.message,
    required this.timestamp,
    this.affectedDocumentIds = const <String>[],
    this.missingDocumentIds = const <String>[],
  });

  factory WorkspaceQuickFixReviewOutcome.fromReviewPlan({
    required String workspaceId,
    required WorkspaceQuickFixReviewPlan reviewPlan,
    required WorkspaceQuickFixReviewOutcomeKind outcomeKind,
    String message = '',
    DateTime? timestamp,
  }) {
    final diagnostic = reviewPlan.diagnostic;
    final confirmation = reviewPlan.confirmationPlan;
    return WorkspaceQuickFixReviewOutcome(
      workspaceId: workspaceId,
      producerId: diagnostic.providerId.isNotEmpty
          ? diagnostic.providerId
          : diagnostic.source,
      documentId: diagnostic.documentId,
      diagnosticCode: diagnostic.diagnostic.code,
      quickFixIndex: reviewPlan.quickFixIndex,
      planId: confirmation.planId,
      outcomeKind: outcomeKind,
      confirmationStatus: confirmation.status,
      ready: reviewPlan.ready,
      message: message.trim().isEmpty ? confirmation.message : message.trim(),
      affectedDocumentIds: confirmation.affectedDocumentIds,
      missingDocumentIds: confirmation.missingDocumentIds,
      timestamp: (timestamp ?? DateTime.now()).toUtc(),
    );
  }

  factory WorkspaceQuickFixReviewOutcome.fromJson(Map<String, Object?> json) {
    return WorkspaceQuickFixReviewOutcome(
      workspaceId: json['workspaceId'] as String? ?? '',
      producerId: json['producerId'] as String? ?? '',
      documentId: json['documentId'] as String? ?? '',
      diagnosticCode: json['diagnosticCode'] as String? ?? '',
      quickFixIndex: json['quickFixIndex'] as int? ?? 0,
      planId: json['planId'] as String? ?? '',
      outcomeKind:
          _workspaceQuickFixReviewOutcomeKindFromWire(json['outcomeKind']) ??
          WorkspaceQuickFixReviewOutcomeKind.previewed,
      confirmationStatus:
          _workspaceQuickFixConfirmationStatusFromWire(
            json['confirmationStatus'],
          ) ??
          WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
      ready: json['ready'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      affectedDocumentIds: _stringListFromJson(json['affectedDocumentIds']),
      missingDocumentIds: _stringListFromJson(json['missingDocumentIds']),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String workspaceId;
  final String producerId;
  final String documentId;
  final String diagnosticCode;
  final int quickFixIndex;
  final String planId;
  final WorkspaceQuickFixReviewOutcomeKind outcomeKind;
  final WorkspaceQuickFixConfirmationStatus confirmationStatus;
  final bool ready;
  final String message;
  final List<String> affectedDocumentIds;
  final List<String> missingDocumentIds;
  final DateTime timestamp;

  bool get applied => outcomeKind == WorkspaceQuickFixReviewOutcomeKind.applied;
  bool get blocked =>
      outcomeKind == WorkspaceQuickFixReviewOutcomeKind.blocked ||
      !ready ||
      confirmationStatus != WorkspaceQuickFixConfirmationStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'producerId': producerId,
      'documentId': documentId,
      'diagnosticCode': diagnosticCode,
      'quickFixIndex': quickFixIndex,
      'planId': planId,
      'outcomeKind': outcomeKind.wireValue,
      'confirmationStatus': confirmationStatus.wireValue,
      'ready': ready,
      'applied': applied,
      'blocked': blocked,
      'message': message,
      'affectedDocumentIds': affectedDocumentIds,
      'missingDocumentIds': missingDocumentIds,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class WorkspaceQuickFixTelemetrySnapshot {
  const WorkspaceQuickFixTelemetrySnapshot({
    required this.workspaceId,
    this.outcomes = const <WorkspaceQuickFixReviewOutcome>[],
    this.updatedAt,
  });

  factory WorkspaceQuickFixTelemetrySnapshot.fromJson(
    Map<String, Object?> json,
  ) {
    final outcomes = <WorkspaceQuickFixReviewOutcome>[];
    final rawOutcomes = json['outcomes'];
    if (rawOutcomes is List) {
      for (final rawOutcome in rawOutcomes) {
        if (rawOutcome is Map) {
          outcomes.add(
            WorkspaceQuickFixReviewOutcome.fromJson(
              Map<String, Object?>.from(rawOutcome),
            ),
          );
        }
      }
    }
    return WorkspaceQuickFixTelemetrySnapshot(
      workspaceId: json['workspaceId'] as String? ?? '',
      outcomes: List.unmodifiable(outcomes),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<WorkspaceQuickFixReviewOutcome> outcomes;
  final DateTime? updatedAt;

  int get appliedCount {
    return outcomes.where((outcome) => outcome.applied).length;
  }

  int get blockedCount {
    return outcomes.where((outcome) => outcome.blocked).length;
  }

  WorkspaceQuickFixTelemetrySnapshot record(
    WorkspaceQuickFixReviewOutcome outcome, {
    int maxOutcomes = 50,
  }) {
    return WorkspaceQuickFixTelemetrySnapshot(
      workspaceId: workspaceId,
      outcomes: <WorkspaceQuickFixReviewOutcome>[
        outcome,
        ...outcomes.where(
          (candidate) =>
              candidate.documentId != outcome.documentId ||
              candidate.diagnosticCode != outcome.diagnosticCode ||
              candidate.quickFixIndex != outcome.quickFixIndex ||
              candidate.timestamp != outcome.timestamp,
        ),
      ].take(maxOutcomes).toList(growable: false),
      updatedAt: outcome.timestamp,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'outcomeCount': outcomes.length,
      'appliedCount': appliedCount,
      'blockedCount': blockedCount,
      'outcomes': outcomes
          .map((outcome) => outcome.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceQuickFixTelemetryStore {
  WorkspaceQuickFixTelemetryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.diagnostics.quick-fix-telemetry',
             layer: 'workspace',
             stateFamily: 'quick-fix-telemetry',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceQuickFixTelemetryStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName =
      'workspace.diagnostics.quick-fix-telemetry';
  static const String _key = 'quick-fix-outcomes';

  final FoundationDataStoreOwner _owner;

  Future<WorkspaceQuickFixTelemetrySnapshot> readSnapshot({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return WorkspaceQuickFixTelemetrySnapshot(workspaceId: workspaceId);
    }
    final snapshot = WorkspaceQuickFixTelemetrySnapshot.fromJson(value);
    return snapshot.workspaceId.isEmpty
        ? WorkspaceQuickFixTelemetrySnapshot(
            workspaceId: workspaceId,
            outcomes: snapshot.outcomes,
            updatedAt: snapshot.updatedAt,
          )
        : snapshot;
  }

  Future<WorkspaceQuickFixTelemetrySnapshot> recordOutcome({
    required WorkspaceQuickFixReviewOutcome outcome,
    int maxOutcomes = 50,
  }) async {
    final next = (await readSnapshot(
      workspaceId: outcome.workspaceId,
    )).record(outcome, maxOutcomes: maxOutcomes);
    await saveSnapshot(snapshot: next);
    return next;
  }

  Future<WorkspaceQuickFixTelemetrySnapshot> saveSnapshot({
    required WorkspaceQuickFixTelemetrySnapshot snapshot,
  }) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: snapshot.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: snapshot.workspaceId,
    );
    return snapshot;
  }

  Future<bool> clearSnapshot({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<WorkspaceDiagnosticsDocumentGroup> groupWorkspaceDiagnostics(
  List<WorkspaceDiagnostic> diagnostics,
) {
  final groups = <String, List<WorkspaceDiagnostic>>{};
  for (final diagnostic in diagnostics) {
    groups.putIfAbsent(diagnostic.documentId, () => <WorkspaceDiagnostic>[]);
    groups[diagnostic.documentId]!.add(diagnostic);
  }
  final result = groups.entries
      .map(
        (entry) => WorkspaceDiagnosticsDocumentGroup(
          documentId: entry.key,
          diagnostics: List<WorkspaceDiagnostic>.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
  result.sort((left, right) {
    if (left.hasErrors != right.hasErrors) {
      return left.hasErrors ? -1 : 1;
    }
    return left.documentId.compareTo(right.documentId);
  });
  return List<WorkspaceDiagnosticsDocumentGroup>.unmodifiable(result);
}

List<WorkspaceDiagnosticsSourceGroup> groupWorkspaceDiagnosticsBySource(
  List<WorkspaceDiagnostic> diagnostics,
) {
  final groups = <String, List<WorkspaceDiagnostic>>{};
  for (final diagnostic in diagnostics) {
    groups.putIfAbsent(diagnostic.source, () => <WorkspaceDiagnostic>[]);
    groups[diagnostic.source]!.add(diagnostic);
  }
  final result = groups.entries
      .map(
        (entry) => WorkspaceDiagnosticsSourceGroup(
          source: entry.key,
          diagnostics: List<WorkspaceDiagnostic>.unmodifiable(entry.value),
        ),
      )
      .toList(growable: false);
  result.sort((left, right) {
    if (left.hasErrors != right.hasErrors) {
      return left.hasErrors ? -1 : 1;
    }
    return left.source.compareTo(right.source);
  });
  return List<WorkspaceDiagnosticsSourceGroup>.unmodifiable(result);
}

List<String> _sortedStrings(Iterable<String> values) {
  final result =
      values
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  return result;
}

WorkspaceQuickFixReviewOutcomeKind? _workspaceQuickFixReviewOutcomeKindFromWire(
  Object? value,
) {
  return switch (value) {
    'previewed' => WorkspaceQuickFixReviewOutcomeKind.previewed,
    'applied' => WorkspaceQuickFixReviewOutcomeKind.applied,
    'blocked' => WorkspaceQuickFixReviewOutcomeKind.blocked,
    'failed' => WorkspaceQuickFixReviewOutcomeKind.failed,
    _ => null,
  };
}

WorkspaceQuickFixConfirmationStatus?
_workspaceQuickFixConfirmationStatusFromWire(Object? value) {
  return switch (value) {
    'ready' => WorkspaceQuickFixConfirmationStatus.ready,
    'blocked-missing-documents' =>
      WorkspaceQuickFixConfirmationStatus.blockedMissingDocuments,
    'blocked-no-preview' =>
      WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
    _ => null,
  };
}

List<String> _stringListFromJson(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((entry) => '$entry').toList(growable: false);
}

DiagnosticSeverity? _diagnosticSeverityFromName(String value) {
  for (final severity in DiagnosticSeverity.values) {
    if (severity.name == value) {
      return severity;
    }
  }
  return null;
}

WorkspaceDiagnosticStreamSourceKind _streamSourceKindForDiagnostic(
  WorkspaceDiagnostic diagnostic,
) {
  final source = diagnostic.source.toLowerCase();
  final providerId = diagnostic.providerId.toLowerCase();
  if (source.contains('quick') || source.contains('code-action')) {
    return WorkspaceDiagnosticStreamSourceKind.quickFix;
  }
  if (source.contains('native') ||
      source.contains('tool') ||
      providerId.contains('native') ||
      providerId.contains('tool')) {
    return WorkspaceDiagnosticStreamSourceKind.nativeTool;
  }
  if (source.contains('styio') || providerId.contains('styio')) {
    return WorkspaceDiagnosticStreamSourceKind.styioProject;
  }
  return WorkspaceDiagnosticStreamSourceKind.external;
}

RuntimeOutputChannelKind _runtimeOutputKindForDiagnostic(
  WorkspaceDiagnostic diagnostic,
) {
  return switch (_streamSourceKindForDiagnostic(diagnostic)) {
    WorkspaceDiagnosticStreamSourceKind.nativeTool =>
      RuntimeOutputChannelKind.nativeTools,
    WorkspaceDiagnosticStreamSourceKind.quickFix =>
      RuntimeOutputChannelKind.runtimeEvents,
    WorkspaceDiagnosticStreamSourceKind.external =>
      RuntimeOutputChannelKind.runtimeEvents,
    WorkspaceDiagnosticStreamSourceKind.styioProject =>
      RuntimeOutputChannelKind.languageService,
  };
}

Map<String, Object?> _diagnosticQuickFixToJson(DiagnosticQuickFix fix) {
  return <String, Object?>{
    'label': fix.label,
    if (fix.detail.isNotEmpty) 'detail': fix.detail,
    'editCount': fix.edits.length,
    'edits': fix.edits
        .map(
          (edit) => <String, Object?>{
            'range': <String, int>{
              'start': edit.range.start,
              'end': edit.range.end,
            },
            'newText': edit.newText,
          },
        )
        .toList(growable: false),
  };
}

abstract class WorkspaceDiagnosticsProvider {
  const WorkspaceDiagnosticsProvider();

  String get providerId;

  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  );
}

class StaticWorkspaceDiagnosticsProvider
    implements WorkspaceDiagnosticsProvider {
  const StaticWorkspaceDiagnosticsProvider({
    required this.providerId,
    required this.snapshot,
  });

  @override
  final String providerId;
  final WorkspaceDiagnosticsSnapshot snapshot;

  @override
  Future<WorkspaceDiagnosticsSnapshot> collect(
    WorkspaceDiagnosticsRequest request,
  ) async {
    return snapshot;
  }
}

class WorkspaceDiagnosticsProviderRegistration {
  const WorkspaceDiagnosticsProviderRegistration({
    required this.id,
    required this.provider,
    this.priority = 0,
    this.state = FoundationRegistryEntryState.registered,
    this.metadata = const <String, Object?>{},
    this.todo = '',
  });

  final String id;
  final WorkspaceDiagnosticsProvider provider;
  final int priority;
  final FoundationRegistryEntryState state;
  final Map<String, Object?> metadata;
  final String todo;
}

class WorkspaceDiagnosticsProviderRegistry {
  WorkspaceDiagnosticsProviderRegistry({
    FoundationProviderRegistry<WorkspaceDiagnosticsProvider>? registry,
  }) : _registry =
           registry ??
           FoundationProviderRegistry<WorkspaceDiagnosticsProvider>();

  static const String owner = 'workspace.diagnostics';
  static const String collectCapability = 'workspace.diagnostics.collect';

  final FoundationProviderRegistry<WorkspaceDiagnosticsProvider> _registry;

  void register(WorkspaceDiagnosticsProviderRegistration registration) {
    _registry.register(
      FoundationProviderRegistration<WorkspaceDiagnosticsProvider>(
        id: registration.id,
        owner: owner,
        provider: registration.provider,
        layer: 'workspace',
        priority: registration.priority,
        state: registration.state,
        capabilities: const <String>[collectCapability],
        metadata: <String, Object?>{
          ...registration.metadata,
          'providerContract': 'workspace-diagnostics-provider',
        },
        todo: registration.todo,
      ),
    );
  }

  FoundationRegistryEntry<WorkspaceDiagnosticsProvider>? resolve({
    bool activeOnly = true,
  }) {
    return _registry.resolve(
      capability: collectCapability,
      owner: owner,
      activeOnly: activeOnly,
    );
  }

  WorkspaceDiagnosticsProvider? provider({bool activeOnly = true}) {
    return resolve(activeOnly: activeOnly)?.value;
  }

  FoundationRegistryManifest manifest({FoundationRegistryEntryState? state}) {
    return _registry.manifest(owner: owner, state: state);
  }
}
