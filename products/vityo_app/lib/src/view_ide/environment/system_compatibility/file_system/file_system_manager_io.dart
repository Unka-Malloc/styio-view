import '../../../../ide/local_service/vityod_client.dart';
import 'file_system_manager.dart';
import 'file_system_prober.dart';
import '../platform_context/platform_context.dart';
import 'file_system_prober_io.dart';
import 'vityod_file_system_manager.dart';

Future<FileSystemManager> createPlatformFileSystemManager({
  FileSystemProber? prober,
  PlatformContextSnapshot? platformContext,
  VityodClient? vityodClient,
  Iterable<String> allowedRoots = const <String>[],
}) async {
  final facts =
      platformContext?.fileSystem ??
      await (prober ?? const LocalFileSystemProber()).probe();
  if (vityodClient == null) {
    return UnsupportedFileSystemManager(facts: facts);
  }
  return VityodFileSystemManager.open(
    facts: facts,
    client: vityodClient,
    allowedRoots: allowedRoots,
  );
}
