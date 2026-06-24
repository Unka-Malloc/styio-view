import '../foundation/foundation.dart';
import 'extension_host_isolation.dart';
import 'extension_manifest_contract.dart';

enum ExtensionInstallPlanStatus {
  ready,
  alreadyInstalled,
  blockedInvalidListing,
}

extension ExtensionInstallPlanStatusX on ExtensionInstallPlanStatus {
  String get wireValue => switch (this) {
    ExtensionInstallPlanStatus.ready => 'ready',
    ExtensionInstallPlanStatus.alreadyInstalled => 'already-installed',
    ExtensionInstallPlanStatus.blockedInvalidListing =>
      'blocked-invalid-listing',
  };
}

class ExtensionMarketplaceListing {
  const ExtensionMarketplaceListing({
    required this.manifest,
    required this.sourceUri,
    this.summary = '',
    this.categories = const <String>[],
    this.downloadSizeBytes,
    this.verified = false,
    this.metadata = const <String, Object?>{},
    this.schemaVersion = 1,
    this.extensions = const {},
  });

  factory ExtensionMarketplaceListing.fromJson(Map<String, Object?> json) {
    final manifest = json['manifest'];
    return ExtensionMarketplaceListing(
      manifest: manifest is Map<String, Object?>
          ? ExtensionManifest.fromJson(manifest)
          : manifest is Map
          ? ExtensionManifest.fromJson(
              manifest.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const ExtensionManifest(
              extensionId: '',
              displayName: '',
              version: '',
              publisher: '',
              entrypoint: '',
            ),
      sourceUri: json['sourceUri'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      categories: _jsonStringList(json['categories']),
      downloadSizeBytes: json['downloadSizeBytes'] as int?,
      verified: json['verified'] as bool? ?? false,
      metadata: _jsonObjectMap(json['metadata']),
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
    );
  }

  static const Set<String> _knownKeys = <String>{
    'manifest',
    'sourceUri',
    'summary',
    'categories',
    'downloadSizeBytes',
    'verified',
    'metadata',
    'valid',
    'schemaVersion',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return Map<String, Object?>.fromEntries(
      json.entries.where((entry) => !_knownKeys.contains(entry.key)),
    );
  }

  final ExtensionManifest manifest;
  final String sourceUri;
  final String summary;
  final List<String> categories;
  final int? downloadSizeBytes;
  final bool verified;
  final Map<String, Object?> metadata;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  String get extensionId => manifest.extensionId;

  bool get valid => manifest.valid && sourceUri.trim().isNotEmpty;

  bool matchesQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final haystack = <String>[
      manifest.extensionId,
      manifest.displayName,
      manifest.publisher,
      manifest.description,
      summary,
      ...categories,
    ].join('\n').toLowerCase();
    return haystack.contains(normalizedQuery);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'manifest': manifest.toJson(),
      'sourceUri': sourceUri,
      'summary': summary,
      'categories': categories,
      if (downloadSizeBytes != null) 'downloadSizeBytes': downloadSizeBytes,
      'verified': verified,
      if (metadata.isNotEmpty) 'metadata': metadata,
      'valid': valid,
      ...extensions,
    };
  }
}

class ExtensionInstallPlan {
  const ExtensionInstallPlan({
    required this.extensionId,
    required this.status,
    required this.message,
    this.listing,
    this.todo = '',
  });

  final String extensionId;
  final ExtensionInstallPlanStatus status;
  final String message;
  final ExtensionMarketplaceListing? listing;
  final String todo;

  bool get ready => status == ExtensionInstallPlanStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'status': status.wireValue,
      'message': message,
      'ready': ready,
      if (listing != null) 'listing': listing!.toJson(),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

enum ExtensionMarketplaceUpdateStatus {
  updateAvailable,
  upToDate,
  notInstalled,
  blockedInvalidListing,
}

extension ExtensionMarketplaceUpdateStatusX
    on ExtensionMarketplaceUpdateStatus {
  String get wireValue {
    return switch (this) {
      ExtensionMarketplaceUpdateStatus.updateAvailable => 'update-available',
      ExtensionMarketplaceUpdateStatus.upToDate => 'up-to-date',
      ExtensionMarketplaceUpdateStatus.notInstalled => 'not-installed',
      ExtensionMarketplaceUpdateStatus.blockedInvalidListing =>
        'blocked-invalid-listing',
    };
  }
}

class ExtensionMarketplaceUpdatePlan {
  const ExtensionMarketplaceUpdatePlan({
    required this.extensionId,
    required this.status,
    required this.installedVersion,
    required this.availableVersion,
    required this.message,
    this.listing,
  });

