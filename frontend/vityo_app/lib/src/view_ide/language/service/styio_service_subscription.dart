import 'dart:async';

import '../../editor/document_state.dart';
import '../../runtime/runtime_output_channels.dart';
import 'styio_service_connector.dart';

enum StyioServiceSubscriptionEventKind {
  started,
  analyzed,
  stale,
  failed,
  cancelled,
  disposed,
}

enum StyioServiceDaemonEventKind { started, analyzed, failed, stopped }

enum StyioServiceDaemonLifecycleState { detached, active, failed, stopped }

enum StyioServiceDaemonRestartReason {
  streamFailed,
  streamStopped,
  providerChanged,
  manual,
}

enum StyioServiceDaemonRestartDispatchStatus {
  blocked,
  scheduled,
  dispatched,
  failed,
}

typedef StyioServiceDocumentContextResolver =
    String? Function(DocumentState document);

typedef StyioServiceDaemonRestartHandler =
    Future<StyioServiceDaemonLifecycleSnapshot> Function(
      StyioServiceDaemonRestartPlan plan,
    );

abstract class StyioServiceDaemonProcessSupervisor {
  const StyioServiceDaemonProcessSupervisor();

  Future<StyioServiceDaemonLifecycleSnapshot> restartStyioServiceDaemon(
    StyioServiceDaemonRestartPlan plan,
  );
}

