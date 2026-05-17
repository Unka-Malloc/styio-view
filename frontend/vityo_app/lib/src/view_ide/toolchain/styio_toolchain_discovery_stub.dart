import '../environment/environment.dart';
import 'toolchain_catalog.dart';

Future<ToolchainCatalog> createPlatformStyioLanguageToolchainCatalog({
  PlatformManagerBundle? platformManagers,
  Map<String, String>? environment,
  Iterable<String> candidatePaths = const <String>[],
}) async {
  return ToolchainCatalog();
}
