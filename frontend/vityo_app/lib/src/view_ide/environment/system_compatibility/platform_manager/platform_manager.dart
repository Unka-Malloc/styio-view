import '../clipboard/clipboard.dart';
import '../file_system/file_system.dart';
import '../local_service/local_service.dart';
import '../network/network.dart';
import '../notification/notification.dart';
import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context_model.dart';
import '../platform_detector/platform_detector.dart';
import '../process/process.dart';
import '../pty/pty.dart';
import '../resource/resource.dart';
import '../shell/shell.dart';

class PlatformManagerBundle {
  const PlatformManagerBundle({
    required this.context,
    required this.compatibility,
    required this.fileSystem,
    required this.shell,
    required this.process,
    required this.resource,
    required this.network,
    required this.clipboard,
    required this.notification,
    required this.localService,
    required this.pty,
  });

  final PlatformContextSnapshot context;
  final PlatformCompatibilitySnapshot compatibility;
  final FileSystemManager fileSystem;
  final ShellManager shell;
  final ProcessManager process;
  final ResourceManager resource;
  final NetworkManager network;
  final ClipboardManager clipboard;
  final NotificationManager notification;
  final LocalServiceManager localService;
  final PtyManager pty;

  PlatformManagerBundleSnapshot snapshot() {
    return PlatformManagerBundleSnapshot(
      targetId: context.targetId,
      contextSource: context.source,
      schemaVersion: context.schemaVersion,
      supportsLinuxDebianArmTarget: compatibility.supportsLinuxDebianArmTarget,
      managerKeys: const <String>[
        'fileSystem',
        'shell',
        'process',
        'resource',
        'network',
        'clipboard',
        'notification',
        'localService',
        'pty',
      ],
    );
  }

  PlatformManagerHealthSnapshot healthSnapshot() {
    final components = <PlatformManagerComponentHealth>[
      PlatformManagerComponentHealth(
        managerKey: 'fileSystem',
        ready: context.fileSystem.supportsLinuxDebianArmTarget,
        message: 'File system manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'shell',
        ready: context.shell.supportsLinuxDebianArmTarget,
        message: 'Shell manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'process',
        ready: context.process.supportsLinuxDebianArmTarget,
        message: 'Process manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'resource',
        ready: context.resource.supportsLinuxDebianArmTarget,
        message: 'Resource manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'network',
        ready: context.network.supportsLinuxDebianArmTarget,
        message: 'Network manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'clipboard',
        ready: context.clipboard.supportsLinuxDebianArmTarget,
        message: 'Clipboard manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'notification',
        ready: context.notification.supportsLinuxDebianArmTarget,
        message: 'Notification manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'localService',
        ready: context.localService.supportsLinuxDebianArmTarget,
        message: 'Local service manager compatibility is available.',
      ),
      PlatformManagerComponentHealth(
        managerKey: 'pty',
        ready: context.pty.supportsLinuxDebianArmTarget,
        message: 'PTY manager compatibility is available.',
      ),
    ];
    return PlatformManagerHealthSnapshot(
      targetId: context.targetId,
      ready: components.every((component) => component.ready),
      components: components,
      todo:
          'TODO: replace fact-level readiness with live manager probes when system managers expose runtime health.',
    );
  }
}

class PlatformManagerBundleSnapshot {
  const PlatformManagerBundleSnapshot({
    required this.targetId,
    required this.contextSource,
    required this.schemaVersion,
    required this.supportsLinuxDebianArmTarget,
    required this.managerKeys,
  });

  final String targetId;
  final String contextSource;
  final String schemaVersion;
  final bool supportsLinuxDebianArmTarget;
  final List<String> managerKeys;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetId': targetId,
      'contextSource': contextSource,
      'schemaVersion': schemaVersion,
      'supportsLinuxDebianArmTarget': supportsLinuxDebianArmTarget,
      'managerKeys': managerKeys,
    };
  }
}

class PlatformManagerComponentHealth {
  const PlatformManagerComponentHealth({
    required this.managerKey,
    required this.ready,
    required this.message,
  });

  final String managerKey;
  final bool ready;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'managerKey': managerKey,
      'ready': ready,
      'message': message,
    };
  }
}

class PlatformManagerHealthSnapshot {
  const PlatformManagerHealthSnapshot({
    required this.targetId,
    required this.ready,
    required this.components,
    this.todo = '',
  });

  final String targetId;
  final bool ready;
  final List<PlatformManagerComponentHealth> components;
  final String todo;

  int get readyCount {
    return components.where((component) => component.ready).length;
  }

  int get blockedCount {
    return components.length - readyCount;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetId': targetId,
      'ready': ready,
      'readyCount': readyCount,
      'blockedCount': blockedCount,
      'componentCount': components.length,
      'components': components
          .map((component) => component.toJson())
          .toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

Future<PlatformManagerBundle> createPlatformManagerBundle({
  required PlatformContextSnapshot platformContext,
}) async {
  return PlatformManagerBundle(
    context: platformContext,
    compatibility: PlatformAdapter(platformContext).adapt(),
    fileSystem: await createPlatformFileSystemManager(
      platformContext: platformContext,
    ),
    shell: await createPlatformShellManager(platformContext: platformContext),
    process: await createPlatformProcessManager(
      platformContext: platformContext,
    ),
    resource: await createPlatformResourceManager(
      platformContext: platformContext,
    ),
    network: await createPlatformNetworkManager(
      platformContext: platformContext,
    ),
    clipboard: await createPlatformClipboardManager(
      platformContext: platformContext,
    ),
    notification: await createPlatformNotificationManager(
      platformContext: platformContext,
    ),
    localService: await createPlatformLocalServiceManager(
      platformContext: platformContext,
    ),
    pty: await createPlatformPtyManager(platformContext: platformContext),
  );
}

Future<PlatformManagerBundle> createDetectedPlatformManagerBundle({
  String targetId = 'local',
  PlatformDetector? detector,
}) async {
  final platformDetector =
      detector ??
      const ProbingPlatformDetector(
        fileSystemProber: LocalFileSystemProber(),
        shellProber: LocalShellProber(),
        processProber: LocalProcessProber(),
        resourceProber: LocalResourceProber(),
        networkProber: LocalNetworkProber(),
        clipboardProber: LocalClipboardProber(),
        notificationProber: LocalNotificationProber(),
        localServiceProber: LocalLoopbackServiceProber(),
        ptyProber: LocalPtyProber(),
      );
  final context = await platformDetector.detect(targetId: targetId);
  return createPlatformManagerBundle(platformContext: context);
}
