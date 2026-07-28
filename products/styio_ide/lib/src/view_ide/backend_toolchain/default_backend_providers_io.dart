import 'backend_provider.dart';
import 'providers/android_backend_provider.dart';
import 'providers/ios_backend_provider.dart';
import 'providers/linux_backend_provider.dart';
import 'providers/macos_backend_provider.dart';
import 'providers/unknown_backend_provider.dart';
import 'providers/windows_backend_provider.dart';

void registerDefaultBackendProviders(BackendProviderRegistry registry) {
  registry
    ..register(const WindowsBackendProvider())
    ..register(const LinuxBackendProvider())
    ..register(const MacosBackendProvider())
    ..register(const AndroidBackendProvider())
    ..register(const IosBackendProvider())
    ..register(const UnknownBackendProvider());
}
