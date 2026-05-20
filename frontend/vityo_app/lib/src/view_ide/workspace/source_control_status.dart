import '../environment/system_compatibility/process/process_manager.dart';

enum SourceControlProviderKind { localDirtyDocuments, git, custom }

enum SourceControlProviderCapability {
  status,
  diff,
  actions,
  branches,
  branchActions,
  history,
}

enum SourceControlFileStatus {
  added,
  copied,
  deleted,
  ignored,
  modified,
  renamed,
  untracked,
  conflicted,
  unknown,
}

enum SourceControlActionKind { stage, unstage, discard, commit }

enum SourceControlActionRisk { safe, indexWrite, destructive, createsRevision }

extension SourceControlProviderKindX on SourceControlProviderKind {
  String get wireValue {
    return switch (this) {
      SourceControlProviderKind.localDirtyDocuments => 'local-dirty-documents',
      SourceControlProviderKind.git => 'git',
      SourceControlProviderKind.custom => 'custom',
    };
  }
}

extension SourceControlProviderCapabilityX on SourceControlProviderCapability {
  String get wireValue {
    return switch (this) {
      SourceControlProviderCapability.status => 'status',
      SourceControlProviderCapability.diff => 'diff',
      SourceControlProviderCapability.actions => 'actions',
      SourceControlProviderCapability.branches => 'branches',
      SourceControlProviderCapability.branchActions => 'branch-actions',
      SourceControlProviderCapability.history => 'history',
    };
  }
}

class SourceControlProviderAdapterDescriptor {
  const SourceControlProviderAdapterDescriptor({
    required this.id,
    required this.label,
    required this.providerKind,
    this.available = true,
    this.capabilities = const <SourceControlProviderCapability>[],
    this.metadata = const <String, Object?>{},
    this.message = '',
  });

