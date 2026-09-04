import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/services/observable_topology/observable_topology.dart';

void main() {
  CompilerHandshakeSnapshot handshake({
    List<int> schemaVersions = const <int>[1],
    List<String> capabilities = kObservableRequiredCapabilities,
    String variant = 'full',
  }) {
    return CompilerHandshakeSnapshot(
      binaryPath: 'styio',
      tool: 'styio',
      compilerVersion: '0.0.1',
      channel: 'nightly',
      variant: variant,
      capabilities: const <String>['compile-plan'],
      supportedContractVersions: const <String, List<int>>{
        'compile_plan': <int>[1],
      },
      integrationPhase: 'compile-plan-live',
      observableStaticSnapshotSchemaVersions: schemaVersions,
      observableStaticSnapshotCapabilities: capabilities,
    );
  }

  ObservableNegotiationDecision decide({
    CompilerHandshakeSnapshot? compiler,
    bool pafioAvailable = true,
    bool ioPlatform = true,
    String? manifestPath = 'Styio.toml',
    bool hosted = false,
  }) {
    return negotiateObservableCapability(
      ObservableNegotiationInput(
        ioPlatform: ioPlatform,
        pafioAvailable: pafioAvailable,
        compiler: compiler,
        manifestPath: manifestPath,
        hosted: hosted,
      ),
    );
  }

  test('negotiation matrix covers toolchain, schema and capability failures', () {
    final missingStyio = decide(compiler: null);
    expect(missingStyio.accepted, isFalse);
    expect(missingStyio.availability, ObservableAvailability.unavailable);
    expect(missingStyio.reason, ObservableReasonCode.noToolchain);
    expect(shouldDecodeObservableSnapshot(missingStyio), isFalse);

    final missingPafio = decide(compiler: handshake(), pafioAvailable: false);
    expect(missingPafio.availability, ObservableAvailability.unavailable);
    expect(missingPafio.reason, ObservableReasonCode.noToolchain);
    expect(shouldDecodeObservableSnapshot(missingPafio), isFalse);

    final nano = decide(
      compiler: handshake(schemaVersions: const <int>[], variant: 'nano'),
    );
    expect(nano.availability, ObservableAvailability.unsupported);
    expect(nano.reason, ObservableReasonCode.unsupportedSchemaVersion);
    expect(shouldDecodeObservableSnapshot(nano), isFalse);

    final older = decide(compiler: handshake(schemaVersions: const <int>[0]));
    expect(older.reason, ObservableReasonCode.unsupportedSchemaVersion);
    expect(shouldDecodeObservableSnapshot(older), isFalse);

    final missingCapability = decide(
      compiler: handshake(
        capabilities: const <String>['static-topology-nodes'],
      ),
    );
    expect(missingCapability.reason, ObservableReasonCode.missingCapability);
    expect(shouldDecodeObservableSnapshot(missingCapability), isFalse);

    final success = decide(compiler: handshake());
    expect(success.accepted, isTrue);
    expect(shouldDecodeObservableSnapshot(success), isTrue);

    final again = decide(compiler: handshake());
    expect(again.accepted, success.accepted);
    expect(again.reason, success.reason);
  });
}
