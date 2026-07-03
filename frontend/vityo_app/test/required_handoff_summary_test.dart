import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/integration/adapter_contracts.dart';
import 'package:vityo_app/src/integration/project_graph_contract.dart';
import 'package:vityo_app/src/integration/required_handoff_summary.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('summarizes styio and pafio handoffs for preview-only project route', () {
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: PlatformTarget.macos,
      projectGraph: const ProjectGraphSnapshot(
        id: 'demo',
        title: 'Demo',
        kind: ProjectKind.package,
        workspaceRoot: '/workspace/demo',
        workspaceMembers: <String>[],
        manifestPath: '/workspace/demo/pafio.toml',
        lockfilePath: '/workspace/demo/pafio.lock',
        toolchainPinPath: '/workspace/demo/pafio-toolchain.toml',
        dependencies: <ProjectDependencySnapshot>[],
        packages: <ProjectPackageSnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>['/workspace/demo/src/main.styio'],
        toolchain: ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.unknown,
          detail: 'unknown',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.unknown,
        activeCompiler: CompilerHandshakeSnapshot(
          binaryPath: '/toolchains/styio/bin/styio',
          tool: 'styio',
          compilerVersion: '0.1.0',
          channel: 'stable',
          variant: 'desktop',
          capabilities: <String>['machine_info_json'],
          supportedContractVersions: <String, List<int>>{
            'machine_info': <int>[1],
          },
          integrationPhase: 'bootstrap-single-file',
        ),
        notes: <String>[],
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cli,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'partial',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'partial',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'preview only',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'not published',
          ),
        ),
      ],
    );

    expect(handoffs, isNotEmpty);
    expect(
      handoffs.any(
        (handoff) =>
            handoff.owner == HandoffOwner.styio &&
            handoff.title.contains('language-service'),
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) =>
            handoff.owner == HandoffOwner.styio &&
            handoff.title.contains('compile-plan consumer'),
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) => handoff.title == 'Publish runtime event stream',
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) =>
            handoff.title == 'Publish runtime event stream' &&
            handoff.detail.contains('ordered runtime event envelopes'),
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) =>
            handoff.owner == HandoffOwner.pafio &&
            handoff.title.contains('project graph'),
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) =>
            handoff.owner == HandoffOwner.pafio &&
            handoff.title.contains('toolchain'),
      ),
      isTrue,
    );
  });

  test(
    'requests runtime event stream handoff when runtime events are unavailable',
    () {
      final handoffs = summarizeRequiredHandoffs(
        platformTarget: PlatformTarget.macos,
        projectGraph: const ProjectGraphSnapshot(
          id: 'runtime-events',
          title: 'Runtime Events',
          kind: ProjectKind.package,
          workspaceRoot: '/workspace/runtime-events',
          workspaceMembers: <String>[],
          manifestPath: '/workspace/runtime-events/pafio.toml',
          dependencies: <ProjectDependencySnapshot>[],
          packages: <ProjectPackageSnapshot>[],
          targets: <ProjectTargetDescriptor>[],
          editorFiles: <String>['/workspace/runtime-events/src/main.styio'],
          toolchain: ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unknown,
            detail: 'unknown',
          ),
          lockState: ProjectLockState.fresh,
          vendorState: ProjectVendorState.present,
          notes: <String>[],
        ),
        adapterCapabilities: const <AdapterCapabilitySnapshot>[
          AdapterCapabilitySnapshot(
            adapterKind: AdapterKind.cli,
            languageService: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            projectGraph: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            execution: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            runtimeEvents: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.unavailable,
              detail: 'not published',
            ),
          ),
        ],
      );

      final runtimeHandoff = handoffs.firstWhere(
        (handoff) => handoff.title == 'Publish runtime event stream',
        orElse: () => const RequiredHandoff(
          owner: HandoffOwner.styio,
          title: 'missing',
          detail: '',
          docPath: '',
        ),
      );

      expect(runtimeHandoff.title, equals('Publish runtime event stream'));
      expect(
        runtimeHandoff.detail.contains('ordered runtime event envelopes'),
        isTrue,
      );
      final unresolvedMarker =
          'not '
          'yet';
      expect(runtimeHandoff.detail.contains(unresolvedMarker), isFalse);
    },
  );

  test(
    'does not request live compile-plan handoff for iOS cloud-only route',
    () {
      final handoffs = summarizeRequiredHandoffs(
        platformTarget: PlatformTarget.ios,
        projectGraph: const ProjectGraphSnapshot(
          id: 'cloud-demo',
          title: 'Cloud Demo',
          kind: ProjectKind.hosted,
          workspaceRoot: '/workspace/cloud-demo',
          workspaceMembers: <String>[],
          manifestPath: '/workspace/cloud-demo/pafio.toml',
          dependencies: <ProjectDependencySnapshot>[],
          packages: <ProjectPackageSnapshot>[],
          targets: <ProjectTargetDescriptor>[],
          editorFiles: <String>['/workspace/cloud-demo/src/main.styio'],
          toolchain: ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.projectPin,
            detail: 'project pin',
          ),
          lockState: ProjectLockState.fresh,
          vendorState: ProjectVendorState.present,
          notes: <String>[],
        ),
        adapterCapabilities: const <AdapterCapabilitySnapshot>[
          AdapterCapabilitySnapshot(
            adapterKind: AdapterKind.cli,
            languageService: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.partial,
              detail: 'partial',
            ),
            projectGraph: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.partial,
              detail: 'partial',
            ),
            execution: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.unavailable,
              detail: 'cloud only',
            ),
            runtimeEvents: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.unavailable,
              detail: 'cloud only',
            ),
          ),
        ],
      );

      expect(
        handoffs.any(
          (handoff) => handoff.title.contains('compile-plan consumer'),
        ),
        isFalse,
      );
    },
  );

  test(
    'accepts hosted project graph and runtime event capabilities from cloud adapter',
    () {
      final handoffs = summarizeRequiredHandoffs(
        platformTarget: PlatformTarget.ios,
        projectGraph: ProjectGraphSnapshot(
          id: 'hosted-runtime',
          title: 'Hosted Runtime',
          kind: ProjectKind.hosted,
          workspaceRoot: '/workspace/hosted-runtime',
          workspaceMembers: const <String>[],
          manifestPath: '/workspace/hosted-runtime/pafio.toml',
          dependencies: const <ProjectDependencySnapshot>[],
          packages: const <ProjectPackageSnapshot>[],
          targets: const <ProjectTargetDescriptor>[],
          editorFiles: const <String>[
            '/workspace/hosted-runtime/src/main.styio',
          ],
          toolchain: const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.managedCurrent,
            detail: 'hosted toolchain',
          ),
          lockState: ProjectLockState.fresh,
          vendorState: ProjectVendorState.present,
          toolchainEnvironment: const ToolchainEnvironmentSnapshot(
            schemaVersion: 1,
            toolchain: ToolchainStatusSnapshot(
              source: ToolchainResolutionSource.managedCurrent,
              detail: 'hosted toolchain',
            ),
            managedToolchains: ManagedToolchainStateSnapshot(),
          ),
          sourceState: const ProjectSourceStateSnapshot(
            schemaVersion: 1,
            pafioHome: '/workspace/.pafio',
          ),
          hostedWorkspace: HostedWorkspaceRecordSnapshot(
            workspaceId: 'hosted-runtime',
            schemaVersion: '1',
            ownerRef: 'Vityo',
            status: HostedWorkspaceStatus.active,
            entryUrl: 'https://hosted.example/workspaces/hosted-runtime',
            createdAt: DateTime.utc(2026, 4, 21),
            lastActiveAt: DateTime.utc(2026, 4, 21, 0, 1),
            retentionDays: 7,
            exportState: HostedWorkspaceExportState.notRequested,
          ),
          notes: const <String>[],
        ),
        adapterCapabilities: const <AdapterCapabilitySnapshot>[
          AdapterCapabilitySnapshot(
            adapterKind: AdapterKind.cloud,
            languageService: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.unavailable,
              detail: 'cloud runtime events do not provide language service',
            ),
            projectGraph: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'hosted project graph is available',
              supportedContractVersions: <int>[1],
            ),
            execution: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'hosted execution is available',
              supportedContractVersions: <int>[1],
            ),
            runtimeEvents: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'hosted runtime events are read from execution envelopes',
              supportedContractVersions: <int>[1],
            ),
          ),
        ],
      );

      expect(
        handoffs.any(
          (handoff) => handoff.title == 'Publish project graph success payload',
        ),
        isFalse,
      );
      expect(
        handoffs.any(
          (handoff) => handoff.title == 'Publish runtime event stream',
        ),
        isFalse,
      );
    },
  );

  test(
    'does not request toolchain state handoff once payload is published',
    () {
      final handoffs = summarizeRequiredHandoffs(
        platformTarget: PlatformTarget.macos,
        projectGraph: const ProjectGraphSnapshot(
          id: 'demo-env',
          title: 'Demo Env',
          kind: ProjectKind.package,
          workspaceRoot: '/workspace/demo-env',
          workspaceMembers: <String>[],
          manifestPath: '/workspace/demo-env/pafio.toml',
          dependencies: <ProjectDependencySnapshot>[],
          packages: <ProjectPackageSnapshot>[],
          targets: <ProjectTargetDescriptor>[],
          editorFiles: <String>['/workspace/demo-env/src/main.styio'],
          toolchain: ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unknown,
            detail: 'unknown',
          ),
          lockState: ProjectLockState.fresh,
          vendorState: ProjectVendorState.present,
          toolchainEnvironment: ToolchainEnvironmentSnapshot(
            schemaVersion: 1,
            toolchain: ToolchainStatusSnapshot(
              source: ToolchainResolutionSource.managedCurrent,
              detail: 'managed current',
            ),
            managedToolchains: ManagedToolchainStateSnapshot(),
          ),
          sourceState: ProjectSourceStateSnapshot(
            schemaVersion: 1,
            pafioHome: '/workspace/.pafio',
          ),
          notes: <String>[],
        ),
        adapterCapabilities: const <AdapterCapabilitySnapshot>[
          AdapterCapabilitySnapshot(
            adapterKind: AdapterKind.cli,
            languageService: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.partial,
              detail: 'partial',
            ),
            projectGraph: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            execution: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            runtimeEvents: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.unavailable,
              detail: 'not published',
            ),
          ),
        ],
      );

      expect(
        handoffs.any(
          (handoff) => handoff.title.contains('toolchain and registry state'),
        ),
        isFalse,
      );
      expect(
        handoffs.any(
          (handoff) =>
              handoff.title.contains('dependency source and cache state'),
        ),
        isFalse,
      );
    },
  );

  test(
    'requests dependency source and cache state until payload is published',
    () {
      final handoffs = summarizeRequiredHandoffs(
        platformTarget: PlatformTarget.macos,
        projectGraph: const ProjectGraphSnapshot(
          id: 'demo-cache',
          title: 'Demo Cache',
          kind: ProjectKind.package,
          workspaceRoot: '/workspace/demo-cache',
          workspaceMembers: <String>[],
          manifestPath: '/workspace/demo-cache/pafio.toml',
          dependencies: <ProjectDependencySnapshot>[],
          packages: <ProjectPackageSnapshot>[],
          targets: <ProjectTargetDescriptor>[],
          editorFiles: <String>['/workspace/demo-cache/src/main.styio'],
          toolchain: ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.managedCurrent,
            detail: 'managed current',
          ),
          lockState: ProjectLockState.fresh,
          vendorState: ProjectVendorState.present,
          toolchainEnvironment: ToolchainEnvironmentSnapshot(
            schemaVersion: 1,
            toolchain: ToolchainStatusSnapshot(
              source: ToolchainResolutionSource.managedCurrent,
              detail: 'managed current',
            ),
            managedToolchains: ManagedToolchainStateSnapshot(),
          ),
          notes: <String>[],
        ),
        adapterCapabilities: const <AdapterCapabilitySnapshot>[
          AdapterCapabilitySnapshot(
            adapterKind: AdapterKind.cli,
            languageService: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.partial,
              detail: 'partial',
            ),
            projectGraph: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            execution: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.available,
              detail: 'available',
            ),
            runtimeEvents: AdapterEndpointCapability(
              level: AdapterCapabilityLevel.unavailable,
              detail: 'not published',
            ),
          ),
        ],
      );

      expect(
        handoffs.any(
          (handoff) =>
              handoff.title.contains('dependency source and cache state'),
        ),
        isTrue,
      );
    },
  );

  test('requests repair handoffs when published pafio payloads fail', () {
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: PlatformTarget.macos,
      projectGraph: const ProjectGraphSnapshot(
        id: 'demo-broken',
        title: 'Demo Broken',
        kind: ProjectKind.package,
        workspaceRoot: '/workspace/demo-broken',
        workspaceMembers: <String>[],
        manifestPath: '/workspace/demo-broken/pafio.toml',
        dependencies: <ProjectDependencySnapshot>[],
        packages: <ProjectPackageSnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>['/workspace/demo-broken/src/main.styio'],
        toolchain: ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.projectPin,
          detail: 'fallback project toolchain',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.unknown,
        projectGraphPayloadFailure: PublishedPayloadFailure(
          command: 'pafio project-graph --json',
          detail: 'Published project graph payload emitted invalid JSON.',
        ),
        toolchainStatePayloadFailure: PublishedPayloadFailure(
          command: 'pafio tool status --json',
          detail: 'Published toolchain-state payload emitted invalid JSON.',
        ),
        notes: <String>[],
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cli,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'partial',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'published payloads are currently broken',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'available',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'not published',
          ),
        ),
      ],
    );

    expect(
      handoffs.any(
        (handoff) => handoff.title == 'Repair published project graph payload',
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) =>
            handoff.title == 'Repair published toolchain and registry state',
      ),
      isTrue,
    );
    expect(
      handoffs.any(
        (handoff) => handoff.title == 'Publish project graph success payload',
      ),
      isFalse,
    );
    expect(
      handoffs.any(
        (handoff) => handoff.title == 'Publish toolchain and registry state',
      ),
      isFalse,
    );
  });
}