class StyioServiceSubscriptionEvent {
  StyioServiceSubscriptionEvent({
    required this.kind,
    required this.documentId,
    required this.revision,
    required this.generation,
    required this.message,
    this.report,
    this.providerId = '',
    this.source = 'subscription-controller',
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final StyioServiceSubscriptionEventKind kind;
  final String documentId;
  final int revision;
  final int generation;
  final String message;
  final StyioServiceAnalysisReport? report;
  final String providerId;
  final String source;
  final DateTime emittedAt;

  bool get analyzed => kind == StyioServiceSubscriptionEventKind.analyzed;
  bool get stale => kind == StyioServiceSubscriptionEventKind.stale;
  bool get failed => kind == StyioServiceSubscriptionEventKind.failed;
  bool get cachedResponseStored => report?.cachedResponseStored ?? false;

  List<RuntimeOutputEvent> semanticPanelEvents({
    StyioServiceResponseTelemetryBridge bridge =
        const StyioServiceResponseTelemetryBridge(),
  }) {
    final response = report?.response;
    if (response == null) {
      return const <RuntimeOutputEvent>[];
    }
    return bridge.eventsForResponse(response, timestamp: emittedAt);
  }

  Map<String, Object?> toJson() {
    final response = report?.response;
    return <String, Object?>{
      'kind': kind.name,
      'documentId': documentId,
      'revision': revision,
      'generation': generation,
      'message': message,
      if (providerId.isNotEmpty) 'providerId': providerId,
      'source': source,
      'cachedResponseStored': cachedResponseStored,
      'semanticPanelEventCount': semanticPanelEvents().length,
      if (response != null) 'response': response.toJson(),
      if (report?.cacheSnapshot != null)
        'cacheSnapshot': report!.cacheSnapshot!.toJson(),
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

class StyioServiceDaemonEvent {
  StyioServiceDaemonEvent({
    required this.kind,
    required this.message,
    this.documentId = '',
    this.revision = 0,
    this.report,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final StyioServiceDaemonEventKind kind;
  final String documentId;
  final int revision;
  final String message;
  final StyioServiceAnalysisReport? report;
  final DateTime emittedAt;

  StyioServiceSubscriptionEvent toSubscriptionEvent({
    required int generation,
    required String providerId,
  }) {
    return StyioServiceSubscriptionEvent(
      kind: switch (kind) {
        StyioServiceDaemonEventKind.started =>
          StyioServiceSubscriptionEventKind.started,
        StyioServiceDaemonEventKind.analyzed =>
          StyioServiceSubscriptionEventKind.analyzed,
        StyioServiceDaemonEventKind.failed =>
          StyioServiceSubscriptionEventKind.failed,
        StyioServiceDaemonEventKind.stopped =>
          StyioServiceSubscriptionEventKind.cancelled,
      },
      documentId: documentId,
      revision: revision,
      generation: generation,
      message: message,
      report: report,
      providerId: providerId,
      source: 'styio-service-daemon',
      emittedAt: emittedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'documentId': documentId,
      'revision': revision,
      'message': message,
      if (report?.response != null) 'response': report!.response.toJson(),
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

class StyioServiceDaemonLifecycleSnapshot {
  const StyioServiceDaemonLifecycleSnapshot({
    required this.state,
    this.providerId = '',
    this.message = '',
  });

  final StyioServiceDaemonLifecycleState state;
  final String providerId;
  final String message;

  bool get active => state == StyioServiceDaemonLifecycleState.active;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'state': state.name,
      'active': active,
      if (providerId.isNotEmpty) 'providerId': providerId,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class StyioServiceDaemonRestartPolicy {
  const StyioServiceDaemonRestartPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.backoffMultiplier = 2,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final int backoffMultiplier;

  bool shouldRestart({
    required int failedAttempt,
    required StyioServiceDaemonLifecycleState state,
    required StyioServiceDaemonRestartReason reason,
  }) {
    if (failedAttempt >= maxAttempts) {
      return false;
    }
    if (reason == StyioServiceDaemonRestartReason.manual ||
        reason == StyioServiceDaemonRestartReason.providerChanged) {
      return true;
    }
    return state == StyioServiceDaemonLifecycleState.failed ||
        state == StyioServiceDaemonLifecycleState.stopped;
  }

  Duration delayForNextAttempt(int failedAttempt) {
    if (failedAttempt <= 0) {
      return Duration.zero;
    }
    var multiplier = 1;
    for (var index = 1; index < failedAttempt; index += 1) {
      multiplier *= backoffMultiplier;
    }
    return initialDelay * multiplier;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'maxAttempts': maxAttempts,
      'initialDelayMs': initialDelay.inMilliseconds,
      'backoffMultiplier': backoffMultiplier,
    };
  }
}

class StyioServiceDaemonRestartPlan {
  const StyioServiceDaemonRestartPlan({
    required this.providerId,
    required this.failedAttempt,
    required this.nextAttempt,
    required this.restartable,
    required this.reason,
    required this.lifecycle,
    required this.delayBeforeRestart,
    required this.message,
    required this.policy,
  });

  factory StyioServiceDaemonRestartPlan.fromLifecycle({
    required StyioServiceDaemonLifecycleSnapshot lifecycle,
    required int failedAttempt,
    required StyioServiceDaemonRestartReason reason,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
  }) {
    final restartable = policy.shouldRestart(
      failedAttempt: failedAttempt,
      state: lifecycle.state,
      reason: reason,
    );
    final delay = restartable
        ? policy.delayForNextAttempt(failedAttempt)
        : Duration.zero;
    final nextAttempt = restartable ? failedAttempt + 1 : failedAttempt;
    final providerId = lifecycle.providerId;
    return StyioServiceDaemonRestartPlan(
      providerId: providerId,
      failedAttempt: failedAttempt,
      nextAttempt: nextAttempt,
      restartable: restartable,
      reason: reason,
      lifecycle: lifecycle,
      delayBeforeRestart: delay,
      message: restartable
          ? 'StyioService daemon $providerId can restart attempt $nextAttempt after ${delay.inMilliseconds}ms.'
          : 'StyioService daemon $providerId cannot restart after attempt $failedAttempt.',
      policy: policy,
    );
  }

  final String providerId;
  final int failedAttempt;
  final int nextAttempt;
  final bool restartable;
  final StyioServiceDaemonRestartReason reason;
  final StyioServiceDaemonLifecycleSnapshot lifecycle;
  final Duration delayBeforeRestart;
  final String message;
  final StyioServiceDaemonRestartPolicy policy;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      'failedAttempt': failedAttempt,
      'nextAttempt': nextAttempt,
      'restartable': restartable,
      'reason': reason.name,
      'lifecycle': lifecycle.toJson(),
      'delayBeforeRestartMs': delayBeforeRestart.inMilliseconds,
      'message': message,
      'policy': policy.toJson(),
    };
  }
}

class StyioServiceDaemonRestartDispatchResult {
  const StyioServiceDaemonRestartDispatchResult({
    required this.status,
    required this.plan,
    required this.message,
    this.lifecycle,
    this.error,
  });

  final StyioServiceDaemonRestartDispatchStatus status;
  final StyioServiceDaemonRestartPlan plan;
  final String message;
  final StyioServiceDaemonLifecycleSnapshot? lifecycle;
  final String? error;

  bool get dispatched =>
      status == StyioServiceDaemonRestartDispatchStatus.dispatched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'dispatched': dispatched,
      'message': message,
      'plan': plan.toJson(),
      if (lifecycle != null) 'lifecycle': lifecycle!.toJson(),
      if (error != null) 'error': error,
    };
  }
}

class StyioServiceDaemonSupervisorControls {
  const StyioServiceDaemonSupervisorControls({
    required this.controller,
    this.processSupervisor,
  });

  final StyioServiceSubscriptionController controller;
  final StyioServiceDaemonProcessSupervisor? processSupervisor;

  bool get processSupervisorAttached => processSupervisor != null;
  StyioServiceDaemonRestartHandler? get restartHandler =>
      processSupervisor?.restartStyioServiceDaemon;

  Future<StyioServiceDaemonRestartDispatchResult> dispatchRestart({
    int failedAttempt = 0,
    StyioServiceDaemonRestartReason reason =
        StyioServiceDaemonRestartReason.manual,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
  }) {
    return controller.dispatchDaemonRestart(
      failedAttempt: failedAttempt,
      reason: reason,
      policy: policy,
      restart: restartHandler,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'processSupervisorAttached': processSupervisorAttached,
      'daemonLifecycle': controller.daemonLifecycle.toJson(),
      'daemonStreamListening': controller.daemonStreamListening,
    };
  }
}

class StyioServiceSubscriptionController {
  StyioServiceSubscriptionController({required this.driver});

  final StyioServiceAnalysisDriver driver;
  final StreamController<StyioServiceSubscriptionEvent> _events =
      StreamController<StyioServiceSubscriptionEvent>.broadcast(sync: true);

  StreamSubscription<DocumentState>? _documentSubscription;
  StreamSubscription<StyioServiceDaemonEvent>? _daemonSubscription;
  StyioServiceDaemonLifecycleSnapshot _daemonLifecycle =
      const StyioServiceDaemonLifecycleSnapshot(
        state: StyioServiceDaemonLifecycleState.detached,
      );
  var _generation = 0;
  var _disposed = false;

  Stream<StyioServiceSubscriptionEvent> get events => _events.stream;
  bool get disposed => _disposed;
  bool get listening => _documentSubscription != null;
  bool get daemonStreamListening => _daemonSubscription != null;
  StyioServiceDaemonLifecycleSnapshot get daemonLifecycle => _daemonLifecycle;
  int get generation => _generation;

  void bindDocumentStream(
    Stream<DocumentState> documents, {
    StyioServiceDocumentContextResolver? filePathForDocument,
    StyioServiceDocumentContextResolver? configPathForDocument,
    StyioServiceDocumentContextResolver? workingDirectoryForDocument,
  }) {
    _ensureActive();
    unawaited(_documentSubscription?.cancel());
    _documentSubscription = documents.listen((document) {
      unawaited(
        refresh(
          document,
          filePath: filePathForDocument?.call(document),
          configPath: configPathForDocument?.call(document),
          workingDirectory: workingDirectoryForDocument?.call(document),
        ),
      );
    });
  }

  void bindDaemonEventStream({
    required String providerId,
    required Stream<StyioServiceDaemonEvent> events,
  }) {
    _ensureActive();
    unawaited(_daemonSubscription?.cancel());
    _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.active,
      providerId: providerId,
      message: 'StyioService daemon stream attached.',
    );
    _daemonSubscription = events.listen(
      (event) {
        _generation += 1;
        _emit(
          event.toSubscriptionEvent(
            generation: _generation,
            providerId: providerId,
          ),
        );
      },
      onError: (Object error) {
        _generation += 1;
        _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
          state: StyioServiceDaemonLifecycleState.failed,
          providerId: providerId,
          message: 'StyioService daemon stream failed: $error',
        );
        _emit(
          StyioServiceSubscriptionEvent(
            kind: StyioServiceSubscriptionEventKind.failed,
            documentId: '',
            revision: 0,
            generation: _generation,
            message: _daemonLifecycle.message,
            providerId: providerId,
            source: 'styio-service-daemon',
          ),
        );
      },
      onDone: () {
        _daemonSubscription = null;
        _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
          state: StyioServiceDaemonLifecycleState.stopped,
          providerId: providerId,
          message: 'StyioService daemon stream stopped.',
        );
      },
    );
  }

  Future<StyioServiceDaemonLifecycleSnapshot> stopDaemonStream({
    String message = 'StyioService daemon stream stopped.',
  }) async {
    _ensureActive();
    await _daemonSubscription?.cancel();
    _daemonSubscription = null;
    _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.stopped,
      providerId: _daemonLifecycle.providerId,
      message: message,
    );
    return _daemonLifecycle;
  }

  StyioServiceDaemonRestartPlan planDaemonRestart({
    required int failedAttempt,
    required StyioServiceDaemonRestartReason reason,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
  }) {
    _ensureActive();
    return StyioServiceDaemonRestartPlan.fromLifecycle(
      lifecycle: _daemonLifecycle,
      failedAttempt: failedAttempt,
      reason: reason,
      policy: policy,
    );
  }

  Future<StyioServiceDaemonRestartDispatchResult> dispatchDaemonRestart({
    required int failedAttempt,
    required StyioServiceDaemonRestartReason reason,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
    StyioServiceDaemonRestartHandler? restart,
  }) async {
    final plan = planDaemonRestart(
      failedAttempt: failedAttempt,
      reason: reason,
      policy: policy,
    );
    if (!plan.restartable) {
      return StyioServiceDaemonRestartDispatchResult(
        status: StyioServiceDaemonRestartDispatchStatus.blocked,
        plan: plan,
        message: plan.message,
      );
    }
    if (restart == null) {
      return StyioServiceDaemonRestartDispatchResult(
        status: StyioServiceDaemonRestartDispatchStatus.scheduled,
        plan: plan,
        message:
            'StyioService daemon restart scheduled; no process handler is attached.',
      );
    }
    try {
      if (plan.delayBeforeRestart > Duration.zero) {
        await Future<void>.delayed(plan.delayBeforeRestart);
      }
      final lifecycle = await restart(plan);
      _daemonLifecycle = lifecycle;
      return StyioServiceDaemonRestartDispatchResult(
        status: StyioServiceDaemonRestartDispatchStatus.dispatched,
        plan: plan,
        lifecycle: lifecycle,
        message: lifecycle.message.isEmpty
            ? 'StyioService daemon restart dispatched.'
            : lifecycle.message,
      );
    } on Object catch (error) {
      _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
        state: StyioServiceDaemonLifecycleState.failed,
        providerId: plan.providerId,
        message: 'StyioService daemon restart failed: $error',
      );
      return StyioServiceDaemonRestartDispatchResult(
        status: StyioServiceDaemonRestartDispatchStatus.failed,
        plan: plan,
        lifecycle: _daemonLifecycle,
        message: _daemonLifecycle.message,
        error: error.toString(),
      );
    }
  }

  Future<StyioServiceSubscriptionEvent> refresh(
    DocumentState document, {
    String? filePath,
    String? configPath,
    String? workingDirectory,
  }) async {
    _ensureActive();
    final generation = ++_generation;
    _emit(
      StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.started,
        documentId: document.documentId,
        revision: document.revision,
        generation: generation,
        message: 'StyioService background analysis started.',
      ),
    );
    try {
      final report = await driver.analyzeDocumentWithReport(
        document,
        filePath: filePath,
        configPath: configPath,
        workingDirectory: workingDirectory,
      );
      if (generation != _generation || _disposed) {
        return _emit(
          StyioServiceSubscriptionEvent(
            kind: StyioServiceSubscriptionEventKind.stale,
            documentId: document.documentId,
            revision: document.revision,
            generation: generation,
            report: report,
            message:
                'StyioService background analysis completed after a newer request.',
          ),
        );
      }
      return _emit(
        StyioServiceSubscriptionEvent(
          kind: StyioServiceSubscriptionEventKind.analyzed,
          documentId: document.documentId,
          revision: document.revision,
          generation: generation,
          report: report,
          message: 'StyioService background analysis completed.',
        ),
      );
    } catch (error) {
      if (generation != _generation || _disposed) {
        return _emit(
          StyioServiceSubscriptionEvent(
            kind: StyioServiceSubscriptionEventKind.stale,
            documentId: document.documentId,
            revision: document.revision,
            generation: generation,
            message:
                'StyioService background analysis failure ignored after a newer request.',
          ),
        );
      }
      return _emit(
        StyioServiceSubscriptionEvent(
          kind: StyioServiceSubscriptionEventKind.failed,
          documentId: document.documentId,
          revision: document.revision,
          generation: generation,
          message: 'StyioService background analysis failed: $error',
        ),
      );
    }
  }