  factory SourceControlProviderAdapterDescriptor.git({
    bool available = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return SourceControlProviderAdapterDescriptor(
      id: 'git',
      label: 'Git',
      providerKind: SourceControlProviderKind.git,
      available: available,
      capabilities: const <SourceControlProviderCapability>[
        SourceControlProviderCapability.status,
        SourceControlProviderCapability.diff,
        SourceControlProviderCapability.actions,
        SourceControlProviderCapability.branches,
        SourceControlProviderCapability.branchActions,
        SourceControlProviderCapability.history,
      ],
      metadata: metadata,
    );
  }

  final String id;
  final String label;
  final SourceControlProviderKind providerKind;
  final bool available;
  final List<SourceControlProviderCapability> capabilities;
  final Map<String, Object?> metadata;
  final String message;

  bool supports(SourceControlProviderCapability capability) {
    return available && capabilities.contains(capability);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'providerKind': providerKind.wireValue,
      'available': available,
      'capabilities': capabilities
          .map((capability) => capability.wireValue)
          .toList(growable: false),
      if (metadata.isNotEmpty) 'metadata': metadata,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class SourceControlProviderAdapterRegistry {
  SourceControlProviderAdapterRegistry({
    Iterable<SourceControlProviderAdapterDescriptor> adapters =
        const <SourceControlProviderAdapterDescriptor>[],
  }) {
    for (final adapter in adapters) {
      register(adapter);
    }
  }

  final List<SourceControlProviderAdapterDescriptor> _adapters =
      <SourceControlProviderAdapterDescriptor>[];

  List<SourceControlProviderAdapterDescriptor> get adapters {
    return List<SourceControlProviderAdapterDescriptor>.unmodifiable(_adapters);
  }

  void register(SourceControlProviderAdapterDescriptor adapter) {
    _adapters.removeWhere((candidate) => candidate.id == adapter.id);
    _adapters.add(adapter);
  }

  SourceControlProviderAdapterDescriptor? resolve({
    required SourceControlProviderCapability capability,
    SourceControlProviderKind? providerKind,
  }) {
    for (final adapter in _adapters) {
      if (providerKind != null && adapter.providerKind != providerKind) {
        continue;
      }
      if (adapter.supports(capability)) {
        return adapter;
      }
    }
    return null;
  }

  Map<String, Object?> manifest() {
    return <String, Object?>{
      'adapterCount': _adapters.length,
      'adapters': _adapters
          .map((adapter) => adapter.toJson())
          .toList(growable: false),
    };
  }
}

extension SourceControlActionKindX on SourceControlActionKind {
  String get wireValue {
    return switch (this) {
      SourceControlActionKind.stage => 'stage',
      SourceControlActionKind.unstage => 'unstage',
      SourceControlActionKind.discard => 'discard',
      SourceControlActionKind.commit => 'commit',
    };
  }
}

extension SourceControlActionRiskX on SourceControlActionRisk {
  String get wireValue {
    return switch (this) {
      SourceControlActionRisk.safe => 'safe',
      SourceControlActionRisk.indexWrite => 'index-write',
      SourceControlActionRisk.destructive => 'destructive',
      SourceControlActionRisk.createsRevision => 'creates-revision',
    };
  }
}

extension SourceControlFileStatusX on SourceControlFileStatus {
  String get wireValue {
    return switch (this) {
      SourceControlFileStatus.added => 'added',
      SourceControlFileStatus.copied => 'copied',
      SourceControlFileStatus.deleted => 'deleted',
      SourceControlFileStatus.ignored => 'ignored',
      SourceControlFileStatus.modified => 'modified',
      SourceControlFileStatus.renamed => 'renamed',
      SourceControlFileStatus.untracked => 'untracked',
      SourceControlFileStatus.conflicted => 'conflicted',
      SourceControlFileStatus.unknown => 'unknown',
    };
  }
}

class SourceControlActionRequest {
  const SourceControlActionRequest({
    required this.kind,
    this.paths = const <String>[],
    this.message = '',
  });

  final SourceControlActionKind kind;
  final List<String> paths;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'paths': paths,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class SourceControlActionPlan {
  const SourceControlActionPlan({
    required this.request,
    required this.normalizedPaths,
    required this.risk,
    required this.requiresConfirmation,
    required this.canRun,
    required this.summary,
    this.blockedReason = '',
  });

  factory SourceControlActionPlan.fromRequest(
    SourceControlActionRequest request,
  ) {
    final normalizedPaths = request.paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final blockedReason = _blockedActionReason(request, normalizedPaths);
    final risk = switch (request.kind) {
      SourceControlActionKind.stage => SourceControlActionRisk.indexWrite,
      SourceControlActionKind.unstage => SourceControlActionRisk.indexWrite,
      SourceControlActionKind.discard => SourceControlActionRisk.destructive,
      SourceControlActionKind.commit => SourceControlActionRisk.createsRevision,
    };
    return SourceControlActionPlan(
      request: SourceControlActionRequest(
        kind: request.kind,
        paths: normalizedPaths,
        message: request.message.trim(),
      ),
      normalizedPaths: normalizedPaths,
      risk: risk,
      requiresConfirmation:
          risk == SourceControlActionRisk.destructive ||
          risk == SourceControlActionRisk.createsRevision,
      canRun: blockedReason.isEmpty,
      blockedReason: blockedReason,
      summary: _actionPlanSummary(request, normalizedPaths, risk),
    );
  }

  final SourceControlActionRequest request;
  final List<String> normalizedPaths;
  final SourceControlActionRisk risk;
  final bool requiresConfirmation;
  final bool canRun;
  final String summary;
  final String blockedReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'request': request.toJson(),
      'normalizedPaths': normalizedPaths,
      'risk': risk.wireValue,
      'requiresConfirmation': requiresConfirmation,
      'canRun': canRun,
      'summary': summary,
      if (blockedReason.isNotEmpty) 'blockedReason': blockedReason,
    };
  }
}

class SourceControlActionResult {
  const SourceControlActionResult({
    required this.kind,
    required this.applied,
    this.paths = const <String>[],
    this.message = '',
  });

  final SourceControlActionKind kind;
  final bool applied;
  final List<String> paths;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'applied': applied,
      'paths': paths,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

String _blockedActionReason(
  SourceControlActionRequest request,
  List<String> normalizedPaths,
) {
  return switch (request.kind) {
    SourceControlActionKind.stage ||
    SourceControlActionKind.unstage ||
    SourceControlActionKind.discard =>
      normalizedPaths.isEmpty
          ? 'Source control ${request.kind.wireValue} requires at least one path.'
          : '',
    SourceControlActionKind.commit =>
      request.message.trim().isEmpty
          ? 'Source control commit requires a commit message.'
          : '',
  };
}

String _actionPlanSummary(
  SourceControlActionRequest request,
  List<String> normalizedPaths,
  SourceControlActionRisk risk,
) {
  final target = request.kind == SourceControlActionKind.commit
      ? request.message.trim()
      : '${normalizedPaths.length} path(s)';
  return '${request.kind.wireValue} $target · risk ${risk.wireValue}';
}

class SourceControlBranchSnapshot {
  const SourceControlBranchSnapshot({
    required this.providerKind,
    this.available = true,
    this.currentBranch = '',
    this.branches = const <String>[],
    this.message = '',
  });

  final SourceControlProviderKind providerKind;
  final bool available;
  final String currentBranch;
  final List<String> branches;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'available': available,
      if (currentBranch.isNotEmpty) 'currentBranch': currentBranch,
      if (message.isNotEmpty) 'message': message,
      'branchCount': branches.length,
      'branches': branches,
    };
  }
}

class SourceControlBranchSwitchPlan {
  const SourceControlBranchSwitchPlan({
    required this.providerKind,
    required this.targetBranch,
    required this.canRun,
    required this.summary,
    this.currentBranch = '',
    this.blockedReason = '',
  });

  factory SourceControlBranchSwitchPlan.fromSnapshot({
    required SourceControlBranchSnapshot snapshot,
    required String targetBranch,
  }) {
    final normalizedTarget = targetBranch.trim();
    final blockedReason = _branchSwitchBlockedReason(
      snapshot: snapshot,
      targetBranch: normalizedTarget,
    );
    return SourceControlBranchSwitchPlan(
      providerKind: snapshot.providerKind,
      currentBranch: snapshot.currentBranch,
      targetBranch: normalizedTarget,
      canRun: blockedReason.isEmpty,
      blockedReason: blockedReason,
      summary: blockedReason.isEmpty
          ? 'switch ${snapshot.currentBranch} -> $normalizedTarget'
          : blockedReason,
    );
  }

  final SourceControlProviderKind providerKind;
  final String currentBranch;
  final String targetBranch;
  final bool canRun;
  final String summary;
  final String blockedReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'currentBranch': currentBranch,
      'targetBranch': targetBranch,
      'canRun': canRun,
      'summary': summary,
      if (blockedReason.isNotEmpty) 'blockedReason': blockedReason,
    };
  }
}

class SourceControlBranchSwitchResult {
  const SourceControlBranchSwitchResult({
    required this.providerKind,
    required this.targetBranch,
    required this.applied,
    this.message = '',
  });

  final SourceControlProviderKind providerKind;
  final String targetBranch;
  final bool applied;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'targetBranch': targetBranch,
      'applied': applied,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class SourceControlHistoryEntry {
  const SourceControlHistoryEntry({
    required this.revision,
    required this.shortRevision,
    required this.summary,
    this.author = '',
    this.authoredAt = '',
  });

  final String revision;
  final String shortRevision;
  final String summary;
  final String author;
  final String authoredAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'revision': revision,
      'shortRevision': shortRevision,
      'summary': summary,
      if (author.isNotEmpty) 'author': author,
      if (authoredAt.isNotEmpty) 'authoredAt': authoredAt,
    };
  }
}

