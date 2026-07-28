import '../clipboard/clipboard_prober.dart';
import '../file_system/file_system_prober.dart';
import '../local_service/local_service_prober.dart';
import '../network/network_prober.dart';
import '../notification/notification_prober.dart';
import '../platform_context/platform_context_model.dart';
import '../process/process_prober.dart';
import '../pty/pty_prober.dart';
import '../resource/resource_prober.dart';
import '../shell/shell_prober.dart';

abstract class PlatformDetector {
  Future<PlatformContextSnapshot> detect({String targetId = 'local'});
}

class ProbingPlatformDetector implements PlatformDetector {
  const ProbingPlatformDetector({
    required FileSystemProber fileSystemProber,
    required ShellProber shellProber,
    required ProcessProber processProber,
    required ResourceProber resourceProber,
    required NetworkProber networkProber,
    required ClipboardProber clipboardProber,
    required NotificationProber notificationProber,
    required LocalServiceProber localServiceProber,
    required PtyProber ptyProber,
  }) : _fileSystemProber = fileSystemProber,
       _shellProber = shellProber,
       _processProber = processProber,
       _resourceProber = resourceProber,
       _networkProber = networkProber,
       _clipboardProber = clipboardProber,
       _notificationProber = notificationProber,
       _localServiceProber = localServiceProber,
       _ptyProber = ptyProber;

  final FileSystemProber _fileSystemProber;
  final ShellProber _shellProber;
  final ProcessProber _processProber;
  final ResourceProber _resourceProber;
  final NetworkProber _networkProber;
  final ClipboardProber _clipboardProber;
  final NotificationProber _notificationProber;
  final LocalServiceProber _localServiceProber;
  final PtyProber _ptyProber;

  @override
  Future<PlatformContextSnapshot> detect({String targetId = 'local'}) async {
    final fileSystem = await _fileSystemProber.probe();
    final shell = await _shellProber.probe();
    final process = await _processProber.probe();
    final resource = await _resourceProber.probe();
    final network = await _networkProber.probe();
    final clipboard = await _clipboardProber.probe();
    final notification = await _notificationProber.probe();
    final localService = await _localServiceProber.probe();
    final pty = await _ptyProber.probe();

    return PlatformContextSnapshot.compose(
      targetId: targetId,
      fileSystem: fileSystem,
      shell: shell,
      process: process,
      resource: resource,
      network: network,
      clipboard: clipboard,
      notification: notification,
      localService: localService,
      pty: pty,
      source: 'prober',
    );
  }
}

class StaticPlatformDetector implements PlatformDetector {
  const StaticPlatformDetector(this.snapshot);

  final PlatformContextSnapshot snapshot;

  @override
  Future<PlatformContextSnapshot> detect({String targetId = 'local'}) async {
    if (targetId == snapshot.targetId) {
      return snapshot;
    }
    return snapshot.copyWith(
      targetId: targetId,
      refreshedAt: DateTime.now().toUtc(),
      source: snapshot.source,
    );
  }
}
