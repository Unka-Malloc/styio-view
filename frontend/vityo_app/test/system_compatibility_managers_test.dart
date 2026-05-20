import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';

void main() {
  test('system compatibility abstract files do not import dart io', () {
    final root = Directory('lib/src/view_ide/environment/system_compatibility');
    final offenders =
        root
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .where((file) {
              final name = file.uri.pathSegments.last;
              return !name.endsWith('_io.dart');
            })
            .where((file) {
              final source = file.readAsStringSync();
              return source.contains("import 'dart:io'") ||
                  source.contains('import "dart:io"');
            })
            .map((file) => file.path)
            .toList(growable: false)
          ..sort();

    expect(offenders, isEmpty);
  });

  test('process manager follows prober facts adapter manager route', () async {
    final facts = await LocalProcessProber(
      operatingSystem: 'linux',
      architectureReader: () async => 'aarch64',
      osReleaseReader: () async => const <String, String>{
        'ID': 'debian',
        'PRETTY_NAME': 'Debian GNU/Linux',
      },
      clock: () => DateTime.utc(2026, 5, 16),
    ).probe();
    final compatibility = ProcessAdapter(facts).adapt();
    final manager = LocalProcessManager(facts: facts);

    final result = await manager.run(
      const ProcessCommandRequest(
        executablePath: '/usr/bin/printf',
        arguments: <String>['process-ok'],
      ),
    );

    expect(facts.supportsLinuxDebianArmTarget, isTrue);
    expect(compatibility.isLinuxDebianArm, isTrue);
    expect(result.succeeded, isTrue);
    expect(result.stdout, 'process-ok');
  });

  test('process manager writes standard input to commands', () async {
    final manager = LocalProcessManager.linuxDebianArmForTest();

    final result = await manager.run(
      const ProcessCommandRequest(
        executablePath: '/usr/bin/cat',
        standardInput: 'process-stdin',
      ),
    );

    expect(result.succeeded, isTrue);
    expect(result.stdout, 'process-stdin');
  });

  test('process manager classifies command failures structurally', () async {
    final manager = LocalProcessManager.linuxDebianArmForTest();
    const failed = ProcessCommandResult(
      status: ProcessCommandStatus.failed,
      executablePath: '/usr/bin/styio',
      arguments: <String>['--bad'],
      exitCode: 2,
      stdout: '',
      stderr: 'bad arguments',
      duration: Duration(milliseconds: 3),
    );
    final nonZeroFailure = manager.failureFor(
      failed,
      operation: 'toolchain.health',
      recoveryHint: 'Check the selected toolchain arguments.',
    );
    final blockedResult = await UnsupportedProcessManager(
      facts: ProcessFacts.linuxDebianArm(),
    ).run(const ProcessCommandRequest(executablePath: '/usr/bin/styio'));
    final blockedFailure = UnsupportedProcessManager(
      facts: ProcessFacts.linuxDebianArm(),
    ).failureFor(blockedResult);

    expect(nonZeroFailure, isNotNull);
    expect(nonZeroFailure!.kind, ProcessFailureKind.nonZeroExit);
    expect(nonZeroFailure.sourceManager, 'LocalProcessManager');
    expect(nonZeroFailure.toJson()['operation'], 'toolchain.health');
    expect(blockedFailure!.kind, ProcessFailureKind.unsupported);
    expect(blockedFailure.sourceManager, 'UnsupportedProcessManager');
  });

  test('resource manager follows prober facts adapter manager route', () async {
    final facts = await LocalResourceProber(
      architectureReader: () async => 'aarch64',
      osReleaseReader: () async => const <String, String>{'ID': 'debian'},
      clock: () => DateTime.utc(2026, 5, 16),
    ).probe();
    final compatibility = ResourceAdapter(facts).adapt();
    final manager = LocalResourceManager(facts: facts);

    final tempPath = await manager.createTempDirectory('vityo_resource_test_');
    addTearDown(() => Directory(tempPath).delete(recursive: true));

    expect(facts.supportsLinuxDebianArmTarget, isTrue);
    expect(compatibility.isLinuxDebianArm, isTrue);
    expect(Directory(tempPath).existsSync(), isTrue);
    expect(manager.snapshot().processorCount, greaterThanOrEqualTo(1));
  });

  test('resource manager classifies resource failures structurally', () {
    final manager = LocalResourceManager.linuxDebianArmForTest();
    final limitFailure = manager.classifyFailure(
      const FileSystemException(
        'No space left on device',
        '/tmp',
        OSError('No space left on device', 28),
      ),
      operation: 'resource.temp.create',
      target: '/tmp',
    );
    final unsupportedFailure =
        UnsupportedResourceManager(
          facts: ResourceFacts.linuxDebianArm(),
        ).classifyFailure(
          UnsupportedError('Temporary directories are not available.'),
          operation: 'resource.temp.create',
          target: '/tmp',
        );

    expect(limitFailure.kind, ResourceFailureKind.resourceLimit);
    expect(limitFailure.sourceManager, 'LocalResourceManager');
    expect(limitFailure.toJson()['operation'], 'resource.temp.create');
    expect(unsupportedFailure.kind, ResourceFailureKind.unsupported);
    expect(
      unsupportedFailure.toJson()['sourceManager'],
      'UnsupportedResourceManager',
    );
  });

  test('file system manager writes bytes and manages executable bit', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_file_system_manager_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final manager = LocalFileSystemManager.linuxDebianArmForTest();
    final path = manager.joinPath(<String>[tempRoot.path, 'tool']);

    await manager.writeBytes(path, const <int>[0, 1, 2, 255]);

    expect(await manager.readBytes(path), const <int>[0, 1, 2, 255]);
    if (!Platform.isWindows) {
      expect(await manager.isExecutable(path), isFalse);
      await manager.setExecutable(path);
      expect(await manager.isExecutable(path), isTrue);
      await manager.setExecutable(path, executable: false);
      expect(await manager.isExecutable(path), isFalse);
    }
  });

  test(
    'platform manager bundle follows detector context adapter manager route',
    () async {
      final context = PlatformContextSnapshot.compose(
        targetId: 'detected-platform',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'detected-platform',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'detected-platform',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(targetId: 'detected-platform'),
        resource: ResourceFacts.linuxDebianArm(targetId: 'detected-platform'),
        network: NetworkFacts.linuxDebianArm(targetId: 'detected-platform'),
        clipboard: ClipboardFacts.linuxDebianArm(targetId: 'detected-platform'),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'detected-platform',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'detected-platform',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'detected-platform'),
      );

      final bundle = await createDetectedPlatformManagerBundle(
        targetId: 'runtime-platform',
        detector: StaticPlatformDetector(context),
      );
      final snapshot = bundle.snapshot();

      expect(bundle.context.targetId, 'runtime-platform');
      expect(bundle.context.source, 'prober');
      expect(bundle.fileSystem.facts.targetId, 'runtime-platform');
      expect(bundle.shell.facts.targetId, 'runtime-platform');
      expect(bundle.process.facts.targetId, 'runtime-platform');
      expect(bundle.resource.facts.targetId, 'runtime-platform');
      expect(bundle.network.facts.targetId, 'runtime-platform');
      expect(bundle.clipboard.facts.targetId, 'runtime-platform');
      expect(bundle.notification.facts.targetId, 'runtime-platform');
      expect(bundle.localService.facts.targetId, 'runtime-platform');
      expect(bundle.pty.facts.targetId, 'runtime-platform');
      expect(bundle.compatibility.supportsLinuxDebianArmTarget, isTrue);
      expect(snapshot.toJson()['targetId'], 'runtime-platform');
      expect(snapshot.toJson()['managerKeys'], contains('fileSystem'));
      expect(snapshot.toJson()['managerKeys'], contains('pty'));
      final health = bundle.probeHealthSnapshot(
        probes: <PlatformManagerHealthProbe>[
          PlatformManagerHealthProbe(
            managerKey: 'shell',
            ready: (_) => false,
            message: (_, _) => 'Shell probe is blocked.',
            recoveryActions: const <PlatformManagerRecoveryAction>[
              PlatformManagerRecoveryAction(
                id: 'platform.shell.open-settings',
                label: 'Open shell settings',
                managerKey: 'shell',
                message: 'Review shell configuration.',
              ),
            ],
          ),
        ],
      );
      final routes = const PlatformManagerRecoveryActionRouter().routesFor(
        health,
      );

      expect(routes.single.route, contains('settings://platform/shell'));
      expect(routes.single.route, contains('platform.shell.open-settings'));
      expect(routes.single.toJson()['managerKey'], 'shell');
    },
  );

  test(
    'network manager reaches local service manager loopback service',
    () async {
      final localServiceFacts = await LocalLoopbackServiceProber(
        architectureReader: () async => 'aarch64',
        osReleaseReader: () async => const <String, String>{'ID': 'debian'},
        clock: () => DateTime.utc(2026, 5, 16),
      ).probe();
      final localServiceCompatibility = LocalServiceAdapter(
        localServiceFacts,
      ).adapt();
      final localServiceManager = LoopbackLocalServiceManager(
        facts: localServiceFacts,
      );
      final networkFacts = await LocalNetworkProber(
        architectureReader: () async => 'aarch64',
        osReleaseReader: () async => const <String, String>{'ID': 'debian'},
        clock: () => DateTime.utc(2026, 5, 16),
      ).probe();
      final networkCompatibility = NetworkAdapter(networkFacts).adapt();
      final networkManager = LocalNetworkManager(facts: networkFacts);

      final service = await localServiceManager.startHttpTextService(
        const LocalHttpServiceRequest(responseText: 'local-service-ok'),
      );
      addTearDown(service.close);

      final response = await networkManager.getText(service.uri);

      expect(localServiceFacts.supportsLinuxDebianArmTarget, isTrue);
      expect(localServiceCompatibility.isLinuxDebianArm, isTrue);
      expect(networkFacts.supportsLinuxDebianArmTarget, isTrue);
      expect(networkCompatibility.isLinuxDebianArm, isTrue);
      expect(response.succeeded, isTrue);
      expect(response.body, 'local-service-ok');
    },
  );

  test('local service manager classifies bind failures structurally', () {
    final manager = LoopbackLocalServiceManager.linuxDebianArmForTest();
    final portFailure = manager.classifyFailure(
      const SocketException(
        'Address already in use',
        osError: OSError('Address already in use', 98),
      ),
      operation: 'local-service.start',
      target: 'loopback-http',
    );
    final unsupportedFailure =
        UnsupportedLocalServiceManager(
          facts: LocalServiceFacts.linuxDebianArm(),
        ).classifyFailure(
          UnsupportedError('Local services are not available.'),
          operation: 'local-service.start',
          target: 'loopback-http',
        );

    expect(portFailure.kind, LocalServiceFailureKind.portUnavailable);
    expect(portFailure.sourceManager, 'LoopbackLocalServiceManager');
    expect(unsupportedFailure.kind, LocalServiceFailureKind.unsupported);
    expect(
      unsupportedFailure.toJson()['sourceManager'],
      'UnsupportedLocalServiceManager',
    );
  });

  test('network manager classifies request failures structurally', () async {
    final manager = LocalNetworkManager.linuxDebianArmForTest();
    final httpFailure = manager.failureForBytes(
      NetworkBinaryResponse(
        status: NetworkRequestStatus.failed,
        uri: Uri.parse('https://downloads.vityo.dev/styio'),
        statusCode: 503,
        bytes: const <int>[],
        message: 'Service unavailable',
      ),
      operation: 'toolchain.download',
    );
    final blockedResponse = await UnsupportedNetworkManager(
      facts: NetworkFacts.linuxDebianArm(),
    ).getText(Uri.parse('https://downloads.vityo.dev/styio'));
    final blockedFailure = UnsupportedNetworkManager(
      facts: NetworkFacts.linuxDebianArm(),
    ).failureForText(blockedResponse);

    expect(httpFailure, isNotNull);
    expect(httpFailure!.kind, NetworkFailureKind.httpStatus);
    expect(httpFailure.statusCode, 503);
    expect(httpFailure.sourceManager, 'LocalNetworkManager');
    expect(blockedFailure!.kind, NetworkFailureKind.unsupported);
    expect(
      blockedFailure.toJson()['sourceManager'],
      'UnsupportedNetworkManager',
    );
  });

  test(
    'clipboard manager follows prober facts adapter manager route',
    () async {
      final facts = await LocalClipboardProber(
        environment: const <String, String>{},
        architectureReader: () async => 'aarch64',
        osReleaseReader: () async => const <String, String>{'ID': 'debian'},
        clock: () => DateTime.utc(2026, 5, 16),
      ).probe();
      final compatibility = ClipboardAdapter(facts).adapt();
      final manager = LocalClipboardManager(facts: facts);

      final write = await manager.writeText('clipboard-ok');
      final read = await manager.readText();

      expect(facts.supportsLinuxDebianArmTarget, isTrue);
      expect(compatibility.isLinuxDebianArm, isTrue);
      expect(write.succeeded, isTrue);
      expect(read.text, 'clipboard-ok');
    },
  );

  test(
    'clipboard manager classifies blocked operations structurally',
    () async {
      final manager = UnsupportedClipboardManager(
        facts: ClipboardFacts.linuxDebianArm(),
      );
      final result = await manager.writeText('clipboard');
      final failure = manager.failureFor(
        result,
        operation: 'clipboard.writeText',
      );

      expect(failure, isNotNull);
      expect(failure!.kind, ClipboardFailureKind.blocked);
      expect(failure.sourceManager, 'UnsupportedClipboardManager');
      expect(failure.toJson()['operation'], 'clipboard.writeText');
    },
  );

  test(
    'notification manager follows prober facts adapter manager route',
    () async {
      final facts = await LocalNotificationProber(
        architectureReader: () async => 'aarch64',
        osReleaseReader: () async => const <String, String>{'ID': 'debian'},
        clock: () => DateTime.utc(2026, 5, 16),
      ).probe();
      final compatibility = NotificationAdapter(facts).adapt();
      final manager = LocalNotificationManager(facts: facts);

      final result = await manager.notify(
        const NotificationRequest(title: 'Vityo', body: 'notification-ok'),
      );

      expect(facts.supportsLinuxDebianArmTarget, isTrue);
      expect(compatibility.isLinuxDebianArm, isTrue);
      expect(result.delivered, isTrue);
      expect(manager.deliveredRequests.single.body, 'notification-ok');
    },
  );

  test(
    'notification manager classifies blocked operations structurally',
    () async {
      final manager = UnsupportedNotificationManager(
        facts: NotificationFacts.linuxDebianArm(),
      );
      final result = await manager.notify(
        const NotificationRequest(title: 'Vityo', body: 'blocked'),
      );
      final failure = manager.failureFor(result);

      expect(failure, isNotNull);
      expect(failure!.kind, NotificationFailureKind.blocked);
      expect(failure.sourceManager, 'UnsupportedNotificationManager');
      expect(failure.toJson()['operation'], 'notification.notify');
    },
  );

  test('local host remains debian arm for manager prober target', () async {
    final machine = await Process.run('uname', const <String>['-m']);
    final osRelease = await File('/etc/os-release').readAsString();
    final isDebianArmHost =
        Platform.isLinux &&
        osRelease.contains('ID=debian') &&
        machine.stdout.toString().trim().toLowerCase() == 'aarch64';

    if (isDebianArmHost) {
      expect(
        (await const LocalProcessProber().probe()).supportsLinuxDebianArmTarget,
        isTrue,
      );
      expect(
        (await const LocalResourceProber().probe())
            .supportsLinuxDebianArmTarget,
        isTrue,
      );
      expect(
        (await const LocalNetworkProber().probe()).supportsLinuxDebianArmTarget,
        isTrue,
      );
      expect(
        (await const LocalClipboardProber().probe())
            .supportsLinuxDebianArmTarget,
        isTrue,
      );
      expect(
        (await const LocalNotificationProber().probe())
            .supportsLinuxDebianArmTarget,
        isTrue,
      );
      expect(
        (await const LocalLoopbackServiceProber().probe())
            .supportsLinuxDebianArmTarget,
        isTrue,
      );
    }
  });
}
