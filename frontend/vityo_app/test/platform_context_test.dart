import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';

void main() {
  PlatformContextController createController() {
    return PlatformContextController(
      store: InMemoryPlatformContextStore(),
      fileSystemProber: StaticFileSystemProber(
        FileSystemFacts.linuxDebianArm(
          targetId: 'ctx',
          architecture: 'aarch64',
        ),
      ),
      shellProber: StaticShellProber(
        ShellFacts.linuxDebianArm(
          targetId: 'ctx',
          architecture: 'aarch64',
          defaultShellPath: '/bin/sh',
        ),
      ),
      processProber: StaticProcessProber(
        ProcessFacts.linuxDebianArm(targetId: 'ctx', architecture: 'aarch64'),
      ),
      resourceProber: StaticResourceProber(
        ResourceFacts.linuxDebianArm(targetId: 'ctx', architecture: 'aarch64'),
      ),
      networkProber: StaticNetworkProber(
        NetworkFacts.linuxDebianArm(targetId: 'ctx', architecture: 'aarch64'),
      ),
      clipboardProber: StaticClipboardProber(
        ClipboardFacts.linuxDebianArm(targetId: 'ctx', architecture: 'aarch64'),
      ),
      notificationProber: StaticNotificationProber(
        NotificationFacts.linuxDebianArm(
          targetId: 'ctx',
          architecture: 'aarch64',
        ),
      ),
      localServiceProber: StaticLocalServiceProber(
        LocalServiceFacts.linuxDebianArm(
          targetId: 'ctx',
          architecture: 'aarch64',
        ),
      ),
      ptyProber: StaticPtyProber(
        PtyFacts.linuxDebianArm(
          targetId: 'ctx',
          architecture: 'aarch64',
          scriptUtilityPath: '/usr/bin/script',
        ),
      ),
      targetId: 'ctx',
    );
  }

  test('platform context refresh composes all system facts', () async {
    final controller = createController();

    final snapshot = await controller.refresh();
    final loaded = await controller.load(refreshIfMissing: false);

    expect(snapshot.supportsLinuxDebianArmTarget, isTrue);
    expect(snapshot.environmentPathListSeparator, ':');
    expect(loaded.fileSystem.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.shell.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.process.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.resource.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.network.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.clipboard.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.notification.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.localService.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.pty.compatibilityTarget, 'linux-debian-arm');
    expect(loaded.shell.defaultShellPath, '/bin/sh');
  });

  test(
    'platform detector composes a context snapshot before storage',
    () async {
      final detector = ProbingPlatformDetector(
        fileSystemProber: StaticFileSystemProber(
          FileSystemFacts.linuxDebianArm(targetId: 'detected'),
        ),
        shellProber: StaticShellProber(
          ShellFacts.linuxDebianArm(
            targetId: 'detected',
            defaultShellPath: '/bin/bash',
          ),
        ),
        processProber: StaticProcessProber(
          ProcessFacts.linuxDebianArm(targetId: 'detected'),
        ),
        resourceProber: StaticResourceProber(
          ResourceFacts.linuxDebianArm(targetId: 'detected'),
        ),
        networkProber: StaticNetworkProber(
          NetworkFacts.linuxDebianArm(targetId: 'detected'),
        ),
        clipboardProber: StaticClipboardProber(
          ClipboardFacts.linuxDebianArm(targetId: 'detected'),
        ),
        notificationProber: StaticNotificationProber(
          NotificationFacts.linuxDebianArm(targetId: 'detected'),
        ),
        localServiceProber: StaticLocalServiceProber(
          LocalServiceFacts.linuxDebianArm(targetId: 'detected'),
        ),
        ptyProber: StaticPtyProber(
          PtyFacts.linuxDebianArm(targetId: 'detected'),
        ),
      );

      final snapshot = await detector.detect(targetId: 'platform-detector');

      expect(snapshot.targetId, 'platform-detector');
      expect(snapshot.source, 'prober');
      expect(snapshot.supportsLinuxDebianArmTarget, isTrue);
      expect(snapshot.fileSystem.targetId, 'platform-detector');
      expect(snapshot.shell.defaultShellPath, '/bin/bash');
      expect(snapshot.shell.targetId, 'platform-detector');
      expect(snapshot.process.targetId, 'platform-detector');
      expect(snapshot.resource.targetId, 'platform-detector');
      expect(snapshot.network.targetId, 'platform-detector');
      expect(snapshot.clipboard.targetId, 'platform-detector');
      expect(snapshot.notification.targetId, 'platform-detector');
      expect(snapshot.localService.targetId, 'platform-detector');
      expect(snapshot.pty.targetId, 'platform-detector');
    },
  );

  test('platform context controller can refresh through a detector', () async {
    final snapshot = PlatformContextSnapshot.compose(
      targetId: 'detector-controller',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'detector-controller',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'detector-controller',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(targetId: 'detector-controller'),
      resource: ResourceFacts.linuxDebianArm(targetId: 'detector-controller'),
      network: NetworkFacts.linuxDebianArm(targetId: 'detector-controller'),
      clipboard: ClipboardFacts.linuxDebianArm(targetId: 'detector-controller'),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'detector-controller',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'detector-controller',
      ),
      pty: PtyFacts.linuxDebianArm(targetId: 'detector-controller'),
    );
    final controller = PlatformContextController(
      store: InMemoryPlatformContextStore(),
      detector: StaticPlatformDetector(snapshot),
      targetId: 'detector-controller',
    );

    final refreshed = await controller.refresh();
    final loaded = await controller.load(refreshIfMissing: false);

    expect(refreshed.targetId, 'detector-controller');
    expect(loaded.shell.defaultShellPath, '/bin/sh');
  });

  test('platform context controller does not reuse another target', () async {
    final stored = PlatformContextSnapshot.compose(
      targetId: 'old-target',
      fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'old-target'),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'old-target',
        defaultShellPath: '/bin/sh',
      ),
    );
    final detected = PlatformContextSnapshot.compose(
      targetId: 'new-target',
      fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'new-target'),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'new-target',
        defaultShellPath: '/bin/bash',
      ),
    );
    final store = InMemoryPlatformContextStore(initialSnapshot: stored);
    final controller = PlatformContextController(
      store: store,
      detector: StaticPlatformDetector(detected),
      targetId: 'new-target',
    );

    expect(() => controller.load(refreshIfMissing: false), throwsStateError);

    final refreshed = await controller.load();
    final loaded = await store.load();

    expect(refreshed.targetId, 'new-target');
    expect(refreshed.shell.defaultShellPath, '/bin/bash');
    expect(loaded?.targetId, 'new-target');
  });

  test('platform context applies fact sections and overrides', () async {
    final controller = createController();

    await controller.refresh();
    await controller.applyShellFacts(
      ShellFacts.linuxDebianArm(defaultShellPath: '/bin/bash'),
    );
    await controller.applyNetworkFacts(
      NetworkFacts.linuxDebianArm(
        proxyEnvironment: const <String, String>{'HTTPS_PROXY': 'proxy'},
      ),
    );
    final updated = await controller.applyOverrides(const <String, Object?>{
      'shell.defaultProfileId': 'bash',
    });

    expect(updated.shell.defaultShellPath, '/bin/bash');
    expect(updated.network.proxyEnvironment['HTTPS_PROXY'], 'proxy');
    expect(updated.overrides['shell.defaultProfileId'], 'bash');
  });

  test('platform context applies every mutable fact section', () async {
    final controller = createController();

    await controller.refresh();
    await controller.applyFileSystemFacts(
      FileSystemFacts.linuxDebianArm(
        targetId: 'foreign-fs',
        architecture: 'armv7l',
      ),
    );
    await controller.applyProcessFacts(
      ProcessFacts.linuxDebianArm(
        targetId: 'foreign-process',
        architecture: 'armv7l',
      ),
    );
    await controller.applyResourceFacts(
      ResourceFacts.linuxDebianArm(
        targetId: 'foreign-resource',
        processorCount: 8,
      ),
    );
    await controller.applyClipboardFacts(
      ClipboardFacts.linuxDebianArm(
        targetId: 'foreign-clipboard',
        supportsSystemClipboard: false,
      ),
    );
    await controller.applyNotificationFacts(
      NotificationFacts.linuxDebianArm(
        targetId: 'foreign-notification',
        supportsDesktopNotifications: false,
      ),
    );
    await controller.applyLocalServiceFacts(
      LocalServiceFacts.linuxDebianArm(
        targetId: 'foreign-local-service',
        architecture: 'armv7l',
      ),
    );
    final updated = await controller.applyPtyFacts(
      PtyFacts.linuxDebianArm(
        targetId: 'foreign-pty',
        scriptUtilityPath: null,
      ),
    );

    expect(updated.fileSystem.targetId, 'ctx');
    expect(updated.fileSystem.architecture, 'armv7l');
    expect(updated.process.targetId, 'ctx');
    expect(updated.process.architecture, 'armv7l');
    expect(updated.resource.processorCount, 8);
    expect(updated.clipboard.supportsSystemClipboard, isFalse);
    expect(updated.notification.supportsDesktopNotifications, isFalse);
    expect(updated.localService.architecture, 'armv7l');
    expect(updated.pty.supportsRawMode, isFalse);
    expect(controller.currentSnapshot, same(updated));
  });

  test('platform context controller reports missing context and probers', () async {
    final controller = PlatformContextController(
      store: InMemoryPlatformContextStore(),
      detector: StaticPlatformDetector(
        PlatformContextSnapshot.compose(
          targetId: 'missing-load',
          fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'missing-load'),
          shell: ShellFacts.linuxDebianArm(targetId: 'missing-load'),
        ),
      ),
      targetId: 'missing-load',
    );

    await expectLater(
      controller.load(refreshIfMissing: false),
      throwsStateError,
    );
    expect(
      () => PlatformContextController(store: InMemoryPlatformContextStore()),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('platform context file store persists and reloads all facts', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_platform_context_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final store = PlatformContextFileStore(
      '${tempRoot.path}${Platform.pathSeparator}platform-context.json',
    );
    final snapshot = PlatformContextSnapshot.compose(
      targetId: 'ctx',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'ctx',
        architecture: 'aarch64',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'ctx',
        architecture: 'aarch64',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(targetId: 'ctx'),
      resource: ResourceFacts.linuxDebianArm(targetId: 'ctx'),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'ctx',
        proxyEnvironment: const <String, String>{'NO_PROXY': 'localhost'},
      ),
      clipboard: ClipboardFacts.linuxDebianArm(targetId: 'ctx'),
      notification: NotificationFacts.linuxDebianArm(targetId: 'ctx'),
      localService: LocalServiceFacts.linuxDebianArm(targetId: 'ctx'),
      pty: PtyFacts.linuxDebianArm(
        targetId: 'ctx',
        scriptUtilityPath: '/usr/bin/script',
      ),
      overrides: const <String, Object?>{'scope': 'test'},
    );

    await store.save(snapshot);
    final loaded = await store.load();

    expect(loaded, isNotNull);
    expect(loaded!.supportsLinuxDebianArmTarget, isTrue);
    expect(loaded.fileSystem.pathStyle, FileSystemPathStyle.posix);
    expect(loaded.shell.defaultShellPath, '/bin/sh');
    expect(loaded.process.supportsSpawn, isTrue);
    expect(loaded.resource.supportsTempDirectory, isTrue);
    expect(loaded.network.proxyEnvironment['NO_PROXY'], 'localhost');
    expect(loaded.clipboard.supportsMemoryFallback, isTrue);
    expect(loaded.notification.supportsInAppFallback, isTrue);
    expect(loaded.localService.supportsLoopbackHttpServer, isTrue);
    expect(loaded.pty.supportsScriptUtility, isTrue);
    expect(loaded.overrides['scope'], 'test');
  });

  test('platform context restores loose JSON provider variants', () {
    final snapshot = PlatformContextSnapshot.fromJson(<String, Object?>{
      'targetId': 'json-context',
      'loadedAt': '2026-06-01T00:00:00Z',
      'refreshedAt': '2026-06-01T01:00:00Z',
      'source': 'fixture',
      'fileSystem': <Object, Object?>{
        'targetId': 'foreign-file-system',
        'operatingSystem': 'windows',
        'distributionId': 'windows',
        'distributionName': 'Windows',
        'architecture': 'x64',
        'pathStyle': 'windows',
        'pathSeparator': r'\',
        'providerKind': 'hosted',
        'watchSupport': 'recursive',
        'caseSensitive': false,
        'supportsFileUri': true,
        'supportsSymbolicLinks': true,
        'supportsAtomicWrite': true,
      },
      'shell': <String, Object?>{
        'providerKind': 'hosted',
        'availableShells': <Object?>[
          <String, Object?>{
            'path': r'C:\Windows\System32\cmd.exe',
            'family': 'cmd',
            'isDefault': true,
          },
          <String, Object?>{'path': '', 'family': 'fish'},
        ],
        'defaultShellPath': r'C:\Windows\System32\cmd.exe',
        'supportsPty': true,
        'supportsLoginShell': true,
      },
      'process': <String, Object?>{
        'providerKind': 'hosted',
        'supportsSpawn': true,
        'supportsSignals': true,
        'supportsProcessGroups': true,
        'supportsEnvironmentOverlay': true,
        'supportsWorkingDirectory': true,
      },
      'resource': <String, Object?>{
        'providerKind': 'virtual',
        'processorCount': 4.8,
        'systemTempPath': r'C:\Temp',
        'homePath': r'C:\Users\Vityo',
        'supportsTempDirectory': true,
        'supportsHomeDirectory': true,
        'supportsStorageProbe': true,
      },
      'network': <String, Object?>{
        'providerKind': 'virtual',
        'supportsHttpClient': true,
        'supportsLoopback': true,
        'proxyEnvironment': <Object, Object?>{1: 'http://proxy.example'},
      },
      'clipboard': <String, Object?>{
        'providerKind': 'memory-fallback',
        'supportsText': true,
        'supportsMemoryFallback': true,
      },
      'notification': <String, Object?>{
        'providerKind': 'in-app-fallback',
        'supportsInAppFallback': true,
      },
      'localService': <String, Object?>{
        'providerKind': 'hosted',
        'supportsLoopbackHttpServer': true,
        'supportsEphemeralPort': true,
      },
      'pty': <String, Object?>{
        'providerKind': 'conpty',
        'supportsPty': true,
        'supportsResize': true,
        'supportsRawMode': true,
        'supportsSignals': true,
        'supportsProcessGroup': true,
        'defaultShellPath': r'C:\Windows\System32\cmd.exe',
      },
      'overrides': <Object, Object?>{1: 'one'},
    });
    final alternate = PlatformContextSnapshot.fromJson(<String, Object?>{
      'targetId': 'alternate-context',
      'fileSystem': <String, Object?>{
        'pathStyle': 'posix',
        'providerKind': 'browser-sandbox',
        'watchSupport': 'polling',
      },
      'shell': <String, Object?>{
        'providerKind': 'virtual',
        'availableShells': <Object?>[
          <String, Object?>{'path': '/bin/zsh', 'family': 'zsh'},
          <String, Object?>{'path': '/usr/bin/fish', 'family': 'fish'},
          <String, Object?>{'path': '/usr/bin/pwsh', 'family': 'powershell'},
        ],
      },
      'process': <String, Object?>{'providerKind': 'virtual'},
      'resource': <String, Object?>{'providerKind': 'hosted'},
      'network': <String, Object?>{'providerKind': 'hosted'},
      'pty': <String, Object?>{'providerKind': 'script-utility'},
    });
    final remote = PlatformContextSnapshot.fromJson(<String, Object?>{
      'targetId': 'remote-context',
      'fileSystem': <String, Object?>{
        'providerKind': 'remote',
        'watchSupport': 'directory',
      },
      'pty': <String, Object?>{'providerKind': 'hosted'},
    });

    expect(snapshot.targetId, 'json-context');
    expect(snapshot.fileSystem.targetId, 'json-context');
    expect(snapshot.fileSystem.pathStyle, FileSystemPathStyle.windows);
    expect(snapshot.fileSystem.providerKind, FileSystemProviderKind.hosted);
    expect(snapshot.fileSystem.watchSupport, FileSystemWatchSupport.recursive);
    expect(snapshot.shell.providerKind, ShellProviderKind.hosted);
    expect(snapshot.shell.availableShells.single.family, ShellFamily.cmd);
    expect(snapshot.process.providerKind, ProcessProviderKind.hosted);
    expect(snapshot.resource.providerKind, ResourceProviderKind.virtual);
    expect(snapshot.resource.processorCount, 4);
    expect(snapshot.network.providerKind, NetworkProviderKind.virtual);
    expect(snapshot.network.proxyEnvironment['1'], 'http://proxy.example');
    expect(snapshot.clipboard.providerKind, ClipboardProviderKind.memoryFallback);
    expect(
      snapshot.notification.providerKind,
      NotificationProviderKind.inAppFallback,
    );
    expect(snapshot.localService.providerKind, LocalServiceProviderKind.hosted);
    expect(snapshot.pty.providerKind, PtyProviderKind.conPty);
    expect(snapshot.overrides['1'], 'one');
    expect(alternate.fileSystem.providerKind, FileSystemProviderKind.browserSandbox);
    expect(alternate.fileSystem.watchSupport, FileSystemWatchSupport.polling);
    expect(alternate.shell.providerKind, ShellProviderKind.virtual);
    expect(
      alternate.shell.availableShells.map((shell) => shell.family),
      <ShellFamily>[ShellFamily.zsh, ShellFamily.fish, ShellFamily.powershell],
    );
    expect(alternate.process.providerKind, ProcessProviderKind.virtual);
    expect(alternate.resource.providerKind, ResourceProviderKind.hosted);
    expect(alternate.network.providerKind, NetworkProviderKind.hosted);
    expect(alternate.pty.providerKind, PtyProviderKind.scriptUtility);
    expect(remote.fileSystem.providerKind, FileSystemProviderKind.remote);
    expect(remote.pty.providerKind, PtyProviderKind.hosted);
  });

  test('platform context feeds all platform managers', () async {
    final context = PlatformContextSnapshot.compose(
      targetId: 'ctx',
      fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'ctx'),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'ctx',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(targetId: 'ctx'),
      resource: ResourceFacts.linuxDebianArm(targetId: 'ctx'),
      network: NetworkFacts.linuxDebianArm(targetId: 'ctx'),
      clipboard: ClipboardFacts.linuxDebianArm(targetId: 'ctx'),
      notification: NotificationFacts.linuxDebianArm(targetId: 'ctx'),
      localService: LocalServiceFacts.linuxDebianArm(targetId: 'ctx'),
      pty: PtyFacts.linuxDebianArm(targetId: 'ctx'),
    );
    final compatibility = PlatformAdapter(context).adapt();

    final fileSystemManager = await createPlatformFileSystemManager(
      platformContext: context,
    );
    final shellManager = await createPlatformShellManager(
      platformContext: context,
    );
    final processManager = await createPlatformProcessManager(
      platformContext: context,
    );
    final resourceManager = await createPlatformResourceManager(
      platformContext: context,
    );
    final networkManager = await createPlatformNetworkManager(
      platformContext: context,
    );
    final clipboardManager = await createPlatformClipboardManager(
      platformContext: context,
    );
    final notificationManager = await createPlatformNotificationManager(
      platformContext: context,
    );
    final localServiceManager = await createPlatformLocalServiceManager(
      platformContext: context,
    );
    final ptyManager = await createPlatformPtyManager(platformContext: context);

    expect(fileSystemManager.facts.targetId, 'ctx');
    expect(shellManager.facts.targetId, 'ctx');
    expect(processManager.facts.targetId, 'ctx');
    expect(resourceManager.facts.targetId, 'ctx');
    expect(networkManager.facts.targetId, 'ctx');
    expect(clipboardManager.facts.targetId, 'ctx');
    expect(notificationManager.facts.targetId, 'ctx');
    expect(localServiceManager.facts.targetId, 'ctx');
    expect(ptyManager.facts.targetId, 'ctx');
    expect(compatibility.supportsLinuxDebianArmTarget, isTrue);
    expect(
      fileSystemManager.compatibility.compatibilityTarget,
      compatibility.fileSystem.compatibilityTarget,
    );
    expect(
      shellManager.compatibility.compatibilityTarget,
      compatibility.shell.compatibilityTarget,
    );
    expect(
      processManager.compatibility.compatibilityTarget,
      compatibility.process.compatibilityTarget,
    );
    expect(
      resourceManager.compatibility.compatibilityTarget,
      compatibility.resource.compatibilityTarget,
    );
    expect(
      networkManager.compatibility.compatibilityTarget,
      compatibility.network.compatibilityTarget,
    );
    expect(
      clipboardManager.compatibility.compatibilityTarget,
      compatibility.clipboard.compatibilityTarget,
    );
    expect(
      notificationManager.compatibility.compatibilityTarget,
      compatibility.notification.compatibilityTarget,
    );
    expect(
      localServiceManager.compatibility.compatibilityTarget,
      compatibility.localService.compatibilityTarget,
    );
    expect(
      ptyManager.compatibility.compatibilityTarget,
      compatibility.pty.compatibilityTarget,
    );

    final result = await shellManager.run(
      const ShellCommandRequest(command: 'printf platform-context'),
    );
    expect(result.succeeded, isTrue);
    expect(result.stdout, 'platform-context');
  }, skip: Platform.isWindows ? 'POSIX shell fixture.' : false);

  test(
    'platform manager bundle composes all managers from one context',
    () async {
      final context = PlatformContextSnapshot.compose(
        targetId: 'manager-bundle',
        fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'manager-bundle'),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'manager-bundle',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(targetId: 'manager-bundle'),
        resource: ResourceFacts.linuxDebianArm(targetId: 'manager-bundle'),
        network: NetworkFacts.linuxDebianArm(targetId: 'manager-bundle'),
        clipboard: ClipboardFacts.linuxDebianArm(targetId: 'manager-bundle'),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'manager-bundle',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'manager-bundle',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'manager-bundle'),
      );

      final managers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final result = await managers.process.run(
        const ProcessCommandRequest(
          executablePath: '/usr/bin/printf',
          arguments: <String>['manager-bundle'],
        ),
      );

      expect(managers.context.targetId, 'manager-bundle');
      expect(managers.compatibility.supportsLinuxDebianArmTarget, isTrue);
      expect(managers.fileSystem.facts.targetId, 'manager-bundle');
      expect(managers.shell.facts.targetId, 'manager-bundle');
      expect(managers.process.facts.targetId, 'manager-bundle');
      expect(managers.resource.facts.targetId, 'manager-bundle');
      expect(managers.network.facts.targetId, 'manager-bundle');
      expect(managers.clipboard.facts.targetId, 'manager-bundle');
      expect(managers.notification.facts.targetId, 'manager-bundle');
      expect(managers.localService.facts.targetId, 'manager-bundle');
      expect(managers.pty.facts.targetId, 'manager-bundle');
      expect(result.succeeded, isTrue);
      expect(result.stdout, 'manager-bundle');
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test(
    'detected platform manager bundle uses platform detector output',
    () async {
      final context = PlatformContextSnapshot.compose(
        targetId: 'detected-manager-bundle',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'detected-manager-bundle',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'detected-manager-bundle'),
      );

      final managers = await createDetectedPlatformManagerBundle(
        targetId: 'detected-manager-bundle',
        detector: StaticPlatformDetector(context),
      );

      expect(managers.context.targetId, 'detected-manager-bundle');
      expect(managers.context.source, context.source);
      expect(managers.compatibility.supportsLinuxDebianArmTarget, isTrue);
      expect(managers.process.facts.targetId, 'detected-manager-bundle');
    },
  );
}
