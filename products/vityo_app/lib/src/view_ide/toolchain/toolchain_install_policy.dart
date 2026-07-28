import 'toolchain_resolver.dart';
import 'toolchain_archive_extractor.dart';
import 'toolchain_provenance_verifier.dart';

enum ToolchainInstallMode {
  disabled,
  manualSelection,
  managedDownload,
  externalCommand,
}

enum ToolchainInstallPlanStatus { planned, blocked }

class ToolchainInstallRequest {
  const ToolchainInstallRequest({
    required this.requirement,
    this.downloadUri,
    this.expectedSha256,
    this.expectedSizeBytes,
    this.stagedFileName,
    this.markExecutable = false,
    this.archiveFormat = ToolchainArchiveFormat.none,
    this.archiveExecutablePath,
    this.archiveManifestPath,
    this.externalCommand,
    this.externalArguments = const <String>[],
    this.provenanceSignatureUri,
  });

  final ToolchainRequirement requirement;
  final Uri? downloadUri;
  final String? expectedSha256;
  final int? expectedSizeBytes;
  final String? stagedFileName;
  final bool markExecutable;
  final ToolchainArchiveFormat archiveFormat;
  final String? archiveExecutablePath;
  final String? archiveManifestPath;
  final String? externalCommand;
  final List<String> externalArguments;
  final Uri? provenanceSignatureUri;
}

class ToolchainInstallPlan {
  const ToolchainInstallPlan({
    required this.status,
    required this.mode,
    required this.requirement,
    this.downloadUri,
    this.expectedSha256,
    this.expectedSizeBytes,
    this.stagedFileName,
    this.markExecutable = false,
    this.archiveFormat = ToolchainArchiveFormat.none,
    this.archiveExecutablePath,
    this.archiveManifestPath,
    this.externalCommand,
    this.externalArguments = const <String>[],
    this.provenanceSignatureUri,
    this.trustedProvenanceKeys = const <ToolchainProvenanceTrustRoot>[],
    this.message,
  });

  final ToolchainInstallPlanStatus status;
  final ToolchainInstallMode mode;
  final ToolchainRequirement requirement;
  final Uri? downloadUri;
  final String? expectedSha256;
  final int? expectedSizeBytes;
  final String? stagedFileName;
  final bool markExecutable;
  final ToolchainArchiveFormat archiveFormat;
  final String? archiveExecutablePath;
  final String? archiveManifestPath;
  final String? externalCommand;
  final List<String> externalArguments;
  final Uri? provenanceSignatureUri;
  final List<ToolchainProvenanceTrustRoot> trustedProvenanceKeys;
  final String? message;

  bool get actionable => status == ToolchainInstallPlanStatus.planned;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'mode': mode.name,
      'requirement': requirement.toJson(),
      if (downloadUri != null) 'downloadUri': downloadUri.toString(),
      if (expectedSha256 != null) 'expectedSha256': expectedSha256,
      if (expectedSizeBytes != null) 'expectedSizeBytes': expectedSizeBytes,
      if (stagedFileName != null) 'stagedFileName': stagedFileName,
      'markExecutable': markExecutable,
      'archiveFormat': archiveFormat.name,
      if (archiveExecutablePath != null)
        'archiveExecutablePath': archiveExecutablePath,
      if (archiveManifestPath != null)
        'archiveManifestPath': archiveManifestPath,
      if (externalCommand != null) 'externalCommand': externalCommand,
      if (externalArguments.isNotEmpty) 'externalArguments': externalArguments,
      if (provenanceSignatureUri != null)
        'provenanceSignatureUri': provenanceSignatureUri.toString(),
      if (trustedProvenanceKeys.isNotEmpty)
        'trustedProvenanceKeyIds': trustedProvenanceKeys
            .map((key) => key.keyId)
            .toList(growable: false),
      if (message != null) 'message': message,
      'actionable': actionable,
    };
  }
}

class ToolchainInstallPolicy {
  const ToolchainInstallPolicy({
    this.allowedModes = const <ToolchainInstallMode>{
      ToolchainInstallMode.manualSelection,
    },
    this.trustedDownloadHosts = const <String>{},
    this.requireManagedDownloadSha256 = false,
    this.requireManagedDownloadSignature = false,
    this.trustedProvenanceKeys = const <ToolchainProvenanceTrustRoot>[],
  });

  final Set<ToolchainInstallMode> allowedModes;
  final Set<String> trustedDownloadHosts;
  final bool requireManagedDownloadSha256;
  final bool requireManagedDownloadSignature;
  final List<ToolchainProvenanceTrustRoot> trustedProvenanceKeys;

