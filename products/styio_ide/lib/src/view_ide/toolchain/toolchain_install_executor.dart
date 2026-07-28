import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/network/network_manager.dart';
import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../environment/system_compatibility/process/process_manager.dart';
import '../runtime/runtime.dart';
import 'toolchain_archive_extractor.dart';
import 'toolchain_catalog.dart';
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

class ToolchainInstallRuntimeExecutionPlan {
  ToolchainInstallRuntimeExecutionPlan({
    required this.installPlan,
    required this.definition,
    required this.executionPlan,
    required this.handoff,
    required this.binding,
  });

  factory ToolchainInstallRuntimeExecutionPlan.fromInstallPlan(
    ToolchainInstallPlan installPlan, {
    String outputChannelId = '',
  }) {
    final requirement = installPlan.requirement;
    final taskId = 'toolchain.install.${requirement.kind.wireValue}';
    final command = installPlan.actionable
        ? installPlan.externalCommand?.trim().isNotEmpty == true
              ? installPlan.externalCommand!.trim()
              : 'toolchain-install:${installPlan.mode.name}'
        : '';
    final definition = RuntimeTaskDefinition(
      id: taskId,
      label: 'Install ${requirement.kind.wireValue} toolchain',
      kind: RuntimeTaskKind.toolchain,
      command: command,
      arguments: installPlan.mode == ToolchainInstallMode.externalCommand
          ? installPlan.externalArguments
          : const <String>[],
      metadata: <String, Object?>{
        'toolchainInstall': true,
        'toolchainKind': requirement.kind.wireValue,
        'installMode': installPlan.mode.name,
        'installPlanStatus': installPlan.status.name,
        if (installPlan.downloadUri != null)
          'downloadUri': installPlan.downloadUri.toString(),
      },
    );
    final executionPlan = const RuntimeExecutionPlanner().plan(
      definition: definition,
    );
    final handoff = executionPlan.createHandoff(
      target: RuntimeExecutionHandoffTarget.toolchainManager,
      outputChannelId: outputChannelId.trim().isEmpty
          ? taskId
          : outputChannelId.trim(),
      metadata: const <String, Object?>{'toolchainInstall': true},
    );
    final binding = handoff.bind(
      outputKind: RuntimeOutputChannelKind.nativeTools,
      metadata: <String, Object?>{
        'toolchainInstall': true,
        'toolchainKind': requirement.kind.wireValue,
        'installMode': installPlan.mode.name,
      },
    );
    return ToolchainInstallRuntimeExecutionPlan(
      installPlan: installPlan,
      definition: definition,
      executionPlan: executionPlan,
      handoff: handoff,
      binding: binding,
    );
  }

  final ToolchainInstallPlan installPlan;
  final RuntimeTaskDefinition definition;
  final RuntimeExecutionPlan executionPlan;
  final RuntimeExecutionHandoff handoff;
  final RuntimeExecutionHandoffBinding binding;

  bool get ready => executionPlan.ready && handoff.ready && binding.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'installPlan': installPlan.toJson(),
      'definition': definition.toJson(),
      'executionPlan': executionPlan.toJson(),
      'handoff': handoff.toJson(),
      'binding': binding.toJson(),
    };
  }
}

enum ToolchainInstallRuntimeExecutionStatus { executed, blocked, wrongRoute }

extension ToolchainInstallRuntimeExecutionStatusX
    on ToolchainInstallRuntimeExecutionStatus {
  String get wireValue => switch (this) {
    ToolchainInstallRuntimeExecutionStatus.executed => 'executed',
    ToolchainInstallRuntimeExecutionStatus.blocked => 'blocked',
    ToolchainInstallRuntimeExecutionStatus.wrongRoute => 'wrong-route',
  };
}

class ToolchainInstallRuntimeExecutionResult {
  const ToolchainInstallRuntimeExecutionResult({
    required this.plan,
    required this.status,
    required this.dispatchResult,
    required this.outputEvents,
    this.execution,
  });

  final ToolchainInstallRuntimeExecutionPlan plan;
  final ToolchainInstallRuntimeExecutionStatus status;
  final RuntimeExecutionDispatchResult dispatchResult;
  final List<RuntimeOutputEvent> outputEvents;
  final ToolchainInstallExecutionResult? execution;

