import '../clipboard/clipboard_adapter.dart';
import '../file_system/file_system_adapter.dart';
import '../local_service/local_service_adapter.dart';
import '../network/network_adapter.dart';
import '../notification/notification_adapter.dart';
import '../platform_context/platform_context_model.dart';
import '../process/process_adapter.dart';
import '../pty/pty_adapter.dart';
import '../resource/resource_adapter.dart';
import '../shell/shell_adapter.dart';

class PlatformAdapter {
  const PlatformAdapter(this.context);

  final PlatformContextSnapshot context;

  FileSystemAdapter get fileSystemAdapter {
    return FileSystemAdapter(context.fileSystem);
  }

  ShellAdapter get shellAdapter {
    return ShellAdapter(context.shell);
  }

  ProcessAdapter get processAdapter {
    return ProcessAdapter(context.process);
  }

  ResourceAdapter get resourceAdapter {
    return ResourceAdapter(context.resource);
  }

  NetworkAdapter get networkAdapter {
    return NetworkAdapter(context.network);
  }

  ClipboardAdapter get clipboardAdapter {
    return ClipboardAdapter(context.clipboard);
  }

  NotificationAdapter get notificationAdapter {
    return NotificationAdapter(context.notification);
  }

  LocalServiceAdapter get localServiceAdapter {
    return LocalServiceAdapter(context.localService);
  }

  PtyAdapter get ptyAdapter {
    return PtyAdapter(context.pty);
  }

  PlatformCompatibilitySnapshot adapt() {
    return PlatformCompatibilitySnapshot(
      targetId: context.targetId,
      fileSystem: fileSystemAdapter.adapt(),
      shell: shellAdapter.adapt(),
      process: processAdapter.adapt(),
      resource: resourceAdapter.adapt(),
      network: networkAdapter.adapt(),
      clipboard: clipboardAdapter.adapt(),
      notification: notificationAdapter.adapt(),
      localService: localServiceAdapter.adapt(),
      pty: ptyAdapter.adapt(),
    );
  }
}

class PlatformCompatibilitySnapshot {
  const PlatformCompatibilitySnapshot({
    required this.targetId,
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

  final String targetId;
  final FileSystemCompatibility fileSystem;
  final ShellCompatibility shell;
  final ProcessCompatibility process;
  final ResourceCompatibility resource;
  final NetworkCompatibility network;
  final ClipboardCompatibility clipboard;
  final NotificationCompatibility notification;
  final LocalServiceCompatibility localService;
  final PtyCompatibility pty;

  bool get supportsLinuxDebianArmTarget {
    return fileSystem.isLinuxDebianArm &&
        shell.isLinuxDebianArm &&
        process.isLinuxDebianArm &&
        resource.isLinuxDebianArm &&
        network.isLinuxDebianArm &&
        clipboard.isLinuxDebianArm &&
        notification.isLinuxDebianArm &&
        localService.isLinuxDebianArm &&
        pty.isLinuxDebianArm;
  }
}