  factory ExtensionMarketplaceUpdatePlan.fromListing({
    required ExtensionMarketplaceListing listing,
    required ExtensionManifestRegistry installedRegistry,
  }) {
    if (!listing.valid) {
      return ExtensionMarketplaceUpdatePlan(
        extensionId: listing.extensionId,
        status: ExtensionMarketplaceUpdateStatus.blockedInvalidListing,
        installedVersion: '',
        availableVersion: listing.manifest.version,
        message: 'Extension update blocked: marketplace listing is invalid.',
        listing: listing,
      );
    }
    final installed = installedRegistry.lookup(listing.extensionId);
    if (installed == null) {
      return ExtensionMarketplaceUpdatePlan(
        extensionId: listing.extensionId,
        status: ExtensionMarketplaceUpdateStatus.notInstalled,
        installedVersion: '',
        availableVersion: listing.manifest.version,
        message: 'Extension is not installed.',
        listing: listing,
      );
    }
    if (installed.version == listing.manifest.version) {
      return ExtensionMarketplaceUpdatePlan(
        extensionId: listing.extensionId,
        status: ExtensionMarketplaceUpdateStatus.upToDate,
        installedVersion: installed.version,
        availableVersion: listing.manifest.version,
        message: 'Extension ${listing.extensionId} is up to date.',
        listing: listing,
      );
    }
    return ExtensionMarketplaceUpdatePlan(
      extensionId: listing.extensionId,
      status: ExtensionMarketplaceUpdateStatus.updateAvailable,
      installedVersion: installed.version,
      availableVersion: listing.manifest.version,
      message:
          'Extension ${listing.extensionId} can update ${installed.version} -> ${listing.manifest.version}.',
      listing: listing,
    );
  }

  final String extensionId;
  final ExtensionMarketplaceUpdateStatus status;
  final String installedVersion;
  final String availableVersion;
  final String message;
  final ExtensionMarketplaceListing? listing;

  bool get canUpdate =>
      status == ExtensionMarketplaceUpdateStatus.updateAvailable;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'status': status.wireValue,
      'installedVersion': installedVersion,
      'availableVersion': availableVersion,
      'message': message,
      'canUpdate': canUpdate,
      if (listing != null) 'listing': listing!.toJson(),
    };
  }
}

enum ExtensionInstallExecutionStatus {
  ready,
  alreadyInstalled,
  blockedInvalidListing,
  blockedUnverifiedPackage,
  blockedHostIsolation,
}

extension ExtensionInstallExecutionStatusX on ExtensionInstallExecutionStatus {
  String get wireValue => switch (this) {
    ExtensionInstallExecutionStatus.ready => 'ready',
    ExtensionInstallExecutionStatus.alreadyInstalled => 'already-installed',
    ExtensionInstallExecutionStatus.blockedInvalidListing =>
      'blocked-invalid-listing',
    ExtensionInstallExecutionStatus.blockedUnverifiedPackage =>
      'blocked-unverified-package',
    ExtensionInstallExecutionStatus.blockedHostIsolation =>
      'blocked-host-isolation',
  };
}

enum ExtensionInstallExecutionStepKind {
  downloadPackage,
  verifySignature,
  registerManifest,
  applyLifecyclePolicy,
  planHostIsolation,
}

extension ExtensionInstallExecutionStepKindX
    on ExtensionInstallExecutionStepKind {
  String get wireValue => switch (this) {
    ExtensionInstallExecutionStepKind.downloadPackage => 'download-package',
    ExtensionInstallExecutionStepKind.verifySignature => 'verify-signature',
    ExtensionInstallExecutionStepKind.registerManifest => 'register-manifest',
    ExtensionInstallExecutionStepKind.applyLifecyclePolicy =>
      'apply-lifecycle-policy',
    ExtensionInstallExecutionStepKind.planHostIsolation =>
      'plan-host-isolation',
  };
}

class ExtensionInstallExecutionStep {
  const ExtensionInstallExecutionStep({
    required this.kind,
    required this.ready,
    required this.message,
    this.todo = '',
  });

  final ExtensionInstallExecutionStepKind kind;
  final bool ready;
  final String message;
  final String todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'ready': ready,
      'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class ExtensionInstallLifecyclePolicyDecision {
  const ExtensionInstallLifecyclePolicyDecision({
    required this.extensionId,
    required this.enabledAfterInstall,
    required this.trustedAfterInstall,
    required this.activateAfterInstall,
    required this.message,
  });

  final String extensionId;
  final bool enabledAfterInstall;
  final bool trustedAfterInstall;
  final bool activateAfterInstall;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'enabledAfterInstall': enabledAfterInstall,
      'trustedAfterInstall': trustedAfterInstall,
      'activateAfterInstall': activateAfterInstall,
      'message': message,
    };
  }
}

class ExtensionInstallLifecyclePolicy {
  const ExtensionInstallLifecyclePolicy({
    this.enableAfterInstall = true,
    this.trustVerifiedListings = true,
    this.activateTrustedAfterInstall = false,
  });

