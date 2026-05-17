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
  final platformDetector = detector ??
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
