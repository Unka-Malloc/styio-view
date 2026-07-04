
/// Describes the health of the semantic index for a document or workspace.
///
/// Mirrors the capability-health model in StyioServiceCapabilityHealth
/// but is scoped to index freshness and upstream availability rather than
/// transport or provider-level health.
enum SemanticIndexStatus {
  /// The index is fully computed and up-to-date with the current document,
  /// workspace graph, toolchain, and provider facts.
  ready,

  /// The index is available but was produced from a partial or approximate
  /// analysis (e.g. built from local fallback when the primary service was
  /// unavailable, or derived from syntax-only information).
  degraded,

  /// The index cannot be built because one or more upstream facts
  /// (toolchain, provider, protocol version) are absent or incompatible.
  blocked,

  /// The index exists but was produced for an older revision, workspace
  /// graph, or upstream fact set, and has not been refreshed.
  stale,
}

extension SemanticIndexStatusX on SemanticIndexStatus {
  bool get isUsable => switch (this) {
    SemanticIndexStatus.ready => true,
    SemanticIndexStatus.degraded => true,
    SemanticIndexStatus.blocked => false,
    SemanticIndexStatus.stale => false,
  };

  String get wireValue => switch (this) {
    SemanticIndexStatus.ready => 'ready',
    SemanticIndexStatus.degraded => 'degraded',
    SemanticIndexStatus.blocked => 'blocked',
    SemanticIndexStatus.stale => 'stale',
  };
}

/// Composite invalidation keys that identify when a semantic index needs
/// to be rebuilt. Every field must match the corresponding fact from
/// Vityo cache ([LanguageCacheEntry]) and the toolchain/provider layer.
class SemanticIndexInvalidationKeys {
  const SemanticIndexInvalidationKeys({
    required this.documentId,
    required this.revision,
    required this.workspaceGraphHash,
    required this.toolchainId,
    required this.providerId,
    required this.protocolVersion,
    required this.semanticPayloadVersion,
  });

  final String documentId;
  final int revision;
  final String workspaceGraphHash;
  final String toolchainId;
  final String providerId;
  final String protocolVersion;
  final String semanticPayloadVersion;

  /// Canonical composite key that must match [LanguageCacheEntry.compositeKey]
  /// for cache lookups to succeed.
  String get compositeKey =>
      '$documentId:$revision:$workspaceGraphHash:$toolchainId:$providerId:$protocolVersion:$semanticPayloadVersion';

  /// True when every key matches the corresponding value in [other].
  bool matches(SemanticIndexInvalidationKeys other) {
    return documentId == other.documentId &&
        revision == other.revision &&
        workspaceGraphHash == other.workspaceGraphHash &&
        toolchainId == other.toolchainId &&
        providerId == other.providerId &&
        protocolVersion == other.protocolVersion &&
        semanticPayloadVersion == other.semanticPayloadVersion;
  }

  @override
  bool operator ==(Object other) =>
      other is SemanticIndexInvalidationKeys && matches(other);

  @override
  int get hashCode => Object.hash(
    documentId,
    revision,
    workspaceGraphHash,
    toolchainId,
    providerId,
    protocolVersion,
    semanticPayloadVersion,
  );

  @override
  String toString() => 'InvalidationKeys($compositeKey)';
}

/// Reason returned when a refactor or cross-file navigation operation is
/// gated because the semantic index is not in a usable state.
class SemanticGateReason {
  const SemanticGateReason({
    required this.status,
    required this.message,
    this.detail = '',
  });

  /// The index status that triggered this gate.
  final SemanticIndexStatus status;

  /// User-facing message explaining why the operation is unavailable.
  final String message;

  /// Optional longer explanation with resolution hints.
  final String detail;
}

/// Core semantic model for Styio language documents.
///
/// Owns the invalidation keys and status logic that determine whether
/// advanced IDE features (rename, find-all-references, refactor, etc.)
/// can operate. Status is derived from the current keys compared against
/// the latest upstream facts (workspace graph, toolchain, provider).
///
/// This is the repo-local contract slice that IDE surfaces query before
/// dispatching to [StyioNavigationFeature], [StyioRefactorFeature], etc.
class StyioSemanticCore {
  const StyioSemanticCore({
    required this.keys,
    this.status = SemanticIndexStatus.stale,
    this.lastReadyKeys,
    this.readyAt,
    this.degradedReason = '',
    this.blockedReason = '',
  });

  /// Current invalidation keys for this core instance.
  final SemanticIndexInvalidationKeys keys;

  /// Computed status based on the latest evaluation.
  final SemanticIndexStatus status;

  /// Snapshot of keys from the last [SemanticIndexStatus.ready] state.
  /// Preserved so that stale indexes can still report what they _were_
  /// built from, enabling fallback presentation.
  final SemanticIndexInvalidationKeys? lastReadyKeys;

  /// When this core last entered [SemanticIndexStatus.ready].
  final DateTime? readyAt;

  /// Machine-readable reason when [status] is [SemanticIndexStatus.degraded].
  final String degradedReason;

  /// Machine-readable reason when [status] is [SemanticIndexStatus.blocked].
  final String blockedReason;

  /// Whether the core is in a state that allows advanced refactors.
  bool get isRefactorReady => status.isUsable;

  /// Whether the core is in a state that allows cross-file navigation.
  bool get isCrossFileNavigationReady => status == SemanticIndexStatus.ready;