  final bool enableAfterInstall;
  final bool trustVerifiedListings;
  final bool activateTrustedAfterInstall;

  ExtensionInstallLifecyclePolicyDecision decide(
    ExtensionMarketplaceListing listing,
  ) {
    final trusted =
        listing.manifest.trustedByDefault ||
        (trustVerifiedListings && listing.verified);
    return ExtensionInstallLifecyclePolicyDecision(
      extensionId: listing.extensionId,
      enabledAfterInstall: enableAfterInstall,
      trustedAfterInstall: trusted,
      activateAfterInstall: activateTrustedAfterInstall && trusted,
      message: trusted
          ? 'Extension ${listing.extensionId} can be trusted after install.'
          : 'Extension ${listing.extensionId} requires explicit user trust.',
    );
  }
}

class ExtensionInstallExecutionPlan {
  const ExtensionInstallExecutionPlan({
    required this.extensionId,
    required this.status,
    required this.message,
    required this.installPlan,
    required this.steps,
    this.hostExecutionPlan,
    this.lifecycleDecision,
  });

  final String extensionId;
  final ExtensionInstallExecutionStatus status;
  final String message;
  final ExtensionInstallPlan installPlan;
  final List<ExtensionInstallExecutionStep> steps;
  final ExtensionHostExecutionPlan? hostExecutionPlan;
  final ExtensionInstallLifecyclePolicyDecision? lifecycleDecision;

  bool get executable {
    return status == ExtensionInstallExecutionStatus.ready &&
        steps.every((step) => step.ready);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'status': status.wireValue,
      'message': message,
      'executable': executable,
      'installPlan': installPlan.toJson(),
      'steps': steps.map((step) => step.toJson()).toList(growable: false),
      if (hostExecutionPlan != null)
        'hostExecutionPlan': hostExecutionPlan!.toJson(),
      if (lifecycleDecision != null)
        'lifecycleDecision': lifecycleDecision!.toJson(),
    };
  }
}

class ExtensionMarketplaceInstaller {
  const ExtensionMarketplaceInstaller({
    this.requireVerifiedPackage = true,
    this.isolationPolicy = const ExtensionHostIsolationPolicy(),
    this.lifecyclePolicy = const ExtensionInstallLifecyclePolicy(),
  });

  final bool requireVerifiedPackage;
  final ExtensionHostIsolationPolicy isolationPolicy;
  final ExtensionInstallLifecyclePolicy lifecyclePolicy;

  ExtensionInstallExecutionPlan planExecution(ExtensionInstallPlan plan) {
    if (plan.status == ExtensionInstallPlanStatus.alreadyInstalled) {
      return ExtensionInstallExecutionPlan(
        extensionId: plan.extensionId,
        status: ExtensionInstallExecutionStatus.alreadyInstalled,
        message: plan.message,
        installPlan: plan,
        steps: const <ExtensionInstallExecutionStep>[],
      );
    }
    if (!plan.ready || plan.listing == null) {
      return ExtensionInstallExecutionPlan(
        extensionId: plan.extensionId,
        status: ExtensionInstallExecutionStatus.blockedInvalidListing,
        message: plan.message,
        installPlan: plan,
        steps: const <ExtensionInstallExecutionStep>[],
      );
    }

    final listing = plan.listing!;
    final lifecycleDecision = lifecyclePolicy.decide(listing);
    final hostPlan = isolationPolicy.planFor(listing.manifest);
    final signatureReady = !requireVerifiedPackage || listing.verified;
    final steps = <ExtensionInstallExecutionStep>[
      ExtensionInstallExecutionStep(
        kind: ExtensionInstallExecutionStepKind.downloadPackage,
        ready: true,
        message: 'Download ${listing.extensionId} from ${listing.sourceUri}.',
        todo:
            'TODO: replace this planning step with a real downloader and cache writer.',
      ),
      ExtensionInstallExecutionStep(
        kind: ExtensionInstallExecutionStepKind.verifySignature,
        ready: signatureReady,
        message: signatureReady
            ? 'Package verification policy is satisfied.'
            : 'Package must be verified before installation.',
        todo:
            'TODO: replace listing.verified with checksum and detached signature verification.',
      ),
      ExtensionInstallExecutionStep(
        kind: ExtensionInstallExecutionStepKind.registerManifest,
        ready: true,
        message:
            'Register manifest ${listing.manifest.extensionId} after package staging.',
      ),
      ExtensionInstallExecutionStep(
        kind: ExtensionInstallExecutionStepKind.applyLifecyclePolicy,
        ready: true,
        message: lifecycleDecision.message,
      ),
      ExtensionInstallExecutionStep(
        kind: ExtensionInstallExecutionStepKind.planHostIsolation,
        ready: hostPlan.executable,
        message: hostPlan.reason,
      ),
    ];

    if (!signatureReady) {
      return ExtensionInstallExecutionPlan(
        extensionId: plan.extensionId,
        status: ExtensionInstallExecutionStatus.blockedUnverifiedPackage,
        message: 'Extension ${plan.extensionId} is blocked until verified.',
        installPlan: plan,
        steps: steps,
        hostExecutionPlan: hostPlan,
        lifecycleDecision: lifecycleDecision,
      );
    }
    if (!hostPlan.executable) {
      return ExtensionInstallExecutionPlan(
        extensionId: plan.extensionId,
        status: ExtensionInstallExecutionStatus.blockedHostIsolation,
        message:
            'Extension ${plan.extensionId} cannot start under the current host isolation policy.',
        installPlan: plan,
        steps: steps,
        hostExecutionPlan: hostPlan,
        lifecycleDecision: lifecycleDecision,
      );
    }
    return ExtensionInstallExecutionPlan(
      extensionId: plan.extensionId,
      status: ExtensionInstallExecutionStatus.ready,
      message: 'Extension ${plan.extensionId} install execution is planned.',
      installPlan: plan,
      steps: steps,
      hostExecutionPlan: hostPlan,
      lifecycleDecision: lifecycleDecision,
    );
  }
}

