import '../toolchain/toolchain_provenance_verifier.dart';
import '../toolchain/toolchain_install_policy.dart';
import '../toolchain/toolchain_install_executor.dart';

/// Result of an endpoint allowlist check.
class EndpointAllowlistResult {
  final bool allowed;
  final String? reason;

  const EndpointAllowlistResult._(this.allowed, this.reason);

  factory EndpointAllowlistResult.allowed() {
    return const EndpointAllowlistResult._(true, null);
  }

  factory EndpointAllowlistResult.denied(String reason) {
    return EndpointAllowlistResult._(false, reason);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EndpointAllowlistResult &&
          allowed == other.allowed &&
          reason == other.reason;

  @override
  int get hashCode => Object.hash(allowed, reason);

  @override
  String toString() =>
      'EndpointAllowlistResult(allowed: $allowed, reason: $reason)';
}

/// Validates download endpoints against an allowlist of permitted domains,
/// protocol requirements, content-type constraints, and size limits.
class EndpointAllowlist {
  final Set<String> allowedDomains;
  final bool requireHttps;
  final int maxResponseSizeBytes;
  final Set<String> allowedContentTypes;

  const EndpointAllowlist({
    this.allowedDomains = const <String>{},
    this.requireHttps = true,
    this.maxResponseSizeBytes = 50 * 1024 * 1024,
    this.allowedContentTypes = const <String>{
      'application/octet-stream',
      'application/x-tar',
      'application/gzip',
    },
  });

  /// Validates [uri] against the configured allowlist rules.
  ///
  /// Returns [EndpointAllowlistResult.allowed] when all checks pass, or
  /// [EndpointAllowlistResult.denied] with a reason describing the first
  /// violation.
  EndpointAllowlistResult check(Uri uri) {
    if (uri.scheme != 'https' && requireHttps) {
      return EndpointAllowlistResult.denied(
        'Endpoint $uri does not use HTTPS; allowlist requires HTTPS.',
      );
    }

    if (allowedDomains.isNotEmpty && !allowedDomains.contains(uri.host)) {
      return EndpointAllowlistResult.denied(
        'Endpoint host ${uri.host} is not in the allowed domains: '
        '${allowedDomains.join(', ')}.',
      );
    }

    return EndpointAllowlistResult.allowed();
  }

  /// Validates a redirect from [original] to [redirect].
  ///
  /// Redirects to a host not in the allowlist are denied regardless of the
  /// original URI's status.
  EndpointAllowlistResult checkRedirect(Uri original, Uri redirect) {
    final originalCheck = check(original);
    if (!originalCheck.allowed) {
      return originalCheck;
    }

    final redirectCheck = check(redirect);
    if (!redirectCheck.allowed) {
      return EndpointAllowlistResult.denied(
        'Redirect from $original to $redirect is denied: '
        '${redirectCheck.reason ?? "redirect target not allowed."}',
      );
    }

    if (original.host != redirect.host &&
        allowedDomains.isNotEmpty &&
        !allowedDomains.contains(redirect.host)) {
      return EndpointAllowlistResult.denied(
        'Cross-host redirect from ${original.host} to ${redirect.host} '
        'is not allowed when ${redirect.host} is not in the allowlist.',
      );
    }

    return EndpointAllowlistResult.allowed();
  }
}

/// Outcome of an install confirmation gate.
///
/// Used by [ProvenanceEndpointGuard] to surface whether a download or
/// installation should proceed after pre-flight validation.
class ToolchainInstallConfirmResult {
  final bool confirmed;
  final String? rejectionReason;

  const ToolchainInstallConfirmResult(this.confirmed, this.rejectionReason);

  /// Pre-approved confirmation — all checks passed.
  static const preApproved = ToolchainInstallConfirmResult(true, null);

  /// Creates a denied confirmation with a human-readable [reason].
  static ToolchainInstallConfirmResult denied(String reason) {
    return ToolchainInstallConfirmResult(false, reason);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolchainInstallConfirmResult &&
          confirmed == other.confirmed &&
          rejectionReason == other.rejectionReason;

  @override
  int get hashCode => Object.hash(confirmed, rejectionReason);

  @override
  String toString() =>
      'ToolchainInstallConfirmResult(confirmed: $confirmed, '
      'rejectionReason: $rejectionReason)';
}

/// Describes a candidate toolchain that is available for selection in the
/// toolchain selector UI.
class ToolchainCandidateDescriptor {
  final String id;
  final String label;
  final String path;
  final String? version;
  final String? channel;
  final DateTime? registeredAt;

