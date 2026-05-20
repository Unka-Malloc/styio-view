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

  PlatformManagerHealthSnapshot probeHealthSnapshot({
    List<PlatformManagerHealthProbe>? probes,
  }) {
    final effectiveProbes =
        probes ?? PlatformManagerHealthProbe.defaultProbes();
    final components = effectiveProbes
        .map((probe) => probe.run(this))
        .toList(growable: false);
    return PlatformManagerHealthSnapshot(
      targetId: context.targetId,
      ready: components.every((component) => component.ready),
      components: components,
      probeSource: 'platform-manager-probes',
      todo:
          'TODO: replace default lightweight probes with manager-specific live operation probes.',
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
    this.recoveryActions = const <PlatformManagerRecoveryAction>[],
  });

  final String managerKey;
  final bool ready;
  final String message;
  final List<PlatformManagerRecoveryAction> recoveryActions;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'managerKey': managerKey,
      'ready': ready,
      'message': message,
      if (recoveryActions.isNotEmpty)
        'recoveryActions': recoveryActions
            .map((action) => action.toJson())
            .toList(growable: false),
    };
  }
}

class PlatformManagerRecoveryAction {
  const PlatformManagerRecoveryAction({
    required this.id,
    required this.label,
    required this.managerKey,
    required this.message,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String label;
  final String managerKey;
  final String message;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'managerKey': managerKey,
      'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

typedef PlatformManagerProbeReady = bool Function(PlatformManagerBundle bundle);
typedef PlatformManagerProbeMessage =
    String Function(PlatformManagerBundle bundle, bool ready);

class PlatformManagerHealthProbe {
  const PlatformManagerHealthProbe({
    required this.managerKey,
    required this.ready,
    required this.message,
    this.recoveryActions = const <PlatformManagerRecoveryAction>[],
  });

  final String managerKey;
  final PlatformManagerProbeReady ready;
  final PlatformManagerProbeMessage message;
  final List<PlatformManagerRecoveryAction> recoveryActions;

  static List<PlatformManagerHealthProbe> defaultProbes() {
    return <PlatformManagerHealthProbe>[
      _probe(
        'fileSystem',
        (bundle) => bundle.context.fileSystem.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'shell',
        (bundle) => bundle.context.shell.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'process',
        (bundle) => bundle.context.process.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'resource',
        (bundle) => bundle.context.resource.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'network',
        (bundle) => bundle.context.network.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'clipboard',
        (bundle) => bundle.context.clipboard.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'notification',
        (bundle) => bundle.context.notification.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'localService',
        (bundle) => bundle.context.localService.supportsLinuxDebianArmTarget,
      ),
      _probe(
        'pty',
        (bundle) => bundle.context.pty.supportsLinuxDebianArmTarget,
      ),
    ];
  }

  PlatformManagerComponentHealth run(PlatformManagerBundle bundle) {
    final result = ready(bundle);
    return PlatformManagerComponentHealth(
      managerKey: managerKey,
      ready: result,
      message: message(bundle, result),
      recoveryActions: result
          ? const <PlatformManagerRecoveryAction>[]
          : recoveryActions,
    );
  }
}

class PlatformManagerHealthSnapshot {
  const PlatformManagerHealthSnapshot({
    required this.targetId,
    required this.ready,
    required this.components,
    this.probeSource = 'platform-context-facts',
    this.todo = '',
  });

  final String targetId;
  final bool ready;
  final List<PlatformManagerComponentHealth> components;
  final String probeSource;
  final String todo;

  int get readyCount {
    return components.where((component) => component.ready).length;
  }

  int get blockedCount {
    return components.length - readyCount;
  }

  List<PlatformManagerRecoveryAction> get recoveryActions {
    return components
        .expand((component) => component.recoveryActions)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetId': targetId,
      'probeSource': probeSource,
      'ready': ready,
      'readyCount': readyCount,
      'blockedCount': blockedCount,
      'recoveryActionCount': recoveryActions.length,
      'componentCount': components.length,
      'components': components
          .map((component) => component.toJson())
          .toList(growable: false),
      if (recoveryActions.isNotEmpty)
        'recoveryActions': recoveryActions
            .map((action) => action.toJson())
            .toList(growable: false),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

PlatformManagerHealthProbe _probe(
  String managerKey,
  PlatformManagerProbeReady ready,
) {
  return PlatformManagerHealthProbe(
    managerKey: managerKey,
    ready: ready,
    message: (_, isReady) => isReady
        ? '$managerKey manager probe is ready.'
        : '$managerKey manager probe is blocked.',
    recoveryActions: <PlatformManagerRecoveryAction>[
      PlatformManagerRecoveryAction(
        id: 'platform.$managerKey.open-settings',
        label: 'Open platform settings',
        managerKey: managerKey,
        message: 'Review platform configuration for $managerKey.',
      ),
    ],
  );
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