enum ExtensionMarketplaceInstallResultStatus {
  installed,
  blockedPlan,
  blockedVerification,
  failed,
}

extension ExtensionMarketplaceInstallResultStatusX
    on ExtensionMarketplaceInstallResultStatus {
  String get wireValue => switch (this) {
    ExtensionMarketplaceInstallResultStatus.installed => 'installed',
    ExtensionMarketplaceInstallResultStatus.blockedPlan => 'blocked-plan',
    ExtensionMarketplaceInstallResultStatus.blockedVerification =>
      'blocked-verification',
    ExtensionMarketplaceInstallResultStatus.failed => 'failed',
  };
}

class ExtensionPackageArtifact {
  const ExtensionPackageArtifact({
    required this.extensionId,
    required this.sourceUri,
    required this.cacheKey,
    required this.sizeBytes,
    this.checksum = '',
    this.metadata = const <String, Object?>{},
  });

  final String extensionId;
  final String sourceUri;
  final String cacheKey;
  final int sizeBytes;
  final String checksum;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'sourceUri': sourceUri,
      'cacheKey': cacheKey,
      'sizeBytes': sizeBytes,
      if (checksum.isNotEmpty) 'checksum': checksum,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionPackageDownloadReceipt {
  const ExtensionPackageDownloadReceipt({
    required this.artifact,
    required this.message,
  });

  final ExtensionPackageArtifact artifact;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{'artifact': artifact.toJson(), 'message': message};
  }
}

class ExtensionPackageVerificationReceipt {
  const ExtensionPackageVerificationReceipt({
    required this.verified,
    required this.message,
    this.checksum = '',
    this.signature = '',
  });

  final bool verified;
  final String message;
  final String checksum;
  final String signature;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'verified': verified,
      'message': message,
      if (checksum.isNotEmpty) 'checksum': checksum,
      if (signature.isNotEmpty) 'signature': signature,
    };
  }
}

abstract class ExtensionPackageDownloader {
  Future<ExtensionPackageDownloadReceipt> download(
    ExtensionMarketplaceListing listing,
  );
}

abstract class ExtensionPackageVerifier {
  Future<ExtensionPackageVerificationReceipt> verify({
    required ExtensionMarketplaceListing listing,
    required ExtensionPackageArtifact artifact,
  });
}

class ListingMetadataPackageVerifier implements ExtensionPackageVerifier {
  const ListingMetadataPackageVerifier();

  @override
  Future<ExtensionPackageVerificationReceipt> verify({
    required ExtensionMarketplaceListing listing,
    required ExtensionPackageArtifact artifact,
  }) async {
    if (!listing.verified) {
      return ExtensionPackageVerificationReceipt(
        verified: false,
        checksum: artifact.checksum,
        message:
            'Listing ${listing.extensionId} is not marked as marketplace verified.',
      );
    }
    return ExtensionPackageVerificationReceipt(
      verified: true,
      checksum: artifact.checksum,
      message:
          'Listing ${listing.extensionId} satisfies marketplace verification metadata.',
    );
  }
}

class ExtensionMarketplaceInstallExecutionResult {
  const ExtensionMarketplaceInstallExecutionResult({
    required this.extensionId,
    required this.status,
    required this.message,
    required this.executionPlan,
    this.downloadReceipt,
    this.verificationReceipt,
    this.registeredManifest,
  });

  final String extensionId;
  final ExtensionMarketplaceInstallResultStatus status;
  final String message;
  final ExtensionInstallExecutionPlan executionPlan;
  final ExtensionPackageDownloadReceipt? downloadReceipt;
  final ExtensionPackageVerificationReceipt? verificationReceipt;
  final ExtensionManifest? registeredManifest;

