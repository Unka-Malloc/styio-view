import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/language_fixture_confidence_matrix.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_manager_connector.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

import '../tool/language_fixture_gate.dart' as language_fixture_gate;

void main() {
  test('language fixture gate command defaults to parser-backed CI roots', () {
    final config = language_fixture_gate.LanguageFixtureGateCommandConfig.parse(
      const <String>[],
      environment: const <String, String>{},
    );

    expect(config.roots, const <String>[
      'test/fixtures/language_service',
      'test/fixtures/styio_language/syntax_contract',
    ]);
  });

  Future<ConfigurationStore> createConfigurationStore(Directory root) async {
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: root.path,
        homePath: root.path,
      ),
    );
    final coordinator = FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    );
    return ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: coordinator,
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: InMemoryCredentialDataStore(),
    );
  }

  test(
    'language fixture gate command runs fixtures through toolchain connector',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'vityo-language-fixture-gate-command-',
      );
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final processManager = LocalProcessManager.linuxDebianArmForTest();
      try {
        final fakeStyio = fileSystemManager.joinPath(<String>[
          tempDirectory.path,
          'fake-styio',
        ]);
        final fixtureRoot = fileSystemManager.joinPath(<String>[
          tempDirectory.path,
          'fixtures',
        ]);
        final valid = fileSystemManager.joinPath(<String>[
          fixtureRoot,
          'valid.true.styio',
        ]);
        final invalid = fileSystemManager.joinPath(<String>[
          fixtureRoot,
          'invalid.false.styio',
        ]);
        await fileSystemManager.writeText(
          fakeStyio,
          r'''#!/bin/sh
case "$*" in
  *invalid.false.styio*)
    printf '%s\n' '{"severity":"error","code":"styio.syntax","message":"invalid fixture","range":{"start":0,"end":1}}'
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
''',
        );
        await fileSystemManager.setExecutable(fakeStyio);
        await fileSystemManager.writeText(valid, '#valid := () => {}');
        await fileSystemManager.writeText(invalid, '#invalid := () => {');

        final output = StringBuffer();
        final errors = StringBuffer();
        final result = await language_fixture_gate.runLanguageFixtureGateCommand(
          <String>['--styio', fakeStyio, '--root', fixtureRoot],
          out: output,
          err: errors,
          fileSystemManager: fileSystemManager,
          processManager: processManager,
          environment: const <String, String>{},
        );

        expect(result, 0);
        expect(errors.toString(), contains('Language fixture gate: passed'));
        expect(errors.toString(), contains('TP=1'));
        expect(errors.toString(), contains('TN=1'));
        expect(output.toString(), contains('"gatePassed": true'));
        expect(output.toString(), contains('"truePositive": 1'));
        expect(output.toString(), contains('"trueNegative": 1'));
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'POSIX shell fixture.' : false,
  );

  test(
    'styio service fixture gate can use persisted toolchain manager',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'vityo-language-fixture-gate-manager-',
      );
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      try {
        final fakeStyio = fileSystemManager.joinPath(<String>[
          tempDirectory.path,
          'fake-styio',
        ]);
        final fixtureRoot = fileSystemManager.joinPath(<String>[
          tempDirectory.path,
          'fixtures',
        ]);
        final valid = fileSystemManager.joinPath(<String>[
          fixtureRoot,
          'valid.true.styio',
        ]);
        final invalid = fileSystemManager.joinPath(<String>[
          fixtureRoot,
          'invalid.false.styio',
        ]);
        await fileSystemManager.writeText(
          fakeStyio,
          r'''#!/bin/sh
case "$*" in
  *invalid.false.styio*)
    printf '%s\n' '{"severity":"error","code":"styio.syntax","message":"invalid fixture","range":{"start":0,"end":1}}'
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
''',
        );
        await fileSystemManager.setExecutable(fakeStyio);
        await fileSystemManager.writeText(valid, '#valid := () => {}');
        await fileSystemManager.writeText(invalid, '#invalid := () => {');

        final configurationStore = await createConfigurationStore(
          tempDirectory,
        );
        final manager = ToolchainManager(
          configurationStore: ToolchainConfigurationStore(
            configurationStore: configurationStore,
          ),
          platformManagers: await createDetectedPlatformManagerBundle(
            targetId: 'fixture-gate-manager',
          ),
          workspaceId: 'fixture-gate',
        );
        await manager.saveCatalog(
          ToolchainCatalog()
            ..register(
              ToolchainDescriptor(
                id: 'persisted-styio',
                kind: ToolchainKind.languageService,
                displayName: 'Persisted Styio',
                executablePath: fakeStyio,
                metadata: const <String, Object?>{
                  'contract': 'styio-cli-jsonl-v1',
                },
              ),
              activate: true,
            ),
        );

        final gate = StyioServiceFixtureGate(
          fileSystemManager: fileSystemManager,
          connector: ToolchainManagerStyioServiceConnector(manager: manager),
        );
        final matrix = await gate.run(roots: <String>[fixtureRoot]);

        expect(matrix.gatePassed, isTrue);
        expect(matrix.summary['truePositive'], 1);
        expect(matrix.summary['trueNegative'], 1);
        expect(
          language_fixture_gate.formatLanguageFixtureGateSummary(matrix),
          contains('2/2 matched'),
        );
      } finally {
        await tempDirectory.delete(recursive: true);
      }
    },
    skip: Platform.isWindows ? 'POSIX shell fixture.' : false,
  );
}
