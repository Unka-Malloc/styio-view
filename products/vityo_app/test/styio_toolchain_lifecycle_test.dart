import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('Styio toolchain lifecycle reports selectable required roles', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-service',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Language Service',
          executablePath: '/usr/bin/styio',
          metadata: <String, Object?>{'language': 'styio'},
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'styio-compiler',
          kind: ToolchainKind.compiler,
          displayName: 'Styio Compiler',
          executablePath: '/usr/bin/styio',
          metadata: <String, Object?>{'toolFamily': 'styio'},
        ),
      );
    final manager = StyioToolchainLifecycleManager(catalog: catalog);

    final report = manager.inspect(
      requiredRoles: const <StyioToolchainRole>[
        StyioToolchainRole.languageService,
        StyioToolchainRole.compiler,
      ],
    );

    expect(report.state, StyioToolchainLifecycleState.selectable);
    expect(report.ready, isFalse);
    expect(
      report.selectableRequiredRoles.single.role,
      StyioToolchainRole.compiler,
    );
    expect(
      report.roleStatus(StyioToolchainRole.languageService)!.ready,
      isTrue,
    );
    expect(report.toJson()['selectableRequiredRoleCount'], 1);
  });

  test('Styio toolchain lifecycle can activate best available roles', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-service',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Language Service',
          executablePath: '/usr/bin/styio',
          metadata: <String, Object?>{'language': 'styio'},
        ),
      )
      ..register(
        const ToolchainDescriptor(
          id: 'styio-runner',
          kind: ToolchainKind.runner,
          displayName: 'Styio Runner',
          executablePath: '/usr/bin/styio',
          metadata: <String, Object?>{'product': 'styio'},
        ),
      );
    final manager = StyioToolchainLifecycleManager(catalog: catalog);

    final report = manager.activateBestAvailable(
      requiredRoles: const <StyioToolchainRole>[
        StyioToolchainRole.languageService,
        StyioToolchainRole.runner,
      ],
    );

    expect(report.state, StyioToolchainLifecycleState.ready);
    expect(report.ready, isTrue);
    expect(catalog.active(ToolchainKind.languageService)!.id, 'styio-service');
    expect(catalog.active(ToolchainKind.runner)!.id, 'styio-runner');
    expect(report.toJson()['missingRequiredRoleCount'], 0);
  });

  test('Styio toolchain lifecycle marks missing required roles', () {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'clang',
          kind: ToolchainKind.compiler,
          displayName: 'Clang',
          executablePath: '/usr/bin/clang++',
          metadata: <String, Object?>{'toolFamily': 'native-cpp'},
        ),
        activate: true,
      );
    final manager = StyioToolchainLifecycleManager(catalog: catalog);

    final report = manager.inspect(
      requiredRoles: const <StyioToolchainRole>[StyioToolchainRole.compiler],
    );

    expect(report.state, StyioToolchainLifecycleState.missing);
    expect(
      report.missingRequiredRoles.single.role,
      StyioToolchainRole.compiler,
    );
    expect(report.message, contains('compiler'));
    expect(report.actionable, isTrue);
  });
}