class SourceControlHistorySnapshot {
  const SourceControlHistorySnapshot({
    required this.providerKind,
    this.available = true,
    this.entries = const <SourceControlHistoryEntry>[],
    this.message = '',
  });

  final SourceControlProviderKind providerKind;
  final bool available;
  final List<SourceControlHistoryEntry> entries;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'available': available,
      if (message.isNotEmpty) 'message': message,
      'entryCount': entries.length,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class SourceControlFileChange {
  const SourceControlFileChange({
    required this.path,
    this.originalPath = '',
    this.stagedStatus,
    this.unstagedStatus,
  });

  final String path;
  final String originalPath;
  final SourceControlFileStatus? stagedStatus;
  final SourceControlFileStatus? unstagedStatus;

  bool get staged => stagedStatus != null;
  bool get unstaged => unstagedStatus != null;

  String get summary {
    final parts = <String>[
      if (stagedStatus != null) 'staged ${stagedStatus!.wireValue}',
      if (unstagedStatus != null) 'unstaged ${unstagedStatus!.wireValue}',
    ];
    return parts.isEmpty ? 'unknown' : parts.join(' · ');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      if (originalPath.isNotEmpty) 'originalPath': originalPath,
      if (stagedStatus != null) 'stagedStatus': stagedStatus!.wireValue,
      if (unstagedStatus != null) 'unstagedStatus': unstagedStatus!.wireValue,
      'summary': summary,
    };
  }
}

class SourceControlStatusSnapshot {
  const SourceControlStatusSnapshot({
    required this.providerKind,
    required this.changes,
    this.available = true,
    this.branchName = '',
    this.message = '',
  });

  final SourceControlProviderKind providerKind;
  final List<SourceControlFileChange> changes;
  final bool available;
  final String branchName;
  final String message;

  bool get clean => changes.isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'available': available,
      'clean': clean,
      if (branchName.isNotEmpty) 'branchName': branchName,
      if (message.isNotEmpty) 'message': message,
      'changeCount': changes.length,
      'changes': changes
          .map((change) => change.toJson())
          .toList(growable: false),
    };
  }
}

class SourceControlDiffSnapshot {
  const SourceControlDiffSnapshot({
    required this.providerKind,
    required this.path,
    this.available = true,
    this.unifiedDiff = '',
    this.message = '',
  });

  static const int maxSerializedDiffChars = 12000;

  final SourceControlProviderKind providerKind;
  final String path;
  final bool available;
  final String unifiedDiff;
  final String message;

  bool get empty => unifiedDiff.trim().isEmpty;

  int get lineCount {
    if (unifiedDiff.isEmpty) {
      return 0;
    }
    return unifiedDiff.split('\n').length;
  }

  SourceControlDiffReviewSummary get reviewSummary {
    var hunkCount = 0;
    var additionCount = 0;
    var deletionCount = 0;
    for (final line in unifiedDiff.split('\n')) {
      if (line.startsWith('@@')) {
        hunkCount += 1;
      } else if (line.startsWith('+') && !line.startsWith('+++')) {
        additionCount += 1;
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        deletionCount += 1;
      }
    }
    return SourceControlDiffReviewSummary(
      path: path,
      available: available,
      lineCount: lineCount,
      hunkCount: hunkCount,
      additionCount: additionCount,
      deletionCount: deletionCount,
      truncated: unifiedDiff.length > maxSerializedDiffChars,
    );
  }

  SourceControlDiffWindow window({int startLine = 0, int lineLimit = 200}) {
    return SourceControlDiffWindow.fromSnapshot(
      snapshot: this,
      startLine: startLine,
      lineLimit: lineLimit,
    );
  }

  Map<String, Object?> toJson() {
    final truncated = unifiedDiff.length > maxSerializedDiffChars;
    final visibleDiff = truncated
        ? unifiedDiff.substring(0, maxSerializedDiffChars)
        : unifiedDiff;
    return <String, Object?>{
      'providerKind': providerKind.wireValue,
      'path': path,
      'available': available,
      'empty': empty,
      'lineCount': lineCount,
      if (message.isNotEmpty) 'message': message,
      'diffTruncated': truncated,
      'reviewSummary': reviewSummary.toJson(),
      'defaultWindow': window().toJson(),
      'unifiedDiff': visibleDiff,
    };
  }
}

class SourceControlDiffWindow {
  const SourceControlDiffWindow({
    required this.path,
    required this.startLine,
    required this.totalLineCount,
    required this.lines,
  });

  factory SourceControlDiffWindow.fromSnapshot({
    required SourceControlDiffSnapshot snapshot,
    int startLine = 0,
    int lineLimit = 200,
  }) {
    final allLines = snapshot.unifiedDiff.isEmpty
        ? const <String>[]
        : snapshot.unifiedDiff.split('\n');
    final normalizedStart = startLine.clamp(0, allLines.length);
    final normalizedLimit = lineLimit <= 0 ? 200 : lineLimit;
    final endLine = (normalizedStart + normalizedLimit).clamp(
      normalizedStart,
      allLines.length,
    );
    return SourceControlDiffWindow(
      path: snapshot.path,
      startLine: normalizedStart,
      totalLineCount: allLines.length,
      lines: List<String>.unmodifiable(
        allLines.sublist(normalizedStart, endLine),
      ),
    );
  }

  final String path;
  final int startLine;
  final int totalLineCount;
  final List<String> lines;

