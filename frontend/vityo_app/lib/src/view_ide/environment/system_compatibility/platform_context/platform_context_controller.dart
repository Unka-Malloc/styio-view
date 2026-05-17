import '../clipboard/clipboard_facts.dart';
import '../clipboard/clipboard_prober.dart';
import '../file_system/file_system_facts.dart';
import '../file_system/file_system_prober.dart';
import '../local_service/local_service_facts.dart';
import '../local_service/local_service_prober.dart';
import '../network/network_facts.dart';
import '../network/network_prober.dart';
import '../notification/notification_facts.dart';
import '../notification/notification_prober.dart';
import '../process/process_facts.dart';
import '../process/process_prober.dart';
import '../pty/pty_facts.dart';
import '../pty/pty_prober.dart';
import '../resource/resource_facts.dart';
import '../resource/resource_prober.dart';
import '../shell/shell_facts.dart';
import '../shell/shell_prober.dart';
import '../platform_detector/platform_detector.dart';
import 'platform_context_model.dart';
import 'platform_context_store.dart';

class PlatformContextController {
  PlatformContextController({
    required PlatformContextStore store,
    PlatformDetector? detector,
    FileSystemProber? fileSystemProber,
    ShellProber? shellProber,
    ProcessProber? processProber,
    ResourceProber? resourceProber,
    NetworkProber? networkProber,
    ClipboardProber? clipboardProber,
    NotificationProber? notificationProber,
    LocalServiceProber? localServiceProber,
    PtyProber? ptyProber,
    this.targetId = 'local',
  }) : _store = store,
       _detector =
           detector ??
           ProbingPlatformDetector(
             fileSystemProber: _required(
               fileSystemProber,
               'fileSystemProber',
             ),
             shellProber: _required(shellProber, 'shellProber'),
             processProber: _required(processProber, 'processProber'),
             resourceProber: _required(resourceProber, 'resourceProber'),
             networkProber: _required(networkProber, 'networkProber'),
             clipboardProber: _required(clipboardProber, 'clipboardProber'),
             notificationProber: _required(
               notificationProber,
               'notificationProber',
             ),
             localServiceProber: _required(
               localServiceProber,
               'localServiceProber',
             ),
             ptyProber: _required(ptyProber, 'ptyProber'),
           );

  final PlatformContextStore _store;
  final PlatformDetector _detector;
  final String targetId;

  PlatformContextSnapshot? _currentSnapshot;

  PlatformContextSnapshot? get currentSnapshot => _currentSnapshot;

  Future<PlatformContextSnapshot> load({bool refreshIfMissing = true}) async {
    final loaded = await _store.load();
    if (loaded != null) {
      if (loaded.targetId != targetId) {
        if (!refreshIfMissing) {
          throw StateError(
            'Platform Context target mismatch: expected $targetId, '
            'found ${loaded.targetId}.',
          );
        }
        return refresh();
      }
      _currentSnapshot = loaded;
      return loaded;
    }
    if (!refreshIfMissing) {
      throw StateError('Platform Context is not available.');
    }
    return refresh();
  }

  Future<PlatformContextSnapshot> refresh() async {
    final snapshot = await _detector.detect(targetId: targetId);
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyFileSystemFacts(
    FileSystemFacts facts,
  ) async {
    final base = await load();
    final snapshot = base.copyWith(
      fileSystem: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyShellFacts(ShellFacts facts) async {
    final base = await load();
    final snapshot = base.copyWith(
      shell: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyProcessFacts(ProcessFacts facts) async {
    final base = await load();
    final snapshot = base.copyWith(
      process: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyResourceFacts(ResourceFacts facts) async {
    final base = await load();
    final snapshot = base.copyWith(
      resource: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyNetworkFacts(NetworkFacts facts) async {
    final base = await load();
    final snapshot = base.copyWith(
      network: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyClipboardFacts(
    ClipboardFacts facts,
  ) async {
    final base = await load();
    final snapshot = base.copyWith(
      clipboard: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyNotificationFacts(
    NotificationFacts facts,
  ) async {
    final base = await load();
    final snapshot = base.copyWith(
      notification: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyLocalServiceFacts(
    LocalServiceFacts facts,
  ) async {
    final base = await load();
    final snapshot = base.copyWith(
      localService: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyPtyFacts(PtyFacts facts) async {
    final base = await load();
    final snapshot = base.copyWith(
      pty: facts,
      refreshedAt: DateTime.now().toUtc(),
      source: 'runtime',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<PlatformContextSnapshot> applyOverrides(
    Map<String, Object?> overrides,
  ) async {
    final base = await load();
    final snapshot = base.copyWith(
      overrides: <String, Object?>{
        ...base.overrides,
        ...overrides,
      },
      refreshedAt: DateTime.now().toUtc(),
      source: 'override',
    );
    await save(snapshot);
    return snapshot;
  }

  Future<void> save(PlatformContextSnapshot snapshot) async {
    _currentSnapshot = snapshot;
    await _store.save(snapshot);
  }

  static T _required<T>(T? value, String name) {
    if (value == null) {
      throw ArgumentError.notNull(name);
    }
    return value;
  }
}
