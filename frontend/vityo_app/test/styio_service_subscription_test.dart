import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_subscription.dart';

void main() {
  test(
    'StyioService subscription analyzes document streams into cache events',
    () async {
      const document = DocumentState(
        documentId: 'fixture://streamed',
        text: 'value := 1\n',
        revision: 7,
      );
      final cache = StyioServiceResultCache();
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
          diagnostics: const <StyioServiceDiagnosticDto>[
            StyioServiceDiagnosticDto(
              severity: DiagnosticSeverity.warning,
              code: 'styio.demo',
              message: 'demo warning',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
          semanticSpans: const <SemanticSpan>[
            SemanticSpan(
              kind: SemanticKind.variable,
              range: SourceRange(start: 0, end: 5),
            ),
          ],
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(
          connector: connector,
          resultCache: cache,
        ),
      );
      addTearDown(controller.dispose);
      final documents = StreamController<DocumentState>();
      addTearDown(documents.close);
      controller.bindDocumentStream(documents.stream);

      documents.add(document);
      final event = await controller.events.firstWhere(
        (event) => event.kind == StyioServiceSubscriptionEventKind.analyzed,
      );

      expect(event.analyzed, isTrue);
      expect(event.cachedResponseStored, isTrue);
      expect(event.report?.serviceSucceeded, isTrue);
      expect(event.semanticPanelEvents(), hasLength(2));
      expect(event.toJson()['semanticPanelEventCount'], 2);
      expect(
        cache.lookupDocument(
          documentId: document.documentId,
          revision: document.revision,
          protocolVersion: 'styio-cli-jsonl-v1',
        ),
        isNotNull,
      );
    },
  );

  test(
    'StyioService subscription marks superseded responses as stale',
    () async {
      const firstDocument = DocumentState(
        documentId: 'fixture://stale',
        text: 'first := 1\n',
        revision: 1,
      );
      const secondDocument = DocumentState(
        documentId: 'fixture://stale',
        text: 'second := 2\n',
        revision: 2,
      );
      final connector = _CompleterStyioServiceConnector();
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);

      final first = controller.refresh(firstDocument);
      await Future<void>.delayed(Duration.zero);
      final second = controller.refresh(secondDocument);
      await Future<void>.delayed(Duration.zero);

      connector.completeAt(0);
      final stale = await first;
      connector.completeAt(1);
      final analyzed = await second;

      expect(stale.kind, StyioServiceSubscriptionEventKind.stale);
      expect(stale.revision, 1);
      expect(analyzed.kind, StyioServiceSubscriptionEventKind.analyzed);
      expect(analyzed.revision, 2);
      expect(controller.generation, 2);
    },
  );

  test(
    'StyioService subscription cancellation stops document stream intake',
    () async {
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);
      final documents = StreamController<DocumentState>();
      addTearDown(documents.close);
      controller.bindDocumentStream(documents.stream);

      final event = await controller.cancel();

      expect(event.kind, StyioServiceSubscriptionEventKind.cancelled);
      expect(controller.listening, isFalse);
    },
  );

  test(
    'StyioService subscription binds provider daemon stream lifecycle',
    () async {
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);
      final daemonEvents = StreamController<StyioServiceDaemonEvent>();
      addTearDown(daemonEvents.close);
      controller.bindDaemonEventStream(
        providerId: 'styio-daemon.fixture',
        events: daemonEvents.stream,
      );
      final nextDaemonEvent = controller.events.firstWhere(
        (event) => event.source == 'styio-service-daemon',
      );

      daemonEvents.add(
        StyioServiceDaemonEvent(
          kind: StyioServiceDaemonEventKind.analyzed,
          documentId: 'fixture://daemon',
          revision: 3,
          message: 'daemon analyzed document',
        ),
      );
      final event = await nextDaemonEvent;
      expect(controller.daemonLifecycle.active, isTrue);
      final stopped = await controller.stopDaemonStream();

      expect(controller.daemonStreamListening, isFalse);
      expect(event.kind, StyioServiceSubscriptionEventKind.analyzed);
      expect(event.providerId, 'styio-daemon.fixture');
      expect(event.documentId, 'fixture://daemon');
      expect(event.toJson()['source'], 'styio-service-daemon');
      expect(stopped.state, StyioServiceDaemonLifecycleState.stopped);
      expect(stopped.providerId, 'styio-daemon.fixture');
      expect(stopped.toJson()['active'], isFalse);
    },
  );

  test('StyioService daemon restart plan applies backoff policy', () async {
    final connector = _FactoryStyioServiceConnector(
      (request) => StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: request.documentId,
        revision: request.revision,
      ),
    );
    final controller = StyioServiceSubscriptionController(
      driver: StyioServiceAnalysisDriver(connector: connector),
    );
    addTearDown(controller.dispose);
    final daemonEvents = StreamController<StyioServiceDaemonEvent>();
    addTearDown(daemonEvents.close);
    controller.bindDaemonEventStream(
      providerId: 'styio-daemon.fixture',
      events: daemonEvents.stream,
    );
    final failedEvent = controller.events.firstWhere(
      (event) => event.kind == StyioServiceSubscriptionEventKind.failed,
    );
    const policy = StyioServiceDaemonRestartPolicy(
      maxAttempts: 3,
      initialDelay: Duration(milliseconds: 100),
      backoffMultiplier: 4,
    );

    daemonEvents.addError(StateError('daemon crashed'));
    await failedEvent;
    final firstPlan = controller.planDaemonRestart(
      failedAttempt: 1,
      reason: StyioServiceDaemonRestartReason.streamFailed,
      policy: policy,
    );
    final exhausted = controller.planDaemonRestart(
      failedAttempt: 3,
      reason: StyioServiceDaemonRestartReason.streamFailed,
      policy: policy,
    );

    expect(
      controller.daemonLifecycle.state,
      StyioServiceDaemonLifecycleState.failed,
    );
    expect(firstPlan.restartable, isTrue);
    expect(firstPlan.nextAttempt, 2);
    expect(firstPlan.delayBeforeRestart, const Duration(milliseconds: 100));
    expect(firstPlan.toJson()['reason'], 'streamFailed');
    expect(firstPlan.toJson()['policy'], policy.toJson());
    expect(exhausted.restartable, isFalse);
    expect(exhausted.nextAttempt, 3);
    expect(exhausted.delayBeforeRestart, Duration.zero);
  });

  test(
    'StyioService daemon restart dispatch records handler outcome',
    () async {
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);
      final daemonEvents = StreamController<StyioServiceDaemonEvent>();
      addTearDown(daemonEvents.close);
      controller.bindDaemonEventStream(
        providerId: 'styio-daemon.fixture',
        events: daemonEvents.stream,
      );
      final failedEvent = controller.events.firstWhere(
        (event) => event.kind == StyioServiceSubscriptionEventKind.failed,
      );

      daemonEvents.addError(StateError('daemon crashed'));
      await failedEvent;
      final scheduled = await controller.dispatchDaemonRestart(
        failedAttempt: 0,
        reason: StyioServiceDaemonRestartReason.manual,
        policy: const StyioServiceDaemonRestartPolicy(
          initialDelay: Duration.zero,
        ),
      );
      final dispatched = await controller.dispatchDaemonRestart(
        failedAttempt: 0,
        reason: StyioServiceDaemonRestartReason.manual,
        policy: const StyioServiceDaemonRestartPolicy(
          initialDelay: Duration.zero,
        ),
        restart: (plan) async => StyioServiceDaemonLifecycleSnapshot(
          state: StyioServiceDaemonLifecycleState.active,
          providerId: plan.providerId,
          message: 'StyioService daemon restart handler ran.',
        ),
      );
      final blocked = await controller.dispatchDaemonRestart(
        failedAttempt: 3,
        reason: StyioServiceDaemonRestartReason.streamFailed,
        policy: const StyioServiceDaemonRestartPolicy(maxAttempts: 3),
      );

      expect(
        scheduled.status,
        StyioServiceDaemonRestartDispatchStatus.scheduled,
      );
      expect(scheduled.toJson()['dispatched'], isFalse);
      expect(
        dispatched.status,
        StyioServiceDaemonRestartDispatchStatus.dispatched,
      );
      expect(dispatched.dispatched, isTrue);
      expect(dispatched.lifecycle?.active, isTrue);
      expect(
        controller.daemonLifecycle.state,
        StyioServiceDaemonLifecycleState.active,
      );
      expect(blocked.status, StyioServiceDaemonRestartDispatchStatus.blocked);
      expect(blocked.plan.restartable, isFalse);
    },
  );

  test(
    'StyioService daemon supervisor controls dispatch process restart',
    () async {
      final connector = _FactoryStyioServiceConnector(
        (request) => StyioServiceResponse(
          status: StyioServiceStatus.succeeded,
          documentId: request.documentId,
          revision: request.revision,
        ),
      );
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: connector),
      );
      addTearDown(controller.dispose);
      final daemonEvents = StreamController<StyioServiceDaemonEvent>();
      addTearDown(daemonEvents.close);
      controller.bindDaemonEventStream(
        providerId: 'styio-daemon.fixture',
        events: daemonEvents.stream,
      );
      final failedEvent = controller.events.firstWhere(
        (event) => event.kind == StyioServiceSubscriptionEventKind.failed,
      );
      daemonEvents.addError(StateError('daemon crashed'));
      await failedEvent;
      final supervisor = _CountingStyioServiceDaemonProcessSupervisor();
      final controls = StyioServiceDaemonSupervisorControls(
        controller: controller,
        processSupervisor: supervisor,
      );

      final dispatched = await controls.dispatchRestart(
        policy: const StyioServiceDaemonRestartPolicy(
          initialDelay: Duration.zero,
        ),
      );

      expect(controls.processSupervisorAttached, isTrue);
      expect(
        dispatched.status,
        StyioServiceDaemonRestartDispatchStatus.dispatched,
      );
      expect(dispatched.lifecycle?.active, isTrue);
      expect(supervisor.restartCount, 1);
      expect(controls.toJson()['processSupervisorAttached'], isTrue);
      expect(controls.toJson()['daemonLifecycle'], isA<Map<String, Object?>>());
    },
  );
}