  int get endLine => startLine + lines.length;
  bool get hasPrevious => startLine > 0;
  bool get hasNext => endLine < totalLineCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'startLine': startLine,
      'endLine': endLine,
      'lineCount': lines.length,
      'totalLineCount': totalLineCount,
      'hasPrevious': hasPrevious,
      'hasNext': hasNext,
      'lines': lines,
    };
  }
}

class SourceControlDiffWindowBinding {
  const SourceControlDiffWindowBinding({
    required this.snapshot,
    this.startLine = 0,
    this.lineLimit = 200,
  });

  final SourceControlDiffSnapshot snapshot;
  final int startLine;
  final int lineLimit;

  SourceControlDiffReviewSummary get reviewSummary => snapshot.reviewSummary;

  SourceControlDiffWindow get window {
    return snapshot.window(startLine: startLine, lineLimit: lineLimit);
  }

  String get visibleText {
    if (!snapshot.available) {
      return snapshot.message;
    }
    final currentWindow = window;
    if (currentWindow.lines.isEmpty) {
      return snapshot.message.isEmpty
          ? 'No diff content in the selected window.'
          : snapshot.message;
    }
    return currentWindow.lines.join('\n');
  }

  SourceControlDiffWindowBinding previousWindow() {
    final currentWindow = window;
    final normalizedLimit = lineLimit <= 0 ? 200 : lineLimit;
    final previousStart = (currentWindow.startLine - normalizedLimit)
        .clamp(0, currentWindow.totalLineCount)
        .toInt();
    return copyWith(startLine: previousStart);
  }

  SourceControlDiffWindowBinding nextWindow() {
    final currentWindow = window;
    if (!currentWindow.hasNext) {
      return this;
    }
    return copyWith(startLine: currentWindow.endLine);
  }

  SourceControlDiffWindowBinding copyWith({
    SourceControlDiffSnapshot? snapshot,
    int? startLine,
    int? lineLimit,
  }) {
    return SourceControlDiffWindowBinding(
      snapshot: snapshot ?? this.snapshot,
      startLine: startLine ?? this.startLine,
      lineLimit: lineLimit ?? this.lineLimit,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerKind': snapshot.providerKind.wireValue,
      'path': snapshot.path,
      'available': snapshot.available,
      'requestedStartLine': startLine,
      'requestedLineLimit': lineLimit,
      'reviewSummary': reviewSummary.toJson(),
      'window': window.toJson(),
    };
  }
}

class SourceControlDiffReviewSummary {
  const SourceControlDiffReviewSummary({
    required this.path,
    required this.available,
    required this.lineCount,
    required this.hunkCount,
    required this.additionCount,
    required this.deletionCount,
    required this.truncated,
  });

  final String path;
  final bool available;
  final int lineCount;
  final int hunkCount;
  final int additionCount;
  final int deletionCount;
  final bool truncated;

  bool get hasChanges => additionCount > 0 || deletionCount > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'available': available,
      'lineCount': lineCount,
      'hunkCount': hunkCount,
      'additionCount': additionCount,
      'deletionCount': deletionCount,
      'hasChanges': hasChanges,
      'truncated': truncated,
    };
  }
}

class SourceControlDiffConfirmationPlan {
  const SourceControlDiffConfirmationPlan({
    required this.kind,
    required this.path,
    required this.risk,
    required this.requiresConfirmation,
    required this.canRun,
    required this.summary,
    required this.reviewSummary,
    this.blockedReason = '',
  });

  factory SourceControlDiffConfirmationPlan.fromDiff({
    required SourceControlDiffSnapshot snapshot,
    required SourceControlActionKind kind,
  }) {
    final actionPlan = SourceControlActionPlan.fromRequest(
      SourceControlActionRequest(kind: kind, paths: <String>[snapshot.path]),
    );
    final reviewSummary = snapshot.reviewSummary;
    final blockedReason = !snapshot.available
        ? 'Source control diff confirmation requires an available diff preview.'
        : snapshot.empty
        ? 'Source control diff confirmation requires reviewed diff content.'
        : actionPlan.blockedReason;
    return SourceControlDiffConfirmationPlan(
      kind: kind,
      path: snapshot.path,
      risk: actionPlan.risk,
      requiresConfirmation: actionPlan.requiresConfirmation,
      canRun: blockedReason.isEmpty && actionPlan.canRun,
      blockedReason: blockedReason,
      reviewSummary: reviewSummary,
      summary:
          '${kind.wireValue} reviewed diff ${snapshot.path} · +${reviewSummary.additionCount} -${reviewSummary.deletionCount} · risk ${actionPlan.risk.wireValue}',
    );
  }

  final SourceControlActionKind kind;
  final String path;
  final SourceControlActionRisk risk;
  final bool requiresConfirmation;
  final bool canRun;
  final String summary;
  final String blockedReason;
  final SourceControlDiffReviewSummary reviewSummary;

  SourceControlActionRequest toActionRequest() {
    return SourceControlActionRequest(kind: kind, paths: <String>[path]);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'path': path,
      'risk': risk.wireValue,
      'requiresConfirmation': requiresConfirmation,
      'canRun': canRun,
      'summary': summary,
      'reviewSummary': reviewSummary.toJson(),
      if (blockedReason.isNotEmpty) 'blockedReason': blockedReason,
    };
  }
}

class SourceControlAgentContextSnapshot {
  const SourceControlAgentContextSnapshot({
    required this.workspaceRoot,
    this.status,
    this.diffReview,
    this.diffWindow,
    this.pendingActionPlan,
    this.lastActionResult,
  });

