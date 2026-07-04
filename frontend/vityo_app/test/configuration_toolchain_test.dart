import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_manager_connector.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test(
    'configuration and toolchain abstract files avoid direct system APIs',
    () {
      final roots = <String>[
        'lib/src/view_ide/environment/configuration',
        'lib/src/view_ide/toolchain',
      ];
      final blockedPatterns = <RegExp>[
        RegExp(r'''import ['"]dart:io['"]'''),
        RegExp(r'\bPlatform\.'),
        RegExp(r'\bProcess\.run'),
        RegExp(r'\bDirectory\.systemTemp'),
        RegExp(r'\bFile\s*\('),
      ];
      final offenders = <String>[];

      for (final root in roots) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          final name = entity.uri.pathSegments.last;
          if (name.endsWith('_io.dart')) {
            continue;
          }
          final source = entity.readAsStringSync();
          for (final pattern in blockedPatterns) {
            if (pattern.hasMatch(source)) {
              offenders.add('${entity.path}: ${pattern.pattern}');
            }
          }
        }
      }
      offenders.sort();

      expect(offenders, isEmpty);
    },
  );

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

  PlatformContextSnapshot createWindowsPlatformContext() {
    return PlatformContextSnapshot.compose(
      targetId: 'windows-toolchain',
      fileSystem: const FileSystemFacts(
        targetId: 'windows-toolchain',
        operatingSystem: 'windows',
        distributionId: 'windows',
        distributionName: 'Windows',
        architecture: 'x64',
        pathStyle: FileSystemPathStyle.windows,
        pathSeparator: r'\',
        providerKind: FileSystemProviderKind.local,
        watchSupport: FileSystemWatchSupport.directory,
        caseSensitive: false,
        supportsFileUri: true,
        supportsSymbolicLinks: true,
        supportsAtomicWrite: true,
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'windows-toolchain',
        defaultShellPath: r'C:\Windows\System32\cmd.exe',
      ),
    );
  }

  PlatformContextSnapshot createLinuxPlatformContext(String targetId) {
    return PlatformContextSnapshot.compose(
      targetId: targetId,
      fileSystem: FileSystemFacts.linuxDebianArm(targetId: targetId),
      shell: ShellFacts.linuxDebianArm(
        targetId: targetId,
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(targetId: targetId),
      resource: ResourceFacts.linuxDebianArm(targetId: targetId),
      network: NetworkFacts.linuxDebianArm(targetId: targetId),
      clipboard: ClipboardFacts.linuxDebianArm(targetId: targetId),
      notification: NotificationFacts.linuxDebianArm(targetId: targetId),
      localService: LocalServiceFacts.linuxDebianArm(targetId: targetId),
      pty: PtyFacts.linuxDebianArm(targetId: targetId),
    );
  }

  test(
    'configuration store persists ordinary settings through foundation datastore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_configuration_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await createConfigurationStore(tempRoot);
      const key = ConfigurationSettingKey(
        namespace: 'shell',
        name: 'default-profile',
        workspaceId: 'demo',
      );

      await store.write(
        const ConfigurationSettingRecord(
          key: key,
          value: <String, Object?>{'profileId': 'bash'},
        ),
      );
      final loaded = await store.read(key);

      expect(loaded, isNotNull);
      expect(loaded!.value['profileId'], 'bash');
    },
  );

  test(
    'configuration store emits setting changes from foundation datastore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_configuration_watch_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await createConfigurationStore(tempRoot);
      const key = ConfigurationSettingKey(
        namespace: 'shell',
        name: 'default-profile',
        workspaceId: 'demo',
      );
      final changes = <ConfigurationSettingChange>[];
      final subscription = store.watch(key).listen(changes.add);
      addTearDown(subscription.cancel);

      await store.write(
        const ConfigurationSettingRecord(
          key: key,
          value: <String, Object?>{'profileId': 'bash'},
        ),
      );
      await store.delete(key);

      expect(
        changes.map((change) => change.kind),
        <ConfigurationSettingChangeKind>[
          ConfigurationSettingChangeKind.written,
          ConfigurationSettingChangeKind.deleted,
        ],
      );
      expect(changes.first.record!.value['profileId'], 'bash');
      expect(changes.last.record, isNull);
      expect(changes.last.key.stableKey, 'shell:demo:default-profile');
    },
  );

  test(
    'configuration store updates settings through foundation transaction',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_configuration_update_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await createConfigurationStore(tempRoot);
      const key = ConfigurationSettingKey(
        namespace: 'shell',
        name: 'default-profile',
        workspaceId: 'demo',
      );

      final created = await store.update(
        key,
        (current) => ConfigurationSettingRecord(
          key: key,
          value: <String, Object?>{
            'profileId': current?.value['profileId'] ?? 'bash',
            'revision': 1,
          },
        ),
      );
      final updated = await store.update(
        key,
        (current) => ConfigurationSettingRecord(
          key: key,
          value: <String, Object?>{
            ...?current?.value,
            'revision': (current?.value['revision'] as int? ?? 0) + 1,
          },
        ),
      );

      expect(created!.value, const <String, Object?>{
        'profileId': 'bash',
        'revision': 1,
      });
      expect(updated!.value, const <String, Object?>{
        'profileId': 'bash',
        'revision': 2,
      });
      expect((await store.read(key))!.value['revision'], 2);
      expect(
        () => store.update(
          key,
          (_) => const ConfigurationSettingRecord(
            key: key,
            value: <String, Object?>{'token': 'raw-secret'},
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('configuration store preserves credential references', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_configuration_credential_ref_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final store = await createConfigurationStore(tempRoot);
    const reference = CredentialReference(
      key: CredentialDataStoreKey(
        namespace: 'toolchain',
        name: 'styio-registry',
        scope: CredentialScope.toolchain,
        targetId: 'nightly',
      ),
      kind: CredentialKind.token,
      displayName: 'Styio registry token',
    );
    const key = ConfigurationSettingKey(
      namespace: 'toolchain',
      name: 'registry-auth',
    );

    await store.write(
      const ConfigurationSettingRecord(
        key: key,
        value: <String, Object?>{'credentialRef': 'styio-registry'},
        credentialReferences: <CredentialReference>[reference],
      ),
    );
    final loaded = await store.read(key);

    expect(loaded, isNotNull);
    expect(loaded!.credentialReferences.single.kind, CredentialKind.token);
    expect(
      loaded.credentialReferences.single.key.stableId,
      'toolchain:toolchain:nightly:styio-registry',
    );
    expect(
      loaded.credentialReferences.single.displayName,
      'Styio registry token',
    );
  });

  test('foundation credential datastore persists redacted metadata', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_foundation_credential_store_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final credentialStore = FoundationCredentialDataStore(dataStore: dataStore);
    const key = CredentialDataStoreKey(
      namespace: 'toolchain',
      name: 'styio-registry',
      scope: CredentialScope.toolchain,
      targetId: 'nightly',
    );

    await credentialStore.write(
      CredentialSecretRecord(
        key: key,
        kind: CredentialKind.token,
        secretValue: 'registry-secret-token',
        displayName: 'Styio registry token',
      ),
    );
    final reloadedStore = FoundationCredentialDataStore(dataStore: dataStore);
    final loaded = await reloadedStore.read(key);
    final snapshot = await reloadedStore.snapshot();
    final snapshotJson = snapshot.toJson().toString();

    expect(loaded, isNotNull);
    expect(loaded!.secretValue, 'registry-secret-token');
    expect(snapshot.credentials.single.redactedValue, startsWith('re****'));
    expect(snapshot.credentials.single.displayName, 'Styio registry token');
    expect(snapshotJson, isNot(contains('registry-secret-token')));
    expect(await reloadedStore.delete(key), isTrue);
    expect(await reloadedStore.delete(key), isFalse);
    expect(await reloadedStore.read(key), isNull);
  });

  test('configuration store rejects raw secret-like values', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_configuration_secret_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final store = await createConfigurationStore(tempRoot);

    expect(
      () => store.write(
        const ConfigurationSettingRecord(
          key: ConfigurationSettingKey(namespace: 'registry', name: 'auth'),
          value: <String, Object?>{'token': 'raw-secret'},
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'shell configuration store persists shell runtime configuration',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_configuration_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final shellStore = ShellConfigurationStore(
        configurationStore: configurationStore,
      );

      await shellStore.save(
        const ShellConfiguration(
          defaultProfileId: 'workspace-sh',
          profiles: <ShellProfileConfiguration>[
            ShellProfileConfiguration(
              id: 'workspace-sh',
              executablePath: '/bin/sh',
              family: ShellFamily.sh,
              arguments: <String>['-lc'],
              environment: <String, String>{'STYIO_MODE': 'nightly'},
            ),
          ],
          environmentOverlay: <String, String>{'PATH_PREFIX': '/opt/styio/bin'},
          loginShell: true,
          interactive: true,
          timeout: Duration(seconds: 12),
        ),
        workspaceId: 'demo',
      );

      final loaded = await shellStore.load(workspaceId: 'demo');

      expect(loaded, isNotNull);
      expect(loaded!.defaultProfileId, 'workspace-sh');
      expect(loaded.defaultProfile!.arguments, const <String>['-lc']);
      expect(loaded.defaultProfile!.environment['STYIO_MODE'], 'nightly');
      expect(loaded.environmentOverlay['PATH_PREFIX'], '/opt/styio/bin');
      expect(loaded.loginShell, isTrue);
      expect(loaded.interactive, isTrue);
      expect(loaded.timeout, const Duration(seconds: 12));
    },
  );

  test('shell configuration parses facts and permissive JSON payloads', () {
    final unsupported = ShellConfiguration.fromFacts(
      ShellFacts.linuxDebianArm(availableShells: const <ShellExecutableFact>[]),
    );
    final fromFacts = ShellConfiguration.fromFacts(
      ShellFacts.linuxDebianArm(
        defaultShellPath: '/bin/zsh',
        availableShells: const <ShellExecutableFact>[
          ShellExecutableFact(path: '/bin/sh', family: ShellFamily.sh),
          ShellExecutableFact(
            path: '/bin/zsh',
            family: ShellFamily.zsh,
            isDefault: true,
          ),
        ],
      ),
    );
    final parsed = ShellConfiguration.fromJson(
      <String, Object?>{
        'defaultProfileId': 'missing',
        'profiles': <Object?>[
          <Object?, Object?>{
            'id': 'pwsh',
            'executablePath': r'C:\PowerShell\pwsh.exe',
            'family': 'powershell',
            'arguments': <Object?>['-NoProfile', 42],
            'environment': <Object?, Object?>{'PSModulePath': r'C:\Modules'},
          },
          'ignored',
        ],
        'environmentOverlay': <Object?, Object?>{'LANG': 'C.UTF-8', 1: 2},
        'loginShell': true,
        'interactive': true,
        'timeoutMs': 1250,
      },
    );
    final copied = parsed.copyWith(
      defaultProfileId: 'pwsh',
      loginShell: false,
      interactive: false,
      timeout: const Duration(seconds: 2),
    );

    expect(unsupported.defaultProfileId, 'unsupported');
    expect(unsupported.defaultProfile, isNull);
    expect(fromFacts.defaultProfileId, 'default');
    expect(parsed.defaultProfile!.id, 'pwsh');
    expect(parsed.defaultProfile!.arguments, <String>['-NoProfile', '42']);
    expect(parsed.defaultProfile!.environment['PSModulePath'], r'C:\Modules');
    expect(parsed.environmentOverlay, <String, String>{
      'LANG': 'C.UTF-8',
      '1': '2',
    });
    expect(parsed.loginShell, isTrue);
    expect(parsed.interactive, isTrue);
    expect(parsed.timeout, const Duration(milliseconds: 1250));
    expect(copied.defaultProfileId, 'pwsh');
    expect(copied.loginShell, isFalse);
    expect(copied.interactive, isFalse);
    expect(copied.timeout, const Duration(seconds: 2));
    expect(shellFamilyFromWireValue('cmd'), ShellFamily.cmd);
    expect(shellFamilyFromWireValue('unknown-shell'), ShellFamily.unknown);
  });

  test('language service configuration persists fallback mode', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_language_service_configuration_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final configurationStore = await createConfigurationStore(tempRoot);
    final languageServiceStore = LanguageServiceConfigurationStore(
      configurationStore: configurationStore,
    );

    await languageServiceStore.save(
      const LanguageServiceConfiguration(allowLocalFallback: false),
      workspaceId: 'demo',
    );
    final loaded = await languageServiceStore.load(workspaceId: 'demo');
    final missing = await languageServiceStore.load(workspaceId: 'other');

    expect(loaded, isNotNull);
    expect(loaded!.allowLocalFallback, isFalse);
    expect(loaded.toJson()['allowLocalFallback'], isFalse);
    expect(missing, isNull);
  });

  test(
    'environment variable configuration stores overlays without OS mutation',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_env_configuration_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final envStore = EnvironmentVariableConfigurationStore(
        configurationStore: configurationStore,
      );
      const credentialReference = CredentialReference(
        key: CredentialDataStoreKey(
          namespace: 'toolchain',
          name: 'registry-token',
          scope: CredentialScope.toolchain,
        ),
        kind: CredentialKind.token,
        displayName: 'Registry token',
      );

      await envStore.save(
        const EnvironmentVariableOverlay(
          id: 'workspace-shell',
          scope: EnvironmentVariableOverlayScope.workspace,
          target: 'terminal',
          workspaceId: 'demo',
          variables: <String, String?>{
            'STYIO_MODE': 'nightly',
            'REMOVE_ME': null,
          },
          pathPrepend: <String>['/opt/styio/bin'],
          pathAppend: <String>['/workspace/bin'],
          envFiles: <String>['.env'],
          credentialReferences: <CredentialReference>[credentialReference],
        ),
      );

      final loaded = await envStore.load(
        id: 'workspace-shell',
        scope: EnvironmentVariableOverlayScope.workspace,
        target: 'terminal',
        workspaceId: 'demo',
      );
      final resolved = const EnvironmentVariableResolver().resolve(
        inherited: const <String, String>{
          'PATH': '/usr/bin',
          'REMOVE_ME': 'from-host',
        },
        overlays: <EnvironmentVariableOverlay>[loaded!],
        runtimeOverrides: const <String, String>{'STYIO_MODE': 'runtime'},
      );

      expect(loaded.envFiles, const <String>['.env']);
      expect(loaded.credentialReferences.single.key.name, 'registry-token');
      expect(resolved['PATH'], '/opt/styio/bin:/usr/bin:/workspace/bin');
      expect(resolved['STYIO_MODE'], 'runtime');
      expect(resolved.containsKey('REMOVE_ME'), isFalse);
    },
  );

  test('environment variable configuration parses scopes and loose JSON', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_env_configuration_edges_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final firstEnv = fileSystemManager.joinPath(<String>[tempRoot.path, '.env']);
    final secondEnv = fileSystemManager.joinPath(<String>[
      tempRoot.path,
      '.env.local',
    ]);
    await fileSystemManager.writeText(firstEnv, "A='one'\n");
    await fileSystemManager.writeText(secondEnv, 'B=two\n');

    final overlay = EnvironmentVariableOverlay.fromJson(
      <String, Object?>{
        'id': 'loose',
        'scope': 'debug',
        'target': 'launch',
        'workspaceId': 'demo',
        'variables': <Object?, Object?>{'A': 1, 'REMOVE_ME': null},
        'pathPrepend': <Object?>['/opt/styio/bin', 7],
        'pathAppend': <Object?>['/workspace/bin'],
        'envFiles': <Object?>['.env', 3],
      },
    );
    final loaded = await EnvironmentVariableFileLoader(
      fileSystemManager: fileSystemManager,
    ).loadAll(<String>[firstEnv, secondEnv]);
    final resolved = const EnvironmentVariableResolver(
      pathVariableName: 'Path',
    ).resolve(
      inherited: const <String, String>{'Path': r'C:\Windows', 'REMOVE_ME': 'x'},
      envFileVariables: loaded.map((file) => file.variables),
      overlays: <EnvironmentVariableOverlay>[overlay],
      pathSeparator: ';',
    );

    expect(
      EnvironmentVariableOverlayScope.values.map((scope) => scope.wireValue),
      <String>[
        'user',
        'workspace',
        'profile',
        'task',
        'debug',
        'toolchain',
        'extension',
      ],
    );
    expect(
      environmentVariableOverlayScopeFromWireValue('profile'),
      EnvironmentVariableOverlayScope.profile,
    );
    expect(
      environmentVariableOverlayScopeFromWireValue('extension'),
      EnvironmentVariableOverlayScope.extension,
    );
    expect(
      environmentVariableOverlayScopeFromWireValue('unknown'),
      EnvironmentVariableOverlayScope.user,
    );
    expect(overlay.scope, EnvironmentVariableOverlayScope.debug);
    expect(overlay.variables, <String, String?>{'A': '1', 'REMOVE_ME': null});
    expect(overlay.pathPrepend, <String>['/opt/styio/bin', '7']);
    expect(overlay.envFiles, <String>['.env', '3']);
    expect(resolved['Path'], r'/opt/styio/bin;7;C:\Windows;/workspace/bin');
    expect(resolved['A'], '1');
    expect(resolved['B'], 'two');
    expect(resolved.containsKey('REMOVE_ME'), isFalse);
    expect(
      () => const EnvironmentVariableFileParser().parse(
        sourcePath: '.env',
        text: 'MISSING_SEPARATOR',
      ),
      throwsFormatException,
    );
  });

  test('environment variable file parser feeds launch resolver', () {
    final parsed = const EnvironmentVariableFileParser().parse(
      sourcePath: '.env',
      text: '''
# Workspace env
STYIO_MODE=file
export STYIO_CHANNEL="nightly"
REMOVE_ME=from-file
''',
    );
    final resolved = const EnvironmentVariableResolver().resolve(
      inherited: const <String, String>{'PATH': '/usr/bin'},
      envFileVariables: <Map<String, String?>>[parsed.variables],
      overlays: const <EnvironmentVariableOverlay>[
        EnvironmentVariableOverlay(
          id: 'workspace',
          scope: EnvironmentVariableOverlayScope.workspace,
          target: 'terminal',
          variables: <String, String?>{
            'STYIO_MODE': 'overlay',
            'REMOVE_ME': null,
          },
        ),
      ],
      runtimeOverrides: const <String, String>{'STYIO_MODE': 'runtime'},
    );

    expect(parsed.sourcePath, '.env');
    expect(parsed.variables['STYIO_CHANNEL'], 'nightly');
    expect(resolved['STYIO_CHANNEL'], 'nightly');
    expect(resolved['STYIO_MODE'], 'runtime');
    expect(resolved.containsKey('REMOVE_ME'), isFalse);
    expect(
      () => const EnvironmentVariableFileParser().parse(
        sourcePath: '.env',
        text: '1BAD=value',
      ),
      throwsFormatException,
    );
  });

  test(
    'environment variable file loader reads env files through file system manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_env_file_loader_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final envPath = fileSystemManager.joinPath(<String>[
        tempRoot.path,
        '.env',
      ]);
      await fileSystemManager.writeText(
        envPath,
        'STYIO_MODE=file\nSTYIO_CHANNEL=nightly\n',
      );
      final loader = EnvironmentVariableFileLoader(
        fileSystemManager: fileSystemManager,
      );

      final loaded = await loader.load(envPath);
      final resolved = const EnvironmentVariableResolver().resolve(
        envFileVariables: <Map<String, String?>>[loaded.variables],
        overlays: const <EnvironmentVariableOverlay>[
          EnvironmentVariableOverlay(
            id: 'toolchain',
            scope: EnvironmentVariableOverlayScope.toolchain,
            target: 'styio-service',
            variables: <String, String?>{'STYIO_MODE': 'overlay'},
          ),
        ],
      );

      expect(loaded.sourcePath, envPath);
      expect(loaded.variables['STYIO_CHANNEL'], 'nightly');
      expect(resolved['STYIO_CHANNEL'], 'nightly');
      expect(resolved['STYIO_MODE'], 'overlay');
    },
  );

  test('environment variable redaction policy hides sensitive values', () {
    const policy = EnvironmentVariableRedactionPolicy();
    const overlay = EnvironmentVariableOverlay(
      id: 'secrets',
      scope: EnvironmentVariableOverlayScope.workspace,
      target: 'terminal',
      variables: <String, String?>{
        'STYIO_TOKEN': 'raw-token',
        'STYIO_MODE': 'nightly',
        'REMOVE_ME': null,
      },
    );
    const parsed = ParsedEnvironmentVariableFile(
      sourcePath: '.env',
      variables: <String, String?>{
        'REGISTRY_PASSWORD': 'raw-password',
        'STYIO_CHANNEL': 'nightly',
      },
    );
    final resolved = const EnvironmentVariableResolver().resolve(
      envFileVariables: <Map<String, String?>>[parsed.variables],
      overlays: const <EnvironmentVariableOverlay>[overlay],
    );

    expect(policy.redactEnvironment(resolved)['STYIO_TOKEN'], '<redacted>');
    expect(
      policy.redactEnvironment(resolved)['REGISTRY_PASSWORD'],
      '<redacted>',
    );
    expect(policy.redactEnvironment(resolved)['STYIO_MODE'], 'nightly');
    expect(
      overlay.toRedactedJson()['variables'].toString(),
      isNot(contains('raw-token')),
    );
    expect(
      parsed.toRedactedJson()['variables'].toString(),
      isNot(contains('raw-password')),
    );
  });

  test(
    'execution manager builds env through resolver and redacts result metadata',
    () async {
      final manager = ExecutionManager(
        processManager: LocalProcessManager.linuxDebianArmForTest(),
        inheritedEnvironment: const <String, String>{'PATH': '/usr/bin'},
      );

      final result = await manager.run(
        const ExecutionRequest(
          executablePath: '/usr/bin/env',
          envFileVariables: <Map<String, String?>>[
            <String, String?>{'STYIO_CHANNEL': 'nightly'},
          ],
          environmentOverlays: <EnvironmentVariableOverlay>[
            EnvironmentVariableOverlay(
              id: 'task',
              scope: EnvironmentVariableOverlayScope.task,
              target: 'execution',
              variables: <String, String?>{
                'STYIO_TOKEN': 'raw-token',
                'STYIO_MODE': 'overlay',
              },
              pathPrepend: <String>['/opt/styio/bin'],
            ),
          ],
          environment: <String, String>{'STYIO_MODE': 'runtime'},
        ),
      );

      expect(result.succeeded, isTrue);
      expect(result.processResult.stdout, contains('STYIO_MODE=runtime'));
      expect(result.processResult.stdout, contains('STYIO_CHANNEL=nightly'));
      expect(
        result.processResult.stdout,
        contains('PATH=/opt/styio/bin:/usr/bin'),
      );
      expect(result.redactedEnvironment['STYIO_TOKEN'], '<redacted>');
      expect(result.toJson().toString(), isNot(contains('raw-token')));
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test(
    'execution manager derives PATH list separator from platform context',
    () async {
      final manager = ExecutionManager.fromPlatformContext(
        platformContext: createWindowsPlatformContext(),
        processManager: UnsupportedProcessManager(
          facts: ProcessFacts.linuxDebianArm(targetId: 'windows-toolchain'),
        ),
        inheritedEnvironment: const <String, String>{
          'PATH': r'C:\Windows\System32',
        },
      );

      final result = await manager.run(
        const ExecutionRequest(
          executablePath: r'C:\Windows\System32\cmd.exe',
          environmentOverlays: <EnvironmentVariableOverlay>[
            EnvironmentVariableOverlay(
              id: 'windows-execution',
              scope: EnvironmentVariableOverlayScope.task,
              target: 'execution',
              pathPrepend: <String>[r'C:\Styio\bin'],
              pathAppend: <String>[r'C:\Workspace\bin'],
            ),
          ],
        ),
      );

      expect(result.status, ExecutionManagerStatus.blocked);
      expect(
        result.redactedEnvironment['PATH'],
        r'C:\Styio\bin;C:\Windows\System32;C:\Workspace\bin',
      );
    },
  );

  test('toolchain configuration store emits catalog changes', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_catalog_watch_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final configurationStore = await createConfigurationStore(tempRoot);
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final changes = <ToolchainCatalogConfigurationChange>[];
    final subscription = toolchainStore
        .watchCatalog(workspaceId: 'demo')
        .listen(changes.add);
    addTearDown(subscription.cancel);
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-nightly',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Nightly',
          executablePath: '/opt/styio/bin/styio',
          version: '2026.05',
          channel: 'nightly',
        ),
        activate: true,
      );

    await toolchainStore.saveCatalog(catalog, workspaceId: 'demo');
    await toolchainStore.deleteCatalog(workspaceId: 'demo');

    expect(
      changes.map((change) => change.kind),
      <ConfigurationSettingChangeKind>[
        ConfigurationSettingChangeKind.written,
        ConfigurationSettingChangeKind.deleted,
      ],
    );
    expect(
      changes.first.catalog!.active(ToolchainKind.languageService)!.id,
      'styio-nightly',
    );
    expect(changes.last.deleted, isTrue);
    expect(changes.last.catalog, isNull);
    expect(changes.last.toJson()['workspaceId'], 'demo');
  });

  test(
    'toolchain configuration store updates catalog transactionally',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_catalog_update_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );

      final updated = await toolchainStore.updateCatalog((catalog) {
        catalog.register(
          const ToolchainDescriptor(
            id: 'styio-nightly',
            kind: ToolchainKind.languageService,
            displayName: 'Styio Nightly',
            executablePath: '/opt/styio/bin/styio',
          ),
          activate: true,
        );
        return catalog;
      }, workspaceId: 'demo');

      expect(
        updated!.active(ToolchainKind.languageService)!.id,
        'styio-nightly',
      );
      expect(
        (await toolchainStore.loadCatalog(
          workspaceId: 'demo',
        )).active(ToolchainKind.languageService)!.id,
        'styio-nightly',
      );

      final deleted = await toolchainStore.updateCatalog(
        (_) => null,
        workspaceId: 'demo',
      );

      expect(deleted, isNull);
      expect(
        (await toolchainStore.loadCatalog(workspaceId: 'demo')).list(),
        isEmpty,
      );
    },
  );

  test(
    'toolchain catalog selects active toolchain and runtime executes it',
    () async {
      final catalog = ToolchainCatalog();
      catalog.register(
        const ToolchainDescriptor(
          id: 'printf',
          kind: ToolchainKind.runner,
          displayName: 'printf',
          executablePath: '/usr/bin/printf',
        ),
        activate: true,
      );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: LocalProcessManager.linuxDebianArmForTest(),
      );

      final result = await runtime.run(
        kind: ToolchainKind.runner,
        arguments: const <String>['toolchain-ok'],
      );

      expect(result.succeeded, isTrue);
      expect(result.toolchainId, 'printf');
      expect(result.stdout, 'toolchain-ok');
      expect(result.toJson()['status'], 'succeeded');
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test(
    'toolchain runtime consumes platform manager bundle process manager',
    () async {
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-platform',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-platform',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-platform',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(targetId: 'toolchain-platform'),
        resource: ResourceFacts.linuxDebianArm(targetId: 'toolchain-platform'),
        network: NetworkFacts.linuxDebianArm(targetId: 'toolchain-platform'),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-platform',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-platform',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-platform',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-platform'),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'printf',
            kind: ToolchainKind.runner,
            displayName: 'printf',
            executablePath: '/usr/bin/printf',
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime.fromPlatformManagers(
        catalog: catalog,
        platformManagers: platformManagers,
      );

      final result = await runtime.run(
        kind: ToolchainKind.runner,
        arguments: const <String>['toolchain-platform-ok'],
      );

      expect(platformManagers.process.facts.targetId, 'toolchain-platform');
      expect(result.succeeded, isTrue);
      expect(result.stdout, 'toolchain-platform-ok');
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test('toolchain resolver selects matching version and channel', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-stable',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Stable',
          executablePath: '/usr/bin/styio',
          version: '1.0.0',
          channel: 'stable',
          metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'styio-nightly',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Nightly',
          executablePath: '/opt/styio-nightly/bin/styio',
          version: '2026.05',
          channel: 'nightly',
          metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v2'},
        ),
      );

    final resolution = const ToolchainResolver().resolve(
      catalog,
      const ToolchainRequirement(
        kind: ToolchainKind.languageService,
        version: '2026.05',
        channel: 'nightly',
        metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v2'},
      ),
    );

    expect(resolution.resolved, isTrue);
    expect(resolution.descriptor!.id, 'styio-nightly');
  });

  test(
    'toolchain runtime blocks when version requirement is not resolved',
    () async {
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'styio-stable',
            kind: ToolchainKind.languageService,
            displayName: 'Styio Stable',
            executablePath: '/usr/bin/styio',
            version: '1.0.0',
            channel: 'stable',
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: LocalProcessManager.linuxDebianArmForTest(),
      );

      final result = await runtime.run(
        kind: ToolchainKind.languageService,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
          version: '2026.05',
          channel: 'nightly',
        ),
      );

      expect(result.status, ToolchainRuntimeStatus.blocked);
      expect(result.message, contains('does not match'));
    },
  );

  test('toolchain health checker reports unresolved requirements', () async {
    final catalog = ToolchainCatalog();

    final report = await const ToolchainHealthChecker().check(
      catalog: catalog,
      processManager: LocalProcessManager.linuxDebianArmForTest(),
      requirement: const ToolchainRequirement(
        kind: ToolchainKind.languageService,
      ),
    );

    expect(report.status, ToolchainHealthStatus.unresolved);
    expect(report.healthy, isFalse);
    expect(report.message, contains('No language-service toolchain'));
    expect(report.toJson()['healthy'], isFalse);
  });

  test('toolchain health checker probes resolved executables', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'printf',
          kind: ToolchainKind.runner,
          displayName: 'printf',
          executablePath: '/usr/bin/printf',
        ),
        activate: true,
      );

    final report = await const ToolchainHealthChecker().check(
      catalog: catalog,
      processManager: LocalProcessManager.linuxDebianArmForTest(),
      requirement: const ToolchainRequirement(kind: ToolchainKind.runner),
      probeArguments: const <String>['toolchain-healthy'],
    );

    expect(report.status, ToolchainHealthStatus.healthy);
    expect(report.processResult?.stdout, 'toolchain-healthy');
    expect(report.toJson()['processResult'], isA<Map<String, Object?>>());
  }, skip: Platform.isWindows ? 'POSIX process fixture.' : false);

  test(
    'toolchain runtime forwards standard input to process manager',
    () async {
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'cat',
            kind: ToolchainKind.runner,
            displayName: 'cat',
            executablePath: '/usr/bin/cat',
          ),
          activate: true,
        );
      final runtime = ToolchainRuntime(
        catalog: catalog,
        processManager: LocalProcessManager.linuxDebianArmForTest(),
      );

      final result = await runtime.run(
        kind: ToolchainKind.runner,
        standardInput: 'toolchain-stdin',
      );

      expect(result.succeeded, isTrue);
      expect(result.stdout, 'toolchain-stdin');
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test('toolchain manager forwards standard input to runtime', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_stdin_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final configurationStore = await createConfigurationStore(tempRoot);
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'cat',
          kind: ToolchainKind.runner,
          displayName: 'cat',
          executablePath: '/usr/bin/cat',
        ),
        activate: true,
      );
    await toolchainStore.saveCatalog(
      catalog,
      targetId: platformManagers.context.targetId,
    );
    final manager = ToolchainManager(
      configurationStore: toolchainStore,
      platformManagers: platformManagers,
    );

    final result = await manager.run(
      kind: ToolchainKind.runner,
      standardInput: 'toolchain-manager-stdin',
    );

    expect(result.succeeded, isTrue);
    expect(result.stdout, 'toolchain-manager-stdin');
  }, skip: Platform.isWindows ? 'POSIX process fixture.' : false);

  test('toolchain manager persists Clang C++ version preference', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_clang_cpp_preference_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final configurationStore = await createConfigurationStore(tempRoot);
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final manager = ToolchainManager(
      configurationStore: toolchainStore,
      platformManagers: platformManagers,
      workspaceId: 'workspace-a',
    );

    await manager.saveClangCppVersionPreference(
      const ClangCppVersionPreference(
        versionId: 'clang-18',
        cppStandard: CppLanguageStandard.cpp23,
      ),
    );

    final loaded = await manager.loadClangCppVersionPreference();
    expect(loaded?.versionId, 'clang-18');
    expect(loaded?.cppStandard, CppLanguageStandard.cpp23);
    expect(await manager.clearClangCppVersionPreference(), isTrue);
    expect(await manager.loadClangCppVersionPreference(), isNull);
  });

  test('toolchain runtime exposes health preflight', () async {
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'printf',
          kind: ToolchainKind.runner,
          displayName: 'printf',
          executablePath: '/usr/bin/printf',
        ),
        activate: true,
      );
    final runtime = ToolchainRuntime(
      catalog: catalog,
      processManager: LocalProcessManager.linuxDebianArmForTest(),
    );

    final report = await runtime.checkHealth(
      kind: ToolchainKind.runner,
      probeArguments: const <String>['runtime-health'],
    );

    expect(report.healthy, isTrue);
    expect(report.processResult?.stdout, 'runtime-health');
  }, skip: Platform.isWindows ? 'POSIX process fixture.' : false);

  test('toolchain install policy plans trusted managed downloads', () {
    const requirement = ToolchainRequirement(
      kind: ToolchainKind.languageService,
      version: '2026.05',
      channel: 'nightly',
    );
    const policy = ToolchainInstallPolicy(
      allowedModes: <ToolchainInstallMode>{
        ToolchainInstallMode.managedDownload,
      },
      trustedDownloadHosts: <String>{'downloads.vityo.dev'},
    );

    final plan = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio/nightly'),
      ),
    );

    expect(plan.actionable, isTrue);
    expect(plan.mode, ToolchainInstallMode.managedDownload);
    expect(plan.downloadUri!.host, 'downloads.vityo.dev');
    expect(plan.toJson()['actionable'], isTrue);
    expect(
      (plan.toJson()['requirement'] as Map<String, Object?>)['kind'],
      'language-service',
    );
  });

  test('toolchain artifact verifier reports checksum and size status', () {
    final artifactBytes = utf8.encode('styio-nightly-artifact');
    final expectedSha256 = sha256.convert(artifactBytes).toString();

    final verified = const ToolchainArtifactVerifier().verify(
      artifactBytes: artifactBytes,
      expectedSha256: expectedSha256.toUpperCase(),
      expectedSizeBytes: artifactBytes.length,
    );
    final notRequested = const ToolchainArtifactVerifier().verify(
      artifactBytes: artifactBytes,
    );
    final failed = const ToolchainArtifactVerifier().verify(
      artifactBytes: artifactBytes,
      expectedSha256: 'not-the-real-checksum',
    );
    final sizeFailed = const ToolchainArtifactVerifier().verify(
      artifactBytes: artifactBytes,
      expectedSizeBytes: artifactBytes.length + 1,
    );

    expect(verified.status, ToolchainArtifactVerificationStatus.verified);
    expect(verified.succeeded, isTrue);
    expect(verified.toJson()['artifactSizeBytes'], artifactBytes.length);
    expect(
      notRequested.status,
      ToolchainArtifactVerificationStatus.notRequested,
    );
    expect(failed.status, ToolchainArtifactVerificationStatus.failed);
    expect(failed.message, contains('SHA-256 mismatch'));
    expect(sizeFailed.status, ToolchainArtifactVerificationStatus.failed);
    expect(sizeFailed.toJson()['message'], contains('size mismatch'));
  });

  test('toolchain install policy blocks untrusted downloads', () {
    const requirement = ToolchainRequirement(
      kind: ToolchainKind.languageService,
      version: '2026.05',
      channel: 'nightly',
    );
    const policy = ToolchainInstallPolicy(
      allowedModes: <ToolchainInstallMode>{
        ToolchainInstallMode.managedDownload,
      },
      trustedDownloadHosts: <String>{'downloads.vityo.dev'},
    );

    final plan = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://example.invalid/styio/nightly'),
      ),
    );

    expect(plan.actionable, isFalse);
    expect(plan.status, ToolchainInstallPlanStatus.blocked);
    expect(plan.message, contains('not trusted'));
    expect(plan.toJson()['status'], 'blocked');
  });

  test('toolchain install policy can require managed download checksum', () {
    const requirement = ToolchainRequirement(
      kind: ToolchainKind.languageService,
      version: '2026.05',
      channel: 'nightly',
    );
    const policy = ToolchainInstallPolicy(
      allowedModes: <ToolchainInstallMode>{
        ToolchainInstallMode.managedDownload,
      },
      trustedDownloadHosts: <String>{'downloads.vityo.dev'},
      requireManagedDownloadSha256: true,
    );

    final blocked = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio/nightly'),
      ),
    );
    final planned = policy.plan(
      ToolchainInstallRequest(
        requirement: requirement,
        downloadUri: Uri.parse('https://downloads.vityo.dev/styio/nightly'),
        expectedSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    );

    expect(blocked.status, ToolchainInstallPlanStatus.blocked);
    expect(blocked.message, contains('SHA-256'));
    expect(planned.status, ToolchainInstallPlanStatus.planned);
    expect(planned.expectedSha256, isNotNull);
  });

  test(
    'toolchain install policy plans required strong provenance with trusted key',
    () {
      const requirement = ToolchainRequirement(
        kind: ToolchainKind.languageService,
        version: '2026.05',
        channel: 'nightly',
      );
      final policy = ToolchainInstallPolicy(
        allowedModes: <ToolchainInstallMode>{
          ToolchainInstallMode.managedDownload,
        },
        trustedDownloadHosts: const <String>{'downloads.vityo.dev'},
        requireManagedDownloadSignature: true,
        trustedProvenanceKeys: <ToolchainProvenanceTrustRoot>[
          ToolchainProvenanceTrustRoot(
            keyId: 'styio-nightly',
            algorithm: ToolchainProvenanceAlgorithm.ed25519,
            publicKeyBase64: base64.encode(List<int>.filled(32, 1)),
          ),
        ],
      );

      final planned = policy.plan(
        ToolchainInstallRequest(
          requirement: requirement,
          downloadUri: Uri.parse('https://downloads.vityo.dev/styio/nightly'),
          expectedSha256:
              '0000000000000000000000000000000000000000000000000000000000000000',
          provenanceSignatureUri: Uri.parse(
            'https://downloads.vityo.dev/styio/nightly.sig',
          ),
        ),
      );

      expect(planned.status, ToolchainInstallPlanStatus.planned);
      expect(planned.actionable, isTrue);
      expect(planned.provenanceSignatureUri, isNotNull);
      expect(planned.trustedProvenanceKeys.single.keyId, 'styio-nightly');
      expect(planned.toJson()['provenanceSignatureUri'], contains('.sig'));
      expect(planned.toJson()['trustedProvenanceKeyIds'], <String>[
        'styio-nightly',
      ]);
    },
  );

  test('toolchain install policy falls back to manual selection', () {
    const requirement = ToolchainRequirement(kind: ToolchainKind.compiler);
    const policy = ToolchainInstallPolicy();

    final plan = policy.plan(
      const ToolchainInstallRequest(requirement: requirement),
    );

    expect(plan.actionable, isTrue);
    expect(plan.mode, ToolchainInstallMode.manualSelection);
  });

  test(
    'toolchain install executor runs external command through platform managers',
    () async {
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-install-executor',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-install-executor',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-install-executor'),
      );
      final executor = ToolchainInstallExecutor(
        platformManagers: await createPlatformManagerBundle(
          platformContext: context,
        ),
        environmentBuilder: const ToolchainEnvironmentBuilder(
          inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
        ),
      );
      final plan = const ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.externalCommand,
        requirement: ToolchainRequirement(kind: ToolchainKind.languageService),
        externalCommand: '/usr/bin/env',
      );

      final result = await executor.execute(
        plan,
        environment: const <String, String>{'VITYO_INSTALL_TEST': 'ok'},
      );

      expect(result.status, ToolchainInstallExecutionStatus.succeeded);
      expect(result.succeeded, isTrue);
      expect(result.processResult?.stdout, contains('VITYO_INSTALL_TEST=ok'));
      expect(result.toJson()['processResult'], isA<Map<String, Object?>>());

      final failed = await executor.execute(
        const ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.externalCommand,
          requirement: ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          externalCommand: '/usr/bin/false',
        ),
      );

      expect(failed.status, ToolchainInstallExecutionStatus.failed);
      expect(failed.platformFailure, isNotNull);
      expect(failed.platformFailure!['kind'], 'nonZeroExit');
      expect(failed.toJson()['platformFailure'], isA<Map<String, Object?>>());
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test(
    'toolchain install executor reports user and download boundaries',
    () async {
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-install-boundary',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-install-boundary',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-install-boundary'),
      );
      final executor = ToolchainInstallExecutor(
        platformManagers: await createPlatformManagerBundle(
          platformContext: context,
        ),
      );

      final manual = await executor.execute(
        const ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.manualSelection,
          requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
        ),
      );
      final download = await executor.execute(
        const ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
        ),
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        request.response.write('unavailable');
        request.response.close();
      });
      final networkFailed = await executor.execute(
        ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: Uri.parse(
            'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio',
          ),
        ),
      );

      expect(manual.status, ToolchainInstallExecutionStatus.requiresUserAction);
      expect(manual.succeeded, isFalse);
      expect(manual.recoveryActions.single.id, 'select-existing-toolchain');
      expect(download.status, ToolchainInstallExecutionStatus.blocked);
      expect(download.message, contains('URI'));
      expect(
        download.recoveryActions.map((action) => action.id),
        contains('configure-managed-download'),
      );
      expect(networkFailed.status, ToolchainInstallExecutionStatus.failed);
      expect(networkFailed.platformFailure!['kind'], 'httpStatus');
    },
  );

  test(
    'toolchain install executor reports blocked plan and command boundaries',
    () async {
      final executor = ToolchainInstallExecutor(
        platformManagers: await createPlatformManagerBundle(
          platformContext: createLinuxPlatformContext(
            'toolchain-install-blocked',
          ),
        ),
      );

      final blocked = await executor.execute(
        const ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.blocked,
          mode: ToolchainInstallMode.managedDownload,
          requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
          message: 'blocked by policy',
        ),
      );
      final disabled = await executor.execute(
        const ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.disabled,
          requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
        ),
      );
      final missingCommand = await executor.execute(
        const ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.externalCommand,
          requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
          externalCommand: '',
        ),
      );

      expect(blocked.status, ToolchainInstallExecutionStatus.blocked);
      expect(blocked.message, 'blocked by policy');
      expect(
        blocked.recoveryActions.map((action) => action.id),
        contains('configure-managed-download'),
      );
      expect(disabled.status, ToolchainInstallExecutionStatus.blocked);
      expect(disabled.recoveryActions.single.id, 'enable-toolchain-installation');
      expect(
        disabled.recoveryActions.single.toJson()['detail'],
        contains('allow a toolchain installation mode'),
      );
      expect(missingCommand.status, ToolchainInstallExecutionStatus.blocked);
      expect(missingCommand.message, contains('command is missing'));
      expect(
        missingCommand.recoveryActions.map((action) => action.id),
        contains('retry-external-installer'),
      );
    },
  );

  test(
    'toolchain install executor handles empty artifacts and provenance setup',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        if (request.uri.path.endsWith('/empty')) {
          request.response.close();
          return;
        }
        request.response.write('artifact-without-signature');
        request.response.close();
      });
      final executor = ToolchainInstallExecutor(
        platformManagers: await createPlatformManagerBundle(
          platformContext: createLinuxPlatformContext(
            'toolchain-install-provenance',
          ),
        ),
      );
      final baseUri = 'http://${InternetAddress.loopbackIPv4.address}:'
          '${server.port}';

      final empty = await executor.execute(
        ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: Uri.parse('$baseUri/empty'),
        ),
      );
      final missingSignatureUri = await executor.execute(
        ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: Uri.parse('$baseUri/artifact'),
          trustedProvenanceKeys: <ToolchainProvenanceTrustRoot>[
            ToolchainProvenanceTrustRoot(
              keyId: 'styio-nightly',
              algorithm: ToolchainProvenanceAlgorithm.ed25519,
              publicKeyBase64: base64.encode(List<int>.filled(32, 1)),
            ),
          ],
        ),
      );

      expect(empty.status, ToolchainInstallExecutionStatus.failed);
      expect(empty.message, contains('empty artifact'));
      expect(missingSignatureUri.status, ToolchainInstallExecutionStatus.failed);
      expect(
        missingSignatureUri.provenanceVerificationStatus,
        ToolchainProvenanceVerificationStatus.failed,
      );
      expect(missingSignatureUri.message, contains('signature URI'));
    },
  );

  test('toolchain install executor stages managed download artifact', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const artifact = 'styio-managed-artifact';
    final artifactSha256 = sha256.convert(artifact.codeUnits).toString();
    server.listen((request) {
      request.response.write(artifact);
      request.response.close();
    });
    final context = PlatformContextSnapshot.compose(
      targetId: 'toolchain-managed-download',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download',
      ),
      pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-managed-download'),
    );
    final platformManagers = await createPlatformManagerBundle(
      platformContext: context,
    );
    final executor = ToolchainInstallExecutor(
      platformManagers: platformManagers,
    );
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.txt',
    );

    final result = await executor.execute(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        expectedSha256: artifactSha256,
        expectedSizeBytes: artifact.length,
        stagedFileName: 'styio-managed.txt',
      ),
    );
    addTearDown(() async {
      final stagedPath = result.stagedPath;
      if (stagedPath != null) {
        await Directory(stagedPath).parent.delete(recursive: true);
      }
    });

    expect(result.status, ToolchainInstallExecutionStatus.staged);
    expect(result.succeeded, isFalse);
    expect(result.networkResponse?.succeeded, isTrue);
    expect(result.artifactSha256, artifactSha256);
    expect(result.artifactSizeBytes, artifact.length);
    expect(
      result.verificationStatus,
      ToolchainArtifactVerificationStatus.verified,
    );
    expect(result.stagedPath, isNotNull);
    expect(result.stagedPath, endsWith('styio-managed.txt'));
    expect(
      await platformManagers.fileSystem.readText(result.stagedPath!),
      artifact,
    );
    expect(result.toJson()['networkResponse'], isA<Map<String, Object?>>());
    expect(result.toJson()['verificationStatus'], 'verified');
  });

  test('toolchain install executor rejects checksum mismatch', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.write('tampered-artifact');
      request.response.close();
    });
    final context = PlatformContextSnapshot.compose(
      targetId: 'toolchain-managed-download-mismatch',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
      pty: PtyFacts.linuxDebianArm(
        targetId: 'toolchain-managed-download-mismatch',
      ),
    );
    final executor = ToolchainInstallExecutor(
      platformManagers: await createPlatformManagerBundle(
        platformContext: context,
      ),
    );
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.txt',
    );

    final result = await executor.execute(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        expectedSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    );

    expect(result.status, ToolchainInstallExecutionStatus.failed);
    expect(
      result.verificationStatus,
      ToolchainArtifactVerificationStatus.failed,
    );
    expect(result.stagedPath, isNull);
    expect(
      result.recoveryActions.map((action) => action.id),
      contains('configure-managed-download'),
    );
    expect(result.message, contains('SHA-256 mismatch'));
  });

  test('toolchain install executor rejects unsafe archive paths', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final archive = createTarArchive(<String, List<int>>{
      'bin/styio': utf8.encode('#!/bin/sh\nprintf styio\n'),
      'vityo-toolchain.json': utf8.encode('{}'),
    });
    server.listen((request) {
      request.response.add(archive);
      request.response.close();
    });
    final platformManagers = await createPlatformManagerBundle(
      platformContext: createLinuxPlatformContext('toolchain-unsafe-archive'),
    );
    final executor = ToolchainInstallExecutor(platformManagers: platformManagers);
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.tar',
    );

    final absoluteExecutable = await executor.execute(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        archiveFormat: ToolchainArchiveFormat.tar,
        archiveExecutablePath: '/bin/styio',
      ),
    );
    final escapingManifest = await executor.execute(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        archiveFormat: ToolchainArchiveFormat.tar,
        archiveExecutablePath: 'bin/styio',
        archiveManifestPath: '../vityo-toolchain.json',
      ),
    );
    addTearDown(() async {
      for (final path in <String?>[
        absoluteExecutable.stagingDirectory,
        absoluteExecutable.extractionDirectory,
        escapingManifest.stagingDirectory,
        escapingManifest.extractionDirectory,
      ]) {
        if (path != null && await platformManagers.fileSystem.exists(path)) {
          await platformManagers.fileSystem.delete(path, recursive: true);
        }
      }
    });

    expect(absoluteExecutable.status, ToolchainInstallExecutionStatus.failed);
    expect(absoluteExecutable.message, contains('is absolute'));
    expect(escapingManifest.status, ToolchainInstallExecutionStatus.failed);
    expect(escapingManifest.extractedExecutablePath, isNotNull);
    expect(escapingManifest.message, contains('escapes the extraction directory'));
  });

  test('toolchain install executor rejects archive executable directories', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final archive = createTarArchive(<String, List<int>>{
      'bin/styio': utf8.encode('#!/bin/sh\nprintf styio\n'),
    });
    final archiveSha256 = sha256.convert(archive).toString();
    server.listen((request) {
      request.response.add(archive);
      request.response.close();
    });
    final platformManagers = await createPlatformManagerBundle(
      platformContext: createLinuxPlatformContext(
        'toolchain-directory-executable',
      ),
    );
    final executor = ToolchainInstallExecutor(platformManagers: platformManagers);
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.tar',
    );

    final result = await executor.execute(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        expectedSha256: archiveSha256,
        expectedSizeBytes: archive.length,
        archiveFormat: ToolchainArchiveFormat.tar,
        archiveExecutablePath: 'bin',
        markExecutable: true,
      ),
    );
    addTearDown(() async {
      for (final path in <String?>[
        result.stagingDirectory,
        result.extractionDirectory,
      ]) {
        if (path != null && await platformManagers.fileSystem.exists(path)) {
          await platformManagers.fileSystem.delete(path, recursive: true);
        }
      }
    });

    expect(result.status, ToolchainInstallExecutionStatus.failed);
    expect(result.extractedExecutablePath, endsWith('bin'));
    expect(result.executablePermissionApplied, isFalse);
    expect(result.message, contains('not executable'));
  });

  test(
    'toolchain install executor preserves binary managed download bytes',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      const artifact = <int>[0, 1, 2, 10, 128, 255];
      final artifactSha256 = sha256.convert(artifact).toString();
      server.listen((request) {
        request.response.add(artifact);
        request.response.close();
      });
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-managed-download-binary',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
        pty: PtyFacts.linuxDebianArm(
          targetId: 'toolchain-managed-download-binary',
        ),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final executor = ToolchainInstallExecutor(
        platformManagers: platformManagers,
      );
      final uri = Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.bin',
      );

      final result = await executor.execute(
        ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: uri,
          expectedSha256: artifactSha256,
          expectedSizeBytes: artifact.length,
          stagedFileName: 'styio.bin',
          markExecutable: true,
        ),
      );
      addTearDown(() async {
        final stagedPath = result.stagedPath;
        if (stagedPath != null) {
          await Directory(stagedPath).parent.delete(recursive: true);
        }
      });

      expect(result.status, ToolchainInstallExecutionStatus.staged);
      expect(result.artifactSha256, artifactSha256);
      expect(result.artifactSizeBytes, artifact.length);
      expect(result.executablePermissionApplied, isTrue);
      expect(
        await platformManagers.fileSystem.readBytes(result.stagedPath!),
        artifact,
      );
      expect(
        await platformManagers.fileSystem.isExecutable(result.stagedPath!),
        isTrue,
      );
    },
  );

  test('toolchain runtime builds process environment from overlays', () async {
    final catalog = ToolchainCatalog();
    catalog.register(
      const ToolchainDescriptor(
        id: 'env',
        kind: ToolchainKind.runner,
        displayName: 'env',
        executablePath: '/usr/bin/env',
      ),
      activate: true,
    );
    final runtime = ToolchainRuntime(
      catalog: catalog,
      processManager: LocalProcessManager.linuxDebianArmForTest(),
      environmentBuilder: const ToolchainEnvironmentBuilder(
        inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
      ),
    );

    final result = await runtime.run(
      kind: ToolchainKind.runner,
      environmentOverlays: const <EnvironmentVariableOverlay>[
        EnvironmentVariableOverlay(
          id: 'toolchain',
          scope: EnvironmentVariableOverlayScope.toolchain,
          target: 'runner',
          variables: <String, String?>{'STYIO_MODE': 'nightly'},
          pathPrepend: <String>['/opt/styio/bin'],
        ),
      ],
      environment: const <String, String>{'STYIO_MODE': 'runtime'},
    );

    expect(result.succeeded, isTrue);
    expect(result.stdout, contains('STYIO_MODE=runtime'));
    expect(result.stdout, contains('PATH=/opt/styio/bin:/usr/bin'));
  }, skip: Platform.isWindows ? 'POSIX process fixture.' : false);

  test(
    'toolchain environment derives PATH list separator from platform context',
    () {
      final builder = ToolchainEnvironmentBuilder.fromPlatformContext(
        createWindowsPlatformContext(),
        inheritedEnvironment: const <String, String>{
          'PATH': r'C:\Windows\System32',
        },
      );
      final resolved = builder.build(
        overlays: const <EnvironmentVariableOverlay>[
          EnvironmentVariableOverlay(
            id: 'windows-toolchain',
            scope: EnvironmentVariableOverlayScope.toolchain,
            target: 'runner',
            pathPrepend: <String>[r'C:\Styio\bin'],
            pathAppend: <String>[r'C:\Workspace\bin'],
          ),
        ],
      );

      expect(builder.pathSeparator, ';');
      expect(
        resolved['PATH'],
        r'C:\Styio\bin;C:\Windows\System32;C:\Workspace\bin',
      );
    },
  );

  test('toolchain payload codec encodes and decodes service payloads', () {
    const codec = ToolchainPayloadCodec();

    final jsonPayload = codec.encodeJson(
      const <String, Object?>{'kind': 'diagnostic', 'count': 2},
      metadata: const <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
    );
    final jsonLinesPayload = codec.encodeJsonLines(const <Map<String, Object?>>[
      <String, Object?>{'line': 1, 'message': 'first'},
      <String, Object?>{'line': 2, 'message': 'second'},
    ]);

    expect(jsonPayload.format, ToolchainPayloadFormat.json);
    expect(jsonPayload.metadata['contract'], 'styio-cli-jsonl-v1');
    expect(codec.decodeJson(jsonPayload)['kind'], 'diagnostic');
    expect(codec.decodeJsonLines(jsonLinesPayload), hasLength(2));
    expect(codec.decodeJsonLines(jsonLinesPayload).last['message'], 'second');
  });

  test('toolchain configuration store persists catalog selection', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_configuration_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final configurationStore = await createConfigurationStore(tempRoot);
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final catalog = ToolchainCatalog()
      ..register(
        const ToolchainDescriptor(
          id: 'styio-nightly',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Nightly',
          executablePath: '/usr/local/bin/styio',
          version: 'nightly',
          channel: 'nightly',
          metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
        ),
        activate: true,
      )
      ..register(
        const ToolchainDescriptor(
          id: 'printf',
          kind: ToolchainKind.runner,
          displayName: 'printf',
          executablePath: '/usr/bin/printf',
        ),
        activate: true,
      );

    await toolchainStore.saveCatalog(catalog, workspaceId: 'demo');
    final loaded = await toolchainStore.loadCatalog(workspaceId: 'demo');

    expect(loaded.list(), hasLength(2));
    expect(loaded.active(ToolchainKind.languageService)?.id, 'styio-nightly');
    expect(
      loaded.active(ToolchainKind.runner)?.executablePath,
      '/usr/bin/printf',
    );
    expect(
      loaded.lookup('styio-nightly')?.metadata['contract'],
      'styio-cli-jsonl-v1',
    );
  });

  test(
    'toolchain manager loads catalog and runs through platform managers',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_manager_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-manager',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-manager',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-manager',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(targetId: 'toolchain-manager'),
        resource: ResourceFacts.linuxDebianArm(targetId: 'toolchain-manager'),
        network: NetworkFacts.linuxDebianArm(targetId: 'toolchain-manager'),
        clipboard: ClipboardFacts.linuxDebianArm(targetId: 'toolchain-manager'),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-manager',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-manager',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-manager'),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final catalogChanges = <ToolchainCatalogConfigurationChange>[];
      final subscription = toolchainStore
          .watchCatalog(workspaceId: 'demo', targetId: 'toolchain-manager')
          .listen(catalogChanges.add);
      addTearDown(subscription.cancel);
      final manager = ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
        workspaceId: 'demo',
      );
      final registration = await manager.registerToolchain(
        const ToolchainDescriptor(
          id: 'printf',
          kind: ToolchainKind.runner,
          displayName: 'printf',
          executablePath: '/usr/bin/printf',
        ),
        activate: true,
      );
      final duplicateRegistration = await manager.registerToolchain(
        const ToolchainDescriptor(
          id: 'printf',
          kind: ToolchainKind.runner,
          displayName: 'printf duplicate',
          executablePath: '/usr/bin/printf',
        ),
      );
      final invalidRegistration = await manager.registerToolchain(
        const ToolchainDescriptor(
          id: '',
          kind: ToolchainKind.runner,
          displayName: 'invalid',
          executablePath: '',
        ),
      );
      final snapshot = await manager.snapshot();
      final result = await manager.run(
        kind: ToolchainKind.runner,
        arguments: const <String>['toolchain-manager-ok'],
      );
      final health = await manager.checkHealth(
        kind: ToolchainKind.runner,
        probeArguments: const <String>['toolchain-manager-health'],
      );
      final statusReport = await manager.statusReport(
        kind: ToolchainKind.runner,
        probeArguments: const <String>['toolchain-manager-health'],
      );
      final missingStatusReport = await manager.statusReport(
        kind: ToolchainKind.languageService,
      );
      final missingSelection = await manager.selectToolchain('missing-tool');
      final clearSelection = await manager.clearActiveToolchain(
        ToolchainKind.runner,
      );

      expect(registration.status, ToolchainRegistrationStatus.registered);
      expect(registration.succeeded, isTrue);
      expect(registration.toJson()['toolchainId'], 'printf');
      expect(
        duplicateRegistration.status,
        ToolchainRegistrationStatus.duplicate,
      );
      expect(duplicateRegistration.succeeded, isFalse);
      expect(invalidRegistration.status, ToolchainRegistrationStatus.invalid);
      expect(invalidRegistration.succeeded, isFalse);
      expect(
        (await manager.loadCatalog()).active(ToolchainKind.runner),
        isNull,
      );
      expect(snapshot.targetId, 'toolchain-manager');
      expect(snapshot.workspaceId, 'demo');
      expect(snapshot.active(ToolchainKind.runner)?.id, 'printf');
      expect(snapshot.toJson()['entries'], isA<List<Object?>>());
      expect(result.succeeded, isTrue);
      expect(result.stdout, 'toolchain-manager-ok');
      expect(health.healthy, isTrue);
      expect(health.processResult?.stdout, 'toolchain-manager-health');
      expect(statusReport.status, ToolchainManagerStatus.ready);
      expect(statusReport.ready, isTrue);
      expect(statusReport.resolution.descriptor?.id, 'printf');
      expect(
        statusReport.capability(ToolchainKind.runner)?.state,
        ToolchainCapabilityState.active,
      );
      expect(statusReport.capability(ToolchainKind.runner)?.usable, isTrue);
      expect(statusReport.recoveryState.kind, ToolchainRecoveryStateKind.none);
      expect(
        statusReport.health?.processResult?.stdout,
        'toolchain-manager-health',
      );
      expect(statusReport.toJson()['ready'], isTrue);
      expect(missingStatusReport.status, ToolchainManagerStatus.unresolved);
      expect(missingStatusReport.ready, isFalse);
      expect(
        missingStatusReport.snapshot.active(ToolchainKind.runner)?.id,
        'printf',
      );
      expect(
        missingStatusReport.capability(ToolchainKind.runner)?.state,
        ToolchainCapabilityState.active,
      );
      expect(
        missingStatusReport.capability(ToolchainKind.languageService)?.state,
        ToolchainCapabilityState.unresolved,
      );
      expect(
        missingStatusReport.recoveryState.kind,
        ToolchainRecoveryStateKind.needsSelection,
      );
      expect(missingStatusReport.recoveryState.actionable, isTrue);
      expect(
        missingStatusReport.recoveryState.actionIds,
        contains('install-managed-toolchain'),
      );
      expect(
        missingStatusReport.resolution.status,
        ToolchainResolutionStatus.missingKind,
      );
      expect(missingSelection.status, ToolchainSelectionStatus.missing);
      expect(missingSelection.kind, isNull);
      expect(missingSelection.succeeded, isFalse);
      expect(clearSelection.status, ToolchainSelectionStatus.cleared);
      expect(clearSelection.kind, ToolchainKind.runner);
      expect(clearSelection.succeeded, isTrue);
      expect(clearSelection.snapshot.active(ToolchainKind.runner), isNull);
      expect(clearSelection.toJson()['status'], 'cleared');
      expect(
        catalogChanges.map((change) => change.kind),
        <ConfigurationSettingChangeKind>[
          ConfigurationSettingChangeKind.written,
          ConfigurationSettingChangeKind.updated,
        ],
      );
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test('toolchain manager scopes state by platform target', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_target_scope_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final configurationStore = await createConfigurationStore(tempRoot);
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final targetAContext = PlatformContextSnapshot.compose(
      targetId: 'target-a',
      fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'target-a'),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'target-a',
        defaultShellPath: '/bin/sh',
      ),
    );
    final targetBContext = PlatformContextSnapshot.compose(
      targetId: 'target-b',
      fileSystem: FileSystemFacts.linuxDebianArm(targetId: 'target-b'),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'target-b',
        defaultShellPath: '/bin/sh',
      ),
    );
    final managerA = ToolchainManager(
      configurationStore: toolchainStore,
      platformManagers: await createPlatformManagerBundle(
        platformContext: targetAContext,
      ),
      workspaceId: 'demo',
    );
    final managerB = ToolchainManager(
      configurationStore: toolchainStore,
      platformManagers: await createPlatformManagerBundle(
        platformContext: targetBContext,
      ),
      workspaceId: 'demo',
    );

    await managerA.registerToolchain(
      const ToolchainDescriptor(
        id: 'styio-target-a',
        kind: ToolchainKind.languageService,
        displayName: 'Styio Target A',
        executablePath: '/target-a/bin/styio',
      ),
      activate: true,
    );
    await toolchainStore.appendInstallHistory(
      ToolchainInstallHistoryEntry(
        id: 'install-target-a',
        status: 'succeeded',
        mode: 'managedDownload',
        kind: ToolchainKind.languageService.wireValue,
        succeeded: true,
        recordedAt: DateTime.utc(2026, 5, 17),
      ),
      workspaceId: 'demo',
      targetId: 'target-a',
    );

    final snapshotA = await managerA.snapshot();
    final snapshotB = await managerB.snapshot();
    final historyA = await toolchainStore.loadInstallHistory(
      workspaceId: 'demo',
      targetId: 'target-a',
    );
    final historyB = await toolchainStore.loadInstallHistory(
      workspaceId: 'demo',
      targetId: 'target-b',
    );

    expect(snapshotA.targetId, 'target-a');
    expect(
      snapshotA.active(ToolchainKind.languageService)?.id,
      'styio-target-a',
    );
    expect(snapshotB.targetId, 'target-b');
    expect(snapshotB.entries, isEmpty);
    expect(historyA.entries, hasLength(1));
    expect(historyB.entries, isEmpty);
  });

  test(
    'toolchain manager plans and executes external install command',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_manager_install_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-manager-install',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-manager-install',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-manager-install'),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final manager = ToolchainManager(
        configurationStore: ToolchainConfigurationStore(
          configurationStore: configurationStore,
        ),
        platformManagers: platformManagers,
        workspaceId: 'demo',
        environmentBuilder: const ToolchainEnvironmentBuilder(
          inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
        ),
      );
      const requirement = ToolchainRequirement(kind: ToolchainKind.compiler);
      final plan = manager.planInstallation(
        const ToolchainInstallRequest(
          requirement: requirement,
          externalCommand: '/usr/bin/env',
        ),
        policy: const ToolchainInstallPolicy(
          allowedModes: <ToolchainInstallMode>{
            ToolchainInstallMode.externalCommand,
          },
        ),
      );

      final result = await manager.executeInstallPlan(
        plan,
        environment: const <String, String>{'VITYO_MANAGER_INSTALL': 'ok'},
      );
      final historyReport = await manager.statusReport(
        kind: ToolchainKind.compiler,
      );

      expect(plan.mode, ToolchainInstallMode.externalCommand);
      expect(result.status, ToolchainInstallExecutionStatus.succeeded);
      expect(
        result.processResult?.stdout,
        contains('VITYO_MANAGER_INSTALL=ok'),
      );
      expect(historyReport.installHistory?.entries, hasLength(1));
      expect(
        historyReport.installHistory?.entries.single.mode,
        ToolchainInstallMode.externalCommand.name,
      );
      expect(historyReport.installHistory?.entries.single.succeeded, isTrue);

      final runtimePlan = ToolchainInstallRuntimeExecutionPlan.fromInstallPlan(
        plan,
      );
      final runtimeBuffer = RuntimeOutputLiveBuffer();
      final runtimeResult =
          await ToolchainInstallRuntimeExecutionAdapter(
            executor: ToolchainInstallExecutor(
              platformManagers: platformManagers,
              environmentBuilder: const ToolchainEnvironmentBuilder(
                inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
              ),
            ),
            clock: () => DateTime.utc(2026, 5, 20, 18),
          ).executePlan(
            runtimePlan,
            buffer: runtimeBuffer,
            environment: const <String, String>{'VITYO_RUNTIME_INSTALL': 'ok'},
          );

      expect(runtimePlan.ready, isTrue);
      expect(runtimeResult.executed, isTrue);
      expect(runtimeResult.succeeded, isTrue);
      expect(
        runtimeResult.dispatchResult.status,
        RuntimeExecutionDispatchStatus.dispatched,
      );
      expect(
        runtimeResult.outputEvents.map((event) => event.message),
        contains('VITYO_RUNTIME_INSTALL=ok'),
      );
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test('toolchain manager reports install and recovery edge states', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_edge_state_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.write('plain artifact without manifest');
      request.response.close();
    });
    final configurationStore = await createConfigurationStore(tempRoot);
    final platformManagers = await createPlatformManagerBundle(
      platformContext: createLinuxPlatformContext('toolchain-manager-edges'),
    );
    final manager = ToolchainManager(
      configurationStore: ToolchainConfigurationStore(
        configurationStore: configurationStore,
      ),
      platformManagers: platformManagers,
      workspaceId: 'demo',
      environmentBuilder: const ToolchainEnvironmentBuilder(
        inheritedEnvironment: <String, String>{'PATH': '/usr/bin'},
      ),
    );

    final notStaged = await manager.installAndRegisterStagedToolchain(
      const ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.externalCommand,
        requirement: ToolchainRequirement(kind: ToolchainKind.runner),
        externalCommand: '/usr/bin/true',
      ),
      toolchainId: 'external-success',
      displayName: 'External Success',
    );
    await manager.registerToolchain(
      const ToolchainDescriptor(
        id: 'printf-runner',
        kind: ToolchainKind.runner,
        displayName: 'printf',
        executablePath: '/usr/bin/printf',
      ),
      activate: true,
    );
    final failedInstall = await manager.executeInstallPlan(
      const ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.externalCommand,
        requirement: ToolchainRequirement(kind: ToolchainKind.runner),
        externalCommand: '/usr/bin/false',
      ),
    );
    final retryReport = await manager.statusReport(kind: ToolchainKind.runner);
    await manager.registerToolchain(
      const ToolchainDescriptor(
        id: 'false-runner',
        kind: ToolchainKind.runner,
        displayName: 'false',
        executablePath: '/usr/bin/false',
      ),
      activate: true,
    );
    final unhealthyReport = await manager.statusReport(
      kind: ToolchainKind.runner,
      includeHealth: true,
      probeArguments: const <String>[],
    );
    final missingClear = await manager.clearActiveToolchain(
      ToolchainKind.compiler,
    );
    final manifestMissing = await manager.installAndRegisterArchiveManifestToolchain(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: Uri.parse(
          'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio',
        ),
        stagedFileName: 'styio',
      ),
    );
    final cleared = await manager.clearCatalog();

    expect(notStaged.status, ToolchainInstallRegistrationStatus.notStaged);
    expect(notStaged.message, contains('did not produce'));
    expect(failedInstall.status, ToolchainInstallExecutionStatus.failed);
    expect(retryReport.recoveryState.kind, ToolchainRecoveryStateKind.retryAvailable);
    expect(
      retryReport.recoveryState.actionIds,
      contains('retry-install-toolchain'),
    );
    expect(unhealthyReport.status, ToolchainManagerStatus.unhealthy);
    expect(
      unhealthyReport.capability(ToolchainKind.runner)?.state,
      ToolchainCapabilityState.unhealthy,
    );
    expect(
      unhealthyReport.recoveryState.actionIds,
      contains('retry-toolchain-health-check'),
    );
    expect(missingClear.message, contains('No active compiler toolchain'));
    expect(
      manifestMissing.status,
      ToolchainInstallRegistrationStatus.invalidManifest,
    );
    expect(manifestMissing.rolledBack, isTrue);
    expect(cleared, isTrue);
  }, skip: Platform.isWindows ? 'POSIX process fixture.' : false);

  test('toolchain manager registers staged managed artifact', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_staged_register_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    const artifact = <int>[35, 33, 47, 98, 105, 110, 47, 115, 104, 10];
    final artifactSha256 = sha256.convert(artifact).toString();
    server.listen((request) {
      request.response.add(artifact);
      request.response.close();
    });
    final configurationStore = await createConfigurationStore(tempRoot);
    final context = PlatformContextSnapshot.compose(
      targetId: 'toolchain-manager-register-staged',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
      pty: PtyFacts.linuxDebianArm(
        targetId: 'toolchain-manager-register-staged',
      ),
    );
    final platformManagers = await createPlatformManagerBundle(
      platformContext: context,
    );
    final manager = ToolchainManager(
      configurationStore: ToolchainConfigurationStore(
        configurationStore: configurationStore,
      ),
      platformManagers: platformManagers,
      workspaceId: 'demo',
    );
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio',
    );

    final result = await manager.installAndRegisterStagedToolchain(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
          version: '2026.05',
          channel: 'nightly',
        ),
        downloadUri: uri,
        expectedSha256: artifactSha256,
        expectedSizeBytes: artifact.length,
        stagedFileName: 'styio',
        markExecutable: true,
      ),
      toolchainId: 'styio-managed',
      displayName: 'Managed Styio',
      activate: true,
      metadata: const <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
    );
    addTearDown(() async {
      final stagedPath = result.execution.stagedPath;
      if (stagedPath != null) {
        await Directory(stagedPath).parent.delete(recursive: true);
      }
    });
    final loaded = await manager.loadCatalog();
    final active = loaded.active(ToolchainKind.languageService);

    expect(result.status, ToolchainInstallRegistrationStatus.registered);
    expect(result.succeeded, isTrue);
    expect(result.registration?.succeeded, isTrue);
    expect(result.toJson()['registration'], isA<Map<String, Object?>>());
    expect(active?.id, 'styio-managed');
    expect(active?.executablePath, result.execution.stagedPath);
    expect(active?.metadata['artifactSha256'], artifactSha256);
    expect(active?.metadata['contract'], 'styio-cli-jsonl-v1');
    expect(
      await platformManagers.fileSystem.isExecutable(active!.executablePath),
      isTrue,
    );
  });

  test(
    'toolchain manager rolls back staged artifact on registration failure',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_manager_rollback_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      const artifact = <int>[35, 33, 47, 98, 105, 110, 47, 115, 104, 10];
      final artifactSha256 = sha256.convert(artifact).toString();
      server.listen((request) {
        request.response.add(artifact);
        request.response.close();
      });
      final configurationStore = await createConfigurationStore(tempRoot);
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-manager-rollback',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-manager-rollback',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-manager-rollback'),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final manager = ToolchainManager(
        configurationStore: ToolchainConfigurationStore(
          configurationStore: configurationStore,
        ),
        platformManagers: platformManagers,
        workspaceId: 'demo',
      );
      await manager.registerToolchain(
        const ToolchainDescriptor(
          id: 'styio-managed',
          kind: ToolchainKind.languageService,
          displayName: 'Existing Styio',
          executablePath: '/usr/bin/printf',
        ),
      );
      final uri = Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio',
      );

      final result = await manager.installAndRegisterStagedToolchain(
        ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          downloadUri: uri,
          expectedSha256: artifactSha256,
          expectedSizeBytes: artifact.length,
          stagedFileName: 'styio',
        ),
        toolchainId: 'styio-managed',
        displayName: 'Managed Styio',
      );

      expect(
        result.status,
        ToolchainInstallRegistrationStatus.registrationFailed,
      );
      expect(
        result.registration?.status,
        ToolchainRegistrationStatus.duplicate,
      );
      expect(result.rolledBack, isTrue);
      expect(result.execution.stagingDirectory, isNotNull);
      expect(
        await platformManagers.fileSystem.exists(
          result.execution.stagingDirectory!,
        ),
        isFalse,
      );
      expect(result.toJson()['rolledBack'], isTrue);
    },
  );

  test(
    'toolchain manager registers executable extracted from tar archive',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_manager_archive_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final archive = createTarArchive(<String, List<int>>{
        'bin/styio': utf8.encode('#!/bin/sh\nprintf archive-styio\n'),
      });
      final archiveSha256 = sha256.convert(archive).toString();
      server.listen((request) {
        request.response.add(archive);
        request.response.close();
      });
      final configurationStore = await createConfigurationStore(tempRoot);
      final context = PlatformContextSnapshot.compose(
        targetId: 'toolchain-manager-archive',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'toolchain-manager-archive',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'toolchain-manager-archive'),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final manager = ToolchainManager(
        configurationStore: ToolchainConfigurationStore(
          configurationStore: configurationStore,
        ),
        platformManagers: platformManagers,
        workspaceId: 'demo',
      );
      final uri = Uri.parse(
        'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.tar',
      );

      final result = await manager.installAndRegisterStagedToolchain(
        ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.languageService,
            version: '2026.05',
            channel: 'nightly',
          ),
          downloadUri: uri,
          expectedSha256: archiveSha256,
          expectedSizeBytes: archive.length,
          stagedFileName: 'styio.tar',
          archiveFormat: ToolchainArchiveFormat.tar,
          archiveExecutablePath: 'bin/styio',
          markExecutable: true,
        ),
        toolchainId: 'styio-archive',
        displayName: 'Archive Styio',
        activate: true,
      );
      addTearDown(() async {
        final stagingDirectory = result.execution.stagingDirectory;
        if (stagingDirectory != null) {
          await platformManagers.fileSystem.delete(
            stagingDirectory,
            recursive: true,
          );
        }
        final extractionDirectory = result.execution.extractionDirectory;
        if (extractionDirectory != null) {
          await platformManagers.fileSystem.delete(
            extractionDirectory,
            recursive: true,
          );
        }
      });
      final active = (await manager.loadCatalog()).active(
        ToolchainKind.languageService,
      );

      expect(result.status, ToolchainInstallRegistrationStatus.registered);
      expect(result.execution.extractedEntryCount, 1);
      expect(result.execution.extractedExecutablePath, isNotNull);
      expect(active?.id, 'styio-archive');
      expect(active?.executablePath, result.execution.extractedExecutablePath);
      expect(
        await platformManagers.fileSystem.readText(active!.executablePath),
        '#!/bin/sh\nprintf archive-styio\n',
      );
      expect(
        await platformManagers.fileSystem.isExecutable(active.executablePath),
        isTrue,
      );
    },
  );

  test('toolchain manager registers archive layout from manifest', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_archive_manifest_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final archive = createTarArchive(<String, List<int>>{
      'bin/styio': utf8.encode('#!/bin/sh\nprintf manifest-styio\n'),
      'vityo-toolchain.json': utf8.encode(
        jsonEncode(<String, Object?>{
          'id': 'styio-manifest',
          'kind': 'language-service',
          'displayName': 'Manifest Styio',
          'executablePath': 'bin/styio',
          'version': '2026.05',
          'channel': 'nightly',
          'metadata': <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
        }),
      ),
    });
    final archiveSha256 = sha256.convert(archive).toString();
    server.listen((request) {
      request.response.add(archive);
      request.response.close();
    });
    final configurationStore = await createConfigurationStore(tempRoot);
    final context = PlatformContextSnapshot.compose(
      targetId: 'toolchain-manager-archive-manifest',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
      pty: PtyFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-manifest',
      ),
    );
    final platformManagers = await createPlatformManagerBundle(
      platformContext: context,
    );
    final manager = ToolchainManager(
      configurationStore: ToolchainConfigurationStore(
        configurationStore: configurationStore,
      ),
      platformManagers: platformManagers,
      workspaceId: 'demo',
    );
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.tar',
    );

    final result = await manager.installAndRegisterArchiveManifestToolchain(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        expectedSha256: archiveSha256,
        expectedSizeBytes: archive.length,
        stagedFileName: 'styio.tar',
        archiveFormat: ToolchainArchiveFormat.tar,
        archiveManifestPath: 'vityo-toolchain.json',
      ),
      activate: true,
    );
    addTearDown(() async {
      final stagingDirectory = result.execution.stagingDirectory;
      if (stagingDirectory != null) {
        await platformManagers.fileSystem.delete(
          stagingDirectory,
          recursive: true,
        );
      }
      final extractionDirectory = result.execution.extractionDirectory;
      if (extractionDirectory != null) {
        await platformManagers.fileSystem.delete(
          extractionDirectory,
          recursive: true,
        );
      }
    });
    final active = (await manager.loadCatalog()).active(
      ToolchainKind.languageService,
    );

    expect(result.status, ToolchainInstallRegistrationStatus.registered);
    expect(result.execution.extractedManifestPath, isNotNull);
    expect(active?.id, 'styio-manifest');
    expect(active?.displayName, 'Manifest Styio');
    expect(active?.version, '2026.05');
    expect(active?.channel, 'nightly');
    expect(active?.metadata['contract'], 'styio-cli-jsonl-v1');
    expect(
      await platformManagers.fileSystem.readText(active!.executablePath),
      '#!/bin/sh\nprintf manifest-styio\n',
    );
  });

  test('toolchain tar extraction rejects path traversal', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_archive_reject_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final archive = createTarArchive(<String, List<int>>{
      '../escape': utf8.encode('bad'),
    });
    server.listen((request) {
      request.response.add(archive);
      request.response.close();
    });
    final configurationStore = await createConfigurationStore(tempRoot);
    final context = PlatformContextSnapshot.compose(
      targetId: 'toolchain-manager-archive-reject',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
      pty: PtyFacts.linuxDebianArm(
        targetId: 'toolchain-manager-archive-reject',
      ),
    );
    final platformManagers = await createPlatformManagerBundle(
      platformContext: context,
    );
    final manager = ToolchainManager(
      configurationStore: ToolchainConfigurationStore(
        configurationStore: configurationStore,
      ),
      platformManagers: platformManagers,
      workspaceId: 'demo',
    );
    final uri = Uri.parse(
      'http://${InternetAddress.loopbackIPv4.address}:${server.port}/styio.tar',
    );

    final result = await manager.installAndRegisterStagedToolchain(
      ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: const ToolchainRequirement(
          kind: ToolchainKind.languageService,
        ),
        downloadUri: uri,
        archiveFormat: ToolchainArchiveFormat.tar,
        archiveExecutablePath: 'bin/styio',
      ),
      toolchainId: 'styio-archive',
      displayName: 'Archive Styio',
    );

    expect(result.status, ToolchainInstallRegistrationStatus.installFailed);
    expect(result.execution.status, ToolchainInstallExecutionStatus.failed);
    expect(result.execution.message, contains('escapes'));
    expect(result.rolledBack, isTrue);
    expect(
      await platformManagers.fileSystem.exists(
        result.execution.stagingDirectory!,
      ),
      isFalse,
    );
    expect(
      await platformManagers.fileSystem.exists(
        result.execution.extractionDirectory!,
      ),
      isFalse,
    );
    expect((await manager.loadCatalog()).list(), isEmpty);
  });

  test(
    'styio service connector can consume managed toolchain catalog',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_managed_styio_connector_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final context = PlatformContextSnapshot.compose(
        targetId: 'managed-styio-connector',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        network: NetworkFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'managed-styio-connector',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'managed-styio-connector'),
      );
      final manager = ToolchainManager(
        configurationStore: ToolchainConfigurationStore(
          configurationStore: configurationStore,
        ),
        platformManagers: await createPlatformManagerBundle(
          platformContext: context,
        ),
        workspaceId: 'demo',
      );
      await manager.saveCatalog(
        ToolchainCatalog()..register(
          const ToolchainDescriptor(
            id: 'printf-styio',
            kind: ToolchainKind.languageService,
            displayName: 'printf Styio',
            executablePath: '/usr/bin/printf',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        ),
      );
      final connector = ToolchainManagerStyioServiceConnector(manager: manager);

      final health = await connector.checkHealth(
        probeArguments: const <String>['managed-health'],
      );
      final response = await connector.analyzeDocument(
        const StyioServiceDocument(
          documentId: 'fixture://managed',
          text: 'value = 1\nvalue\n',
          revision: 1,
          filePath: '/workspace/main.styio',
        ),
      );

      expect(health.healthy, isTrue);
      expect(health.processResult?.stdout, 'managed-health');
      expect(response.status, StyioServiceStatus.succeeded);
      expect(response.toolchainId, 'printf-styio');
      expect(response.stdout, contains('--parser-engine'));
    },
    skip: Platform.isWindows ? 'POSIX process fixture.' : false,
  );

  test(
    'styio service connector health forwards environment overlays',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_managed_styio_health_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final context = PlatformContextSnapshot.compose(
        targetId: 'managed-styio-health',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'managed-styio-health',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'managed-styio-health',
          defaultShellPath: '/bin/sh',
        ),
        process: ProcessFacts.linuxDebianArm(targetId: 'managed-styio-health'),
        resource: ResourceFacts.linuxDebianArm(
          targetId: 'managed-styio-health',
        ),
        network: NetworkFacts.linuxDebianArm(targetId: 'managed-styio-health'),
        clipboard: ClipboardFacts.linuxDebianArm(
          targetId: 'managed-styio-health',
        ),
        notification: NotificationFacts.linuxDebianArm(
          targetId: 'managed-styio-health',
        ),
        localService: LocalServiceFacts.linuxDebianArm(
          targetId: 'managed-styio-health',
        ),
        pty: PtyFacts.linuxDebianArm(targetId: 'managed-styio-health'),
      );
      final manager = ToolchainManager(
        configurationStore: ToolchainConfigurationStore(
          configurationStore: configurationStore,
        ),
        platformManagers: await createPlatformManagerBundle(
          platformContext: context,
        ),
        workspaceId: 'demo',
      );
      await manager.saveCatalog(
        ToolchainCatalog()..register(
          const ToolchainDescriptor(
            id: 'shell-styio-health',
            kind: ToolchainKind.languageService,
            displayName: 'Shell Styio Health',
            executablePath: '/bin/sh',
            metadata: <String, Object?>{'contract': 'styio-cli-jsonl-v1'},
          ),
          activate: true,
        ),
      );
      final connector = ToolchainManagerStyioServiceConnector(manager: manager);

      final health = await connector.checkHealth(
        probeArguments: const <String>[
          '-c',
          r'printf "$STYIO_MODE:$STYIO_CHANNEL:$(pwd)"',
        ],
        environmentOverlays: const <EnvironmentVariableOverlay>[
          EnvironmentVariableOverlay(
            id: 'styio-health',
            scope: EnvironmentVariableOverlayScope.toolchain,
            target: 'styio-service',
            variables: <String, String?>{'STYIO_CHANNEL': 'nightly'},
          ),
        ],
        environment: const <String, String>{'STYIO_MODE': 'runtime'},
        workingDirectory: tempRoot.path,
      );

      expect(health.healthy, isTrue);
      final expectedWorkingDirectory = tempRoot.resolveSymbolicLinksSync();
      expect(
        health.processResult?.stdout,
        'runtime:nightly:$expectedWorkingDirectory',
      );
    },
    skip: Platform.isWindows ? 'POSIX shell fixture.' : false,
  );

  test(
    'styio language toolchain discovery is owned by toolchain layer',
    () async {
      final catalog = await createPlatformStyioLanguageToolchainCatalog();
      final discovered = catalog.list();

      expect(
        discovered.every(
          (descriptor) => descriptor.kind == ToolchainKind.languageService,
        ),
        isTrue,
      );
    },
  );

  test(
    'styio language toolchain discovery can use platform managers',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_discovery_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final context = PlatformContextSnapshot.compose(
        targetId: 'managed-discovery',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'managed-discovery',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'managed-discovery',
          defaultShellPath: '/bin/sh',
        ),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final styioPath = platformManagers.fileSystem.joinPath(<String>[
        tempRoot.path,
        'styio',
      ]);
      await platformManagers.fileSystem.writeText(styioPath, '#!/bin/sh\n');
      await platformManagers.fileSystem.setExecutable(styioPath);

      final catalog = await createPlatformStyioLanguageToolchainCatalog(
        platformManagers: platformManagers,
        environment: const <String, String>{},
        candidatePaths: <String>[styioPath],
      );
      final active = catalog.active(ToolchainKind.languageService);

      expect(active, isNotNull);
      expect(active!.executablePath, styioPath);
      expect(active.metadata['source'], 'platform-discovery');
    },
  );

  test(
    'native compiler discovery registers clang and clang++ as one compiler toolchain',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_native_compiler_discovery_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final context = PlatformContextSnapshot.compose(
        targetId: 'native-compiler-discovery',
        fileSystem: FileSystemFacts.linuxDebianArm(
          targetId: 'native-compiler-discovery',
        ),
        shell: ShellFacts.linuxDebianArm(
          targetId: 'native-compiler-discovery',
          defaultShellPath: '/bin/sh',
        ),
      );
      final platformManagers = await createPlatformManagerBundle(
        platformContext: context,
      );
      final clangPath = platformManagers.fileSystem.joinPath(<String>[
        tempRoot.path,
        'clang',
      ]);
      final clangxxPath = platformManagers.fileSystem.joinPath(<String>[
        tempRoot.path,
        'clang++',
      ]);
      await platformManagers.fileSystem.writeText(clangPath, '#!/bin/sh\n');
      await platformManagers.fileSystem.writeText(clangxxPath, '#!/bin/sh\n');
      await platformManagers.fileSystem.setExecutable(clangPath);
      await platformManagers.fileSystem.setExecutable(clangxxPath);

      final catalog = await createPlatformNativeCompilerToolchainCatalog(
        platformManagers: platformManagers,
        environment: const <String, String>{},
        cCompilerCandidatePaths: <String>[clangPath],
        cxxCompilerCandidatePaths: <String>[clangxxPath],
        clangVersionOutputProbe: (_) async =>
            'Ubuntu clang version 18.1.3 (1ubuntu1)\n'
            'Target: aarch64-unknown-linux-gnu\n',
      );
      final active = catalog.active(ToolchainKind.compiler);

      expect(active, isNotNull);
      expect(active!.id, 'native-clang-cpp-compiler');
      expect(active.executablePath, clangxxPath);
      expect(active.version, '18.1.3');
      expect(active.metadata['compilerFamily'], 'clang');
      expect(active.metadata['clangVersion'], '18.1.3');
      expect(active.metadata['clangVendor'], 'ubuntu');
      expect(active.metadata['clangVersionSource'], 'clang++ --version');
      expect(active.metadata['cCompilerPath'], clangPath);
      expect(active.metadata['cxxCompilerPath'], clangxxPath);
      expect(active.metadata['languages'], <String>['c', 'cpp']);
      expect(active.metadata['defaultForNativeCode'], isTrue);
    },
  );

  test(
    'terminal runtime derives PATH list separator from platform context',
    () async {
      final terminal = TerminalRuntime.fromPlatformContext(
        platformContext: createWindowsPlatformContext(),
        ptyManager: UnsupportedPtyManager(
          facts: PtyFacts.linuxDebianArm(targetId: 'windows-toolchain'),
        ),
        inheritedEnvironment: const <String, String>{
          'PATH': r'C:\Windows\System32',
        },
        shellConfiguration: const ShellConfiguration(
          defaultProfileId: 'cmd',
          profiles: <ShellProfileConfiguration>[
            ShellProfileConfiguration(
              id: 'cmd',
              executablePath: r'C:\Windows\System32\cmd.exe',
              family: ShellFamily.sh,
            ),
          ],
        ),
      );

      final session = await terminal.start(
        environmentOverlays: const <EnvironmentVariableOverlay>[
          EnvironmentVariableOverlay(
            id: 'windows-terminal',
            scope: EnvironmentVariableOverlayScope.workspace,
            target: 'terminal',
            pathPrepend: <String>[r'C:\Styio\bin'],
            pathAppend: <String>[r'C:\Workspace\bin'],
          ),
        ],
      );
      final request = (session as UnsupportedPtySession).request;

      expect(
        request.environment['PATH'],
        r'C:\Styio\bin;C:\Windows\System32;C:\Workspace\bin',
      );
    },
  );

  test(
    'terminal runtime starts configured shell through pty manager',
    () async {
      final ptyFacts = await const LocalPtyProber().probe();
      final terminal = TerminalRuntime(
        ptyManager: LocalPtyManager(facts: ptyFacts),
        shellConfiguration: const ShellConfiguration(
          defaultProfileId: 'sh',
          environmentOverlay: <String, String>{'STYIO_MODE': 'config'},
          profiles: <ShellProfileConfiguration>[
            ShellProfileConfiguration(
              id: 'sh',
              executablePath: '/bin/sh',
              family: ShellFamily.sh,
              arguments: <String>[
                '-c',
                r'test -t 1 && printf "terminal-ok:$STYIO_MODE:$STYIO_CHANNEL:$RUNTIME_FLAG"',
              ],
              environment: <String, String>{'STYIO_MODE': 'profile'},
            ),
          ],
        ),
      );

      final session = await terminal.start(
        envFileVariables: const <Map<String, String?>>[
          <String, String?>{'STYIO_CHANNEL': 'nightly'},
        ],
        environmentOverlays: const <EnvironmentVariableOverlay>[
          EnvironmentVariableOverlay(
            id: 'workspace-terminal',
            scope: EnvironmentVariableOverlayScope.workspace,
            target: 'terminal',
            variables: <String, String?>{'STYIO_MODE': 'overlay'},
          ),
        ],
        environment: const <String, String>{'RUNTIME_FLAG': 'runtime'},
      );
      final outputFuture = session.output.join();
      final exitCode = await session.exitCode.timeout(
        const Duration(seconds: 5),
      );
      final output = await outputFuture.timeout(const Duration(seconds: 5));

      expect(exitCode, 0);
      expect(output, contains('terminal-ok:profile:nightly:runtime'));
    },
    skip: !Platform.isLinux ? 'Linux script PTY backend only.' : false,
  );

  test(
    'native compiler discovery exposes CMake Ninja and clangd toolchain facts',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_native_cpp_tools_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      Future<String> fakeTool(String name) async {
        final file = File('${tempRoot.path}/$name');
        await file.writeAsString('fake $name');
        return file.path;
      }

      final clang = await fakeTool('clang');
      final clangxx = await fakeTool('clang++');
      final cmake = await fakeTool('cmake');
      final ninja = await fakeTool('ninja');
      final clangd = await fakeTool('clangd');
      final catalog = await createPlatformNativeCompilerToolchainCatalog(
        environment: <String, String>{
          'VITYO_CLANG_BIN': clang,
          'VITYO_CLANGXX_BIN': clangxx,
          'VITYO_CMAKE_BIN': cmake,
          'VITYO_NINJA_BIN': ninja,
          'VITYO_CLANGD_BIN': clangd,
        },
        cCompilerCandidatePaths: const <String>[],
        cxxCompilerCandidatePaths: const <String>[],
        cmakeCandidatePaths: const <String>[],
        ninjaCandidatePaths: const <String>[],
        clangdCandidatePaths: const <String>[],
      );

      final compiler = catalog.active(ToolchainKind.compiler)!;
      final cmakeDescriptor = catalog.lookup('native-cmake-build-tool')!;
      final ninjaDescriptor = catalog.lookup('native-ninja-build-tool')!;
      final clangdDescriptor = catalog.lookup(
        'native-clangd-language-service',
      )!;

      expect(compiler.metadata['compilerFamily'], 'clang');
      expect(compiler.metadata['cCompilerPath'], clang);
      expect(compiler.metadata['cxxCompilerPath'], clangxx);
      expect(cmakeDescriptor.kind, ToolchainKind.buildTool);
      expect(cmakeDescriptor.executablePath, cmake);
      expect(cmakeDescriptor.metadata['projectModel'], 'cmake');
      expect(cmakeDescriptor.metadata['supportsPresets'], isTrue);
      expect(ninjaDescriptor.kind, ToolchainKind.buildTool);
      expect(ninjaDescriptor.executablePath, ninja);
      expect(ninjaDescriptor.metadata['buildSystem'], 'ninja');
      expect(clangdDescriptor.kind, ToolchainKind.languageService);
      expect(clangdDescriptor.executablePath, clangd);
      expect(clangdDescriptor.metadata['consumesCompileCommands'], isTrue);
    },
  );

  test(
    'native C++ developer tools expose debugger formatter analyzer and test runner facts',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_native_cpp_dev_tools_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      Future<String> fakeTool(String name) async {
        final file = File('${tempRoot.path}/$name');
        await file.writeAsString('fake $name');
        return file.path;
      }

      final lldb = await fakeTool('lldb');
      final gdb = await fakeTool('gdb');
      final clangFormat = await fakeTool('clang-format');
      final clangTidy = await fakeTool('clang-tidy');
      final ctest = await fakeTool('ctest');
      final catalog = await createPlatformNativeCompilerToolchainCatalog(
        environment: <String, String>{
          'VITYO_LLDB_BIN': lldb,
          'VITYO_GDB_BIN': gdb,
          'VITYO_CLANG_FORMAT_BIN': clangFormat,
          'VITYO_CLANG_TIDY_BIN': clangTidy,
          'VITYO_CTEST_BIN': ctest,
        },
        cCompilerCandidatePaths: const <String>[],
        cxxCompilerCandidatePaths: const <String>[],
        cmakeCandidatePaths: const <String>[],
        ninjaCandidatePaths: const <String>[],
        clangdCandidatePaths: const <String>[],
        lldbCandidatePaths: const <String>[],
        gdbCandidatePaths: const <String>[],
        clangFormatCandidatePaths: const <String>[],
        clangTidyCandidatePaths: const <String>[],
        ctestCandidatePaths: const <String>[],
      );

      final lldbDescriptor = catalog.lookup('native-lldb-debugger')!;
      final gdbDescriptor = catalog.lookup('native-gdb-debugger')!;
      final clangFormatDescriptor = catalog.lookup(
        'native-clang-format-formatter',
      )!;
      final clangTidyDescriptor = catalog.lookup(
        'native-clang-tidy-static-analyzer',
      )!;
      final ctestDescriptor = catalog.lookup('native-ctest-test-runner')!;

      expect(lldbDescriptor.kind, ToolchainKind.debugger);
      expect(lldbDescriptor.executablePath, lldb);
      expect(lldbDescriptor.metadata['debuggerKind'], 'lldb');
      expect(gdbDescriptor.kind, ToolchainKind.debugger);
      expect(gdbDescriptor.executablePath, gdb);
      expect(gdbDescriptor.metadata['debuggerKind'], 'gdb');
      expect(clangFormatDescriptor.kind, ToolchainKind.formatter);
      expect(clangFormatDescriptor.executablePath, clangFormat);
      expect(clangFormatDescriptor.metadata['toolRole'], 'formatter');
      expect(clangFormatDescriptor.metadata['configurationFiles'], <String>[
        '.clang-format',
        '_clang-format',
      ]);
      expect(clangTidyDescriptor.kind, ToolchainKind.staticAnalyzer);
      expect(clangTidyDescriptor.executablePath, clangTidy);
      expect(clangTidyDescriptor.metadata['toolRole'], 'static-analysis');
      expect(clangTidyDescriptor.metadata['consumesCompileCommands'], isTrue);
      expect(ctestDescriptor.kind, ToolchainKind.testRunner);
      expect(ctestDescriptor.executablePath, ctest);
      expect(ctestDescriptor.metadata['toolRole'], 'test-runner');
      expect(ctestDescriptor.metadata['projectModel'], 'cmake');
    },
  );
}