typedef _StyioServiceResponseFactory =
    StyioServiceResponse Function(StyioServiceDocument request);

class _FactoryStyioServiceConnector implements StyioServiceConnector {
  const _FactoryStyioServiceConnector(this.factory);

  final _StyioServiceResponseFactory factory;

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    return factory(document);
  }
}

class _CompleterStyioServiceConnector implements StyioServiceConnector {
  final List<_PendingStyioServiceRequest> pending =
      <_PendingStyioServiceRequest>[];

  @override
  Future<StyioServiceResponse> analyzeDocument(StyioServiceDocument document) {
    final completer = Completer<StyioServiceResponse>();
    pending.add(_PendingStyioServiceRequest(document, completer));
    return completer.future;
  }

  void completeAt(int index) {
    final request = pending[index].document;
    pending[index].completer.complete(
      StyioServiceResponse(
        status: StyioServiceStatus.succeeded,
        documentId: request.documentId,
        revision: request.revision,
      ),
    );
  }
}

class _PendingStyioServiceRequest {
  const _PendingStyioServiceRequest(this.document, this.completer);

  final StyioServiceDocument document;
  final Completer<StyioServiceResponse> completer;
}

class _CountingStyioServiceDaemonProcessSupervisor
    implements StyioServiceDaemonProcessSupervisor {
  int restartCount = 0;

  @override
  Future<StyioServiceDaemonLifecycleSnapshot> restartStyioServiceDaemon(
    StyioServiceDaemonRestartPlan plan,
  ) async {
    restartCount += 1;
    return StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.active,
      providerId: plan.providerId,
      message: 'StyioService daemon restarted by supervisor controls.',
    );
  }
}