  factory SourceControlAgentContextSnapshot.fromState({
    required String workspaceRoot,
    SourceControlStatusSnapshot? status,
    SourceControlDiffSnapshot? diffPreview,
    SourceControlActionPlan? pendingActionPlan,
    SourceControlActionResult? lastActionResult,
    int diffLineLimit = 80,
  }) {
    return SourceControlAgentContextSnapshot(
      workspaceRoot: workspaceRoot,
      status: status,
      diffReview: diffPreview?.reviewSummary,
      diffWindow: diffPreview?.window(lineLimit: diffLineLimit),
      pendingActionPlan: pendingActionPlan,
      lastActionResult: lastActionResult,
    );
  }

  final String workspaceRoot;
  final SourceControlStatusSnapshot? status;
  final SourceControlDiffReviewSummary? diffReview;
  final SourceControlDiffWindow? diffWindow;
  final SourceControlActionPlan? pendingActionPlan;
  final SourceControlActionResult? lastActionResult;

  bool get loaded => status != null;
  bool get available => status?.available ?? false;
  bool get clean => status?.clean ?? true;
  bool get hasDiffPreview => diffReview != null;
  bool get requiresHumanConfirmation {
    return pendingActionPlan?.requiresConfirmation ?? false;
  }

  String get providerKind {
    return status?.providerKind.wireValue ?? 'unknown';
  }

  String get branchName {
    return status?.branchName ?? '';
  }

  String get message {
    return status?.message ?? 'Source control status has not been loaded.';
  }

  List<String> get stagedPaths {
    return _pathsWhere((change) => change.staged);
  }

  List<String> get unstagedPaths {
    return _pathsWhere((change) => change.unstaged);
  }

  List<String> get conflictedPaths {
    return _pathsWhere(
      (change) =>
          change.stagedStatus == SourceControlFileStatus.conflicted ||
          change.unstagedStatus == SourceControlFileStatus.conflicted,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceRoot': workspaceRoot,
      'providerKind': providerKind,
      'loaded': loaded,
      'available': available,
      'clean': clean,
      if (branchName.isNotEmpty) 'branchName': branchName,
      'message': message,
      'changeCount': status?.changes.length ?? 0,
      'stagedPaths': stagedPaths,
      'unstagedPaths': unstagedPaths,
      'conflictedPaths': conflictedPaths,
      'hasDiffPreview': hasDiffPreview,
      'requiresHumanConfirmation': requiresHumanConfirmation,
      if (diffReview != null) 'diffReview': diffReview!.toJson(),
      if (diffWindow != null) 'diffWindow': diffWindow!.toJson(),
      if (pendingActionPlan != null)
        'pendingActionPlan': pendingActionPlan!.toJson(),
      if (lastActionResult != null)
        'lastActionResult': lastActionResult!.toJson(),
    };
  }

  List<String> _pathsWhere(bool Function(SourceControlFileChange change) test) {
    final changes = status?.changes ?? const <SourceControlFileChange>[];
    return List<String>.unmodifiable(
      changes.where(test).map((change) => change.path),
    );
  }
}

