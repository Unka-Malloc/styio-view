import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_launch_contract.dart';
import 'package:vityo_app/src/view_ide/debugger/extension_debug_contributions.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test(
    'extension debug catalog converts debugger routes to launch profiles',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.debug',
            displayName: 'Styio Debug',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'debug.dart',
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.debugger,
                id: 'styio-lldb',
                target: 'debugger.dap',
                title: 'Styio LLDB',
                metadata: <String, Object?>{
                  'debuggerId': 'styio-lldb-dap',
                  'executablePath': '/usr/bin/lldb-dap',
                  'adapterProtocol': 'dap',
                  'programPath': '/workspace/build/styio',
                  'cwd': '/workspace',
                  'debuggerArguments': <String>['--stdio'],
                  'arguments': <String>['--smoke'],
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );

      final catalog = ExtensionDebugContributionCatalog.fromRoutes(routes);
      final profile = catalog.runnableProfiles.single;

      expect(catalog.contributions.single.ready, isTrue);
      expect(profile.id, 'styio-lldb-dap');
      expect(profile.displayName, 'Styio LLDB');
      expect(profile.configuration.readiness, DebugLaunchReadiness.ready);
      expect(profile.configuration.debuggerArguments, <String>['--stdio']);
      expect(profile.configuration.arguments, <String>['--smoke']);
      expect(catalog.toJson()['runnableProfileCount'], 1);
    },
  );

  test(
    'extension debug catalog keeps non-runnable profile without program',
    () {
      final route = const ExtensionContributionRouter().routeContribution(
        extensionId: 'styio.debug',
        contribution: const ExtensionContributionPoint(
          kind: ExtensionContributionKind.debugger,
          id: 'styio-lldb',
          target: 'debugger.dap',
          metadata: <String, Object?>{'executablePath': '/usr/bin/lldb-dap'},
        ),
      );

      final catalog = ExtensionDebugContributionCatalog.fromRoutes(
        ExtensionContributionRouteManifest(
          routes: <ExtensionContributionRoute>[route],
        ),
      );

      expect(catalog.profiles.single.configuration.ready, isFalse);
      expect(catalog.runnableProfiles, isEmpty);
      expect(
        catalog.profiles.single.configuration.readiness,
        DebugLaunchReadiness.missingProgram,
      );
    },
  );
}
