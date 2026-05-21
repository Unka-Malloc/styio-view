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

  test(
    'StyioService daemon process adapter launches through registry',
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
      final requests = <StyioServiceDaemonProcessLaunchRequest>[];
      final registry = StyioServiceDaemonProcessLauncherRegistry(
        launchers: <StyioServiceDaemonProcessLauncherRegistration>[
          StyioServiceDaemonProcessLauncherRegistration(
            launcherId: 'fixture-local-process',
            label: 'Fixture Local Process',
            kind: StyioServiceDaemonProcessLauncherKind.localProcess,
            providerIds: const <String>{'styio-daemon.fixture'},
            metadata: const <String, Object?>{'platform': 'test'},
            launcher: (request) async {
              requests.add(request);
              return StyioServiceDaemonProcessLaunchResult.started(
                providerId: request.providerId,
                processId: 4242,
                endpoint: 'stdio://styio-service',
                metadata: const <String, Object?>{
                  'processHandleId': 'styio-service-proc-1',
                },
              );
            },
          ),
        ],
      );
      final adapter = StyioServiceDaemonProcessAdapter.fromRegistry(
        registry: registry,
        defaultArguments: const <String>['service', '--jsonl'],
      );

      final snapshot = await adapter.restartStyioServiceDaemon(plan);

      expect(snapshot.active, isTrue);
      expect(snapshot.providerId, 'styio-daemon.fixture');
      expect(requests.single.arguments, <String>['service', '--jsonl']);
      expect(requests.single.metadata['launcherRegistry'], isTrue);
      expect(registry.toJson()['launcherCount'], 1);
    },
  );

  test(
    'StyioService daemon local process launcher maps starter process identity',
    () async {
      final starts = <StyioServiceDaemonLocalProcessStartRequest>[];
      final localLauncher = StyioServiceDaemonLocalProcessLauncher(
        executablePath: '/opt/styio/bin/styio',
        metadata: const <String, Object?>{'source': 'toolchain-manager'},
        starter: (request) async {
          starts.add(request);
          return const StyioServiceDaemonLocalProcessStartResult.started(
            pid: 5151,
            endpoint: 'stdio://styio-service',
            metadata: <String, Object?>{'transport': 'stdio'},
          );
        },
      );
      final registry = StyioServiceDaemonProcessLauncherRegistry(
        launchers: <StyioServiceDaemonProcessLauncherRegistration>[
          localLauncher.registration(
            providerIds: const <String>{'styio-daemon.local'},
          ),
        ],
      );
      final request = StyioServiceDaemonProcessLaunchRequest(
        providerId: 'styio-daemon.local',
        reason: StyioServiceDaemonRestartReason.manual,
        attempt: 2,
        restartable: true,
        arguments: const <String>['service', '--jsonl'],
        workingDirectory: '/workspace/project',
        environment: const <String, String>{'STYIO_HOME': '/opt/styio'},
      );

      final result = await registry.launch(request);

      expect(result.started, isTrue);
      expect(result.processId, 5151);
      expect(result.endpoint, 'stdio://styio-service');
      expect(result.metadata['processHandleId'], '5151');
      expect(result.metadata['transport'], 'stdio');
      expect(starts.single.executablePath, '/opt/styio/bin/styio');
      expect(starts.single.arguments, <String>['service', '--jsonl']);
      expect(starts.single.metadata['attempt'], 2);
      expect(starts.single.toJson()['environmentKeys'], <String>['STYIO_HOME']);
      expect(localLauncher.toJson()['endpoint'], 'stdio://styio-service');
    },
  );

  test(
    'StyioService daemon local process launcher fails without executable',
    () async {
      final localLauncher = StyioServiceDaemonLocalProcessLauncher(
        executablePath: ' ',
        starter: (_) async {
          return const StyioServiceDaemonLocalProcessStartResult.started(
            pid: 1,
          );
        },
      );
      final request = StyioServiceDaemonProcessLaunchRequest(
        providerId: 'styio-daemon.local',
        reason: StyioServiceDaemonRestartReason.manual,
        attempt: 1,
        restartable: true,
        arguments: const <String>['service'],
      );

      final result = await localLauncher.launch(request);

      expect(result.started, isFalse);
      expect(result.message, contains('no executable path'));
      expect(result.metadata['TODO'], contains('ToolchainManager'));
    },
  );

  test(
    'StyioService daemon process launcher registry reports missing launchers',
    () async {
      final registry = StyioServiceDaemonProcessLauncherRegistry();
      final request = StyioServiceDaemonProcessLaunchRequest(
        providerId: 'styio-daemon.missing',
        reason: StyioServiceDaemonRestartReason.manual,
        attempt: 1,
        restartable: true,
        arguments: const <String>['service'],
      );

      final result = await registry.launch(request);

      expect(result.started, isFalse);
      expect(result.providerId, 'styio-daemon.missing');
      expect(result.message, contains('missing'));
      expect(result.metadata['launcherMissing'], isTrue);
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
