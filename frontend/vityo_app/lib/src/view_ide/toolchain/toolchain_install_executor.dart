import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/network/network_manager.dart';
import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../environment/system_compatibility/process/process_manager.dart';
import 'toolchain_archive_extractor.dart';
import 'toolchain_environment.dart';
import 'toolchain_install_policy.dart';
import 'toolchain_provenance_verifier.dart';

enum ToolchainInstallExecutionStatus {
  succeeded,
  staged,
  failed,
  blocked,
  requiresUserAction,
}

enum ToolchainArtifactVerificationStatus { notRequested, verified, failed }

class ToolchainArtifactVerification {
  const ToolchainArtifactVerification({
    required this.status,
    required this.artifactSha256,
    required this.artifactSizeBytes,
    this.message,
  });

  final ToolchainArtifactVerificationStatus status;
  final String artifactSha256;
  final int artifactSizeBytes;
  final String? message;

  bool get succeeded => status != ToolchainArtifactVerificationStatus.failed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'artifactSha256': artifactSha256,
      'artifactSizeBytes': artifactSizeBytes,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class ToolchainArtifactVerifier {
  const ToolchainArtifactVerifier();

  ToolchainArtifactVerification verify({
    required List<int> artifactBytes,
    String? expectedSha256,
    int? expectedSizeBytes,
  }) {
    final artifactSizeBytes = artifactBytes.length;
    final artifactSha256 = sha256.convert(artifactBytes).toString();
    final normalizedExpectedSha256 = expectedSha256?.trim().toLowerCase();

    if (normalizedExpectedSha256 != null &&
        normalizedExpectedSha256.isNotEmpty &&
        artifactSha256 != normalizedExpectedSha256) {
      return ToolchainArtifactVerification(
        status: ToolchainArtifactVerificationStatus.failed,
        artifactSha256: artifactSha256,
        artifactSizeBytes: artifactSizeBytes,
        message: 'Managed toolchain artifact SHA-256 mismatch.',
      );
    }
    if (expectedSizeBytes != null && artifactSizeBytes != expectedSizeBytes) {
      return ToolchainArtifactVerification(
        status: ToolchainArtifactVerificationStatus.failed,
        artifactSha256: artifactSha256,
        artifactSizeBytes: artifactSizeBytes,
        message: 'Managed toolchain artifact size mismatch.',
      );
    }
    return ToolchainArtifactVerification(
      status: normalizedExpectedSha256 == null && expectedSizeBytes == null
          ? ToolchainArtifactVerificationStatus.notRequested
          : ToolchainArtifactVerificationStatus.verified,
      artifactSha256: artifactSha256,
      artifactSizeBytes: artifactSizeBytes,
    );
  }
}

class ToolchainRecoveryAction {
  const ToolchainRecoveryAction({
    required this.id,
    required this.label,
    this.detail = '',
  });

  final String id;
  final String label;
  final String detail;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      if (detail.isNotEmpty) 'detail': detail,
    };
  }
}

class ToolchainInstallExecutionResult {
  const ToolchainInstallExecutionResult({
    required this.status,
    required this.plan,
    this.processResult,
    this.networkResponse,
    this.provenanceResponse,
    this.stagingDirectory,
    this.stagedPath,
    this.extractionDirectory,
    this.extractedExecutablePath,
    this.extractedManifestPath,
    this.extractedEntryCount,
    this.artifactSha256,
    this.artifactSizeBytes,
    this.verificationStatus,
    this.provenanceVerificationStatus,
    this.provenanceKeyId,
    this.executablePermissionApplied = false,
    this.recoveryActions = const <ToolchainRecoveryAction>[],
    this.platformFailure,
    this.message,
  });

  final ToolchainInstallExecutionStatus status;
  final ToolchainInstallPlan plan;
  final ProcessCommandResult? processResult;
  final NetworkBinaryResponse? networkResponse;
  final NetworkBinaryResponse? provenanceResponse;
  final String? stagingDirectory;
  final String? stagedPath;
  final String? extractionDirectory;
  final String? extractedExecutablePath;
  final String? extractedManifestPath;
  final int? extractedEntryCount;
  final String? artifactSha256;
  final int? artifactSizeBytes;
  final ToolchainArtifactVerificationStatus? verificationStatus;
  final ToolchainProvenanceVerificationStatus? provenanceVerificationStatus;
  final String? provenanceKeyId;
  final bool executablePermissionApplied;
  final List<ToolchainRecoveryAction> recoveryActions;
  final Map<String, Object?>? platformFailure;
  final String? message;

