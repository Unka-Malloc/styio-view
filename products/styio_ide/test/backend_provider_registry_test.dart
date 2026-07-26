import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/backend_provider.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/default_backend_providers.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/dependency_source_adapter.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/deployment_adapter.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_adapter.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/runtime_event_adapter.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:styio_ide/src/view_ide/platform/platform_target.dart';

void main() {
  test(
    'default IO catalog resolves one independently named provider per target',
    () {
      final registry = createDefaultBackendProviderRegistry();

      expect(registry.resolve(PlatformTarget.windows).id, 'windows.local');
      expect(registry.resolve(PlatformTarget.linux).id, 'linux.local');
      expect(registry.resolve(PlatformTarget.macos).id, 'macos.local');
      expect(registry.resolve(PlatformTarget.android).id, 'android.hybrid');
      expect(registry.resolve(PlatformTarget.ios).id, 'ios.hosted');
      expect(registry.resolve(PlatformTarget.unknown).id, 'unknown.io');
    },
  );

  test('higher-priority platform provider overrides the default provider', () {
    final registry = BackendProviderRegistry(
      providers: <BackendProvider>[
        const _FakeBackendProvider(
          id: 'windows.default',
          platformTarget: PlatformTarget.windows,
        ),
        const _FakeBackendProvider(
          id: 'windows.specialized',
          platformTarget: PlatformTarget.windows,
          priority: 10,
        ),
      ],
    );

    expect(registry.resolve(PlatformTarget.windows).id, 'windows.specialized');
  });

  test(
    'equal-priority providers fail closed instead of selecting by accident',
    () {
      final registry = BackendProviderRegistry(
        providers: <BackendProvider>[
          const _FakeBackendProvider(
            id: 'windows.alpha',
            platformTarget: PlatformTarget.windows,
          ),
          const _FakeBackendProvider(
            id: 'windows.beta',
            platformTarget: PlatformTarget.windows,
          ),
        ],
      );

      expect(
        () => registry.resolve(PlatformTarget.windows),
        throwsA(isA<StateError>()),
      );
    },
  );

  test('duplicate provider identifiers are rejected at registration', () {
    final registry = BackendProviderRegistry();
    registry.register(
      const _FakeBackendProvider(
        id: 'windows.local',
        platformTarget: PlatformTarget.windows,
      ),
    );

    expect(
      () => registry.register(
        const _FakeBackendProvider(
          id: 'windows.local',
          platformTarget: PlatformTarget.linux,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('missing platform provider fails closed', () {
    final registry = BackendProviderRegistry();

    expect(
      () => registry.resolve(PlatformTarget.windows),
      throwsA(isA<StateError>()),
    );
  });
}

final class _FakeBackendProvider implements BackendProvider {
  const _FakeBackendProvider({
    required this.id,
    required this.platformTarget,
    this.priority = 0,
  });

  @override
  final String id;

  final PlatformTarget platformTarget;

  @override
  final int priority;

  @override
  Set<PlatformTarget> get supportedPlatforms => <PlatformTarget>{
    platformTarget,
  };

  @override
  Future<DependencySourceAdapter> createDependencySourceAdapter() {
    throw UnsupportedError('Not used by registry tests.');
  }

  @override
  Future<DeploymentAdapter> createDeploymentAdapter() {
    throw UnsupportedError('Not used by registry tests.');
  }

  @override
  Future<ExecutionAdapter> createExecutionAdapter(
    ProjectGraphSnapshot projectGraph,
  ) {
    throw UnsupportedError('Not used by registry tests.');
  }

  @override
  Future<ProjectGraphAdapter> createProjectGraphAdapter() {
    throw UnsupportedError('Not used by registry tests.');
  }

  @override
  RuntimeEventAdapter createRuntimeEventAdapter() {
    throw UnsupportedError('Not used by registry tests.');
  }

  @override
  Future<ToolchainManagementAdapter> createToolchainManagementAdapter() {
    throw UnsupportedError('Not used by registry tests.');
  }
}
