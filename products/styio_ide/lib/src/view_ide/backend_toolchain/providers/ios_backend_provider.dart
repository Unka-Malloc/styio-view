import '../../platform/platform_target.dart';
import 'io_backend_provider.dart';

final class IosBackendProvider extends IoBackendProvider {
  const IosBackendProvider()
    : super(id: 'ios.hosted', platformTarget: PlatformTarget.ios);
}
