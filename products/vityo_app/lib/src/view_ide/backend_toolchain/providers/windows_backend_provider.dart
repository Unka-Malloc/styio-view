import '../../platform/platform_target.dart';
import 'io_backend_provider.dart';

final class WindowsBackendProvider extends IoBackendProvider {
  const WindowsBackendProvider()
    : super(id: 'windows.local', platformTarget: PlatformTarget.windows);
}
