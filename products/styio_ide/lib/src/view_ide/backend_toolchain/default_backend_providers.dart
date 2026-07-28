import 'backend_provider.dart';
import 'default_backend_providers_web.dart'
    if (dart.library.io) 'default_backend_providers_io.dart'
    as platform_catalog;

BackendProviderRegistry createDefaultBackendProviderRegistry() {
  final registry = BackendProviderRegistry();
  platform_catalog.registerDefaultBackendProviders(registry);
  return registry;
}