  Future<StyioServiceSubscriptionEvent> cancel({
    String message = 'StyioService background subscription cancelled.',
  }) async {
    _ensureActive();
    _generation += 1;
    await _documentSubscription?.cancel();
    _documentSubscription = null;
    await _daemonSubscription?.cancel();
    _daemonSubscription = null;
    _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.stopped,
      providerId: _daemonLifecycle.providerId,
      message: message,
    );
    return _emit(
      StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.cancelled,
        documentId: '',
        revision: 0,
        generation: _generation,
        message: message,
      ),
    );
  }

  Future<StyioServiceSubscriptionEvent> dispose() async {
    if (_disposed) {
      return StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.disposed,
        documentId: '',
        revision: 0,
        generation: _generation,
        message: 'StyioService background subscription already disposed.',
      );
    }
    _generation += 1;
    await _documentSubscription?.cancel();
    _documentSubscription = null;
    await _daemonSubscription?.cancel();
    _daemonSubscription = null;
    _daemonLifecycle = StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.stopped,
      providerId: _daemonLifecycle.providerId,
      message: 'StyioService daemon stream disposed.',
    );
    _disposed = true;
    final event = _emit(
      StyioServiceSubscriptionEvent(
        kind: StyioServiceSubscriptionEventKind.disposed,
        documentId: '',
        revision: 0,
        generation: _generation,
        message: 'StyioService background subscription disposed.',
      ),
    );
    await _events.close();
    return event;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('StyioService background subscription is disposed.');
    }
  }

  StyioServiceSubscriptionEvent _emit(StyioServiceSubscriptionEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
    return event;
  }
}
