import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_route_summary.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('iOS route explains cloud-only execution and disables local JIT', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.ios,
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/ios-demo',
        activeFilePath: '/workspace/ios-demo/main.styio',
        title: 'iOS cloud-only',
        notes: const <String>[],
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cloud,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'cloud language unavailable',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'cloud project graph unavailable',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'cloud execution unavailable',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'cloud runtime unavailable',
          ),
        ),
      ],
    );

    expect(summary.title, 'Cloud-only by policy');
    expect(summary.primaryAdapterKind, AdapterKind.cloud);
    expect(summary.previewOnly, isTrue);
    expect(summary.body, contains('Local CLI and FFI execution stay disabled'));
    expect(summary.jitRoute.title, 'JIT disabled by iOS policy');
    expect(summary.jitRoute.blocked, isTrue);
  });

  test('iOS cloud route becomes live when cloud execution is available', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.ios,
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/ios-live',
        activeFilePath: '/workspace/ios-live/main.styio',
        title: 'iOS cloud live',
        notes: const <String>[],
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cloud,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'cloud language available',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'cloud project graph available',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'cloud execution available',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'cloud runtime available',
          ),
        ),
      ],
    );

    expect(summary.title, 'Cloud-only by policy');
    expect(summary.previewOnly, isFalse);
    expect(summary.body, contains('hosted control plane is live'));
  });

  test('scratch project prefers local CLI route when compiler is resolved', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.macos,
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: '/workspace/demo/scratch/main.styio',
        title: 'Scratch',
        activeCompiler: const CompilerHandshakeSnapshot(
          binaryPath: '/toolchains/styio/bin/styio',
          tool: 'styio',
          compilerVersion: '0.1.0',
          channel: 'stable',
          variant: 'desktop',
          capabilities: <String>['machine_info_json', 'single_file_entry'],
          supportedContractVersions: <String, List<int>>{
            'machine_info': <int>[1],
          },
          integrationPhase: 'bootstrap-single-file',
        ),
        notes: const <String>['scratch route'],
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cli,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'partial',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'n/a',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'single-file only',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'n/a',
          ),
        ),
      ],
    );

    expect(summary.title, 'Scratch single-file route');
    expect(summary.primaryAdapterKind, AdapterKind.cli);
    expect(summary.previewOnly, isFalse);
  });

  test('project route stays preview-only without compile-plan consumer', () {
    final summary = summarizeExecutionRoute(
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
          source: ToolchainResolutionSource.projectPin,
          detail: 'project pin',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.present,
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
            detail: 'n/a',
          ),
        ),
      ],
    );

    expect(summary.title, 'Project route preview-only');
    expect(summary.previewOnly, isTrue);
  });

  test('route gate blocks preview-only workflow routes', () {
    final gate = evaluateExecutionRouteGate(
      platformTarget: PlatformTarget.macos,
      projectGraph: _packageGraph(),
      adapterCapabilities: _capabilities(
        cliExecution: AdapterCapabilityLevel.partial,
      ),
    );

    expect(gate.allowed, isFalse);
    expect(gate.summary.title, 'Project route preview-only');
    expect(gate.blockedReason, contains('build/run/test stays blocked'));
  });

  test(
    'route gate blocks compile-plan project when adapter is unavailable',
    () {
      final gate = evaluateExecutionRouteGate(
        platformTarget: PlatformTarget.macos,
        projectGraph: _packageGraphWithCompilePlan(),
        adapterCapabilities: _capabilities(
          cliExecution: AdapterCapabilityLevel.unavailable,
        ),
      );

      expect(gate.allowed, isFalse);
      expect(gate.summary.title, 'Project route blocked by adapter');
      expect(gate.blockedReason, contains('no CLI execution adapter'));
    },
  );

  test('project route is live when compile-plan consumer is advertised', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.macos,
      projectGraph: const ProjectGraphSnapshot(
        id: 'demo-live',
        title: 'Demo Live',
        kind: ProjectKind.package,
        workspaceRoot: '/workspace/demo-live',
        workspaceMembers: <String>[],
        manifestPath: '/workspace/demo-live/pafio.toml',
        lockfilePath: '/workspace/demo-live/pafio.lock',
        toolchainPinPath: '/workspace/demo-live/pafio-toolchain.toml',
        dependencies: <ProjectDependencySnapshot>[],
        packages: <ProjectPackageSnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>['/workspace/demo-live/src/main.styio'],
        toolchain: ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.projectPin,
          detail: 'project pin',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.present,
        activeCompiler: CompilerHandshakeSnapshot(
          binaryPath: '/toolchains/styio/bin/styio',
          tool: 'styio',
          compilerVersion: '0.1.0',
          channel: 'stable',
          variant: 'desktop',
          capabilities: <String>[
            'machine_info_json',
            'jsonl_diagnostics',
            'single_file_entry',
          ],
          supportedContractVersions: <String, List<int>>{
            'machine_info': <int>[1],
            'compile_plan': <int>[1],
          },
          integrationPhase: 'compile-plan-live',
          featureFlags: <String, bool>{'compile_plan_consumer': true},
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
            level: AdapterCapabilityLevel.available,
            detail: 'live compile-plan handoff',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'n/a',
          ),
        ),
      ],
    );

    expect(summary.title, 'Project route live through pafio');
    expect(summary.previewOnly, isFalse);
  });

  test('project JIT route stays blocked without a published JIT contract', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.macos,
      routeIntent: ExecutionRouteIntent.jit,
      projectGraph: const ProjectGraphSnapshot(
        id: 'demo-jit',
        title: 'Demo JIT',
        kind: ProjectKind.package,
        workspaceRoot: '/workspace/demo-jit',
        workspaceMembers: <String>[],
        manifestPath: '/workspace/demo-jit/pafio.toml',
        lockfilePath: '/workspace/demo-jit/pafio.lock',
        toolchainPinPath: '/workspace/demo-jit/pafio-toolchain.toml',
        dependencies: <ProjectDependencySnapshot>[],
        packages: <ProjectPackageSnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>['/workspace/demo-jit/src/main.styio'],
        toolchain: ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.projectPin,
          detail: 'project pin',
        ),
        lockState: ProjectLockState.unknown,
        vendorState: ProjectVendorState.present,
        activeCompiler: CompilerHandshakeSnapshot(
          binaryPath: '/toolchains/styio/bin/styio',
          tool: 'styio',
          compilerVersion: '0.1.0',
          channel: 'stable',
          variant: 'desktop',
          capabilities: <String>[
            'machine_info_json',
            'jsonl_diagnostics',
            'single_file_entry',
          ],
          supportedContractVersions: <String, List<int>>{
            'machine_info': <int>[1],
            'compile_plan': <int>[1],
          },
          integrationPhase: 'compile-plan-live',
          featureFlags: <String, bool>{'compile_plan_consumer': true},
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
            level: AdapterCapabilityLevel.available,
            detail: 'live compile-plan handoff',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.unavailable,
            detail: 'n/a',
          ),
        ),
      ],
    );

    expect(summary.title, 'JIT route blocked by missing compiler contract');
    expect(summary.primaryAdapterKind, AdapterKind.cli);
    expect(summary.previewOnly, isTrue);
    expect(summary.body, contains('has not advertised a JIT contract'));
  });

  test('hosted web route is live once cloud project workflow is published', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.web,
      projectGraph: ProjectGraphSnapshot(
        id: 'hosted-demo',
        title: 'Hosted Demo',
        kind: ProjectKind.hosted,
        workspaceRoot: '/workspace/hosted-demo',
        workspaceMembers: <String>[],
        manifestPath: '/workspace/hosted-demo/pafio.toml',
        dependencies: <ProjectDependencySnapshot>[],
        packages: <ProjectPackageSnapshot>[],
        targets: <ProjectTargetDescriptor>[],
        editorFiles: <String>['/workspace/hosted-demo/src/main.styio'],
        toolchain: const ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.projectPin,
          detail: 'hosted pin',
        ),
        lockState: ProjectLockState.fresh,
        vendorState: ProjectVendorState.present,
        hostedWorkspace: HostedWorkspaceRecordSnapshot(
          workspaceId: 'hosted-demo',
          schemaVersion: '1',
          ownerRef: 'Vityo',
          status: HostedWorkspaceStatus.active,
          entryUrl: 'https://hosted.test/workspaces/hosted-demo',
          createdAt: DateTime.utc(2026, 4, 18),
          lastActiveAt: DateTime.utc(2026, 4, 18, 1),
          retentionDays: 7,
          exportState: HostedWorkspaceExportState.notRequested,
        ),
        notes: <String>[],
      ),
      adapterCapabilities: const <AdapterCapabilitySnapshot>[
        AdapterCapabilitySnapshot(
          adapterKind: AdapterKind.cloud,
          languageService: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.partial,
            detail: 'partial',
          ),
          projectGraph: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'hosted project graph',
          ),
          execution: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'hosted execution',
          ),
          runtimeEvents: AdapterEndpointCapability(
            level: AdapterCapabilityLevel.available,
            detail: 'hosted runtime events',
          ),
        ),
      ],
    );

    expect(summary.title, 'Hosted project route');
    expect(summary.primaryAdapterKind, AdapterKind.cloud);
    expect(summary.previewOnly, isFalse);
  });

  test('jit route stays blocked until a local adapter publishes support', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.macos,
      projectGraph: _packageGraph(),
      adapterCapabilities: _capabilities(
        cliExecution: AdapterCapabilityLevel.partial,
      ),
      routeIntent: ExecutionRouteIntent.jit,
    );

    expect(summary.title, 'JIT route blocked by missing compiler contract');
    expect(summary.primaryAdapterKind, AdapterKind.cli);
    expect(summary.previewOnly, isTrue);
    expect(summary.jitRoute.blocked, isTrue);
  });

  test(
    'jit route is live when the active compiler advertises a jit contract',
    () {
      final projectGraph = _packageGraph(jitReady: true);
      final summary = summarizeExecutionRoute(
        platformTarget: PlatformTarget.macos,
        projectGraph: projectGraph,
        adapterCapabilities: _capabilities(
          cliExecution: AdapterCapabilityLevel.available,
        ),
        routeIntent: ExecutionRouteIntent.jit,
      );

      expect(projectGraph.jitRouteAdvertised, isTrue);
      expect(summary.title, 'JIT route live through local CLI');
      expect(summary.primaryAdapterKind, AdapterKind.cli);
      expect(summary.previewOnly, isFalse);
      expect(summary.jitRoute.blocked, isFalse);
    },
  );

  test('android workflow remains local-first while cloud fallback is live', () {
    final summary = summarizeExecutionRoute(
      platformTarget: PlatformTarget.android,
      projectGraph: _packageGraph(),
      adapterCapabilities: _capabilities(
        cliExecution: AdapterCapabilityLevel.partial,
        cloudExecution: AdapterCapabilityLevel.available,
      ),
    );

    expect(summary.title, 'Android local-first execution');
    expect(summary.primaryAdapterKind, AdapterKind.cli);
    expect(summary.previewOnly, isFalse);
    expect(summary.body, contains('local CLI execution is active'));
    expect(summary.body, contains('Cloud is available'));
    expect(
      summary.jitRoute.title,
      'Android JIT route pending local compiler support',
    );
    expect(summary.jitRoute.blocked, isTrue);
  });

  test('backend route selection normalizes live local CLI route', () {
    final selection = selectBackendExecutionRoute(
      platformTarget: PlatformTarget.macos,
      projectGraph: _packageGraphWithCompilePlan(),
      adapterCapabilities: _capabilities(
        cliExecution: AdapterCapabilityLevel.available,
      ),
    );

    expect(selection.routeKind, BackendExecutionRouteKind.localCli);
    expect(selection.adapterKind, AdapterKind.cli);
    expect(selection.allowed, isTrue);
    expect(selection.toJson()['routeKind'], 'local-cli');
  });

  test('backend route selection normalizes hosted route', () {
    final selection = selectBackendExecutionRoute(
      platformTarget: PlatformTarget.web,
      projectGraph: ProjectGraphSnapshot(
        id: 'hosted-selection',
        title: 'Hosted Selection',
        kind: ProjectKind.hosted,
        workspaceRoot: '/workspace/hosted-selection',
        workspaceMembers: const <String>[],
        manifestPath: '/workspace/hosted-selection/pafio.toml',
        dependencies: const <ProjectDependencySnapshot>[],
        packages: const <ProjectPackageSnapshot>[],
        targets: const <ProjectTargetDescriptor>[],
        editorFiles: const <String>['/workspace/hosted-selection/main.styio'],
        toolchain: const ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.projectPin,
          detail: 'hosted pin',
        ),
        lockState: ProjectLockState.fresh,
        vendorState: ProjectVendorState.present,
        hostedWorkspace: HostedWorkspaceRecordSnapshot(
          workspaceId: 'hosted-selection',
          schemaVersion: '1',
          ownerRef: 'Vityo',
          status: HostedWorkspaceStatus.active,
          entryUrl: 'https://hosted.test/workspaces/hosted-selection',
          createdAt: DateTime.utc(2026, 4, 18),
          lastActiveAt: DateTime.utc(2026, 4, 18, 1),
          retentionDays: 7,
          exportState: HostedWorkspaceExportState.notRequested,
        ),
        notes: const <String>[],
      ),
      adapterCapabilities: _capabilities(
        cloudExecution: AdapterCapabilityLevel.available,
      ),
    );

    expect(selection.routeKind, BackendExecutionRouteKind.hosted);
    expect(selection.adapterKind, AdapterKind.cloud);
    expect(selection.allowed, isTrue);
    expect(selection.toJson()['routeKind'], 'hosted');
  });

  test('backend route selection normalizes blocked route', () {
    final selection = selectBackendExecutionRoute(
      platformTarget: PlatformTarget.macos,
      projectGraph: _packageGraph(),
      adapterCapabilities: _capabilities(
        cliExecution: AdapterCapabilityLevel.partial,
      ),
    );

    expect(selection.routeKind, BackendExecutionRouteKind.blocked);
    expect(selection.adapterKind, AdapterKind.cli);
    expect(selection.allowed, isFalse);
    expect(selection.blockedReason, contains('build/run/test stays blocked'));
    expect(selection.toJson()['routeKind'], 'blocked');
  });
}

