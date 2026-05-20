import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('extension marketplace index searches and plans installs', () {
    const listing = ExtensionMarketplaceListing(
      manifest: ExtensionManifest(
        extensionId: 'styio.language',
        displayName: 'Styio Language',
        version: '1.0.0',
        publisher: 'vityo',
        entrypoint: 'styio_language.dart',
        description: 'Styio language service extension',
      ),
      sourceUri: 'https://marketplace.vityo.invalid/styio.language-1.0.0.zip',
      summary: 'Language support for Styio projects.',
      categories: <String>['language', 'styio'],
      verified: true,
    );
    const invalidListing = ExtensionMarketplaceListing(
      manifest: ExtensionManifest(
        extensionId: 'broken.extension',
        displayName: 'Broken Extension',
        version: '1.0.0',
        publisher: 'vityo',
        entrypoint: 'broken.dart',
      ),
      sourceUri: '',
    );
    const index = ExtensionMarketplaceIndex(
      workspaceId: 'demo',
      listings: <ExtensionMarketplaceListing>[invalidListing, listing],
    );

    expect(index.search('styio').single.extensionId, 'styio.language');
    expect(
      index
          .installPlan(
            installedRegistry: ExtensionManifestRegistry(),
            extensionId: 'styio.language',
          )
          .status,
      ExtensionInstallPlanStatus.ready,
    );
    expect(
      index
          .installPlan(
            installedRegistry: ExtensionManifestRegistry()
              ..register(listing.manifest),
            extensionId: 'styio.language',
          )
          .status,
      ExtensionInstallPlanStatus.alreadyInstalled,
    );
    expect(
      index
          .installPlan(
            installedRegistry: ExtensionManifestRegistry(),
            extensionId: 'broken.extension',
          )
          .status,
      ExtensionInstallPlanStatus.blockedInvalidListing,
    );
    expect(
      ExtensionMarketplaceIndex.fromJson(
        index.toJson(),
      ).lookup('styio.language'),
      isNotNull,
    );
  });

  test('extension marketplace installer composes execution steps', () {
    const listing = ExtensionMarketplaceListing(
      manifest: ExtensionManifest(
        extensionId: 'styio.language',
        displayName: 'Styio Language',
        version: '1.0.0',
        publisher: 'vityo',
        entrypoint: 'styio_language.dart',
        trustedByDefault: true,
        metadata: <String, Object?>{'isolationMode': 'local-process'},
      ),
      sourceUri: 'https://marketplace.vityo.invalid/styio.language-1.0.0.zip',
      verified: true,
    );
    const index = ExtensionMarketplaceIndex(
      workspaceId: 'demo',
      listings: <ExtensionMarketplaceListing>[listing],
    );
    final installPlan = index.installPlan(
      installedRegistry: ExtensionManifestRegistry(),
      extensionId: 'styio.language',
    );

    final executionPlan = const ExtensionMarketplaceInstaller().planExecution(
      installPlan,
    );

    expect(executionPlan.status, ExtensionInstallExecutionStatus.ready);
    expect(executionPlan.executable, isTrue);
    expect(
      executionPlan.steps.map((step) => step.kind).toList(growable: false),
      <ExtensionInstallExecutionStepKind>[
        ExtensionInstallExecutionStepKind.downloadPackage,
        ExtensionInstallExecutionStepKind.verifySignature,
        ExtensionInstallExecutionStepKind.registerManifest,
        ExtensionInstallExecutionStepKind.applyLifecyclePolicy,
        ExtensionInstallExecutionStepKind.planHostIsolation,
      ],
    );
    expect(
      executionPlan.hostExecutionPlan?.mode,
      ExtensionHostIsolationMode.localProcess,
    );
    expect(executionPlan.lifecycleDecision?.trustedAfterInstall, isTrue);
    expect(executionPlan.toJson()['status'], 'ready');
  });

  test('extension marketplace installer blocks unverified packages', () {
    const listing = ExtensionMarketplaceListing(
      manifest: ExtensionManifest(
        extensionId: 'external.theme',
        displayName: 'External Theme',
        version: '1.0.0',
        publisher: 'external',
        entrypoint: 'theme.dart',
        trustedByDefault: true,
      ),
      sourceUri: 'https://marketplace.vityo.invalid/external.theme-1.0.0.zip',
    );
    const index = ExtensionMarketplaceIndex(
      workspaceId: 'demo',
      listings: <ExtensionMarketplaceListing>[listing],
    );
    final installPlan = index.installPlan(
      installedRegistry: ExtensionManifestRegistry(),
      extensionId: 'external.theme',
    );

    final executionPlan = const ExtensionMarketplaceInstaller().planExecution(
      installPlan,
    );

    expect(
      executionPlan.status,
      ExtensionInstallExecutionStatus.blockedUnverifiedPackage,
    );
    expect(executionPlan.executable, isFalse);
    expect(
      executionPlan.steps
          .singleWhere(
            (step) =>
                step.kind == ExtensionInstallExecutionStepKind.verifySignature,
          )
          .ready,
      isFalse,
    );
  });

  test(
    'extension marketplace index persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_extension_marketplace_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
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
      final store = ExtensionMarketplaceIndexStore.fromDataStore(
        dataStore: dataStore,
      );

      await store.saveIndex(
        const ExtensionMarketplaceIndex(
          workspaceId: 'demo',
          listings: <ExtensionMarketplaceListing>[
            ExtensionMarketplaceListing(
              manifest: ExtensionManifest(
                extensionId: 'theme.solar',
                displayName: 'Solar Theme',
                version: '1.0.0',
                publisher: 'vityo',
                entrypoint: 'theme.dart',
              ),
              sourceUri: 'https://marketplace.vityo.invalid/theme.solar.zip',
              categories: <String>['theme'],
            ),
          ],
        ),
      );
      final restored = await store.readIndex(workspaceId: 'demo');

      expect(restored.workspaceId, 'demo');
      expect(restored.lookup('theme.solar'), isNotNull);
      expect(restored.search('theme').single.extensionId, 'theme.solar');
      expect(await store.deleteIndex(workspaceId: 'demo'), isTrue);
      expect((await store.readIndex(workspaceId: 'demo')).listings, isEmpty);
    },
  );
}
