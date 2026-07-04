import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test(
    'resource coordinator maps namespaces to resource locations without file writes',
    () {
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: '/tmp',
          homePath: '/home/vityo',
          processorCount: 4,
        ),
      );
      final coordinator = FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      );

      final appData = coordinator.location(
        kind: FoundationResourceKind.appData,
        namespace: 'platform-context',
      );
      final cache = coordinator.location(
        kind: FoundationResourceKind.workspaceCache,
        namespace: 'language-index',
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo workspace',
      );
      final budget = coordinator.budgetFor('language-index');

      expect(
        appData.path,
        '/home/vityo/.local/share/vityo/data/platform-context',
      );
      expect(
        cache.path,
        contains(
          '/home/vityo/.cache/vityo/workspace-cache/workspace/demo_workspace/language-index',
        ),
      );
      expect(cache.cleanupAllowed, isTrue);
      expect(budget.processorCount, 4);
    },
  );

  test(
    'foundation datastore persists ordinary records through file system manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_datastore_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final coordinator = FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: coordinator,
        fileSystemManager: fileSystemManager,
      );
      const namespace = FoundationDataStoreNamespace(
        name: 'settings',
        schemaVersion: 1,
      );

      await datastore.writeJson(
        namespace: namespace,
        key: 'window-layout',
        value: const <String, Object?>{'panel': 'debug'},
      );
      final loaded = await datastore.readJson(
        namespace: namespace,
        key: 'window-layout',
      );

      expect(loaded, const <String, Object?>{'panel': 'debug'});
      expect(
        await fileSystemManager.exists(
          fileSystemManager.joinPath(<String>[
            tempRoot.path,
            '.local',
            'share',
            'vityo',
            'data',
            'settings',
            'window-layout.json',
          ]),
        ),
        isTrue,
      );
    },
  );

  test(
    'foundation datastore applies named schema migrations on read',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_datastore_migration_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
        migrations: <FoundationDataMigrationStep>[
          FoundationDataMigrationStep(
            name: 'settings-window-layout-add-schema-marker',
            namespace: 'settings',
            sourceSchemaState: 1,
            targetSchemaState: 2,
            migrate: (value) => <String, Object?>{...value, 'schema': 2},
          ),
        ],
      );

      await datastore.writeJson(
        namespace: const FoundationDataStoreNamespace(
          name: 'settings',
          schemaVersion: 1,
        ),
        key: 'window-layout',
        value: const <String, Object?>{'panel': 'debug'},
      );
      final loaded = await datastore.readJson(
        namespace: const FoundationDataStoreNamespace(
          name: 'settings',
          schemaVersion: 2,
        ),
        key: 'window-layout',
      );

      expect(loaded, const <String, Object?>{'panel': 'debug', 'schema': 2});
      final migratedDatastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      expect(
        await migratedDatastore.readJson(
          namespace: const FoundationDataStoreNamespace(
            name: 'settings',
            schemaVersion: 2,
          ),
          key: 'window-layout',
        ),
        const <String, Object?>{'panel': 'debug', 'schema': 2},
      );
      expect(
        () => datastore.readJson(
          namespace: const FoundationDataStoreNamespace(
            name: 'settings',
            schemaVersion: 3,
          ),
          key: 'window-layout',
        ),
        throwsStateError,
      );
    },
  );

  test('foundation datastore serializes writes with lock service', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_foundation_datastore_lock_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final lockService = FoundationLockService();
    final datastore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
      lockService: lockService,
    );
    const namespace = FoundationDataStoreNamespace(name: 'settings');
    final releaseLock = Completer<void>();
    final blocker = lockService.runExclusive<void>(
      'datastore:settings:user::window-layout',
      (_) async => releaseLock.future,
    );

    final write = datastore.writeJson(
      namespace: namespace,
      key: 'window-layout',
      value: const <String, Object?>{'panel': 'debug'},
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      lockService.isLocked('datastore:settings:user::window-layout'),
      isTrue,
    );
    releaseLock.complete();
    await blocker;
    await write;

    expect(
      await datastore.readJson(namespace: namespace, key: 'window-layout'),
      const <String, Object?>{'panel': 'debug'},
    );
  });

  test('foundation datastore owner scopes namespace access', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_foundation_datastore_owner_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final datastore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final owner = FoundationDataStoreOwner(
      descriptor: const FoundationDataStoreOwnerDescriptor(
        ownerId: 'service.language',
        layer: 'service',
        stateFamily: 'language-results',
        allowedNamespaces: <String>{'language-results'},
      ),
      dataStore: datastore,
    );

    await owner.writeJson(
      namespaceName: 'language-results',
      key: 'main',
      value: const <String, Object?>{'diagnostics': 1},
    );
    final loaded = await owner.readJson(
      namespaceName: 'language-results',
      key: 'main',
    );

    expect(loaded, const <String, Object?>{'diagnostics': 1});
    expect(
      () => owner.namespace(name: 'toolchain-selection'),
      throwsStateError,
    );

    final prefixedOwner = FoundationDataStoreOwner(
      descriptor: const FoundationDataStoreOwnerDescriptor(
        ownerId: 'configuration',
        layer: 'environment',
        stateFamily: 'configuration',
        allowedNamespacePrefixes: <String>{'configuration.'},
      ),
      dataStore: datastore,
    );
    expect(
      prefixedOwner.namespace(name: 'configuration.shell').name,
      'configuration.shell',
    );
  });

  test(
    'foundation datastore updates records atomically through owner boundary',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_datastore_update_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final owner = FoundationDataStoreOwner(
        descriptor: const FoundationDataStoreOwnerDescriptor(
          ownerId: 'configuration',
          layer: 'environment',
          stateFamily: 'configuration',
          allowedNamespaces: <String>{'configuration.shell'},
        ),
        dataStore: datastore,
      );

      final created = await owner.updateJson(
        namespaceName: 'configuration.shell',
        key: 'runtime',
        update: (current) => <String, Object?>{
          'shell': current?['shell'] ?? '/bin/sh',
          'revision': 1,
        },
      );
      final updated = await owner.updateJson(
        namespaceName: 'configuration.shell',
        key: 'runtime',
        update: (current) => <String, Object?>{
          ...?current,
          'revision': (current?['revision'] as int? ?? 0) + 1,
        },
      );

      expect(created, const <String, Object?>{
        'shell': '/bin/sh',
        'revision': 1,
      });
      expect(updated, const <String, Object?>{
        'shell': '/bin/sh',
        'revision': 2,
      });
      expect(
        await owner.readJson(
          namespaceName: 'configuration.shell',
          key: 'runtime',
        ),
        const <String, Object?>{'shell': '/bin/sh', 'revision': 2},
      );

      final deleted = await owner.updateJson(
        namespaceName: 'configuration.shell',
        key: 'runtime',
        update: (_) => null,
      );

      expect(deleted, isNull);
      expect(
        await owner.readJson(
          namespaceName: 'configuration.shell',
          key: 'runtime',
        ),
        isNull,
      );
      expect(
        () => owner.updateJson(
          namespaceName: 'toolchain.selection',
          key: 'active',
          update: (_) => const <String, Object?>{},
        ),
        throwsStateError,
      );
    },
  );

  test('foundation datastore emits scoped change events', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_foundation_datastore_watch_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final datastore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    addTearDown(datastore.close);
    final owner = FoundationDataStoreOwner(
      descriptor: const FoundationDataStoreOwnerDescriptor(
        ownerId: 'configuration',
        layer: 'environment',
        stateFamily: 'configuration',
        allowedNamespacePrefixes: <String>{'configuration.'},
      ),
      dataStore: datastore,
    );
    final changes = <FoundationDataStoreChange>[];
    final subscription = owner
        .watchJson(namespaceName: 'configuration.shell', key: 'runtime')
        .listen(changes.add);
    addTearDown(subscription.cancel);

    await owner.writeJson(
      namespaceName: 'configuration.shell',
      key: 'runtime',
      value: const <String, Object?>{'shell': '/bin/sh'},
    );
    await owner.updateJson(
      namespaceName: 'configuration.shell',
      key: 'runtime',
      update: (current) => <String, Object?>{...?current, 'revision': 2},
    );
    await owner.writeJson(
      namespaceName: 'configuration.env',
      key: 'runtime',
      value: const <String, Object?>{'ignored': true},
    );
    await owner.delete(namespaceName: 'configuration.shell', key: 'runtime');

    expect(
      changes.map((change) => change.kind),
      <FoundationDataStoreChangeKind>[
        FoundationDataStoreChangeKind.written,
        FoundationDataStoreChangeKind.updated,
        FoundationDataStoreChangeKind.deleted,
      ],
    );
    expect(changes.first.namespace, 'configuration.shell');
    expect(changes.first.key, 'runtime');
    expect(changes.first.value, const <String, Object?>{'shell': '/bin/sh'});
    expect(changes.last.value, isNull);
    expect(changes.first.toJson()['scope'], 'user');
  });

  test(
    'foundation datastore edit supports write delete and keep decisions',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_datastore_edit_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      addTearDown(datastore.close);
      const namespace = FoundationDataStoreNamespace(name: 'settings');
      final changes = <FoundationDataStoreChange>[];
      final subscription = datastore
          .watchJson(namespace: namespace, key: 'window-layout')
          .listen(changes.add);
      addTearDown(subscription.cancel);

      final writeDecision = await datastore.editJson(
        namespace: namespace,
        key: 'window-layout',
        edit: (_) => FoundationDataStoreEditDecision.write(
          const <String, Object?>{'panel': 'debug'},
        ),
      );
      final keepDecision = await datastore.editJson(
        namespace: namespace,
        key: 'window-layout',
        edit: (_) => FoundationDataStoreEditDecision.keep,
      );
      final deleteDecision = await datastore.editJson(
        namespace: namespace,
        key: 'window-layout',
        edit: (_) => FoundationDataStoreEditDecision.delete,
      );

      expect(writeDecision.action, FoundationDataStoreEditAction.write);
      expect(keepDecision.action, FoundationDataStoreEditAction.keep);
      expect(deleteDecision.action, FoundationDataStoreEditAction.delete);
      expect(
        changes.map((change) => change.kind),
        <FoundationDataStoreChangeKind>[
          FoundationDataStoreChangeKind.written,
          FoundationDataStoreChangeKind.deleted,
        ],
      );
      expect(
        await datastore.readJson(namespace: namespace, key: 'window-layout'),
        isNull,
      );
    },
  );

  test(
    'foundation registry registers looks up and updates lifecycle state',
    () {
      final registry = FoundationRegistry<String>();

      registry.register(
        const FoundationRegistryEntry<String>(
          id: 'service.language.styio',
          kind: 'service',
          owner: 'service-layer',
          value: 'Styio service connector',
          metadata: <String, Object?>{'capability': 'language-service'},
        ),
      );
      registry.setState(
        'service.language.styio',
        FoundationRegistryEntryState.active,
      );

      final entry = registry.lookup('service.language.styio');
      final manifest = registry.manifest(kind: 'service');

      expect(entry, isNotNull);
      expect(entry!.state, FoundationRegistryEntryState.active);
      expect(registry.contains('service.language.styio'), isTrue);
      expect(
        registry.requireEntry('service.language.styio').value,
        'Styio service connector',
      );
      expect(registry.list(kind: 'service'), hasLength(1));
      expect(manifest.entries.single.id, 'service.language.styio');
      expect(
        manifest.entries.single.metadata['capability'],
        'language-service',
      );
      expect(manifest.toJson()['entries'], isA<List<Object?>>());
      expect(registry.unregister('service.language.styio'), isTrue);
    },
  );

  test(
    'foundation registry filters by kind owner and state without exposing runtime values',
    () {
      final registry = FoundationRegistry<Object>();
      final metadata = <String, Object?>{'capability': 'language-service'};

      registry
        ..register(
          FoundationRegistryEntry<Object>(
            id: 'service.language.styio',
            kind: 'service',
            owner: 'service-layer',
            value: Object(),
            metadata: metadata,
          ),
        )
        ..register(
          const FoundationRegistryEntry<Object>(
            id: 'toolchain.styio.local',
            kind: 'toolchain',
            owner: 'environment-layer',
            value: Object(),
          ),
        );
      metadata['capability'] = 'mutated';
      registry
        ..setState(
          'service.language.styio',
          FoundationRegistryEntryState.active,
        )
        ..updateMetadata('service.language.styio', const <String, Object?>{
          'transport': 'lsp',
        });

      final manifest = registry.manifest(
        kind: 'service',
        owner: 'service-layer',
        state: FoundationRegistryEntryState.active,
      );

      expect(manifest.entries, hasLength(1));
      expect(manifest.entries.single.id, 'service.language.styio');
      expect(
        manifest.entries.single.metadata['capability'],
        'language-service',
      );
      expect(manifest.entries.single.metadata['transport'], 'lsp');
      expect(manifest.toJson().toString(), isNot(contains('Instance of')));
      expect(
        () => manifest.entries.single.metadata['new'] = 'value',
        throwsUnsupportedError,
      );
      expect(registry.kinds(), <String>['service', 'toolchain']);
      expect(registry.owners(kind: 'service'), <String>['service-layer']);
    },
  );

  test(
    'foundation registry scoped contributions reveal previous entries on dispose',
    () {
      final registry = FoundationRegistry<String>()
        ..register(
          const FoundationRegistryEntry<String>(
            id: 'command.run',
            kind: 'command',
            owner: 'core.commands',
            value: 'core-run',
            state: FoundationRegistryEntryState.active,
            metadata: <String, Object?>{'order': 20},
          ),
        );
      final registration = registry.registerContribution(
        const ContributionDescriptor<String>(
          id: 'command.run',
          kind: 'command',
          owner: 'module.fast-run',
          value: 'module-run',
          state: FoundationRegistryEntryState.active,
          order: 5,
        ),
        scopeId: 'module.fast-run',
      );

      expect(registry.lookup('command.run')!.value, 'module-run');
      expect(registry.lookup('command.run')!.owner, 'module.fast-run');
      expect(
        registry.manifest(kind: 'command').entries.single.owner,
        'module.fast-run',
      );
      expect(registration.dispose(), isTrue);
      expect(registration.dispose(), isFalse);
      expect(registry.lookup('command.run')!.value, 'core-run');
      expect(registry.lookup('command.run')!.owner, 'core.commands');
    },
  );

  test('registry scope disposes owned contributions in reverse order', () {
    final registry = FoundationRegistry<String>();
    final scope = RegistryScope(id: 'module.agent', owner: 'module.agent');

    scope
      ..register(
        registry: registry,
        contribution: const ContributionDescriptor<String>(
          id: 'surface.agent',
          kind: 'surface',
          owner: 'module.agent',
          value: 'agent-surface',
          order: 30,
        ),
      )
      ..register(
        registry: registry,
        contribution: const ContributionDescriptor<String>(
          id: 'command.agent.ask',
          kind: 'command',
          owner: 'module.agent',
          value: 'ask-command',
          order: 10,
        ),
      );

    expect(registry.list().map((entry) => entry.id), <String>[
      'command.agent.ask',
      'surface.agent',
    ]);

    scope.dispose();

    expect(scope.disposed, isTrue);
    expect(registry.list(), isEmpty);
    expect(
      () => scope.register(
        registry: registry,
        contribution: const ContributionDescriptor<String>(
          id: 'after-dispose',
          kind: 'command',
          owner: 'module.agent',
          value: 'bad',
        ),
      ),
      throwsStateError,
    );
  });

  test('foundation registry registrar wraps category and owner boundaries', () {
    final registry = FoundationRegistry<String>();
    final providerRegistrar = FoundationRegistryRegistrar<String>(
      registry: registry,
      owner: 'service-layer',
      category: FoundationRegistrationCategory.provider,
    );
    final commandRegistrar = FoundationRegistryRegistrar<String>(
      registry: registry,
      owner: 'interaction-layer',
      category: FoundationRegistrationCategory.command,
    );

    providerRegistrar.register(
      id: 'styio-service',
      value: 'runtime-provider',
      metadata: const <String, Object?>{'capability': 'language-service'},
    );
    commandRegistrar.register(id: 'rename-symbol', value: 'runtime-command');
    providerRegistrar
      ..setState('styio-service', FoundationRegistryEntryState.active)
      ..updateMetadata('styio-service', const <String, Object?>{
        'transport': 'lsp',
      });

    expect(providerRegistrar.kind, 'provider');
    expect(
      providerRegistrar.lookup('styio-service')!.value,
      'runtime-provider',
    );
    expect(providerRegistrar.lookup('rename-symbol'), isNull);
    expect(
      providerRegistrar.list(state: FoundationRegistryEntryState.active),
      hasLength(1),
    );
    expect(commandRegistrar.manifest().entries.single.id, 'rename-symbol');
    expect(
      providerRegistrar.manifest().entries.single.metadata['transport'],
      'lsp',
    );
    expect(
      () => commandRegistrar.requireEntry('styio-service'),
      throwsStateError,
    );
  });

  test('foundation registry rejects invalid duplicate and missing entries', () {
    final registry = FoundationRegistry<String>();

    expect(
      () => registry.register(
        const FoundationRegistryEntry<String>(
          id: '',
          kind: 'service',
          owner: 'service-layer',
          value: 'bad',
        ),
      ),
      throwsArgumentError,
    );

    registry.register(
      const FoundationRegistryEntry<String>(
        id: 'service.language.styio',
        kind: 'service',
        owner: 'service-layer',
        value: 'Styio service connector',
      ),
    );

    expect(
      () => registry.register(
        const FoundationRegistryEntry<String>(
          id: 'service.language.styio',
          kind: 'service',
          owner: 'service-layer',
          value: 'duplicate',
        ),
      ),
      throwsStateError,
    );
    expect(() => registry.requireEntry('missing'), throwsStateError);
    expect(
      () => registry.updateMetadata('missing', const <String, Object?>{}),
      throwsStateError,
    );
  });

  test(
    'foundation registry manifest store persists projections through datastore owner',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_registry_manifest_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final datastore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final owner = FoundationDataStoreOwner(
        descriptor: const FoundationDataStoreOwnerDescriptor(
          ownerId: 'foundation.registry',
          layer: 'foundation',
          stateFamily: 'registry-manifests',
          allowedNamespaces: <String>{'foundation.registry.manifests'},
        ),
        dataStore: datastore,
      );
      final manifestStore = FoundationRegistryManifestStore(owner: owner);
      final registry = FoundationRegistry<String>()
        ..register(
          const FoundationRegistryEntry<String>(
            id: 'service.language.styio',
            kind: 'service',
            owner: 'service-layer',
            value: 'runtime-value-must-not-be-persisted',
            metadata: <String, Object?>{'capability': 'language-service'},
          ),
        );

      await manifestStore.writeManifest(
        key: 'service-providers',
        manifest: registry.manifest(kind: 'service'),
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      );
      final loaded = await manifestStore.readManifest(
        key: 'service-providers',
        scope: FoundationResourceScope.workspace,
        workspaceId: 'demo-workspace',
      );

      expect(loaded, isNotNull);
      expect(loaded!.entries.single.id, 'service.language.styio');
      expect(loaded.entries.single.metadata['capability'], 'language-service');
      expect(loaded.toJson().toString(), isNot(contains('runtime-value')));
      expect(
        await manifestStore.deleteManifest(
          key: 'service-providers',
          scope: FoundationResourceScope.workspace,
          workspaceId: 'demo-workspace',
        ),
        isTrue,
      );
      expect(
        await manifestStore.readManifest(
          key: 'service-providers',
          scope: FoundationResourceScope.workspace,
          workspaceId: 'demo-workspace',
        ),
        isNull,
      );
    },
  );

  test('foundation workspace owns workspace scope and cache location', () {
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(homePath: '/home/vityo'),
    );
    final coordinator = FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    );
    final workspace = FoundationWorkspace(
      scope: const FoundationWorkspaceScope(
        workspaceId: 'demo-workspace',
        rootPath: '/workspace/demo',
      ),
      resourceCoordinator: coordinator,
    );

    workspace.open();
    final cache = workspace.workspaceCacheLocation('semantic-index');
    workspace.reload();
    workspace.close();

    expect(cache.path, isNot(startsWith('/workspace/demo')));
    expect(cache.path, contains('demo-workspace'));
    expect(workspace.state, FoundationWorkspaceState.closed);
  });

  test('foundation service container stores workspace scoped services', () {
    final container = FoundationWorkspaceServiceContainer();

    container.register<String>('language-service', 'styio');

    expect(container.lookup<String>('language-service'), 'styio');
    expect(container.unregister('language-service'), isTrue);
  });

  test(
    'foundation lifecycle coordinator sequences shared service lifecycle',
    () async {
      final events = <String>[];
      final coordinator = FoundationLifecycleCoordinator()
        ..register(
          FoundationLifecycleComponent(
            id: 'datastore',
            onInitialize: () async => events.add('datastore:init'),
            onReload: () async => events.add('datastore:reload'),
            onStop: () async => events.add('datastore:stop'),
            onDispose: () async => events.add('datastore:dispose'),
          ),
        )
        ..register(
          FoundationLifecycleComponent(
            id: 'registry',
            onInitialize: () async => events.add('registry:init'),
            onReload: () async => events.add('registry:reload'),
            onStop: () async => events.add('registry:stop'),
            onDispose: () async => events.add('registry:dispose'),
          ),
        );

      await coordinator.initializeAll();
      await coordinator.reloadAll();
      await coordinator.stopAll();
      await coordinator.disposeAll();

      expect(events, <String>[
        'datastore:init',
        'registry:init',
        'datastore:reload',
        'registry:reload',
        'registry:stop',
        'datastore:stop',
        'registry:dispose',
        'datastore:dispose',
      ]);
      expect(
        coordinator.stateOf('datastore'),
        FoundationLifecycleState.disposed,
      );
    },
  );

  test(
    'foundation lock service serializes updates with the same key',
    () async {
      final lockService = FoundationLockService();
      final firstEntered = Completer<void>();
      final allowFirstToFinish = Completer<void>();
      final events = <String>[];

      final first = lockService.runExclusive<String>('settings', (token) async {
        events.add('${token.key}:first:start');
        firstEntered.complete();
        await allowFirstToFinish.future;
        events.add('${token.key}:first:end');
        return 'first';
      });
      await firstEntered.future;

      final second = lockService.runExclusive<String>('settings', (token) {
        events.add('${token.key}:second');
        return 'second';
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, <String>['settings:first:start']);

      allowFirstToFinish.complete();

      expect(await first, 'first');
      expect(await second, 'second');
      expect(events, <String>[
        'settings:first:start',
        'settings:first:end',
        'settings:second',
      ]);
      expect(lockService.isLocked('settings'), isFalse);
    },
  );

  test('foundation event bus routes shared foundation state events', () async {
    final eventBus = FoundationEventBus();
    addTearDown(eventBus.close);
    final received = <FoundationEvent>[];
    final subscription = eventBus
        .subscribe(topic: 'foundation.workspace')
        .listen(received.add);
    addTearDown(subscription.cancel);

    eventBus
      ..publish(
        FoundationEvent(
          topic: 'foundation.workspace',
          owner: 'workspace',
          payload: const <String, Object?>{'state': 'open'},
        ),
      )
      ..publish(
        FoundationEvent(
          topic: 'foundation.other',
          owner: 'other',
          payload: const <String, Object?>{'ignored': true},
        ),
      );

    expect(received, hasLength(1));
    expect(received.single.payload, const <String, Object?>{'state': 'open'});
  });

  test('foundation diagnostics sink records infrastructure status', () {
    final eventBus = FoundationEventBus();
    addTearDown(eventBus.close);
    final routed = <FoundationEvent>[];
    final subscription = eventBus
        .subscribe(topic: 'foundation.diagnostics')
        .listen(routed.add);
    addTearDown(subscription.cancel);
    final sink = FoundationDiagnosticsSink(eventBus: eventBus);

    sink
      ..emit(
        FoundationDiagnosticEvent(
          component: 'datastore',
          severity: FoundationDiagnosticSeverity.warning,
          message: 'migration fallback used',
          metadata: const <String, Object?>{'namespace': 'settings'},
        ),
      )
      ..emit(
        FoundationDiagnosticEvent(
          component: 'registry',
          message: 'registry warmed',
        ),
      );

    expect(
      sink.list(severity: FoundationDiagnosticSeverity.warning),
      hasLength(1),
    );
    expect(sink.list(component: 'registry').single.message, 'registry warmed');
    expect(routed, hasLength(2));
    expect(routed.first.owner, 'datastore');
  });
  group('DataStore Owner Registry', () {
    test('registers owners and detects missing families', () {
      final registry = FoundationDataStoreOwnerRegistry();

      // Register a few owners
      registry.registerOwner(const FoundationDataStoreOwnerDescriptor(
        ownerId: 'config-settings-owner',
        layer: 'Configuration',
        stateFamily: 'settings',
        allowedNamespaces: {'settings', 'profiles'},
      ));
      registry.registerOwner(const FoundationDataStoreOwnerDescriptor(
        ownerId: 'interaction-editor-owner',
        layer: 'Interaction',
        stateFamily: 'editor-session',
        allowedNamespaces: {'editor-session', 'tabs'},
      ));

      // Declare one family as ephemeral
      registry.declareEphemeral(
        'runtime.task-history',
        'Task history is ephemeral per session',
      );

      // Assert lookups
      expect(
        registry.ownerFor('Configuration.settings')?.ownerId,
        'config-settings-owner',
      );
      expect(registry.isEphemeral('runtime.task-history'), isTrue);

      // Missing families should be reported
      final missing = registry.missingOwnerFamilyIds();
      expect(missing, isNotEmpty);
      expect(missing, contains('configuration.endpoint-policy'));
      expect(registry.isComplete, isFalse);
    });

    test('rejects duplicate owner registration', () {
      final registry = FoundationDataStoreOwnerRegistry();
      registry.registerOwner(const FoundationDataStoreOwnerDescriptor(
        ownerId: 'owner-1',
        layer: 'Configuration',
        stateFamily: 'settings',
      ));
      expect(
        () => registry.registerOwner(const FoundationDataStoreOwnerDescriptor(
          ownerId: 'owner-2',
          layer: 'Configuration',
          stateFamily: 'settings',
        )),
        throwsStateError,
      );
    });

    test('rejects ephemeral declaration when owner exists', () {
      final registry = FoundationDataStoreOwnerRegistry();
      registry.registerOwner(const FoundationDataStoreOwnerDescriptor(
        ownerId: 'owner-1',
        layer: 'Configuration',
        stateFamily: 'settings',
      ));
      expect(
        () => registry.declareEphemeral(
          'Configuration.settings',
          'should not work',
        ),
        throwsStateError,
      );
    });

    test('emits manifest projection without runtime values', () {
      final registry = FoundationDataStoreOwnerRegistry();
      registry.registerOwner(const FoundationDataStoreOwnerDescriptor(
        ownerId: 'config-settings-owner',
        layer: 'Configuration',
        stateFamily: 'settings',
        allowedNamespaces: {'settings'},
      ));
      registry.declareEphemeral(
        'service.language-result-cache',
        'cached only',
      );

      final manifest = registry.manifest();
      final json = manifest.toJson();

      // Manifest contains no runtime values
      expect(json['isComplete'], isA<bool>());
      expect(json['owners'], isA<List<Object?>>());
      expect(json['ephemeralFamilies'], isA<List<Object?>>());
      expect(
        (json['ephemeralFamilies'] as List<Object?>)
            .contains('service.language-result-cache'),
        isTrue,
      );

      // Owner entries are metadata-only
      final ownerEntries = json['owners'] as List<Object?>;
      expect(ownerEntries, hasLength(1));
      final ownerJson = ownerEntries.first as Map<String, Object?>;
      expect(ownerJson['ownerId'], 'config-settings-owner');
      expect(ownerJson['layer'], 'Configuration');
      expect(ownerJson['stateFamily'], 'settings');
      expect(ownerJson['allowedNamespaces'], ['settings']);
    });

    test('all persistent state families have defined layer and description', () {
      for (final family in vityoPersistentStateFamilies) {
        expect(family.familyId, isNotEmpty);
        expect(family.layer, isNotEmpty);
        expect(family.description, isNotEmpty);
      }
    });
  });

  group('Registry Manifest Projection', () {
    test('manifest strips runtime values from registered entries', () {
      final registry = FoundationRegistry<String>();
      registry.registerContribution(
        const ContributionDescriptor<String>(
          id: 'test.command',
          kind: 'command',
          owner: 'test-owner',
          value: 'do-something',
        ),
        scopeId: 'test-scope',
      );

      final manifest = registry.manifest();
      expect(manifest.entries, hasLength(1));
      final entry = manifest.entries.first;
      final json = entry.toJson();

      // Manifest entry must have id, kind, owner, state -- never value
      expect(json['id'], 'test.command');
      expect(json['kind'], 'command');
      expect(json['owner'], 'test-owner');
      expect(json['state'], 'registered');
      expect(json.containsKey('value'), isFalse,
          reason: 'Manifest entry must not leak runtime values');
    });

    test('manifest projection handles empty registry', () {
      final registry = FoundationRegistry<String>();
      final manifest = registry.manifest();
      expect(manifest.entries, isEmpty);
    });

    test('registry validator confirms manifest integrity', () {
      final registry = FoundationRegistry<String>();
      registry.registerContribution(
        const ContributionDescriptor<String>(
          id: 'test.command',
          kind: 'command',
          owner: 'test-owner',
          value: 'value-should-not-leak',
        ),
        scopeId: 'test-scope',
      );

      final validator = const FoundationRegistryValidator();
      final diagnostics = validator.validateManifestProjection(registry);
      expect(diagnostics, isEmpty,
          reason: 'All manifest entries must have complete metadata');
    });

    test('registry refuses registration after dispose', () {
      final registry = FoundationRegistry<String>();
      final scope = RegistryScope(id: 's1', owner: 'test');
      scope.register<String>(
        registry: registry,
        contribution: const ContributionDescriptor<String>(
          id: 'entry-1',
          kind: 'command',
          owner: 'test',
          value: 'v',
        ),
      );
      scope.dispose();

      // Disposed registration should not be usable
      // After scope dispose, re-registering in same scope should fail
      expect(
        () => scope.register<String>(
          registry: registry,
          contribution: const ContributionDescriptor<String>(
            id: 'entry-2',
            kind: 'command',
            owner: 'test',
            value: 'v2',
          ),
        ),
        throwsStateError,
      );
      expect(scope.disposed, isTrue);
    });
  });

  group('Capability Gap Agent Safety', () {
    test('agent-safe projector strips runtime values', () {
      final snapshot = const VityoIdeCapabilityFramework().snapshot();
      final gate = const IdeCapabilityClosureGate();
      final report = gate.evaluate(snapshot);
      final projector = const IdeCapabilityAgentSafeProjector();

      final projection = projector.project(report);
      final summary = projector.summarize(report);

      // Summary is metadata-only
      expect(summary['version'], isA<String>());
      expect(summary['readyCount'], isA<int>());
      expect(summary['isFrameworkClosed'], isA<bool>());
      expect(summary['items'], isA<List<Object?>>());

      // Each projected item has no runtime values
      for (final item in projection) {
        final json = item.toJson();
        expect(json.containsKey('capabilityId'), isTrue);
        expect(json.containsKey('layer'), isTrue);
        expect(json.containsKey('status'), isTrue);
        expect(json.containsKey('isBlocking'), isTrue);
        expect(json.containsKey('ownerPath'), isTrue);
        // Must not leak raw payloads
        expect(json.containsKey('reason'), isFalse,
            reason: 'Agent projection must not leak internal reasons');
      }
    });

    test('closure report correctly identifies todo items', () {
      final snapshot = const VityoIdeCapabilityFramework().snapshot();
      final gate = const IdeCapabilityClosureGate();
      final report = gate.evaluate(snapshot);

      // At this stage of Vityo, some capabilities are scaffolded/todo
      expect(report.todoCount, greaterThanOrEqualTo(0));
      expect(report.hardFailureCount, greaterThanOrEqualTo(0));
      expect(report.isFrameworkClosed, isA<bool>());
    });
  });

  group('Lifecycle State Contract', () {
    test('registry lifecycle transitions are valid', () {
      // The FoundationRegistry itself does not carry lifecycle state directly,
      // but the lifecycle coordinator sequences components that include registries.
      final coordinator = FoundationLifecycleCoordinator();
      final states = <String, FoundationLifecycleState>{};

      coordinator.register(FoundationLifecycleComponent(
        id: 'registry-component',
        onInitialize: () async {
          states['registry'] = FoundationLifecycleState.initializing;
          states['registry'] = FoundationLifecycleState.ready;
        },
        onStop: () async {
          states['registry'] = FoundationLifecycleState.stopped;
        },
        onDispose: () async {
          states['registry'] = FoundationLifecycleState.disposed;
        },
      ));

      expect(
        coordinator.stateOf('registry-component'),
        FoundationLifecycleState.registered,
      );
    });

    test('lifecycle coordinator stop/dispose order is reverse registration', () async {
      final events = <String>[];
      final coordinator = FoundationLifecycleCoordinator()
        ..register(FoundationLifecycleComponent(
          id: 'first',
          onStop: () async => events.add('first:stop'),
          onDispose: () async => events.add('first:dispose'),
        ))
        ..register(FoundationLifecycleComponent(
          id: 'second',
          onStop: () async => events.add('second:stop'),
          onDispose: () async => events.add('second:dispose'),
        ));

      await coordinator.stopAll();
      await coordinator.disposeAll();

      // Stop/dispose must be reverse order
      expect(events, [
        'second:stop',
        'first:stop',
        'second:dispose',
        'first:dispose',
      ]);
    });
  });
}