ProjectGraphSnapshot _packageGraph({bool jitReady = false}) {
  return ProjectGraphSnapshot(
    id: jitReady ? 'demo-jit' : 'demo-route',
    title: jitReady ? 'Demo JIT' : 'Demo Route',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo-route',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo-route/pafio.toml',
    dependencies: const <ProjectDependencySnapshot>[],
    packages: const <ProjectPackageSnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>['/workspace/demo-route/src/main.styio'],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'project pin',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    activeCompiler: CompilerHandshakeSnapshot(
      binaryPath: '/toolchains/styio/bin/styio',
      tool: 'styio',
      compilerVersion: '0.1.0',
      channel: 'stable',
      variant: 'desktop',
      capabilities: const <String>['machine_info_json'],
      supportedContractVersions: <String, List<int>>{
        'machine_info': const <int>[1],
        if (jitReady) 'jit_route': const <int>[1],
      },
      integrationPhase: jitReady ? 'jit-live' : 'bootstrap-single-file',
    ),
    notes: const <String>[],
  );
}

ProjectGraphSnapshot _packageGraphWithCompilePlan() {
  return const ProjectGraphSnapshot(
    id: 'demo-compile-plan',
    title: 'Demo Compile Plan',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo-compile-plan',
    workspaceMembers: <String>[],
    manifestPath: '/workspace/demo-compile-plan/pafio.toml',
    dependencies: <ProjectDependencySnapshot>[],
    packages: <ProjectPackageSnapshot>[],
    targets: <ProjectTargetDescriptor>[],
    editorFiles: <String>['/workspace/demo-compile-plan/src/main.styio'],
    toolchain: ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'project pin',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    activeCompiler: CompilerHandshakeSnapshot(
      binaryPath: '/toolchains/styio/bin/styio',
      tool: 'styio',
      compilerVersion: '0.1.0',
      channel: 'stable',
      variant: 'desktop',
      capabilities: <String>[
        'machine_info_json',
        'jsonl_diagnostics',
        'single_file_entry',
      ],
      supportedContractVersions: <String, List<int>>{
        'machine_info': <int>[1],
        'compile_plan': <int>[1],
      },
      integrationPhase: 'compile-plan-live',
      featureFlags: <String, bool>{'compile_plan_consumer': true},
    ),
    notes: <String>[],
  );
}

List<AdapterCapabilitySnapshot> _capabilities({
  AdapterCapabilityLevel cliExecution = AdapterCapabilityLevel.unavailable,
  AdapterCapabilityLevel cloudExecution = AdapterCapabilityLevel.unavailable,
  AdapterCapabilityLevel ffiExecution = AdapterCapabilityLevel.unavailable,
}) {
  return <AdapterCapabilitySnapshot>[
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cli,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'partial',
      ),
      projectGraph: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'partial',
      ),
      execution: AdapterEndpointCapability(
        level: cliExecution,
        detail: 'cli execution',
      ),
      runtimeEvents: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'runtime events not used',
      ),
    ),
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cloud,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'not used',
      ),
      projectGraph: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'cloud project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'cloud execution',
      ),
      runtimeEvents: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'cloud runtime events',
      ),
    ),
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.ffi,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'not used',
      ),
      projectGraph: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'not used',
      ),
      execution: AdapterEndpointCapability(
        level: ffiExecution,
        detail: 'ffi execution',
      ),
      runtimeEvents: AdapterEndpointCapability(
        level: ffiExecution,
        detail: 'ffi runtime events',
      ),
    ),
  ];
}
