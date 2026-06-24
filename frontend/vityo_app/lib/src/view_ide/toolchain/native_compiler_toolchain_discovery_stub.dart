import '../environment/environment.dart';
import 'toolchain_catalog.dart';

Future<ToolchainCatalog> createPlatformNativeCompilerToolchainCatalog({
  PlatformManagerBundle? platformManagers,
  Map<String, String>? environment,
  Iterable<String> cCompilerCandidatePaths = const <String>[],
  Iterable<String> cxxCompilerCandidatePaths = const <String>[],
  Iterable<String> cmakeCandidatePaths = const <String>[],
  Iterable<String> ninjaCandidatePaths = const <String>[],
  Iterable<String> clangdCandidatePaths = const <String>[],
  Iterable<String> lldbCandidatePaths = const <String>[],
  Iterable<String> gdbCandidatePaths = const <String>[],
  Iterable<String> clangFormatCandidatePaths = const <String>[],
  Iterable<String> clangTidyCandidatePaths = const <String>[],
  Iterable<String> ctestCandidatePaths = const <String>[],
  Future<String?> Function(String executablePath)? clangVersionOutputProbe,
}) async {
  return ToolchainCatalog();
}
