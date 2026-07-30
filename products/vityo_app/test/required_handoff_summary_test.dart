import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/required_handoff_summary.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

void main() {
  test('missing owner contracts produce precise handoffs', () {
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: PlatformTarget.macos,
      projectGraph: _project(),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[],
    );

    expect(
      handoffs
          .where((handoff) => handoff.owner == HandoffOwner.pafio)
          .map((handoff) => handoff.title),
      contains('Publish metadata v1'),
    );
    expect(
      handoffs
          .where((handoff) => handoff.owner == HandoffOwner.styio)
          .map((handoff) => handoff.title),
      containsAll(<String>[
        'Publish language-service machine contract',
        'Publish compile-plan consumer and live execution contract',
        'Publish runtime event stream',
      ]),
    );
  });

  test('invalid metadata reports the Pafio repair boundary', () {
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: PlatformTarget.macos,
      projectGraph: _project(
        failure: const PublishedPayloadFailure(
          command: 'pafio metadata --json',
          detail: 'schema mismatch',
        ),
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        _availableCapabilities,
      ],
    );

    final repair = handoffs.singleWhere(
      (handoff) => handoff.title == 'Repair Pafio metadata v1 payload',
    );
    expect(repair.owner, HandoffOwner.pafio);
    expect(repair.blocking, isTrue);
    expect(repair.detail, contains('schema mismatch'));
  });

  test('available owner contracts need no blocking handoff', () {
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: PlatformTarget.macos,
      projectGraph: _project(
        compiler: const CompilerHandshakeSnapshot(
          binaryPath: 'styio',
          tool: 'styio',
          compilerVersion: '1.0.0',
          channel: 'system',
          variant: 'system',
          capabilities: <String>['compile-plan'],
          supportedContractVersions: <String, List<int>>{
            'compile_plan': <int>[1],
          },
          integrationPhase: 'compile-plan-live',
        ),
        lockState: ProjectLockState.fresh,
        vendorState: ProjectVendorState.present,
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        _availableCapabilities,
      ],
    );

    expect(handoffs.where((handoff) => handoff.blocking), isEmpty);
  });
}

const _availableCapabilities = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cli,
  languageService: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.available,
    detail: 'available',
  ),
  projectGraph: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.available,
    detail: 'metadata v1',
  ),
  execution: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.available,
    detail: 'workflow v1',
  ),
  runtimeEvents: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.available,
    detail: 'runtime-events v1',
  ),
);

ProjectGraphSnapshot _project({
  PublishedPayloadFailure? failure,
  CompilerHandshakeSnapshot? compiler,
  ProjectLockState lockState = ProjectLockState.unknown,
  ProjectVendorState vendorState = ProjectVendorState.unknown,
}) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/pafio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/pafio.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>['/workspace/demo/src/main.styio'],
    toolchain: compiler == null
        ? const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail: 'system Styio unavailable',
          )
        : const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.environment,
            detail: 'system Styio available',
          ),
    lockState: lockState,
    vendorState: vendorState,
    activeCompiler: compiler,
    projectGraphPayloadFailure: failure,
    notes: const <String>[],
  );
}