  /// Evaluate the gate for an advanced refactor operation.
  ///
  /// Returns `null` when the operation is permitted, or a [SemanticGateReason]
  /// describing why it is disabled or degraded.
  SemanticGateReason? refactorGate() {
    switch (status) {
      case SemanticIndexStatus.ready:
        return null;
      case SemanticIndexStatus.degraded:
        return SemanticGateReason(
          status: status,
          message: 'Refactor is degraded because $degradedReason.',
          detail:
              'Results may be incomplete. '
              'Verify changes manually before committing.',
        );
      case SemanticIndexStatus.blocked:
        return SemanticGateReason(
          status: status,
          message: 'Refactor is blocked: $blockedReason.',
          detail:
              'Resolve the blockage (toolchain, provider, '
              'or protocol version) and re-index.',
        );
      case SemanticIndexStatus.stale:
        return SemanticGateReason(
          status: status,
          message:
              'Refactor is unavailable because the semantic '
              'index is stale.',
          detail:
              'Trigger re-indexing by saving the document or '
              'running "Re-index Workspace" from the command palette.',
        );
    }
  }

  /// Evaluate the gate for a cross-file navigation operation.
  ///
  /// Cross-file navigation (go-to-definition into another file,
  /// find-all-references across files) requires a fully ready index
  /// because stale or degraded facts can lead to incorrect locations.
  ///
  /// Returns `null` when the operation is permitted, or a
  /// [SemanticGateReason] describing why it is disabled.
  SemanticGateReason? crossFileNavigationGate() {
    switch (status) {
      case SemanticIndexStatus.ready:
        return null;
      case SemanticIndexStatus.degraded:
        return SemanticGateReason(
          status: status,
          message:
              'Cross-file navigation is unavailable because '
              'the index is degraded: $degradedReason.',
          detail:
              'Only local-file navigation is available. '
              'Re-index when the upstream service recovers.',
        );
      case SemanticIndexStatus.blocked:
        return SemanticGateReason(
          status: status,
          message: 'Cross-file navigation is blocked: $blockedReason.',
          detail: 'Resolve the blockage and re-index.',
        );
      case SemanticIndexStatus.stale:
        return SemanticGateReason(
          status: status,
          message:
              'Cross-file navigation is unavailable because '
              'the semantic index is stale.',
          detail: 'Trigger re-indexing to enable cross-file navigation.',
        );
    }
  }

  /// Create a new [StyioSemanticCore] by evaluating the current keys
  /// against the latest upstream facts.
  ///
  /// [latestKeys] represents the most recent invalidation keys from
  /// the upstream (workspace graph, toolchain, provider).
  /// [lastReadyCore] is the previous ready core (or `null` if none).
  /// [upstreamBlockedReason] is set when upstream facts are absent.
  factory StyioSemanticCore.evaluate({
    required SemanticIndexInvalidationKeys latestKeys,
    required StyioSemanticCore? lastReadyCore,
    String upstreamBlockedReason = '',
    String upstreamDegradedReason = '',
  }) {
    // If upstream facts are absent, the core is blocked.
    if (upstreamBlockedReason.isNotEmpty) {
      return StyioSemanticCore(
        keys: latestKeys,
        status: SemanticIndexStatus.blocked,
        lastReadyKeys: lastReadyCore?.lastReadyKeys ?? lastReadyCore?.keys,
        readyAt: lastReadyCore?.readyAt,
        degradedReason: '',
        blockedReason: upstreamBlockedReason,
      );
    }

    // If the current keys match the ready keys, the core is ready.
    final readyKeys = lastReadyCore?.keys;
    if (readyKeys != null && latestKeys.matches(readyKeys)) {
      return StyioSemanticCore(
        keys: latestKeys,
        status: SemanticIndexStatus.ready,
        lastReadyKeys: lastReadyCore?.lastReadyKeys ?? readyKeys,
        readyAt: lastReadyCore?.readyAt,
        degradedReason: '',
        blockedReason: '',
      );
    }

    // If there was a previous ready core but keys diverged, we are stale.
    if (lastReadyCore != null) {
      return StyioSemanticCore(
        keys: latestKeys,
        status: SemanticIndexStatus.stale,
        lastReadyKeys: lastReadyCore.lastReadyKeys ?? lastReadyCore.keys,
        readyAt: lastReadyCore.readyAt,
        degradedReason: '',
        blockedReason: '',
      );
    }

    // No previous ready core: check if we should be degraded or stale.
    if (upstreamDegradedReason.isNotEmpty) {
      return StyioSemanticCore(
        keys: latestKeys,
        status: SemanticIndexStatus.degraded,
        lastReadyKeys: null,
        readyAt: null,
        degradedReason: upstreamDegradedReason,
        blockedReason: '',
      );
    }

    // Default: stale (no ready history, no explicit degradation).
    return StyioSemanticCore(
      keys: latestKeys,
      status: SemanticIndexStatus.stale,
      lastReadyKeys: null,
      readyAt: null,
      degradedReason: '',
      blockedReason: '',
    );
  }

  /// Convenience constructor for a fully ready core.
  factory StyioSemanticCore.ready({
    required SemanticIndexInvalidationKeys keys,
  }) {
    return StyioSemanticCore(
      keys: keys,
      status: SemanticIndexStatus.ready,
      lastReadyKeys: keys,
      readyAt: DateTime.now(),
      degradedReason: '',
      blockedReason: '',
    );
  }
}