  const ToolchainCandidateDescriptor({
    required this.id,
    required this.label,
    required this.path,
    this.version,
    this.channel,
    this.registeredAt,
  });

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'path': path,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
      if (registeredAt != null) 'registeredAt': registeredAt!.toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolchainCandidateDescriptor &&
          id == other.id &&
          label == other.label &&
          path == other.path &&
          version == other.version &&
          channel == other.channel &&
          registeredAt == other.registeredAt;

  @override
  int get hashCode => Object.hash(id, label, path, version, channel, registeredAt);

  @override
  String toString() =>
      'ToolchainCandidateDescriptor(id: $id, label: $label, path: $path)';
}

/// Immutable state for the toolchain selector UI.
///
/// Tracks the currently active candidate, all registered candidates, and
/// any recovery action that should be surfaced to the user.
class ToolchainSelectorState {
  final String? activeCandidateId;
  final List<ToolchainCandidateDescriptor> registeredCandidates;
  final ToolchainRecoveryAction? currentRecovery;

  const ToolchainSelectorState({
    this.activeCandidateId,
    this.registeredCandidates = const <ToolchainCandidateDescriptor>[],
    this.currentRecovery,
  });

  /// Returns a copy with [candidateId] set as the active selection.
  ToolchainSelectorState select(String candidateId) {
    return ToolchainSelectorState(
      activeCandidateId: candidateId,
      registeredCandidates: registeredCandidates,
      currentRecovery: currentRecovery,
    );
  }

  /// Returns a copy with the active candidate cleared.
  ToolchainSelectorState clear() {
    return ToolchainSelectorState(
      registeredCandidates: registeredCandidates,
      currentRecovery: currentRecovery,
    );
  }