  bool get executed =>
      status == ToolchainInstallRuntimeExecutionStatus.executed;
  bool get succeeded => execution?.succeeded ?? false;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'executed': executed,
      'succeeded': succeeded,
      'plan': plan.toJson(),
      'dispatch': dispatchResult.toJson(),
      if (execution != null) 'execution': execution!.toJson(),
      'outputEvents': outputEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class ToolchainInstallRuntimeExecutionAdapter {
  ToolchainInstallRuntimeExecutionAdapter({
    required this.executor,
    RuntimeExecutionManagerRegistry? registry,
    RuntimeTaskClock? clock,
  }) : _registry =
           registry ?? RuntimeExecutionManagerRegistry.defaultManagers(),
       _clock = clock ?? DateTime.now().toUtc;

  final ToolchainInstallExecutor executor;
  final RuntimeExecutionManagerRegistry _registry;
  final RuntimeTaskClock _clock;

  Future<ToolchainInstallRuntimeExecutionResult> executePlan(
    ToolchainInstallRuntimeExecutionPlan plan, {
    required RuntimeOutputLiveBuffer buffer,
    Map<String, String> environment = const <String, String>{},
    Iterable<EnvironmentVariableOverlay> environmentOverlays =
        const <EnvironmentVariableOverlay>[],
    String? workingDirectory,
    Duration? timeout,
  }) async {
    final dispatchResult = _registry.dispatchToLiveBuffer(
      plan.binding,
      buffer: buffer,
      timestamp: _clock(),
      metadata: <String, Object?>{
        'toolchainInstall': true,
        'installMode': plan.installPlan.mode.name,
      },
    );
    if (plan.binding.managerId != 'toolchain-manager') {
      return _controlResult(
        plan: plan,
        buffer: buffer,
        dispatchResult: dispatchResult,
        status: ToolchainInstallRuntimeExecutionStatus.wrongRoute,
        message:
            'Toolchain install ignored non-toolchain route ${plan.binding.managerId}.',
      );
    }
    if (!plan.ready ||
        dispatchResult.status != RuntimeExecutionDispatchStatus.dispatched) {
      return _controlResult(
        plan: plan,
        buffer: buffer,
        dispatchResult: dispatchResult,
        status: ToolchainInstallRuntimeExecutionStatus.blocked,
        message: plan.ready
            ? dispatchResult.message
            : 'Toolchain install runtime plan is blocked.',
      );
    }

    final execution = await executor.execute(
      plan.installPlan,
      environment: environment,
      environmentOverlays: environmentOverlays,
      workingDirectory: workingDirectory,
      timeout: timeout,
    );
    final outputEvents = _eventsForExecution(
      binding: plan.binding,
      execution: execution,
    );
    for (final event in outputEvents) {
      buffer.addEvent(event, now: event.timestamp);
    }
    return ToolchainInstallRuntimeExecutionResult(
      plan: plan,
      status: ToolchainInstallRuntimeExecutionStatus.executed,
      dispatchResult: dispatchResult,
      execution: execution,
      outputEvents: List<RuntimeOutputEvent>.unmodifiable(outputEvents),
    );
  }

  ToolchainInstallRuntimeExecutionResult _controlResult({
    required ToolchainInstallRuntimeExecutionPlan plan,
    required RuntimeOutputLiveBuffer buffer,
    required RuntimeExecutionDispatchResult dispatchResult,
    required ToolchainInstallRuntimeExecutionStatus status,
    required String message,
  }) {
    final event = plan.binding.outputEvent(
      message: message,
      timestamp: _clock(),
      kind: RuntimeOutputChannelKind.runtimeEvents,
      metadata: <String, Object?>{
        'toolchainInstallRuntimeStatus': status.wireValue,
        'dispatchStatus': dispatchResult.status.wireValue,
      },
    );
    buffer.addEvent(event, now: event.timestamp);
    return ToolchainInstallRuntimeExecutionResult(
      plan: plan,
      status: status,
      dispatchResult: dispatchResult,
      outputEvents: <RuntimeOutputEvent>[event],
    );
  }

  List<RuntimeOutputEvent> _eventsForExecution({
    required RuntimeExecutionHandoffBinding binding,
    required ToolchainInstallExecutionResult execution,
  }) {
    final timestamp = _clock();
    return <RuntimeOutputEvent>[
      binding.outputEvent(
        message:
            execution.message ?? 'Toolchain install ${execution.status.name}.',
        timestamp: timestamp,
        kind: RuntimeOutputChannelKind.runtimeEvents,
        metadata: <String, Object?>{
          'toolchainInstallRuntimeStatus':
              ToolchainInstallRuntimeExecutionStatus.executed.wireValue,
          'installStatus': execution.status.name,
          'installSucceeded': execution.succeeded,
          'recoveryActionCount': execution.recoveryActions.length,
        },
      ),
      for (final line in _toolchainInstallOutputChunks(
        execution.processResult?.stdout ?? '',
      ))
        RuntimeOutputEvent(
          channelId: '${binding.outputChannel.id}.stdout',
          label: '${binding.outputChannel.label} stdout',
          kind: RuntimeOutputChannelKind.stdout,
          message: line,
          timestamp: timestamp,
          metadata: const <String, Object?>{
            'toolchainInstallRuntimeStatus': 'executed',
            'stream': 'stdout',
          },
        ),
      for (final line in _toolchainInstallOutputChunks(
        execution.processResult?.stderr ?? '',
      ))
        RuntimeOutputEvent(
          channelId: '${binding.outputChannel.id}.stderr',
          label: '${binding.outputChannel.label} stderr',
          kind: RuntimeOutputChannelKind.stderr,
          message: line,
          timestamp: timestamp,
          metadata: const <String, Object?>{
            'toolchainInstallRuntimeStatus': 'executed',
            'stream': 'stderr',
          },
        ),
    ];
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

List<String> _toolchainInstallOutputChunks(String output) {
  if (output.isEmpty) {
    return const <String>[];
  }
  final normalized = output.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.isEmpty ? <String>[output] : lines;
}
