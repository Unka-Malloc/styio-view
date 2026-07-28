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

  test(
    'extension marketplace update plan compares installed listing versions',
    () {
      const installed = ExtensionManifest(
        extensionId: 'styio.language',
        displayName: 'Styio Language',
        version: '1.0.0',
        publisher: 'vityo',
        entrypoint: 'styio_language.dart',
      );
      const listing = ExtensionMarketplaceListing(
        manifest: ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.1.0',
          publisher: 'vityo',
          entrypoint: 'styio_language.dart',
        ),
        sourceUri: 'https://marketplace.vityo.invalid/styio.language-1.1.0.zip',
        verified: true,
      );
      final registry = ExtensionManifestRegistry()..register(installed);

      final plan = ExtensionMarketplaceUpdatePlan.fromListing(
        listing: listing,
        installedRegistry: registry,
      );

      expect(plan.status, ExtensionMarketplaceUpdateStatus.updateAvailable);
      expect(plan.canUpdate, isTrue);
      expect(plan.installedVersion, '1.0.0');
      expect(plan.availableVersion, '1.1.0');
      expect(plan.toJson()['status'], 'update-available');
    },
  );

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
    'extension marketplace install executor downloads verifies and registers',
    () async {
      const listing = ExtensionMarketplaceListing(
        manifest: ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'styio_language.dart',
          trustedByDefault: true,
        ),
        sourceUri: 'https://marketplace.vityo.invalid/styio.language-1.0.0.zip',
        verified: true,
      );
      const index = ExtensionMarketplaceIndex(
        workspaceId: 'demo',
        listings: <ExtensionMarketplaceListing>[listing],
      );
      final registry = ExtensionManifestRegistry();
      final installPlan = index.installPlan(
        installedRegistry: registry,
        extensionId: 'styio.language',
      );
      final executionPlan = const ExtensionMarketplaceInstaller().planExecution(
        installPlan,
      );
      const executor = ExtensionMarketplaceInstallExecutor(
        downloader: _FakePackageDownloader(),
      );

      final result = await executor.execute(
        executionPlan: executionPlan,
        installedRegistry: registry,
      );

      expect(result.installed, isTrue);
      expect(result.status, ExtensionMarketplaceInstallResultStatus.installed);
      expect(
        result.downloadReceipt?.artifact.cacheKey,
        'cache/styio.language.zip',
      );
      expect(result.verificationReceipt?.verified, isTrue);
      expect(registry.lookup('styio.language'), isNotNull);
      expect(
        result.toJson()['registeredManifest'],
        isA<Map<String, Object?>>(),
      );
    },
  );

  test(
    'extension marketplace install executor blocks failed verification',
    () async {
      const listing = ExtensionMarketplaceListing(
        manifest: ExtensionManifest(
          extensionId: 'external.theme',
          displayName: 'External Theme',
          version: '1.0.0',
          publisher: 'external',
          entrypoint: 'theme.dart',
          trustedByDefault: true,
        ),
        sourceUri: 'https://marketplace.vityo.invalid/external.theme.zip',
        verified: true,
      );
      const index = ExtensionMarketplaceIndex(
        workspaceId: 'demo',
        listings: <ExtensionMarketplaceListing>[listing],
      );
      final registry = ExtensionManifestRegistry();
      final installPlan = index.installPlan(
        installedRegistry: registry,
        extensionId: 'external.theme',
      );
      final executionPlan = const ExtensionMarketplaceInstaller().planExecution(
        installPlan,
      );
      const executor = ExtensionMarketplaceInstallExecutor(
        downloader: _FakePackageDownloader(),
        verifier: _RejectingPackageVerifier(),
      );

      final result = await executor.execute(
        executionPlan: executionPlan,
        installedRegistry: registry,
      );

      expect(
        result.status,
        ExtensionMarketplaceInstallResultStatus.blockedVerification,
      );
      expect(result.installed, isFalse);
      expect(result.verificationReceipt?.verified, isFalse);
      expect(registry.lookup('external.theme'), isNull);
    },
  );

  test(
    'extension marketplace IO bridge executes install operations in order',
    () async {
      const listing = ExtensionMarketplaceListing(
        manifest: ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'styio_language.dart',
          trustedByDefault: true,
        ),
        sourceUri: 'https://marketplace.vityo.invalid/styio.language.zip',
        verified: true,
      );
      const lifecycleDecision = ExtensionInstallLifecyclePolicyDecision(
        extensionId: 'styio.language',
        enabledAfterInstall: true,
        trustedAfterInstall: true,
        activateAfterInstall: true,
        message: 'Enable trusted extension after install.',
      );
      final observedKinds = <ExtensionMarketplaceIoOperationKind>[];
      late ExtensionMarketplaceIoOperationRegistration downloadHandler;
      late ExtensionMarketplaceIoOperationRegistration cacheHandler;
      late ExtensionMarketplaceIoOperationRegistration lifecycleHandler;
      downloadHandler = _marketplaceIoHandler(
        id: 'download',
        kind: ExtensionMarketplaceIoOperationKind.downloadPackage,
        observedKinds: observedKinds,
        cacheKey: 'cache/styio.language.zip',
        self: () => downloadHandler,
      );
      cacheHandler = _marketplaceIoHandler(
        id: 'cache',
        kind: ExtensionMarketplaceIoOperationKind.writePackageCache,
        observedKinds: observedKinds,
        cacheKey: 'cache/styio.language.zip',
        self: () => cacheHandler,
      );
      lifecycleHandler = _marketplaceIoHandler(
        id: 'lifecycle',
        kind: ExtensionMarketplaceIoOperationKind.persistLifecyclePolicy,
        observedKinds: observedKinds,
        self: () => lifecycleHandler,
      );
      final bridge = ExtensionMarketplaceIoBridge(
        registry: ExtensionMarketplaceIoOperationRegistry(
          handlers: <ExtensionMarketplaceIoOperationRegistration>[
            downloadHandler,
            cacheHandler,
            lifecycleHandler,
          ],
        ),
      );

      final result = await bridge.executeInstallIo(
        listing: listing,
        lifecycleDecision: lifecycleDecision,
        timestamp: DateTime.utc(2026, 5, 21),
      );

      expect(result.completed, isTrue);
      expect(observedKinds, <ExtensionMarketplaceIoOperationKind>[
        ExtensionMarketplaceIoOperationKind.downloadPackage,
        ExtensionMarketplaceIoOperationKind.writePackageCache,
        ExtensionMarketplaceIoOperationKind.persistLifecyclePolicy,
      ]);
      expect(result.results.first.cacheKey, 'cache/styio.language.zip');
      expect(result.toJson()['resultCount'], 3);
    },
  );

  test(
    'extension marketplace IO bridge executes update download flow',
    () async {
      const listing = ExtensionMarketplaceListing(
        manifest: ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.1.0',
          publisher: 'vityo',
          entrypoint: 'styio_language.dart',
        ),
        sourceUri: 'https://marketplace.vityo.invalid/styio.language-1.1.0.zip',
        verified: true,
      );
      final updatePlan = ExtensionMarketplaceUpdatePlan.fromListing(
        listing: listing,
        installedRegistry: ExtensionManifestRegistry()
          ..register(
            const ExtensionManifest(
              extensionId: 'styio.language',
              displayName: 'Styio Language',
              version: '1.0.0',
              publisher: 'vityo',
              entrypoint: 'styio_language.dart',
            ),
          ),
      );
      final observedKinds = <ExtensionMarketplaceIoOperationKind>[];
      late ExtensionMarketplaceIoOperationRegistration updateDownloadHandler;
      late ExtensionMarketplaceIoOperationRegistration cacheHandler;
      updateDownloadHandler = _marketplaceIoHandler(
        id: 'update-download',
        kind: ExtensionMarketplaceIoOperationKind.downloadUpdatePackage,
        observedKinds: observedKinds,
        cacheKey: 'cache/styio.language-1.1.0.zip',
        self: () => updateDownloadHandler,
      );
      cacheHandler = _marketplaceIoHandler(
        id: 'cache',
        kind: ExtensionMarketplaceIoOperationKind.writePackageCache,
        observedKinds: observedKinds,
        cacheKey: 'cache/styio.language-1.1.0.zip',
        self: () => cacheHandler,
      );
      final bridge = ExtensionMarketplaceIoBridge(
        registry: ExtensionMarketplaceIoOperationRegistry(
          handlers: <ExtensionMarketplaceIoOperationRegistration>[
            updateDownloadHandler,
            cacheHandler,
          ],
        ),
      );

      final result = await bridge.executeUpdateIo(
        updatePlan: updatePlan,
        timestamp: DateTime.utc(2026, 5, 21),
      );

      expect(result.completed, isTrue);
      expect(observedKinds, <ExtensionMarketplaceIoOperationKind>[
        ExtensionMarketplaceIoOperationKind.downloadUpdatePackage,
        ExtensionMarketplaceIoOperationKind.writePackageCache,
      ]);
      expect(result.results.first.request.updatePlan?.canUpdate, isTrue);
      expect(result.results.first.cacheKey, 'cache/styio.language-1.1.0.zip');
    },
  );

  test('extension marketplace IO bridge reports missing handlers', () async {
    const listing = ExtensionMarketplaceListing(
      manifest: ExtensionManifest(
        extensionId: 'styio.language',
        displayName: 'Styio Language',
        version: '1.0.0',
        publisher: 'vityo',
        entrypoint: 'styio_language.dart',
      ),
      sourceUri: 'https://marketplace.vityo.invalid/styio.language.zip',
      verified: true,
    );
    const lifecycleDecision = ExtensionInstallLifecyclePolicyDecision(
      extensionId: 'styio.language',
      enabledAfterInstall: true,
      trustedAfterInstall: true,
      activateAfterInstall: true,
      message: 'Enable trusted extension after install.',
    );
    final bridge = ExtensionMarketplaceIoBridge(
      registry: ExtensionMarketplaceIoOperationRegistry(),
    );

    final result = await bridge.executeInstallIo(
      listing: listing,
      lifecycleDecision: lifecycleDecision,
      timestamp: DateTime.utc(2026, 5, 21),
    );

    expect(result.completed, isFalse);
    expect(
      result.results.map((entry) => entry.status).toSet(),
      <ExtensionMarketplaceIoOperationStatus>{
        ExtensionMarketplaceIoOperationStatus.missingHandler,
      },
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

class _FakePackageDownloader implements ExtensionPackageDownloader {
  const _FakePackageDownloader();

  @override
  Future<ExtensionPackageDownloadReceipt> download(
    ExtensionMarketplaceListing listing,
  ) async {
    return ExtensionPackageDownloadReceipt(
      artifact: ExtensionPackageArtifact(
        extensionId: listing.extensionId,
        sourceUri: listing.sourceUri,
        cacheKey: 'cache/${listing.extensionId}.zip',
        sizeBytes: listing.downloadSizeBytes ?? 42,
        checksum: 'sha256:test-${listing.extensionId}',
      ),
      message: 'Downloaded ${listing.extensionId}.',
    );
  }
}

ExtensionMarketplaceIoOperationRegistration _marketplaceIoHandler({
  required String id,
  required ExtensionMarketplaceIoOperationKind kind,
  required List<ExtensionMarketplaceIoOperationKind> observedKinds,
  required ExtensionMarketplaceIoOperationRegistration Function() self,
  String cacheKey = '',
}) {
  return ExtensionMarketplaceIoOperationRegistration(
    handlerId: id,
    label: id,
    kind: kind,
    handler: (request) async {
      observedKinds.add(request.kind);
      return ExtensionMarketplaceIoOperationResult.completed(
        request: request,
        handler: self(),
        message: '${request.kind.wireValue} completed.',
        artifactUri: request.listing.sourceUri,
        cacheKey: cacheKey,
      );
    },
  );
}

class _RejectingPackageVerifier implements ExtensionPackageVerifier {
  const _RejectingPackageVerifier();

  @override
  Future<ExtensionPackageVerificationReceipt> verify({
    required ExtensionMarketplaceListing listing,
    required ExtensionPackageArtifact artifact,
  }) async {
    return ExtensionPackageVerificationReceipt(
      verified: false,
      checksum: artifact.checksum,
      message: 'Rejected ${listing.extensionId}.',
    );
  }
}