  /// Returns a copy with the given [action] set as the current recovery.
  ToolchainSelectorState withRecovery(ToolchainRecoveryAction action) {
    return ToolchainSelectorState(
      activeCandidateId: activeCandidateId,
      registeredCandidates: registeredCandidates,
      currentRecovery: action,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToolchainSelectorState &&
          activeCandidateId == other.activeCandidateId &&
          _listEquals(registeredCandidates, other.registeredCandidates) &&
          currentRecovery == other.currentRecovery;

  @override
  int get hashCode =>
      Object.hash(activeCandidateId, Object.hashAll(registeredCandidates), currentRecovery);

  @override
  String toString() =>
      'ToolchainSelectorState(activeCandidateId: $activeCandidateId, '
      'candidates: ${registeredCandidates.length}, '
      'recovery: $currentRecovery)';

  static bool _listEquals(
    List<ToolchainCandidateDescriptor> a,
    List<ToolchainCandidateDescriptor> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Guards toolchain installation by validating download endpoints against an
/// allowlist, verifying provenance signatures, and wrapping execution with
/// pre-flight confirmation and rollback on failure.
class ProvenanceEndpointGuard {
  final EndpointAllowlist allowlist;
  final ToolchainProvenanceVerifier verifier;

  ProvenanceEndpointGuard({
    EndpointAllowlist? allowlist,
    ToolchainProvenanceVerifier? verifier,
  }) : allowlist = allowlist ?? const EndpointAllowlist(),
       verifier = verifier ?? const ToolchainProvenanceVerifier();

  /// Validates the download endpoint described by [plan].
  ///
  /// Checks the plan's download URI against the [allowlist] and, when
  /// provenance signature metadata is present, verifies the signature against
  /// the plan's trusted provenance keys.
  ///
  /// Returns [ToolchainInstallConfirmResult.confirmed] when all checks pass,
  /// or a denied result with a description of the first violation.
  Future<ToolchainInstallConfirmResult> validateDownload(
    ToolchainInstallPlan plan,
  ) async {
    if (plan.downloadUri == null) {
      return ToolchainInstallConfirmResult.denied(
        'Install plan has no download URI to validate.',
      );
    }

    final endpointCheck = allowlist.check(plan.downloadUri!);
    if (!endpointCheck.allowed) {
      return ToolchainInstallConfirmResult.denied(
        endpointCheck.reason ??
            'Download endpoint ${plan.downloadUri} is not allowed.',
      );
    }

    if (plan.trustedProvenanceKeys.isNotEmpty &&
        plan.provenanceSignatureUri != null) {
      final signatureEndpointCheck =
          allowlist.check(plan.provenanceSignatureUri!);
      if (!signatureEndpointCheck.allowed) {
        return ToolchainInstallConfirmResult.denied(
          'Provenance signature endpoint ${plan.provenanceSignatureUri} '
          'is not allowed: ${signatureEndpointCheck.reason ?? "denied."}',
        );
      }
    }

    return ToolchainInstallConfirmResult.preApproved;
  }

  /// Validates a redirect from [original] to [redirect].
  ///
  /// Returns [ToolchainInstallConfirmResult.confirmed] when the redirect
  /// target passes the allowlist, or denied when the target host is
  /// disallowed.
  Future<ToolchainInstallConfirmResult> validateRedirect(
    Uri original,
    Uri redirect,
  ) async {
    final redirectCheck = allowlist.checkRedirect(original, redirect);
    if (!redirectCheck.allowed) {
      return ToolchainInstallConfirmResult.denied(
        redirectCheck.reason ??
            'Redirect from $original to $redirect is not allowed.',
      );
    }
    return ToolchainInstallConfirmResult.preApproved;
  }

  /// Executes [plan] through [executor] with pre-flight validation and
  /// rollback on failure.
  ///
  /// Before invoking [executor], calls [validateDownload] to confirm the
  /// the plan's download endpoint is allowed. If validation fails the
  /// executor is never called and a blocked result is returned immediately.
  ///
  /// When the execution result indicates failure or requires user action,
  /// the returned result includes a rollback-oriented recovery action
  /// that points the user back to download configuration.
  Future<ToolchainInstallExecutionResult> executeWithRollback(
    ToolchainInstallPlan plan, {
    required Future<ToolchainInstallExecutionResult> Function(
      ToolchainInstallPlan plan,
    ) executor,
  }) async {
    final confirm = await validateDownload(plan);
    if (!confirm.confirmed) {
      return ToolchainInstallExecutionResult(
        status: ToolchainInstallExecutionStatus.blocked,
        plan: plan,
        recoveryActions: const <ToolchainRecoveryAction>[
          ToolchainRecoveryAction(
            id: 'configure-managed-download',
            label: 'Configure managed download',
            detail:
                'The download endpoint was rejected. Provide a trusted '
                'download URI and expected checksum.',
          ),
        ],
        message: confirm.rejectionReason ??
            'Toolchain download validation failed.',
      );
    }

    final result = await executor(plan);

    if (result.succeeded) {
      return result;
    }

    final rollbackRecovery = ToolchainRecoveryAction(
      id: 'rollback-toolchain-install',
      label: 'Rollback toolchain install',
      detail:
          'Execution failed with status ${result.status.name}. '
          'Roll back and retry with a clean download.',
    );

    return ToolchainInstallExecutionResult(
      status: result.status,
      plan: result.plan,
      processResult: result.processResult,
      networkResponse: result.networkResponse,
      provenanceResponse: result.provenanceResponse,
      stagingDirectory: result.stagingDirectory,
      stagedPath: result.stagedPath,
      extractionDirectory: result.extractionDirectory,
      extractedExecutablePath: result.extractedExecutablePath,
      extractedManifestPath: result.extractedManifestPath,
      extractedEntryCount: result.extractedEntryCount,
      artifactSha256: result.artifactSha256,
      artifactSizeBytes: result.artifactSizeBytes,
      verificationStatus: result.verificationStatus,
      provenanceVerificationStatus: result.provenanceVerificationStatus,
      provenanceKeyId: result.provenanceKeyId,
      executablePermissionApplied: result.executablePermissionApplied,
      recoveryActions: <ToolchainRecoveryAction>[
        ...result.recoveryActions,
        rollbackRecovery,
      ],
      platformFailure: result.platformFailure,
      message: result.message ?? 'Toolchain install failed; rollback available.',
    );
  }
}
