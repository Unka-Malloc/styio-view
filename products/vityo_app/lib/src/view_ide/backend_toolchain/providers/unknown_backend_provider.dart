import '../../platform/platform_target.dart';
import 'io_backend_provider.dart';

final class UnknownBackendProvider extends IoBackendProvider {
  const UnknownBackendProvider()
    : super(id: 'unknown.io', platformTarget: PlatformTarget.unknown);
}