  bool get succeeded => status == ToolchainInstallExecutionStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'plan': plan.toJson(),
      if (processResult != null) 'processResult': processResult!.toJson(),
      if (networkResponse != null) 'networkResponse': networkResponse!.toJson(),
      if (provenanceResponse != null)
        'provenanceResponse': provenanceResponse!.toJson(),
      if (stagingDirectory != null) 'stagingDirectory': stagingDirectory,
      if (stagedPath != null) 'stagedPath': stagedPath,
      if (extractionDirectory != null)
        'extractionDirectory': extractionDirectory,
      if (extractedExecutablePath != null)
        'extractedExecutablePath': extractedExecutablePath,
      if (extractedManifestPath != null)
        'extractedManifestPath': extractedManifestPath,
      if (extractedEntryCount != null)
        'extractedEntryCount': extractedEntryCount,
      if (artifactSha256 != null) 'artifactSha256': artifactSha256,
      if (artifactSizeBytes != null) 'artifactSizeBytes': artifactSizeBytes,
      if (verificationStatus != null)
        'verificationStatus': verificationStatus!.name,
      if (provenanceVerificationStatus != null)
        'provenanceVerificationStatus': provenanceVerificationStatus!.name,
      if (provenanceKeyId != null) 'provenanceKeyId': provenanceKeyId,
      'executablePermissionApplied': executablePermissionApplied,
      if (recoveryActions.isNotEmpty)
        'recoveryActions': recoveryActions
            .map((action) => action.toJson())
            .toList(growable: false),
      if (platformFailure != null) 'platformFailure': platformFailure,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class ToolchainInstallExecutor {
  const ToolchainInstallExecutor({
    required PlatformManagerBundle platformManagers,
    ToolchainEnvironmentBuilder environmentBuilder =
        const ToolchainEnvironmentBuilder(),
  }) : _platformManagers = platformManagers,
       _environmentBuilder = environmentBuilder;

  final PlatformManagerBundle _platformManagers;
  final ToolchainEnvironmentBuilder _environmentBuilder;

  Future<ToolchainInstallExecutionResult> execute(
    ToolchainInstallPlan plan, {
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    if (!plan.actionable) {
      return ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.blocked,
        plan: plan,
        recoveryActions: _recoveryActionsForPlan(plan),
        message: plan.message ?? 'Toolchain installation plan is blocked.',
      );
    }

    return switch (plan.mode) {
      ToolchainInstallMode.disabled => ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.blocked,
        plan: plan,
        recoveryActions: _recoveryActionsForPlan(plan),
        message: plan.message ?? 'Toolchain installation is disabled.',
      ),
      ToolchainInstallMode.manualSelection => ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.requiresUserAction,
        plan: plan,
        recoveryActions: _recoveryActionsForPlan(plan),
        message: plan.message ?? 'Select an existing toolchain executable.',
      ),
      ToolchainInstallMode.managedDownload => _executeManagedDownload(
        plan,
        timeout: timeout,
      ),
      ToolchainInstallMode.externalCommand => _executeExternalCommand(
        plan,
        environment: environment,
        environmentOverlays: environmentOverlays,
        workingDirectory: workingDirectory,
        timeout: timeout,
      ),
    };
  }

  Future<ToolchainInstallExecutionResult> _executeManagedDownload(
    ToolchainInstallPlan plan, {
    Duration? timeout,
  }) async {
    final uri = plan.downloadUri;
    if (uri == null) {
      return ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.blocked,
        plan: plan,
        recoveryActions: _recoveryActionsForPlan(plan),
        message: 'Managed toolchain download URI is missing.',
      );
    }

    try {
      final response = await _platformManagers.network.getBytes(
        uri,
        timeout: timeout ?? const Duration(seconds: 30),
      );
      if (!response.succeeded) {
        return ToolchainInstallExecutionResult(
          status: ToolchainInstallExecutionStatus.failed,
          plan: plan,
          networkResponse: response,
          platformFailure: _platformManagers.network
              .failureForBytes(
                response,
                operation: 'toolchain.managed-download',
              )
              ?.toJson(),
          recoveryActions: _recoveryActionsForPlan(plan),
          message: response.message ?? 'Managed toolchain download failed.',
        );
      }
      if (response.bytes.isEmpty) {
        return ToolchainInstallExecutionResult(
          status: ToolchainInstallExecutionStatus.failed,
          plan: plan,
          networkResponse: response,
          recoveryActions: _recoveryActionsForPlan(plan),
          message: 'Managed toolchain download returned an empty artifact.',
        );
      }

      final artifactBytes = response.bytes;
      final verification = const ToolchainArtifactVerifier().verify(
        artifactBytes: artifactBytes,
        expectedSha256: plan.expectedSha256,
        expectedSizeBytes: plan.expectedSizeBytes,
      );
      final artifactSizeBytes = verification.artifactSizeBytes;
      final artifactSha256 = verification.artifactSha256;
      var effectiveVerificationStatus = verification.status;
      NetworkBinaryResponse? provenanceResponse;
      ToolchainProvenanceVerificationStatus? provenanceVerificationStatus;
      String? provenanceKeyId;
      if (!verification.succeeded) {
        return ToolchainInstallExecutionResult(
          status: ToolchainInstallExecutionStatus.failed,
          plan: plan,
          networkResponse: response,
          artifactSha256: artifactSha256,
          artifactSizeBytes: artifactSizeBytes,
          verificationStatus: verification.status,
          recoveryActions: _recoveryActionsForPlan(plan),
          message: verification.message,
        );
      }
      if (plan.provenanceSignatureUri != null ||
          plan.trustedProvenanceKeys.isNotEmpty) {
        final signatureUri = plan.provenanceSignatureUri;
        if (signatureUri == null) {
          return ToolchainInstallExecutionResult(
            status: ToolchainInstallExecutionStatus.failed,
            plan: plan,
            networkResponse: response,
            artifactSha256: artifactSha256,
            artifactSizeBytes: artifactSizeBytes,
            verificationStatus: effectiveVerificationStatus,
            provenanceVerificationStatus:
                ToolchainProvenanceVerificationStatus.failed,
            recoveryActions: _recoveryActionsForPlan(plan),
            message:
                'Managed toolchain provenance verification requires a signature URI.',
          );
        }
        provenanceResponse = await _platformManagers.network.getBytes(
          signatureUri,
          timeout: timeout ?? const Duration(seconds: 30),
        );
        if (!provenanceResponse.succeeded) {
          return ToolchainInstallExecutionResult(
            status: ToolchainInstallExecutionStatus.failed,
            plan: plan,
            networkResponse: response,
            provenanceResponse: provenanceResponse,
            artifactSha256: artifactSha256,
            artifactSizeBytes: artifactSizeBytes,
            verificationStatus: effectiveVerificationStatus,
            provenanceVerificationStatus:
                ToolchainProvenanceVerificationStatus.failed,
            platformFailure: _platformManagers.network
                .failureForBytes(
                  provenanceResponse,
                  operation: 'toolchain.managed-download.provenance',
                )
                ?.toJson(),
            recoveryActions: _recoveryActionsForPlan(plan),
            message:
                provenanceResponse.message ??
                'Managed toolchain provenance signature download failed.',
          );
        }
        final provenance = await const ToolchainProvenanceVerifier().verify(
          artifactBytes: artifactBytes,
          signaturePayload: utf8.decode(provenanceResponse.bytes),
          trustRoots: plan.trustedProvenanceKeys,
        );
        provenanceVerificationStatus = provenance.status;
        provenanceKeyId = provenance.verifiedKeyId;
        if (!provenance.succeeded) {
          return ToolchainInstallExecutionResult(
            status: ToolchainInstallExecutionStatus.failed,
            plan: plan,
            networkResponse: response,
            provenanceResponse: provenanceResponse,
            artifactSha256: artifactSha256,
            artifactSizeBytes: artifactSizeBytes,
            verificationStatus: effectiveVerificationStatus,
            provenanceVerificationStatus: provenanceVerificationStatus,
            recoveryActions: _recoveryActionsForPlan(plan),
            message: provenance.message,
          );
        }
        effectiveVerificationStatus =
            ToolchainArtifactVerificationStatus.verified;
      }

      final stagingDirectory = await _platformManagers.resource
          .createTempDirectory('vityo-toolchain-download-');
      final stagedPath = _platformManagers.fileSystem.joinPath(<String>[
        stagingDirectory,
        _downloadFileName(plan),
      ]);
      await _platformManagers.fileSystem.writeBytes(
        stagedPath,
        response.bytes,
        createParents: true,
        atomic: true,
      );
      String? extractionDirectory;
      String? extractedExecutablePath;
      String? extractedManifestPath;
      int? extractedEntryCount;
      var executableTargetPath = stagedPath;
      if (plan.archiveFormat == ToolchainArchiveFormat.tar) {
        extractionDirectory = await _platformManagers.resource
            .createTempDirectory('vityo-toolchain-extract-');
        final extraction =
            await ToolchainArchiveExtractor(
              fileSystemManager: _platformManagers.fileSystem,
            ).extractTar(
              archiveBytes: response.bytes,
              destinationDirectory: extractionDirectory,
            );
        extractedEntryCount = extraction.extractedEntryCount;
        if (!extraction.succeeded) {
          return ToolchainInstallExecutionResult(
            status: ToolchainInstallExecutionStatus.failed,
            plan: plan,
            networkResponse: response,
            stagingDirectory: stagingDirectory,
            stagedPath: stagedPath,
            extractionDirectory: extractionDirectory,
            extractedEntryCount: extractedEntryCount,
            artifactSha256: artifactSha256,
            artifactSizeBytes: artifactSizeBytes,
            verificationStatus: effectiveVerificationStatus,
            provenanceVerificationStatus: provenanceVerificationStatus,
            provenanceKeyId: provenanceKeyId,
            recoveryActions: _recoveryActionsForPlan(plan),
            message: extraction.message,
          );
        }
        final archiveExecutablePath = plan.archiveExecutablePath;
        if (archiveExecutablePath != null && archiveExecutablePath.isNotEmpty) {
          final validationError = _archiveExecutablePathError(
            archiveExecutablePath,
          );
          if (validationError != null) {
            return ToolchainInstallExecutionResult(
              status: ToolchainInstallExecutionStatus.failed,
              plan: plan,
              networkResponse: response,
              stagingDirectory: stagingDirectory,
              stagedPath: stagedPath,
              extractionDirectory: extractionDirectory,
              extractedEntryCount: extractedEntryCount,
              artifactSha256: artifactSha256,
              artifactSizeBytes: artifactSizeBytes,
              verificationStatus: effectiveVerificationStatus,
              provenanceVerificationStatus: provenanceVerificationStatus,
              provenanceKeyId: provenanceKeyId,
              recoveryActions: _recoveryActionsForPlan(plan),
              message: validationError,
            );
          }
          extractedExecutablePath = _platformManagers.fileSystem.joinPath(
            <String>[extractionDirectory, archiveExecutablePath],
          );
          executableTargetPath = extractedExecutablePath;
        }
        final archiveManifestPath = plan.archiveManifestPath;
        if (archiveManifestPath != null && archiveManifestPath.isNotEmpty) {
          final validationError = _archiveExecutablePathError(
            archiveManifestPath,
          );
          if (validationError != null) {
            return ToolchainInstallExecutionResult(
              status: ToolchainInstallExecutionStatus.failed,
              plan: plan,
              networkResponse: response,
              stagingDirectory: stagingDirectory,
              stagedPath: stagedPath,
              extractionDirectory: extractionDirectory,
              extractedExecutablePath: extractedExecutablePath,
              extractedEntryCount: extractedEntryCount,
              artifactSha256: artifactSha256,
              artifactSizeBytes: artifactSizeBytes,
              verificationStatus: effectiveVerificationStatus,
              provenanceVerificationStatus: provenanceVerificationStatus,
              provenanceKeyId: provenanceKeyId,
              message: validationError,
            );
          }
          extractedManifestPath = _platformManagers.fileSystem.joinPath(
            <String>[extractionDirectory, archiveManifestPath],
          );
        }
      }
      var executablePermissionApplied = false;
      if (plan.markExecutable) {
        await _platformManagers.fileSystem.setExecutable(executableTargetPath);
        executablePermissionApplied = await _platformManagers.fileSystem
            .isExecutable(executableTargetPath);
        if (!executablePermissionApplied) {
          return ToolchainInstallExecutionResult(
            status: ToolchainInstallExecutionStatus.failed,
            plan: plan,
            networkResponse: response,
            stagingDirectory: stagingDirectory,
            stagedPath: stagedPath,
            extractionDirectory: extractionDirectory,
            extractedExecutablePath: extractedExecutablePath,
            extractedManifestPath: extractedManifestPath,
            extractedEntryCount: extractedEntryCount,
            artifactSha256: artifactSha256,
            artifactSizeBytes: artifactSizeBytes,
            verificationStatus: effectiveVerificationStatus,
            provenanceVerificationStatus: provenanceVerificationStatus,
            provenanceKeyId: provenanceKeyId,
            recoveryActions: _recoveryActionsForPlan(plan),
            message: 'Managed toolchain artifact is not executable.',
          );
        }
      }

      return ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.staged,
        plan: plan,
        networkResponse: response,
        stagingDirectory: stagingDirectory,
        stagedPath: stagedPath,
        extractionDirectory: extractionDirectory,
        extractedExecutablePath: extractedExecutablePath,
        extractedManifestPath: extractedManifestPath,
        extractedEntryCount: extractedEntryCount,
        artifactSha256: artifactSha256,
        artifactSizeBytes: artifactSizeBytes,
        verificationStatus: effectiveVerificationStatus,
        provenanceVerificationStatus: provenanceVerificationStatus,
        provenanceKeyId: provenanceKeyId,
        executablePermissionApplied: executablePermissionApplied,
        message:
            'Managed toolchain artifact staged; install verification and '
            'registration must run before this toolchain is used.',
      );
    } on Object catch (error) {
      return ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.failed,
        plan: plan,
        recoveryActions: _recoveryActionsForPlan(plan),
        message: error.toString(),
      );
    }
  }

  Future<ToolchainInstallExecutionResult> _executeExternalCommand(
    ToolchainInstallPlan plan, {
    required Map<String, String> environment,
    required Iterable<EnvironmentVariableOverlay> environmentOverlays,
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final executablePath = plan.externalCommand;
    if (executablePath == null || executablePath.isEmpty) {
      return ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.blocked,
        plan: plan,
        recoveryActions: _recoveryActionsForPlan(plan),
        message: 'External toolchain install command is missing.',
      );
    }

    final result = await _platformManagers.process.run(
      ProcessCommandRequest(
        executablePath: executablePath,
        arguments: plan.externalArguments,
        environment: _environmentBuilder.build(
          overlays: environmentOverlays,
          runtimeOverrides: environment,
        ),
        workingDirectory: workingDirectory,
        timeout: timeout,
      ),
    );

    final platformFailure = result.succeeded
        ? null
        : _platformManagers.process
              .failureFor(result, operation: 'toolchain.external-install')
              ?.toJson();

    return ToolchainInstallExecutionResult(
      status: result.succeeded
          ? ToolchainInstallExecutionStatus.succeeded
          : ToolchainInstallExecutionStatus.failed,
      plan: plan,
      processResult: result,
      platformFailure: platformFailure,
      recoveryActions: result.succeeded
          ? const <ToolchainRecoveryAction>[]
          : _recoveryActionsForPlan(plan),
      message: result.message,
    );
  }

  List<ToolchainRecoveryAction> _recoveryActionsForPlan(
    ToolchainInstallPlan plan,
  ) {
    return switch (plan.mode) {
      ToolchainInstallMode.manualSelection => const <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select existing toolchain',
          detail: 'Choose a local executable and register it manually.',
        ),
      ],
      ToolchainInstallMode.managedDownload => const <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'configure-managed-download',
          label: 'Configure managed download',
          detail: 'Provide a trusted download URI and expected checksum.',
        ),
        ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select existing toolchain',
          detail: 'Use a local executable instead of managed download.',
        ),
      ],
      ToolchainInstallMode.externalCommand => const <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'retry-external-installer',
          label: 'Retry external installer',
          detail: 'Run the configured installer command again.',
        ),
        ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select existing toolchain',
          detail: 'Choose a local executable if the installer keeps failing.',
        ),
      ],
      ToolchainInstallMode.disabled => const <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'enable-toolchain-installation',
          label: 'Enable toolchain installation',
          detail: 'Change policy to allow a toolchain installation mode.',
        ),
      ],
    };
  }

  String _downloadFileName(ToolchainInstallPlan plan) {
    final configuredFileName = plan.stagedFileName;
    if (configuredFileName != null && configuredFileName.trim().isNotEmpty) {
      return _sanitizeFileName(configuredFileName);
    }
    final uri = plan.downloadUri!;
    String? candidate;
    for (final segment in uri.pathSegments) {
      if (segment.trim().isNotEmpty) {
        candidate = segment;
      }
    }
    final fileName = candidate == null || candidate.isEmpty
        ? 'toolchain-artifact.txt'
        : candidate;
    return _sanitizeFileName(fileName);
  }

  String _sanitizeFileName(String fileName) {
    final sanitized = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? 'toolchain-artifact.txt' : sanitized;
  }

  String? _archiveExecutablePathError(String path) {
    if (path.startsWith('/')) {
      return 'Archive executable path $path is absolute.';
    }
    for (final segment in path.split('/')) {
      if (segment == '..') {
        return 'Archive executable path $path escapes the extraction directory.';
      }
    }
    return null;
  }
}
