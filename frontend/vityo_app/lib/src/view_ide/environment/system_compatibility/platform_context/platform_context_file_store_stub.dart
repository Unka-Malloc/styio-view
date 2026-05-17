import 'platform_context_model.dart';
import 'platform_context_store.dart';

class PlatformContextFileStore implements PlatformContextStore {
  const PlatformContextFileStore(this.path);

  final String path;

  @override
  Future<PlatformContextSnapshot?> load() async {
    return null;
  }

  @override
  Future<void> save(PlatformContextSnapshot snapshot) async {
    throw UnsupportedError('Platform context file store is not available.');
  }
}
