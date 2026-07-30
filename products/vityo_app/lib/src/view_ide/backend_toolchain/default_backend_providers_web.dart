import 'backend_provider.dart';
import 'providers/web_backend_provider.dart';

void registerDefaultBackendProviders(BackendProviderRegistry registry) {
  registry.register(const WebBackendProvider());
}
