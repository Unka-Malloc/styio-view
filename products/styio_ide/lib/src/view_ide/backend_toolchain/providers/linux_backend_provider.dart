import '../../platform/platform_target.dart';
import 'io_backend_provider.dart';

final class LinuxBackendProvider extends IoBackendProvider {
  const LinuxBackendProvider()
    : super(id: 'linux.local', platformTarget: PlatformTarget.linux);
}
