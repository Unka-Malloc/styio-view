import '../../platform/platform_target.dart';
import 'io_backend_provider.dart';

final class AndroidBackendProvider extends IoBackendProvider {
  const AndroidBackendProvider()
    : super(id: 'android.hybrid', platformTarget: PlatformTarget.android);
}
