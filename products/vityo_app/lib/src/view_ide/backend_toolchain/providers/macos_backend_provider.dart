import '../../platform/platform_target.dart';
import 'io_backend_provider.dart';

final class MacosBackendProvider extends IoBackendProvider {
  const MacosBackendProvider()
    : super(id: 'macos.local', platformTarget: PlatformTarget.macos);
}
