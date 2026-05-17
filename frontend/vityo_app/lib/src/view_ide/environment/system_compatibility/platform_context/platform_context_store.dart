import 'platform_context_model.dart';

abstract class PlatformContextStore {
  Future<PlatformContextSnapshot?> load();

  Future<void> save(PlatformContextSnapshot snapshot);
}

class InMemoryPlatformContextStore implements PlatformContextStore {
  InMemoryPlatformContextStore({PlatformContextSnapshot? initialSnapshot})
    : _snapshot = initialSnapshot;

  PlatformContextSnapshot? _snapshot;

  @override
  Future<PlatformContextSnapshot?> load() async {
    return _snapshot;
  }

  @override
  Future<void> save(PlatformContextSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
