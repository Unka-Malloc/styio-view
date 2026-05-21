import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_daemon_process_adapter.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_subscription.dart';

void main() {
  test(
    'StyioService daemon process adapter feeds supervisor controls',
    () async {
      final controller = StyioServiceSubscriptionController(
        driver: StyioServiceAnalysisDriver(connector: _NoopStyioConnector()),
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
      final requests = <StyioServiceDaemonProcessLaunchRequest>[];
      final adapter = StyioServiceDaemonProcessAdapter(
        defaultArguments: const <String>['service', '--jsonl'],
        workingDirectory: '/workspace/project',
        environment: const <String, String>{'STYIO_HOME': '/opt/styio'},
        launcher: (request) async {
          requests.add(request);
          return StyioServiceDaemonProcessLaunchResult.started(
            providerId: request.providerId,
            processId: 42,
            endpoint: 'stdio://styio-service',
          );
        },
      );
      final controls = StyioServiceDaemonSupervisorControls(
        controller: controller,
        processSupervisor: adapter,
      );

      daemonEvents.addError(StateError('daemon crashed'));
      await failedEvent;
      final dispatched = await controls.dispatchRestart(
        policy: const StyioServiceDaemonRestartPolicy(
          initialDelay: Duration.zero,
        ),
      );

      expect(dispatched.dispatched, isTrue);
      expect(dispatched.lifecycle?.active, isTrue);
      expect(dispatched.lifecycle?.providerId, 'styio-daemon.fixture');
      expect(requests.single.reason, StyioServiceDaemonRestartReason.manual);
      expect(requests.single.arguments, <String>['service', '--jsonl']);
      expect(requests.single.toJson()['environmentKeys'], <String>[
        'STYIO_HOME',
      ]);
      expect(adapter.toJson()['environmentKeys'], <String>['STYIO_HOME']);
    },
  );

  test(
    'StyioService daemon process adapter reports launcher failures',
    () async {
      const lifecycle = StyioServiceDaemonLifecycleSnapshot(
        state: StyioServiceDaemonLifecycleState.failed,
        providerId: 'styio-daemon.fixture',
        message: 'daemon crashed',
      );
      final plan = StyioServiceDaemonRestartPlan.fromLifecycle(
        lifecycle: lifecycle,
        failedAttempt: 0,
        reason: StyioServiceDaemonRestartReason.manual,
        policy: const StyioServiceDaemonRestartPolicy(
          initialDelay: Duration.zero,
        ),
      );
      final adapter = StyioServiceDaemonProcessAdapter(
        launcher: (_) => throw StateError('missing binary'),
      );

      final snapshot = await adapter.restartStyioServiceDaemon(plan);

      expect(snapshot.state, StyioServiceDaemonLifecycleState.failed);
      expect(snapshot.providerId, 'styio-daemon.fixture');
      expect(snapshot.message, contains('missing binary'));
    },
  );
}

class _NoopStyioConnector implements StyioServiceConnector {
  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    return StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: document.documentId,
      revision: document.revision,
    );
  }
}