  bool get installed =>
      status == ExtensionMarketplaceInstallResultStatus.installed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'extensionId': extensionId,
      'status': status.wireValue,
      'installed': installed,
      'message': message,
      'executionPlan': executionPlan.toJson(),
      if (downloadReceipt != null) 'download': downloadReceipt!.toJson(),
      if (verificationReceipt != null)
        'verification': verificationReceipt!.toJson(),
      if (registeredManifest != null)
        'registeredManifest': registeredManifest!.toJson(),
    };
  }
}

class ExtensionMarketplaceInstallExecutor {
  const ExtensionMarketplaceInstallExecutor({
    required this.downloader,
    this.verifier = const ListingMetadataPackageVerifier(),
  });

  final ExtensionPackageDownloader downloader;
  final ExtensionPackageVerifier verifier;

  Future<ExtensionMarketplaceInstallExecutionResult> execute({
    required ExtensionInstallExecutionPlan executionPlan,
    required ExtensionManifestRegistry installedRegistry,
  }) async {
    if (!executionPlan.executable ||
        executionPlan.installPlan.listing == null) {
      return ExtensionMarketplaceInstallExecutionResult(
        extensionId: executionPlan.extensionId,
        status: ExtensionMarketplaceInstallResultStatus.blockedPlan,
        message: executionPlan.message,
        executionPlan: executionPlan,
      );
    }
    final listing = executionPlan.installPlan.listing!;
    try {
      final download = await downloader.download(listing);
      final verification = await verifier.verify(
        listing: listing,
        artifact: download.artifact,
      );
      if (!verification.verified) {
        return ExtensionMarketplaceInstallExecutionResult(
          extensionId: executionPlan.extensionId,
          status: ExtensionMarketplaceInstallResultStatus.blockedVerification,
          message: verification.message,
          executionPlan: executionPlan,
          downloadReceipt: download,
          verificationReceipt: verification,
        );
      }
      installedRegistry.register(listing.manifest);
      return ExtensionMarketplaceInstallExecutionResult(
        extensionId: executionPlan.extensionId,
        status: ExtensionMarketplaceInstallResultStatus.installed,
        message: 'Extension ${listing.extensionId} installed and registered.',
        executionPlan: executionPlan,
        downloadReceipt: download,
        verificationReceipt: verification,
        registeredManifest: listing.manifest,
      );
    } on Object catch (error) {
      return ExtensionMarketplaceInstallExecutionResult(
        extensionId: executionPlan.extensionId,
        status: ExtensionMarketplaceInstallResultStatus.failed,
        message:
            'Extension ${executionPlan.extensionId} install failed: $error',
        executionPlan: executionPlan,
      );
    }
  }
}

enum ExtensionMarketplaceIoOperationKind {
  fetchIndex,
  downloadPackage,
  writePackageCache,
  downloadUpdatePackage,
  persistLifecyclePolicy,
}

extension ExtensionMarketplaceIoOperationKindX
    on ExtensionMarketplaceIoOperationKind {
  String get wireValue => switch (this) {
    ExtensionMarketplaceIoOperationKind.fetchIndex => 'fetch-index',
    ExtensionMarketplaceIoOperationKind.downloadPackage => 'download-package',
    ExtensionMarketplaceIoOperationKind.writePackageCache =>
      'write-package-cache',
    ExtensionMarketplaceIoOperationKind.downloadUpdatePackage =>
      'download-update-package',
    ExtensionMarketplaceIoOperationKind.persistLifecyclePolicy =>
      'persist-lifecycle-policy',
  };
}

enum ExtensionMarketplaceIoOperationStatus {
  completed,
  blocked,
  missingHandler,
  failed,
}

extension ExtensionMarketplaceIoOperationStatusX
    on ExtensionMarketplaceIoOperationStatus {
  String get wireValue => switch (this) {
    ExtensionMarketplaceIoOperationStatus.completed => 'completed',
    ExtensionMarketplaceIoOperationStatus.blocked => 'blocked',
    ExtensionMarketplaceIoOperationStatus.missingHandler => 'missing-handler',
    ExtensionMarketplaceIoOperationStatus.failed => 'failed',
  };
}

typedef ExtensionMarketplaceIoOperationHandler =
    Future<ExtensionMarketplaceIoOperationResult> Function(
      ExtensionMarketplaceIoOperationRequest request,
    );

class ExtensionMarketplaceIoOperationRequest {
  const ExtensionMarketplaceIoOperationRequest({
    required this.kind,
    required this.listing,
    required this.timestamp,
    this.updatePlan,
    this.lifecycleDecision,
    this.metadata = const <String, Object?>{},
  });

