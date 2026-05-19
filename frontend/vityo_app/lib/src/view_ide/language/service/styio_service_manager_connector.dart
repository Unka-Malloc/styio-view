import '../../environment/configuration/environment_variable_configuration.dart';
import '../../toolchain/toolchain_catalog.dart';
import '../../toolchain/toolchain_health_check.dart';
import '../../toolchain/toolchain_manager.dart';
import '../../toolchain/toolchain_resolver.dart';
import 'styio_service_connector.dart';

class ToolchainManagerStyioServiceConnector implements StyioServiceConnector {
  const ToolchainManagerStyioServiceConnector({
    required ToolchainManager manager,
    this.protocol = const StyioCliJsonlProtocol(),
    this.documentMaterializer,
    ToolchainRequirement? requirement,
    this.timeout = const Duration(seconds: 10),
  }) : _manager = manager,
       _requirement = requirement;

  final ToolchainManager _manager;
  final StyioCliJsonlProtocol protocol;
  final StyioServiceDocumentMaterializer? documentMaterializer;
  final ToolchainRequirement? _requirement;
  final Duration timeout;

  Future<ToolchainHealthReport> checkHealth({
    List<String>? probeArguments,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
  }) {
    return _manager.checkHealth(
      kind: ToolchainKind.languageService,
      requirement: _effectiveRequirement(),
      probeArguments: probeArguments,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
  }

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    final catalog = await _manager.loadCatalog();
    final runtime = _manager.runtimeFor(catalog);
    return ToolchainStyioServiceConnector(
      runtime: runtime,
      protocol: protocol,
      documentMaterializer:
          documentMaterializer ??
          StyioServiceDocumentMaterializer(
            fileSystemManager: _manager.platformManagers.fileSystem,
            resourceManager: _manager.platformManagers.resource,
          ),
      requirement: _effectiveRequirement(),
      timeout: timeout,
    ).analyzeDocument(document);
  }

  ToolchainRequirement _effectiveRequirement() {
    return _requirement ??
        ToolchainRequirement(
          kind: ToolchainKind.languageService,
          metadata: <String, Object?>{'contract': protocol.protocolVersion},
        );
  }
}
