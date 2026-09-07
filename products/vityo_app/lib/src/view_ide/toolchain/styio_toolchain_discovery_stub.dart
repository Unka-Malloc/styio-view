import '../environment/environment.dart';
import 'toolchain_catalog.dart';

Future<ToolchainCatalog> createPlatformStyioLanguageToolchainCatalog({
  required PlatformManagerBundle platformManagers,
  Map<String, String> environment = const <String, String>{},
  Iterable<String> candidatePaths = const <String>[],
}) async {
  return ToolchainCatalog();
}