  final ExtensionMarketplaceIoOperationKind kind;
  final ExtensionMarketplaceListing listing;
  final DateTime timestamp;
  final ExtensionMarketplaceUpdatePlan? updatePlan;
  final ExtensionInstallLifecyclePolicyDecision? lifecycleDecision;
  final Map<String, Object?> metadata;

  String get extensionId => listing.extensionId;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'extensionId': extensionId,
      'timestamp': timestamp.toIso8601String(),
      'listing': listing.toJson(),
      if (updatePlan != null) 'updatePlan': updatePlan!.toJson(),
      if (lifecycleDecision != null)
        'lifecycleDecision': lifecycleDecision!.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionMarketplaceIoOperationRegistration {
  const ExtensionMarketplaceIoOperationRegistration({
    required this.handlerId,
    required this.label,
    required this.kind,
    required this.handler,
    this.available = true,
    this.metadata = const <String, Object?>{},
  });

  final String handlerId;
  final String label;
  final ExtensionMarketplaceIoOperationKind kind;
  final ExtensionMarketplaceIoOperationHandler handler;
  final bool available;
  final Map<String, Object?> metadata;

  bool accepts(ExtensionMarketplaceIoOperationRequest request) {
    return available && kind == request.kind;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'handlerId': handlerId,
      'label': label,
      'kind': kind.wireValue,
      'available': available,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionMarketplaceIoOperationResult {
  const ExtensionMarketplaceIoOperationResult({
    required this.request,
    required this.status,
    required this.message,
    this.handler,
    this.artifactUri = '',
    this.cacheKey = '',
    this.metadata = const <String, Object?>{},
  });

  factory ExtensionMarketplaceIoOperationResult.completed({
    required ExtensionMarketplaceIoOperationRequest request,
    required ExtensionMarketplaceIoOperationRegistration handler,
    required String message,
    String artifactUri = '',
    String cacheKey = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionMarketplaceIoOperationResult(
      request: request,
      status: ExtensionMarketplaceIoOperationStatus.completed,
      handler: handler,
      message: message,
      artifactUri: artifactUri,
      cacheKey: cacheKey,
      metadata: metadata,
    );
  }

  factory ExtensionMarketplaceIoOperationResult.blocked({
    required ExtensionMarketplaceIoOperationRequest request,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionMarketplaceIoOperationResult(
      request: request,
      status: ExtensionMarketplaceIoOperationStatus.blocked,
      message: message,
      metadata: metadata,
    );
  }

  factory ExtensionMarketplaceIoOperationResult.missingHandler({
    required ExtensionMarketplaceIoOperationRequest request,
  }) {
    return ExtensionMarketplaceIoOperationResult(
      request: request,
      status: ExtensionMarketplaceIoOperationStatus.missingHandler,
      message:
          'Extension marketplace IO handler is missing for operation '
          '${request.kind.wireValue}.',
    );
  }

  factory ExtensionMarketplaceIoOperationResult.failed({
    required ExtensionMarketplaceIoOperationRequest request,
    required Object error,
  }) {
    return ExtensionMarketplaceIoOperationResult(
      request: request,
      status: ExtensionMarketplaceIoOperationStatus.failed,
      message: 'Extension marketplace IO operation failed: $error',
      metadata: <String, Object?>{'error': error.toString()},
    );
  }

  final ExtensionMarketplaceIoOperationRequest request;
  final ExtensionMarketplaceIoOperationStatus status;
  final String message;
  final ExtensionMarketplaceIoOperationRegistration? handler;
  final String artifactUri;
  final String cacheKey;
  final Map<String, Object?> metadata;

  bool get completed =>
      status == ExtensionMarketplaceIoOperationStatus.completed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'completed': completed,
      'message': message,
      'kind': request.kind.wireValue,
      'extensionId': request.extensionId,
      if (handler != null) 'handler': handler!.toJson(),
      if (artifactUri.isNotEmpty) 'artifactUri': artifactUri,
      if (cacheKey.isNotEmpty) 'cacheKey': cacheKey,
      'request': request.toJson(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class ExtensionMarketplaceIoOperationRegistry {
  ExtensionMarketplaceIoOperationRegistry({
    Iterable<ExtensionMarketplaceIoOperationRegistration> handlers =
        const <ExtensionMarketplaceIoOperationRegistration>[],
  }) {
    for (final handler in handlers) {
      register(handler);
    }
  }

  final List<ExtensionMarketplaceIoOperationRegistration> _handlers =
      <ExtensionMarketplaceIoOperationRegistration>[];

  List<ExtensionMarketplaceIoOperationRegistration> get handlers {
    return List<ExtensionMarketplaceIoOperationRegistration>.unmodifiable(
      _handlers,
    );
  }

  void register(ExtensionMarketplaceIoOperationRegistration handler) {
    _handlers.removeWhere(
      (candidate) => candidate.handlerId == handler.handlerId,
    );
    _handlers.add(handler);
  }

  ExtensionMarketplaceIoOperationRegistration? resolve(
    ExtensionMarketplaceIoOperationRequest request,
  ) {
    for (final handler in _handlers) {
      if (handler.accepts(request)) {
        return handler;
      }
    }
    return null;
  }

  Future<ExtensionMarketplaceIoOperationResult> execute(
    ExtensionMarketplaceIoOperationRequest request,
  ) async {
    final handler = resolve(request);
    if (handler == null) {
      return ExtensionMarketplaceIoOperationResult.missingHandler(
        request: request,
      );
    }
    try {
      final result = await handler.handler(request);
      return ExtensionMarketplaceIoOperationResult(
        request: result.request,
        status: result.status,
        handler: result.handler ?? handler,
        message: result.message,
        artifactUri: result.artifactUri,
        cacheKey: result.cacheKey,
        metadata: <String, Object?>{...handler.metadata, ...result.metadata},
      );
    } catch (error) {
      return ExtensionMarketplaceIoOperationResult.failed(
        request: request,
        error: error,
      );
    }
  }
}

class ExtensionMarketplaceIoBatchResult {
  const ExtensionMarketplaceIoBatchResult({required this.results});

  final List<ExtensionMarketplaceIoOperationResult> results;

  bool get completed => results.every((result) => result.completed);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'completed': completed,
      'resultCount': results.length,
      'results': results
          .map((result) => result.toJson())
          .toList(growable: false),
    };
  }
}

class ExtensionMarketplaceIoBridge {
  const ExtensionMarketplaceIoBridge({required this.registry});

  final ExtensionMarketplaceIoOperationRegistry registry;

  Future<ExtensionMarketplaceIoBatchResult> executeInstallIo({
    required ExtensionMarketplaceListing listing,
    required ExtensionInstallLifecyclePolicyDecision lifecycleDecision,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _executeRequests(<ExtensionMarketplaceIoOperationRequest>[
      ExtensionMarketplaceIoOperationRequest(
        kind: ExtensionMarketplaceIoOperationKind.downloadPackage,
        listing: listing,
        lifecycleDecision: lifecycleDecision,
        timestamp: timestamp,
        metadata: metadata,
      ),
      ExtensionMarketplaceIoOperationRequest(
        kind: ExtensionMarketplaceIoOperationKind.writePackageCache,
        listing: listing,
        lifecycleDecision: lifecycleDecision,
        timestamp: timestamp,
        metadata: metadata,
      ),
      ExtensionMarketplaceIoOperationRequest(
        kind: ExtensionMarketplaceIoOperationKind.persistLifecyclePolicy,
        listing: listing,
        lifecycleDecision: lifecycleDecision,
        timestamp: timestamp,
        metadata: metadata,
      ),
    ]);
  }

  Future<ExtensionMarketplaceIoBatchResult> executeUpdateIo({
    required ExtensionMarketplaceUpdatePlan updatePlan,
    required DateTime timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final listing = updatePlan.listing;
    if (listing == null) {
      return Future<ExtensionMarketplaceIoBatchResult>.value(
        ExtensionMarketplaceIoBatchResult(
          results: <ExtensionMarketplaceIoOperationResult>[
            ExtensionMarketplaceIoOperationResult.blocked(
              request: ExtensionMarketplaceIoOperationRequest(
                kind: ExtensionMarketplaceIoOperationKind.downloadUpdatePackage,
                listing: const ExtensionMarketplaceListing(
                  manifest: ExtensionManifest(
                    extensionId: '',
                    displayName: '',
                    version: '',
                    publisher: '',
                    entrypoint: '',
                  ),
                  sourceUri: '',
                ),
                updatePlan: updatePlan,
                timestamp: timestamp,
                metadata: metadata,
              ),
              message:
                  'Extension marketplace update IO blocked because the update '
                  'plan has no listing.',
            ),
          ],
        ),
      );
    }
    return _executeRequests(<ExtensionMarketplaceIoOperationRequest>[
      ExtensionMarketplaceIoOperationRequest(
        kind: ExtensionMarketplaceIoOperationKind.downloadUpdatePackage,
        listing: listing,
        updatePlan: updatePlan,
        timestamp: timestamp,
        metadata: metadata,
      ),
      ExtensionMarketplaceIoOperationRequest(
        kind: ExtensionMarketplaceIoOperationKind.writePackageCache,
        listing: listing,
        updatePlan: updatePlan,
        timestamp: timestamp,
        metadata: metadata,
      ),
    ]);
  }

  Future<ExtensionMarketplaceIoBatchResult> _executeRequests(
    List<ExtensionMarketplaceIoOperationRequest> requests,
  ) async {
    final results = <ExtensionMarketplaceIoOperationResult>[];
    for (final request in requests) {
      results.add(await registry.execute(request));
    }
    return ExtensionMarketplaceIoBatchResult(results: results);
  }
}

class ExtensionMarketplaceIndex {
  const ExtensionMarketplaceIndex({
    required this.workspaceId,
    this.listings = const <ExtensionMarketplaceListing>[],
    this.updatedAt,
    this.schemaVersion = 1,
    this.extensions = const {},
  });

  factory ExtensionMarketplaceIndex.fromJson(Map<String, Object?> json) {
    return ExtensionMarketplaceIndex(
      workspaceId: json['workspaceId'] as String? ?? '',
      listings: _jsonMarketplaceListings(json['listings']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extensions: _collectUnknown(json),
    );
  }

  static const Set<String> _knownKeys = <String>{
    'workspaceId',
    'listingCount',
    'installableCount',
    'listings',
    'updatedAt',
    'schemaVersion',
  };

  static Map<String, Object?> _collectUnknown(Map<String, Object?> json) {
    return Map<String, Object?>.fromEntries(
      json.entries.where((entry) => !_knownKeys.contains(entry.key)),
    );
  }

  final String workspaceId;
  final List<ExtensionMarketplaceListing> listings;
  final DateTime? updatedAt;
  final int schemaVersion;
  final Map<String, Object?> extensions;

  ExtensionMarketplaceListing? lookup(String extensionId) {
    final normalizedId = extensionId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final listing in sortedListings) {
      if (listing.extensionId == normalizedId) {
        return listing;
      }
    }
    return null;
  }

  List<ExtensionMarketplaceListing> get sortedListings {
    final result = listings.toList(growable: false)
      ..sort((left, right) => left.extensionId.compareTo(right.extensionId));
    return result;
  }

  List<ExtensionMarketplaceListing> search(String query) {
    return sortedListings
        .where((listing) => listing.matchesQuery(query))
        .toList(growable: false);
  }

  ExtensionInstallPlan installPlan({
    required ExtensionManifestRegistry installedRegistry,
    required String extensionId,
  }) {
    final normalizedId = extensionId.trim();
    final listing = lookup(normalizedId);
    if (listing == null || !listing.valid) {
      return ExtensionInstallPlan(
        extensionId: normalizedId,
        status: ExtensionInstallPlanStatus.blockedInvalidListing,
        message:
            'Extension $normalizedId is missing a valid marketplace listing.',
        listing: listing,
      );
    }
    if (installedRegistry.lookup(normalizedId) != null) {
      return ExtensionInstallPlan(
        extensionId: normalizedId,
        status: ExtensionInstallPlanStatus.alreadyInstalled,
        message: 'Extension $normalizedId is already installed.',
        listing: listing,
      );
    }
    return ExtensionInstallPlan(
      extensionId: normalizedId,
      status: ExtensionInstallPlanStatus.ready,
      message: 'Extension $normalizedId can be installed from marketplace.',
      listing: listing,
      todo:
          'TODO: execute this plan through ExtensionMarketplaceInstallExecutor with a concrete downloader.',
    );
  }

  ExtensionMarketplaceIndex copyWith({
    String? workspaceId,
    List<ExtensionMarketplaceListing>? listings,
    DateTime? updatedAt,
  }) {
    return ExtensionMarketplaceIndex(
      workspaceId: workspaceId ?? this.workspaceId,
      listings: listings ?? this.listings,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    final listings = sortedListings;
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'workspaceId': workspaceId,
      'listingCount': listings.length,
      'installableCount': listings.where((listing) => listing.valid).length,
      'listings': listings
          .map((listing) => listing.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      ...extensions,
    };
  }
}

class ExtensionMarketplaceIndexStore {
  ExtensionMarketplaceIndexStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'extension.marketplace-index',
             layer: 'extension',
             stateFamily: 'extension-marketplace',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const ExtensionMarketplaceIndexStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'extension.marketplace-index';
  static const String _key = 'listings';

  final FoundationDataStoreOwner _owner;

  Future<void> saveIndex(ExtensionMarketplaceIndex index) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: index.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: index.workspaceId,
    );
  }

  Future<ExtensionMarketplaceIndex> readIndex({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return ExtensionMarketplaceIndex(workspaceId: workspaceId);
    }
    final index = ExtensionMarketplaceIndex.fromJson(value);
    return index.workspaceId.isEmpty
        ? index.copyWith(workspaceId: workspaceId)
        : index;
  }

  Future<bool> deleteIndex({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchIndex({required String workspaceId}) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<ExtensionMarketplaceListing> _jsonMarketplaceListings(Object? value) {
  if (value is! List) {
    return const <ExtensionMarketplaceListing>[];
  }
  return value
      .whereType<Map>()
      .map(
        (listing) => ExtensionMarketplaceListing.fromJson(
          listing.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .whereType<String>()
      .where((item) => item.trim().isNotEmpty)
      .toList(growable: false);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}