class SourceControlCommandRequest {
  const SourceControlCommandRequest({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

class SourceControlCommandResult {
  const SourceControlCommandResult({
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

typedef SourceControlCommandRunner =
    Future<SourceControlCommandResult> Function(
      SourceControlCommandRequest request,
    );

class ProcessSourceControlCommandRunner {
  const ProcessSourceControlCommandRunner({
    required this.processManager,
    this.timeout = const Duration(seconds: 10),
  });

  final ProcessManager processManager;
  final Duration timeout;

  Future<SourceControlCommandResult> call(
    SourceControlCommandRequest request,
  ) async {
    final result = await processManager.run(
      ProcessCommandRequest(
        executablePath: request.executable,
        arguments: request.arguments,
        workingDirectory: request.workingDirectory,
        timeout: timeout,
      ),
    );
    return SourceControlCommandResult(
      exitCode: result.exitCode ?? _exitCodeForProcessStatus(result.status),
      stdout: result.stdout,
      stderr: result.stderr.isNotEmpty ? result.stderr : result.message ?? '',
    );
  }
}

int _exitCodeForProcessStatus(ProcessCommandStatus status) {
  return switch (status) {
    ProcessCommandStatus.succeeded => 0,
    ProcessCommandStatus.failed => 1,
    ProcessCommandStatus.timedOut => 124,
    ProcessCommandStatus.blocked => 126,
  };
}

abstract class SourceControlStatusProvider {
  const SourceControlStatusProvider();

  SourceControlProviderKind get providerKind;

  Future<SourceControlStatusSnapshot> status({required String workspaceRoot});
}

abstract class SourceControlDiffProvider {
  const SourceControlDiffProvider();

  SourceControlProviderKind get providerKind;

  Future<SourceControlDiffSnapshot> diff({
    required String workspaceRoot,
    required String path,
  });
}

abstract class SourceControlActionProvider {
  const SourceControlActionProvider();

  SourceControlProviderKind get providerKind;

  Future<SourceControlActionResult> runAction({
    required String workspaceRoot,
    required SourceControlActionRequest request,
  });
}

abstract class SourceControlBranchProvider {
  const SourceControlBranchProvider();

  SourceControlProviderKind get providerKind;

  Future<SourceControlBranchSnapshot> branches({required String workspaceRoot});
}

abstract class SourceControlBranchActionProvider {
  const SourceControlBranchActionProvider();

  SourceControlProviderKind get providerKind;

  Future<SourceControlBranchSwitchResult> switchBranch({
    required String workspaceRoot,
    required SourceControlBranchSwitchPlan plan,
  });
}

abstract class SourceControlHistoryProvider {
  const SourceControlHistoryProvider();

  SourceControlProviderKind get providerKind;

  Future<SourceControlHistorySnapshot> history({
    required String workspaceRoot,
    int limit = 25,
  });
}

class StaticSourceControlStatusProvider extends SourceControlStatusProvider {
  const StaticSourceControlStatusProvider(this.snapshot);

  final SourceControlStatusSnapshot snapshot;

  @override
  SourceControlProviderKind get providerKind => snapshot.providerKind;

  @override
  Future<SourceControlStatusSnapshot> status({
    required String workspaceRoot,
  }) async {
    return snapshot;
  }
}

class StaticSourceControlDiffProvider extends SourceControlDiffProvider {
  const StaticSourceControlDiffProvider(this.snapshot);

  final SourceControlDiffSnapshot snapshot;

  @override
  SourceControlProviderKind get providerKind => snapshot.providerKind;

  @override
  Future<SourceControlDiffSnapshot> diff({
    required String workspaceRoot,
    required String path,
  }) async {
    return snapshot;
  }
}

class GitPorcelainStatusProvider extends SourceControlStatusProvider {
  const GitPorcelainStatusProvider({
    required this.runner,
    this.parser = const GitPorcelainStatusParser(),
    this.executable = 'git',
  });

  final SourceControlCommandRunner runner;
  final GitPorcelainStatusParser parser;
  final String executable;

  static const List<String> statusArguments = <String>[
    'status',
    '--porcelain=v1',
    '--branch',
  ];

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlStatusSnapshot> status({
    required String workspaceRoot,
  }) async {
    try {
      final result = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: statusArguments,
          workingDirectory: workspaceRoot,
        ),
      );
      if (result.exitCode == 0) {
        return parser.parse(result.stdout);
      }
      return _unavailable(
        _failureMessage(
          result.exitCode,
          stderr: result.stderr,
          stdout: result.stdout,
        ),
      );
    } on Object catch (error) {
      return _unavailable('Git status unavailable: $error');
    }
  }

  SourceControlStatusSnapshot _unavailable(String message) {
    return SourceControlStatusSnapshot(
      providerKind: SourceControlProviderKind.git,
      available: false,
      changes: const <SourceControlFileChange>[],
      message: message,
    );
  }
}

class GitSourceControlDiffProvider extends SourceControlDiffProvider {
  const GitSourceControlDiffProvider({
    required this.runner,
    this.executable = 'git',
  });

  final SourceControlCommandRunner runner;
  final String executable;

  static List<String> diffArgumentsFor(String path) {
    return <String>['diff', '--', path];
  }

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlDiffSnapshot> diff({
    required String workspaceRoot,
    required String path,
  }) async {
    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      return _unavailable(normalizedPath, 'Git diff skipped: missing path.');
    }
    try {
      final result = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: diffArgumentsFor(normalizedPath),
          workingDirectory: workspaceRoot,
        ),
      );
      if (result.exitCode == 0) {
        return SourceControlDiffSnapshot(
          providerKind: SourceControlProviderKind.git,
          path: normalizedPath,
          unifiedDiff: result.stdout,
          message: result.stdout.trim().isEmpty
              ? 'No unstaged Git diff for $normalizedPath.'
              : 'Git diff for $normalizedPath.',
        );
      }
      return _unavailable(
        normalizedPath,
        _diffFailureMessage(
          result.exitCode,
          stderr: result.stderr,
          stdout: result.stdout,
        ),
      );
    } on Object catch (error) {
      return _unavailable(normalizedPath, 'Git diff unavailable: $error');
    }
  }

  SourceControlDiffSnapshot _unavailable(String path, String message) {
    return SourceControlDiffSnapshot(
      providerKind: SourceControlProviderKind.git,
      path: path,
      available: false,
      message: message,
    );
  }
}

class GitSourceControlActionProvider extends SourceControlActionProvider {
  const GitSourceControlActionProvider({
    required this.runner,
    this.executable = 'git',
  });

  final SourceControlCommandRunner runner;
  final String executable;

  static List<String> actionArgumentsFor(SourceControlActionRequest request) {
    final paths = request.paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    return switch (request.kind) {
      SourceControlActionKind.stage => <String>['add', '--', ...paths],
      SourceControlActionKind.unstage => <String>[
        'restore',
        '--staged',
        '--',
        ...paths,
      ],
      SourceControlActionKind.discard => <String>['restore', '--', ...paths],
      SourceControlActionKind.commit => <String>[
        'commit',
        '-m',
        request.message.trim(),
        if (paths.isNotEmpty) '--',
        ...paths,
      ],
    };
  }

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlActionResult> runAction({
    required String workspaceRoot,
    required SourceControlActionRequest request,
  }) async {
    final normalizedPaths = request.paths
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final validationMessage = _validateActionRequest(request, normalizedPaths);
    if (validationMessage.isNotEmpty) {
      return SourceControlActionResult(
        kind: request.kind,
        applied: false,
        paths: normalizedPaths,
        message: validationMessage,
      );
    }

    try {
      final result = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: actionArgumentsFor(
            SourceControlActionRequest(
              kind: request.kind,
              paths: normalizedPaths,
              message: request.message.trim(),
            ),
          ),
          workingDirectory: workspaceRoot,
        ),
      );
      final actionLabel = request.kind.wireValue;
      if (result.exitCode == 0) {
        return SourceControlActionResult(
          kind: request.kind,
          applied: true,
          paths: normalizedPaths,
          message: _commandSuccessMessage(
            'Git $actionLabel',
            stdout: result.stdout,
            stderr: result.stderr,
          ),
        );
      }
      return SourceControlActionResult(
        kind: request.kind,
        applied: false,
        paths: normalizedPaths,
        message: _commandFailureMessage(
          'Git $actionLabel',
          result.exitCode,
          stderr: result.stderr,
          stdout: result.stdout,
        ),
      );
    } on Object catch (error) {
      return SourceControlActionResult(
        kind: request.kind,
        applied: false,
        paths: normalizedPaths,
        message: 'Git ${request.kind.wireValue} unavailable: $error',
      );
    }
  }

  String _validateActionRequest(
    SourceControlActionRequest request,
    List<String> normalizedPaths,
  ) {
    return switch (request.kind) {
      SourceControlActionKind.stage ||
      SourceControlActionKind.unstage ||
      SourceControlActionKind.discard =>
        normalizedPaths.isEmpty
            ? 'Git ${request.kind.wireValue} skipped: no paths were provided.'
            : '',
      SourceControlActionKind.commit =>
        request.message.trim().isEmpty
            ? 'Git commit skipped: commit message is required.'
            : '',
    };
  }
}