List<int> createTarArchive(Map<String, List<int>> files) {
  final archive = <int>[];
  for (final entry in files.entries) {
    final header = createTarHeader(entry.key, entry.value.length);
    archive.addAll(header);
    archive.addAll(entry.value);
    final remainder = entry.value.length % 512;
    if (remainder != 0) {
      archive.addAll(List<int>.filled(512 - remainder, 0));
    }
  }
  archive.addAll(List<int>.filled(1024, 0));
  return archive;
}

List<int> createTarHeader(String name, int size) {
  final header = List<int>.filled(512, 0);
  writeTarField(header, 0, 100, name);
  writeTarField(header, 100, 8, '0000755');
  writeTarField(header, 108, 8, '0000000');
  writeTarField(header, 116, 8, '0000000');
  writeTarField(header, 124, 12, size.toRadixString(8).padLeft(11, '0'));
  writeTarField(header, 136, 12, '00000000000');
  for (var index = 148; index < 156; index += 1) {
    header[index] = 32;
  }
  header[156] = 48;
  writeTarField(header, 257, 6, 'ustar');
  writeTarField(header, 263, 2, '00');
  final checksum = header.fold<int>(0, (sum, byte) => sum + byte);
  writeTarField(header, 148, 8, checksum.toRadixString(8).padLeft(6, '0'));
  header[154] = 0;
  header[155] = 32;
  return header;
}

void writeTarField(List<int> header, int offset, int length, String value) {
  final bytes = ascii.encode(value);
  for (var index = 0; index < bytes.length && index < length; index += 1) {
    header[offset + index] = bytes[index];
  }
}
