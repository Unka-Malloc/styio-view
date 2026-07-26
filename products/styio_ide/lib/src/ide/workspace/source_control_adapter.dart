/// Source Control adapter contract — capability-gap-safe model.
///
/// This is an adapter contract, not a Git client. Desktop may express
/// local git candidate; Web/iOS default blocked or hosted-controlled.
/// No real destructive git operations are implemented.
/// Real git integration requires permission model and approval flow.
library;

// ── Provider Kind ─────────────────────────────────────────────────

enum SourceControlProviderKind {
  /// No provider available.
  none,

  /// Local git repository detected.
  localGit,

  /// Hosted/cloud source control (Web/iOS route).
  hosted,

  /// Provider exists but is not currently accessible.
  unavailable,
}

// ── Change ────────────────────────────────────────────────────────

enum SourceControlChangeKind {
  modified,
  added,
  deleted,
  renamed,
  untracked,
  conflicted,
}

class SourceControlChange {
  const SourceControlChange({
    required this.filePath,
    required this.kind,
    this.oldPath,
    this.staged = false,
  });

  final String filePath;
  final SourceControlChangeKind kind;
  final String? oldPath;
  final bool staged;

  Map<String, Object?> toJson() => <String, Object?>{
        'filePath': filePath,
        'kind': kind.name,
        'oldPath': oldPath,
        'staged': staged,
      };
}

// ── Snapshot ──────────────────────────────────────────────────────

class SourceControlSnapshot {
  const SourceControlSnapshot({
    this.providerKind = SourceControlProviderKind.none,
    this.branchName = '',
    this.remoteName = '',
    this.changes = const <SourceControlChange>[],
    this.aheadCount = 0,
    this.behindCount = 0,
    this.unpulledCount = 0,
    this.blockedReason = '',
  });

  final SourceControlProviderKind providerKind;
  final String branchName;
  final String remoteName;
  final List<SourceControlChange> changes;
  final int aheadCount;
  final int behindCount;
  final int unpulledCount;

  /// If non-empty, the provider is blocked for this reason.
  final String blockedReason;

  bool get isAvailable =>
      providerKind != SourceControlProviderKind.none &&
      providerKind != SourceControlProviderKind.unavailable &&
      blockedReason.isEmpty;

  bool get hasChanges => changes.isNotEmpty;

  int get stagedCount => changes.where((c) => c.staged).length;
  int get unstagedCount => changes.where((c) => !c.staged).length;

  Map<String, Object?> toJson() => <String, Object?>{
        'providerKind': providerKind.name,
        'branchName': branchName,
        'remoteName': remoteName,
        'changes': changes.map((c) => c.toJson()).toList(growable: false),
        'stagedCount': stagedCount,
        'unstagedCount': unstagedCount,
        'aheadCount': aheadCount,
        'behindCount': behindCount,
        'unpulledCount': unpulledCount,
        'blockedReason': blockedReason,
        'isAvailable': isAvailable,
        'hasChanges': hasChanges,
      };

  static const SourceControlSnapshot none = SourceControlSnapshot();

  static SourceControlSnapshot blocked(String reason) =>
      SourceControlSnapshot(
        providerKind: SourceControlProviderKind.unavailable,
        blockedReason: reason,
      );

  static SourceControlSnapshot hostedBlocked() =>
      blocked('Source control is hosted-controlled on this platform.');

  static SourceControlSnapshot notMounted() =>
      blocked('Source control module is not mounted.');
}

// ── Local History ─────────────────────────────────────────────────

class LocalHistoryEntry {
  const LocalHistoryEntry({
    required this.entryId,
    required this.filePath,
    required this.savedAtIso8601,
    this.contentHash = '',
    this.byteLength = 0,
  });

  final String entryId;
  final String filePath;
  final String savedAtIso8601;
  final String contentHash;
  final int byteLength;

  Map<String, Object?> toJson() => <String, Object?>{
        'entryId': entryId,
        'filePath': filePath,
        'savedAtIso8601': savedAtIso8601,
        'contentHash': contentHash,
        'byteLength': byteLength,
      };
}

class LocalHistorySnapshot {
  const LocalHistorySnapshot({
    this.entries = const <LocalHistoryEntry>[],
    this.maxEntries = 100,
    this.persisted = false,
  });

  final List<LocalHistoryEntry> entries;
  final int maxEntries;
  final bool persisted;

  bool get isAvailable => persisted;

  Map<String, Object?> toJson() => <String, Object?>{
        'entries': entries.map((e) => e.toJson()).toList(growable: false),
        'maxEntries': maxEntries,
        'persisted': persisted,
        'isAvailable': isAvailable,
      };

  static const LocalHistorySnapshot empty = LocalHistorySnapshot();
}

// ── Adapter Contract ──────────────────────────────────────────────

/// Vityo-owned source control adapter contract.
///
/// Desktop may consume this via a local git CLI/FFI adapter.
/// Web/iOS routes return [SourceControlSnapshot.hostedBlocked].
/// This contract does not define write operations (commit, push, etc.)
/// because those require explicit permission/approval model.
abstract class SourceControlAdapter {
  /// Produces a source control snapshot for the current workspace.
  /// Returns [SourceControlSnapshot.none] if no provider is available.
  /// Returns [SourceControlSnapshot.blocked] if the route is unsupported.
  SourceControlSnapshot readSnapshot();

  /// Whether destructive operations (commit, push, reset, etc.) are
  /// permitted on this platform. Currently always returns false.
  bool get allowsDestructiveOperations;

  /// The provider kind available on this platform.
  SourceControlProviderKind get providerKind;
}