  ToolchainInstallPlan plan(ToolchainInstallRequest request) {
    if (allowedModes.contains(ToolchainInstallMode.managedDownload) &&
        request.downloadUri != null) {
      final uri = request.downloadUri!;
      if (!_isTrustedDownloadUri(uri)) {
        return ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.blocked,
          mode: ToolchainInstallMode.managedDownload,
          requirement: request.requirement,
          downloadUri: uri,
          expectedSha256: request.expectedSha256,
          expectedSizeBytes: request.expectedSizeBytes,
          stagedFileName: request.stagedFileName,
          markExecutable: request.markExecutable,
          archiveFormat: request.archiveFormat,
          archiveExecutablePath: request.archiveExecutablePath,
          archiveManifestPath: request.archiveManifestPath,
          message:
              'Managed toolchain download host ${uri.host} is not trusted.',
        );
      }
      if (requireManagedDownloadSha256 &&
          (request.expectedSha256 == null ||
              request.expectedSha256!.trim().isEmpty)) {
        return ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.blocked,
          mode: ToolchainInstallMode.managedDownload,
          requirement: request.requirement,
          downloadUri: uri,
          expectedSizeBytes: request.expectedSizeBytes,
          stagedFileName: request.stagedFileName,
          markExecutable: request.markExecutable,
          archiveFormat: request.archiveFormat,
          archiveExecutablePath: request.archiveExecutablePath,
          message: 'Managed toolchain download requires an expected SHA-256.',
        );
      }
      if (requireManagedDownloadSignature) {
        final signatureUri = request.provenanceSignatureUri;
        if (signatureUri == null) {
          return ToolchainInstallPlan(
            status: ToolchainInstallPlanStatus.blocked,
            mode: ToolchainInstallMode.managedDownload,
            requirement: request.requirement,
            downloadUri: uri,
            expectedSha256: request.expectedSha256,
            expectedSizeBytes: request.expectedSizeBytes,
            stagedFileName: request.stagedFileName,
            markExecutable: request.markExecutable,
            archiveFormat: request.archiveFormat,
            archiveExecutablePath: request.archiveExecutablePath,
            archiveManifestPath: request.archiveManifestPath,
            message:
                'Managed toolchain download requires a provenance signature URI.',
          );
        }
        if (!_isTrustedDownloadUri(signatureUri)) {
          return ToolchainInstallPlan(
            status: ToolchainInstallPlanStatus.blocked,
            mode: ToolchainInstallMode.managedDownload,
            requirement: request.requirement,
            downloadUri: uri,
            expectedSha256: request.expectedSha256,
            expectedSizeBytes: request.expectedSizeBytes,
            stagedFileName: request.stagedFileName,
            markExecutable: request.markExecutable,
            archiveFormat: request.archiveFormat,
            archiveExecutablePath: request.archiveExecutablePath,
            archiveManifestPath: request.archiveManifestPath,
            provenanceSignatureUri: signatureUri,
            message:
                'Managed toolchain provenance signature host ${signatureUri.host} is not trusted.',
          );
        }
        if (trustedProvenanceKeys.isEmpty) {
          return ToolchainInstallPlan(
            status: ToolchainInstallPlanStatus.blocked,
            mode: ToolchainInstallMode.managedDownload,
            requirement: request.requirement,
            downloadUri: uri,
            expectedSha256: request.expectedSha256,
            expectedSizeBytes: request.expectedSizeBytes,
            stagedFileName: request.stagedFileName,
            markExecutable: request.markExecutable,
            archiveFormat: request.archiveFormat,
            archiveExecutablePath: request.archiveExecutablePath,
            archiveManifestPath: request.archiveManifestPath,
            provenanceSignatureUri: signatureUri,
            message:
                'Managed toolchain download requires at least one trusted provenance key.',
          );
        }
        return ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.managedDownload,
          requirement: request.requirement,
          downloadUri: uri,
          expectedSha256: request.expectedSha256,
          expectedSizeBytes: request.expectedSizeBytes,
          stagedFileName: request.stagedFileName,
          markExecutable: request.markExecutable,
          archiveFormat: request.archiveFormat,
          archiveExecutablePath: request.archiveExecutablePath,
          archiveManifestPath: request.archiveManifestPath,
          provenanceSignatureUri: signatureUri,
          trustedProvenanceKeys: trustedProvenanceKeys,
        );
      }
      return ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.managedDownload,
        requirement: request.requirement,
        downloadUri: uri,
        expectedSha256: request.expectedSha256,
        expectedSizeBytes: request.expectedSizeBytes,
        stagedFileName: request.stagedFileName,
        markExecutable: request.markExecutable,
        archiveFormat: request.archiveFormat,
        archiveExecutablePath: request.archiveExecutablePath,
        archiveManifestPath: request.archiveManifestPath,
        provenanceSignatureUri: request.provenanceSignatureUri,
        trustedProvenanceKeys: request.provenanceSignatureUri == null
            ? const <ToolchainProvenanceTrustRoot>[]
            : trustedProvenanceKeys,
      );
    }

    if (allowedModes.contains(ToolchainInstallMode.externalCommand) &&
        request.externalCommand != null &&
        request.externalCommand!.isNotEmpty) {
      return ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.externalCommand,
        requirement: request.requirement,
        externalCommand: request.externalCommand,
        externalArguments: request.externalArguments,
      );
    }

    if (allowedModes.contains(ToolchainInstallMode.manualSelection)) {
      return ToolchainInstallPlan(
        status: ToolchainInstallPlanStatus.planned,
        mode: ToolchainInstallMode.manualSelection,
        requirement: request.requirement,
        message: 'Select an existing toolchain executable.',
      );
    }

    return ToolchainInstallPlan(
      status: ToolchainInstallPlanStatus.blocked,
      mode: ToolchainInstallMode.disabled,
      requirement: request.requirement,
      message: 'Toolchain installation is disabled by policy.',
    );
  }

  bool _isTrustedDownloadUri(Uri uri) {
    if (uri.scheme != 'https') {
      return false;
    }
    return trustedDownloadHosts.contains(uri.host);
  }
}