class GitSourceControlBranchProvider extends SourceControlBranchProvider {
  const GitSourceControlBranchProvider({
    required this.runner,
    this.executable = 'git',
  });

  final SourceControlCommandRunner runner;
  final String executable;

  static const List<String> branchArguments = <String>[
    'branch',
    '--format=%(refname:short)',
  ];

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlBranchSnapshot> branches({
    required String workspaceRoot,
  }) async {
    try {
      final currentResult = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: const <String>['branch', '--show-current'],
          workingDirectory: workspaceRoot,
        ),
      );
      if (currentResult.exitCode != 0) {
        return _unavailable(
          _commandFailureMessage(
            'Git branch',
            currentResult.exitCode,
            stderr: currentResult.stderr,
            stdout: currentResult.stdout,
          ),
        );
      }
      final branchesResult = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: branchArguments,
          workingDirectory: workspaceRoot,
        ),
      );
      if (branchesResult.exitCode != 0) {
        return _unavailable(
          _commandFailureMessage(
            'Git branch list',
            branchesResult.exitCode,
            stderr: branchesResult.stderr,
            stdout: branchesResult.stdout,
          ),
        );
      }
      final branches = branchesResult.stdout
          .split('\n')
          .map((branch) => branch.trim())
          .where((branch) => branch.isNotEmpty)
          .toList(growable: false);
      return SourceControlBranchSnapshot(
        providerKind: SourceControlProviderKind.git,
        currentBranch: currentResult.stdout.trim(),
        branches: List<String>.unmodifiable(branches),
        message: 'Git branch list loaded.',
      );
    } on Object catch (error) {
      return _unavailable('Git branch unavailable: $error');
    }
  }

  SourceControlBranchSnapshot _unavailable(String message) {
    return SourceControlBranchSnapshot(
      providerKind: SourceControlProviderKind.git,
      available: false,
      message: message,
    );
  }
}

class GitSourceControlBranchActionProvider
    extends SourceControlBranchActionProvider {
  const GitSourceControlBranchActionProvider({
    required this.runner,
    this.executable = 'git',
  });

  final SourceControlCommandRunner runner;
  final String executable;

  static List<String> switchArgumentsFor(String branch) {
    return <String>['switch', branch.trim()];
  }

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlBranchSwitchResult> switchBranch({
    required String workspaceRoot,
    required SourceControlBranchSwitchPlan plan,
  }) async {
    if (!plan.canRun) {
      return SourceControlBranchSwitchResult(
        providerKind: SourceControlProviderKind.git,
        targetBranch: plan.targetBranch,
        applied: false,
        message: plan.blockedReason,
      );
    }
    try {
      final result = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: switchArgumentsFor(plan.targetBranch),
          workingDirectory: workspaceRoot,
        ),
      );
      if (result.exitCode == 0) {
        return SourceControlBranchSwitchResult(
          providerKind: SourceControlProviderKind.git,
          targetBranch: plan.targetBranch,
          applied: true,
          message: _commandSuccessMessage(
            'Git switch',
            stdout: result.stdout,
            stderr: result.stderr,
          ),
        );
      }
      return SourceControlBranchSwitchResult(
        providerKind: SourceControlProviderKind.git,
        targetBranch: plan.targetBranch,
        applied: false,
        message: _commandFailureMessage(
          'Git switch',
          result.exitCode,
          stderr: result.stderr,
          stdout: result.stdout,
        ),
      );
    } on Object catch (error) {
      return SourceControlBranchSwitchResult(
        providerKind: SourceControlProviderKind.git,
        targetBranch: plan.targetBranch,
        applied: false,
        message: 'Git switch unavailable: $error',
      );
    }
  }
}

class GitSourceControlHistoryProvider extends SourceControlHistoryProvider {
  const GitSourceControlHistoryProvider({
    required this.runner,
    this.executable = 'git',
  });

  final SourceControlCommandRunner runner;
  final String executable;

  static List<String> historyArgumentsFor(int limit) {
    final normalizedLimit = limit <= 0 ? 25 : limit;
    return <String>[
      'log',
      '--date=iso-strict',
      '-n',
      '$normalizedLimit',
      '--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s',
    ];
  }

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlHistorySnapshot> history({
    required String workspaceRoot,
    int limit = 25,
  }) async {
    try {
      final result = await runner(
        SourceControlCommandRequest(
          executable: executable,
          arguments: historyArgumentsFor(limit),
          workingDirectory: workspaceRoot,
        ),
      );
      if (result.exitCode != 0) {
        return _unavailable(
          _commandFailureMessage(
            'Git history',
            result.exitCode,
            stderr: result.stderr,
            stdout: result.stdout,
          ),
        );
      }
      final entries = const GitLogHistoryParser().parse(result.stdout);
      return SourceControlHistorySnapshot(
        providerKind: SourceControlProviderKind.git,
        entries: entries,
        message: entries.isEmpty
            ? 'Git history is empty.'
            : 'Git history loaded.',
      );
    } on Object catch (error) {
      return _unavailable('Git history unavailable: $error');
    }
  }

  SourceControlHistorySnapshot _unavailable(String message) {
    return SourceControlHistorySnapshot(
      providerKind: SourceControlProviderKind.git,
      available: false,
      message: message,
    );
  }
}

String _failureMessage(
  int exitCode, {
  required String stderr,
  required String stdout,
}) {
  return _commandFailureMessage(
    'Git status',
    exitCode,
    stderr: stderr,
    stdout: stdout,
  );
}

String _diffFailureMessage(
  int exitCode, {
  required String stderr,
  required String stdout,
}) {
  return _commandFailureMessage(
    'Git diff',
    exitCode,
    stderr: stderr,
    stdout: stdout,
  );
}

String _commandFailureMessage(
  String commandLabel,
  int exitCode, {
  required String stderr,
  required String stdout,
}) {
  final detail = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
  if (detail.isEmpty) {
    return '$commandLabel failed with exit code $exitCode.';
  }
  return '$commandLabel failed with exit code $exitCode: $detail';
}

String _commandSuccessMessage(
  String commandLabel, {
  required String stdout,
  required String stderr,
}) {
  final detail = stdout.trim().isNotEmpty ? stdout.trim() : stderr.trim();
  if (detail.isEmpty) {
    return '$commandLabel applied.';
  }
  return '$commandLabel applied: $detail';
}

String _branchSwitchBlockedReason({
  required SourceControlBranchSnapshot snapshot,
  required String targetBranch,
}) {
  if (!snapshot.available) {
    return snapshot.message.isEmpty
        ? 'Source control branches are unavailable.'
        : snapshot.message;
  }
  if (targetBranch.isEmpty) {
    return 'Source control branch switch requires a target branch.';
  }
  if (snapshot.currentBranch == targetBranch) {
    return 'Source control branch switch skipped: already on $targetBranch.';
  }
  if (snapshot.branches.isNotEmpty &&
      !snapshot.branches.contains(targetBranch)) {
    return 'Source control branch switch blocked: $targetBranch is not in the branch list.';
  }
  return '';
}

class GitPorcelainStatusParser {
  const GitPorcelainStatusParser();

  SourceControlStatusSnapshot parse(String output) {
    final changes = <SourceControlFileChange>[];
    var branchName = '';

    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('## ')) {
        branchName = _parseBranchName(line.substring(3));
        continue;
      }
      if (line.length < 3) {
        changes.add(
          SourceControlFileChange(
            path: line,
            stagedStatus: SourceControlFileStatus.unknown,
          ),
        );
        continue;
      }

      final stagedStatus = _statusFromPorcelainCode(line.codeUnitAt(0));
      final unstagedStatus = _statusFromPorcelainCode(line.codeUnitAt(1));
      final pathText = line.substring(3);
      final renameParts = _splitRenamePath(pathText);

      changes.add(
        SourceControlFileChange(
          path: renameParts.$2,
          originalPath: renameParts.$1,
          stagedStatus: stagedStatus,
          unstagedStatus: unstagedStatus,
        ),
      );
    }

    return SourceControlStatusSnapshot(
      providerKind: SourceControlProviderKind.git,
      branchName: branchName,
      changes: List<SourceControlFileChange>.unmodifiable(changes),
      message: changes.isEmpty ? 'Git workspace is clean.' : 'Git changes.',
    );
  }
}

class GitLogHistoryParser {
  const GitLogHistoryParser();

  List<SourceControlHistoryEntry> parse(String output) {
    final entries = <SourceControlHistoryEntry>[];
    for (final rawLine in output.split('\n')) {
      final line = rawLine.trimRight();
      if (line.isEmpty) {
        continue;
      }
      final parts = line.split('\x1f');
      if (parts.length < 5) {
        entries.add(
          SourceControlHistoryEntry(
            revision: parts.isEmpty ? line : parts.first,
            shortRevision: parts.length > 1 ? parts[1] : '',
            summary: parts.length > 4 ? parts.sublist(4).join(' ') : line,
          ),
        );
        continue;
      }
      entries.add(
        SourceControlHistoryEntry(
          revision: parts[0],
          shortRevision: parts[1],
          author: parts[2],
          authoredAt: parts[3],
          summary: parts.sublist(4).join('\x1f'),
        ),
      );
    }
    return List<SourceControlHistoryEntry>.unmodifiable(entries);
  }
}

String _parseBranchName(String value) {
  final aheadMarker = value.indexOf('...');
  if (aheadMarker >= 0) {
    return value.substring(0, aheadMarker).trim();
  }
  final spaceMarker = value.indexOf(' ');
  if (spaceMarker >= 0) {
    return value.substring(0, spaceMarker).trim();
  }
  return value.trim();
}

(String, String) _splitRenamePath(String pathText) {
  final separator = pathText.indexOf(' -> ');
  if (separator < 0) {
    return ('', pathText.trim());
  }
  return (
    pathText.substring(0, separator).trim(),
    pathText.substring(separator + 4).trim(),
  );
}

SourceControlFileStatus? _statusFromPorcelainCode(int codeUnit) {
  return switch (codeUnit) {
    32 => null,
    33 => SourceControlFileStatus.ignored,
    63 => SourceControlFileStatus.untracked,
    65 => SourceControlFileStatus.added,
    67 => SourceControlFileStatus.copied,
    68 => SourceControlFileStatus.deleted,
    77 => SourceControlFileStatus.modified,
    82 => SourceControlFileStatus.renamed,
    85 => SourceControlFileStatus.conflicted,
    _ => SourceControlFileStatus.unknown,
  };
}
